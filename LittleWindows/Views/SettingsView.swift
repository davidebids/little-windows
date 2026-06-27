import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]

    @StateObject private var profileService = ProfileService.shared
    @State private var showingDeleteConfirmation = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingImportConfirmation = false
    @State private var exportDocument = BackupDocument()
    @State private var pendingImportData: Data?
    @State private var statusMessage: String?

    private var selectedProfile: BabyProfile? {
        profileService.selectedProfile(in: profiles)
    }

    private var isDogProfile: Bool {
        selectedProfile?.profileType == .dog
    }

    var body: some View {
        Form {
            if let profile = selectedProfile {
                ProfileSettingsSection(profile: profile)
            }

            Section {
                NavigationLink {
                    LazySettingsDestination {
                        ManageProfilesView()
                    }
                } label: {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selectedProfile?.name ?? "None")
                            Text("Switch or edit")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } label: {
                        Label("Profiles", systemImage: "person.2.fill")
                    }
                }
            } header: {
                Label("Profiles", systemImage: "person.crop.circle")
            }

            Section("Your name") {
                CaregiverNameFields(
                    detail: "Name on this device appears on new care entries you log here. Family Sync share name labels the shared family space; most people can keep both names the same."
                )
            }

            if !isDogProfile {
                DeferredChildSleepSettingsSections(profile: selectedProfile)
            }

            SyncSettingsSection()

            Section {
                NavigationLink {
                    LazySettingsDestination {
                        FoodReminderSettingsLauncher()
                    }
                } label: {
                    Label("Food reminders", systemImage: "bell.badge.fill")
                }
            } header: {
                Label("Food & Home", systemImage: "fork.knife")
            } footer: {
                Text("Food & Home records are household-level and sync through the same private iCloud store when iCloud Sync is available.")
            }

            AppointmentSettingsSection(profile: selectedProfile)

            if !isDogProfile {
                MonthlyAgeGuideSettingsSection(profile: selectedProfile)
            }

            Section("Data") {
                Button("Export JSON backup", systemImage: "square.and.arrow.up") {
                    export()
                }
                Button("Import JSON backup", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
                Button("Delete all data", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }

            Section {
                Text("Sleep predictions are a planning aid, not medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SettingsBuildInfoFooter()
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Little-Windows-Backup"
        ) { result in
            if case .failure(let error) = result {
                statusMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .appActionSheet(
            isPresented: $showingImportConfirmation,
            title: "Replace Current Data?",
            message: "This replaces every current profile, event, prediction, milestone, appointment, and guide-read state. Export a backup first if you may need this history.",
            systemImage: "square.and.arrow.down",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Import Backup",
                    subtitle: "Replace all current Little Windows data.",
                    systemImage: "square.and.arrow.down.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    performPendingImport()
                }
            ],
            cancelAction: {
                pendingImportData = nil
            }
        )
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete All Data?",
            message: "This permanently deletes every profile, event, prediction, milestone, appointment, and guide-read state. Export a backup first if you may need this history.",
            systemImage: "trash",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Delete All Data",
                    subtitle: "Remove all local Little Windows history.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    deleteAll()
                }
            ]
        )
        .alert("Little Windows", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try DataExportImportService.exportData(context: modelContext))
            showingExporter = true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingImportData = data
            showingImportConfirmation = true
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func performPendingImport() {
        guard let data = pendingImportData else { return }
        do {
            try DataExportImportService.importData(data, context: modelContext)
            pendingImportData = nil
            statusMessage = "Backup imported."
        } catch {
            pendingImportData = nil
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteAll() {
        do {
            try DataExportImportService.deleteAll(context: modelContext)
            statusMessage = "All history was deleted."
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

struct LazySettingsDestination<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

private struct ChildSleepSettingsRenderState {
    var currentPrediction: SleepPrediction?
    var currentPressure: SleepPressure?
    var selectedProfileIsSleeping: Bool
    var notificationStatus: String
    var sleepPressureStatus: String
    var sleepPressurePreviewText: String
    var notificationPreview: LittleWindowNotificationCopy

    static let placeholder = ChildSleepSettingsRenderState(
        currentPrediction: nil,
        currentPressure: nil,
        selectedProfileIsSleeping: false,
        notificationStatus: "Checking next alert",
        sleepPressureStatus: "Checking pressure",
        sleepPressurePreviewText: "Checking recent sleep rhythm.",
        notificationPreview: LittleWindowNotificationCopy(
            title: "Nap window soon",
            body: "Little Windows will show the next alert preview after it checks recent sleep."
        )
    )
}

private struct DeferredChildSleepSettingsSections: View {
    let profile: BabyProfile?
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                ChildSleepSettingsSections(profile: profile)
            } else {
                Section("Prediction") {
                    LabeledContent {
                        ProgressView()
                            .controlSize(.small)
                    } label: {
                        Label("Preparing sleep settings", systemImage: "moon.stars.fill")
                    }
                }
            }
        }
        .task(id: profile?.id) {
            isReady = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            isReady = true
        }
    }
}

private struct ChildSleepSettingsSections: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var events: [BabyEvent]
    @Query private var records: [SleepPredictionRecord]

    let profile: BabyProfile?

    @AppStorage("feedAdjustmentEnabled") private var feedAdjustmentEnabled = true
    @AppStorage("nursingAdjustmentEnabled") private var nursingAdjustmentEnabled = true
    @AppStorage("bedtimePredictionEnabled") private var bedtimePredictionEnabled = true
    @AppStorage("predictionNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("sleepPressureAlertsEnabled") private var sleepPressureAlertsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 10
    @AppStorage("littleWindowNapAlertsEnabled") private var napAlertsEnabled = true
    @AppStorage("littleWindowBedtimeAlertsEnabled") private var bedtimeAlertsEnabled = true
    @AppStorage("littleWindowConfidenceThreshold") private var confidenceThresholdRawValue =
        LittleWindowConfidenceThreshold.medium.rawValue
    @AppStorage("customWakeMinimum") private var customWakeMinimum = 0.0
    @AppStorage("customWakeMaximum") private var customWakeMaximum = 0.0

    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingAlertPermissionPrompt = false
    @State private var showingPermissionDenied = false
    @State private var pendingNotificationRefresh: Task<Void, Never>?
    @State private var cachedRenderState = ChildSleepSettingsRenderState.placeholder
    @State private var renderRefreshTask: Task<Void, Never>?

    init(profile: BabyProfile?) {
        self.profile = profile

        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { event in
                event.startDate >= recentCutoff
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        _events = Query(eventDescriptor)

        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.actualSleepEventID == nil || record.generatedAt >= recentCutoff
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        _records = Query(recordDescriptor)
    }

    var body: some View {
        let state = cachedRenderState

        Group {
            Section("Prediction") {
                Toggle("Use feed timing", isOn: $feedAdjustmentEnabled)
                    .onChange(of: feedAdjustmentEnabled) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }
                Toggle("Use nursing timing", isOn: $nursingAdjustmentEnabled)
                    .onChange(of: nursingAdjustmentEnabled) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }
                Toggle("Predict bedtime", isOn: $bedtimePredictionEnabled)
                    .onChange(of: bedtimePredictionEnabled) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }
                NavigationLink("Wake-window tuning") {
                    LazySettingsDestination {
                        WakeWindowTuningView(
                            minimum: $customWakeMinimum,
                            maximum: $customWakeMaximum
                        )
                    }
                }
            }

            Section {
                Toggle(
                    "Enable Little Window Alerts",
                    isOn: Binding(
                        get: { notificationsEnabled },
                        set: { enabled in
                            if enabled {
                                showingAlertPermissionPrompt = true
                            } else {
                                notificationsEnabled = false
                                Task {
                                    await notificationManager.cancelPendingLittleWindowAlerts()
                                }
                            }
                        }
                    )
                )

                if notificationsEnabled {
                    Picker("Alert timing", selection: $notificationLeadMinutes) {
                        Text("At window start").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                        Text("20 minutes before").tag(20)
                        Text("30 minutes before").tag(30)
                    }
                    .onChange(of: notificationLeadMinutes) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }

                    Toggle("Nap alerts", isOn: $napAlertsEnabled)
                        .onChange(of: napAlertsEnabled) { _, _ in
                            scheduleRenderStateRefresh()
                            scheduleNotificationRefresh()
                        }
                    Toggle("Bedtime alerts", isOn: $bedtimeAlertsEnabled)
                        .onChange(of: bedtimeAlertsEnabled) { _, _ in
                            scheduleRenderStateRefresh()
                            scheduleNotificationRefresh()
                        }

                    Picker("Minimum confidence", selection: $confidenceThresholdRawValue) {
                        ForEach(LittleWindowConfidenceThreshold.allCases) { threshold in
                            Text(threshold.displayName).tag(threshold.rawValue)
                        }
                    }
                    .onChange(of: confidenceThresholdRawValue) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }

                    LabeledContent("Next alert") {
                        Text(state.notificationStatus)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if notificationManager.authorizationStatus == .denied {
                    Button("Open iOS Notification Settings", systemImage: "gear") {
                        openNotificationSettings()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notification preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(state.notificationPreview.title)
                        .font(.subheadline.weight(.semibold))
                    Text(state.notificationPreview.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } header: {
                Label("Little Window Alerts", systemImage: "bell.badge.fill")
            } footer: {
                Text("Little Windows can remind you before the next likely nap or bedtime window. Alerts are based on logged patterns and are not medical advice.")
            }

            Section {
                Toggle(
                    "Enable Sleep Pressure Alerts",
                    isOn: Binding(
                        get: { sleepPressureAlertsEnabled },
                        set: { enabled in
                            if enabled {
                                Task { await enableSleepPressureAlerts() }
                            } else {
                                sleepPressureAlertsEnabled = false
                                Task {
                                    await notificationManager.cancelPendingSleepPressureAlerts(
                                        profileID: profileID
                                    )
                                }
                            }
                        }
                    )
                )

                if sleepPressureAlertsEnabled {
                    LabeledContent("Next pressure alert") {
                        Text(state.sleepPressureStatus)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pressure preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label(
                        state.currentPressure?.band.statusText ?? "Learning rhythm",
                        systemImage: state.currentPressure?.band.systemImage ?? "sparkle.magnifyingglass"
                    )
                    .font(.subheadline.weight(.semibold))
                    Text(state.sleepPressurePreviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } header: {
                Label("Sleep Pressure Alerts", systemImage: "gauge.with.dots.needle.50percent")
            } footer: {
                Text("These are separate from Little Window Alerts. They use the current pressure band and are hidden for babies under 4 months while Little Windows is learning rhythm.")
            }
        }
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
            Text("Little Windows can remind you before the next likely nap or bedtime window.")
        }
        .alert("Notifications are turned off", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                openNotificationSettings()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can allow Little Window Alerts in iOS Settings whenever you're ready.")
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
            await notificationManager.configure()
            await refreshRenderState()
        }
        .onChange(of: profileID) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: events.count) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: records.count) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: sleepPressureAlertsEnabled) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: notificationsEnabled) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: customWakeMinimum) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: customWakeMaximum) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onDisappear {
            pendingNotificationRefresh?.cancel()
            renderRefreshTask?.cancel()
        }
    }

    private var profileID: UUID? {
        profile?.id
    }

    private var scopedEventsForProfile: [BabyEvent] {
        events.filter { $0.matchesProfile(profileID) }
    }

    private var scopedRecordsForProfile: [SleepPredictionRecord] {
        records.filter { $0.matchesProfile(profileID) }
    }

    private func makeRenderState() -> ChildSleepSettingsRenderState {
        let scopedEvents = scopedEventsForProfile
        let scopedRecords = scopedRecordsForProfile
        let currentPrediction = scopedRecords.first(where: {
            $0.actualSleepEventID == nil
        })?.prediction
        let selectedProfileIsSleeping = scopedEvents.contains {
            $0.type == .sleep && $0.isTimerRunning
        }
        let currentPressure = SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: scopedEvents,
            records: scopedRecords,
            settings: settings
        )
        let notificationStatus = notificationManager.statusText(
            prediction: currentPrediction,
            settings: .current,
            isSleeping: selectedProfileIsSleeping
        )
        let sleepPressureStatus = NotificationManager.sleepPressureStatusText(
            pressure: currentPressure,
            enabled: sleepPressureAlertsEnabled,
            isSleeping: selectedProfileIsSleeping,
            authorizationStatus: notificationManager.authorizationStatus
        )
        let sleepPressurePreviewText: String
        if let pressure = currentPressure {
            if let score = pressure.score {
                sleepPressurePreviewText = "\(Int(score.rounded())) / 100 · \(pressure.confidenceLabel.displayName.lowercased()) confidence"
            } else {
                sleepPressurePreviewText = "No pressure score yet; Little Windows is learning rhythm."
            }
        } else {
            sleepPressurePreviewText = "Complete a sleep log to start learning pressure."
        }
        let notificationPreview: LittleWindowNotificationCopy
        if let currentPrediction {
            notificationPreview = NotificationManager.notificationCopy(
                for: currentPrediction,
                babyName: profile?.name ?? "Baby",
                leadMinutes: notificationLeadMinutes
            )
        } else {
            notificationPreview = LittleWindowNotificationCopy(
                title: "Nap window soon",
                body: "Baby's Little Window is estimated for 1:55-2:35 PM."
            )
        }
        return ChildSleepSettingsRenderState(
            currentPrediction: currentPrediction,
            currentPressure: currentPressure,
            selectedProfileIsSleeping: selectedProfileIsSleeping,
            notificationStatus: notificationStatus,
            sleepPressureStatus: sleepPressureStatus,
            sleepPressurePreviewText: sleepPressurePreviewText,
            notificationPreview: notificationPreview
        )
    }

    @MainActor
    private func refreshRenderState() async {
        await Task.yield()
        guard !Task.isCancelled else { return }
        cachedRenderState = makeRenderState()
    }

    private func scheduleRenderStateRefresh() {
        renderRefreshTask?.cancel()
        renderRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            cachedRenderState = makeRenderState()
        }
    }

    private var settings: PredictionSettings {
        PredictionSettings(
            feedAdjustmentEnabled: feedAdjustmentEnabled,
            nursingAdjustmentEnabled: nursingAdjustmentEnabled,
            bedtimePredictionEnabled: bedtimePredictionEnabled,
            customBaselineMinimum: customWakeMinimum > 0 ? customWakeMinimum : nil,
            customBaselineMaximum: customWakeMaximum > 0 ? customWakeMaximum : nil
        )
    }

    private func rescheduleNotification() async {
        await EventMutationService.refreshPrediction(
            profile: profile,
            events: scopedEventsForProfile,
            records: scopedRecordsForProfile,
            context: modelContext,
            settings: settings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes
        )
    }

    private func scheduleNotificationRefresh() {
        pendingNotificationRefresh?.cancel()
        pendingNotificationRefresh = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await rescheduleNotification()
        }
    }

    private var currentPrediction: SleepPrediction? {
        cachedRenderState.currentPrediction
    }

    private var notificationStatus: String {
        cachedRenderState.notificationStatus
    }

    private var currentPressure: SleepPressure? {
        cachedRenderState.currentPressure
    }

    private var selectedProfileIsSleeping: Bool {
        cachedRenderState.selectedProfileIsSleeping
    }

    private var sleepPressureStatus: String {
        cachedRenderState.sleepPressureStatus
    }

    private var sleepPressurePreviewText: String {
        cachedRenderState.sleepPressurePreviewText
    }

    private var notificationPreview: LittleWindowNotificationCopy {
        cachedRenderState.notificationPreview
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
        await rescheduleNotification()
        await refreshRenderState()
    }

    private func enableSleepPressureAlerts() async {
        let status = await notificationManager.getAuthorizationStatus()
        let granted: Bool
        if status == .notDetermined {
            granted = await notificationManager.requestAuthorization()
        } else {
            granted = status == .authorized || status == .provisional || status == .ephemeral
        }
        guard granted else {
            sleepPressureAlertsEnabled = false
            showingPermissionDenied = true
            return
        }
        sleepPressureAlertsEnabled = true
        scheduleNotificationRefresh()
        scheduleRenderStateRefresh()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }
}

