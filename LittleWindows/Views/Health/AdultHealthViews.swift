import Charts
import SwiftData
import SwiftUI

private enum AdultHealthMetric: String, CaseIterable, Identifiable, Sendable {
    case bloodPressure
    case heartRate
    case oxygenSaturation
    case respiratoryRate
    case bloodGlucose
    case temperature
    case weight
    case pain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bloodPressure: "Blood pressure"
        case .heartRate: "Heart rate"
        case .oxygenSaturation: "Oxygen saturation"
        case .respiratoryRate: "Respiratory rate"
        case .bloodGlucose: "Blood glucose"
        case .temperature: "Temperature"
        case .weight: "Weight"
        case .pain: "Pain"
        }
    }

    var unit: String {
        switch self {
        case .bloodPressure: "mmHg"
        case .heartRate: "bpm"
        case .oxygenSaturation: "%"
        case .respiratoryRate: "breaths/min"
        case .bloodGlucose: "mg/dL"
        case .temperature: "°F"
        case .weight: "lb"
        case .pain: "/10"
        }
    }

    var eventType: EventType {
        switch self {
        case .bloodPressure: .bloodPressure
        case .heartRate: .heartRate
        case .oxygenSaturation: .oxygenSaturation
        case .respiratoryRate: .respiratoryRate
        case .bloodGlucose: .glucose
        case .temperature: .temperature
        case .weight: .growth
        case .pain: .pain
        }
    }
}

private struct AdultHealthChartPoint: Identifiable, Sendable {
    var eventID: UUID
    var date: Date
    var value: Double
    var series: String
    var id: String { "\(eventID.uuidString)-\(series)" }

    static func make(from event: CareEvent, metric: AdultHealthMetric) -> [AdultHealthChartPoint] {
        switch metric {
        case .bloodPressure:
            let details = event.healthObservationDetails
            guard let systolic = details.systolicBloodPressure,
                  let diastolic = details.diastolicBloodPressure else { return [] }
            return [
                AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(systolic), series: "Systolic"),
                AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(diastolic), series: "Diastolic")
            ]
        case .heartRate:
            guard let value = event.healthObservationDetails.heartRateBPM else { return [] }
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(value), series: "Heart rate")]
        case .oxygenSaturation:
            guard let value = event.healthObservationDetails.oxygenSaturationPercent else { return [] }
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: value, series: "Oxygen")]
        case .respiratoryRate:
            guard let value = event.healthObservationDetails.respiratoryRatePerMinute else { return [] }
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(value), series: "Respiratory rate")]
        case .bloodGlucose:
            let details = event.healthObservationDetails
            guard let value = details.bloodGlucoseValue else { return [] }
            let normalized = (details.bloodGlucoseUnit ?? .milligramsPerDeciliter)
                .milligramsPerDeciliter(from: value)
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: normalized, series: "Blood glucose")]
        case .temperature:
            guard let value = event.temperatureCelsius else { return [] }
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: value * 9 / 5 + 32, series: "Temperature")]
        case .weight:
            guard let value = event.canonicalWeightKilograms else { return [] }
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: value / 0.45359237, series: "Weight")]
        case .pain:
            guard let value = event.healthObservationDetails.painScore else { return [] }
            return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(value), series: "Pain")]
        }
    }
}

private struct AdultHealthLatestValue: Identifiable, Sendable {
    var title: String
    var value: String
    var date: Date
    var id: String { title }

    static func make(from event: CareEvent) -> AdultHealthLatestValue? {
        let metric: AdultHealthMetric
        let value: String?
        switch event.type {
        case .bloodPressure:
            metric = .bloodPressure
            let details = event.healthObservationDetails
            value = if let systolic = details.systolicBloodPressure,
                       let diastolic = details.diastolicBloodPressure {
                "\(systolic)/\(diastolic) mmHg"
            } else { nil }
        case .heartRate:
            metric = .heartRate
            value = event.healthObservationDetails.heartRateBPM.map { "\($0) bpm" }
        case .oxygenSaturation:
            metric = .oxygenSaturation
            value = event.healthObservationDetails.oxygenSaturationPercent.map {
                "\($0.formatted(.number.precision(.fractionLength(0...1))))%"
            }
        case .respiratoryRate:
            metric = .respiratoryRate
            value = event.healthObservationDetails.respiratoryRatePerMinute.map { "\($0)/min" }
        case .glucose:
            metric = .bloodGlucose
            let details = event.healthObservationDetails
            value = details.bloodGlucoseValue.map {
                let unit = details.bloodGlucoseUnit ?? .milligramsPerDeciliter
                return "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit.displayName)"
            }
        case .temperature:
            metric = .temperature
            value = event.temperatureCelsius.map {
                "\(($0 * 9 / 5 + 32).formatted(.number.precision(.fractionLength(1)))) °F"
            }
        case .growth:
            metric = .weight
            value = event.canonicalWeightKilograms.map {
                "\(($0 / 0.45359237).formatted(.number.precision(.fractionLength(0...1)))) lb"
            }
        case .pain:
            metric = .pain
            value = event.healthObservationDetails.painScore.map { "\($0)/10" }
        default:
            return nil
        }
        guard let value else { return nil }
        return AdultHealthLatestValue(
            title: metric.displayName,
            value: value,
            date: event.startDate
        )
    }
}

