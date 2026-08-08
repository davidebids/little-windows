import Foundation
import SwiftData

enum MedicationScheduleDate {
    static func currentCalendar(
        timeZone: TimeZone = CareTimeZoneSettings.effectiveTimeZone()
    ) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    static func displayDate(
        for storedDate: Date,
        anchorTimeZoneIdentifier: String?,
        calendar targetCalendar: Calendar = currentCalendar()
    ) -> Date {
        var anchorCalendar = targetCalendar
        if let anchorTimeZoneIdentifier,
           let anchorTimeZone = TimeZone(identifier: anchorTimeZoneIdentifier) {
            anchorCalendar.timeZone = anchorTimeZone
        }
        let components = anchorCalendar.dateComponents([.year, .month, .day], from: storedDate)
        return targetCalendar.date(from: components) ?? targetCalendar.startOfDay(for: storedDate)
    }

    static func storedDate(
        for selectedDate: Date,
        anchorTimeZoneIdentifier: String,
        calendar selectionCalendar: Calendar = currentCalendar()
    ) -> Date {
        let components = selectionCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        var anchorCalendar = selectionCalendar
        if let anchorTimeZone = TimeZone(identifier: anchorTimeZoneIdentifier) {
            anchorCalendar.timeZone = anchorTimeZone
        }
        return anchorCalendar.date(from: components) ?? selectionCalendar.startOfDay(for: selectedDate)
    }
}

enum MedicationForm: String, Codable, CaseIterable, Identifiable {
    case tablet
    case capsule
    case liquid
    case injection
    case inhaler
    case drops
    case cream
    case patch
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tablet: "Tablet"
        case .capsule: "Capsule"
        case .liquid: "Liquid"
        case .injection: "Injection"
        case .inhaler: "Inhaler"
        case .drops: "Drops"
        case .cream: "Cream"
        case .patch: "Patch"
        case .other: "Other"
        }
    }
}

enum MedicationRoute: String, Codable, CaseIterable, Identifiable {
    case oral
    case topical
    case inhaled
    case injected
    case eye
    case ear
    case nasal
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oral: "By mouth"
        case .topical: "Topical"
        case .inhaled: "Inhaled"
        case .injected: "Injected"
        case .eye: "Eye"
        case .ear: "Ear"
        case .nasal: "Nasal"
        case .other: "Other"
        }
    }
}

enum MedicationScheduleKind: String, Codable, CaseIterable, Identifiable {
    case daily
    case specificWeekdays
    case everyNDays
    case fixedCourse
    case cycle
    case alternating
    case taper
    case asNeeded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Every day"
        case .specificWeekdays: "Specific weekdays"
        case .everyNDays: "Every few days"
        case .fixedCourse: "Fixed course"
        case .cycle: "On/off cycle"
        case .alternating: "Alternating doses"
        case .taper: "Taper"
        case .asNeeded: "As needed"
        }
    }

    var isScheduled: Bool { self != .asNeeded }
}

enum MedicationTimeZoneBehavior: String, Codable, CaseIterable, Identifiable {
    case localTime
    case fixedTimeZone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localTime: "Follow local time"
        case .fixedTimeZone: "Keep home time"
        }
    }
}

enum MedicationDoseStatus: String, Codable, CaseIterable, Identifiable {
    case taken
    case skipped

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum MedicationSupplyReason: String, Codable, CaseIterable, Identifiable {
    case refill
    case correction
    case dose
    case discarded

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct MedicationDoseTime: Codable, Equatable, Hashable, Identifiable {
    var hour: Int
    var minute: Int

    var id: String { String(format: "%02d:%02d", hour, minute) }

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 8, minute: components.minute ?? 0)
    }

    func date(on day: Date, calendar: Calendar) -> Date? {
        let startOfDay = calendar.startOfDay(for: day)
        guard let value = calendar.nextDate(
            after: startOfDay.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(value, inSameDayAs: startOfDay) else {
            return nil
        }
        return value
    }
}

@Model
final class Medication {
    var id: UUID = UUID()
    var profileID: UUID?
    var name: String = ""
    var formRawValue: String = MedicationForm.tablet.rawValue
    var strength: Double?
    var strengthUnit: String = "mg"
    var routeRawValue: String = MedicationRoute.oral.rawValue
    var instructions: String = ""
    var reasonForTaking: String = ""
    var prescriber: String = ""
    var pharmacy: String = ""
    var currentSupply: Double?
    var refillThreshold: Double?
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        name: String,
        form: MedicationForm = .tablet,
        strength: Double? = nil,
        strengthUnit: String = "mg",
        route: MedicationRoute = .oral,
        instructions: String = "",
        reasonForTaking: String = "",
        prescriber: String = "",
        pharmacy: String = "",
        currentSupply: Double? = nil,
        refillThreshold: Double? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.formRawValue = form.rawValue
        self.strength = strength
        self.strengthUnit = strengthUnit
        self.routeRawValue = route.rawValue
        self.instructions = instructions
        self.reasonForTaking = reasonForTaking
        self.prescriber = prescriber
        self.pharmacy = pharmacy
        self.currentSupply = currentSupply
        self.refillThreshold = refillThreshold
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRawValue)! }
        set { formRawValue = newValue.rawValue }
    }

    var route: MedicationRoute {
        get { MedicationRoute(rawValue: routeRawValue)! }
        set { routeRawValue = newValue.rawValue }
    }

    var strengthDescription: String? {
        guard let strength else { return nil }
        return "\(strength.formatted(.number.precision(.fractionLength(0...2)))) \(strengthUnit)"
    }

    var needsRefill: Bool {
        guard let currentSupply, let refillThreshold else { return false }
        return currentSupply <= refillThreshold
    }
}

