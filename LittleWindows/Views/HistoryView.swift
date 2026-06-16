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

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query private var records: [SleepPredictionRecord]
    @AppStorage("feedAdjustmentEnabled") private var feedAdjustmentEnabled = true
    @AppStorage("nursingAdjustmentEnabled") private var nursingAdjustmentEnabled = true
    @AppStorage("bedtimePredictionEnabled") private var bedtimePredictionEnabled = true
    @AppStorage("predictionNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 10
    @AppStorage("customWakeMinimum") private var customWakeMinimum = 0.0
    @AppStorage("customWakeMaximum") private var customWakeMaximum = 0.0
    @AppStorage("historyDisplayMode") private var displayModeRawValue = HistoryDisplayMode.list.rawValue
    @State private var selectedDate = Date()
    @State private var events: [BabyEvent] = []
    @State private var appointments: [DoctorAppointment] = []
    @State private var milestones: [MilestoneEntry] = []
    @State private var editorRoute: EventEditorRoute?
    @State private var activeTimerToEdit: BabyEvent?
    @StateObject private var profileService = ProfileService.shared

    init() {
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.actualSleepEventID == nil || record.generatedAt >= recentCutoff
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        _records = Query(recordDescriptor)

        if let value = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_HISTORY_DATE"],
           let date = ISO8601DateFormatter().date(from: value) {
            _selectedDate = State(initialValue: date)
        }
    }

    private var profile: BabyProfile? {
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
            get: { HistoryDisplayMode(rawValue: displayModeRawValue) ?? .list },
            set: { displayModeRawValue = $0.rawValue }
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

            summarySection

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

            historySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Calendar")
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
                    save: { save(event) },
                    discard: { delete(event) },
                    switchNursingSide: event.type == .nursing
                        ? { switchNursingSide(event) }
                        : nil,
                    setNursingSide: event.type == .nursing
                        ? { setNursingSide($0, for: event) }
                        : nil
                )
            }
        }
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

            DatePicker("History date", selection: $selectedDate, displayedComponents: .date)
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
                        selectedDate = Date()
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
                .padding(14)
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
                            delete: delete
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
                            delete(appointment)
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
                            delete(milestone)
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
                            delete(event)
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
            selectedDate = date
        }
    }

    private func refreshDayData() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.startOfNextDay(for: selectedDate)
        let selectedProfileID = profile?.id

        do {
            let eventDescriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { event in
                    event.startDate >= start && event.startDate < end && event.endDate != nil
                },
                sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
            )
            events = try modelContext.fetch(eventDescriptor)
                .filter { $0.matchesProfile(selectedProfileID) }

            let appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
                predicate: #Predicate<DoctorAppointment> { appointment in
                    appointment.startDate >= start && appointment.startDate < end
                },
                sortBy: [SortDescriptor(\DoctorAppointment.startDate, order: .reverse)]
            )
            appointments = try modelContext.fetch(appointmentDescriptor)
                .filter { $0.matchesProfile(selectedProfileID) }

            let milestoneDescriptor = FetchDescriptor<MilestoneEntry>(
                predicate: #Predicate<MilestoneEntry> { milestone in
                    milestone.date >= start && milestone.date < end
                },
                sortBy: [SortDescriptor(\MilestoneEntry.date, order: .reverse)]
            )
            milestones = try modelContext.fetch(milestoneDescriptor)
                .filter { $0.matchesProfile(selectedProfileID) }
        } catch {
            events = []
            appointments = []
            milestones = []
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

    private func eventChanged(
        _ event: BabyEvent,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false
    ) async {
        event.profileID = event.profileID ?? profile?.id
        await EventMutationService.eventDidChange(
            event,
            profile: profile,
            events: recentPredictionEvents(including: event),
            records: scopedRecords,
            context: modelContext,
            settings: settings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes,
            refreshPrediction: refreshPrediction,
            waitForSystemIntegrations: waitForSystemIntegrations
        )
        refreshDayData()
    }

    private func recentPredictionEvents(including event: BabyEvent? = nil) -> [BabyEvent] {
        let selectedProfileID = profile?.id
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var descriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { value in
                value.startDate >= cutoff
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 900
        var values = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.matchesProfile(selectedProfileID) }
        if let event, !values.contains(where: { $0.id == event.id }) {
            values.append(event)
        }
        return values
    }

    private func open(_ event: BabyEvent) {
        if event.isTimerDraft {
            activeTimerToEdit = event
        } else {
            editorRoute = EventEditorRoute(type: event.type, event: event)
        }
    }

    private func adjustStart(of event: BabyEvent, to date: Date) {
        EventTimerService.adjustStartDate(event, to: date)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
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
        }
    }

    private func save(_ event: BabyEvent) {
        EventMutationService.saveTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: true,
                waitForSystemIntegrations: true
            )
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

    private func delete(_ event: BabyEvent) {
        Task {
            await EventMutationService.delete(
                event,
                profile: profile,
                events: recentPredictionEvents(including: event),
                records: scopedRecords,
                context: modelContext,
                settings: settings,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes
            )
            refreshDayData()
        }
    }

    private func delete(_ milestone: MilestoneEntry) {
        modelContext.delete(milestone)
        try? modelContext.save()
        refreshDayData()
    }

    private func delete(_ appointment: DoctorAppointment) {
        Task {
            await NotificationManager.shared.cancelAppointmentReminders(
                appointmentID: appointment.id
            )
            modelContext.delete(appointment)
            try? modelContext.save()
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
                Text("\(DateFormatting.time.string(from: appointment.startDate)) · \(appointment.appointmentType.displayName)")
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
        for events: [BabyEvent],
        on date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayTimelinePlacement] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.startOfNextDay(for: date)
        let intervals = events.compactMap { event -> Interval? in
            guard event.startDate >= dayStart, event.startDate < dayEnd else { return nil }
            let rawEnd = event.endDate ?? (event.isActiveTimer ? now : event.startDate)
            let clippedEnd = min(dayEnd, max(event.startDate, rawEnd))
            let startMinute = max(0, event.startDate.timeIntervalSince(dayStart) / 60)
            let actualEndMinute = max(startMinute, clippedEnd.timeIntervalSince(dayStart) / 60)
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
    let events: [BabyEvent]
    let edit: (BabyEvent) -> Void
    let delete: (BabyEvent) -> Void

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
            referenceDate = events.min { $0.startDate < $1.startDate }?.startDate ?? date
        }
        return max(0, calendar.component(.hour, from: referenceDate) - 1)
    }

    private func eventBlock(
        _ event: BabyEvent,
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
    let event: BabyEvent
    let height: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.type.tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: event.type.systemImage)
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
            return DateFormatting.window(start: event.startDate, end: endDate)
        }
        return event.isActiveTimer
            ? "\(DateFormatting.time.string(from: event.startDate)) - now"
            : DateFormatting.time.string(from: event.startDate)
    }

    private var detailText: String? {
        if let duration = event.duration, duration >= 60 {
            return DurationFormatting.string(seconds: duration)
        }
        if event.type == .feed, let amount = event.amountOz {
            return String(format: "%.1f oz", amount)
        }
        if event.type == .nursing, event.totalNursingDurationSeconds > 0 {
            return DurationFormatting.string(seconds: event.totalNursingDurationSeconds)
        }
        return event.caregiverName
    }
}

