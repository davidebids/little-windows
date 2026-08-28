import Foundation

enum CareStoryCategory: String, CaseIterable, Sendable, Hashable {
    case medication
    case symptom
    case pain
    case vital
    case sleep
    case activity

    var displayName: String {
        switch self {
        case .medication: "Medication"
        case .symptom: "Symptoms"
        case .pain: "Pain"
        case .vital: "Vitals"
        case .sleep: "Sleep"
        case .activity: "Activity"
        }
    }
}

enum CareStoryObservationKind: String, Sendable {
    case timing
    case comparison
    case discussion
}

struct CareStoryEventRecord: Sendable {
    let id: UUID
    let date: Date
    let category: CareStoryCategory
    let title: String
    let detail: String?
    let symptomName: String?
    let symptomSeverity: Int?
    let painScore: Int?
    let systolicBloodPressure: Int?
    let diastolicBloodPressure: Int?
    let durationMinutes: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        category: CareStoryCategory,
        title: String,
        detail: String? = nil,
        symptomName: String? = nil,
        symptomSeverity: Int? = nil,
        painScore: Int? = nil,
        systolicBloodPressure: Int? = nil,
        diastolicBloodPressure: Int? = nil,
        durationMinutes: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.detail = detail
        self.symptomName = symptomName
        self.symptomSeverity = symptomSeverity
        self.painScore = painScore
        self.systolicBloodPressure = systolicBloodPressure
        self.diastolicBloodPressure = diastolicBloodPressure
        self.durationMinutes = durationMinutes
    }

    var isBloodPressure: Bool {
        (systolicBloodPressure != nil && diastolicBloodPressure != nil)
            || title.localizedCaseInsensitiveContains("blood pressure")
    }
}

struct CareStoryMedicationChangeRecord: Sendable {
    let id: UUID
    let date: Date
    let medicationName: String
    let changeKind: MedicationPlanChangeKind
    let source: MedicationPlanChangeSource
    let beforeDose: String?
    let afterDose: String?
    let beforeSchedule: String?
    let afterSchedule: String?

    init(
        id: UUID = UUID(),
        date: Date,
        medicationName: String,
        changeKind: MedicationPlanChangeKind,
        source: MedicationPlanChangeSource,
        beforeDose: String? = nil,
        afterDose: String? = nil,
        beforeSchedule: String? = nil,
        afterSchedule: String? = nil
    ) {
        self.id = id
        self.date = date
        self.medicationName = medicationName
        self.changeKind = changeKind
        self.source = source
        self.beforeDose = beforeDose
        self.afterDose = afterDose
        self.beforeSchedule = beforeSchedule
        self.afterSchedule = afterSchedule
    }
}

struct CareStoryDoseRecord: Sendable {
    let id: UUID
    let date: Date
    let medicationName: String
    let status: MedicationDoseStatus
    let timing: MedicationDoseTiming?
    let reason: MedicationDoseReason?
    let scheduledAmount: Double
    let actualAmount: Double?
    let doseUnit: String

    init(
        id: UUID = UUID(),
        date: Date,
        medicationName: String,
        status: MedicationDoseStatus,
        timing: MedicationDoseTiming? = nil,
        reason: MedicationDoseReason? = nil,
        scheduledAmount: Double = 1,
        actualAmount: Double? = nil,
        doseUnit: String = "dose"
    ) {
        self.id = id
        self.date = date
        self.medicationName = medicationName
        self.status = status
        self.timing = timing
        self.reason = reason
        self.scheduledAmount = scheduledAmount
        self.actualAmount = actualAmount
        self.doseUnit = doseUnit
    }

    var hasDifferentAmount: Bool {
        guard status == .taken, let actualAmount else { return false }
        return abs(actualAmount - scheduledAmount) > 0.000_001
    }

    var isException: Bool {
        status != .taken || timing == .late || hasDifferentAmount
    }
}

struct CareStoryAppointmentRecord: Sendable {
    let id: UUID
    let date: Date
    let title: String
    let typeName: String
    let summary: String?

    init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        typeName: String,
        summary: String? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.typeName = typeName
        self.summary = summary
    }
}

struct CareStoryTimelineItem: Identifiable, Sendable {
    let id: String
    let date: Date
    let category: CareStoryCategory
    let title: String
    let detail: String?
    let isMedicationPlanChange: Bool
    let isBloodPressure: Bool
}

struct CareStoryPainActivityDay: Identifiable, Sendable {
    let date: Date
    let averagePainScore: Double?
    let painEntryCount: Int
    let activityEntryCount: Int

    var id: Date { date }
}

struct CareStoryBloodPressureReading: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let systolic: Int
    let diastolic: Int
}

struct CareStoryMissedDoseMarker: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let medicationName: String
    let status: MedicationDoseStatus
}

struct CareStoryWindowSummary: Sendable {
    let symptomEntries: Int
    let symptomDays: Int
    let averageSymptomSeverity: Double?
    let symptomSeverityDays: Int
    let averagePainScore: Double?
    let painDays: Int
    let activityDays: Int
    let averageSleepHours: Double?
    let sleepDays: Int
    let bloodPressureReadings: Int
    let averageSystolicBloodPressure: Double?
    let averageDiastolicBloodPressure: Double?
    let missedDoseCount: Int
    let doseExceptionCount: Int
    let recordedDoseCount: Int
    let activeRecordDays: Int
}

struct CareStoryChapterSignal: Identifiable, Sendable {
    let id: String
    let dayOffset: Int
    let category: CareStoryCategory
    let count: Int
}

struct CareStorySourceRecord: Identifiable, Sendable {
    let id: String
    let date: Date
    let category: CareStoryCategory
    let title: String
    let detail: String?
}

enum CareStoryDomain: String, CaseIterable, Sendable, Hashable {
    case symptoms
    case pain
    case sleep
    case activity
    case bloodPressure
    case doseConsistency

    var displayName: String {
        switch self {
        case .symptoms: "Symptoms"
        case .pain: "Pain"
        case .sleep: "Sleep"
        case .activity: "Activity"
        case .bloodPressure: "Blood pressure"
        case .doseConsistency: "Dose consistency"
        }
    }
}

