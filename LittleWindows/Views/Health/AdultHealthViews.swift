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

private struct AdultHealthChartDayKey: Hashable {
    let date: Date
    let series: String
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

private enum AdultHealthReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .week: "Past week"
        case .month: "Past month"
        case .year: "Past year"
        }
    }

    func range(endingAt date: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let end = calendar.startOfDay(for: date)
        let start: Date
        switch self {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        case .month:
            let priorMonth = calendar.date(byAdding: .month, value: -1, to: end) ?? end
            start = calendar.date(byAdding: .day, value: 1, to: priorMonth) ?? priorMonth
        case .year:
            let priorYear = calendar.date(byAdding: .year, value: -1, to: end) ?? end
            start = calendar.date(byAdding: .day, value: 1, to: priorYear) ?? priorYear
        }
        return start...end
    }
}

private struct AdultMedicationReportRow: Identifiable, Sendable {
    let id: UUID
    let name: String
    let strengthDescription: String?
    let startedAt: Date
    let endedAt: Date?
    let trackedDayCount: Int
    let takenCount: Int
    let skippedCount: Int
    let heldCount: Int
    let refusedCount: Int
    let unableCount: Int
    let missedCount: Int
    let lateCount: Int
    let differentAmountCount: Int
    let exceptionCount: Int
    let missedReasonSummary: String?
    let lastReviewedAt: Date?
    let isConfirmedCurrent: Bool
    let isCurrent: Bool
}

private struct AdultPainReportPoint: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let score: Int
    let location: String?
}

private struct AdultBloodPressureReportReading: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let systolic: Int
    let diastolic: Int
}

private struct AdultPainChartPoint: Identifiable, Sendable {
    let date: Date
    let score: Double

    var id: Date { date }
}

private struct AdultBloodPressureChartPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    let series: String

    var id: String { "\(date.timeIntervalSinceReferenceDate)-\(series)" }
}

private struct AdultHealthReportSnapshot: Sendable {
    let periodStart: Date
    let periodEnd: Date
    let medications: [AdultMedicationReportRow]
    let painPoints: [AdultPainReportPoint]
    let painChartPoints: [AdultPainChartPoint]
    let bloodPressureReadings: [AdultBloodPressureReportReading]
    let bloodPressureChartPoints: [AdultBloodPressureChartPoint]

    var takenDoseCount: Int {
        medications.reduce(0) { $0 + $1.takenCount }
    }

    var doseExceptionCount: Int {
        medications.reduce(0) { $0 + $1.exceptionCount }
    }

    var medicationsNeedingReviewCount: Int {
        medications.count { $0.isCurrent && !$0.isConfirmedCurrent }
    }

    var averagePain: Double? {
        guard !painPoints.isEmpty else { return nil }
        return Double(painPoints.reduce(0) { $0 + $1.score }) / Double(painPoints.count)
    }

    var averageSystolic: Int? {
        guard !bloodPressureReadings.isEmpty else { return nil }
        return Int(
            (Double(bloodPressureReadings.reduce(0) { $0 + $1.systolic })
                / Double(bloodPressureReadings.count)).rounded()
        )
    }

    var averageDiastolic: Int? {
        guard !bloodPressureReadings.isEmpty else { return nil }
        return Int(
            (Double(bloodPressureReadings.reduce(0) { $0 + $1.diastolic })
                / Double(bloodPressureReadings.count)).rounded()
        )
    }
}

