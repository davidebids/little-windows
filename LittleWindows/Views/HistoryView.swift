import SwiftData
import SwiftUI

enum HistoryDisplayMode: String, CaseIterable, Identifiable {
    case list
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .day: "Day"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .day: "calendar.day.timeline.left"
        }
    }
}

struct ReportsView: View {
    @ObservedObject private var router = DeepLinkRouter.shared
    @AppStorage("reportsDisplayMode") private var displayModeRawValue = ReportsDisplayMode.day.rawValue
    @State private var selectedDate: Date
    private let profileID: UUID?

    init(profileID: UUID? = nil) {
        self.profileID = profileID
        _selectedDate = State(initialValue: HistoryView.initialSelectedDate())
    }

    private var displayMode: Binding<ReportsDisplayMode> {
        Binding(
            get: { router.selectedReportsMode },
            set: {
                router.selectedReportsMode = $0
                displayModeRawValue = $0.rawValue
            }
        )
    }
    private var historyDisplayMode: HistoryDisplayMode? {
        switch displayMode.wrappedValue {
        case .day:
            return .day
        case .list:
            return .list
        case .summary:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Reports view", selection: displayMode) {
                ForEach(ReportsDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if let historyDisplayMode {
                HistoryView(
                    profileID: profileID,
                    forcedDisplayMode: historyDisplayMode,
                    showsDisplayModePicker: false,
                    navigationTitle: "Reports",
                    selectedDate: $selectedDate
                )
            } else {
                InsightsDashboardView(navigationTitle: "Reports")
            }
        }
        .background(AppTheme.background)
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @Query private var records: [SleepPredictionRecord]
    @AppStorage("feedAdjustmentEnabled") private var feedAdjustmentEnabled = true
    @AppStorage("nursingAdjustmentEnabled") private var nursingAdjustmentEnabled = true
    @AppStorage("bedtimePredictionEnabled") private var bedtimePredictionEnabled = true
    @AppStorage("predictionNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 10
    @AppStorage("customWakeMinimum") private var customWakeMinimum = 0.0
    @AppStorage("customWakeMaximum") private var customWakeMaximum = 0.0
    @AppStorage("historyDisplayMode") private var displayModeRawValue = HistoryDisplayMode.list.rawValue
    @State private var internalSelectedDate: Date
    @State private var events: [CareEvent] = []
    @State private var appointments: [DoctorAppointment] = []
    @State private var milestones: [MilestoneEntry] = []
    @State private var editorRoute: EventEditorRoute?
    @State private var activeTimerToEdit: CareEvent?
    @State private var eventPendingDelete: CareEvent?
    @State private var milestonePendingDelete: MilestoneEntry?
    @State private var appointmentPendingDelete: DoctorAppointment?
    @State private var showingDeleteEventConfirmation = false
    @State private var showingDeleteMilestoneConfirmation = false
    @State private var showingDeleteAppointmentConfirmation = false
    @State private var timerSystemRefreshTask: Task<Void, Never>?
    @State private var timerSystemRefreshRevision = UUID()
    @StateObject private var profileService = ProfileService.shared
    private let forcedDisplayMode: HistoryDisplayMode?
    private let showsDisplayModePicker: Bool
    private let navigationTitle: String
    private let externalSelectedDate: Binding<Date>?

    init(
        profileID: UUID? = nil,
        forcedDisplayMode: HistoryDisplayMode? = nil,
        showsDisplayModePicker: Bool = true,
        navigationTitle: String = "Calendar",
        selectedDate: Binding<Date>? = nil
    ) {
        self.forcedDisplayMode = forcedDisplayMode
        self.showsDisplayModePicker = showsDisplayModePicker
        self.navigationTitle = navigationTitle
        self.externalSelectedDate = selectedDate
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let selectedProfileID = profileID ?? ProfileService.shared.selectedProfileID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.profileID == selectedProfileID
                    && (record.actualSleepEventID == nil || record.generatedAt >= recentCutoff)
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        _records = Query(recordDescriptor)
        _internalSelectedDate = State(initialValue: Self.initialSelectedDate())
    }

    static func initialSelectedDate() -> Date {
        if let value = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_HISTORY_DATE"],
           let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return Date()
    }

    private var profile: CareProfile? {
        profileService.selectedProfile(in: profiles)
    }
    private var scopedRecords: [SleepPredictionRecord] {
        records.filter { $0.matchesProfile(profile?.id) }
    }
    private var summary: DailySummary {
        DailySummaryService.summary(for: events)
    }
    private var displayMode: Binding<HistoryDisplayMode> {
        Binding(
            get: { forcedDisplayMode ?? HistoryDisplayMode(rawValue: displayModeRawValue) ?? .list },
            set: { if forcedDisplayMode == nil { displayModeRawValue = $0.rawValue } }
        )
    }
    private var selectedDate: Date {
        selectedDateBinding.wrappedValue
    }
    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { externalSelectedDate?.wrappedValue ?? internalSelectedDate },
            set: { newValue in
                if externalSelectedDate != nil {
                    externalSelectedDate?.wrappedValue = newValue
                } else {
                    internalSelectedDate = newValue
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                dateNavigator
                    .padding(12)
                    .appSurface()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if displayMode.wrappedValue == .day {
                summarySection
            }

            if showsDisplayModePicker {
                Section {
                    Picker("History view", selection: displayMode) {
                        ForEach(HistoryDisplayMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            historySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(navigationTitle)
        .task(id: historyRefreshToken) {
            refreshDayData()
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                EventEditorView(type: route.type, event: route.event) { event in
                    event.profileID = event.profileID ?? profile?.id
                    Task { await eventChanged(event) }
                }
            }
        }
        .sheet(item: $activeTimerToEdit) { event in
            NavigationStack {
                ActiveTimerEditorView(
                    event: event,
                    adjustStart: { date in adjustStart(of: event, to: date) },
                    stop: { stop(event) },
                    resume: { resume(event) },
                    reset: { reset(event) },
                    save: { endDate in save(event, endDate: endDate) },
                    discard: { discardTimer(event) },
                    setStartTimeZone: { setStartTimeZone($0, for: event) },
                    setEndTimeZone: { setEndTimeZone($0, for: event) },
                    switchNursingSide: event.type == .nursing
                        ? { switchNursingSide(event) }
                        : nil,
                    setNursingSide: event.type == .nursing
                        ? { setNursingSide($0, for: event) }
                        : nil
                )
            }
        }
        .appActionSheet(
            isPresented: $showingDeleteEventConfirmation,
            title: "Delete event?",
            message: "This permanently removes the event from the timeline.",
            systemImage: "trash.fill",
            tint: .red,
            options: eventPendingDelete.map { event in
                [AppActionSheetOption(
                    title: "Delete Event",
                    subtitle: "Permanently remove this event from the timeline.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    delete(event)
                    eventPendingDelete = nil
                }]
            } ?? [],
            cancelAction: { eventPendingDelete = nil }
        )
        .appActionSheet(
            isPresented: $showingDeleteMilestoneConfirmation,
            title: "Delete memory?",
            message: "This permanently removes the memory from the timeline.",
            systemImage: "trash.fill",
            tint: .red,
            options: milestonePendingDelete.map { milestone in
                [AppActionSheetOption(
                    title: "Delete Memory",
                    subtitle: "Permanently remove this memory from the timeline.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    delete(milestone)
                    milestonePendingDelete = nil
                }]
            } ?? [],
            cancelAction: { milestonePendingDelete = nil }
        )
        .appActionSheet(
            isPresented: $showingDeleteAppointmentConfirmation,
            title: "Delete appointment?",
            message: "This permanently removes the appointment and cancels its reminders.",
            systemImage: "calendar.badge.minus",
            tint: .red,
            options: appointmentPendingDelete.map { appointment in
                [AppActionSheetOption(
                    title: "Delete Appointment",
                    subtitle: "Remove the appointment and cancel its reminders.",
                    systemImage: "calendar.badge.minus",
                    tint: .red,
                    role: .destructive
                ) {
                    delete(appointment)
                    appointmentPendingDelete = nil
                }]
            } ?? [],
            cancelAction: { appointmentPendingDelete = nil }
        )
    }

    private var historyRefreshToken: String {
        [
            profile?.id.uuidString ?? "no-profile",
            Calendar.current.startOfDay(for: selectedDate).timeIntervalSinceReferenceDate.description
        ].joined(separator: "-")
    }

    private var dateNavigator: some View {
        HStack(spacing: 12) {
            Button {
                changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)

            DatePicker("History date", selection: selectedDateBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity)

            Button {
                changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)

            if !Calendar.current.isDateInToday(selectedDate) {
                Button("Today") {
                    withAnimation(.snappy) {
                        selectedDateBinding.wrappedValue = Date()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            SummaryGrid(summary: summary)
                .environment(\.careProfileType, profile?.profileType ?? .child)
                .padding(10)
                .appSurface()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Daily snapshot", subtitle: DateFormatting.day.string(from: selectedDate))
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            if events.isEmpty && milestones.isEmpty && appointments.isEmpty {
                ContentUnavailableView(
                    "Nothing logged",
                    systemImage: "calendar.badge.clock",
                    description: Text("Choose another day, add care from Today, schedule an appointment, or capture a milestone.")
                )
            } else if displayMode.wrappedValue == .day {
                VStack(spacing: 12) {
                    if !appointments.isEmpty {
                        appointmentMarkers
                    }
                    if !milestones.isEmpty {
                        milestoneMarkers
                    }
                    if !events.isEmpty {
                        CalendarDayView(
                            date: selectedDate,
                            events: events,
                            edit: open,
                            delete: confirmDelete
                        )
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(appointments) { appointment in
                    NavigationLink {
                        AppointmentDetailView(appointment: appointment)
                    } label: {
                        CalendarAppointmentRow(appointment: appointment)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            confirmDelete(appointment)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                ForEach(milestones) { milestone in
                    NavigationLink {
                        MilestoneDetailView(milestone: milestone)
                    } label: {
                        CalendarMilestoneRow(
                            milestone: milestone,
                            birthDate: profile?.birthDate
                        )
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            confirmDelete(milestone)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                ForEach(events) { event in
                    Button {
                        open(event)
                    } label: {
                        EventRow(event: event)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            confirmDelete(event)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            AppSectionHeader(
                title: displayMode.wrappedValue == .day ? "Day timeline" : "Events",
                subtitle: events.isEmpty && milestones.isEmpty && appointments.isEmpty
                    ? nil
                    : "\(events.count + milestones.count + appointments.count) total"
            )
        }
    }

    private var appointmentMarkers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Appointments", systemImage: "stethoscope")
                .font(.headline)
                .foregroundStyle(.indigo)
            ForEach(appointments) { appointment in
                NavigationLink {
                    AppointmentDetailView(appointment: appointment)
                } label: {
                    CalendarAppointmentRow(appointment: appointment)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.13), Color.cyan.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.indigo.opacity(0.14), lineWidth: 0.5)
        }
    }

    private var milestoneMarkers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Milestones & Memories", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(MilestonePalette.accent)
            ForEach(milestones) { milestone in
                NavigationLink {
                    MilestoneDetailView(milestone: milestone)
                } label: {
                    CalendarMilestoneRow(
                        milestone: milestone,
                        birthDate: profile?.birthDate
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.13), Color.orange.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.pink.opacity(0.14), lineWidth: 0.5)
        }
    }

    private func changeDay(by value: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) else {
            return
        }
        withAnimation(.snappy) {
            selectedDateBinding.wrappedValue = date
        }
    }

    private func refreshDayData() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.startOfNextDay(for: selectedDate)
        // A local calendar day can be up to 26 hours away from the device's
        // current zone (UTC-12 through UTC+14). Fetch a little beyond that,
        // then apply the event's recorded local day in memory.
        let eventFetchStart = start.addingTimeInterval(-30 * 60 * 60)
        let eventFetchEnd = end.addingTimeInterval(30 * 60 * 60)
        let selectedProfileID = profile?.id

        do {
            if let selectedProfileID {
                let eventDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.profileID == selectedProfileID &&
                            event.startDate >= eventFetchStart &&
                            event.startDate < eventFetchEnd
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                events = try modelContext.fetch(eventDescriptor)
                    .filter {
                        Self.visibleDayEvent($0, selectedProfileID: selectedProfileID)
                            && $0.occursOnLocalDay(selectedDate, calendar: calendar)
                    }
                    .sorted { $0.localStartMinute(calendar: calendar) > $1.localStartMinute(calendar: calendar) }

                let appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
                    predicate: #Predicate<DoctorAppointment> { appointment in
                        appointment.profileID == selectedProfileID &&
                            appointment.startDate >= start &&
                            appointment.startDate < end
                    },
                    sortBy: [SortDescriptor(\DoctorAppointment.startDate, order: .reverse)]
                )
                appointments = try modelContext.fetch(appointmentDescriptor)

                let milestoneDescriptor = FetchDescriptor<MilestoneEntry>(
                    predicate: #Predicate<MilestoneEntry> { milestone in
                        milestone.profileID == selectedProfileID &&
                            milestone.date >= start &&
                            milestone.date < end
                    },
                    sortBy: [SortDescriptor(\MilestoneEntry.date, order: .reverse)]
                )
                milestones = try modelContext.fetch(milestoneDescriptor)
            } else {
                let eventDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.startDate >= eventFetchStart &&
                            event.startDate < eventFetchEnd
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                events = try modelContext.fetch(eventDescriptor)
                    .filter {
                        Self.visibleDayEvent($0, selectedProfileID: selectedProfileID)
                            && $0.occursOnLocalDay(selectedDate, calendar: calendar)
                    }
                    .sorted { $0.localStartMinute(calendar: calendar) > $1.localStartMinute(calendar: calendar) }

                let appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
                    predicate: #Predicate<DoctorAppointment> { appointment in
                        appointment.startDate >= start && appointment.startDate < end
                    },
                    sortBy: [SortDescriptor(\DoctorAppointment.startDate, order: .reverse)]
                )
                appointments = try modelContext.fetch(appointmentDescriptor)

                let milestoneDescriptor = FetchDescriptor<MilestoneEntry>(
                    predicate: #Predicate<MilestoneEntry> { milestone in
                        milestone.date >= start && milestone.date < end
                    },
                    sortBy: [SortDescriptor(\MilestoneEntry.date, order: .reverse)]
                )
                milestones = try modelContext.fetch(milestoneDescriptor)
            }
        } catch {
            events = []
            appointments = []
            milestones = []
        }
    }

    static func visibleDayEvent(_ event: CareEvent, selectedProfileID: UUID?) -> Bool {
        event.matchesProfile(selectedProfileID)
            && !event.isTimerDraft
            && EventVisibilityStore.isVisible(event)
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

    private func eventChanged(
        _ event: CareEvent,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false
    ) async {
        event.profileID = event.profileID ?? profile?.id
        await EventMutationService.eventDidChange(
            event,
            profile: profile,
            context: modelContext,
            settings: settings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes,
            refreshPrediction: refreshPrediction,
            waitForSystemIntegrations: waitForSystemIntegrations
        )
        refreshDayData()
    }

    private func open(_ event: CareEvent) {
        if event.type == .feed, event.feedKind == .solid {
            let router = DeepLinkRouter.shared
            router.openSolids(
                .solidMeal(event.id),
                profileID: event.profileID,
                returningTo: .reports
            )
            return
        }
        if event.isTimerDraft {
            activeTimerToEdit = editableTimer(event)
        } else {
            editorRoute = EventEditorRoute(type: event.type, event: event)
        }
    }

    private func confirmDelete(_ event: CareEvent) {
        eventPendingDelete = event
        showingDeleteEventConfirmation = true
    }

    private func confirmDelete(_ milestone: MilestoneEntry) {
        milestonePendingDelete = milestone
        showingDeleteMilestoneConfirmation = true
    }

    private func confirmDelete(_ appointment: DoctorAppointment) {
        appointmentPendingDelete = appointment
        showingDeleteAppointmentConfirmation = true
    }

    private func adjustStart(of event: CareEvent, to date: Date) {
        let draft = timerDraftForMutation(event)
        EventTimerService.adjustStartDate(draft, to: date)
        persistTimerMutation(draft)
    }

    private func stop(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventMutationService.stopTimer(draft, context: modelContext)
        persistTimerMutation(draft)
    }

    private func resume(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventMutationService.resumeTimer(draft, context: modelContext)
        persistTimerMutation(draft)
    }

    private func reset(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventMutationService.resetTimer(draft, context: modelContext)
        persistTimerMutation(draft)
    }

    private func setStartTimeZone(_ identifier: String, for event: CareEvent) {
        let draft = timerDraftForMutation(event)
        draft.startTimeZoneIdentifier = identifier
        persistTimerMutation(draft)
    }

    private func setEndTimeZone(_ identifier: String, for event: CareEvent) {
        let draft = timerDraftForMutation(event)
        draft.endTimeZoneIdentifier = identifier
        persistTimerMutation(draft)
    }

    @discardableResult
    private func save(_ event: CareEvent, endDate: Date? = nil) -> Bool {
        let draft = timerDraftForMutation(event)
        let didFinish = EventMutationService.saveTimer(
            draft,
            context: modelContext,
            endDate: endDate
        )
        guard didFinish else {
            return !draft.isTimerDraft && draft.endDate != nil
        }
        scheduleTimerSystemRefresh(
            activeTimers: activeTimerDrafts(replacing: draft),
            scheduleNotification: true,
            refreshPredictionFor: draft,
            persistenceRequest: EventMutationService.timerPersistenceRequest(for: draft)
        )
        return true
    }

    private func switchNursingSide(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventTimerService.switchNursingSide(draft, context: modelContext)
        persistTimerMutation(draft)
    }

    private func setNursingSide(_ side: NursingSide, for event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventTimerService.setNursingSide(draft, to: side, context: modelContext)
        persistTimerMutation(draft)
    }

    private func persistTimerMutation(_ event: CareEvent) {
        scheduleTimerSystemRefresh(
            activeTimers: activeTimerDrafts(replacing: event),
            scheduleNotification: EventMutationService.shouldRefreshLittleWindowAlert(
                after: event
            ),
            persistenceRequest: EventMutationService.timerPersistenceRequest(for: event)
        )
    }

    private func discardTimer(_ event: CareEvent) {
        guard event.isTimerDraft else { return }
        let eventID = event.id
        let scheduleNotification = EventMutationService.shouldRefreshLittleWindowAlert(
            after: event
        )
        guard EventMutationService.discardTimer(
            event,
            context: modelContext,
            deleteFromContext: false
        ) else {
            return
        }
        scheduleTimerSystemRefresh(
            activeTimers: activeTimerDrafts(removing: eventID),
            scheduleNotification: scheduleNotification,
            persistenceRequest: EventMutationService.timerPersistenceRequest(
                for: event,
                deleting: true
            ),
            discardedTimerID: eventID
        )
    }

    private func activeTimerDrafts(
        replacing replacement: CareEvent? = nil,
        removing removedID: UUID? = nil
    ) -> [CareEvent] {
        let selectedProfileID = profile?.id
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate<CareEvent> { event in
                event.profileID == selectedProfileID && event.timerStateRawValue != nil
            },
            sortBy: [SortDescriptor(\CareEvent.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        var values = EventVisibilityStore.visibleEvents(
            in: (try? modelContext.fetch(descriptor)) ?? []
        )
        if let removedID {
            values.removeAll { $0.id == removedID }
        }
        if let replacement {
            values.removeAll { $0.id == replacement.id }
            if replacement.isTimerDraft {
                values.append(replacement)
            }
        }
        return values
    }

    private func scheduleTimerSystemRefresh(
        activeTimers: [CareEvent],
        scheduleNotification: Bool,
        refreshPredictionFor event: CareEvent? = nil,
        persistenceRequest: TimerPersistenceRequest? = nil,
        discardedTimerID: UUID? = nil
    ) {
        timerSystemRefreshTask?.cancel()
        let refreshRevision = UUID()
        timerSystemRefreshRevision = refreshRevision
        let currentProfile = profile
        let currentRecords = scopedRecords
        let currentSettings = settings
        let alertsEnabled = notificationsEnabled
        let leadMinutes = notificationLeadMinutes
        let surfaceRevision = Date()
        let timerSnapshot = WidgetSnapshotService.refreshActiveTimerState(
            profile: currentProfile,
            events: activeTimers,
            now: surfaceRevision
        )
        let container = modelContext.container
        let profileID = currentProfile?.id
        let profileName = currentProfile?.name ?? "Baby"
        let currentPrediction = currentRecords
            .lazy
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }?
            .prediction
        let hasSleepDraft = activeTimers.contains {
            $0.isSleepBlock && $0.isTimerDraft
        }

        Task.detached(priority: .utility) {
            await LiveActivityManager.shared.synchronize(
                timer: timerSnapshot,
                revision: surfaceRevision
            )
        }

        if event == nil {
            // Pausing, resuming, and discarding drafts do not alter completed
            // history. Persist the one row without starting a full prediction
            // scan or retaining the Reports interaction transaction.
            timerSystemRefreshTask = Task.detached(priority: .userInitiated) {
                let persisted: Bool
                if let persistenceRequest {
                    persisted = await EventMutationService.persistTimerMutation(
                        persistenceRequest,
                        container: container
                    )
                } else {
                    persisted = true
                }
                guard !Task.isCancelled else { return }
                if !persisted {
                    await MainActor.run {
                        guard timerSystemRefreshRevision == refreshRevision else { return }
                        if let discardedTimerID {
                            EventVisibilityStore.restore(discardedTimerID)
                        }
                        timerSystemRefreshTask = nil
                    }
                    return
                }
                if scheduleNotification {
                    await NotificationManager.shared.schedule(
                        prediction: currentPrediction,
                        babyName: profileName,
                        profileID: profileID,
                        leadMinutes: leadMinutes,
                        enabled: alertsEnabled,
                        isSleeping: hasSleepDraft
                    )
                }
                guard !Task.isCancelled else { return }
                WatchConnectivityService.shared.scheduleCurrentStatePublish()
                await MainActor.run {
                    guard timerSystemRefreshRevision == refreshRevision else { return }
                    timerSystemRefreshTask = nil
                }
            }
            return
        }

        timerSystemRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            if let persistenceRequest,
               !(await EventMutationService.persistTimerMutation(
                    persistenceRequest,
                    container: modelContext.container
               )) {
                if let discardedTimerID {
                    EventVisibilityStore.restore(discardedTimerID)
                }
                refreshDayData()
                timerSystemRefreshTask = nil
                return
            }
            guard !Task.isCancelled else { return }
            if let event {
                await EventMutationService.eventDidChange(
                    event,
                    profile: currentProfile,
                    context: modelContext,
                    settings: currentSettings,
                    notificationsEnabled: alertsEnabled,
                    notificationLeadMinutes: leadMinutes,
                    refreshPrediction: true,
                    waitForSystemIntegrations: false,
                    eventAlreadyPersisted: persistenceRequest != nil
                )
            }
            guard !Task.isCancelled else { return }
            refreshDayData()
            timerSystemRefreshTask = nil
        }
    }

    private func editableTimer(_ event: CareEvent) -> CareEvent {
        event.modelContext == nil
            ? event
            : EventMutationService.detachedTimerCopy(event)
    }

    private func timerDraftForMutation(_ event: CareEvent) -> CareEvent {
        let draft = editableTimer(event)
        if activeTimerToEdit?.id == event.id, activeTimerToEdit !== draft {
            activeTimerToEdit = draft
        }
        return draft
    }

    private func delete(_ event: CareEvent) {
        let eventID = event.id
        let currentProfile = profile
        let currentSettings = settings
        let alertsEnabled = notificationsEnabled
        let leadMinutes = notificationLeadMinutes

        EventVisibilityStore.markPendingDeletion(eventID)
        events.removeAll { $0.id == eventID }

        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let outcome = await EventMutationService.delete(
                event,
                profile: currentProfile,
                context: modelContext,
                settings: currentSettings,
                notificationsEnabled: alertsEnabled,
                notificationLeadMinutes: leadMinutes
            )
            if !outcome.didPersist {
                EventVisibilityStore.restore(eventID)
            }
            refreshDayData()
        }
    }

    private func delete(_ milestone: MilestoneEntry) {
        PhotoAttachmentStore.deleteAttachments(
            with: milestone.photoAttachmentIDs,
            context: modelContext
        )
        modelContext.delete(milestone)
        guard PersistenceService.save(context: modelContext) else { return }
        refreshDayData()
    }

    private func delete(_ appointment: DoctorAppointment) {
        Task {
            await NotificationManager.shared.cancelAppointmentReminders(
                appointmentID: appointment.id
            )
            modelContext.delete(appointment)
            guard PersistenceService.save(context: modelContext) else { return }
            refreshDayData()
        }
    }
}

private struct CalendarAppointmentRow: View {
    let appointment: DoctorAppointment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appointment.appointmentType.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.indigo)
                .frame(width: 36, height: 36)
                .background(Color.indigo.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Appointment: \(appointment.displayTitle)")
                        .font(.subheadline.weight(.semibold))
                    if appointment.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text("\(DateFormatting.timeString(from: appointment.startDate, timeZone: appointment.timeZone, includesTimeZone: true)) · \(appointment.appointmentType.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct CalendarMilestoneRow: View {
    let milestone: MilestoneEntry
    let birthDate: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: milestone.category.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(milestone.category.tint)
                .frame(width: 36, height: 36)
                .background(milestone.category.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Milestone: \(milestone.title)")
                        .font(.subheadline.weight(.semibold))
                    if milestone.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                    }
                }
                if let birthDate {
                    Text(milestone.ageAtMilestoneDescription(birthDate: birthDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct DayTimelinePlacement: Equatable {
    let eventID: UUID
    let startMinute: Double
    let endMinute: Double
    let column: Int
    let columnCount: Int
}

enum DayTimelineLayout {
    private struct Interval {
        let eventID: UUID
        let startMinute: Double
        let endMinute: Double
    }

    static func placements(
        for events: [CareEvent],
        on date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayTimelinePlacement] {
        let intervals = events.compactMap { event -> Interval? in
            guard event.occursOnLocalDay(date, calendar: calendar) else { return nil }
            let rawEnd = event.endDate ?? (event.isActiveTimer ? now : event.startDate)
            let startMinute = max(0, event.localStartMinute(calendar: calendar))
            let elapsedMinutes = max(0, rawEnd.timeIntervalSince(event.startDate) / 60)
            let actualEndMinute = min(24 * 60, startMinute + elapsedMinutes)
            let displayEndMinute = min(24 * 60, max(actualEndMinute, startMinute + 30))
            return Interval(
                eventID: event.id,
                startMinute: startMinute,
                endMinute: displayEndMinute
            )
        }
        .sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            return $0.endMinute > $1.endMinute
        }

        var result = [DayTimelinePlacement]()
        var group = [Interval]()
        var groupEnd = 0.0

        func appendGroup(_ values: [Interval]) {
            guard !values.isEmpty else { return }
            var columnEnds = [Double]()
            var assignments = [(Interval, Int)]()
            for interval in values {
                if let available = columnEnds.firstIndex(where: { $0 <= interval.startMinute }) {
                    columnEnds[available] = interval.endMinute
                    assignments.append((interval, available))
                } else {
                    assignments.append((interval, columnEnds.count))
                    columnEnds.append(interval.endMinute)
                }
            }
            let columnCount = max(1, columnEnds.count)
            result.append(contentsOf: assignments.map { interval, column in
                DayTimelinePlacement(
                    eventID: interval.eventID,
                    startMinute: interval.startMinute,
                    endMinute: interval.endMinute,
                    column: column,
                    columnCount: columnCount
                )
            })
        }

        for interval in intervals {
            if !group.isEmpty, interval.startMinute >= groupEnd {
                appendGroup(group)
                group.removeAll(keepingCapacity: true)
                groupEnd = 0
            }
            group.append(interval)
            groupEnd = max(groupEnd, interval.endMinute)
        }
        appendGroup(group)
        return result
    }
}

private struct CalendarDayView: View {
    let date: Date
    let events: [CareEvent]
    let edit: (CareEvent) -> Void
    let delete: (CareEvent) -> Void

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 68
    private let timeColumnWidth: CGFloat = 58
    private let eventGap: CGFloat = 5
    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        GeometryReader { proxy in
                            let placements = DayTimelineLayout.placements(
                                for: events,
                                on: date,
                                now: timeline.date,
                                calendar: calendar
                            )
                            ZStack(alignment: .topLeading) {
                                hourGrid(width: proxy.size.width)
                                ForEach(placements, id: \.eventID) { placement in
                                    if let event = events.first(where: { $0.id == placement.eventID }) {
                                        eventBlock(
                                            event,
                                            placement: placement,
                                            availableWidth: proxy.size.width
                                        )
                                    }
                                }
                                currentTimeIndicator(width: proxy.size.width, now: timeline.date)
                            }
                        }
                        .frame(height: hourHeight * 24)
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 590)
                .task(id: calendar.startOfDay(for: date)) {
                    await Task.yield()
                    scrollProxy.scrollTo(scrollTargetHour, anchor: .top)
                }
            }
        }
        .background(AppTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(AppTheme.line, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var dayHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(date.formatted(.dateTime.month(.wide).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Times use each entry's recorded zone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                legendDot(.indigo, "Sleep")
                legendDot(.orange, "Care")
                legendDot(.teal, "Other")
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func hourGrid(width: CGFloat) -> some View {
        ForEach(0...24, id: \.self) { hour in
            let y = CGFloat(hour) * hourHeight
            Color.clear
                .frame(width: 1, height: 1)
                .offset(y: y)
                .id(hour)
            Path { path in
                path.move(to: CGPoint(x: timeColumnWidth, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(Color.primary.opacity(hour % 6 == 0 ? 0.13 : 0.075), lineWidth: 0.5)

            if hour < 24 {
                Text(hourLabel(hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth - 8, alignment: .trailing)
                    .offset(y: max(0, y - 7))
            }
        }
    }

    @ViewBuilder
    private func currentTimeIndicator(width: CGFloat, now: Date) -> some View {
        if calendar.isDateInToday(date) {
            let minute = min(
                24 * 60,
                max(0, now.timeIntervalSince(calendar.startOfDay(for: date)) / 60)
            )
            let y = CGFloat(minute / 60) * hourHeight
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(Color.red.opacity(0.72))
                    .frame(height: 1)
            }
            .frame(width: width - timeColumnWidth + 4)
            .offset(x: timeColumnWidth - 4, y: y - 3.5)
            .allowsHitTesting(false)
        }
    }

    private var scrollTargetHour: Int {
        let referenceDate: Date
        if calendar.isDateInToday(date) {
            referenceDate = Date()
        } else {
            let earliestMinute = events.map { $0.localStartMinute(calendar: calendar) }.min()
            return max(0, Int((earliestMinute ?? 60) / 60) - 1)
        }
        return max(0, calendar.component(.hour, from: referenceDate) - 1)
    }

    private func eventBlock(
        _ event: CareEvent,
        placement: DayTimelinePlacement,
        availableWidth: CGFloat
    ) -> some View {
        let eventAreaWidth = availableWidth - timeColumnWidth - 8
        let totalGaps = CGFloat(max(0, placement.columnCount - 1)) * eventGap
        let columnWidth = max(48, (eventAreaWidth - totalGaps) / CGFloat(placement.columnCount))
        let x = timeColumnWidth
            + CGFloat(placement.column) * (columnWidth + eventGap)
        let y = CGFloat(placement.startMinute / 60) * hourHeight + 2
        let height = max(
            40,
            CGFloat((placement.endMinute - placement.startMinute) / 60) * hourHeight - 4
        )

        return Button {
            edit(event)
        } label: {
            CalendarEventBlock(event: event, height: height)
        }
        .buttonStyle(.plain)
        .frame(width: columnWidth, height: height)
        .offset(x: x, y: y)
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                edit(event)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete(event)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let value = calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: calendar.startOfDay(for: date)
        ) else {
            return ""
        }
        return Self.hourFormatter.string(from: value)
    }
}

private struct CalendarEventBlock: View {
    let event: CareEvent
    let height: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.type.tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: event.type.systemImage(for: event.profileTypeSnapshot))
                        .font(.caption2.weight(.bold))
                    Text(event.displayTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if event.isActiveTimer {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }
                if height >= 52 {
                    Text(timeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if height >= 76, let detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(event.type.tint)
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.type.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(event.type.tint.opacity(0.2), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens event details")
    }

    private var timeText: String {
        if let endDate = event.endDate {
            return DateFormatting.window(
                start: event.startDate,
                end: endDate,
                startTimeZone: event.startTimeZone,
                endTimeZone: event.endTimeZone,
                includesTimeZones: event.shouldShowTimeZoneInTimeline
            )
        }
        return event.isActiveTimer
            ? "\(DateFormatting.timeString(from: event.startDate, timeZone: event.startTimeZone, includesTimeZone: event.shouldShowTimeZoneInTimeline)) - now"
            : DateFormatting.timeString(
                from: event.startDate,
                timeZone: event.startTimeZone,
                includesTimeZone: event.shouldShowTimeZoneInTimeline
            )
    }

    private var detailText: String? {
        if let duration = event.timelineDurationDescription {
            return duration
        }
        if event.type == .feed, let amount = event.amountOz {
            return String(format: "%.1f oz", amount)
        }
        return event.caregiverName
    }
}

private struct SummaryGrid: View {
    @Environment(\.careProfileType) private var profileType
    let summary: DailySummary

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            if profileType == .dog {
                SummaryCell("Food", "\(summary.dogFoodCount)", icon: "fork.knife", color: .orange)
                SummaryCell("Water", "\(summary.waterCount)", icon: "drop.fill", color: .cyan)
                SummaryCell("Treats", "\(summary.treatCount)", icon: "birthday.cake.fill", color: .pink)
                SummaryCell(
                    "Potty",
                    "\(summary.pottyCount) logs, \(summary.pottyAccidents) accidents",
                    icon: "pawprint.fill",
                    color: .teal
                )
                SummaryCell("Walks", DurationFormatting.string(seconds: summary.walkTime), icon: "figure.walk", color: .green)
                SummaryCell("Rest", DurationFormatting.string(seconds: summary.restTime), icon: "bed.double.fill", color: .indigo)
                SummaryCell("Training", DurationFormatting.string(seconds: summary.trainingTime), icon: "graduationcap.fill", color: .purple)
                SummaryCell("Grooming", DurationFormatting.string(seconds: summary.groomingTime), icon: "comb.fill", color: .mint)
                SummaryCell("Medicine", "\(summary.medicineNames.count)", icon: "cross.case.fill", color: .red)
                SummaryCell("Symptoms", "\(summary.symptomCount)", icon: "exclamationmark.triangle.fill", color: .orange)
                SummaryCell("Vaccines", "\(summary.vaccineCount)", icon: "syringe.fill", color: .blue)
                SummaryCell("Glucose", "\(summary.glucoseCount)", icon: "drop.triangle.fill", color: .pink)
            } else if profileType == .adult {
                SummaryCell("Medicine", "\(summary.medicineNames.count)", icon: "cross.case.fill", color: .red)
                SummaryCell("Symptoms", "\(summary.symptomCount)", icon: "exclamationmark.triangle.fill", color: .orange)
                SummaryCell("Blood pressure", "\(summary.bloodPressureCount)", icon: "heart.text.square.fill", color: .red)
                SummaryCell("Pulse", "\(summary.heartRateCount)", icon: "waveform.path.ecg", color: .pink)
                SummaryCell("Oxygen", "\(summary.oxygenSaturationCount)", icon: "lungs.fill", color: .blue)
                SummaryCell("Respiratory rate", "\(summary.respiratoryRateCount)", icon: "wind", color: .cyan)
                SummaryCell("Glucose", "\(summary.glucoseCount)", icon: "drop.triangle.fill", color: .purple)
                SummaryCell("Temperature", "\(summary.temperatureCount)", icon: "thermometer.medium", color: .red)
                SummaryCell("Pain", "\(summary.painCount)", icon: "bandage.fill", color: .orange)
                SummaryCell("Weight & height", "\(summary.growthCount)", icon: "ruler.fill", color: .green)
                SummaryCell("Sleep", DurationFormatting.string(seconds: summary.totalSleep), icon: "moon.fill", color: .indigo)
                SummaryCell("Activities", "\(summary.activityCount)", icon: "figure.play", color: .green)
                SummaryCell("Custom", "\(summary.customCount)", icon: "sparkles", color: .gray)
            } else {
                SummaryCell("Total sleep", DurationFormatting.string(seconds: summary.totalSleep), icon: "moon.fill", color: .indigo)
                SummaryCell("Day sleep", DurationFormatting.string(seconds: summary.daytimeSleep), icon: "sun.haze.fill", color: .orange)
                SummaryCell("Naps", "\(summary.napCount)", icon: "bed.double.fill", color: .purple)
                SummaryCell("Average nap", DurationFormatting.string(seconds: summary.averageNap), icon: "clock.fill", color: .blue)
                SummaryCell("Feeds", "\(summary.feedCount)", icon: "waterbottle.fill", color: .orange)
                SummaryCell(
                    "Bottle",
                    "\(summary.bottleFeedCount) logs, \(String(format: "%.1f oz", summary.bottleOunces))",
                    icon: "drop.fill",
                    color: .cyan
                )
                SummaryCell("Nursing", DurationFormatting.string(seconds: summary.nursingTotal), icon: "figure.and.child.holdinghands", color: .pink)
                SummaryCell(
                    "Pumping",
                    "\(summary.pumpingSessions) sessions, \(String(format: "%.1f oz", summary.pumpingOunces))",
                    icon: "drop.circle.fill",
                    color: .cyan
                )
                SummaryCell(
                    "Solids",
                    "\(summary.solidFeedCount) tastes, \(summary.solidSensitivityObservations) notes",
                    icon: "carrot.fill",
                    color: .orange
                )
                SummaryCell(
                    "Diapers",
                    "\(summary.wetDiapers) pee, \(summary.dirtyDiapers) poo, \(summary.bothDiapers) mixed",
                    icon: "humidity.fill",
                    color: .teal
                )
                SummaryCell(
                    "Potty",
                    "\(summary.childPottyCount) logs, \(summary.childPottyAccidents) accidents",
                    icon: "figure.child",
                    color: .teal
                )
                SummaryCell("Tummy time", DurationFormatting.string(seconds: summary.tummyTime), icon: "figure.play", color: .green)
                SummaryCell("Reading", DurationFormatting.string(seconds: summary.readingTime), icon: "book.fill", color: .blue)
                SummaryCell("Activities", "\(summary.activityCount)", icon: "figure.play", color: .green)
                SummaryCell("Medicine", "\(summary.medicineNames.count)", icon: "cross.case.fill", color: .red)
                SummaryCell("Baths", "\(summary.bathCount)", icon: "bathtub.fill", color: .cyan)
                SummaryCell("Growth", "\(summary.growthCount)", icon: "ruler.fill", color: .green)
                SummaryCell("Temperature", "\(summary.temperatureCount)", icon: "thermometer.medium", color: .red)
                SummaryCell("Custom", "\(summary.customCount)", icon: "sparkles", color: .gray)
            }
        }
    }
}

private struct CareProfileTypeKey: EnvironmentKey {
    static let defaultValue: CareProfileType = .child
}

private extension EnvironmentValues {
    var careProfileType: CareProfileType {
        get { self[CareProfileTypeKey.self] }
        set { self[CareProfileTypeKey.self] = newValue }
    }
}

private struct SummaryCell: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    init(_ title: String, _ value: String, icon: String, color: Color) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 12))
    }
}