private struct SummaryGrid: View {
    let summary: DailySummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryCell("Total sleep", DurationFormatting.string(seconds: summary.totalSleep), icon: "moon.fill", color: .indigo)
            SummaryCell("Day sleep", DurationFormatting.string(seconds: summary.daytimeSleep), icon: "sun.haze.fill", color: .orange)
            SummaryCell("Naps", "\(summary.napCount)", icon: "bed.double.fill", color: .purple)
            SummaryCell("Average nap", DurationFormatting.string(seconds: summary.averageNap), icon: "clock.fill", color: .blue)
            SummaryCell("Feeds", "\(summary.feedCount)", icon: "waterbottle.fill", color: .orange)
            SummaryCell("Bottle", String(format: "%.1f oz", summary.bottleOunces), icon: "drop.fill", color: .cyan)
            SummaryCell("Nursing", DurationFormatting.string(seconds: summary.nursingTotal), icon: "figure.and.child.holdinghands", color: .pink)
            SummaryCell(
                "Diapers",
                "\(summary.wetDiapers) pee, \(summary.dirtyDiapers) poo, \(summary.bothDiapers) mixed",
                icon: "humidity.fill",
                color: .teal
            )
            SummaryCell("Tummy time", DurationFormatting.string(seconds: summary.tummyTime), icon: "figure.play", color: .green)
            SummaryCell("Reading", DurationFormatting.string(seconds: summary.readingTime), icon: "book.fill", color: .blue)
            SummaryCell("Medicine", "\(summary.medicineNames.count)", icon: "cross.case.fill", color: .red)
            SummaryCell("Baths", "\(summary.bathCount)", icon: "bathtub.fill", color: .cyan)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}