@ModelActor
private actor AdultHealthSummaryWorker {
    func latestValues(profileID: UUID) -> [AdultHealthLatestValue] {
        AdultHealthMetric.allCases.compactMap { metric in
            let rawValue = metric.eventType.rawValue
            var descriptor = FetchDescriptor<CareEvent>(
                predicate: #Predicate {
                    $0.profileID == profileID && $0.typeRawValue == rawValue
                },
                sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            guard let event = try? modelContext.fetch(descriptor).first else { return nil }
            return AdultHealthLatestValue.make(from: event)
        }
    }
}

@ModelActor
private actor AdultHealthTrendWorker {
    func points(profileID: UUID, metric: AdultHealthMetric) -> [AdultHealthChartPoint] {
        let typeRawValue = metric.eventType.rawValue
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.typeRawValue == typeRawValue
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 365
        let events = (try? modelContext.fetch(descriptor)) ?? []
        return events
            .flatMap { AdultHealthChartPoint.make(from: $0, metric: metric) }
            .sorted { $0.date < $1.date }
    }
}

private struct AdultHealthTrendRequest: Equatable {
    let profileID: UUID
    let metric: AdultHealthMetric
    let eventsRevision: Date?
}

private struct AdultHealthTrendSnapshot {
    let profileID: UUID
    let metric: AdultHealthMetric
    let points: [AdultHealthChartPoint]
}

private struct AdultHealthTrendSection: View {
    let metric: AdultHealthMetric
    let points: [AdultHealthChartPoint]
    let isLoading: Bool

    var body: some View {
        let visiblePoints = points
        Group {
            if isLoading {
                ProgressView("Loading trend…")
                    .frame(maxWidth: .infinity, minHeight: 210)
            } else if visiblePoints.isEmpty {
                ContentUnavailableView(
                    "No \(metric.displayName.lowercased()) entries",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Log a value to start this chart.")
                )
            } else {
                Chart(visiblePoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(metric.unit, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    if visiblePoints.count <= 120 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(metric.unit, point.value)
                        )
                        .foregroundStyle(by: .value("Series", point.series))
                    }
                }
                .frame(height: 210)
                .chartLegend(position: .bottom)
                .accessibilityIdentifier("adult-health.trend-loaded.\(metric.rawValue)")
            }
        }
    }
}