enum CareStoryShiftDirection: String, Sendable {
    case higher
    case lower
    case similar
    case insufficient
}

struct CareStoryDomainShift: Identifiable, Sendable {
    let domain: CareStoryDomain
    let beforeValue: String
    let afterValue: String
    let direction: CareStoryShiftDirection
    let changeLabel: String
    let insight: String

    var id: String { domain.rawValue }
    var isComparable: Bool { direction != .insufficient }
}

enum CareStoryEvidenceLevel: String, Sendable {
    case early
    case building
    case strong

    var displayName: String {
        switch self {
        case .early: "Early story"
        case .building: "Building context"
        case .strong: "Strong context"
        }
    }
}

struct CareStoryEvidence: Sendable {
    let level: CareStoryEvidenceLevel
    let comparableDomainCount: Int
    let beforeActiveDays: Int
    let afterActiveDays: Int
    let afterDaysAvailable: Int

    var coverageDescription: String {
        "Records on \(beforeActiveDays)/7 days before and \(afterActiveDays)/\(max(1, afterDaysAvailable)) after"
    }
}

enum CareStoryChapterKind: String, Sendable {
    case medicationChange
    case symptomEpisode
    case painEpisode
    case appointment
}

struct CareStoryChapter: Identifiable, Sendable {
    let id: String
    let kind: CareStoryChapterKind
    let date: Date
    let medicationName: String
    let title: String
    let changeDetail: String?
    let sourceLabel: String
    let beforeLabel: String
    let afterLabel: String
    let before: CareStoryWindowSummary
    let after: CareStoryWindowSummary
    let afterWindowIsComplete: Bool
    let signals: [CareStoryChapterSignal]
    let sourceRecords: [CareStorySourceRecord]
    let sourceRecordCount: Int
    let highlights: [String]
    let evidence: CareStoryEvidence
    let domainShifts: [CareStoryDomainShift]
    let pulseHeadline: String
    let discussionPrompts: [String]
}

struct CareStoryObservation: Identifiable, Sendable {
    let id: String
    let kind: CareStoryObservationKind
    let statement: String
    let caution: String
}

struct CareStorySnapshot: Sendable {
    let startDate: Date
    let endDate: Date
    let timelineItems: [CareStoryTimelineItem]
    let observations: [CareStoryObservation]
    let painActivityDays: [CareStoryPainActivityDay]
    let bloodPressureReadings: [CareStoryBloodPressureReading]
    let missedDoseMarkers: [CareStoryMissedDoseMarker]
    let chapters: [CareStoryChapter]
    let dataWasLimited: Bool

    var recordCount: Int { timelineItems.count }
}

enum CareStorySnapshotContent: Equatable, Sendable {
    case complete
    case chaptersOnly
}