@Model
final class MedicationRegimen {
    var id: UUID = UUID()
    var profileID: UUID?
    var medicationID: UUID = UUID()
    var scheduleKindRawValue: String = MedicationScheduleKind.daily.rawValue
    var startDate: Date = Date()
    var endDate: Date?
    var doseAmount: Double = 1
    var doseUnit: String = "tablet"
    var doseTimesData: Data?
    var weekdayMask: Int = 127
    var intervalDays: Int = 2
    var cycleOnDays: Int = 21
    var cycleOffDays: Int = 7
    var minimumHoursBetweenDoses: Double?
    var maximumDosesPerDay: Int?
    var remindersEnabled: Bool = false
    var followUpRemindersEnabled: Bool = false
    var reminderLeadMinutes: Int = 0
    var timeZoneBehaviorRawValue: String = MedicationTimeZoneBehavior.localTime.rawValue
    var timeZoneIdentifier: String?
    var instructions: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        medicationID: UUID,
        scheduleKind: MedicationScheduleKind,
        startDate: Date,
        endDate: Date? = nil,
        doseAmount: Double,
        doseUnit: String,
        doseTimes: [MedicationDoseTime] = [MedicationDoseTime(hour: 8, minute: 0)],
        weekdayMask: Int = 127,
        intervalDays: Int = 2,
        cycleOnDays: Int = 21,
        cycleOffDays: Int = 7,
        minimumHoursBetweenDoses: Double? = nil,
        maximumDosesPerDay: Int? = nil,
        remindersEnabled: Bool = false,
        followUpRemindersEnabled: Bool = false,
        reminderLeadMinutes: Int = 0,
        timeZoneBehavior: MedicationTimeZoneBehavior = .localTime,
        timeZoneIdentifier: String? = nil,
        instructions: String = "",
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.medicationID = medicationID
        self.scheduleKindRawValue = scheduleKind.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.doseTimesData = try? JSONEncoder().encode(doseTimes)
        self.weekdayMask = weekdayMask
        self.intervalDays = max(intervalDays, 1)
        self.cycleOnDays = max(cycleOnDays, 1)
        self.cycleOffDays = max(cycleOffDays, 0)
        self.minimumHoursBetweenDoses = minimumHoursBetweenDoses
        self.maximumDosesPerDay = maximumDosesPerDay
        self.remindersEnabled = remindersEnabled
        self.followUpRemindersEnabled = followUpRemindersEnabled
        self.reminderLeadMinutes = reminderLeadMinutes
        self.timeZoneBehaviorRawValue = timeZoneBehavior.rawValue
        self.timeZoneIdentifier = timeZoneIdentifier
        self.instructions = instructions
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var scheduleKind: MedicationScheduleKind {
        get { MedicationScheduleKind(rawValue: scheduleKindRawValue)! }
        set { scheduleKindRawValue = newValue.rawValue }
    }

    var doseTimes: [MedicationDoseTime] {
        get {
            guard let doseTimesData,
                  let values = try? JSONDecoder().decode([MedicationDoseTime].self, from: doseTimesData) else {
                return []
            }
            return values.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        }
        set { doseTimesData = try? JSONEncoder().encode(newValue) }
    }

    var timeZoneBehavior: MedicationTimeZoneBehavior {
        get { MedicationTimeZoneBehavior(rawValue: timeZoneBehaviorRawValue)! }
        set { timeZoneBehaviorRawValue = newValue.rawValue }
    }

    var scheduleSummary: String {
        switch scheduleKind {
        case .daily: "Every day"
        case .specificWeekdays: "Selected weekdays"
        case .everyNDays: "Every \(intervalDays) days"
        case .fixedCourse:
            endDate.map {
                let displayDate = MedicationScheduleDate.displayDate(
                    for: $0,
                    anchorTimeZoneIdentifier: timeZoneIdentifier
                )
                return "Through \(displayDate.formatted(date: .abbreviated, time: .omitted))"
            } ?? "Fixed course"
        case .cycle: "\(cycleOnDays) days on, \(cycleOffDays) days off"
        case .alternating: "Alternating doses"
        case .taper: "Taper schedule"
        case .asNeeded: "As needed"
        }
    }
}

