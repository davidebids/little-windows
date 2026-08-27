import Foundation
import SwiftData
import UserNotifications

struct MedicationOccurrence: Identifiable, Equatable, Hashable {
    var regimenID: UUID
    var medicationID: UUID
    var phaseID: UUID?
    var scheduledAt: Date
    var doseAmount: Double
    var doseUnit: String
    var scheduleKey: String? = nil

    var occurrenceKey: String {
        scheduleKey ?? "\(regimenID.uuidString)|\(Int(scheduledAt.timeIntervalSince1970))"
    }

    var id: String { occurrenceKey }
}

struct MedicationScheduledDoseReference {
    var profileID: UUID
    var medicationID: UUID
    var regimenID: UUID
    var phaseID: UUID?
    var occurrenceKey: String
    var scheduledAt: Date
    var doseAmount: Double
    var doseUnit: String
}

enum MedicationScheduledDoseResolution {
    case valid(
        medication: Medication,
        regimen: MedicationRegimen,
        occurrence: MedicationOccurrence,
        existingRecord: MedicationDoseRecord?
    )
    case rejected(String)
}

enum MedicationScheduledDoseMutationResult: Equatable {
    case applied(medicationName: String)
    case duplicate(medicationName: String)
    case rejected(String)
}

struct MedicationAdherenceSummary: Equatable {
    var scheduledCount: Int
    var takenCount: Int
    var skippedCount: Int
    var missedCount: Int
    var heldCount: Int = 0
    var refusedCount: Int = 0
    var unableCount: Int = 0
    var recordedMissedCount: Int = 0
    var lateCount: Int = 0
    var differentAmountCount: Int = 0
    var takenExceptionCount: Int = 0

    var completionRate: Double? {
        guard scheduledCount > 0 else { return nil }
        return Double(takenCount) / Double(scheduledCount)
    }

    var recordedNotTakenCount: Int {
        skippedCount + heldCount + refusedCount + unableCount + recordedMissedCount
    }

    var exceptionCount: Int {
        recordedNotTakenCount + missedCount + takenExceptionCount
    }
}

enum MedicationAsNeededDecision: Equatable {
    case allowed
    case waitUntil(Date)
    case dailyLimitReached(Int)
}

enum MedicationSnoozeStateStore {
    private static let storageKey = "medication.activeSnoozes.v1"
    private static let maximumEntryCount = 256

    static func isSnoozed(
        occurrenceKey: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        let entries = activeEntries(now: now, defaults: defaults)
        return entries[occurrenceKey].map { $0 > now.timeIntervalSince1970 } ?? false
    }

    static func activeOccurrenceKeys(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        Set(activeEntries(now: now, defaults: defaults).keys)
    }

    static func markSnoozed(
        occurrenceKey: String,
        until fireDate: Date,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard !occurrenceKey.isEmpty, fireDate > now else { return }
        var entries = activeEntries(now: now, defaults: defaults)
        entries[occurrenceKey] = fireDate.timeIntervalSince1970
        if entries.count > maximumEntryCount {
            for key in entries
                .sorted(by: { $0.value < $1.value })
                .prefix(entries.count - maximumEntryCount)
                .map(\.key) {
                entries.removeValue(forKey: key)
            }
        }
        defaults.set(entries, forKey: storageKey)
    }

    static func clear(
        occurrenceKey: String,
        defaults: UserDefaults = .standard
    ) {
        var entries = storedEntries(defaults: defaults)
        guard entries.removeValue(forKey: occurrenceKey) != nil else { return }
        defaults.set(entries, forKey: storageKey)
    }

    static func clear(
        regimenID: UUID,
        defaults: UserDefaults = .standard
    ) {
        var entries = storedEntries(defaults: defaults)
        let prefix = "\(regimenID.uuidString)|"
        let matchingKeys = entries.keys.filter { $0.hasPrefix(prefix) }
        guard !matchingKeys.isEmpty else { return }
        for key in matchingKeys {
            entries.removeValue(forKey: key)
        }
        defaults.set(entries, forKey: storageKey)
    }

    static func retain(
        occurrenceKeys: Set<String>,
        for regimenID: UUID,
        defaults: UserDefaults = .standard
    ) {
        var entries = storedEntries(defaults: defaults)
        let prefix = "\(regimenID.uuidString)|"
        let discardedKeys = entries.keys.filter {
            $0.hasPrefix(prefix) && !occurrenceKeys.contains($0)
        }
        guard !discardedKeys.isEmpty else { return }
        for key in discardedKeys {
            entries.removeValue(forKey: key)
        }
        defaults.set(entries, forKey: storageKey)
    }

    private static func activeEntries(
        now: Date,
        defaults: UserDefaults
    ) -> [String: TimeInterval] {
        let entries = storedEntries(defaults: defaults)
        let active = entries.filter { $0.value > now.timeIntervalSince1970 }
        if active.count != entries.count {
            defaults.set(active, forKey: storageKey)
        }
        return active
    }

    private static func storedEntries(defaults: UserDefaults) -> [String: TimeInterval] {
        let values = defaults.dictionary(forKey: storageKey) ?? [:]
        return values.reduce(into: [:]) { result, value in
            if let timestamp = value.value as? NSNumber {
                result[value.key] = timestamp.doubleValue
            }
        }
    }
}

enum MedicationScheduleEngine {
    static func occurrences(
        regimen: MedicationRegimen,
        phases: [MedicationSchedulePhase],
        from rangeStart: Date,
        through rangeEnd: Date,
        calendar sourceCalendar: Calendar = MedicationScheduleDate.currentCalendar(),
        includeInactive: Bool = false
    ) -> [MedicationOccurrence] {
        guard (includeInactive || regimen.isActive),
              regimen.scheduleKind.isScheduled,
              rangeStart <= rangeEnd else { return [] }

        var calendar = sourceCalendar
        if regimen.timeZoneBehavior == .fixedTimeZone,
           let identifier = regimen.timeZoneIdentifier,
           let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }

        let regimenStartDay = anchoredDay(
            for: regimen.startDate,
            anchorTimeZoneIdentifier: regimen.timeZoneIdentifier,
            calendar: calendar
        )
        let regimenEndDay = regimen.endDate.map {
            anchoredDay(
                for: $0,
                anchorTimeZoneIdentifier: regimen.timeZoneIdentifier,
                calendar: calendar
            )
        }
        var day = max(calendar.startOfDay(for: rangeStart), regimenStartDay)
        let finalDay = calendar.startOfDay(for: rangeEnd)
        let sortedPhases = phases
            .filter { $0.regimenID == regimen.id }
            .sorted { $0.sequence < $1.sequence }
        var result = [MedicationOccurrence]()

