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

enum MedicationDoseUnit: String, Codable, CaseIterable, Identifiable {
    case tablet
    case capsule
    case milliliters = "mL"
    case milligrams = "mg"
    case micrograms = "mcg"
    case grams = "g"
    case units = "unit"
    case drops = "drop"
    case puffs = "puff"
    case sprays = "spray"
    case applications = "application"
    case patches = "patch"
    case packets = "packet"
    case scoops = "scoop"
    case suppositories = "suppository"
    case teaspoons = "tsp"
    case tablespoons = "tbsp"
    case doses = "dose"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tablet: "Tablet"
        case .capsule: "Capsule"
        case .milliliters: "Milliliter (mL)"
        case .milligrams: "Milligram (mg)"
        case .micrograms: "Microgram (mcg)"
        case .grams: "Gram (g)"
        case .units: "Unit"
        case .drops: "Drop"
        case .puffs: "Puff"
        case .sprays: "Spray"
        case .applications: "Application"
        case .patches: "Patch"
        case .packets: "Packet"
        case .scoops: "Scoop"
        case .suppositories: "Suppository"
        case .teaspoons: "Teaspoon (tsp)"
        case .tablespoons: "Tablespoon (tbsp)"
        case .doses: "Dose"
        }
    }

    static func defaultUnit(for form: MedicationForm) -> MedicationDoseUnit {
        switch form {
        case .tablet: .tablet
        case .capsule: .capsule
        case .liquid, .injection: .milliliters
        case .inhaler: .puffs
        case .drops: .drops
        case .cream: .applications
        case .patch: .patches
        case .other: .doses
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
    case held
    case refused
    case unable
    case missed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .taken: "Taken"
        case .skipped: "Skipped"
        case .held: "Held per clinician"
        case .refused: "Refused"
        case .unable: "Unable to take"
        case .missed: "Missed"
        }
    }

    var countsAsTaken: Bool { self == .taken }
    var countsAsNotTaken: Bool { !countsAsTaken }
}

enum MedicationDoseTiming: String, Codable, CaseIterable, Identifiable {
    case onSchedule
    case late

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onSchedule: "As scheduled"
        case .late: "Taken late"
        }
    }
}

enum MedicationDoseReason: String, Codable, CaseIterable, Identifiable {
    case asleep
    case away
    case outOfSupply
    case forgot
    case perClinicianInstruction
    case refused
    case unableToTake
    case sideEffects
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asleep: "Asleep"
        case .away: "Away from home"
        case .outOfSupply: "Out of supply"
        case .forgot: "Forgot"
        case .perClinicianInstruction: "Per clinician instruction"
        case .refused: "Refused"
        case .unableToTake: "Unable to take"
        case .sideEffects: "Side effects or concern"
        case .other: "Other"
        }
    }
}

struct MedicationDoseEntry: Equatable {
    var status: MedicationDoseStatus
    var takenAt: Date?
    var actualDoseAmount: Double?
    var timing: MedicationDoseTiming?
    var reason: MedicationDoseReason?
    var notes: String
}

enum MedicationPlanChangeSource: String, Codable, CaseIterable, Identifiable {
    case prescriptionLabel
    case dischargePaperwork
    case clinician
    case caregiver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prescriptionLabel: "Prescription label"
        case .dischargePaperwork: "Discharge paperwork"
        case .clinician: "Clinician"
        case .caregiver: "Caregiver"
        }
    }
}

enum MedicationPlanChangeKind: String, Codable, CaseIterable, Identifiable {
    case added
    case updated
    case stopped
    case restored
    case confirmedCurrent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .added: "Medication added"
        case .updated: "Plan changed"
        case .stopped: "Medication stopped"
        case .restored: "Medication restored"
        case .confirmedCurrent: "Confirmed current"
        }
    }
}

struct MedicationPlanChangeContext: Equatable {
    var effectiveFrom: Date
    var source: MedicationPlanChangeSource
    var appointmentID: UUID?
    var reconciliationID: UUID?
    var notes: String
    var confirmsCurrent: Bool