@ModelActor
private actor AdultHealthReportWorker {
    func snapshot(
        profileID: UUID,
        periodStart: Date,
        periodEnd: Date,
        now: Date
    ) -> AdultHealthReportSnapshot {
        let calendar = Calendar.current
        let periodEndExclusive = calendar.startOfNextDay(for: periodEnd)

        var medicationDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\Medication.createdAt)]
        )
        medicationDescriptor.fetchLimit = 500
        let medications = (try? modelContext.fetch(medicationDescriptor)) ?? []

        var regimenDescriptor = FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationRegimen.startDate)]
        )
        regimenDescriptor.fetchLimit = 1_000
        let regimens = (try? modelContext.fetch(regimenDescriptor)) ?? []

        let doseFetchLowerBound = periodStart.addingTimeInterval(-86_400)
        let doseDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.loggedAt >= doseFetchLowerBound
            },
            sortBy: [SortDescriptor(\MedicationDoseRecord.loggedAt, order: .reverse)]
        )
        // Filter by the dose's meaningful time below: actual time when taken,
        // scheduled time for other outcomes, and logged time for legacy data.
        let doses = ((try? modelContext.fetch(doseDescriptor)) ?? []).filter { dose in
            let reportDate = dose.status == .taken
                ? (dose.takenAt ?? dose.scheduledAt ?? dose.loggedAt)
                : (dose.scheduledAt ?? dose.loggedAt)
            return reportDate >= periodStart && reportDate < periodEndExclusive
        }

        let regimensByMedicationID = Dictionary(grouping: regimens, by: \.medicationID)
        let dosesByMedicationID = Dictionary(grouping: doses, by: \.medicationID)
        let medicationRows = medications.compactMap { medication -> AdultMedicationReportRow? in
            let medicationRegimens = regimensByMedicationID[medication.id] ?? []
            let medicationDoses = dosesByMedicationID[medication.id] ?? []
            let overlapsPeriod = medicationRegimens.contains { regimen in
                regimen.startDate < periodEndExclusive &&
                    (regimen.endDate == nil || regimen.endDate! >= periodStart)
            }
            let wasCreatedInPeriod = medication.createdAt >= periodStart &&
                medication.createdAt < periodEndExclusive
            guard !medication.isArchived || overlapsPeriod || wasCreatedInPeriod || !medicationDoses.isEmpty else {
                return nil
            }

            let startedAt = medicationRegimens.map(\.startDate).min() ?? medication.createdAt
            let isCurrent = !medication.isArchived && medicationRegimens.contains { regimen in
                regimen.isActive && (regimen.endDate == nil || regimen.endDate! >= now)
            }
            let explicitEnd = medicationRegimens.compactMap(\.endDate).max()
            let endedAt: Date? = if isCurrent {
                nil
            } else if let explicitEnd {
                explicitEnd
            } else if medication.isArchived {
                medication.updatedAt
            } else {
                nil
            }
            let durationEnd = min(endedAt ?? now, now)
            let trackedDayCount = max(
                1,
                (calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: startedAt),
                    to: calendar.startOfDay(for: max(durationEnd, startedAt))
                ).day ?? 0) + 1
            )
            let strengthDescription = medication.strength.map {
                "\($0.formatted(.number.precision(.fractionLength(0...2)))) \(medication.strengthUnit)"
            }
            let missedReasons = medicationDoses.compactMap { dose -> MedicationDoseReason? in
                guard MedicationDoseStatus(rawValue: dose.statusRawValue) == .missed else { return nil }
                return dose.reasonRawValue.flatMap(MedicationDoseReason.init(rawValue:))
            }
            let missedReasonCounts = Dictionary(grouping: missedReasons, by: { $0 })
            let missedReasonSummary = MedicationDoseReason.allCases.compactMap { reason -> String? in
                guard let count = missedReasonCounts[reason]?.count, count > 0 else { return nil }
                return "\(count) \(reason.displayName.lowercased())"
            }.joined(separator: " · ")
            return AdultMedicationReportRow(
                id: medication.id,
                name: medication.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Medication"
                    : medication.name,
                strengthDescription: strengthDescription,
                startedAt: startedAt,
                endedAt: endedAt,
                trackedDayCount: trackedDayCount,
                takenCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .taken
                },
                skippedCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .skipped
                },
                heldCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .held
                },
                refusedCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .refused
                },
                unableCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .unable
                },
                missedCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .missed
                },
                lateCount: medicationDoses.count {
                    MedicationDoseStatus(rawValue: $0.statusRawValue) == .taken
                        && MedicationDoseTiming(rawValue: $0.timingRawValue ?? "") == .late
                },
                differentAmountCount: medicationDoses.count {
                    guard MedicationDoseStatus(rawValue: $0.statusRawValue) == .taken,
                          let actualDoseAmount = $0.actualDoseAmount else { return false }
                    return abs(actualDoseAmount - $0.doseAmount) > 0.000_001
                },
                exceptionCount: medicationDoses.count { dose in
                    guard let status = MedicationDoseStatus(rawValue: dose.statusRawValue) else {
                        return false
                    }
                    if status != .taken { return true }
                    if MedicationDoseTiming(rawValue: dose.timingRawValue ?? "") == .late {
                        return true
                    }
                    guard let actualDoseAmount = dose.actualDoseAmount else { return false }
                    return abs(actualDoseAmount - dose.doseAmount) > 0.000_001
                },
                missedReasonSummary: missedReasonSummary.isEmpty ? nil : missedReasonSummary,
                lastReviewedAt: medication.lastReviewedAt,
                isConfirmedCurrent: medication.isConfirmedCurrent,
                isCurrent: isCurrent
            )
        }.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let painRawValue = EventType.pain.rawValue
        var painDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID &&
                    $0.typeRawValue == painRawValue &&
                    $0.startDate >= periodStart &&
                    $0.startDate < periodEndExclusive
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        painDescriptor.fetchLimit = 2_000
        let painEvents: [CareEvent] = (try? modelContext.fetch(painDescriptor)) ?? []
        let painPoints: [AdultPainReportPoint] = painEvents.compactMap { event in
            let details = event.healthObservationDetails
            guard let score = details.painScore else { return nil }
            return AdultPainReportPoint(
                id: event.id,
                date: event.startDate,
                score: score,
                location: details.painLocationSummary
            )
        }
        let painChartPoints = Dictionary(
            grouping: painPoints,
            by: { calendar.startOfDay(for: $0.date) }
        ).map { date, points in
            AdultPainChartPoint(
                date: date,
                score: Double(points.reduce(0) { $0 + $1.score }) / Double(points.count)
            )
        }.sorted { $0.date < $1.date }

        let bloodPressureRawValue = EventType.bloodPressure.rawValue
        var bloodPressureDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID &&
                    $0.typeRawValue == bloodPressureRawValue &&
                    $0.startDate >= periodStart &&
                    $0.startDate < periodEndExclusive
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        bloodPressureDescriptor.fetchLimit = 2_000
        let bloodPressureEvents: [CareEvent] =
            (try? modelContext.fetch(bloodPressureDescriptor)) ?? []
        let bloodPressureReadings: [AdultBloodPressureReportReading] =
            bloodPressureEvents.compactMap { event in
                let details = event.healthObservationDetails
                guard let systolic = details.systolicBloodPressure,
                      let diastolic = details.diastolicBloodPressure else { return nil }
                return AdultBloodPressureReportReading(
                    id: event.id,
                    date: event.startDate,
                    systolic: systolic,
                    diastolic: diastolic
                )
            }
        let bloodPressureChartPoints = Dictionary(
            grouping: bloodPressureReadings,
            by: { calendar.startOfDay(for: $0.date) }
        ).flatMap { date, readings in
            let count = Double(readings.count)
            let averageSystolic = Double(readings.reduce(0) { $0 + $1.systolic }) / count
            let averageDiastolic = Double(readings.reduce(0) { $0 + $1.diastolic }) / count
            return [
                AdultBloodPressureChartPoint(
                    date: date,
                    value: averageSystolic,
                    series: "Systolic"
                ),
                AdultBloodPressureChartPoint(
                    date: date,
                    value: averageDiastolic,
                    series: "Diastolic"
                )
            ]
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.series < $1.series
        }

        return AdultHealthReportSnapshot(
            periodStart: periodStart,
            periodEnd: periodEnd,
            medications: medicationRows,
            painPoints: painPoints,
            painChartPoints: painChartPoints,
            bloodPressureReadings: bloodPressureReadings,
            bloodPressureChartPoints: bloodPressureChartPoints
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
    func points(
        profileID: UUID,
        metric: AdultHealthMetric,
        periodStart: Date?,
        periodEndExclusive: Date?
    ) -> [AdultHealthChartPoint] {
        let typeRawValue = metric.eventType.rawValue
        let events: [CareEvent]
        if let periodStart, let periodEndExclusive {
            var descriptor = FetchDescriptor<CareEvent>(
                predicate: #Predicate {
                    $0.profileID == profileID &&
                        $0.typeRawValue == typeRawValue &&
                        $0.startDate >= periodStart &&
                        $0.startDate < periodEndExclusive
                },
                sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
            )
            descriptor.fetchLimit = 2_000
            events = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            var descriptor = FetchDescriptor<CareEvent>(
                predicate: #Predicate {
                    $0.profileID == profileID && $0.typeRawValue == typeRawValue
                },
                sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
            )
            descriptor.fetchLimit = 365
            events = (try? modelContext.fetch(descriptor)) ?? []
        }
        let points = events
            .flatMap { AdultHealthChartPoint.make(from: $0, metric: metric) }
        guard periodStart != nil else {
            return points.sorted { $0.date < $1.date }
        }

        let calendar = Calendar.current
        return Dictionary(grouping: points) { point in
            AdultHealthChartDayKey(
                date: calendar.startOfDay(for: point.date),
                series: point.series
            )
        }.compactMap { key, dailyPoints in
            guard let representative = dailyPoints.first else { return nil }
            return AdultHealthChartPoint(
                eventID: representative.eventID,
                date: key.date,
                value: dailyPoints.reduce(0) { $0 + $1.value } / Double(dailyPoints.count),
                series: key.series
            )
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.series < $1.series
        }
    }
}