        while day <= finalDay {
            if let regimenEndDay,
               day > regimenEndDay {
                break
            }
            let dayIndex = max(
                calendar.dateComponents([.day], from: regimenStartDay, to: day).day ?? 0,
                0
            )
            if isScheduledDay(
                regimen: regimen,
                day: day,
                dayIndex: dayIndex,
                calendar: calendar
            ) {
                let phase = phaseForDay(
                    kind: regimen.scheduleKind,
                    dayIndex: dayIndex,
                    phases: sortedPhases
                )
                if regimen.scheduleKind != .taper || phase != nil || sortedPhases.isEmpty {
                    let doseAmount = phase?.doseAmount ?? regimen.doseAmount
                    let doseUnit = phase?.doseUnit ?? regimen.doseUnit
                    let configuredDoseTimes = phase?.doseTimes.isEmpty == false
                        ? phase!.doseTimes
                        : regimen.doseTimes
                    let doseTimes = Array(Set(configuredDoseTimes)).sorted {
                        ($0.hour, $0.minute) < ($1.hour, $1.minute)
                    }
                    for doseTime in doseTimes {
                        guard let scheduledAt = doseTime.date(on: day, calendar: calendar),
                              scheduledAt >= rangeStart,
                              scheduledAt <= rangeEnd,
                              scheduledAt >= regimenStartDay,
                              regimenEndDay.map({ scheduledAt < calendar.date(byAdding: .day, value: 1, to: $0)! }) ?? true else {
                            continue
                        }
                        result.append(MedicationOccurrence(
                            regimenID: regimen.id,
                            medicationID: regimen.medicationID,
                            phaseID: phase?.id,
                            scheduledAt: scheduledAt,
                            doseAmount: doseAmount,
                            doseUnit: doseUnit,
                            scheduleKey: occurrenceKey(
                                regimenID: regimen.id,
                                scheduledAt: scheduledAt,
                                calendar: calendar
                            )
                        ))
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return result.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    static func versionedOccurrences(
        medicationID: UUID,
        regimens: [MedicationRegimen],
        phases: [MedicationSchedulePhase],
        revisions: [MedicationPlanRevision],
        from rangeStart: Date,
        through rangeEnd: Date,
        calendar: Calendar = MedicationScheduleDate.currentCalendar()
    ) -> [MedicationOccurrence] {
        guard rangeStart <= rangeEnd else { return [] }
        let medicationRegimens = regimens.filter { $0.medicationID == medicationID }
        let regimensByID = Dictionary(
            uniqueKeysWithValues: medicationRegimens.map { ($0.id, $0) }
        )
        func effectiveBoundary(for revision: MedicationPlanRevision) -> Date {
            guard calendar.isDate(revision.effectiveFrom, inSameDayAs: revision.changedAt) else {
                return revision.effectiveFrom
            }
            return max(revision.effectiveFrom, revision.changedAt)
        }
        let allLifecycleRevisionEntries = revisions
            .filter {
                $0.medicationID == medicationID && $0.changeKind != .confirmedCurrent
            }
            .map { revision in
                (revision: revision, boundary: effectiveBoundary(for: revision))
            }
            .sorted {
                if $0.boundary != $1.boundary {
                    return $0.boundary < $1.boundary
                }
                if $0.revision.changedAt != $1.revision.changedAt {
                    return $0.revision.changedAt < $1.revision.changedAt
                }
                return $0.revision.id.uuidString < $1.revision.id.uuidString
            }
        let allLifecycleRevisions = allLifecycleRevisionEntries.map(\.revision)
        let effectiveBoundariesByRevisionID = Dictionary(
            uniqueKeysWithValues: allLifecycleRevisionEntries.map { ($0.revision.id, $0.boundary) }
        )

        // Family Sync can preserve two concurrent plan-edit audit branches while
        // conflict resolution leaves only one regimen active. Reconstruct the
        // branch leading to that authoritative regimen so the abandoned branch
        // remains auditable without creating duplicate expected doses.
        var terminalRegimenIDs = Set(
            medicationRegimens.filter(\.isActive).map(\.id)
        )
        if terminalRegimenIDs.isEmpty,
           let stoppedRevision = allLifecycleRevisions.last(where: { $0.changeKind == .stopped }),
           let stoppedRegimenID = stoppedRevision.priorRegimenID ?? stoppedRevision.regimenID {
            terminalRegimenIDs.insert(stoppedRegimenID)
        }
        if terminalRegimenIDs.isEmpty,
           let latestRegimenID = allLifecycleRevisions.reversed().compactMap(\.regimenID).first {
            terminalRegimenIDs.insert(latestRegimenID)
        }

        var branchRegimenIDs = terminalRegimenIDs
        var selectedUpdateRevisionIDs = Set<UUID>()
        var pendingRegimenIDs = Array(terminalRegimenIDs)
        let updateRevisionsByRegimenID = Dictionary(
            grouping: allLifecycleRevisions.filter { revision in
                revision.changeKind == .updated && revision.regimenID != nil
            },
            by: { $0.regimenID! }
        )
        while let regimenID = pendingRegimenIDs.popLast() {
            guard let revision = updateRevisionsByRegimenID[regimenID]?.last else { continue }
            selectedUpdateRevisionIDs.insert(revision.id)
            if let priorRegimenID = revision.priorRegimenID,
               branchRegimenIDs.insert(priorRegimenID).inserted {
                pendingRegimenIDs.append(priorRegimenID)
            }
        }

        let lifecycleRevisions = allLifecycleRevisions.filter { revision in
            switch revision.changeKind {
            case .updated:
                selectedUpdateRevisionIDs.contains(revision.id)
            case .added, .restored:
                revision.regimenID.map(branchRegimenIDs.contains) ?? false
            case .stopped:
                (revision.priorRegimenID ?? revision.regimenID)
                    .map(branchRegimenIDs.contains) ?? false
            case .confirmedCurrent:
                false
            }
        }

        struct Interval {
            var regimenID: UUID
            var start: Date
            var end: Date
        }
        var activeStarts = [UUID: Date]()
        var intervals = [Interval]()

        func close(_ regimenID: UUID, at end: Date) {
            guard let start = activeStarts.removeValue(forKey: regimenID), start < end else { return }
            intervals.append(Interval(regimenID: regimenID, start: start, end: end))
        }

        for revision in lifecycleRevisions {
            guard let boundary = effectiveBoundariesByRevisionID[revision.id] else { continue }
            switch revision.changeKind {
            case .added, .restored:
                if let regimenID = revision.regimenID, regimensByID[regimenID] != nil {
                    if activeStarts[regimenID] != nil { close(regimenID, at: boundary) }
                    activeStarts[regimenID] = boundary
                }
            case .updated:
                if let priorRegimenID = revision.priorRegimenID {
                    close(priorRegimenID, at: boundary)
                }
                if let regimenID = revision.regimenID, regimensByID[regimenID] != nil {
                    activeStarts[regimenID] = boundary
                }
            case .stopped:
                if let regimenID = revision.priorRegimenID ?? revision.regimenID {
                    close(regimenID, at: boundary)
                }
            case .confirmedCurrent:
                break
            }
        }
        activeStarts.forEach { regimenID, start in
            guard start <= rangeEnd else { return }
            intervals.append(Interval(
                regimenID: regimenID,
                start: start,
                end: rangeEnd.addingTimeInterval(0.001)
            ))
        }

        if allLifecycleRevisions.isEmpty {
            intervals = medicationRegimens.compactMap { regimen in
                let end = regimen.isActive
                    ? rangeEnd.addingTimeInterval(0.001)
                    : regimen.updatedAt
                guard regimen.startDate < end else { return nil }
                return Interval(regimenID: regimen.id, start: regimen.startDate, end: end)
            }
        }

        let phasesByRegimenID = Dictionary(grouping: phases, by: \.regimenID)
        return intervals.flatMap { interval -> [MedicationOccurrence] in
            guard let regimen = regimensByID[interval.regimenID] else { return [] }
            let start = max(rangeStart, interval.start)
            let endExclusive = min(rangeEnd.addingTimeInterval(0.001), interval.end)
            guard start < endExclusive else { return [] }
            return occurrences(
                regimen: regimen,
                phases: phasesByRegimenID[regimen.id] ?? [],
                from: start,
                through: endExclusive.addingTimeInterval(-0.001),
                calendar: calendar,
                includeInactive: true
            )
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    static func adherence(
        occurrences: [MedicationOccurrence],
        records: [MedicationDoseRecord],
        through now: Date = Date()
    ) -> MedicationAdherenceSummary {
        let expected = occurrences.filter { $0.scheduledAt <= now }
        let recordsByKey = Dictionary(
            records.compactMap { record in
                record.occurrenceKey.map { ($0, record) }
            },
            uniquingKeysWith: { first, second in
                first.loggedAt >= second.loggedAt ? first : second
            }
        )
        let expectedRecords = expected.compactMap { recordsByKey[$0.occurrenceKey] }
        let taken = expectedRecords.count { $0.status == .taken }
        let skipped = expectedRecords.count { $0.status == .skipped }
        return MedicationAdherenceSummary(
            scheduledCount: expected.count,
            takenCount: taken,
            skippedCount: skipped,
            missedCount: max(expected.count - expectedRecords.count, 0),
            heldCount: expectedRecords.count { $0.status == .held },
            refusedCount: expectedRecords.count { $0.status == .refused },
            unableCount: expectedRecords.count { $0.status == .unable },
            recordedMissedCount: expectedRecords.count { $0.status == .missed },
            lateCount: expectedRecords.count { $0.status == .taken && $0.timing == .late },
            differentAmountCount: expectedRecords.count { $0.hasDifferentActualAmount },
            takenExceptionCount: expectedRecords.count {
                $0.status == .taken && ($0.timing == .late || $0.hasDifferentActualAmount)
            }
        )
    }

    static func unloggedOccurrences(
        _ occurrences: [MedicationOccurrence],
        records: [MedicationDoseRecord]
    ) -> [MedicationOccurrence] {
        let loggedKeys = Set(records.compactMap(\.occurrenceKey))
        return occurrences.filter { !loggedKeys.contains($0.occurrenceKey) }
    }

    static func asNeededDecision(
        regimen: MedicationRegimen,
        records: [MedicationDoseRecord],
        at date: Date = Date(),
        calendar: Calendar = MedicationScheduleDate.currentCalendar()
    ) -> MedicationAsNeededDecision {
        var latestTakenAt: Date?
        var todayCount = 0
        for record in records {
            let actualTime = record.takenAt ?? record.loggedAt
            guard record.regimenID == regimen.id,
                  record.status == .taken,
                  actualTime <= date else { continue }
            if latestTakenAt.map({ actualTime > $0 }) ?? true {
                latestTakenAt = actualTime
            }
            if calendar.isDate(actualTime, inSameDayAs: date) {
                todayCount += 1
            }
        }
        if let maximum = regimen.maximumDosesPerDay {
            if todayCount >= maximum {
                return .dailyLimitReached(maximum)
            }
        }
        if let minimumHours = regimen.minimumHoursBetweenDoses,
           let last = latestTakenAt {
            let next = last.addingTimeInterval(minimumHours * 60 * 60)
            if date < next { return .waitUntil(next) }
        }
        return .allowed
    }

    private static func isScheduledDay(
        regimen: MedicationRegimen,
        day: Date,
        dayIndex: Int,
        calendar: Calendar
    ) -> Bool {
        switch regimen.scheduleKind {
        case .daily, .fixedCourse, .alternating, .taper:
            return true
        case .specificWeekdays:
            let weekday = calendar.component(.weekday, from: day)
            return regimen.weekdayMask & (1 << (weekday - 1)) != 0
        case .everyNDays:
            return dayIndex % max(regimen.intervalDays, 1) == 0
        case .cycle:
            let cycleLength = max(regimen.cycleOnDays + regimen.cycleOffDays, 1)
            return dayIndex % cycleLength < regimen.cycleOnDays
        case .asNeeded:
            return false
        }
    }

    private static func phaseForDay(
        kind: MedicationScheduleKind,
        dayIndex: Int,
        phases: [MedicationSchedulePhase]
    ) -> MedicationSchedulePhase? {
        guard !phases.isEmpty else { return nil }
        switch kind {
        case .alternating:
            let cycleLength = phases.reduce(0) { $0 + max($1.durationDays ?? 1, 1) }
            var cycleDay = dayIndex % max(cycleLength, 1)
            for phase in phases {
                let length = max(phase.durationDays ?? 1, 1)
                if cycleDay < length { return phase }
                cycleDay -= length
            }
            return phases.last
        case .taper:
            var remainingDay = dayIndex
            for phase in phases {
                guard let duration = phase.durationDays else { return phase }
                if remainingDay < max(duration, 1) { return phase }
                remainingDay -= max(duration, 1)
            }
            return nil
        default:
            return nil
        }
    }

    private static func anchoredDay(
        for date: Date,
        anchorTimeZoneIdentifier: String?,
        calendar: Calendar
    ) -> Date {
        MedicationScheduleDate.displayDate(
            for: date,
            anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
            calendar: calendar
        )
    }

    private static func occurrenceKey(
        regimenID: UUID,
        scheduledAt: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduledAt
        )
        return String(
            format: "%@|%04d-%02d-%02d|%02d:%02d",
            regimenID.uuidString,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}

@MainActor
enum MedicationService {
    @discardableResult
    static func createMedication(
        profileID: UUID,
        name: String,
        form: MedicationForm,
        strength: Double?,
        strengthUnit: String,
        route: MedicationRoute,
        instructions: String,
        reasonForTaking: String,
        prescriber: String,
        pharmacy: String,
        currentSupply: Double?,
        refillThreshold: Double?,
        refillLeadDays: Int = 7,
        prescriptionNumber: String = "",
        fillQuantity: Double? = nil,
        refillsRemaining: Int? = nil,
        prescriptionExpirationDate: Date? = nil,
        context: ModelContext
    ) -> Medication {
        let normalizedCurrentSupply = currentSupply.map { max($0, 0) }
        let medication = Medication(
            profileID: profileID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            form: form,
            strength: strength,
            strengthUnit: strengthUnit.trimmingCharacters(in: .whitespacesAndNewlines),
            route: route,
            instructions: instructions,
            reasonForTaking: reasonForTaking,
            prescriber: prescriber,
            pharmacy: pharmacy,
            currentSupply: normalizedCurrentSupply,
            refillThreshold: refillThreshold.map { max($0, 0) },
            refillLeadDays: max(refillLeadDays, 0),
            prescriptionNumber: prescriptionNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            fillQuantity: fillQuantity.map { max($0, 0) },
            refillsRemaining: refillsRemaining.map { max($0, 0) },
            prescriptionExpirationDate: prescriptionExpirationDate
        )
        context.insert(medication)
        if let normalizedCurrentSupply {
            context.insert(MedicationSupplyLog(
                profileID: profileID,
                medicationID: medication.id,
                adjustment: normalizedCurrentSupply,
                resultingSupply: normalizedCurrentSupply,
                reason: .correction,
                notes: "Initial quantity."
            ))
        }
        return medication
    }

    @discardableResult
    static func createRegimen(
        for medication: Medication,
        scheduleKind: MedicationScheduleKind,
        startDate: Date,
        endDate: Date?,
        doseAmount: Double,
        doseUnit: String,
        doseTimes: [MedicationDoseTime],
        weekdayMask: Int,
        intervalDays: Int,
        cycleOnDays: Int,
        cycleOffDays: Int,
        minimumHoursBetweenDoses: Double?,
        maximumDosesPerDay: Int?,
        remindersEnabled: Bool,
        followUpRemindersEnabled: Bool,
        timeZoneBehavior: MedicationTimeZoneBehavior,
        phases: [(durationDays: Int?, doseAmount: Double)],
        changeContext: MedicationPlanChangeContext? = nil,
        context: ModelContext
    ) -> MedicationRegimen? {
        guard let profileID = medication.profileID else { return nil }
        let now = Date()
        var planContext = changeContext ?? MedicationPlanChangeContext(
            effectiveFrom: startDate,
            source: .caregiver
        )
        planContext.effectiveFrom = normalizedPlanEffectiveDate(planContext.effectiveFrom)
        let scheduleCalendar = MedicationScheduleDate.currentCalendar()
        let anchorTimeZoneIdentifier = scheduleCalendar.timeZone.identifier
        let regimen = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: scheduleKind,
            startDate: MedicationScheduleDate.storedDate(
                for: startDate,
                anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
                calendar: scheduleCalendar
            ),
            endDate: endDate.map {
                MedicationScheduleDate.storedDate(
                    for: $0,
                    anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
                    calendar: scheduleCalendar
                )
            },
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            doseTimes: scheduleKind == .asNeeded ? [] : doseTimes,
            weekdayMask: weekdayMask,
            intervalDays: intervalDays,
            cycleOnDays: cycleOnDays,
            cycleOffDays: cycleOffDays,
            minimumHoursBetweenDoses: minimumHoursBetweenDoses,
            maximumDosesPerDay: maximumDosesPerDay,
            remindersEnabled: remindersEnabled,
            followUpRemindersEnabled: followUpRemindersEnabled,
            timeZoneBehavior: timeZoneBehavior,
            timeZoneIdentifier: anchorTimeZoneIdentifier
        )
        context.insert(regimen)
        var createdPhases = [MedicationSchedulePhase]()
        for (index, phase) in phases.enumerated() {
            let createdPhase = MedicationSchedulePhase(
                profileID: profileID,
                regimenID: regimen.id,
                sequence: index,
                durationDays: phase.durationDays,
                doseAmount: phase.doseAmount,
                doseUnit: doseUnit,
                doseTimes: doseTimes
            )
            context.insert(createdPhase)
            createdPhases.append(createdPhase)
        }
        medication.isConfirmedCurrent = planContext.confirmsCurrent
        if planContext.confirmsCurrent { medication.lastReviewedAt = now }
        medication.updatedAt = now
        let afterSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: regimen,
            phases: createdPhases
        )
        context.insert(MedicationPlanRevision(
            profileID: profileID,
            medicationID: medication.id,
            regimenID: regimen.id,
            changeKind: .added,
            source: planContext.source,
            effectiveFrom: planContext.effectiveFrom,
            changedAt: now,
            appointmentID: planContext.appointmentID,
            reconciliationID: planContext.reconciliationID,
            notes: planContext.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            afterSnapshot: afterSnapshot,
            createdAt: now,
            updatedAt: now
        ))
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return regimen
    }

    @discardableResult
    static func updateMedication(
        medication: Medication,
        regimen: MedicationRegimen,
        name: String,
        form: MedicationForm,
        strength: Double?,
        strengthUnit: String,
        route: MedicationRoute,
        instructions: String,
        reasonForTaking: String,
        prescriber: String,
        pharmacy: String,
        currentSupply: Double?,
        refillThreshold: Double?,
        refillLeadDays: Int = 7,
        prescriptionNumber: String = "",
        fillQuantity: Double? = nil,
        refillsRemaining: Int? = nil,
        prescriptionExpirationDate: Date? = nil,
        scheduleKind: MedicationScheduleKind,
        startDate: Date,
        endDate: Date?,
        doseAmount: Double,
        doseUnit: String,
        doseTimes: [MedicationDoseTime],
        weekdayMask: Int,
        intervalDays: Int,
        cycleOnDays: Int,
        cycleOffDays: Int,
        minimumHoursBetweenDoses: Double?,
        maximumDosesPerDay: Int?,
        remindersEnabled: Bool,
        followUpRemindersEnabled: Bool,
        timeZoneBehavior: MedicationTimeZoneBehavior,
        phases: [(durationDays: Int?, doseAmount: Double)],
        changeContext: MedicationPlanChangeContext? = nil,
        context: ModelContext
    ) -> MedicationRegimen? {
        guard let profileID = medication.profileID,
              regimen.profileID == profileID,
              regimen.medicationID == medication.id else { return nil }
        let now = Date()
        var planContext = changeContext ?? MedicationPlanChangeContext(
            effectiveFrom: startDate,
            source: .caregiver
        )
        planContext.effectiveFrom = normalizedPlanEffectiveDate(planContext.effectiveFrom)
        guard planContext.effectiveFrom >= latestActivationDate(
            regimenID: regimen.id,
            fallback: regimen.startDate,
            context: context
        ) else { return nil }
        let priorPhases = phasesForRegimen(regimen.id, context: context)
        let beforeSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: regimen,
            phases: priorPhases
        )
        medication.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.form = form
        medication.strength = strength
        medication.strengthUnit = strengthUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.route = route
        medication.instructions = instructions
        medication.reasonForTaking = reasonForTaking
        medication.prescriber = prescriber
        medication.pharmacy = pharmacy
        let normalizedCurrentSupply = currentSupply.map { max($0, 0) }
        if medication.currentSupply != normalizedCurrentSupply {
            context.insert(MedicationSupplyLog(
                profileID: profileID,
                medicationID: medication.id,
                adjustment: (normalizedCurrentSupply ?? 0) - (medication.currentSupply ?? 0),
                resultingSupply: normalizedCurrentSupply,
                reason: .correction,
                notes: normalizedCurrentSupply == nil
                    ? "Supply tracking turned off."
                    : "Quantity updated while editing medication."
            ))
        }
        medication.currentSupply = normalizedCurrentSupply
        medication.refillThreshold = refillThreshold.map { max($0, 0) }
        medication.refillLeadDays = max(refillLeadDays, 0)
        medication.prescriptionNumber = prescriptionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.fillQuantity = fillQuantity.map { max($0, 0) }
        medication.refillsRemaining = refillsRemaining.map { max($0, 0) }
        medication.prescriptionExpirationDate = prescriptionExpirationDate
        medication.isConfirmedCurrent = planContext.confirmsCurrent
        if planContext.confirmsCurrent { medication.lastReviewedAt = now }
        medication.updatedAt = now

        let scheduleCalendar = MedicationScheduleDate.currentCalendar()
        let anchorTimeZoneIdentifier = regimen.timeZoneIdentifier ?? scheduleCalendar.timeZone.identifier
        regimen.isActive = false
        regimen.updatedAt = now
        let newRegimen = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: scheduleKind,
            startDate: MedicationScheduleDate.storedDate(
                for: startDate,
                anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
                calendar: scheduleCalendar
            ),
            endDate: endDate.map {
                MedicationScheduleDate.storedDate(
                    for: $0,
                    anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
                    calendar: scheduleCalendar
                )
            },
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            doseTimes: scheduleKind == .asNeeded ? [] : doseTimes,
            weekdayMask: weekdayMask,
            intervalDays: max(intervalDays, 1),
            cycleOnDays: max(cycleOnDays, 1),
            cycleOffDays: max(cycleOffDays, 0),
            minimumHoursBetweenDoses: minimumHoursBetweenDoses,
            maximumDosesPerDay: maximumDosesPerDay,
            remindersEnabled: remindersEnabled,
            followUpRemindersEnabled: remindersEnabled && followUpRemindersEnabled,
            timeZoneBehavior: timeZoneBehavior,
            timeZoneIdentifier: anchorTimeZoneIdentifier,
            createdAt: now,
            updatedAt: now
        )
        context.insert(newRegimen)
        var createdPhases = [MedicationSchedulePhase]()
        for (index, phase) in phases.enumerated() {
            let createdPhase = MedicationSchedulePhase(
                profileID: profileID,
                regimenID: newRegimen.id,
                sequence: index,
                durationDays: phase.durationDays,
                doseAmount: phase.doseAmount,
                doseUnit: doseUnit,
                doseTimes: doseTimes
            )
            context.insert(createdPhase)
            createdPhases.append(createdPhase)
        }
        let afterSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: newRegimen,
            phases: createdPhases
        )
        context.insert(MedicationPlanRevision(
            profileID: profileID,
            medicationID: medication.id,
            priorRegimenID: regimen.id,
            regimenID: newRegimen.id,
            changeKind: .updated,
            source: planContext.source,
            effectiveFrom: planContext.effectiveFrom,
            changedAt: now,
            appointmentID: planContext.appointmentID,
            reconciliationID: planContext.reconciliationID,
            notes: planContext.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            createdAt: now,
            updatedAt: now
        ))
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
            // The notification cleanup can outlive this model context (notably
            // during app teardown and in-memory test stores), so capture only
            // the value rather than retaining the SwiftData model instance.
            let priorRegimenID = regimen.id
            MedicationSnoozeStateStore.clear(regimenID: priorRegimenID)
            Task { await MedicationNotificationScheduler.cancel(regimenID: priorRegimenID) }
            return newRegimen
        }
        return nil
    }

    static func resolveScheduledDose(
        _ reference: MedicationScheduledDoseReference,
        context: ModelContext
    ) -> MedicationScheduledDoseResolution {
        guard !reference.occurrenceKey.isEmpty,
              reference.scheduledAt.timeIntervalSinceReferenceDate.isFinite,
              reference.doseAmount.isFinite,
              reference.doseAmount > 0,
              !reference.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected("This medication reminder is incomplete.")
        }

        let profileID = reference.profileID
        let medicationID = reference.medicationID
        let regimenID = reference.regimenID
        let occurrenceKey = reference.occurrenceKey

        var profileDescriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate { profile in
                profile.id == profileID && !profile.isArchived
            }
        )
        profileDescriptor.fetchLimit = 1
        guard let profile = (try? context.fetch(profileDescriptor))?.first,
              profile.profileType.capabilities.supportsMedications else {
            return .rejected("This reminder's profile is no longer available.")
        }