enum CareStoryService {
    static func makeSnapshot(
        events: [CareStoryEventRecord],
        medicationChanges: [CareStoryMedicationChangeRecord],
        doseRecords: [CareStoryDoseRecord],
        appointments: [CareStoryAppointmentRecord] = [],
        dataWasLimited: Bool = false,
        content: CareStorySnapshotContent = .complete,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> CareStorySnapshot {
        let includeOverviewData = content == .complete
        let scopedEvents = includeOverviewData
            ? events.filter { $0.date >= startDate && $0.date < endDate }
            : []
        let scopedChanges = medicationChanges.filter { $0.date >= startDate && $0.date < endDate }
        let scopedDoses = includeOverviewData
            ? doseRecords.filter { $0.date >= startDate && $0.date < endDate }
            : []

        var items: [CareStoryTimelineItem] = []
        if includeOverviewData {
            items = scopedEvents.map { event in
                CareStoryTimelineItem(
                    id: "event-\(event.id.uuidString)",
                    date: event.date,
                    category: event.category,
                    title: event.title,
                    detail: event.detail,
                    isMedicationPlanChange: false,
                    isBloodPressure: event.isBloodPressure
                )
            }
            items += scopedChanges.map(timelineItem(for:))
            items += scopedDoses.filter(\.isException).map(timelineItem(for:))
            items.sort {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id < $1.id
            }
        }

        return CareStorySnapshot(
            startDate: startDate,
            endDate: endDate,
            timelineItems: items,
            observations: includeOverviewData
                ? observations(
                    events: scopedEvents,
                    medicationChanges: scopedChanges,
                    doseRecords: scopedDoses,
                    calendar: calendar
                )
                : [],
            painActivityDays: includeOverviewData
                ? painActivityDays(events: scopedEvents, calendar: calendar)
                : [],
            bloodPressureReadings: includeOverviewData
                ? bloodPressureReadings(events: scopedEvents)
                : [],
            missedDoseMarkers: includeOverviewData
                ? missedDoseMarkers(doseRecords: scopedDoses)
                : [],
            chapters: chapters(
                events: events,
                medicationChanges: scopedChanges,
                doseRecords: doseRecords,
                appointments: appointments.filter { $0.date >= startDate && $0.date < endDate },
                startDate: startDate,
                endDate: endDate,
                calendar: calendar
            ),
            dataWasLimited: dataWasLimited
        )
    }

    private static func timelineItem(
        for change: CareStoryMedicationChangeRecord
    ) -> CareStoryTimelineItem {
        let name = cleanMedicationName(change.medicationName)
        let title: String
        switch change.changeKind {
        case .added: title = "Started \(name)"
        case .updated:
            title = doseOrScheduleChanged(change) ? "Dose or schedule changed for \(name)" : "Plan changed for \(name)"
        case .stopped: title = "Stopped \(name)"
        case .restored: title = "Restarted \(name)"
        case .confirmedCurrent: title = "Confirmed \(name) current"
        }

        var details: [String] = []
        if let beforeDose = nonBlank(change.beforeDose),
           let afterDose = nonBlank(change.afterDose),
           beforeDose != afterDose {
            details.append("\(beforeDose) → \(afterDose)")
        } else if let beforeSchedule = nonBlank(change.beforeSchedule),
                  let afterSchedule = nonBlank(change.afterSchedule),
                  beforeSchedule != afterSchedule {
            details.append("\(beforeSchedule) → \(afterSchedule)")
        }
        details.append("Source: \(change.source.displayName)")

        return CareStoryTimelineItem(
            id: "plan-\(change.id.uuidString)",
            date: change.date,
            category: .medication,
            title: title,
            detail: details.joined(separator: " · "),
            isMedicationPlanChange: true,
            isBloodPressure: false
        )
    }

    private static func timelineItem(for dose: CareStoryDoseRecord) -> CareStoryTimelineItem {
        let name = cleanMedicationName(dose.medicationName)
        var detailParts: [String] = []
        if let reason = dose.reason {
            detailParts.append(reason.displayName)
        }
        if dose.hasDifferentAmount, let actualAmount = dose.actualAmount {
            detailParts.append(
                "\(number(actualAmount)) \(dose.doseUnit) recorded; \(number(dose.scheduledAmount)) scheduled"
            )
        }

        let outcome: String
        if dose.status == .taken, dose.timing == .late, dose.hasDifferentAmount {
            outcome = "Taken late, different amount"
        } else if dose.status == .taken, dose.timing == .late {
            outcome = "Taken late"
        } else if dose.status == .taken, dose.hasDifferentAmount {
            outcome = "Different amount taken"
        } else {
            outcome = dose.status.displayName
        }

        return CareStoryTimelineItem(
            id: "dose-\(dose.id.uuidString)",
            date: dose.date,
            category: .medication,
            title: "\(name): \(outcome)",
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
            isMedicationPlanChange: false,
            isBloodPressure: false
        )
    }

    private static func painActivityDays(
        events: [CareStoryEventRecord],
        calendar: Calendar
    ) -> [CareStoryPainActivityDay] {
        let relevantEvents = events.filter { $0.category == .pain || $0.category == .activity }
        return Dictionary(grouping: relevantEvents) { calendar.startOfDay(for: $0.date) }
            .map { date, dayEvents in
                let painScores = dayEvents.compactMap(\.painScore)
                let averagePain = painScores.isEmpty
                    ? nil
                    : Double(painScores.reduce(0, +)) / Double(painScores.count)
                return CareStoryPainActivityDay(
                    date: date,
                    averagePainScore: averagePain,
                    painEntryCount: painScores.count,
                    activityEntryCount: dayEvents.count { $0.category == .activity }
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func bloodPressureReadings(
        events: [CareStoryEventRecord]
    ) -> [CareStoryBloodPressureReading] {
        events.compactMap { event in
            guard let systolic = event.systolicBloodPressure,
                  let diastolic = event.diastolicBloodPressure else { return nil }
            return CareStoryBloodPressureReading(
                id: event.id,
                date: event.date,
                systolic: systolic,
                diastolic: diastolic
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func missedDoseMarkers(
        doseRecords: [CareStoryDoseRecord]
    ) -> [CareStoryMissedDoseMarker] {
        doseRecords.compactMap { dose in
            guard dose.status == .missed || dose.status == .skipped else { return nil }
            return CareStoryMissedDoseMarker(
                id: dose.id,
                date: dose.date,
                medicationName: cleanMedicationName(dose.medicationName),
                status: dose.status
            )
        }
        .sorted { $0.date < $1.date }
    }

    private struct ChapterSignalKey: Hashable {
        let dayOffset: Int
        let category: CareStoryCategory
    }

    private struct ChapterAnchor {
        let id: String
        let kind: CareStoryChapterKind
        let date: Date
        let title: String
        let detail: String?
        let sourceLabel: String
        let medicationName: String
        let beforeLabel: String
        let afterLabel: String
        let seriesKey: String?
    }

    private static func chapters(
        events: [CareStoryEventRecord],
        medicationChanges: [CareStoryMedicationChangeRecord],
        doseRecords: [CareStoryDoseRecord],
        appointments: [CareStoryAppointmentRecord],
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> [CareStoryChapter] {
        let medicationAnchors = medicationChanges
            .filter { $0.changeKind != .confirmedCurrent }
            .map { change -> ChapterAnchor in
                let item = timelineItem(for: change)
                return ChapterAnchor(
                    id: "medication-\(change.id.uuidString)",
                    kind: .medicationChange,
                    date: change.date,
                    title: item.title,
                    detail: changeDetail(change),
                    sourceLabel: change.source.displayName,
                    medicationName: cleanMedicationName(change.medicationName),
                    beforeLabel: "Before",
                    afterLabel: "After",
                    seriesKey: nil
                )
            }

        let appointmentAnchors = appointments.map { appointment in
            ChapterAnchor(
                id: "appointment-\(appointment.id.uuidString)",
                kind: .appointment,
                date: appointment.date,
                title: appointment.title,
                detail: nonBlank(appointment.summary),
                sourceLabel: appointment.typeName,
                medicationName: "",
                beforeLabel: "Before",
                afterLabel: "After",
                seriesKey: nil
            )
        }
        let anchors = (medicationAnchors
            + appointmentAnchors
            + detectedEpisodeAnchors(events: events, calendar: calendar))
            .filter { $0.date >= startDate && $0.date < endDate }
            .sorted { $0.date > $1.date }
            .prefix(12)

        return anchors.map { anchor in
            let beforeStart = calendar.date(byAdding: .day, value: -7, to: anchor.date)
                ?? anchor.date.addingTimeInterval(-7 * 86_400)
            let afterEnd = calendar.date(byAdding: .day, value: 7, to: anchor.date)
                ?? anchor.date.addingTimeInterval(7 * 86_400)
            let visibleAfterEnd = min(afterEnd, endDate)
            let before = windowSummary(
                events: events,
                doseRecords: doseRecords,
                startDate: beforeStart,
                endDate: anchor.date,
                calendar: calendar
            )
            let after = windowSummary(
                events: events,
                doseRecords: doseRecords,
                startDate: anchor.date,
                endDate: visibleAfterEnd,
                calendar: calendar
            )
            let afterDaysAvailable = min(
                7,
                max(
                    1,
                    calendar.dateComponents(
                        [.day],
                        from: calendar.startOfDay(for: anchor.date),
                        to: calendar.startOfDay(for: visibleAfterEnd)
                    ).day ?? 1
                )
            )
            let complete = afterEnd <= endDate
            let shifts = domainShifts(
                before: before,
                after: after,
                afterDaysAvailable: afterDaysAvailable
            )
            let evidence = chapterEvidence(
                before: before,
                after: after,
                afterDaysAvailable: afterDaysAvailable,
                afterWindowIsComplete: complete,
                shifts: shifts
            )
            let sourceCollection = chapterSourceRecords(
                events: events,
                doseRecords: doseRecords,
                startDate: beforeStart,
                endDate: visibleAfterEnd
            )
            return CareStoryChapter(
                id: "chapter-\(anchor.id)",
                kind: anchor.kind,
                date: anchor.date,
                medicationName: anchor.medicationName,
                title: anchor.title,
                changeDetail: anchor.detail,
                sourceLabel: anchor.sourceLabel,
                beforeLabel: anchor.beforeLabel,
                afterLabel: complete ? anchor.afterLabel : "So far",
                before: before,
                after: after,
                afterWindowIsComplete: complete,
                signals: chapterSignals(
                    events: events,
                    doseRecords: doseRecords,
                    changeDate: anchor.date,
                    startDate: beforeStart,
                    endDate: visibleAfterEnd,
                    calendar: calendar
                ),
                sourceRecords: sourceCollection.records,
                sourceRecordCount: sourceCollection.totalCount,
                highlights: chapterHighlights(
                    events: events,
                    before: before,
                    after: after,
                    changeDate: anchor.date,
                    beforeStart: beforeStart,
                    afterEnd: visibleAfterEnd
                ),
                evidence: evidence,
                domainShifts: shifts,
                pulseHeadline: pulseHeadline(shifts: shifts),
                discussionPrompts: discussionPrompts(
                    shifts: shifts,
                    evidence: evidence,
                    afterWindowIsComplete: complete
                )
            )
        }
    }

    private static func detectedEpisodeAnchors(
        events: [CareStoryEventRecord],
        calendar: Calendar
    ) -> [ChapterAnchor] {
        var anchors: [ChapterAnchor] = []
        let symptomEvents = events.filter { $0.category == .symptom }
        let groupedSymptoms = Dictionary(grouping: symptomEvents) {
            normalizedSymptomName($0.symptomName ?? $0.title)
        }
        for (name, values) in groupedSymptoms where !name.isEmpty {
            for cluster in episodeClusters(values, maximumGapDays: 4, calendar: calendar) {
                let recordedDays = Set(cluster.map { calendar.startOfDay(for: $0.date) }).count
                guard cluster.count >= 2, recordedDays >= 2, let first = cluster.first else { continue }
                anchors.append(ChapterAnchor(
                    id: "symptom-\(first.id.uuidString)",
                    kind: .symptomEpisode,
                    date: first.date,
                    title: "\(displaySymptomName(first.symptomName ?? first.title)) episode",
                    detail: "\(cluster.count) entries across \(recordedDays) recorded days",
                    sourceLabel: "Detected from symptom entries",
                    medicationName: "",
                    beforeLabel: "Before",
                    afterLabel: "After",
                    seriesKey: "symptom-\(name)"
                ))
            }
        }

        let elevatedPainEvents = events.filter {
            $0.category == .pain && ($0.painScore ?? 0) >= 6
        }
        for cluster in episodeClusters(elevatedPainEvents, maximumGapDays: 4, calendar: calendar) {
            let recordedDays = Set(cluster.map { calendar.startOfDay(for: $0.date) }).count
            guard cluster.count >= 2, recordedDays >= 2, let first = cluster.first else { continue }
            let peak = cluster.compactMap(\.painScore).max() ?? 0
            anchors.append(ChapterAnchor(
                id: "pain-\(first.id.uuidString)",
                kind: .painEpisode,
                date: first.date,
                title: "Elevated-pain period",
                detail: "\(cluster.count) entries across \(recordedDays) days · highest recorded \(peak)/10",
                sourceLabel: "Detected from pain entries",
                medicationName: "",
                beforeLabel: "Before",
                afterLabel: "After",
                seriesKey: "pain"
            ))
        }

        var selected: [ChapterAnchor] = []
        var seriesCounts: [String: Int] = [:]
        for anchor in anchors.sorted(by: { $0.date > $1.date }) {
            let key = anchor.seriesKey ?? anchor.id
            guard seriesCounts[key, default: 0] < 2 else { continue }
            selected.append(anchor)
            seriesCounts[key, default: 0] += 1
            if selected.count == 6 { break }
        }
        return selected
    }

    private static func episodeClusters(
        _ events: [CareStoryEventRecord],
        maximumGapDays: Int,
        calendar: Calendar
    ) -> [[CareStoryEventRecord]] {
        let sorted = events.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        var clusters: [[CareStoryEventRecord]] = [[first]]
        for event in sorted.dropFirst() {
            guard let clusterStart = clusters[clusters.count - 1].first,
                  let previous = clusters[clusters.count - 1].last else { continue }
            let gap = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: previous.date),
                to: calendar.startOfDay(for: event.date)
            ).day ?? 0
            let span = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: clusterStart.date),
                to: calendar.startOfDay(for: event.date)
            ).day ?? 0
            if gap <= maximumGapDays, span < 7 {
                clusters[clusters.count - 1].append(event)
            } else {
                clusters.append([event])
            }
        }
        return clusters
    }

    private static func domainShifts(
        before: CareStoryWindowSummary,
        after: CareStoryWindowSummary,
        afterDaysAvailable: Int
    ) -> [CareStoryDomainShift] {
        let hasCompleteComparisonWindow = afterDaysAvailable >= 7
        let symptomComparable = hasCompleteComparisonWindow
            && before.symptomDays > 0
            && after.symptomDays > 0
        let activityComparable = hasCompleteComparisonWindow
            && before.activityDays > 0
            && after.activityDays > 0
        return [
            symptomShift(
                before: before,
                after: after,
                entriesComparable: symptomComparable
            ),
            decimalShift(
                domain: .pain,
                before: before.averagePainScore,
                after: after.averagePainScore,
                comparable: before.painDays >= 2 && after.painDays >= 2,
                threshold: 0.5,
                format: { "\(oneDecimal($0))/10" }
            ),
            decimalShift(
                domain: .sleep,
                before: before.averageSleepHours,
                after: after.averageSleepHours,
                comparable: before.sleepDays >= 2 && after.sleepDays >= 2,
                threshold: 0.5,
                format: { "\(oneDecimal($0))h avg" }
            ),
            integerShift(
                domain: .activity,
                before: before.activityDays,
                after: after.activityDays,
                comparable: activityComparable,
                unit: "days"
            ),
            bloodPressureShift(before: before, after: after),
            doseConsistencyShift(before: before, after: after)
        ]
    }

    private static func integerShift(
        domain: CareStoryDomain,
        before: Int,
        after: Int,
        comparable: Bool,
        unit: String
    ) -> CareStoryDomainShift {
        guard comparable else { return insufficientShift(domain) }
        let direction: CareStoryShiftDirection = before == after ? .similar : (after > before ? .higher : .lower)
        let changeLabel = direction == .similar
            ? "Similar recorded"
            : (direction == .higher ? "More recorded" : "Fewer recorded")
        return CareStoryDomainShift(
            domain: domain,
            beforeValue: "\(before) \(unit)",
            afterValue: "\(after) \(unit)",
            direction: direction,
            changeLabel: changeLabel,
            insight: "\(domain.displayName) moved from \(before) to \(after) recorded \(unit)."
        )
    }

    private static func symptomShift(
        before: CareStoryWindowSummary,
        after: CareStoryWindowSummary,
        entriesComparable: Bool
    ) -> CareStoryDomainShift {
        if before.symptomSeverityDays >= 2,
           after.symptomSeverityDays >= 2,
           before.averageSymptomSeverity != nil,
           after.averageSymptomSeverity != nil {
            return decimalShift(
                domain: .symptoms,
                before: before.averageSymptomSeverity,
                after: after.averageSymptomSeverity,
                comparable: true,
                threshold: 0.5,
                format: { "\(oneDecimal($0))/5 avg" }
            )
        }
        return integerShift(
            domain: .symptoms,
            before: before.symptomEntries,
            after: after.symptomEntries,
            comparable: entriesComparable,
            unit: "entries"
        )
    }

    private static func decimalShift(
        domain: CareStoryDomain,
        before: Double?,
        after: Double?,
        comparable: Bool,
        threshold: Double,
        format: (Double) -> String
    ) -> CareStoryDomainShift {
        guard comparable, let before, let after else { return insufficientShift(domain) }
        let difference = after - before
        let direction: CareStoryShiftDirection = abs(difference) < threshold
            ? .similar
            : (difference > 0 ? .higher : .lower)
        let changeLabel = direction == .similar
            ? "Similar recorded"
            : (direction == .higher ? "Higher recorded" : "Lower recorded")
        return CareStoryDomainShift(
            domain: domain,
            beforeValue: format(before),
            afterValue: format(after),
            direction: direction,
            changeLabel: changeLabel,
            insight: "Recorded \(domain.displayName.lowercased()) moved from \(format(before)) to \(format(after))."
        )
    }

    private static func bloodPressureShift(
        before: CareStoryWindowSummary,
        after: CareStoryWindowSummary
    ) -> CareStoryDomainShift {
        guard before.bloodPressureReadings >= 2,
              after.bloodPressureReadings >= 2,
              let beforeSystolic = before.averageSystolicBloodPressure,
              let beforeDiastolic = before.averageDiastolicBloodPressure,
              let afterSystolic = after.averageSystolicBloodPressure,
              let afterDiastolic = after.averageDiastolicBloodPressure else {
            return insufficientShift(.bloodPressure)
        }
        let beforeValue = "\(Int(beforeSystolic.rounded()))/\(Int(beforeDiastolic.rounded())) avg"
        let afterValue = "\(Int(afterSystolic.rounded()))/\(Int(afterDiastolic.rounded())) avg"
        let systolicDifference = afterSystolic - beforeSystolic
        let diastolicDifference = afterDiastolic - beforeDiastolic
        let direction: CareStoryShiftDirection
        if abs(systolicDifference) < 3, abs(diastolicDifference) < 2 {
            direction = .similar
        } else {
            direction = systolicDifference + diastolicDifference > 0 ? .higher : .lower
        }
        return CareStoryDomainShift(
            domain: .bloodPressure,
            beforeValue: beforeValue,
            afterValue: afterValue,
            direction: direction,
            changeLabel: direction == .similar
                ? "Similar recorded"
                : (direction == .higher ? "Higher recorded" : "Lower recorded"),
            insight: "Recorded blood-pressure averages moved from \(beforeValue) to \(afterValue)."
        )
    }

    private static func doseConsistencyShift(
        before: CareStoryWindowSummary,
        after: CareStoryWindowSummary
    ) -> CareStoryDomainShift {
        guard before.recordedDoseCount >= 2, after.recordedDoseCount >= 2 else {
            return insufficientShift(.doseConsistency)
        }
        let beforeRate = Double(before.doseExceptionCount) / Double(before.recordedDoseCount)
        let afterRate = Double(after.doseExceptionCount) / Double(after.recordedDoseCount)
        let difference = afterRate - beforeRate
        let direction: CareStoryShiftDirection = abs(difference) < 0.1
            ? .similar
            : (difference > 0 ? .higher : .lower)
        let beforeValue = "\(before.doseExceptionCount) of \(before.recordedDoseCount) exceptions"
        let afterValue = "\(after.doseExceptionCount) of \(after.recordedDoseCount) exceptions"
        return CareStoryDomainShift(
            domain: .doseConsistency,
            beforeValue: beforeValue,
            afterValue: afterValue,
            direction: direction,
            changeLabel: direction == .similar
                ? "Similar recorded"
                : (direction == .higher ? "More exceptions" : "Fewer exceptions"),
            insight: "Recorded dose exceptions moved from \(beforeValue) to \(afterValue)."
        )
    }

    private static func insufficientShift(_ domain: CareStoryDomain) -> CareStoryDomainShift {
        CareStoryDomainShift(
            domain: domain,
            beforeValue: "Not enough",
            afterValue: "Not enough",
            direction: .insufficient,
            changeLabel: "Keep logging",
            insight: "There is not enough recorded \(domain.displayName.lowercased()) data in both windows yet."
        )
    }

    private static func chapterEvidence(
        before: CareStoryWindowSummary,
        after: CareStoryWindowSummary,
        afterDaysAvailable: Int,
        afterWindowIsComplete: Bool,
        shifts: [CareStoryDomainShift]
    ) -> CareStoryEvidence {
        let comparableCount = shifts.count { $0.isComparable }
        let level: CareStoryEvidenceLevel
        if afterWindowIsComplete,
           before.activeRecordDays >= 4,
           after.activeRecordDays >= 4,
           comparableCount >= 3 {
            level = .strong
        } else if afterDaysAvailable >= 3,
                  before.activeRecordDays >= 2,
                  after.activeRecordDays >= 2,
                  comparableCount >= 1 {
            level = .building
        } else {
            level = .early
        }
        return CareStoryEvidence(
            level: level,
            comparableDomainCount: comparableCount,
            beforeActiveDays: min(7, before.activeRecordDays),
            afterActiveDays: min(afterDaysAvailable, after.activeRecordDays),
            afterDaysAvailable: afterDaysAvailable
        )
    }

    private static func pulseHeadline(shifts: [CareStoryDomainShift]) -> String {
        let changed = shifts.filter { $0.isComparable && $0.direction != .similar }
        if changed.count >= 2 {
            return "\(changed[0].domain.displayName) and \(changed[1].domain.displayName.lowercased()) show the clearest recorded shifts."
        }
        if let changed = changed.first {
            return "\(changed.domain.displayName) shows the clearest recorded shift."
        }
        let comparableCount = shifts.count { $0.isComparable }
        if comparableCount > 0 {
            return "Comparable recorded patterns were broadly similar across \(comparableCount) areas."
        }
        return "This story is still taking shape as more care is recorded."
    }

    private static func discussionPrompts(
        shifts: [CareStoryDomainShift],
        evidence: CareStoryEvidence,
        afterWindowIsComplete: Bool
    ) -> [String] {
        var prompts: [String] = []
        if !afterWindowIsComplete {
            prompts.append("This follow-up window is still in progress. What would be useful to keep recording?")
        }
        for shift in shifts where shift.isComparable && shift.direction != .similar {
            let prompt: String
            switch shift.domain {
            case .symptoms:
                prompt = "Does the recorded symptom shift match what caregivers remember?"
            case .pain:
                prompt = "Does the recorded pain shift match day-to-day experience?"
            case .sleep:
                prompt = "Was anything else different on the days when sleep changed?"
            case .activity:
                prompt = "Did routine, mobility, or opportunity affect the activity days recorded?"
            case .bloodPressure:
                prompt = "Are the before-and-after blood-pressure averages useful to review at the next visit?"
            case .doseConsistency:
                prompt = "Were timing, supply, refusal, or routine factors behind the dose exceptions?"
            }
            prompts.append(prompt)
            if prompts.count == 3 { break }
        }
        if prompts.isEmpty || (prompts.count == 1 && evidence.level == .early) {
            prompts.append("Do these recorded patterns match what caregivers noticed outside the app?")
        }
        return Array(prompts.prefix(3))
    }

    private static func windowSummary(
        events: [CareStoryEventRecord],
        doseRecords: [CareStoryDoseRecord],
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> CareStoryWindowSummary {
        let windowEvents = events.filter { $0.date >= startDate && $0.date < endDate }
        let symptomDays = Set(windowEvents.filter { $0.category == .symptom }.map {
            calendar.startOfDay(for: $0.date)
        }).count
        let symptomSeverityEvents = windowEvents.filter {
            $0.category == .symptom && $0.symptomSeverity != nil
        }
        let symptomSeverities = symptomSeverityEvents.compactMap(\.symptomSeverity)
        let symptomSeverityDays = Set(symptomSeverityEvents.map {
            calendar.startOfDay(for: $0.date)
        }).count
        let painEvents = windowEvents.filter { $0.category == .pain }.compactMap(\.painScore)
        let painDays = Set(windowEvents.filter { $0.category == .pain }.map {
            calendar.startOfDay(for: $0.date)
        }).count
        let activityDays = Set(windowEvents.filter { $0.category == .activity }.map {
            calendar.startOfDay(for: $0.date)
        }).count
        let sleepHours = windowEvents
            .filter { $0.category == .sleep }
            .compactMap(\.durationMinutes)
            .filter { $0 > 0 }
            .map { $0 / 60 }
        let sleepDays = Set(windowEvents.filter {
            $0.category == .sleep && ($0.durationMinutes ?? 0) > 0
        }.map { calendar.startOfDay(for: $0.date) }).count
        let bloodPressureValues = windowEvents.compactMap { event -> (Double, Double)? in
            guard let systolic = event.systolicBloodPressure,
                  let diastolic = event.diastolicBloodPressure else { return nil }
            return (Double(systolic), Double(diastolic))
        }
        let windowDoses = doseRecords.filter { $0.date >= startDate && $0.date < endDate }
        let missedDoseCount = windowDoses.count {
            $0.status == .missed || $0.status == .skipped
        }
        let activeEventDays = windowEvents.map { calendar.startOfDay(for: $0.date) }
        let activeDoseDays = windowDoses.map { calendar.startOfDay(for: $0.date) }

        return CareStoryWindowSummary(
            symptomEntries: windowEvents.count { $0.category == .symptom },
            symptomDays: symptomDays,
            averageSymptomSeverity: symptomSeverities.isEmpty
                ? nil
                : Double(symptomSeverities.reduce(0, +)) / Double(symptomSeverities.count),
            symptomSeverityDays: symptomSeverityDays,
            averagePainScore: painEvents.isEmpty
                ? nil
                : Double(painEvents.reduce(0, +)) / Double(painEvents.count),
            painDays: painDays,
            activityDays: activityDays,
            averageSleepHours: sleepHours.isEmpty
                ? nil
                : sleepHours.reduce(0, +) / Double(sleepHours.count),
            sleepDays: sleepDays,
            bloodPressureReadings: bloodPressureValues.count,
            averageSystolicBloodPressure: bloodPressureValues.isEmpty
                ? nil
                : bloodPressureValues.reduce(0) { $0 + $1.0 } / Double(bloodPressureValues.count),
            averageDiastolicBloodPressure: bloodPressureValues.isEmpty
                ? nil
                : bloodPressureValues.reduce(0) { $0 + $1.1 } / Double(bloodPressureValues.count),
            missedDoseCount: missedDoseCount,
            doseExceptionCount: windowDoses.count { $0.isException },
            recordedDoseCount: windowDoses.count,
            activeRecordDays: Set(activeEventDays + activeDoseDays).count
        )
    }

    private static func chapterSignals(
        events: [CareStoryEventRecord],
        doseRecords: [CareStoryDoseRecord],
        changeDate: Date,
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> [CareStoryChapterSignal] {
        let changeDay = calendar.startOfDay(for: changeDate)
        var counts: [ChapterSignalKey: Int] = [:]

        for event in events where event.date >= startDate && event.date < endDate {
            let eventDay = calendar.startOfDay(for: event.date)
            let offset = calendar.dateComponents([.day], from: changeDay, to: eventDay).day ?? 0
            guard (-7...7).contains(offset) else { continue }
            counts[ChapterSignalKey(dayOffset: offset, category: event.category), default: 0] += 1
        }
        for dose in doseRecords
            where dose.date >= startDate && dose.date < endDate && dose.isException {
            let doseDay = calendar.startOfDay(for: dose.date)
            let offset = calendar.dateComponents([.day], from: changeDay, to: doseDay).day ?? 0
            guard (-7...7).contains(offset) else { continue }
            counts[ChapterSignalKey(dayOffset: offset, category: .medication), default: 0] += 1
        }

        return counts.map { key, count in
            CareStoryChapterSignal(
                id: "\(key.dayOffset)-\(key.category.rawValue)",
                dayOffset: key.dayOffset,
                category: key.category,
                count: count
            )
        }
        .sorted {
            if $0.dayOffset != $1.dayOffset { return $0.dayOffset < $1.dayOffset }
            return categoryOrder($0.category) < categoryOrder($1.category)
        }
    }

    private struct ChapterSourceCollection {
        let records: [CareStorySourceRecord]
        let totalCount: Int
    }

    private static func chapterSourceRecords(
        events: [CareStoryEventRecord],
        doseRecords: [CareStoryDoseRecord],
        startDate: Date,
        endDate: Date
    ) -> ChapterSourceCollection {
        var records = events
            .filter { $0.date >= startDate && $0.date < endDate }
            .map { event in
                CareStorySourceRecord(
                    id: "event-\(event.id.uuidString)",
                    date: event.date,
                    category: event.category,
                    title: event.title,
                    detail: event.detail
                )
            }
        records += doseRecords
            .filter { $0.date >= startDate && $0.date < endDate && $0.isException }
            .map { dose in
                let item = timelineItem(for: dose)
                return CareStorySourceRecord(
                    id: item.id,
                    date: item.date,
                    category: .medication,
                    title: item.title,
                    detail: item.detail
                )
            }
        let sorted = records
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id < $1.id
            }
        return ChapterSourceCollection(
            records: sorted
            .prefix(80)
            .map { $0 },
            totalCount: sorted.count
        )
    }

    private static func chapterHighlights(
        events: [CareStoryEventRecord],
        before: CareStoryWindowSummary,
        after: CareStoryWindowSummary,
        changeDate: Date,
        beforeStart: Date,
        afterEnd: Date
    ) -> [String] {
        let beforeSymptoms = events.filter {
            $0.category == .symptom && $0.date >= beforeStart && $0.date < changeDate
        }
        let afterSymptoms = events.filter {
            $0.category == .symptom && $0.date >= changeDate && $0.date < afterEnd
        }
        var values: [String] = []

        let groupedAfterSymptoms = Dictionary(grouping: afterSymptoms) {
            normalizedSymptomName($0.symptomName ?? $0.title)
        }
        if let mostFrequent = groupedAfterSymptoms
            .filter({ !$0.key.isEmpty && $0.value.count >= 2 })
            .max(by: { $0.value.count < $1.value.count }) {
            let beforeCount = beforeSymptoms.count {
                normalizedSymptomName($0.symptomName ?? $0.title) == mostFrequent.key
            }
            let name = displaySymptomName(mostFrequent.value.first?.symptomName ?? mostFrequent.key)
            values.append(
                "\(mostFrequent.value.count) \(name.lowercased()) \(entryWord(mostFrequent.value.count)) after the change; \(beforeCount) before."
            )
        } else if before.symptomEntries > 0 || after.symptomEntries > 0 {
            values.append(
                "Symptom entries: \(before.symptomEntries) before and \(after.symptomEntries) after."
            )
        }

        if let beforePain = before.averagePainScore, let afterPain = after.averagePainScore {
            values.append(
                "Recorded pain averaged \(oneDecimal(beforePain)) before and \(oneDecimal(afterPain)) after."
            )
        } else if after.painDays > 0 {
            values.append("Pain was recorded on \(after.painDays) \(dayWord(after.painDays)) after the change.")
        }

        if before.activityDays > 0 || after.activityDays > 0 {
            values.append(
                "Activity was logged on \(before.activityDays) days before and \(after.activityDays) days after."
            )
        }
        if before.missedDoseCount > 0 || after.missedDoseCount > 0 {
            values.append(
                "Missed or skipped doses: \(before.missedDoseCount) before and \(after.missedDoseCount) after."
            )
        }
        if values.isEmpty, before.bloodPressureReadings > 0 || after.bloodPressureReadings > 0 {
            values.append(
                "Blood-pressure readings: \(before.bloodPressureReadings) before and \(after.bloodPressureReadings) after."
            )
        }
        return Array(values.prefix(3))
    }

    private static func changeDetail(_ change: CareStoryMedicationChangeRecord) -> String? {
        var values: [String] = []
        if let beforeDose = nonBlank(change.beforeDose),
           let afterDose = nonBlank(change.afterDose),
           beforeDose != afterDose {
            values.append("Dose: \(beforeDose) → \(afterDose)")
        }
        if let beforeSchedule = nonBlank(change.beforeSchedule),
           let afterSchedule = nonBlank(change.afterSchedule),
           beforeSchedule != afterSchedule {
            values.append("Schedule: \(beforeSchedule) → \(afterSchedule)")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private static func categoryOrder(_ category: CareStoryCategory) -> Int {
        CareStoryCategory.allCases.firstIndex(of: category) ?? 0
    }

    private static func observations(
        events: [CareStoryEventRecord],
        medicationChanges: [CareStoryMedicationChangeRecord],
        doseRecords: [CareStoryDoseRecord],
        calendar: Calendar
    ) -> [CareStoryObservation] {
        var values = symptomTimingObservations(
            events: events,
            medicationChanges: medicationChanges,
            calendar: calendar
        )
        if let painComparison = painAndActivityObservation(events: events, calendar: calendar) {
            values.append(painComparison)
        }
        if let bloodPressure = bloodPressureAndMissedDoseObservation(
            events: events,
            doseRecords: doseRecords
        ) {
            values.append(bloodPressure)
        }
        return Array(values.prefix(4))
    }

    private static func symptomTimingObservations(
        events: [CareStoryEventRecord],
        medicationChanges: [CareStoryMedicationChangeRecord],
        calendar: Calendar
    ) -> [CareStoryObservation] {
        let symptoms = events.filter { $0.category == .symptom }
        var results: [CareStoryObservation] = []
        var reportedSymptoms = Set<String>()

        for change in medicationChanges
            .filter({ $0.changeKind != .confirmedCurrent })
            .sorted(by: { $0.date > $1.date }) {
            guard let windowEnd = calendar.date(byAdding: .day, value: 7, to: change.date) else {
                continue
            }
            let windowSymptoms = symptoms.filter { $0.date >= change.date && $0.date < windowEnd }
            let grouped = Dictionary(grouping: windowSymptoms) { event in
                normalizedSymptomName(event.symptomName ?? event.title)
            }
            guard let mostFrequent = grouped
                .filter({ !$0.key.isEmpty && $0.value.count >= 2 && !reportedSymptoms.contains($0.key) })
                .max(by: {
                    if $0.value.count != $1.value.count { return $0.value.count < $1.value.count }
                    return $0.key > $1.key
                }) else { continue }

            reportedSymptoms.insert(mostFrequent.key)
            let count = mostFrequent.value.count
            let symptom = displaySymptomName(mostFrequent.value.first?.symptomName ?? mostFrequent.key)
            let changeDescription = change.changeKind == .updated
                ? "\(cleanMedicationName(change.medicationName))’s plan changed"
                : "\(cleanMedicationName(change.medicationName)) was \(change.changeKind == .stopped ? "stopped" : "started")"
            results.append(CareStoryObservation(
                id: "symptom-\(change.id.uuidString)-\(mostFrequent.key)",
                kind: .timing,
                statement: "\(count) \(symptom.lowercased()) \(entryWord(count)) were recorded in the seven days after \(changeDescription).",
                caution: "This is a timing observation only and does not show what caused the symptom."
            ))
            if results.count == 2 { break }
        }
        return results
    }

    private static func painAndActivityObservation(
        events: [CareStoryEventRecord],
        calendar: Calendar
    ) -> CareStoryObservation? {
        let painEvents = events.filter { $0.category == .pain && $0.painScore != nil }
        let activityDays = Set(events.filter { $0.category == .activity }.map {
            calendar.startOfDay(for: $0.date)
        })
        let painByDay = Dictionary(grouping: painEvents) { calendar.startOfDay(for: $0.date) }
        let dailyAverages = painByDay.compactMapValues { values -> Double? in
            let scores = values.compactMap(\.painScore)
            guard !scores.isEmpty else { return nil }
            return Double(scores.reduce(0, +)) / Double(scores.count)
        }
        let activityPain = dailyAverages.filter { activityDays.contains($0.key) }.map(\.value)
        let otherPain = dailyAverages.filter { !activityDays.contains($0.key) }.map(\.value)
        guard activityPain.count >= 2, otherPain.count >= 2 else { return nil }

        let activityAverage = activityPain.reduce(0, +) / Double(activityPain.count)
        let otherAverage = otherPain.reduce(0, +) / Double(otherPain.count)
        guard abs(activityAverage - otherAverage) >= 0.5 else { return nil }
        let direction = activityAverage < otherAverage ? "lower" : "higher"
        return CareStoryObservation(
            id: "pain-activity-comparison",
            kind: .comparison,
            statement: "Recorded pain scores averaged \(direction) on days that also had activity logs (\(oneDecimal(activityAverage)) vs \(oneDecimal(otherAverage)) on other recorded days).",
            caution: "This compares logged days only and does not show that activity changed pain."
        )
    }

    private static func bloodPressureAndMissedDoseObservation(
        events: [CareStoryEventRecord],
        doseRecords: [CareStoryDoseRecord]
    ) -> CareStoryObservation? {
        let readingCount = events.count { $0.category == .vital && $0.isBloodPressure }
        let missedCount = doseRecords.count { $0.status == .missed || $0.status == .skipped }
        guard readingCount > 0, missedCount > 0 else { return nil }
        return CareStoryObservation(
            id: "blood-pressure-missed-doses",
            kind: .discussion,
            statement: "\(readingCount) blood-pressure \(readingWord(readingCount)) and \(missedCount) missed \(doseWord(missedCount)) are shown together for discussion at the next visit.",
            caution: "Their appearance on the same timeline does not imply that one affected the other."
        )
    }

    private static func doseOrScheduleChanged(_ change: CareStoryMedicationChangeRecord) -> Bool {
        nonBlank(change.beforeDose) != nonBlank(change.afterDose)
            || nonBlank(change.beforeSchedule) != nonBlank(change.afterSchedule)
    }

    private static func normalizedSymptomName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "Symptom:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func displaySymptomName(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "Symptom:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Symptom" : cleaned
    }

    private static func cleanMedicationName(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Medication" : cleaned
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func entryWord(_ count: Int) -> String { count == 1 ? "entry" : "entries" }
    private static func readingWord(_ count: Int) -> String { count == 1 ? "reading" : "readings" }
    private static func doseWord(_ count: Int) -> String { count == 1 ? "dose" : "doses" }
    private static func dayWord(_ count: Int) -> String { count == 1 ? "day" : "days" }
}