    init(
        effectiveFrom: Date = Date(),
        source: MedicationPlanChangeSource = .caregiver,
        appointmentID: UUID? = nil,
        reconciliationID: UUID? = nil,
        notes: String = "",
        confirmsCurrent: Bool = false
    ) {
        self.effectiveFrom = effectiveFrom
        self.source = source
        self.appointmentID = appointmentID
        self.reconciliationID = reconciliationID
        self.notes = notes
        self.confirmsCurrent = confirmsCurrent
    }
}

enum MedicationSupplyReason: String, Codable, CaseIterable, Identifiable {
    case refill
    case correction
    case dose
    case discarded

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum MedicationRefillStatus: String, Codable, CaseIterable, Identifiable {
    case needsRequest
    case requested
    case readyForPickup
    case pickedUp
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .needsRequest: "Request needed"
        case .requested: "Requested"
        case .readyForPickup: "Ready for pickup"
        case .pickedUp: "Picked up"
        case .cancelled: "Cancelled"
        }
    }

    var isOpen: Bool {
        switch self {
        case .needsRequest, .requested, .readyForPickup: true
        case .pickedUp, .cancelled: false
        }
    }
}

enum MedicationSupplyProjectionConfidence: String, Equatable {
    case limited
    case developing
    case established

    var displayName: String {
        switch self {
        case .limited: "Limited dose history"
        case .developing: "Developing estimate"
        case .established: "Based on recent use"
        }
    }
}

struct MedicationSupplyProjection: Equatable {
    var estimatedRunOutDate: Date
    var estimatedDaysRemaining: Double
    var averageDailyUse: Double
    var observedDoseCount: Int
    var observedDayCount: Int
    var confidence: MedicationSupplyProjectionConfidence
}

enum MedicationTripSupplyRisk: Equatable {
    case beforeTrip(runOutDate: Date)
    case duringTrip(runOutDate: Date)
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
    var refillLeadDays: Int = 7
    var prescriptionNumber: String = ""
    var fillQuantity: Double?
    var refillsRemaining: Int?
    var prescriptionExpirationDate: Date?
    var isArchived: Bool = false
    var lastReviewedAt: Date?
    var isConfirmedCurrent: Bool = false
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
        refillLeadDays: Int = 7,
        prescriptionNumber: String = "",
        fillQuantity: Double? = nil,
        refillsRemaining: Int? = nil,
        prescriptionExpirationDate: Date? = nil,
        isArchived: Bool = false,
        lastReviewedAt: Date? = nil,
        isConfirmedCurrent: Bool = false,
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
        self.refillLeadDays = refillLeadDays
        self.prescriptionNumber = prescriptionNumber
        self.fillQuantity = fillQuantity
        self.refillsRemaining = refillsRemaining
        self.prescriptionExpirationDate = prescriptionExpirationDate
        self.isArchived = isArchived
        self.lastReviewedAt = lastReviewedAt
        self.isConfirmedCurrent = isConfirmedCurrent
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

