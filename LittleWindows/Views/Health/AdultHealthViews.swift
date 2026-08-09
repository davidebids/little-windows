import Charts
import SwiftData
import SwiftUI

private enum AdultHealthMetric: String, CaseIterable, Identifiable {
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
}

private struct AdultHealthChartPoint: Identifiable {
    var eventID: UUID
    var date: Date
    var value: Double
    var series: String
    var id: String { "\(eventID.uuidString)-\(series)" }
}

struct AdultHealthOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [CareEvent]
    let profile: CareProfile
    @State private var selectedMetric: AdultHealthMetric = .bloodPressure
    @State private var eventTypeToLog: EventType?

    init(profile: CareProfile) {
        self.profile = profile
        let profileID = profile.id
        _events = Query(FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        ))
    }

    private var healthEvents: [CareEvent] {
        events.filter {
            [.symptom, .bloodPressure, .heartRate, .oxygenSaturation,
             .respiratoryRate, .glucose, .temperature, .growth, .pain].contains($0.type)
        }
    }

    private var chartPoints: [AdultHealthChartPoint] {
        events.compactMap { event -> [AdultHealthChartPoint]? in
            let details = event.healthObservationDetails
            switch selectedMetric {
            case .bloodPressure:
                guard event.type == .bloodPressure,
                      let systolic = details.systolicBloodPressure,
                      let diastolic = details.diastolicBloodPressure else { return nil }
                return [
                    AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(systolic), series: "Systolic"),
                    AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(diastolic), series: "Diastolic")
                ]
            case .heartRate:
                guard event.type == .heartRate, let value = details.heartRateBPM else { return nil }
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(value), series: "Heart rate")]
            case .oxygenSaturation:
                guard event.type == .oxygenSaturation, let value = details.oxygenSaturationPercent else { return nil }
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: value, series: "Oxygen")]
            case .respiratoryRate:
                guard event.type == .respiratoryRate, let value = details.respiratoryRatePerMinute else { return nil }
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(value), series: "Respiratory rate")]
            case .bloodGlucose:
                guard event.type == .glucose, let value = details.bloodGlucoseValue else { return nil }
                let normalizedValue = (details.bloodGlucoseUnit ?? .milligramsPerDeciliter)
                    .milligramsPerDeciliter(from: value)
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: normalizedValue, series: "Blood glucose")]
            case .temperature:
                guard event.type == .temperature, let value = event.temperatureCelsius else { return nil }
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: value * 9 / 5 + 32, series: "Temperature")]
            case .weight:
                guard event.type == .growth, let value = event.canonicalWeightKilograms else { return nil }
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: value / 0.45359237, series: "Weight")]
            case .pain:
                guard event.type == .pain, let value = details.painScore else { return nil }
                return [AdultHealthChartPoint(eventID: event.id, date: event.startDate, value: Double(value), series: "Pain")]
            }
        }
        .flatMap { $0 }
        .sorted { $0.date < $1.date }
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
                    event.profileID = profile.id
                    event.profileTypeSnapshot = .adult
                    _ = PersistenceService.save(context: modelContext)
                    SystemIntegrationReconciler.requestReconciliation()
                }
            }
        }
    }

    private var healthEventTypes: Set<EventType> {
        [.symptom, .bloodPressure, .heartRate, .oxygenSaturation,
         .respiratoryRate, .glucose, .temperature, .growth, .pain]
    }

    @ViewBuilder
    private var latestSection: some View {
        let latest = [
            latestValue(.bloodPressure), latestValue(.heartRate), latestValue(.oxygenSaturation),
            latestValue(.respiratoryRate), latestValue(.bloodGlucose), latestValue(.temperature),
            latestValue(.weight), latestValue(.pain)
        ].compactMap { $0 }
        if !latest.isEmpty {
            Section("Latest") {
                ForEach(latest, id: \.title) { item in
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
        Section {
            Picker("Metric", selection: $selectedMetric) {
                ForEach(AdultHealthMetric.allCases) { Text($0.displayName).tag($0) }
            }
            if chartPoints.isEmpty {
                ContentUnavailableView(
                    "No \(selectedMetric.displayName.lowercased()) entries",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Log a value to start this chart.")
                )
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.unit, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.unit, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                }
                .frame(height: 210)
                .chartLegend(position: .bottom)
            }
        } header: {
            AppSectionHeader(title: "Trends", subtitle: "Recorded values")
        }
    }

    @ViewBuilder
    private var symptomsSection: some View {
        let symptoms = events.filter { $0.type == .symptom }.prefix(10)
        if !symptoms.isEmpty {
            Section("Symptoms") {
                ForEach(symptoms) { event in
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
        if !healthEvents.isEmpty {
            Section("Recent health logs") {
                ForEach(healthEvents.prefix(25)) { event in
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

    private func latestValue(_ metric: AdultHealthMetric) -> (title: String, value: String, date: Date)? {
        // Build the latest display directly so selecting a chart metric does not
        // alter the summary cards.
        for event in events {
            let details = event.healthObservationDetails
            switch metric {
            case .bloodPressure where event.type == .bloodPressure:
                if let systolic = details.systolicBloodPressure, let diastolic = details.diastolicBloodPressure {
                    return (metric.displayName, "\(systolic)/\(diastolic) mmHg", event.startDate)
                }
            case .heartRate where event.type == .heartRate:
                if let value = details.heartRateBPM { return (metric.displayName, "\(value) bpm", event.startDate) }
            case .oxygenSaturation where event.type == .oxygenSaturation:
                if let value = details.oxygenSaturationPercent { return (metric.displayName, "\(value.formatted(.number.precision(.fractionLength(0...1))))%", event.startDate) }
            case .respiratoryRate where event.type == .respiratoryRate:
                if let value = details.respiratoryRatePerMinute { return (metric.displayName, "\(value)/min", event.startDate) }
            case .bloodGlucose where event.type == .glucose:
                if let value = details.bloodGlucoseValue {
                    let unit = details.bloodGlucoseUnit ?? .milligramsPerDeciliter
                    return (metric.displayName, "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit.displayName)", event.startDate)
                }
            case .temperature where event.type == .temperature:
                if let value = event.temperatureCelsius { return (metric.displayName, "\((value * 9 / 5 + 32).formatted(.number.precision(.fractionLength(1)))) °F", event.startDate) }
            case .weight where event.type == .growth:
                if let value = event.canonicalWeightKilograms {
                    return (metric.displayName, "\((value / 0.45359237).formatted(.number.precision(.fractionLength(0...1)))) lb", event.startDate)
                }
            case .pain where event.type == .pain:
                if let value = details.painScore {
                    return (metric.displayName, "\(value)/10", event.startDate)
                }
            default:
                continue
            }
        }
        return nil
    }

    private func healthEventEditor(_ event: CareEvent) -> some View {
        EventEditorView(type: event.type, event: event) { savedEvent in
            savedEvent.profileID = profile.id
            savedEvent.profileTypeSnapshot = .adult
            _ = PersistenceService.save(context: modelContext)
            SystemIntegrationReconciler.requestReconciliation()
        }
    }
}