        var medicationDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { medication in
                medication.id == medicationID
                    && medication.profileID == profileID
                    && !medication.isArchived
            }
        )
        medicationDescriptor.fetchLimit = 1
        guard let medication = (try? context.fetch(medicationDescriptor))?.first else {
            return .rejected("This reminder no longer matches an active medication.")
        }

        var regimenDescriptor = FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { regimen in
                regimen.id == regimenID
                    && regimen.profileID == profileID
                    && regimen.medicationID == medicationID
            }
        )
        regimenDescriptor.fetchLimit = 1
        guard let regimen = (try? context.fetch(regimenDescriptor))?.first,
              regimen.scheduleKind.isScheduled else {
            return .rejected("This reminder no longer matches a medication schedule.")
        }

        let medicationRegimens = (try? context.fetch(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.medicationID == medicationID
            }
        ))) ?? []
        let regimenIDs = Set(medicationRegimens.map(\.id))
        let phases = (try? context.fetch(FetchDescriptor<MedicationSchedulePhase>(
            predicate: #Predicate { regimenIDs.contains($0.regimenID) }
        ))) ?? []
        let revisions = (try? context.fetch(FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.medicationID == medicationID
            }
        ))) ?? []
        let occurrence = MedicationScheduleEngine.versionedOccurrences(
            medicationID: medicationID,
            regimens: medicationRegimens,
            phases: phases,
            revisions: revisions,
            from: reference.scheduledAt.addingTimeInterval(-1),
            through: reference.scheduledAt.addingTimeInterval(1)
        ).first {
            $0.occurrenceKey == reference.occurrenceKey
                && $0.phaseID == reference.phaseID
                && abs($0.scheduledAt.timeIntervalSince(reference.scheduledAt)) < 0.001
                && abs($0.doseAmount - reference.doseAmount) < 0.000_001
                && $0.doseUnit == reference.doseUnit
        }
        guard let occurrence else {
            return .rejected("This medication schedule changed. Open Medications to review it.")
        }

        var recordDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate { record in
                record.profileID == profileID
                    && record.medicationID == medicationID
                    && record.regimenID == regimenID
                    && record.occurrenceKey == occurrenceKey
            }
        )
        recordDescriptor.fetchLimit = 1
        return .valid(
            medication: medication,
            regimen: regimen,
            occurrence: occurrence,
            existingRecord: (try? context.fetch(recordDescriptor))?.first
        )
    }

    static func recordScheduledDose(
        _ reference: MedicationScheduledDoseReference,
        status: MedicationDoseStatus,
        at date: Date = Date(),
        takenAt: Date? = nil,
        actualDoseAmount: Double? = nil,
        timing: MedicationDoseTiming? = nil,
        reason: MedicationDoseReason? = nil,
        notes: String = "",
        context: ModelContext
    ) -> MedicationScheduledDoseMutationResult {
        switch resolveScheduledDose(reference, context: context) {
        case .rejected(let message):
            return .rejected(message)
        case .valid(let medication, let regimen, let occurrence, let existingRecord):
            if let existingRecord {
                if existingRecord.status == status {
                    return .duplicate(medicationName: medication.name)
                }
                return .rejected("This dose was already recorded as \(existingRecord.status.displayName.lowercased()).")
            }
            guard recordDose(
                medication: medication,
                regimen: regimen,
                occurrence: occurrence,
                status: status,
                at: date,
                takenAt: takenAt,
                actualDoseAmount: actualDoseAmount,
                timing: timing,
                reason: reason,
                notes: notes,
                context: context
            ) != nil else {
                return .rejected("This dose could not be saved. Please try again.")
            }
            return .applied(medicationName: medication.name)
        }
    }

    @discardableResult
    static func recordDose(
        medication: Medication,
        regimen: MedicationRegimen,
        occurrence: MedicationOccurrence? = nil,
        status: MedicationDoseStatus,
        at date: Date = Date(),
        takenAt: Date? = nil,
        actualDoseAmount: Double? = nil,
        timing: MedicationDoseTiming? = nil,
        reason: MedicationDoseReason? = nil,
        notes: String = "",
        context: ModelContext
    ) -> MedicationDoseRecord? {
        guard let profileID = medication.profileID,
              regimen.profileID == profileID,
              regimen.medicationID == medication.id,
              occurrence.map({
                  $0.regimenID == regimen.id && $0.medicationID == medication.id
              }) ?? true else { return nil }
        let matchingRecord: MedicationDoseRecord? = occurrence.flatMap { occurrence in
            let medicationID = medication.id
            let regimenID = regimen.id
            let occurrenceKey = occurrence.occurrenceKey
            var descriptor = FetchDescriptor<MedicationDoseRecord>(
                predicate: #Predicate { record in
                    record.profileID == profileID
                        && record.medicationID == medicationID
                        && record.regimenID == regimenID
                        && record.occurrenceKey == occurrenceKey
                }
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first
        }
        if let matchingRecord {
            return matchingRecord.status == status ? matchingRecord : nil
        }
        let record = MedicationDoseRecord(
            profileID: profileID,
            medicationID: medication.id,
            regimenID: regimen.id,
            phaseID: occurrence?.phaseID,
            occurrenceKey: occurrence?.occurrenceKey,
            scheduledAt: occurrence?.scheduledAt,
            status: .skipped,
            takenAt: nil,
            doseAmount: occurrence?.doseAmount ?? regimen.doseAmount,
            doseUnit: occurrence?.doseUnit ?? regimen.doseUnit,
            notes: notes
        )
        context.insert(record)
        guard apply(
            entry: MedicationDoseEntry(
                status: status,
                takenAt: takenAt,
                actualDoseAmount: actualDoseAmount,
                timing: timing,
                reason: reason,
                notes: notes
            ),
            to: record,
            medication: medication,
            at: date,
            context: context
        ) else {
            context.delete(record)
            return nil
        }
        let regimenID = regimen.id
        guard PersistenceService.save(context: context) else { return nil }
        SystemIntegrationReconciler.requestReconciliation()
        if let occurrence {
            MedicationSnoozeStateStore.clear(occurrenceKey: occurrence.occurrenceKey)
            Task {
                await MedicationNotificationScheduler.cancel(
                    regimenID: regimenID,
                    occurrence: occurrence
                )
            }
        }
        return record
    }

    static func updateDoseRecordStatus(
        _ record: MedicationDoseRecord,
        medication: Medication,
        status: MedicationDoseStatus,
        at date: Date = Date(),
        context: ModelContext
    ) {
        guard let profileID = medication.profileID,
              record.profileID == profileID,
              record.medicationID == medication.id else { return }
        _ = apply(
            entry: MedicationDoseEntry(
                status: status,
                takenAt: status == .taken ? date : nil,
                actualDoseAmount: status == .taken ? record.doseAmount : nil,
                timing: nil,
                reason: nil,
                notes: record.notes
            ),
            to: record,
            medication: medication,
            at: date,
            context: context
        )
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
            cancelNotification(for: record)
        }
    }

    @discardableResult
    static func updateDoseRecord(
        _ record: MedicationDoseRecord,
        medication: Medication,
        entry: MedicationDoseEntry,
        at date: Date = Date(),
        context: ModelContext
    ) -> Bool {
        guard let profileID = medication.profileID,
              record.profileID == profileID,
              record.medicationID == medication.id,
              apply(
                  entry: entry,
                  to: record,
                  medication: medication,
                  at: date,
                  context: context
              ) else { return false }
        guard PersistenceService.save(context: context) else { return false }
        SystemIntegrationReconciler.requestReconciliation()
        cancelNotification(for: record)
        return true
    }

    static func deleteDoseRecord(
        _ record: MedicationDoseRecord,
        medication: Medication,
        context: ModelContext
    ) {
        guard let profileID = medication.profileID,
              record.profileID == profileID,
              record.medicationID == medication.id else { return }
        deleteMirror(for: record, context: context)
        refundSupplyIfNeeded(
            for: record,
            medication: medication,
            note: "Dose record deleted.",
            context: context
        )
        context.delete(record)
        medication.updatedAt = Date()
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
        }
    }

    @discardableResult
    static func prepareForCareEventDeletion(
        eventID: UUID,
        context: ModelContext
    ) -> Bool {
        var recordDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate { $0.careEventID == eventID }
        )
        recordDescriptor.fetchLimit = 1
        guard let record = (try? context.fetch(recordDescriptor))?.first else { return false }
        let medicationID = record.medicationID
        var medicationDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == medicationID }
        )
        medicationDescriptor.fetchLimit = 1
        if let medication = (try? context.fetch(medicationDescriptor))?.first {
            refundSupplyIfNeeded(
                for: record,
                medication: medication,
                note: "Medication timeline entry deleted.",
                context: context
            )
            medication.updatedAt = Date()
        }
        context.delete(record)
        return true
    }

    static func updateSupply(
        medication: Medication,
        newSupply: Double,
        reason: MedicationSupplyReason,
        notes: String = "",
        context: ModelContext
    ) {
        guard let profileID = medication.profileID else { return }
        let oldSupply = medication.currentSupply ?? 0
        let resultingSupply = max(newSupply, 0)
        medication.currentSupply = resultingSupply
        medication.updatedAt = Date()
        context.insert(MedicationSupplyLog(
            profileID: profileID,
            medicationID: medication.id,
            adjustment: resultingSupply - oldSupply,
            resultingSupply: resultingSupply,
            reason: reason,
            notes: notes
        ))
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
        }
    }

    static func supplyProjection(
        medication: Medication,
        doseRecords: [MedicationDoseRecord],
        now: Date = Date(),
        lookbackDays: Int = 60,
        calendar: Calendar = .current
    ) -> MedicationSupplyProjection? {
        supplyProjections(
            medications: [medication],
            doseRecords: doseRecords,
            now: now,
            lookbackDays: lookbackDays,
            calendar: calendar
        )[medication.id]
    }

    /// Calculates projections for a screen's medication collection in one pass
    /// through dose history. This avoids rescanning the same 60-day history for
    /// every medication on Home and trip surfaces.
    static func supplyProjections(
        medications: [Medication],
        doseRecords: [MedicationDoseRecord],
        now: Date = Date(),
        lookbackDays: Int = 60,
        calendar: Calendar = .current
    ) -> [UUID: MedicationSupplyProjection] {
        let safeLookbackDays = max(lookbackDays, 1)
        let lookbackStart = calendar.date(
            byAdding: .day,
            value: -safeLookbackDays,
            to: now
        ) ?? now.addingTimeInterval(-Double(safeLookbackDays) * 86_400)
        let supplyByMedicationID = Dictionary(
            medications.compactMap { medication -> (UUID, Double)? in
                guard let currentSupply = medication.currentSupply,
                      currentSupply.isFinite,
                      currentSupply >= 0 else { return nil }
                return (medication.id, currentSupply)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !supplyByMedicationID.isEmpty else { return [:] }

        var usageByMedicationID = [UUID: MedicationSupplyUsage]()
        usageByMedicationID.reserveCapacity(supplyByMedicationID.count)
        for record in doseRecords {
            guard supplyByMedicationID[record.medicationID] != nil,
                  record.status == .taken,
                  let amount = record.effectiveActualDoseAmount,
                  amount.isFinite,
                  amount > 0 else { continue }
            let date = record.takenAt ?? record.scheduledAt ?? record.loggedAt
            guard date >= lookbackStart, date <= now else { continue }
            if var usage = usageByMedicationID[record.medicationID] {
                usage.firstDate = min(usage.firstDate, date)
                usage.consumed += amount
                usage.doseCount += 1
                usageByMedicationID[record.medicationID] = usage
            } else {
                usageByMedicationID[record.medicationID] = MedicationSupplyUsage(
                    firstDate: date,
                    consumed: amount,
                    doseCount: 1
                )
            }
        }

        var projections = [UUID: MedicationSupplyProjection]()
        projections.reserveCapacity(usageByMedicationID.count)
        for (medicationID, usage) in usageByMedicationID {
            guard let currentSupply = supplyByMedicationID[medicationID],
                  let projection = makeSupplyProjection(
                      currentSupply: currentSupply,
                      usage: usage,
                      now: now,
                      calendar: calendar
                  ) else { continue }
            projections[medicationID] = projection
        }
        return projections
    }

    private struct MedicationSupplyUsage {
        var firstDate: Date
        var consumed: Double
        var doseCount: Int
    }

    private static func makeSupplyProjection(
        currentSupply: Double,
        usage: MedicationSupplyUsage,
        now: Date,
        calendar: Calendar
    ) -> MedicationSupplyProjection? {
        let firstDay = calendar.startOfDay(for: usage.firstDate)
        let currentDay = calendar.startOfDay(for: now)
        let observedDayCount = max(
            1,
            (calendar.dateComponents([.day], from: firstDay, to: currentDay).day ?? 0) + 1
        )
        let averageDailyUse = usage.consumed / Double(observedDayCount)
        guard averageDailyUse.isFinite, averageDailyUse > 0 else { return nil }
        let estimatedDaysRemaining = currentSupply / averageDailyUse
        let estimatedRunOutDate = now.addingTimeInterval(estimatedDaysRemaining * 86_400)
        let confidence: MedicationSupplyProjectionConfidence = if usage.doseCount < 3
            || observedDayCount < 3 {
            .limited
        } else if observedDayCount < 7 {
            .developing
        } else {
            .established
        }
        return MedicationSupplyProjection(
            estimatedRunOutDate: estimatedRunOutDate,
            estimatedDaysRemaining: estimatedDaysRemaining,
            averageDailyUse: averageDailyUse,
            observedDoseCount: usage.doseCount,
            observedDayCount: observedDayCount,
            confidence: confidence
        )
    }

    static func tripSupplyRisk(
        projection: MedicationSupplyProjection,
        trip: PackingTrip,
        calendar: Calendar = .current
    ) -> MedicationTripSupplyRisk? {
        let tripStart = calendar.startOfDay(for: trip.startDate)
        let tripEndExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: trip.endDate)
        ) ?? trip.endDate.addingTimeInterval(86_400)
        if projection.estimatedRunOutDate < tripStart {
            return .beforeTrip(runOutDate: projection.estimatedRunOutDate)
        }
        if projection.estimatedRunOutDate < tripEndExclusive {
            return .duringTrip(runOutDate: projection.estimatedRunOutDate)
        }
        return nil
    }

    @discardableResult
    static func createRefillTask(
        medication: Medication,
        householdID: UUID,
        dueDate: Date?,
        fillQuantity: Double?,
        assignedCaregiverIdentifier: String? = nil,
        assignedCaregiverName: String? = nil,
        notes: String = "",
        context: ModelContext,
        now: Date = Date()
    ) -> MedicationRefillTask? {
        guard let profileID = medication.profileID, !medication.isArchived else { return nil }
        var householdDescriptor = FetchDescriptor<Household>(
            predicate: #Predicate { $0.id == householdID }
        )
        householdDescriptor.fetchLimit = 1
        guard (try? context.fetch(householdDescriptor))?.first != nil else { return nil }
        let medicationID = medication.id
        let pickedUpStatus = MedicationRefillStatus.pickedUp.rawValue
        let cancelledStatus = MedicationRefillStatus.cancelled.rawValue
        var openTaskDescriptor = FetchDescriptor<MedicationRefillTask>(
            predicate: #Predicate {
                $0.medicationID == medicationID
                    && $0.statusRawValue != pickedUpStatus
                    && $0.statusRawValue != cancelledStatus
            }
        )
        openTaskDescriptor.fetchLimit = 1
        guard ((try? context.fetch(openTaskDescriptor)) ?? []).isEmpty else { return nil }
        let normalizedFillQuantity = fillQuantity.map { max($0, 0) }
        guard normalizedFillQuantity.map({ $0 > 0 }) ?? true else { return nil }
        let assignedIdentifier = assignedCaregiverIdentifier?.nilIfBlank
        let assignedName = assignedCaregiverName?.nilIfBlank
        guard (assignedIdentifier == nil) == (assignedName == nil) else { return nil }
        let task = MedicationRefillTask(
            householdID: householdID,
            profileID: profileID,
            medicationID: medication.id,
            dueDate: dueDate,
            fillQuantity: normalizedFillQuantity,
            prescriptionNumberSnapshot: medication.prescriptionNumber,
            pharmacySnapshot: medication.pharmacy,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            assignedCaregiverIdentifier: assignedIdentifier,
            assignedCaregiverName: assignedName,
            createdAt: now,
            updatedAt: now
        )
        context.insert(task)
        guard PersistenceService.save(context: context) else { return nil }
        SystemIntegrationReconciler.requestReconciliation()
        return task
    }

    @discardableResult
    static func updateRefillTask(
        _ task: MedicationRefillTask,
        medication: Medication,
        dueDate: Date?,
        fillQuantity: Double?,
        assignedCaregiverIdentifier: String?,
        assignedCaregiverName: String?,
        notes: String,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard task.profileID == medication.profileID,
              task.medicationID == medication.id,
              task.isOpen else { return false }
        let normalizedFillQuantity = fillQuantity.map { max($0, 0) }
        guard normalizedFillQuantity.map({ $0 > 0 }) ?? true else { return false }
        let assignedIdentifier = assignedCaregiverIdentifier?.nilIfBlank
        let assignedName = assignedCaregiverName?.nilIfBlank
        guard (assignedIdentifier == nil) == (assignedName == nil) else { return false }
        task.dueDate = dueDate
        task.fillQuantity = normalizedFillQuantity
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.assignedCaregiverIdentifier = assignedIdentifier
        task.assignedCaregiverName = assignedName
        task.prescriptionNumberSnapshot = medication.prescriptionNumber
        task.pharmacySnapshot = medication.pharmacy
        task.updatedAt = now
        let saved = PersistenceService.save(context: context)
        if saved {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return saved
    }

    @discardableResult
    static func setRefillStatus(
        _ task: MedicationRefillTask,
        medication: Medication,
        status: MedicationRefillStatus,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard task.profileID == medication.profileID,
              task.medicationID == medication.id,
              canTransitionRefill(from: task.status, to: status) else { return false }
        if task.status == status { return true }
        switch status {
        case .needsRequest:
            task.requestedAt = nil
            task.readyForPickupAt = nil
        case .requested:
            task.requestedAt = task.requestedAt ?? now
            task.readyForPickupAt = nil
        case .readyForPickup:
            task.requestedAt = task.requestedAt ?? now
            task.readyForPickupAt = now
        case .pickedUp:
            guard let profileID = medication.profileID else { return false }
            let quantity = task.fillQuantity ?? medication.fillQuantity
            guard let quantity, quantity.isFinite, quantity > 0 else { return false }
            let oldSupply = medication.currentSupply ?? 0
            let newSupply = oldSupply + quantity
            medication.currentSupply = newSupply
            if let refillsRemaining = medication.refillsRemaining, refillsRemaining > 0 {
                medication.refillsRemaining = refillsRemaining - 1
            }
            medication.updatedAt = now
            context.insert(MedicationSupplyLog(
                id: HouseholdAttentionService.deterministicID(
                    "medication-refill-pickup",
                    task.id.uuidString.lowercased()
                ),
                profileID: profileID,
                medicationID: medication.id,
                adjustment: quantity,
                resultingSupply: newSupply,
                reason: .refill,
                notes: "Picked up refill.",
                loggedAt: now
            ))
            task.pickedUpAt = now
            task.completedByCaregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier(
                defaults: defaults
            )
            task.completedByCaregiverName = CaregiverIdentityService.currentCaregiverName(
                defaults: defaults
            )
        case .cancelled:
            task.cancelledAt = now
            task.completedByCaregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier(
                defaults: defaults
            )
            task.completedByCaregiverName = CaregiverIdentityService.currentCaregiverName(
                defaults: defaults
            )
        }
        task.status = status
        task.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        if !status.isOpen {
            HouseholdAttentionSnoozeStore.clear(
                sourceKey: task.attentionSourceKey,
                defaults: defaults
            )
            HouseholdAttentionService.deleteInteractions(
                sourceKey: task.attentionSourceKey,
                context: context
            )
            _ = PersistenceService.save(context: context)
        }
        SystemIntegrationReconciler.requestReconciliation()
        return true
    }

    private static func canTransitionRefill(
        from current: MedicationRefillStatus,
        to next: MedicationRefillStatus
    ) -> Bool {
        if current == next { return true }
        return switch (current, next) {
        case (.needsRequest, .requested),
             (.needsRequest, .cancelled),
             (.requested, .needsRequest),
             (.requested, .readyForPickup),
             (.requested, .cancelled),
             (.readyForPickup, .requested),
             (.readyForPickup, .pickedUp),
             (.readyForPickup, .cancelled): true
        default: false
        }
    }

    @discardableResult
    static func archive(
        medication: Medication,
        regimens: [MedicationRegimen],
        changeContext: MedicationPlanChangeContext? = nil,
        context: ModelContext
    ) -> Bool {
        guard let profileID = medication.profileID else { return false }
        let now = Date()
        var planContext = changeContext ?? MedicationPlanChangeContext(
            effectiveFrom: now,
            source: .caregiver
        )
        planContext.effectiveFrom = normalizedPlanEffectiveDate(planContext.effectiveFrom)
        let currentRegimen = regimens.first {
            $0.profileID == profileID && $0.medicationID == medication.id && $0.isActive
        }
        if let currentRegimen {
            guard planContext.effectiveFrom >= latestActivationDate(
                regimenID: currentRegimen.id,
                fallback: currentRegimen.startDate,
                context: context
            ) else { return false }
        }
        let currentPhases = currentRegimen.map {
            phasesForRegimen($0.id, context: context)
        } ?? []
        let beforeSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: currentRegimen,
            phases: currentPhases
        )
        medication.isArchived = true
        medication.isConfirmedCurrent = false
        medication.updatedAt = now
        let medicationRegimens = regimens.filter {
            $0.profileID == profileID && $0.medicationID == medication.id
        }
        medicationRegimens.forEach { $0.isActive = false; $0.updatedAt = now }
        let regimenIDs = medicationRegimens.map(\.id)
        let medicationID = medication.id
        let openRefillTasks = ((try? context.fetch(FetchDescriptor<MedicationRefillTask>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ))) ?? []).filter(\.isOpen)
        openRefillTasks.forEach { task in
            task.status = .cancelled
            task.cancelledAt = now
            task.completedByCaregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier()
            task.completedByCaregiverName = CaregiverIdentityService.currentCaregiverName()
            task.updatedAt = now
            HouseholdAttentionService.deleteInteractions(
                sourceKey: task.attentionSourceKey,
                context: context
            )
            HouseholdAttentionSnoozeStore.clear(sourceKey: task.attentionSourceKey)
        }
        let afterSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: currentRegimen,
            phases: currentPhases
        )
        context.insert(MedicationPlanRevision(
            profileID: profileID,
            medicationID: medication.id,
            priorRegimenID: currentRegimen?.id,
            regimenID: currentRegimen?.id,
            changeKind: .stopped,
            source: planContext.source,
            effectiveFrom: planContext.effectiveFrom,
            changedAt: now,
            appointmentID: planContext.appointmentID,
            reconciliationID: planContext.reconciliationID,
            notes: planContext.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            createdAt: now,
            updatedAt: now
        ))
        let saved = PersistenceService.save(context: context)
        if saved {
            SystemIntegrationReconciler.requestReconciliation()
            Task {
                for regimenID in regimenIDs {
                    await MedicationNotificationScheduler.cancel(regimenID: regimenID)
                }
            }
        }
        return saved
    }

    @discardableResult
    static func restore(
        medication: Medication,
        regimens: [MedicationRegimen],
        changeContext: MedicationPlanChangeContext? = nil,
        context: ModelContext
    ) -> Bool {
        guard let profileID = medication.profileID else { return false }
        let now = Date()
        var planContext = changeContext ?? MedicationPlanChangeContext(
            effectiveFrom: now,
            source: .caregiver
        )
        planContext.effectiveFrom = normalizedPlanEffectiveDate(planContext.effectiveFrom)
        let latestRegimen = regimens
            .filter({
                $0.profileID == profileID && $0.medicationID == medication.id
            })
            .max(by: { $0.updatedAt < $1.updatedAt })
        let latestPhases = latestRegimen.map {
            phasesForRegimen($0.id, context: context)
        } ?? []
        let beforeSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: latestRegimen,
            phases: latestPhases
        )
        medication.isArchived = false
        medication.isConfirmedCurrent = planContext.confirmsCurrent
        if planContext.confirmsCurrent { medication.lastReviewedAt = now }
        medication.updatedAt = now
        if let latestRegimen {
            latestRegimen.isActive = true
            latestRegimen.updatedAt = now
        }
        let afterSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: latestRegimen,
            phases: latestPhases
        )
        context.insert(MedicationPlanRevision(
            profileID: profileID,
            medicationID: medication.id,
            regimenID: latestRegimen?.id,
            changeKind: .restored,
            source: planContext.source,
            effectiveFrom: planContext.effectiveFrom,
            changedAt: now,
            appointmentID: planContext.appointmentID,
            reconciliationID: planContext.reconciliationID,
            notes: planContext.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            createdAt: now,
            updatedAt: now
        ))
        let saved = PersistenceService.save(context: context)
        if saved {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return saved
    }

    @discardableResult
    static func confirmCurrent(
        medication: Medication,
        regimens: [MedicationRegimen],
        changeContext: MedicationPlanChangeContext,
        context: ModelContext
    ) -> Bool {
        guard let profileID = medication.profileID, !medication.isArchived else { return false }
        let now = Date()
        var changeContext = changeContext
        changeContext.effectiveFrom = normalizedPlanEffectiveDate(changeContext.effectiveFrom)
        let activeRegimen = regimens.first {
            $0.profileID == profileID && $0.medicationID == medication.id && $0.isActive
        }
        let phases = activeRegimen.map {
            phasesForRegimen($0.id, context: context)
        } ?? []
        let snapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: activeRegimen,
            phases: phases
        )
        medication.isConfirmedCurrent = true
        medication.lastReviewedAt = now
        medication.updatedAt = now
        let confirmedSnapshot = MedicationPlanSnapshot(
            medication: medication,
            regimen: activeRegimen,
            phases: phases
        )
        context.insert(MedicationPlanRevision(
            profileID: profileID,
            medicationID: medication.id,
            priorRegimenID: activeRegimen?.id,
            regimenID: activeRegimen?.id,
            changeKind: .confirmedCurrent,
            source: changeContext.source,
            effectiveFrom: changeContext.effectiveFrom,
            changedAt: now,
            appointmentID: changeContext.appointmentID,
            reconciliationID: changeContext.reconciliationID,
            notes: changeContext.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            beforeSnapshot: snapshot,
            afterSnapshot: confirmedSnapshot,
            createdAt: now,
            updatedAt: now
        ))
        let saved = PersistenceService.save(context: context)
        if saved {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return saved
    }

    @discardableResult
    static func completeReconciliation(
        id: UUID = UUID(),
        profileID: UUID,
        source: MedicationPlanChangeSource,
        effectiveFrom: Date,
        appointmentID: UUID? = nil,
        notes: String = "",
        reviewedMedicationIDs: [UUID],
        context: ModelContext
    ) -> MedicationReconciliation? {
        let effectiveFrom = normalizedPlanEffectiveDate(effectiveFrom)
        let uniqueReviewedIDs = Set(reviewedMedicationIDs)
        guard uniqueReviewedIDs.count == reviewedMedicationIDs.count else { return nil }
        let medications = (try? context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        let profileMedicationIDs = Set(medications.map(\.id))
        let activeMedicationIDs = Set(medications.filter { !$0.isArchived }.map(\.id))
        guard uniqueReviewedIDs.isSubset(of: profileMedicationIDs),
              activeMedicationIDs.isSubset(of: uniqueReviewedIDs) else { return nil }
        let linkedRevisions = (try? context.fetch(FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate { $0.reconciliationID == id }
        ))) ?? []
        let revisedMedicationIDs = Set(linkedRevisions.compactMap { revision in
            revision.profileID == profileID ? revision.medicationID : nil
        })
        guard uniqueReviewedIDs.isSubset(of: revisedMedicationIDs),
              linkedRevisions.allSatisfy({ revision in
                  revision.profileID == profileID
                      && revision.source == source
                      && revision.effectiveFrom == effectiveFrom
                      && revision.appointmentID == appointmentID
              }) else { return nil }
        var existingDescriptor = FetchDescriptor<MedicationReconciliation>(
            predicate: #Predicate { $0.id == id }
        )
        existingDescriptor.fetchLimit = 1
        guard ((try? context.fetch(existingDescriptor)) ?? []).isEmpty else { return nil }
        let now = Date()
        let reconciliation = MedicationReconciliation(
            id: id,
            profileID: profileID,
            appointmentID: appointmentID,
            source: source,
            effectiveFrom: effectiveFrom,
            completedAt: now,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            reviewedMedicationIDs: reviewedMedicationIDs,
            createdAt: now,
            updatedAt: now
        )
        context.insert(reconciliation)
        guard PersistenceService.save(context: context) else { return nil }
        SystemIntegrationReconciler.requestReconciliation()
        return reconciliation
    }

    @discardableResult
    static func abandonReconciliation(
        id: UUID,
        context: ModelContext
    ) -> Bool {
        var reconciliationDescriptor = FetchDescriptor<MedicationReconciliation>(
            predicate: #Predicate { $0.id == id }
        )
        reconciliationDescriptor.fetchLimit = 1
        if ((try? context.fetch(reconciliationDescriptor)) ?? []).first != nil {
            return true
        }
        let revisions = (try? context.fetch(FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate { $0.reconciliationID == id }
        ))) ?? []
        guard !revisions.isEmpty else { return true }
        let now = Date()
        revisions.forEach {
            $0.reconciliationID = nil
            $0.updatedAt = now
        }
        let saved = PersistenceService.save(context: context)
        if saved {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return saved
    }

    static func phasesForRegimen(
        _ regimenID: UUID,
        context: ModelContext
    ) -> [MedicationSchedulePhase] {
        let descriptor = FetchDescriptor<MedicationSchedulePhase>(
            predicate: #Predicate { $0.regimenID == regimenID },
            sortBy: [SortDescriptor(\MedicationSchedulePhase.sequence)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func doseRecordsForRegimen(
        _ regimenID: UUID,
        context: ModelContext
    ) -> [MedicationDoseRecord] {
        let descriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate { $0.regimenID == regimenID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    private static func apply(
        entry: MedicationDoseEntry,
        to record: MedicationDoseRecord,
        medication: Medication,
        at date: Date,
        context: ModelContext
    ) -> Bool {
        guard let profileID = medication.profileID,
              record.profileID == profileID,
              record.medicationID == medication.id else { return false }

        if entry.status == .missed, entry.reason == nil { return false }
        if entry.status == .taken,
           let takenAt = entry.takenAt,
           takenAt > date { return false }

        let normalizedActualAmount: Double?
        if entry.status == .taken {
            let value = entry.actualDoseAmount ?? record.doseAmount
            guard value.isFinite, value > 0 else { return false }
            normalizedActualAmount = value
        } else {
            normalizedActualAmount = nil
        }

        let normalizedReason: MedicationDoseReason? = switch entry.status {
        case .taken, .skipped: nil
        case .held: entry.reason ?? .perClinicianInstruction
        case .refused: .refused
        case .unable: .unableToTake
        case .missed: entry.reason
        }

        record.status = entry.status
        record.loggedAt = date
        record.takenAt = entry.status == .taken ? (entry.takenAt ?? date) : nil
        record.actualDoseAmount = normalizedActualAmount
        record.timing = entry.status == .taken
            ? (entry.timing ?? inferredTiming(actualTime: record.takenAt ?? date, scheduledAt: record.scheduledAt))
            : nil
        record.reason = normalizedReason
        record.notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = date

        reconcileSupply(
            for: record,
            medication: medication,
            actualDoseAmount: normalizedActualAmount,
            context: context
        )

        if entry.status == .taken {
            let actualTime = record.takenAt ?? date
            let actualAmount = normalizedActualAmount ?? record.doseAmount
            if record.careEventID == nil {
                let event = CareEvent(
                    profileID: profileID,
                    type: .medicine,
                    startDate: actualTime,
                    endDate: actualTime,
                    startTimeZoneIdentifier: CareTimeZoneSettings.effectiveIdentifier(),
                    endTimeZoneIdentifier: CareTimeZoneSettings.effectiveIdentifier(),
                    caregiverName: record.caregiverName,
                    notes: record.notes.nilIfEmpty
                )
                var profileDescriptor = FetchDescriptor<CareProfile>(
                    predicate: #Predicate { $0.id == profileID }
                )
                profileDescriptor.fetchLimit = 1
                event.profileTypeSnapshot = (try? context.fetch(profileDescriptor))?.first?.profileType
                event.medicineName = medication.name
                event.dose = actualAmount
                event.doseUnit = record.doseUnit
                context.insert(event)
                record.careEventID = event.id
            } else if let eventID = record.careEventID {
                var descriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
                descriptor.fetchLimit = 1
                if let event = (try? context.fetch(descriptor))?.first {
                    event.startDate = actualTime
                    event.endDate = actualTime
                    event.medicineName = medication.name
                    event.dose = actualAmount
                    event.doseUnit = record.doseUnit
                    event.notes = record.notes.nilIfEmpty
                    event.updatedAt = date
                }
            }
        } else {
            deleteMirror(for: record, context: context)
        }
        medication.updatedAt = date
        return true
    }

    private static func normalizedPlanEffectiveDate(_ date: Date) -> Date {
        MedicationScheduleDate.currentCalendar().startOfDay(for: date)
    }

    private static func latestActivationDate(
        regimenID: UUID,
        fallback: Date,
        context: ModelContext
    ) -> Date {
        let revisions = (try? context.fetch(FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate { $0.regimenID == regimenID }
        ))) ?? []
        return revisions.compactMap { revision -> Date? in
            switch revision.changeKind {
            case .added, .updated, .restored: revision.effectiveFrom
            case .stopped, .confirmedCurrent: nil
            }
        }.max() ?? normalizedPlanEffectiveDate(fallback)
    }

    private static func inferredTiming(
        actualTime: Date,
        scheduledAt: Date?
    ) -> MedicationDoseTiming? {
        guard let scheduledAt else { return nil }
        return actualTime.timeIntervalSince(scheduledAt) >= 30 * 60 ? .late : .onSchedule
    }

    private static func reconcileSupply(
        for record: MedicationDoseRecord,
        medication: Medication,
        actualDoseAmount: Double?,
        context: ModelContext
    ) {
        guard let profileID = medication.profileID else { return }
        guard let currentSupply = medication.currentSupply else {
            record.supplyAdjustmentApplied = 0
            return
        }
        let previouslyDeducted = max(-record.supplyAdjustmentApplied, 0)
        let availableBeforeThisDose = max(currentSupply + previouslyDeducted, 0)
        let newlyDeducted = actualDoseAmount.map {
            min(availableBeforeThisDose, max($0, 0))
        } ?? 0
        let adjustment = previouslyDeducted - newlyDeducted
        record.supplyAdjustmentApplied = -newlyDeducted
        medication.currentSupply = max(currentSupply + adjustment, 0)
        guard abs(adjustment) > 0.000_001 else { return }
        context.insert(MedicationSupplyLog(
            profileID: profileID,
            medicationID: medication.id,
            doseRecordID: record.id,
            adjustment: adjustment,
            resultingSupply: medication.currentSupply,
            reason: .dose,
            notes: previouslyDeducted > 0
                ? "Dose outcome or actual amount updated."
                : "Dose recorded."
        ))
    }

    private static func deleteMirror(
        for record: MedicationDoseRecord,
        context: ModelContext
    ) {
        guard let eventID = record.careEventID else { return }
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.id == eventID }
        )
        descriptor.fetchLimit = 1
        if let event = (try? context.fetch(descriptor))?.first {
            context.delete(event)
        }
        record.careEventID = nil
    }

    private static func refundSupplyIfNeeded(
        for record: MedicationDoseRecord,
        medication: Medication,
        note: String,
        context: ModelContext
    ) {
        let refund = -record.supplyAdjustmentApplied
        guard refund > 0,
              let profileID = medication.profileID,
              let currentSupply = medication.currentSupply else {
            record.supplyAdjustmentApplied = 0
            return
        }
        medication.currentSupply = currentSupply + refund
        record.supplyAdjustmentApplied = 0
        context.insert(MedicationSupplyLog(
            profileID: profileID,
            medicationID: medication.id,
            doseRecordID: record.id,
            adjustment: refund,
            resultingSupply: medication.currentSupply,
            reason: .correction,
            notes: note
        ))
    }

    private static func cancelNotification(for record: MedicationDoseRecord) {
        guard let regimenID = record.regimenID,
              let scheduledAt = record.scheduledAt else { return }
        Task {
            await MedicationNotificationScheduler.cancel(
                regimenID: regimenID,
                scheduledAt: scheduledAt
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MedicationNotificationScheduler {
    static let categoryIdentifier = "MEDICATION_REMINDER"
    static let takenActionIdentifier = "LOG_MEDICATION_TAKEN"
    static let skippedActionIdentifier = "LOG_MEDICATION_SKIPPED"
    static let snoozeActionIdentifier = "SNOOZE_MEDICATION_10_MIN"
    static let openActionIdentifier = "OPEN_MEDICATIONS"
    private static let identifierPrefix = "medication."
    static let systemPendingRequestLimit = 64
    static let totalRollingRequestLimit = 48

    static func availableMedicationRequestCount(
        nonMedicationPendingRequestCount: Int
    ) -> Int {
        min(
            totalRollingRequestLimit,
            max(systemPendingRequestLimit - max(nonMedicationPendingRequestCount, 0), 0)
        )
    }

    static func reschedule(
        medication: Medication,
        regimen: MedicationRegimen,
        phases: [MedicationSchedulePhase],
        records: [MedicationDoseRecord],
        maximumRequestCount: Int = 24,
        now: Date = Date()
    ) async -> Int {
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let snoozeSearchStart = Calendar.current.date(byAdding: .hour, value: -12, to: now)
            ?? now.addingTimeInterval(-12 * 60 * 60)
        let unloggedOccurrences = MedicationScheduleEngine.unloggedOccurrences(
            MedicationScheduleEngine.occurrences(
                regimen: regimen,
                phases: phases,
                from: snoozeSearchStart,
                through: end
            ),
            records: records
        )
        let activeSnoozedOccurrenceKeys = Set(unloggedOccurrences.compactMap { occurrence in
            MedicationSnoozeStateStore.isSnoozed(
                occurrenceKey: occurrence.occurrenceKey,
                now: now
            ) ? occurrence.occurrenceKey : nil
        })
        await cancel(
            regimenID: regimen.id,
            preservingSnoozedOccurrenceKeys: activeSnoozedOccurrenceKeys
        )
        guard regimen.remindersEnabled,
              maximumRequestCount > 0,
              await NotificationManager.shared.ensureAuthorization() else { return 0 }
        let occurrences = unloggedOccurrences.filter {
            $0.scheduledAt >= now
                && !activeSnoozedOccurrenceKeys.contains($0.occurrenceKey)
        }
        var scheduledRequestCount = 0
        for occurrence in occurrences {
            guard scheduledRequestCount < maximumRequestCount else { break }
            let content = UNMutableNotificationContent()
            content.title = "Time for \(medication.name)"
            content.body = "\(occurrence.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(occurrence.doseUnit)"
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = [
                "profileID": medication.profileID?.uuidString ?? "",
                "medicationID": medication.id.uuidString,
                "regimenID": regimen.id.uuidString,
                "phaseID": occurrence.phaseID?.uuidString ?? "",
                "occurrenceKey": occurrence.occurrenceKey,
                "scheduledAt": occurrence.scheduledAt.timeIntervalSince1970,
                "doseAmount": occurrence.doseAmount,
                "doseUnit": occurrence.doseUnit,
                "deepLink": "littlewindows://profile/\(medication.profileID?.uuidString ?? "")/medications"
            ]
            let fireDate = occurrence.scheduledAt.addingTimeInterval(
                TimeInterval(-regimen.reminderLeadMinutes * 60)
            )
            guard fireDate > now else { continue }
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(regimenID: regimen.id, occurrence: occurrence),
                content: content,
                trigger: oneShotTrigger(
                    at: fireDate,
                    timeZone: notificationTimeZone(for: regimen)
                )
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                scheduledRequestCount += 1
            } catch {
                continue
            }
            if regimen.followUpRemindersEnabled,
               scheduledRequestCount < maximumRequestCount {
                let followUpDate = occurrence.scheduledAt.addingTimeInterval(30 * 60)
                guard followUpDate > now,
                      let followUpContent = content.mutableCopy() as? UNMutableNotificationContent else {
                    continue
                }
                followUpContent.title = "Medication not logged"
                followUpContent.body = "Review the \(medication.name) dose scheduled 30 minutes ago."
                let followUpRequest = UNNotificationRequest(
                    identifier: notificationIdentifier(
                        regimenID: regimen.id,
                        scheduledAt: occurrence.scheduledAt
                    ) + ".followup",
                    content: followUpContent,
                    trigger: oneShotTrigger(
                        at: followUpDate,
                        timeZone: notificationTimeZone(for: regimen)
                    )
                )
                do {
                    try await UNUserNotificationCenter.current().add(followUpRequest)
                    scheduledRequestCount += 1
                } catch {
                    continue
                }
            }
        }
        return scheduledRequestCount
    }

    static func cancel(
        regimenID: UUID,
        preservingSnoozedOccurrenceKeys: Set<String> = []
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefix = "\(identifierPrefix)\(regimenID.uuidString)."
        center.removePendingNotificationRequests(
            withIdentifiers: pending.compactMap { request in
                guard request.identifier.hasPrefix(prefix) else { return nil }
                if request.identifier.contains(".snooze"),
                   let occurrenceKey = request.content.userInfo["occurrenceKey"] as? String,
                   preservingSnoozedOccurrenceKeys.contains(occurrenceKey) {
                    return nil
                }
                return request.identifier
            }
        )
        MedicationSnoozeStateStore.retain(
            occurrenceKeys: preservingSnoozedOccurrenceKeys,
            for: regimenID
        )
    }

    static func cancel(regimenID: UUID, occurrence: MedicationOccurrence) async {
        await cancel(regimenID: regimenID, scheduledAt: occurrence.scheduledAt)
    }

    static func cancel(regimenID: UUID, scheduledAt: Date) async {
        let center = UNUserNotificationCenter.current()
        let baseIdentifier = notificationIdentifier(
            regimenID: regimenID,
            scheduledAt: scheduledAt
        )
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.compactMap { request in
            request.identifier == baseIdentifier || request.identifier.hasPrefix("\(baseIdentifier).")
                ? request.identifier
                : nil
        })
    }

    @discardableResult
    static func snooze(_ response: UNNotificationResponse) async -> Bool {
        guard let content = response.notification.request.content.mutableCopy()
                as? UNMutableNotificationContent,
              let command = doseCommand(from: content.userInfo, status: .taken) else { return false }
        let fireDate = Date().addingTimeInterval(10 * 60)
        let request = UNNotificationRequest(
            identifier: response.notification.request.identifier + ".snooze",
            content: content,
            trigger: oneShotTrigger(at: fireDate)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            MedicationSnoozeStateStore.markSnoozed(
                occurrenceKey: command.occurrenceKey,
                until: fireDate
            )
            return true
        } catch {
            return false
        }
    }

    static func scheduleWatchSnooze(
        medication: WatchMedicationSnapshot,
        fireDate: Date
    ) async -> Bool {
        guard fireDate > Date().addingTimeInterval(1) else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
        do {
            try await center.add(watchSnoozeRequest(
                medication: medication,
                fireDate: fireDate
            ))
            MedicationSnoozeStateStore.markSnoozed(
                occurrenceKey: medication.occurrenceKey,
                until: fireDate
            )
            return true
        } catch {
            return false
        }
    }

    static func watchSnoozeRequest(
        medication: WatchMedicationSnapshot,
        fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(medication.medicationName)"
        content.body = "\(medication.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(medication.doseUnit)"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "profileID": medication.profileID.uuidString,
            "medicationID": medication.medicationID.uuidString,
            "regimenID": medication.regimenID.uuidString,
            "phaseID": medication.phaseID?.uuidString ?? "",
            "occurrenceKey": medication.occurrenceKey,
            "scheduledAt": medication.scheduledAt.timeIntervalSince1970,
            "doseAmount": medication.doseAmount,
            "doseUnit": medication.doseUnit,
            "deepLink": "littlewindows://profile/\(medication.profileID.uuidString)/medications"
        ]
        return UNNotificationRequest(
            identifier: notificationIdentifier(
                regimenID: medication.regimenID,
                scheduledAt: medication.scheduledAt
            ) + ".snooze",
            content: content,
            trigger: oneShotTrigger(at: fireDate)
        )
    }

    static func doseCommand(
        from userInfo: [AnyHashable: Any],
        status: MedicationDoseStatus
    ) -> MedicationDoseRouteCommand? {
        guard let profileID = (userInfo["profileID"] as? String).flatMap(UUID.init(uuidString:)),
              let medicationID = (userInfo["medicationID"] as? String).flatMap(UUID.init(uuidString:)),
              let regimenID = (userInfo["regimenID"] as? String).flatMap(UUID.init(uuidString:)),
              let occurrenceKey = userInfo["occurrenceKey"] as? String,
              !occurrenceKey.isEmpty,
              let scheduledTimestamp = userInfo["scheduledAt"] as? Double,
              let doseAmount = userInfo["doseAmount"] as? Double,
              doseAmount > 0,
              let doseUnit = userInfo["doseUnit"] as? String,
              !doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let phaseID = (userInfo["phaseID"] as? String).flatMap(UUID.init(uuidString:))
        return MedicationDoseRouteCommand(
            profileID: profileID,
            medicationID: medicationID,
            regimenID: regimenID,
            phaseID: phaseID,
            occurrenceKey: occurrenceKey,
            scheduledAt: Date(timeIntervalSince1970: scheduledTimestamp),
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            status: status
        )
    }

    private static func notificationIdentifier(
        regimenID: UUID,
        occurrence: MedicationOccurrence
    ) -> String {
        notificationIdentifier(regimenID: regimenID, scheduledAt: occurrence.scheduledAt)
    }

    private static func notificationIdentifier(
        regimenID: UUID,
        scheduledAt: Date
    ) -> String {
        "\(identifierPrefix)\(regimenID.uuidString).\(Int(scheduledAt.timeIntervalSince1970))"
    }

    private static func oneShotTrigger(
        at date: Date,
        timeZone: TimeZone? = nil
    ) -> UNCalendarNotificationTrigger {
        var calendar = Calendar.current
        if let timeZone {
            calendar.timeZone = timeZone
        }
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.timeZone = timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private static func notificationTimeZone(for regimen: MedicationRegimen) -> TimeZone? {
        if regimen.timeZoneBehavior == .fixedTimeZone {
            return regimen.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        }
        // A nil time zone follows the device as it travels. An explicit app-level
        // override remains fixed until the user changes that setting.
        return CareTimeZoneSettings.manualOverrideTimeZone()
    }
}