    var prescriptionIsExpired: Bool {
        prescriptionExpirationDate.map { $0 < Date() } ?? false
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

struct MedicationPlanPhaseSnapshot: Codable, Equatable {
    var sequence: Int
    var durationDays: Int?
    var doseAmount: Double
    var doseUnit: String
    var doseTimes: [MedicationDoseTime]
}

struct MedicationPlanSnapshot: Codable, Equatable {
    var medicationName: String
    var formRawValue: String
    var strength: Double?
    var strengthUnit: String
    var routeRawValue: String
    var instructions: String
    var reasonForTaking: String
    var prescriber: String
    var pharmacy: String
    var currentSupply: Double?
    var refillThreshold: Double?
    var refillLeadDays: Int?
    var prescriptionNumber: String?
    var fillQuantity: Double?
    var refillsRemaining: Int?
    var prescriptionExpirationDate: Date?
    var isArchived: Bool
    var lastReviewedAt: Date?
    var isConfirmedCurrent: Bool?

    var regimenID: UUID?
    var scheduleKindRawValue: String?
    var startDate: Date?
    var endDate: Date?
    var doseAmount: Double?
    var doseUnit: String?
    var doseTimes: [MedicationDoseTime]
    var weekdayMask: Int?
    var intervalDays: Int?
    var cycleOnDays: Int?
    var cycleOffDays: Int?
    var minimumHoursBetweenDoses: Double?
    var maximumDosesPerDay: Int?
    var remindersEnabled: Bool?
    var followUpRemindersEnabled: Bool?
    var reminderLeadMinutes: Int?
    var timeZoneBehaviorRawValue: String?
    var timeZoneIdentifier: String?
    var regimenInstructions: String?
    var phases: [MedicationPlanPhaseSnapshot]

    init(
        medication: Medication,
        regimen: MedicationRegimen?,
        phases: [MedicationSchedulePhase]
    ) {
        medicationName = medication.name
        formRawValue = medication.formRawValue
        strength = medication.strength
        strengthUnit = medication.strengthUnit
        routeRawValue = medication.routeRawValue
        instructions = medication.instructions
        reasonForTaking = medication.reasonForTaking
        prescriber = medication.prescriber
        pharmacy = medication.pharmacy
        currentSupply = medication.currentSupply
        refillThreshold = medication.refillThreshold
        refillLeadDays = medication.refillLeadDays
        prescriptionNumber = medication.prescriptionNumber
        fillQuantity = medication.fillQuantity
        refillsRemaining = medication.refillsRemaining
        prescriptionExpirationDate = medication.prescriptionExpirationDate
        isArchived = medication.isArchived
        lastReviewedAt = medication.lastReviewedAt
        isConfirmedCurrent = medication.isConfirmedCurrent

        regimenID = regimen?.id
        scheduleKindRawValue = regimen?.scheduleKindRawValue
        startDate = regimen?.startDate
        endDate = regimen?.endDate
        doseAmount = regimen?.doseAmount
        doseUnit = regimen?.doseUnit
        doseTimes = regimen?.doseTimes ?? []
        weekdayMask = regimen?.weekdayMask
        intervalDays = regimen?.intervalDays
        cycleOnDays = regimen?.cycleOnDays
        cycleOffDays = regimen?.cycleOffDays
        minimumHoursBetweenDoses = regimen?.minimumHoursBetweenDoses
        maximumDosesPerDay = regimen?.maximumDosesPerDay
        remindersEnabled = regimen?.remindersEnabled
        followUpRemindersEnabled = regimen?.followUpRemindersEnabled
        reminderLeadMinutes = regimen?.reminderLeadMinutes
        timeZoneBehaviorRawValue = regimen?.timeZoneBehaviorRawValue
        timeZoneIdentifier = regimen?.timeZoneIdentifier
        regimenInstructions = regimen?.instructions
        self.phases = phases
            .filter { regimen == nil || $0.regimenID == regimen?.id }
            .sorted { $0.sequence < $1.sequence }
            .map {
                MedicationPlanPhaseSnapshot(
                    sequence: $0.sequence,
                    durationDays: $0.durationDays,
                    doseAmount: $0.doseAmount,
                    doseUnit: $0.doseUnit,
                    doseTimes: $0.doseTimes
                )
            }
    }

    var scheduleKind: MedicationScheduleKind? {
        scheduleKindRawValue.flatMap(MedicationScheduleKind.init(rawValue:))
    }

    var form: MedicationForm {
        MedicationForm(rawValue: formRawValue) ?? .other
    }

    var route: MedicationRoute {
        MedicationRoute(rawValue: routeRawValue) ?? .other
    }
}

@Model
final class MedicationPlanRevision {
    var id: UUID = UUID()
    var profileID: UUID?
    var medicationID: UUID = UUID()
    var priorRegimenID: UUID?
    var regimenID: UUID?
    var changeKindRawValue: String = MedicationPlanChangeKind.updated.rawValue
    var sourceRawValue: String = MedicationPlanChangeSource.caregiver.rawValue
    var effectiveFrom: Date = Date()
    var changedAt: Date = Date()
    var changedByIdentifier: String = ""
    var changedByName: String = ""
    var appointmentID: UUID?
    var reconciliationID: UUID?
    var notes: String = ""
    var beforeSnapshotData: Data?
    var afterSnapshotData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        medicationID: UUID,
        priorRegimenID: UUID? = nil,
        regimenID: UUID? = nil,
        changeKind: MedicationPlanChangeKind,
        source: MedicationPlanChangeSource,
        effectiveFrom: Date,
        changedAt: Date = Date(),
        changedByIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier(),
        changedByName: String = CaregiverIdentityService.currentCaregiverName(),
        appointmentID: UUID? = nil,
        reconciliationID: UUID? = nil,
        notes: String = "",
        beforeSnapshot: MedicationPlanSnapshot? = nil,
        afterSnapshot: MedicationPlanSnapshot,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.medicationID = medicationID
        self.priorRegimenID = priorRegimenID
        self.regimenID = regimenID
        changeKindRawValue = changeKind.rawValue
        sourceRawValue = source.rawValue
        self.effectiveFrom = effectiveFrom
        self.changedAt = changedAt
        self.changedByIdentifier = changedByIdentifier
        self.changedByName = changedByName
        self.appointmentID = appointmentID
        self.reconciliationID = reconciliationID
        self.notes = notes
        beforeSnapshotData = beforeSnapshot.flatMap { try? JSONEncoder().encode($0) }
        afterSnapshotData = try? JSONEncoder().encode(afterSnapshot)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var changeKind: MedicationPlanChangeKind {
        MedicationPlanChangeKind(rawValue: changeKindRawValue) ?? .updated
    }

    var source: MedicationPlanChangeSource {
        MedicationPlanChangeSource(rawValue: sourceRawValue) ?? .caregiver
    }

    var beforeSnapshot: MedicationPlanSnapshot? {
        beforeSnapshotData.flatMap { try? JSONDecoder().decode(MedicationPlanSnapshot.self, from: $0) }
    }

    var afterSnapshot: MedicationPlanSnapshot? {
        afterSnapshotData.flatMap { try? JSONDecoder().decode(MedicationPlanSnapshot.self, from: $0) }
    }
}

@Model
final class MedicationReconciliation {
    var id: UUID = UUID()
    var profileID: UUID?
    var appointmentID: UUID?
    var sourceRawValue: String = MedicationPlanChangeSource.caregiver.rawValue
    var effectiveFrom: Date = Date()
    var completedAt: Date = Date()
    var reviewerIdentifier: String = ""
    var reviewerName: String = ""
    var notes: String = ""
    var reviewedMedicationIDsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        appointmentID: UUID? = nil,
        source: MedicationPlanChangeSource,
        effectiveFrom: Date,
        completedAt: Date = Date(),
        reviewerIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier(),
        reviewerName: String = CaregiverIdentityService.currentCaregiverName(),
        notes: String = "",
        reviewedMedicationIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.appointmentID = appointmentID
        sourceRawValue = source.rawValue
        self.effectiveFrom = effectiveFrom
        self.completedAt = completedAt
        self.reviewerIdentifier = reviewerIdentifier
        self.reviewerName = reviewerName
        self.notes = notes
        reviewedMedicationIDsData = try? JSONEncoder().encode(reviewedMedicationIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var source: MedicationPlanChangeSource {
        MedicationPlanChangeSource(rawValue: sourceRawValue) ?? .caregiver
    }

    var reviewedMedicationIDs: [UUID] {
        get {
            guard let reviewedMedicationIDsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: reviewedMedicationIDsData)) ?? []
        }
        set { reviewedMedicationIDsData = try? JSONEncoder().encode(newValue) }
    }
}

@Model
final class MedicationRefillTask {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var profileID: UUID?
    var medicationID: UUID = UUID()
    var statusRawValue: String = MedicationRefillStatus.needsRequest.rawValue
    var dueDate: Date?
    var fillQuantity: Double?
    var prescriptionNumberSnapshot: String = ""
    var pharmacySnapshot: String = ""
    var notes: String = ""
    var requestedAt: Date?
    var readyForPickupAt: Date?
    var pickedUpAt: Date?
    var cancelledAt: Date?
    var createdByCaregiverIdentifier: String = ""
    var createdByCaregiverName: String = ""
    var assignedCaregiverIdentifier: String?
    var assignedCaregiverName: String?
    var completedByCaregiverIdentifier: String?
    var completedByCaregiverName: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        householdID: UUID,
        profileID: UUID,
        medicationID: UUID,
        status: MedicationRefillStatus = .needsRequest,
        dueDate: Date? = nil,
        fillQuantity: Double? = nil,
        prescriptionNumberSnapshot: String = "",
        pharmacySnapshot: String = "",
        notes: String = "",
        requestedAt: Date? = nil,
        readyForPickupAt: Date? = nil,
        pickedUpAt: Date? = nil,
        cancelledAt: Date? = nil,
        createdByCaregiverIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier(),
        createdByCaregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        assignedCaregiverIdentifier: String? = nil,
        assignedCaregiverName: String? = nil,
        completedByCaregiverIdentifier: String? = nil,
        completedByCaregiverName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.medicationID = medicationID
        statusRawValue = status.rawValue
        self.dueDate = dueDate
        self.fillQuantity = fillQuantity
        self.prescriptionNumberSnapshot = prescriptionNumberSnapshot
        self.pharmacySnapshot = pharmacySnapshot
        self.notes = notes
        self.requestedAt = requestedAt
        self.readyForPickupAt = readyForPickupAt
        self.pickedUpAt = pickedUpAt
        self.cancelledAt = cancelledAt
        self.createdByCaregiverIdentifier = createdByCaregiverIdentifier
        self.createdByCaregiverName = createdByCaregiverName
        self.assignedCaregiverIdentifier = assignedCaregiverIdentifier
        self.assignedCaregiverName = assignedCaregiverName
        self.completedByCaregiverIdentifier = completedByCaregiverIdentifier
        self.completedByCaregiverName = completedByCaregiverName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: MedicationRefillStatus {
        get { MedicationRefillStatus(rawValue: statusRawValue) ?? .needsRequest }
        set { statusRawValue = newValue.rawValue }
    }

