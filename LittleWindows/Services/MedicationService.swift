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

    var completionRate: Double? {
        guard scheduledCount > 0 else { return nil }
        return Double(takenCount) / Double(scheduledCount)
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
        calendar sourceCalendar: Calendar = MedicationScheduleDate.currentCalendar()
    ) -> [MedicationOccurrence] {
        guard regimen.isActive,
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
        let taken = expected.filter { recordsByKey[$0.occurrenceKey]?.status == .taken }.count
        let skipped = expected.filter { recordsByKey[$0.occurrenceKey]?.status == .skipped }.count
        return MedicationAdherenceSummary(
            scheduledCount: expected.count,
            takenCount: taken,
            skippedCount: skipped,
            missedCount: max(expected.count - taken - skipped, 0)
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
        let taken = records
            .filter {
                $0.regimenID == regimen.id
                    && $0.status == .taken
                    && ($0.takenAt ?? $0.loggedAt) <= date
            }
            .sorted { ($0.takenAt ?? $0.loggedAt) > ($1.takenAt ?? $1.loggedAt) }
        if let maximum = regimen.maximumDosesPerDay {
            let todayCount = taken.filter {
                calendar.isDate($0.takenAt ?? $0.loggedAt, inSameDayAs: date)
            }.count
            if todayCount >= maximum {
                return .dailyLimitReached(maximum)
            }
        }
        if let minimumHours = regimen.minimumHoursBetweenDoses,
           let last = taken.first.map({ $0.takenAt ?? $0.loggedAt }) {
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
            refillThreshold: refillThreshold.map { max($0, 0) }
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
        context: ModelContext
    ) -> MedicationRegimen? {
        guard let profileID = medication.profileID else { return nil }
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
        for (index, phase) in phases.enumerated() {
            context.insert(MedicationSchedulePhase(
                profileID: profileID,
                regimenID: regimen.id,
                sequence: index,
                durationDays: phase.durationDays,
                doseAmount: phase.doseAmount,
                doseUnit: doseUnit,
                doseTimes: doseTimes
            ))
        }
        medication.updatedAt = Date()
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return regimen
    }

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
        context: ModelContext
    ) {
        guard let profileID = medication.profileID,
              regimen.profileID == profileID,
              regimen.medicationID == medication.id else { return }
        let now = Date()
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
        medication.updatedAt = now

        let scheduleCalendar = MedicationScheduleDate.currentCalendar()
        let anchorTimeZoneIdentifier = regimen.timeZoneIdentifier ?? scheduleCalendar.timeZone.identifier
        regimen.scheduleKind = scheduleKind
        regimen.startDate = MedicationScheduleDate.storedDate(
            for: startDate,
            anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
            calendar: scheduleCalendar
        )
        regimen.endDate = endDate.map {
            MedicationScheduleDate.storedDate(
                for: $0,
                anchorTimeZoneIdentifier: anchorTimeZoneIdentifier,
                calendar: scheduleCalendar
            )
        }
        regimen.doseAmount = doseAmount
        regimen.doseUnit = doseUnit
        regimen.doseTimes = scheduleKind == .asNeeded ? [] : doseTimes
        regimen.weekdayMask = weekdayMask
        regimen.intervalDays = max(intervalDays, 1)
        regimen.cycleOnDays = max(cycleOnDays, 1)
        regimen.cycleOffDays = max(cycleOffDays, 0)
        regimen.minimumHoursBetweenDoses = minimumHoursBetweenDoses
        regimen.maximumDosesPerDay = maximumDosesPerDay
        regimen.remindersEnabled = remindersEnabled
        regimen.followUpRemindersEnabled = remindersEnabled && followUpRemindersEnabled
        regimen.timeZoneBehavior = timeZoneBehavior
        regimen.timeZoneIdentifier = anchorTimeZoneIdentifier
        regimen.updatedAt = now

        for phase in phasesForRegimen(regimen.id, context: context) {
            context.delete(phase)
        }
        for (index, phase) in phases.enumerated() {
            context.insert(MedicationSchedulePhase(
                profileID: profileID,
                regimenID: regimen.id,
                sequence: index,
                durationDays: phase.durationDays,
                doseAmount: phase.doseAmount,
                doseUnit: doseUnit,
                doseTimes: doseTimes
            ))
        }
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
        }
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
                    && regimen.isActive
            }
        )
        regimenDescriptor.fetchLimit = 1
        guard let regimen = (try? context.fetch(regimenDescriptor))?.first,
              regimen.scheduleKind.isScheduled else {
            return .rejected("This reminder no longer matches an active medication schedule.")
        }

        let phases = phasesForRegimen(regimen.id, context: context)
        let occurrence = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: phases,
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
        let record = matchingRecord ?? MedicationDoseRecord(
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
        if matchingRecord == nil { context.insert(record) }
        apply(
            status: status,
            to: record,
            medication: medication,
            at: date,
            notes: notes,
            context: context
        )
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
        apply(
            status: status,
            to: record,
            medication: medication,
            at: date,
            notes: record.notes,
            context: context
        )
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
            cancelNotification(for: record)
        }
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

    static func archive(
        medication: Medication,
        regimens: [MedicationRegimen],
        context: ModelContext
    ) {
        guard let profileID = medication.profileID else { return }
        medication.isArchived = true
        medication.updatedAt = Date()
        let medicationRegimens = regimens.filter {
            $0.profileID == profileID && $0.medicationID == medication.id
        }
        medicationRegimens.forEach { $0.isActive = false; $0.updatedAt = Date() }
        let regimenIDs = medicationRegimens.map(\.id)
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
            Task {
                for regimenID in regimenIDs {
                    await MedicationNotificationScheduler.cancel(regimenID: regimenID)
                }
            }
        }
    }

    static func restore(
        medication: Medication,
        regimens: [MedicationRegimen],
        context: ModelContext
    ) {
        guard let profileID = medication.profileID else { return }
        medication.isArchived = false
        medication.updatedAt = Date()
        if let latestRegimen = regimens
            .filter({
                $0.profileID == profileID && $0.medicationID == medication.id
            })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            latestRegimen.isActive = true
            latestRegimen.updatedAt = Date()
        }
        if PersistenceService.save(context: context) {
            SystemIntegrationReconciler.requestReconciliation()
        }
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

    private static func apply(
        status: MedicationDoseStatus,
        to record: MedicationDoseRecord,
        medication: Medication,
        at date: Date,
        notes: String,
        context: ModelContext
    ) {
        guard let profileID = medication.profileID,
              record.profileID == profileID,
              record.medicationID == medication.id else { return }
        let wasTaken = record.status == .taken
        record.status = status
        record.loggedAt = date
        record.takenAt = status == .taken ? date : nil
        record.notes = notes
        record.updatedAt = date

        if status == .taken {
            if record.careEventID == nil {
                let event = CareEvent(
                    profileID: profileID,
                    type: .medicine,
                    startDate: date,
                    endDate: date,
                    startTimeZoneIdentifier: CareTimeZoneSettings.effectiveIdentifier(),
                    endTimeZoneIdentifier: CareTimeZoneSettings.effectiveIdentifier(),
                    caregiverName: record.caregiverName,
                    notes: notes.nilIfEmpty
                )
                var profileDescriptor = FetchDescriptor<CareProfile>(
                    predicate: #Predicate { $0.id == profileID }
                )
                profileDescriptor.fetchLimit = 1
                event.profileTypeSnapshot = (try? context.fetch(profileDescriptor))?.first?.profileType
                event.medicineName = medication.name
                event.dose = record.doseAmount
                event.doseUnit = record.doseUnit
                context.insert(event)
                record.careEventID = event.id
            }
            if !wasTaken, let currentSupply = medication.currentSupply {
                let deducted = min(max(currentSupply, 0), record.doseAmount)
                record.supplyAdjustmentApplied = -deducted
                medication.currentSupply = max(currentSupply - deducted, 0)
                context.insert(MedicationSupplyLog(
                    profileID: profileID,
                    medicationID: medication.id,
                    doseRecordID: record.id,
                    adjustment: -deducted,
                    resultingSupply: medication.currentSupply,
                    reason: .dose
                ))
            }
        } else {
            deleteMirror(for: record, context: context)
            if wasTaken {
                refundSupplyIfNeeded(
                    for: record,
                    medication: medication,
                    note: "Dose changed from taken to skipped.",
                    context: context
                )
            }
        }
        medication.updatedAt = date
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