private struct AdultHealthTrendRequest: Equatable {
    let isEnabled: Bool
    let profileID: UUID
    let metric: AdultHealthMetric
    let eventsRevision: Date?
    let periodStart: Date?
    let periodEndExclusive: Date?
}

private struct AdultHealthTrendSnapshot {
    let request: AdultHealthTrendRequest
    let points: [AdultHealthChartPoint]
}

private struct AdultHealthReportRequest: Equatable {
    let profileID: UUID
    let period: AdultHealthReportPeriod
    let periodStart: Date
    let periodEnd: Date
    let eventsRevision: Date?
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
    let showsReportSummary: Bool
    @State private var selectedMetric: AdultHealthMetric = .bloodPressure
    @State private var selectedReportPeriod: AdultHealthReportPeriod = .week
    @State private var eventTypeToLog: EventType?
    @State private var latestValues: [AdultHealthLatestValue] = []
    @State private var reportSnapshot: AdultHealthReportSnapshot?
    @State private var reportAnchorDate = Date()
    @State private var showsAdditionalTrends = false
    // Keep the result above the List row so iPad row recycling cannot restart
    // the fetch and repeatedly restore the loading placeholder during layout.
    @State private var trendSnapshot: AdultHealthTrendSnapshot?

    init(profile: CareProfile, showsReportSummary: Bool = false) {
        self.profile = profile
        self.showsReportSummary = showsReportSummary
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
            if showsReportSummary {
                reportPeriodSection
                reportOverviewSection
                additionalTrendsSection
            } else {
                latestSection
                trendSection
            }
            if showsReportSummary {
                medicationReportSection
                painReportSection
                bloodPressureReportSection
            } else {
                symptomsSection
                recentSection
            }
            Section {
                Label("Charts show the values entered and do not interpret whether a result is normal or concerning.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("adult-health.overview")
        .navigationTitle(showsReportSummary ? "Reports" : "Health Log")
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
            guard !showsReportSummary else { return }
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
        .task(id: reportRequest) {
            await loadReport(for: reportRequest)
        }
    }

    private var healthEventTypes: Set<EventType> {
        [.symptom, .bloodPressure, .heartRate, .oxygenSaturation,
         .respiratoryRate, .glucose, .temperature, .growth, .pain]
    }

    private var reportPeriodRange: ClosedRange<Date> {
        selectedReportPeriod.range(endingAt: reportAnchorDate)
    }

    private var reportRequest: AdultHealthReportRequest {
        AdultHealthReportRequest(
            profileID: profile.id,
            period: selectedReportPeriod,
            periodStart: reportPeriodRange.lowerBound,
            periodEnd: reportPeriodRange.upperBound,
            eventsRevision: events.lazy.map(\.updatedAt).max()
        )
    }

    private var reportPeriodSection: some View {
        Section {
            Picker("Summary period", selection: $selectedReportPeriod) {
                ForEach(AdultHealthReportPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("adult-report.period-picker")

            Text(
                "\(reportPeriodRange.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(reportPeriodRange.upperBound.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        } header: {
            AppSectionHeader(
                title: "Health summary",
                subtitle: selectedReportPeriod.accessibilityLabel
            )
        }
    }

    private var reportOverviewSection: some View {
        Section("At a glance") {
            if let reportSnapshot {
                LabeledContent("Medications tracked", value: "\(reportSnapshot.medications.count)")
                    .accessibilityIdentifier("adult-report.medication-count")
                LabeledContent("Doses taken", value: "\(reportSnapshot.takenDoseCount)")
                LabeledContent("Dose exceptions", value: "\(reportSnapshot.doseExceptionCount)")
                LabeledContent(
                    "Medication plans needing review",
                    value: "\(reportSnapshot.medicationsNeedingReviewCount)"
                )
                LabeledContent("Pain entries", value: "\(reportSnapshot.painPoints.count)")
                    .accessibilityIdentifier("adult-report.pain-count")
                LabeledContent(
                    "Blood pressure readings",
                    value: "\(reportSnapshot.bloodPressureReadings.count)"
                )
                .accessibilityIdentifier("adult-report.blood-pressure-count")
            } else {
                ProgressView("Loading summary…")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var medicationReportSection: some View {
        Section {
            if let reportSnapshot {
                if reportSnapshot.medications.isEmpty {
                    ContentUnavailableView(
                        "No medications in this period",
                        systemImage: "pills",
                        description: Text("Current medications and medications with activity in this period will appear here.")
                    )
                } else {
                    ForEach(reportSnapshot.medications) { medication in
                        medicationReportRow(medication)
                    }
                }
            }
        } header: {
            AppSectionHeader(
                title: "Medication history",
                subtitle: "Schedule duration and recorded doses"
            )
        }
        .accessibilityIdentifier("adult-report.medications")
    }

    private func medicationReportRow(_ medication: AdultMedicationReportRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pills.fill")
                .foregroundStyle(.red)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(medication.name)
                        .font(.subheadline.weight(.semibold))
                    if medication.isCurrent {
                        Text("Current")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                if let strengthDescription = medication.strengthDescription {
                    Text(strengthDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if medication.isCurrent {
                    Label(
                        medication.isConfirmedCurrent ? "Confirmed current" : "Needs review",
                        systemImage: medication.isConfirmedCurrent
                            ? "checkmark.seal.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medication.isConfirmedCurrent ? .green : .orange)
                }
                if let lastReviewedAt = medication.lastReviewedAt {
                    Text("Last reviewed \(lastReviewedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Tracked for \(medication.trackedDayCount) \(medication.trackedDayCount == 1 ? "day" : "days") · started \(medication.startedAt.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let endedAt = medication.endedAt, !medication.isCurrent {
                    Text("Ended \(endedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(medicationOutcomeSummary(medication))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let missedReasonSummary = medication.missedReasonSummary {
                    Text("Missed reasons: \(missedReasonSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func medicationOutcomeSummary(_ medication: AdultMedicationReportRow) -> String {
        var parts = ["\(medication.takenCount) taken"]
        if medication.lateCount > 0 { parts.append("\(medication.lateCount) late") }
        if medication.differentAmountCount > 0 {
            parts.append("\(medication.differentAmountCount) different amount")
        }
        if medication.heldCount > 0 { parts.append("\(medication.heldCount) held") }
        if medication.refusedCount > 0 { parts.append("\(medication.refusedCount) refused") }
        if medication.unableCount > 0 { parts.append("\(medication.unableCount) unable") }
        if medication.missedCount > 0 { parts.append("\(medication.missedCount) missed") }
        if medication.skippedCount > 0 { parts.append("\(medication.skippedCount) skipped") }
        return parts.joined(separator: " · ") + " in this period"
    }

    private var painReportSection: some View {
        Section {
            if let reportSnapshot {
                if reportSnapshot.painPoints.isEmpty {
                    ContentUnavailableView(
                        "No pain entries",
                        systemImage: "bolt.heart",
                        description: Text("Pain scores logged in this period will appear here.")
                    )
                } else {
                    LabeledContent(
                        "Average score",
                        value: reportSnapshot.averagePain.map {
                            "\($0.formatted(.number.precision(.fractionLength(1))))/10"
                        } ?? "–"
                    )
                    if let latest = reportSnapshot.painPoints.first {
                        LabeledContent("Latest", value: "\(latest.score)/10")
                    }
                    Chart(reportSnapshot.painChartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Pain score", point.score)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.linear)
                        if reportSnapshot.painChartPoints.count <= 120 {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Pain score", point.score)
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .chartYScale(domain: 0...10)
                    .frame(height: 190)

                    ForEach(reportSnapshot.painPoints.prefix(8)) { point in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pain \(point.score)/10")
                                    .font(.subheadline.weight(.semibold))
                                if let location = point.location {
                                    Text(location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            AppSectionHeader(title: "Pain over time", subtitle: "Recorded scores from 0–10")
        }
        .accessibilityIdentifier("adult-report.pain")
    }

    private var bloodPressureReportSection: some View {
        Section {
            if let reportSnapshot {
                if reportSnapshot.bloodPressureReadings.isEmpty {
                    ContentUnavailableView(
                        "No blood pressure readings",
                        systemImage: "heart.text.square",
                        description: Text("Blood pressure logged in this period will appear here.")
                    )
                } else {
                    if let systolic = reportSnapshot.averageSystolic,
                       let diastolic = reportSnapshot.averageDiastolic {
                        LabeledContent("Period average", value: "\(systolic)/\(diastolic) mmHg")
                    }
                    if let latest = reportSnapshot.bloodPressureReadings.first {
                        LabeledContent(
                            "Latest",
                            value: "\(latest.systolic)/\(latest.diastolic) mmHg"
                        )
                    }

                    Chart(reportSnapshot.bloodPressureChartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("mmHg", point.value)
                        )
                        .foregroundStyle(by: .value("Reading", point.series))
                        if reportSnapshot.bloodPressureReadings.count <= 120 {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("mmHg", point.value)
                            )
                            .foregroundStyle(by: .value("Reading", point.series))
                        }
                    }
                    .chartForegroundStyleScale([
                        "Systolic": Color.red,
                        "Diastolic": Color.blue
                    ])
                    .chartLegend(position: .bottom)
                    .frame(height: 210)

                    ForEach(reportSnapshot.bloodPressureReadings.prefix(12)) { reading in
                        HStack {
                            Text("\(reading.systolic)/\(reading.diastolic) mmHg")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            AppSectionHeader(
                title: "Blood pressure history",
                subtitle: "Systolic and diastolic readings"
            )
        }
        .accessibilityIdentifier("adult-report.blood-pressure")
    }

    private func loadReport(for request: AdultHealthReportRequest) async {
        guard showsReportSummary else { return }
        reportSnapshot = nil
        let worker = AdultHealthReportWorker(modelContainer: modelContext.container)
        let snapshot = await worker.snapshot(
            profileID: request.profileID,
            periodStart: request.periodStart,
            periodEnd: request.periodEnd,
            now: reportAnchorDate
        )
        guard !Task.isCancelled, reportRequest == request else { return }
        reportSnapshot = snapshot
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
                isLoading: trendSnapshot?.request != trendRequest
            )
        } header: {
            AppSectionHeader(
                title: "Trends",
                subtitle: showsReportSummary
                    ? selectedReportPeriod.accessibilityLabel
                    : "Up to 365 recent entries"
            )
        }
    }

    private var additionalTrendsSection: some View {
        Section {
            Button {
                showsAdditionalTrends.toggle()
            } label: {
                HStack {
                    Label(
                        "Heart rate, oxygen, glucose, and more",
                        systemImage: "chart.xyaxis.line"
                    )
                    Spacer()
                    Image(systemName: showsAdditionalTrends ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("adult-report.additional-trends-toggle")
            .accessibilityValue(showsAdditionalTrends ? "Expanded" : "Collapsed")

            if showsAdditionalTrends {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(AdultHealthMetric.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("adult-health.metric-picker")
                AdultHealthTrendSection(
                    metric: selectedMetric,
                    points: visibleTrendPoints,
                    isLoading: trendSnapshot?.request != trendRequest
                )
            }
        } header: {
            AppSectionHeader(
                title: "Other health trends",
                subtitle: "Open to choose a metric"
            )
        }
    }

    private var trendRequest: AdultHealthTrendRequest {
        let period = reportPeriodRange
        return AdultHealthTrendRequest(
            isEnabled: !showsReportSummary || showsAdditionalTrends,
            profileID: profile.id,
            metric: selectedMetric,
            eventsRevision: events.lazy.map(\.updatedAt).max(),
            periodStart: showsReportSummary ? period.lowerBound : nil,
            periodEndExclusive: showsReportSummary
                ? Calendar.current.startOfNextDay(for: period.upperBound)
                : nil
        )
    }

    private var visibleTrendPoints: [AdultHealthChartPoint] {
        guard trendSnapshot?.request == trendRequest else {
            return []
        }
        return trendSnapshot?.points ?? []
    }

    private func loadSelectedTrend(for request: AdultHealthTrendRequest) async {
        guard request.isEnabled else {
            trendSnapshot = nil
            return
        }
        let worker = AdultHealthTrendWorker(modelContainer: modelContext.container)
        let points = await worker.points(
            profileID: request.profileID,
            metric: request.metric,
            periodStart: request.periodStart,
            periodEndExclusive: request.periodEndExclusive
        )
        guard !Task.isCancelled,
              trendRequest == request else {
            return
        }
        trendSnapshot = AdultHealthTrendSnapshot(
            request: request,
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
                                    details.symptomLocationSummary,
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