    var isOpen: Bool { status.isOpen }

    var attentionSourceKey: String {
        "\(HouseholdAttentionSourceKind.medicationRefill.rawValue):\(id.uuidString.lowercased())"
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
    var actualDoseAmount: Double?
    var timingRawValue: String?
    var reasonRawValue: String?
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
        actualDoseAmount: Double? = nil,
        timing: MedicationDoseTiming? = nil,
        reason: MedicationDoseReason? = nil,
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
        self.actualDoseAmount = actualDoseAmount
        self.timingRawValue = timing?.rawValue
        self.reasonRawValue = reason?.rawValue
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
        get { MedicationDoseStatus(rawValue: statusRawValue) ?? .skipped }
        set { statusRawValue = newValue.rawValue }
    }

    var timing: MedicationDoseTiming? {
        get { timingRawValue.flatMap(MedicationDoseTiming.init(rawValue:)) }
        set { timingRawValue = newValue?.rawValue }
    }

    var reason: MedicationDoseReason? {
        get { reasonRawValue.flatMap(MedicationDoseReason.init(rawValue:)) }
        set { reasonRawValue = newValue?.rawValue }
    }

    var effectiveActualDoseAmount: Double? {
        guard status.countsAsTaken else { return nil }
        return actualDoseAmount ?? doseAmount
    }

    var hasDifferentActualAmount: Bool {
        guard let effectiveActualDoseAmount else { return false }
        return abs(effectiveActualDoseAmount - doseAmount) > 0.000_001
    }

    var outcomeDisplayName: String {
        guard status == .taken else { return status.displayName }
        return switch (timing == .late, hasDifferentActualAmount) {
        case (true, true): "Taken late, different amount"
        case (true, false): "Taken late"
        case (false, true): "Different amount taken"
        case (false, false): "Taken"
        }
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
extension MedicationPlanRevision: ProfileScopedRecord {}
extension MedicationReconciliation: ProfileScopedRecord {}
extension MedicationRefillTask: ProfileScopedRecord {}
extension MedicationDoseRecord: ProfileScopedRecord {}
extension MedicationSupplyLog: ProfileScopedRecord {}