private struct AppointmentSettingsSection: View {
    @Query private var appointments: [DoctorAppointment]
    @AppStorage("appointmentRemindersEnabled") private var appointmentRemindersEnabled = true
    @StateObject private var notificationManager = NotificationManager.shared

    let profile: BabyProfile?

    init(profile: BabyProfile?) {
        self.profile = profile

        if let profileID = profile?.id {
            _appointments = Query(
                FetchDescriptor<DoctorAppointment>(
                    predicate: #Predicate<DoctorAppointment> { appointment in
                        appointment.profileID == profileID
                    },
                    sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
                )
            )
        } else {
            _appointments = Query(
                FetchDescriptor<DoctorAppointment>(
                    sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
                )
            )
        }
    }

    private var profileID: UUID? {
        profile?.id
    }

    private var selectedProfileAppointments: [DoctorAppointment] {
        appointments.filter { $0.matchesProfile(profileID) }
    }

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    AppointmentsListView()
                }
            } label: {
                LabeledContent {
                    Text("\(selectedProfileAppointments.count)")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Appointments and visits", systemImage: "stethoscope")
                }
            }
            Toggle("Appointment reminders", isOn: $appointmentRemindersEnabled)
                .onChange(of: appointmentRemindersEnabled) { _, enabled in
                    Task {
                        let appointments = selectedProfileAppointments
                        if enabled {
                            for appointment in appointments where !appointment.isCompleted {
                                await notificationManager.rescheduleAppointmentReminders(
                                    appointment: appointment,
                                    babyName: profile?.name ?? "Baby"
                                )
                            }
                        } else {
                            for appointment in appointments {
                                await notificationManager.cancelAppointmentReminders(
                                    appointmentID: appointment.id
                                )
                            }
                        }
                    }
                }
        } header: {
            Label("Appointments", systemImage: "calendar.badge.clock")
        } footer: {
            Text("Appointment reminders are separate from Little Window sleep alerts.")
        }
    }
}

