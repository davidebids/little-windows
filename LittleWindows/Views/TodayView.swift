import SwiftData
import SwiftUI
import UIKit

struct EventEditorRoute: Identifiable {
    let id = UUID()
    var type: EventType
    var event: BabyEvent?
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query private var allEvents: [BabyEvent]
    @Query(sort: \DoctorAppointment.startDate) private var appointments: [DoctorAppointment]
    @Query private var records: [SleepPredictionRecord]
    @Query(sort: \AgeGuideReadState.updatedAt) private var ageGuideReadStates: [AgeGuideReadState]
    @Query(sort: \PuppyStageGuideReadState.updatedAt) private var puppyStageGuideReadStates: [PuppyStageGuideReadState]

    @AppStorage("caregiverOne") private var caregiverOne = "Caregiver 1"
    @AppStorage("currentCaregiverName") private var currentCaregiverName = ""
    @AppStorage("feedAdjustmentEnabled") private var feedAdjustmentEnabled = true
    @AppStorage("nursingAdjustmentEnabled") private var nursingAdjustmentEnabled = true
    @AppStorage("bedtimePredictionEnabled") private var bedtimePredictionEnabled = true
    @AppStorage("predictionNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 10
    @AppStorage("customWakeMinimum") private var customWakeMinimum = 0.0
    @AppStorage("customWakeMaximum") private var customWakeMaximum = 0.0

    @State private var editorRoute: EventEditorRoute?
    @State private var activeTimerToEdit: BabyEvent?
    @State private var showingExplanation = false
    @State private var showingBackwardsPlanner = false
    @State private var duplicateTimerMessage: String?
    @State private var showingAlertPermissionPrompt = false
    @State private var showingPermissionDenied = false
    @State private var showingSleepChooser = false
    @State private var showingNursingChooser = false
    @State private var showingActivityChooser = false
    @State private var showingAppointments = false
    @State private var appointmentToOpen: DoctorAppointment?
    @State private var selectedMilestoneTemplate: MilestoneTemplate?
    @State private var puppyGuideToOpen: PuppyStageGuide?
    @State private var puppyGuideProfileToOpen: BabyProfile?
    @State private var showingProfileEditor = false
    @State private var eventPendingDelete: BabyEvent?
    @State private var showingDeleteEventConfirmation = false
    @State private var activeSleepPlan: ActiveSleepPlan?
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var profileService = ProfileService.shared

    init() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let recentCutoff = calendar.date(byAdding: .day, value: -45, to: todayStart) ?? todayStart

        var eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { event in
                event.startDate >= recentCutoff
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        _allEvents = Query(eventDescriptor)

        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.actualSleepEventID == nil || record.generatedAt >= recentCutoff
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        _records = Query(recordDescriptor)
    }
    private var profile: BabyProfile? {
        profileService.selectedProfile(in: profiles)
    }
    private var selectedProfileID: UUID? { profile?.id }
    private var scopedEvents: [BabyEvent] {
        allEvents.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var scopedRecords: [SleepPredictionRecord] {
        records.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var scopedAppointments: [DoctorAppointment] {
        appointments.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var scopedAgeGuideReadStates: [AgeGuideReadState] {
        ageGuideReadStates.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var scopedPuppyGuideReadStates: [PuppyStageGuideReadState] {
        puppyStageGuideReadStates.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var currentAgeGuide: AgeGuide? {
        profile.flatMap { AgeGuideService.shared.currentAgeGuide(for: $0) }
    }
    private var shouldShowAgeGuideCard: Bool {
        guard let profile, let guide = currentAgeGuide else { return false }
        let state = scopedAgeGuideReadStates.first { $0.guideID == guide.id }
        return AgeGuideService.shared.shouldShowMonthlyCard(
            profile: profile,
            readState: state
        )
    }
    private var currentPuppyGuide: PuppyStageGuide? {
        profile.flatMap { PuppyStageGuideService.shared.currentGuide(for: $0) }
    }
    private var shouldShowPuppyGuideCard: Bool {
        guard let profile, let guide = currentPuppyGuide else { return false }
        let state = scopedPuppyGuideReadStates.first { $0.guideID == guide.id }
        return PuppyStageGuideService.shared.shouldShowStageCard(
            profile: profile,
            readState: state
        )
    }
    private var todayEvents: [BabyEvent] {
        scopedEvents.filter {
            !$0.isTimerDraft && Calendar.current.isDateInToday($0.startDate)
        }
    }
    private var activeEvents: [BabyEvent] {
        scopedEvents.filter(\.isTimerDraft).sorted { $0.startDate < $1.startDate }
    }
    private var prediction: SleepPrediction? {
        PredictionTuningService.currentPrediction(
            profile: profile,
            events: scopedEvents,
            records: scopedRecords,
            settings: predictionSettings
        )
    }
    private var isDogProfile: Bool { profile?.profileType == .dog }
    private var activeCaregiverName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: caregiverOne
        )
    }
    private var relevantAppointments: [DoctorAppointment] {
        let now = Date()
        let soon = now.addingTimeInterval(3 * 24 * 60 * 60)
        return scopedAppointments
            .filter { !$0.isCompleted && $0.startDate >= Calendar.current.startOfDay(for: now) && $0.startDate <= soon }
            .sorted { $0.startDate < $1.startDate }
    }
    private var predictionSettings: PredictionSettings {
        PredictionSettings(
            feedAdjustmentEnabled: feedAdjustmentEnabled,
            nursingAdjustmentEnabled: nursingAdjustmentEnabled,
            bedtimePredictionEnabled: bedtimePredictionEnabled,
            customBaselineMinimum: customWakeMinimum > 0 ? customWakeMinimum : nil,
            customBaselineMaximum: customWakeMaximum > 0 ? customWakeMaximum : nil
        )
    }
    private var runningSleepTimer: BabyEvent? {
        activeEvents.first {
            $0.type == .sleep && $0.isTimerRunning
        }
    }
    private var awakeSinceDate: Date? {
        guard runningSleepTimer == nil else { return nil }
        let now = Date()
        let completedSleepEnd = scopedEvents
            .filter { $0.type == .sleep && !$0.isTimerDraft }
            .compactMap(\.endDate)
            .filter { $0 <= now }
            .max()
        let stoppedDraftSleepEnd = activeEvents
            .filter { $0.type == .sleep && !$0.isTimerRunning }
            .map(\.updatedAt)
            .filter { $0 <= now }
            .max()
        return [completedSleepEnd, stoppedDraftSleepEnd]
            .compactMap { $0 }
            .max()
    }

    var body: some View {
        let todayEvents = todayEvents
        let activeEvents = activeEvents
        let prediction = prediction

        List {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Good \(greeting), \(activeCaregiverName)")
                            .font(.title2.bold())
                        if let profile {
                            Text(profile.profileType == .dog
                                ? "\(profile.name) · \(profile.profileSubtitle)"
                                : "\(profile.name) is \(DateFormatting.age(from: profile.birthDate))"
                            )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let profile {
                        VStack(spacing: 3) {
                            Text("\(todayEvents.count)")
                                .font(.title3.bold())
                                .monospacedDigit()
                            Text("logs today")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("\(todayEvents.count) logs today for \(profile.name)")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }

            if profile == nil {
                noProfileSection
            } else {
                activeTimersSection(activeEvents)

                if isDogProfile {
                    dogTodaySummarySection
                    puppyStageGuideSection
                } else {
                    monthlyAgeGuideSection
                }

                appointmentsSection

                if !isDogProfile {
                    Section {
                        PredictionCard(
                            prediction: prediction,
                            babyName: profile?.name ?? "Baby",
                            awakeSinceDate: awakeSinceDate,
                            alertStatusText: notificationManager.statusText(
                                prediction: prediction,
                                settings: .current,
                                isSleeping: activeEvents.contains {
                                    $0.type == .sleep && $0.isTimerRunning
                                }
                            ),
                            alertsEnabled: notificationsEnabled,
                            toggleAlerts: toggleLittleWindowAlerts,
                            showBackwardsPlanner: { showingBackwardsPlanner = true },
                            showExplanation: { showingExplanation = true }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                if isDogProfile {
                    dogQuickActionsSection
                } else {
                    childQuickActionsSection
                }

                Section {
                    if todayEvents.isEmpty {
                        ContentUnavailableView(
                            "No events yet",
                            systemImage: "clock",
                            description: Text("Use a quick action to start \(profile?.name ?? "the profile")'s day.")
                        )
                    } else {
                        ForEach(todayEvents) { event in
                            Button {
                                if event.isTimerDraft {
                                    activeTimerToEdit = event
                                } else {
                                    editorRoute = EventEditorRoute(type: event.type, event: event)
                                }
                            } label: {
                                EventRow(event: event)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    eventPendingDelete = event
                                    showingDeleteEventConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    AppSectionHeader(
                        title: "Today's timeline",
                        subtitle: todayEvents.isEmpty ? nil : "\(todayEvents.count) events"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    deepLinkRouter.presentSettings()
                } label: {
                    if let profile {
                        ProfileAvatarView(profile: profile, size: 32)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(profile?.name ?? "Profile") settings")
                .accessibilityHint("Opens settings where you can switch profiles")
            }
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                EventEditorView(type: route.type, event: route.event) { savedEvent in
                    Task { await eventChanged(savedEvent) }
                }
            }
        }
        .sheet(item: $activeTimerToEdit) { event in
            NavigationStack {
                activeTimerEditor(for: event)
            }
        }
        .sheet(isPresented: $showingAppointments) {
            NavigationStack {
                AppointmentsListView()
            }
        }
        .sheet(item: $appointmentToOpen) { appointment in
            NavigationStack {
                AppointmentDetailView(appointment: appointment)
            }
        }
        .sheet(item: $selectedMilestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template)
            }
        }
        .sheet(item: $puppyGuideToOpen) { guide in
            NavigationStack {
                PuppyStageGuideDetailView(guide: guide, profile: puppyGuideProfileToOpen ?? profile)
            }
        }
        .sheet(isPresented: $showingProfileEditor) {
            NavigationStack {
                ProfileEditorView()
            }
        }
        .sheet(isPresented: $showingExplanation) {
            NavigationStack {
                PredictionExplanationView(prediction: prediction)
            }
        }
        .sheet(isPresented: $showingBackwardsPlanner) {
            if let profile {
                NavigationStack {
                    BackwardsSleepPlanView(
                        profile: profile,
                        events: scopedEvents,
                        settings: predictionSettings,
                        activePlan: activeSleepPlan,
                        activatePlan: activateSleepPlan,
                        deactivatePlan: deactivateSleepPlan
                    )
                }
            }
        }
        .confirmationDialog(
            "Delete event?",
            isPresented: $showingDeleteEventConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                if let eventPendingDelete {
                    delete(eventPendingDelete)
                }
                eventPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                eventPendingDelete = nil
            }
        } message: {
            Text("This permanently removes the event from the timeline.")
        }
        .modifier(
            SleepKindChooser(
                isPresented: $showingSleepChooser,
                startSleep: { kind in
                    startTimer(.sleep, sleepKind: kind)
                }
            )
        )
        .alert(
            "Timer already running",
            isPresented: Binding(
                get: { duplicateTimerMessage != nil },
                set: { if !$0 { duplicateTimerMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateTimerMessage ?? "")
        }
        .appActionSheet(
            isPresented: $showingNursingChooser,
            title: "Start Nursing",
            message: "Choose the starting side. You can switch sides while the timer runs.",
            systemImage: "figure.and.child.holdinghands",
            tint: .pink,
            options: [
                AppActionSheetOption(
                    title: "Left Side",
                    subtitle: "Begin tracking time on the left side.",
                    systemImage: "l.circle.fill",
                    tint: .pink
                ) {
                    startNursing(.left)
                },
                AppActionSheetOption(
                    title: "Right Side",
                    subtitle: "Begin tracking time on the right side.",
                    systemImage: "r.circle.fill",
                    tint: .pink
                ) {
                    startNursing(.right)
                }
            ]
        )
        .appActionSheet(
            isPresented: $showingActivityChooser,
            title: "Start Activity",
            message: "Pick a common activity timer or open a custom activity entry.",
            systemImage: "figure.play",
            tint: .green,
            options: activityOptions
        )
        .confirmationDialog(
            "Turn on Little Window Alerts?",
            isPresented: $showingAlertPermissionPrompt,
            titleVisibility: .visible
        ) {
            Button("Allow Notifications") {
                Task { await enableLittleWindowAlerts() }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Little Windows can remind you before \(profile?.name ?? "your baby")'s next likely nap or bedtime window.")
        }
        .alert("Notifications are turned off", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can allow Little Window Alerts in iOS Settings whenever you're ready.")
        }
        .onChange(of: deepLinkRouter.pendingAction) { _, _ in
            handlePendingDeepLink()
        }
        .onChange(of: deepLinkRouter.pendingProfileID) { _, _ in
            handlePendingProfileSwitch()
            refreshActiveSleepPlan()
        }
        .onChange(of: deepLinkRouter.pendingAppointmentCommand) { _, _ in
            handlePendingAppointmentDeepLink()
        }
        .onChange(of: deepLinkRouter.pendingPuppyGuideCommand) { _, _ in
            handlePendingPuppyGuideDeepLink()
        }
        .onChange(of: deepLinkRouter.isDataReady) { _, ready in
            if ready {
                handlePendingProfileSwitch()
                handlePendingDeepLink()
                handlePendingAppointmentDeepLink()
                handlePendingPuppyGuideDeepLink()
            }
        }
        .task {
            await notificationManager.configure()
            _ = profileService.ensureSelection(in: profiles)
            refreshActiveSleepPlan()
            handlePendingProfileSwitch()
            handlePendingDeepLink()
            handlePendingAppointmentDeepLink()
            handlePendingPuppyGuideDeepLink()
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        default: "evening"
        }
    }

    private var noProfileSection: some View {
        Section {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("Create a profile")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)

                    Text("Add a child or dog profile to start logging care, or import an existing backup from Settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingProfileEditor = true
                } label: {
                    Label("Add Profile", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var monthlyAgeGuideSection: some View {
        if shouldShowAgeGuideCard, let profile, let guide = currentAgeGuide {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    AgeGuideFeatureCard(
                        guide: guide,
                        babyName: profile.name,
                        isCurrent: true,
                        isUnread: !scopedAgeGuideReadStates.contains {
                            $0.guideID == guide.id && $0.firstOpenedAt != nil
                        },
                        reachedDate: AgeGuideService.shared.monthlyBirthdayDate(
                            for: profile,
                            ageMonth: guide.ageMonth
                        ),
                        onDismiss: {
                            AgeGuideService.shared.markMonthlyCardDismissed(
                                guide,
                                in: modelContext,
                                readStates: scopedAgeGuideReadStates,
                                profileID: selectedProfileID
                            )
                        },
                        onAddMilestone: {
                            selectedMilestoneTemplate = guide.milestonePrompts.first?.milestoneTemplate
                        }
                    )
                    NavigationLink {
                        AgeGuideDetailView(guide: guide)
                    } label: {
                        Label("Read development guide", systemImage: "book.pages.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MilestonePalette.accent)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "This Month", subtitle: guide.ageLabel)
            }
        }
    }

    @ViewBuilder
    private var puppyStageGuideSection: some View {
        if shouldShowPuppyGuideCard, let profile, let guide = currentPuppyGuide {
            Section {
                PuppyStageGuideCard(
                    profile: profile,
                    guide: guide,
                    onDismiss: {
                        PuppyStageGuideService.shared.markStageCardDismissed(
                            guide,
                            in: modelContext,
                            readStates: scopedPuppyGuideReadStates,
                            profileID: selectedProfileID
                        )
                    },
                    onRead: {
                        puppyGuideToOpen = guide
                    },
                    onAddMilestone: {
                        selectedMilestoneTemplate = guide.milestonePrompts.first.map {
                            MilestoneTemplate(title: $0.title, category: $0.suggestedCategory)
                        }
                    },
                    onLogTraining: {
                        startTimer(.training)
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "Puppy Stage Guides", subtitle: guide.title)
            }
        }
    }

    private var childQuickActionsSection: some View {
        Section {
            VStack(spacing: 14) {
                Button {
                    showingSleepChooser = true
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "moon.stars.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start sleep")
                                .font(.headline)
                            Text("Choose nap or night sleep")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [.indigo, Color(red: 0.43, green: 0.34, blue: 0.84)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 19)
                    )
                }
                .buttonStyle(.plain)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 14
                ) {
                    QuickActionButton(title: "Feed", icon: "waterbottle.fill", color: .orange) {
                        editorRoute = EventEditorRoute(type: .feed)
                    }
                    QuickActionButton(
                        title: "Nursing",
                        icon: "figure.and.child.holdinghands",
                        color: .pink
                    ) {
                        showingNursingChooser = true
                    }
                    QuickActionButton(title: "Diaper", icon: "drop.fill", color: .teal) {
                        editorRoute = EventEditorRoute(type: .diaper)
                    }
                    QuickActionButton(title: "Activity", icon: "figure.play", color: .green) {
                        showingActivityChooser = true
                    }
                    QuickActionButton(title: "Medicine", icon: "cross.case.fill", color: .red) {
                        editorRoute = EventEditorRoute(type: .medicine)
                    }
                    QuickActionButton(title: "Temperature", icon: "thermometer.medium", color: .red) {
                        editorRoute = EventEditorRoute(type: .temperature)
                    }
                    QuickActionButton(title: "Growth", icon: "ruler.fill", color: .mint) {
                        editorRoute = EventEditorRoute(type: .growth)
                    }
                    QuickActionButton(title: "Visits", icon: "stethoscope", color: .indigo) {
                        showingAppointments = true
                    }
                    QuickActionButton(title: "Custom", icon: "sparkles", color: .purple) {
                        editorRoute = EventEditorRoute(type: .custom)
                    }
                }
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Log something")
        } footer: {
            Text("Choose the sleep or activity kind, or use another action to log quickly.")
                .font(.caption)
        }
    }

    private var dogQuickActionsSection: some View {
        Section {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 14
            ) {
                QuickActionButton(title: "Food", icon: "fork.knife", color: .orange) {
                    editorRoute = EventEditorRoute(type: .food)
                }
                QuickActionButton(title: "Water", icon: "drop.fill", color: .cyan) {
                    editorRoute = EventEditorRoute(type: .water)
                }
                QuickActionButton(title: "Treat", icon: "birthday.cake.fill", color: .brown) {
                    editorRoute = EventEditorRoute(type: .treat)
                }
                QuickActionButton(title: "Start Walk", icon: "figure.walk", color: .green) {
                    startTimer(.walk)
                }
                QuickActionButton(title: "Pee", icon: "pawprint.fill", color: .teal) {
                    logDogPotty(.pee, accident: false)
                }
                QuickActionButton(title: "Poop", icon: "pawprint.circle.fill", color: .teal) {
                    logDogPotty(.poop, accident: false)
                }
                QuickActionButton(title: "Accident", icon: "exclamationmark.triangle.fill", color: .orange) {
                    logDogPotty(.pee, accident: true)
                }
                QuickActionButton(title: "Rest", icon: "bed.double.fill", color: .indigo) {
                    startTimer(.rest)
                }
                QuickActionButton(title: "Training", icon: "graduationcap.fill", color: .purple) {
                    startTimer(.training)
                }
                QuickActionButton(title: "Medicine", icon: "cross.case.fill", color: .red) {
                    editorRoute = EventEditorRoute(type: .medicine)
                }
                QuickActionButton(title: "Symptom", icon: "exclamationmark.triangle.fill", color: .red) {
                    editorRoute = EventEditorRoute(type: .symptom)
                }
                QuickActionButton(title: "Grooming", icon: "comb.fill", color: .pink) {
                    editorRoute = EventEditorRoute(type: .grooming)
                }
                QuickActionButton(title: "Teeth", icon: "mouth.fill", color: .mint) {
                    logDogGrooming(.teethBrushing)
                }
                QuickActionButton(title: "Weight", icon: "scalemass.fill", color: .mint) {
                    editorRoute = EventEditorRoute(type: .growth)
                }
                QuickActionButton(title: "Temp", icon: "thermometer.medium", color: .red) {
                    editorRoute = EventEditorRoute(type: .temperature)
                }
                QuickActionButton(title: "Vaccine", icon: "syringe.fill", color: .mint) {
                    editorRoute = EventEditorRoute(type: .vaccine)
                }
                QuickActionButton(title: "Vet Visit", icon: "stethoscope", color: .indigo) {
                    showingAppointments = true
                }
                QuickActionButton(title: "Custom", icon: "sparkles", color: .purple) {
                    editorRoute = EventEditorRoute(type: .custom)
                }
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Dog care")
        } footer: {
            Text("Walk, training, and rest timers use the same Live Activity and widget controls. No GPS route tracking or location permission is used.")
                .font(.caption)
        }
    }

    private var dogTodaySummarySection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                DogSummaryCard(title: "Last food", value: lastEventTitle(.food), icon: "fork.knife", color: .orange)
                DogSummaryCard(title: "Last water", value: lastEventTitle(.water), icon: "drop.fill", color: .cyan)
                DogSummaryCard(title: "Last pee", value: lastDogPottyTitle(.pee), icon: "pawprint.fill", color: .teal)
                DogSummaryCard(title: "Last poop", value: lastDogPottyTitle(.poop), icon: "pawprint.circle.fill", color: .teal)
                DogSummaryCard(title: "Last walk", value: lastEventTitle(.walk), icon: "figure.walk", color: .green)
                DogSummaryCard(title: "Medicine", value: lastEventTitle(.medicine), icon: "cross.case.fill", color: .red)
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "\(profile?.name ?? "Dog") today", subtitle: "Quick snapshot")
        }
    }

    @ViewBuilder
    private func activeTimersSection(_ events: [BabyEvent]) -> some View {
        if !events.isEmpty {
            Section {
                ForEach(events) { event in
                    activeTimerCard(for: event)
                }
            } header: {
                AppSectionHeader(
                    title: "Timers",
                    subtitle: "\(events.count) draft\(events.count == 1 ? "" : "s")"
                )
            }
        }
    }

    @ViewBuilder
    private var appointmentsSection: some View {
        if !relevantAppointments.isEmpty {
            Section {
                ForEach(relevantAppointments.prefix(2)) { appointment in
                    Button {
                        appointmentToOpen = appointment
                    } label: {
                        AppointmentCard(appointment: appointment)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        Button {
                            markCompleted(appointment)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Appointments")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        showingAppointments = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("View all")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all appointments")
                }
                .textCase(nil)
                .padding(.horizontal, 4)
            }
        }
    }

    private func activeTimerCard(for event: BabyEvent) -> some View {
        ActiveTimerCard(
            event: event,
            planWakeAlert: wakeAlert(for: event),
            edit: { activeTimerToEdit = event },
            toggleRunning: {
                event.isTimerRunning ? stop(event) : resume(event)
            },
            save: { save(event) },
            switchNursingSide: nursingSideSwitcher(for: event),
            setNursingSide: nursingSideSetter(for: event)
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func activeTimerEditor(for event: BabyEvent) -> some View {
        ActiveTimerEditorView(
            event: event,
            adjustStart: { date in adjustStart(of: event, to: date) },
            stop: { stop(event) },
            resume: { resume(event) },
            reset: { reset(event) },
            save: { endDate in save(event, endDate: endDate) },
            discard: { delete(event) },
            switchNursingSide: nursingSideSwitcher(for: event),
            setNursingSide: nursingSideSetter(for: event)
        )
    }

    private func nursingSideSwitcher(for event: BabyEvent) -> (() -> Void)? {
        guard event.type == .nursing else { return nil }
        return { switchNursingSide(event) }
    }

    private func nursingSideSetter(for event: BabyEvent) -> ((NursingSide) -> Void)? {
        guard event.type == .nursing else { return nil }
        return { side in setNursingSide(side, for: event) }
    }

    @discardableResult
    private func startTimer(
        _ type: EventType,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        activityType: ActivityType? = nil
    ) -> BabyEvent? {
        let created = EventMutationService.startTimer(
            type: type,
            nursingSide: nursingSide,
            sleepKind: sleepKind,
            activityType: activityType,
            caregiverName: activeCaregiverName,
            events: scopedEvents,
            profileID: selectedProfileID,
            profileType: profile?.profileType,
            context: modelContext
        )
        if let created {
            Task {
                await eventChanged(
                    created,
                    refreshPrediction: false,
                    waitForSystemIntegrations: true
                )
                await syncActiveSleepPlanWakeAlert(
                    for: created.type == .sleep ? created : nil
                )
            }
            return created
        } else {
            duplicateTimerMessage = "A \(type.displayName.lowercased()) timer is already running."
            return nil
        }
    }

    private func logDogPotty(_ pottyType: DogPottyType, accident: Bool) {
        var details = DogEventDetails()
        details.pottyType = pottyType
        details.pottyLocation = accident ? .indoorAccident : .outside
        details.accident = accident
        let now = Date()
        let event = BabyEvent(
            profileID: selectedProfileID,
            type: .potty,
            startDate: now,
            endDate: now,
            caregiverName: activeCaregiverName
        )
        event.profileTypeSnapshot = .dog
        event.dogDetails = details
        modelContext.insert(event)
        Task {
            await eventChanged(event, refreshPrediction: false, waitForSystemIntegrations: true)
        }
    }

    private func logDogGrooming(_ groomingType: DogGroomingType) {
        var details = DogEventDetails()
        details.groomingType = groomingType
        let now = Date()
        let event = BabyEvent(
            profileID: selectedProfileID,
            type: .grooming,
            startDate: now,
            endDate: now,
            caregiverName: activeCaregiverName
        )
        event.profileTypeSnapshot = .dog
        event.dogDetails = details
        modelContext.insert(event)
        Task {
            await eventChanged(event, refreshPrediction: false, waitForSystemIntegrations: true)
        }
    }

    private func lastEventTitle(_ type: EventType) -> String {
        scopedEvents
            .filter { $0.type == type && !$0.isTimerDraft }
            .max { $0.startDate < $1.startDate }?
            .displayTitle ?? "Not logged"
    }

    private func lastDogPottyTitle(_ pottyType: DogPottyType) -> String {
        scopedEvents
            .filter {
                $0.type == .potty
                    && !$0.isTimerDraft
                    && ($0.dogDetails.pottyType == pottyType || $0.dogDetails.pottyType == .both)
            }
            .max { $0.startDate < $1.startDate }?
            .displayTitle ?? "Not logged"
    }

    private func startNursing(_ side: NursingSide) {
        if let event = startTimer(.nursing, nursingSide: side) {
            activeTimerToEdit = event
        }
    }

    private func stop(_ event: BabyEvent) {
        EventMutationService.stopTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private func resume(_ event: BabyEvent) {
        EventMutationService.resumeTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func reset(_ event: BabyEvent) {
        EventMutationService.resetTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func save(_ event: BabyEvent, endDate: Date? = nil) {
        EventMutationService.saveTimer(event, context: modelContext, endDate: endDate)
        Task {
            await eventChanged(
                event,
                refreshPrediction: true,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private func switchNursingSide(_ event: BabyEvent) {
        EventTimerService.switchNursingSide(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func setNursingSide(_ side: NursingSide, for event: BabyEvent) {
        EventTimerService.setNursingSide(event, to: side, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
        }
    }

    private func markCompleted(_ appointment: DoctorAppointment) {
        appointment.isCompleted = true
        appointment.updatedAt = Date()
        try? modelContext.save()
        Task {
            await notificationManager.cancelAppointmentReminders(
                appointmentID: appointment.id
            )
        }
    }

    private func handlePendingDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard let action = deepLinkRouter.consumeAction() else { return }
        switch action {
        case .showActiveTimer:
            activeTimerToEdit = EventTimerService.primaryActiveEvent(in: scopedEvents)
        case .showEvent(let id):
            if let event = scopedEvents.first(where: { $0.id == id }) {
                if event.isTimerDraft {
                    activeTimerToEdit = event
                } else {
                    editorRoute = EventEditorRoute(type: event.type, event: event)
                }
            }
        case .stopActiveTimer:
            if let event = EventTimerService.primaryActiveEvent(in: scopedEvents) {
                stop(event)
            }
        case .stopTimer(let id):
            if let event = scopedEvents.first(where: { $0.id == id && $0.isTimerRunning }) {
                stop(event)
            }
        case .resumeTimer(let id):
            if let event = scopedEvents.first(where: {
                $0.id == id && $0.isTimerDraft && !$0.isTimerRunning
            }) {
                resume(event)
            }
        case .switchNursingSide(let id):
            if let event = scopedEvents.first(where: { $0.id == id }) {
                switchNursingSide(event)
            }
        case .startTimer(let type, let side):
            if type == .sleep {
                showingSleepChooser = true
            } else {
                startTimer(type, nursingSide: side)
            }
        case .startActivity(let activity):
            startTimer(.activity, activityType: activity)
        case .logDiaper:
            editorRoute = EventEditorRoute(type: .diaper)
        case .logEvent(let type):
            editorRoute = EventEditorRoute(type: type)
        }
    }

    private func handlePendingProfileSwitch() {
        guard let id = deepLinkRouter.pendingProfileID else { return }
        profileService.switchProfile(id: id, profiles: profiles)
        deepLinkRouter.pendingProfileID = nil
        refreshActiveSleepPlan()
    }

    private func handlePendingAppointmentDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard let command = deepLinkRouter.consumeAppointmentCommand() else { return }
        switch command {
        case .list:
            showingAppointments = true
        case .detail(let id), .notes(let id):
            appointmentToOpen = scopedAppointments.first { $0.id == id }
        }
    }

    private func handlePendingPuppyGuideDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard deepLinkRouter.consumePuppyGuideCommand() != nil else { return }
        guard let targetProfile = dogProfileForPuppyGuide(),
              let guide = PuppyStageGuideService.shared.currentGuide(for: targetProfile) else {
            return
        }
        if profile?.id != targetProfile.id {
            profileService.switchProfile(targetProfile)
        }
        puppyGuideProfileToOpen = targetProfile
        puppyGuideToOpen = guide
    }

    private func dogProfileForPuppyGuide() -> BabyProfile? {
        if let profile, profile.profileType == .dog {
            return profile
        }
        return profiles.first { $0.profileType == .dog && !$0.isArchived }
    }

    private func eventChanged(
        _ event: BabyEvent,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false
    ) async {
        event.profileID = event.profileID ?? selectedProfileID
        let currentEvents = scopedEvents.contains(where: { $0.id == event.id })
            ? scopedEvents
            : scopedEvents + [event]
        await EventMutationService.eventDidChange(
            event,
            profile: profile,
            events: currentEvents,
            records: scopedRecords,
            context: modelContext,
            settings: predictionSettings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes,
            refreshPrediction: refreshPrediction,
            waitForSystemIntegrations: waitForSystemIntegrations
        )
    }

    private func adjustStart(of event: BabyEvent, to date: Date) {
        EventTimerService.adjustStartDate(event, to: date)
    }

    private func delete(_ event: BabyEvent) {
        Task {
            await EventMutationService.delete(
                event,
                profile: profile,
                events: scopedEvents,
                records: scopedRecords,
                context: modelContext,
                settings: predictionSettings,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes
            )
        }
    }

    private func toggleLittleWindowAlerts() {
        if notificationsEnabled {
            notificationsEnabled = false
            Task {
                await notificationManager.cancelPendingLittleWindowAlerts()
            }
        } else {
            showingAlertPermissionPrompt = true
        }
    }

    private func refreshActiveSleepPlan() {
        activeSleepPlan = ActiveSleepPlanService.activePlan(
            for: selectedProfileID
        )
    }

    private func activateSleepPlan(_ plan: BackwardsSleepPlan) {
        guard let profileID = selectedProfileID else { return }
        activeSleepPlan = ActiveSleepPlanService.activate(
            plan: plan,
            profileID: profileID
        )
        Task {
            await ensureNotificationPermissionForPlan()
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private func deactivateSleepPlan() {
        ActiveSleepPlanService.clear(profileID: selectedProfileID)
        activeSleepPlan = nil
        Task {
            await notificationManager.cancelActiveSleepPlanWakeAlert(
                profileID: selectedProfileID
            )
        }
    }

    private func wakeAlert(for event: BabyEvent?) -> ActiveSleepPlanWakeAlert? {
        ActiveSleepPlanService.wakeAlert(
            for: activeSleepPlan,
            profile: profile,
            events: scopedEvents,
            activeSleep: event,
            settings: predictionSettings
        )
    }

    private func ensureNotificationPermissionForPlan() async {
        let status = await notificationManager.getAuthorizationStatus()
        if status == .notDetermined {
            _ = await notificationManager.requestAuthorization()
        } else if status == .denied {
            showingPermissionDenied = true
        }
    }

    private func syncActiveSleepPlanWakeAlert(for event: BabyEvent? = nil) async {
        refreshActiveSleepPlan()
        let alert = wakeAlert(for: event ?? runningSleepTimer)
        if let alert {
            await notificationManager.scheduleActiveSleepPlanWakeAlert(
                alert,
                babyName: profile?.name ?? "Baby"
            )
        } else {
            await notificationManager.cancelActiveSleepPlanWakeAlert(
                profileID: selectedProfileID
            )
        }
    }

    private func enableLittleWindowAlerts() async {
        let status = await notificationManager.getAuthorizationStatus()
        let granted: Bool
        if status == .notDetermined {
            granted = await notificationManager.requestAuthorization()
        } else {
            granted = status == .authorized || status == .provisional || status == .ephemeral
        }
        guard granted else {
            notificationsEnabled = false
            showingPermissionDenied = true
            return
        }
        notificationsEnabled = true
        await notificationManager.rescheduleLittleWindowAlertIfNeeded(
            prediction: prediction,
            babyName: profile?.name ?? "Baby",
            profileID: selectedProfileID,
            settings: .current,
            isSleeping: activeEvents.contains {
                $0.type == .sleep && $0.isTimerRunning
            }
        )
    }

    private var activityOptions: [AppActionSheetOption] {
        ActivityType.allCases.map { activity in
            AppActionSheetOption(
                title: activity.displayName,
                subtitle: activity == .custom
                    ? "Open the editor for a custom activity."
                    : "Start a timer now.",
                systemImage: activity.systemImage,
                tint: .green
            ) {
                if activity == .custom {
                    editorRoute = EventEditorRoute(type: .activity)
                } else {
                    startTimer(.activity, activityType: activity)
                }
            }
        }
    }
}

private struct SleepKindChooser: ViewModifier {
    @Binding var isPresented: Bool
    let startSleep: (SleepKind) -> Void

    func body(content: Content) -> some View {
        content.appActionSheet(
            isPresented: $isPresented,
            title: "Start Sleep",
            message: "This keeps daytime naps and overnight sleep accurate in History and Insights.",
            systemImage: "moon.zzz.fill",
            tint: .indigo,
            options: SleepKind.allCases.map { kind in
                AppActionSheetOption(
                    title: kind.displayName,
                    subtitle: kind == .nap ? "Track a daytime sleep." : "Track overnight sleep.",
                    systemImage: kind == .nap ? "sun.max.fill" : "moon.stars.fill",
                    tint: .indigo
                ) {
                    startSleep(kind)
                }
            }
        )
    }
}

private struct QuickActionButton: View {
    var title: String
    var icon: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionButtonLabel(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionButtonLabel: View {
    var title: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct DogSummaryCard: View {
    var title: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())
                Spacer()
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}
