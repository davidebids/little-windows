import Charts
import SwiftData
import SwiftUI

struct InsightsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    let navigationTitle: String
    @StateObject private var viewModel = InsightsViewModel()
    @StateObject private var profileService = ProfileService.shared
    @State private var events: [BabyEvent] = []
    @State private var appointments: [DoctorAppointment] = []
    @State private var records: [SleepPredictionRecord] = []

    init(navigationTitle: String = "Insights") {
        self.navigationTitle = navigationTitle
    }

    private var profile: BabyProfile? {
        profileService.selectedProfile(in: profiles)
    }
    private var isDogProfile: Bool {
        profile?.profileType == .dog
    }
    private var scopedEvents: [BabyEvent] {
        events.filter { $0.matchesProfile(profile?.id) }
    }
    private var scopedAppointments: [DoctorAppointment] {
        appointments.filter { $0.matchesProfile(profile?.id) }
    }
    private var scopedRecords: [SleepPredictionRecord] {
        records.filter { $0.matchesProfile(profile?.id) }
    }

    private var refreshToken: String {
        [
            profile?.id.uuidString ?? "none",
            viewModel.selectedSection.rawValue,
            viewModel.selectedRange.rawValue,
            viewModel.comparesToPreviousPeriod.description,
            viewModel.customStartDate.timeIntervalSinceReferenceDate.description,
            viewModel.customEndDate.timeIntervalSinceReferenceDate.description
        ].joined(separator: "-")
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                controls

                if isDogProfile {
                    DogInsightsView(
                        profile: profile,
                        events: scopedEvents,
                        period: viewModel.selectedPeriodRange
                    )
                } else {
                    switch viewModel.selectedSection {
                    case .overview:
                        overview
                    case .sleep:
                        SleepInsightsView(snapshot: viewModel.snapshot)
                    case .wakeWindows:
                        WakeWindowInsightsView(snapshot: viewModel.snapshot)
                    case .feeding:
                        FeedingInsightsView(snapshot: viewModel.snapshot)
                    case .diapers:
                        DiaperInsightsView(snapshot: viewModel.snapshot)
                    case .activities:
                        ActivityInsightsView(snapshot: viewModel.snapshot)
                    case .medicine:
                        MedicineInsightsView(snapshot: viewModel.snapshot)
                    case .appointments:
                        AppointmentInsightsView(
                            appointments: scopedAppointments,
                            period: viewModel.selectedPeriodRange
                        )
                    case .growth:
                        GrowthInsightsView(
                            profile: profile,
                            events: scopedEvents
                        )
                    case .temperature:
                        TemperatureInsightsView(snapshot: viewModel.snapshot)
                    case .predictionAccuracy:
                        PredictionAccuracyInsightsView(snapshot: viewModel.snapshot)
                    }
                }

                Text("Insights are based only on your logged data and are not medical advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(AppTheme.background)
        .navigationTitle(navigationTitle)
        .task(id: refreshToken) {
            if let sectionName = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_INSIGHTS_SECTION"],
               let section = InsightsSection.allCases.first(where: {
                   $0.rawValue.caseInsensitiveCompare(sectionName) == .orderedSame
               }) {
                viewModel.selectedSection = section
            }
            refreshInsightsData()
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    dateRangePicker
                    Spacer(minLength: 8)
                    compareToggle
                }

                VStack(alignment: .leading, spacing: 10) {
                    dateRangePicker
                    compareToggle
                }
            }
            .opacity(isDogProfile || viewModel.selectedSection.usesDateRange ? 1 : 0.38)

            if viewModel.selectedRange == .custom && (isDogProfile || viewModel.selectedSection.usesDateRange) {
                VStack(spacing: 10) {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { viewModel.customStartDate },
                            set: { viewModel.updateCustomStart($0) }
                        ),
                        in: ...viewModel.customEndDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { viewModel.customEndDate },
                            set: { viewModel.updateCustomEnd($0) }
                        ),
                        in: viewModel.customStartDate...Date(),
                        displayedComponents: .date
                    )
                }
                .font(.subheadline)
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Label(filterStatusText, systemImage: filterStatusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !isDogProfile,
               viewModel.selectedSection.usesDateRange,
               viewModel.selectedSection.supportsPreviousPeriodComparison {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .padding(.top, 1)
                    Text(comparisonHelpText)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !isDogProfile {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(InsightsSection.allCases) { section in
                            Button {
                                withAnimation(.snappy) {
                                    viewModel.selectedSection = section
                                }
                            } label: {
                                Text(section.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(viewModel.selectedSection == section ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        viewModel.selectedSection == section ? Color.indigo : Color.primary.opacity(0.06),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .appSurface()
    }

    private var dateRangePicker: some View {
        Picker("Date range", selection: $viewModel.selectedRange) {
            ForEach(InsightsDateRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.menu)
        .disabled(!isDogProfile && !viewModel.selectedSection.usesDateRange)
    }

    @ViewBuilder
    private var compareToggle: some View {
        if !isDogProfile {
            Toggle(
                "Compare to previous period",
                isOn: $viewModel.comparesToPreviousPeriod
            )
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .disabled(!viewModel.selectedSection.supportsPreviousPeriodComparison)
        }
    }

    private var filterStatusText: String {
        if isDogProfile {
            return "\(viewModel.periodLabel) · dog care logs only"
        }
        if !viewModel.selectedSection.usesDateRange {
            return "Growth uses every measurement from birth."
        }
        if !viewModel.selectedSection.supportsPreviousPeriodComparison {
            return "\(viewModel.periodLabel) · comparison unavailable for this section"
        }
        return viewModel.periodLabel
    }

    private var filterStatusIcon: String {
        viewModel.selectedSection.usesDateRange ? "calendar" : "calendar.badge.minus"
    }

    private var comparisonHelpText: String {
        if viewModel.comparesToPreviousPeriod {
            return "Percentage badges compare supported metrics with \(viewModel.previousPeriodLabel)."
        }
        return "Turn on comparison to see percentage changes from the immediately preceding period."
    }

    private var eventFetchRange: ClosedRange<Date> {
        let period = viewModel.selectedPeriodRange
        guard viewModel.selectedSection.supportsPreviousPeriodComparison,
              viewModel.comparesToPreviousPeriod else {
            return period
        }
        let calendar = Calendar.current
        let dayCount = max(
            1,
            (calendar.dateComponents([.day], from: period.lowerBound, to: period.upperBound).day ?? 0) + 1
        )
        let previousStart = calendar.date(byAdding: .day, value: -dayCount, to: period.lowerBound)
            ?? period.lowerBound
        return previousStart...period.upperBound
    }

    private func refreshInsightsData() {
        let selectedProfileID = profile?.id
        let now = Date()
        let calendar = Calendar.current
        let range = eventFetchRange
        let rangeEnd = calendar.startOfNextDay(for: range.upperBound)

        do {
            if viewModel.selectedSection == .growth {
                let descriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.typeRawValue == "growth"
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate)]
                )
                events = try modelContext.fetch(descriptor)
                    .filter { $0.matchesProfile(selectedProfileID) }
            } else {
                let descriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.startDate >= range.lowerBound && event.startDate < rangeEnd
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate)]
                )
                events = try modelContext.fetch(descriptor)
                    .filter { $0.matchesProfile(selectedProfileID) }
            }

            let appointmentStart = calendar.date(byAdding: .month, value: -6, to: now) ?? range.lowerBound
            let appointmentEnd = calendar.date(byAdding: .year, value: 1, to: now) ?? rangeEnd
            let appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
                predicate: #Predicate<DoctorAppointment> { appointment in
                    appointment.startDate >= appointmentStart && appointment.startDate < appointmentEnd
                },
                sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
            )
            appointments = try modelContext.fetch(appointmentDescriptor)
                .filter { $0.matchesProfile(selectedProfileID) }

            let recordStart = calendar.date(byAdding: .day, value: -45, to: range.lowerBound) ?? range.lowerBound
            let recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
                predicate: #Predicate<SleepPredictionRecord> { record in
                    record.actualSleepEventID == nil || record.generatedAt >= recordStart
                },
                sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
            )
            records = try modelContext.fetch(recordDescriptor)
                .filter { $0.matchesProfile(selectedProfileID) }
        } catch {
            events = []
            appointments = []
            records = []
        }

        viewModel.refresh(
            profileName: profile?.name ?? "Baby",
            events: scopedEvents.filter { !$0.isTimerDraft },
            records: scopedRecords,
            now: now
        )
    }

    private var overview: some View {
        Group {
            InsightMetricGrid(metrics: viewModel.snapshot.overviewMetrics)
            InsightObservationsCard(trends: viewModel.snapshot.overviewTrends)

            InsightChartCard(
                title: "Daily sleep",
                subtitle: "Daytime and night sleep in hours",
                isEmpty: viewModel.snapshot.dailySleep.allSatisfy { $0.totalMinutes == 0 },
                emptyMessage: "Log completed sleep for at least one day."
            ) {
                Chart(viewModel.snapshot.dailySleep) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Hours", point.daytimeMinutes / 60)
                    )
                    .foregroundStyle(by: .value("Type", "Daytime"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Hours", point.nightMinutes / 60)
                    )
                    .foregroundStyle(by: .value("Type", "Night"))
                }
                .chartForegroundStyleScale(["Daytime": Color.orange, "Night": Color.indigo])
                .chartXAxis { compactDateAxis }
            }

            InsightChartCard(
                title: "Naps per day",
                subtitle: "Completed daytime sleep sessions",
                isEmpty: viewModel.snapshot.dailySleep.allSatisfy { $0.napCount == 0 }
            ) {
                Chart(viewModel.snapshot.dailySleep) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Naps", point.napCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.purple)
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Naps", point.napCount)
                    )
                    .foregroundStyle(.purple)
                }
                .chartXAxis { compactDateAxis }
            }

            InsightChartCard(
                title: "Wake-window trend",
                subtitle: "Minutes awake before each sleep",
                isEmpty: viewModel.snapshot.wakeWindows.isEmpty,
                emptyMessage: "Log at least two completed sleeps to calculate wake windows."
            ) {
                Chart(viewModel.snapshot.wakeWindows) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(.teal)
                    PointMark(
                        x: .value("Day", point.date),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(.teal)
                }
                .chartXAxis { compactDateAxis }
            }

            InsightChartCard(
                title: "Prediction error",
                subtitle: "Negative is early, positive is late",
                isEmpty: viewModel.snapshot.predictionErrors.isEmpty,
                emptyMessage: "Prediction accuracy appears after predictions are matched to actual sleep."
            ) {
                Chart(viewModel.snapshot.predictionErrors) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Error", point.errorMinutes)
                    )
                    .foregroundStyle(.indigo)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Error", point.errorMinutes)
                    )
                    .foregroundStyle(point.insideWindow ? .green : .orange)
                    RuleMark(y: .value("On time", 0))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .chartXAxis { compactDateAxis }
            }
        }
    }

    private var compactDateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.weekday(.narrow))
        }
    }
}