private struct MonthlyAgeGuideSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var ageGuideReadStates: [AgeGuideReadState]

    let profile: BabyProfile?

    @AppStorage("monthlyAgeGuideNotificationsEnabled") private var monthlyAgeGuideNotificationsEnabled = false
    @AppStorage("monthlyAgeGuideNotificationTiming") private var monthlyAgeGuideNotificationTimingRawValue =
        MonthlyAgeGuideNotificationTiming.monthlyBirthday.rawValue
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingPermissionDenied = false

    init(profile: BabyProfile?) {
        self.profile = profile

        if let profileID = profile?.id {
            _ageGuideReadStates = Query(
                FetchDescriptor<AgeGuideReadState>(
                    predicate: #Predicate<AgeGuideReadState> { state in
                        state.profileID == profileID
                    },
                    sortBy: [SortDescriptor(\AgeGuideReadState.updatedAt)]
                )
            )
        } else {
            _ageGuideReadStates = Query(
                FetchDescriptor<AgeGuideReadState>(
                    sortBy: [SortDescriptor(\AgeGuideReadState.updatedAt)]
                )
            )
        }
    }

    private var selectedProfileAgeGuideReadStates: [AgeGuideReadState] {
        ageGuideReadStates.filter { $0.matchesProfile(profile?.id) }
    }

    var body: some View {
        Section {
            Toggle(
                "Monthly guide notifications",
                isOn: Binding(
                    get: { monthlyAgeGuideNotificationsEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                let granted = await notificationManager.requestAuthorization()
                                if granted {
                                    monthlyAgeGuideNotificationsEnabled = true
                                    await rescheduleMonthlyAgeGuideNotification()
                                } else {
                                    monthlyAgeGuideNotificationsEnabled = false
                                    showingPermissionDenied = true
                                }
                            }
                        } else {
                            monthlyAgeGuideNotificationsEnabled = false
                            Task {
                                await notificationManager.cancelMonthlyAgeGuideNotifications()
                            }
                        }
                    }
                )
            )
            if monthlyAgeGuideNotificationsEnabled {
                Picker("Timing", selection: $monthlyAgeGuideNotificationTimingRawValue) {
                    ForEach(MonthlyAgeGuideNotificationTiming.allCases) { timing in
                        Text(timing.displayName).tag(timing.rawValue)
                    }
                }
                .onChange(of: monthlyAgeGuideNotificationTimingRawValue) { _, _ in
                    Task { await rescheduleMonthlyAgeGuideNotification() }
                }
            }
            NavigationLink {
                LazySettingsDestination {
                    AgeGuidesListView(
                        guides: AgeGuideService.shared.allAgeGuides(),
                        currentMonth: profile.map {
                            AgeGuideService.shared.ageMonth(for: $0)
                        },
                        readStates: selectedProfileAgeGuideReadStates
                    )
                }
            } label: {
                Label("Browse age guides", systemImage: "book.pages.fill")
            }
        } header: {
            Label("Monthly Age Guides", systemImage: "calendar.badge.clock")
        } footer: {
            Text("One gentle reminder per monthly age at most. Guides are parent education and memory prompts, not medical advice.")
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
            if UserDefaults.standard.object(forKey: "monthlyAgeGuideNotificationsEnabled") == nil,
               notificationManager.authorizationStatus == .authorized {
                monthlyAgeGuideNotificationsEnabled = true
                await rescheduleMonthlyAgeGuideNotification()
            }
        }
        .alert("Notifications are turned off", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                openNotificationSettings()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can allow Little Window Alerts in iOS Settings whenever you're ready.")
        }
    }

    private func rescheduleMonthlyAgeGuideNotification() async {
        guard let profile else { return }
        let timing = MonthlyAgeGuideNotificationTiming(
            rawValue: monthlyAgeGuideNotificationTimingRawValue
        ) ?? .monthlyBirthday
        await notificationManager.scheduleMonthlyAgeGuideNotification(
            profile: profile,
            readStates: selectedProfileAgeGuideReadStates,
            context: modelContext,
            timing: timing
        )
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }
}