@Model
final class MedicationSchedulePhase {
    var id: UUID = UUID()
    var profileID: UUID?
    var regimenID: UUID = UUID()
    var sequence: Int = 0
    var durationDays: Int?
    var doseAmount: Double = 1
    var doseUnit: String = "tablet"
    var doseTimesData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        regimenID: UUID,
        sequence: Int,
        durationDays: Int?,
        doseAmount: Double,
        doseUnit: String,
        doseTimes: [MedicationDoseTime],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.regimenID = regimenID
        self.sequence = sequence
        self.durationDays = durationDays
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.doseTimesData = try? JSONEncoder().encode(doseTimes)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var doseTimes: [MedicationDoseTime] {
        get {
            guard let doseTimesData,
                  let values = try? JSONDecoder().decode([MedicationDoseTime].self, from: doseTimesData) else {
                return []
            }
            return values.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        }
        set { doseTimesData = try? JSONEncoder().encode(newValue) }
    }
}

@Model
final class MedicationDoseRecord {
    var id: UUID = UUID()
    var profileID: UUID?
    var medicationID: UUID = UUID()
    var regimenID: UUID?
    var phaseID: UUID?
    var occurrenceKey: String?
    var scheduledAt: Date?
    var statusRawValue: String = MedicationDoseStatus.taken.rawValue
    var loggedAt: Date = Date()
    var takenAt: Date?
    var doseAmount: Double = 1
    var doseUnit: String = "tablet"
    var supplyAdjustmentApplied: Double = 0
    var caregiverIdentifier: String = ""
    var caregiverName: String = ""
    var notes: String = ""
    var careEventID: UUID?
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        medicationID: UUID,
        regimenID: UUID? = nil,
        phaseID: UUID? = nil,
        occurrenceKey: String? = nil,
        scheduledAt: Date? = nil,
        status: MedicationDoseStatus,
        loggedAt: Date = Date(),
        takenAt: Date? = nil,
        doseAmount: Double,
        doseUnit: String,
        supplyAdjustmentApplied: Double = 0,
        caregiverIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier(),
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        notes: String = "",
        careEventID: UUID? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.medicationID = medicationID
        self.regimenID = regimenID
        self.phaseID = phaseID
        self.occurrenceKey = occurrenceKey
        self.scheduledAt = scheduledAt
        self.statusRawValue = status.rawValue
        self.loggedAt = loggedAt
        self.takenAt = takenAt
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.supplyAdjustmentApplied = supplyAdjustmentApplied
        self.caregiverIdentifier = caregiverIdentifier
        self.caregiverName = caregiverName
        self.notes = notes
        self.careEventID = careEventID
        self.updatedAt = updatedAt
    }

    var status: MedicationDoseStatus {
        get { MedicationDoseStatus(rawValue: statusRawValue)! }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class MedicationSupplyLog {
    var id: UUID = UUID()
    var profileID: UUID?
    var medicationID: UUID = UUID()
    var doseRecordID: UUID?
    var adjustment: Double = 0
    var resultingSupply: Double?
    var reasonRawValue: String = MedicationSupplyReason.correction.rawValue
    var notes: String = ""
    var loggedAt: Date = Date()
    var caregiverIdentifier: String = ""
    var caregiverName: String = ""

    init(
        id: UUID = UUID(),
        profileID: UUID,
        medicationID: UUID,
        doseRecordID: UUID? = nil,
        adjustment: Double,
        resultingSupply: Double?,
        reason: MedicationSupplyReason,
        notes: String = "",
        loggedAt: Date = Date(),
        caregiverIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier(),
        caregiverName: String = CaregiverIdentityService.currentCaregiverName()
    ) {
        self.id = id
        self.profileID = profileID
        self.medicationID = medicationID
        self.doseRecordID = doseRecordID
        self.adjustment = adjustment
        self.resultingSupply = resultingSupply
        self.reasonRawValue = reason.rawValue
        self.notes = notes
        self.loggedAt = loggedAt
        self.caregiverIdentifier = caregiverIdentifier
        self.caregiverName = caregiverName
    }

    var reason: MedicationSupplyReason {
        get { MedicationSupplyReason(rawValue: reasonRawValue)! }
        set { reasonRawValue = newValue.rawValue }
    }
}

extension Medication: ProfileScopedRecord {}
extension MedicationRegimen: ProfileScopedRecord {}
extension MedicationSchedulePhase: ProfileScopedRecord {}
extension MedicationDoseRecord: ProfileScopedRecord {}
extension MedicationSupplyLog: ProfileScopedRecord {}