struct AdultHealthOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [CareEvent]
    @Query private var symptomEvents: [CareEvent]
    let profile: CareProfile
    @State private var selectedMetric: AdultHealthMetric = .bloodPressure
    @State private var eventTypeToLog: EventType?
    @State private var latestValues: [AdultHealthLatestValue] = []
    // Keep the result above the List row so iPad row recycling cannot restart
    // the fetch and repeatedly restore the loading placeholder during layout.
    @State private var trendSnapshot: AdultHealthTrendSnapshot?

    init(profile: CareProfile) {
        self.profile = profile
        let profileID = profile.id
        let healthTypes = [
            EventType.symptom.rawValue,
            EventType.bloodPressure.rawValue,
            EventType.heartRate.rawValue,
            EventType.oxygenSaturation.rawValue,
            EventType.respiratoryRate.rawValue,
            EventType.glucose.rawValue,
            EventType.temperature.rawValue,
            EventType.growth.rawValue,
            EventType.pain.rawValue
        ]
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID && healthTypes.contains($0.typeRawValue)
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        // The overview only renders 25 recent rows. Metric trends and exact
        // lifetime latest values are fetched independently below, so opening
        // Adult Care never materializes thousands of unrelated observations.
        descriptor.fetchLimit = 25
        _events = Query(descriptor)
        let symptomRawValue = EventType.symptom.rawValue
        var symptomDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.typeRawValue == symptomRawValue
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        symptomDescriptor.fetchLimit = 10
        _symptomEvents = Query(symptomDescriptor)
    }

    var body: some View {
        List {
            latestSection
            trendSection
            symptomsSection
            recentSection
            Section {
                Label("Charts show the values entered and do not interpret whether a result is normal or concerning.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("adult-health.overview")
        .navigationTitle("Health Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Log", systemImage: "plus") {
                    ForEach(EventType.cases(for: .adult).filter { healthEventTypes.contains($0) }) { type in
                        Button(type.displayName, systemImage: type.systemImage(for: .adult)) {
                            eventTypeToLog = type
                        }
                    }
                }
            }
        }
        .sheet(item: $eventTypeToLog) { type in
            NavigationStack {
                EventEditorView(type: type) { event in
                    persistHealthEvent(event)
                }
            }
        }
        .task(id: events.first?.updatedAt) {
            let container = modelContext.container
            let profileID = profile.id
            latestValues = await Task.detached(priority: .userInitiated) {
                let worker = AdultHealthSummaryWorker(modelContainer: container)
                return await worker.latestValues(profileID: profileID)
            }.value
        }
        .task(id: trendRequest) {
            await loadSelectedTrend(for: trendRequest)
        }
    }

    private var healthEventTypes: Set<EventType> {
        [.symptom, .bloodPressure, .heartRate, .oxygenSaturation,
         .respiratoryRate, .glucose, .temperature, .growth, .pain]
    }

    @ViewBuilder
    private var latestSection: some View {
        let latest = latestValues
        if !latest.isEmpty {
            Section("Latest") {
                ForEach(latest) { item in
                    LabeledContent(item.title) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.value).fontWeight(.semibold)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var trendSection: some View {
        return Section {
            Picker("Metric", selection: $selectedMetric) {
                ForEach(AdultHealthMetric.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("adult-health.metric-picker")
            AdultHealthTrendSection(
                metric: selectedMetric,
                points: visibleTrendPoints,
                isLoading: trendSnapshot?.profileID != profile.id ||
                    trendSnapshot?.metric != selectedMetric
            )
        } header: {
            AppSectionHeader(title: "Trends", subtitle: "Up to 365 recent entries")
        }
    }

    private var trendRequest: AdultHealthTrendRequest {
        AdultHealthTrendRequest(
            profileID: profile.id,
            metric: selectedMetric,
            eventsRevision: events.lazy.map(\.updatedAt).max()
        )
    }

    private var visibleTrendPoints: [AdultHealthChartPoint] {
        guard trendSnapshot?.profileID == profile.id,
              trendSnapshot?.metric == selectedMetric else {
            return []
        }
        return trendSnapshot?.points ?? []
    }

    private func loadSelectedTrend(for request: AdultHealthTrendRequest) async {
        let worker = AdultHealthTrendWorker(modelContainer: modelContext.container)
        let points = await worker.points(
            profileID: request.profileID,
            metric: request.metric
        )
        guard !Task.isCancelled,
              profile.id == request.profileID,
              selectedMetric == request.metric else {
            return
        }
        trendSnapshot = AdultHealthTrendSnapshot(
            profileID: request.profileID,
            metric: request.metric,
            points: points
        )
    }

    @ViewBuilder
    private var symptomsSection: some View {
        if !symptomEvents.isEmpty {
            Section("Symptoms") {
                ForEach(symptomEvents) { event in
                    NavigationLink {
                        healthEventEditor(event)
                    } label: {
                        let details = event.healthObservationDetails
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(details.symptomName ?? "Symptom")
                                    .font(.subheadline.weight(.semibold))
                                Text([
                                    details.symptomSeverity.map { "\($0)/10" },
                                    details.symptomBodyLocation,
                                    details.symptomResolved == true ? "resolved" : nil
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !events.isEmpty {
            Section("Recent health logs") {
                ForEach(events.prefix(25)) { event in
                    NavigationLink {
                        healthEventEditor(event)
                    } label: {
                        HStack {
                            Image(systemName: event.type.systemImage(for: .adult))
                                .foregroundStyle(event.type.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.displayTitle)
                                    .font(.subheadline)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func healthEventEditor(_ event: CareEvent) -> some View {
        EventEditorView(type: event.type, event: event) { savedEvent in
            persistHealthEvent(savedEvent)
        }
    }

    private func persistHealthEvent(_ event: CareEvent) {
        event.profileID = profile.id
        event.profileTypeSnapshot = .adult
        let container = modelContext.container
        Task {
            guard await EventMutationService.persistStandaloneEvent(
                event,
                container: container
            ) else { return }

            // Adult observations do not affect sleep predictions, reminders,
            // widgets, or Live Activities. The watch summary is the only
            // derived surface that needs an update.
            WatchConnectivityService.shared.scheduleCurrentStatePublish()
        }
    }
}