private struct SettingsBuildInfoFooter: View {
    private var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
    }

    private var buildChannel: String {
        #if DEBUG
        return "Debug"
        #elseif targetEnvironment(simulator)
        return "Simulator"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "TestFlight"
        }
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            return "Development"
        }
        return "App Store"
        #endif
    }

    var body: some View {
        Section {
            VStack(spacing: 4) {
                Text("Little Windows")
                    .font(.caption.weight(.semibold))
                Text("Version \(version) (\(build))")
                    .font(.caption2.monospacedDigit())
                Text("Build: \(buildChannel)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
}

private struct FoodReminderSettingsLauncher: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \FoodReminder.dateTime) private var reminders: [FoodReminder]
    @Query(sort: \ShoppingList.sortOrder) private var shoppingLists: [ShoppingList]
    @Query(sort: \MealPrepItem.updatedAt, order: .reverse) private var mealPrepItems: [MealPrepItem]

    var body: some View {
        Group {
            if let household = households.first {
                FoodReminderSettingsView(
                    household: household,
                    reminders: reminders.filter { $0.householdID == household.id },
                    shoppingLists: shoppingLists.filter { $0.householdID == household.id && !$0.isArchived },
                    mealPrepItems: mealPrepItems.filter { $0.householdID == household.id && !$0.isArchived }
                )
            } else {
                ProgressView("Preparing Food & Home")
                    .task {
                        FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
                    }
            }
        }
    }
}

private struct SyncSettingsSection: View {
    @AppStorage(PersistenceService.iCloudSyncEnabledKey) private var isICloudSyncEnabled = true
    @AppStorage(PersistenceService.familySyncModeKey) private var syncModeRawValue = FamilySyncMode.privateICloudSync.rawValue

    private var syncMode: FamilySyncMode {
        FamilySyncMode(rawValue: syncModeRawValue)
            ?? (isICloudSyncEnabled ? .privateICloudSync : .localOnly)
    }

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    ICloudSyncSettingsView()
                }
            } label: {
                LabeledContent {
                    Text(isICloudSyncEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("iCloud and sharing", systemImage: "icloud")
                }
            }
            NavigationLink {
                LazySettingsDestination {
                    FamilySyncSettingsView()
                }
            } label: {
                LabeledContent {
                    Text(syncMode == .sharedFamilySync ? "On" : "Off")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Family Sync", systemImage: "person.2.badge.gearshape.fill")
                }
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Private iCloud Sync covers the same Apple Account. Family Sync shares Little Windows data with accepted iCloud caregivers across Apple Accounts.")
        }
    }
}

private struct ProfileSettingsSection: View {
    @Bindable var profile: BabyProfile
    @State private var draftName = ""
    @State private var draftNotes = ""
    @State private var pendingSave: Task<Void, Never>?

    init(profile: BabyProfile) {
        self.profile = profile
        _draftName = State(initialValue: profile.name)
        _draftNotes = State(initialValue: profile.notes)
    }

    var body: some View {
        Section {
            HStack(spacing: 14) {
                ProfileAvatarView(profile: profile, size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(draftName.isEmpty ? profile.name : draftName)
                        .font(.headline)
                    Text(DateFormatting.age(from: profile.birthDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            TextField("Name", text: $draftName)
                .onSubmit(saveNow)
                .onChange(of: draftName) { _, _ in scheduleSave() }
            DatePicker("Birthdate", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date)
                .onChange(of: profile.birthDate) { _, _ in profile.updatedAt = Date() }
            Picker("Sex for growth charts", selection: Binding(
                get: { profile.sex },
                set: {
                    profile.sex = $0
                    profile.updatedAt = Date()
                }
            )) {
                ForEach(BabySex.allCases) {
                    Text($0.displayName).tag($0)
                }
            }
            TextField("Notes", text: $draftNotes, axis: .vertical)
                .onSubmit(saveNow)
                .onChange(of: draftNotes) { _, _ in scheduleSave() }
        } header: {
            Label("Baby profile", systemImage: "face.smiling")
        }
        .onAppear(perform: syncDraftsFromProfile)
        .onChange(of: profile.id) { _, _ in syncDraftsFromProfile() }
        .onDisappear(perform: saveNow)
    }

    private func syncDraftsFromProfile() {
        pendingSave?.cancel()
        draftName = profile.name
        draftNotes = profile.notes
    }

    private func scheduleSave() {
        let name = draftName
        let notes = draftNotes
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            save(name: name, notes: notes)
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        save(name: draftName, notes: draftNotes)
    }

    private func save(name: String, notes: String) {
        guard profile.name != name || profile.notes != notes else { return }
        profile.name = name
        profile.notes = notes
        profile.updatedAt = Date()
    }
}

struct CaregiverNameFields: View {
    let detail: String
    var clearsFamilySyncPrompt = false
    var showsFallback = true

    @State private var currentName: String
    @State private var primaryName: String
    @State private var pendingSave: Task<Void, Never>?

    init(
        detail: String,
        clearsFamilySyncPrompt: Bool = false,
        showsFallback: Bool = true
    ) {
        self.detail = detail
        self.clearsFamilySyncPrompt = clearsFamilySyncPrompt
        self.showsFallback = showsFallback
        _currentName = State(
            initialValue: UserDefaults.standard.string(
                forKey: CaregiverIdentityService.currentCaregiverNameKey
            ) ?? ""
        )
        _primaryName = State(
            initialValue: UserDefaults.standard.string(
                forKey: CaregiverIdentityService.primaryCaregiverNameKey
            ) ?? "Caregiver 1"
        )
    }

    var body: some View {
        Group {
            LabeledContent("Name on this device") {
                TextField("Your name", text: $currentName)
                    .textContentType(.name)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(saveNow)
                    .onChange(of: currentName) { _, _ in scheduleSave() }
            }
            LabeledContent("Share name") {
                TextField("Optional", text: $primaryName)
                    .textContentType(.name)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(saveNow)
                    .onChange(of: primaryName) { _, _ in scheduleSave() }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if showsFallback && currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Using \(fallbackName) until you enter a name here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: saveNow)
    }

    private var fallbackName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: "",
            primaryName: primaryName,
            fallback: "Caregiver"
        )
    }

    private func scheduleSave() {
        let currentName = currentName
        let primaryName = primaryName
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            save(currentName: currentName, primaryName: primaryName)
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        save(currentName: currentName, primaryName: primaryName)
    }

    private func save(currentName: String, primaryName: String) {
        let defaults = UserDefaults.standard
        defaults.set(currentName, forKey: CaregiverIdentityService.currentCaregiverNameKey)
        defaults.set(primaryName, forKey: CaregiverIdentityService.primaryCaregiverNameKey)
        if clearsFamilySyncPrompt,
           !currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(false, forKey: CaregiverIdentityService.needsLogNamePromptKey)
        }
    }
}

private struct WakeWindowTuningView: View {
    @Binding var minimum: Double
    @Binding var maximum: Double

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortest") {
                    TextField("Minutes", value: $minimum, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Longest") {
                    TextField("Minutes", value: $maximum, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Use age-based defaults") {
                    minimum = 0
                    maximum = 0
                }
            } header: {
                Text("Fallback wake-window range")
            } footer: {
                Text("Used when there is not enough personal sleep history yet. Set both fields to 0 to use the age-based default range.")
            }
        }
        .navigationTitle("Wake Windows")
        .navigationBarTitleDisplayMode(.inline)
    }
}
