import Foundation

enum VoiceCareKind: String, CaseIterable, Codable, Sendable {
    case bottle, diaper, sleep, nursing, pumping, temperature, bloodPressure
    case heartRate, oxygenSaturation, respiratoryRate, glucose, weight, pain
    case symptom, activity, note
    case wetDiaper, dirtyDiaper, mixedDiaper, potty, pottyPee, pottyPoop, pottyBoth
    case solidMeal, otherFeed, height, headCircumference
    case tummyTime, storyTime, brushTeeth, indoorPlay, outdoorPlay, screenTime, bath
    case exercise, physicalTherapy, socialActivity
    case littlePee, mediumPee, bigPee, littlePoo, mediumPoo, bigPoo
    case littleMixedDiaper, mediumMixedDiaper, bigMixedDiaper

    var title: String {
        switch self {
        case .bottle: "Bottle"
        case .diaper: "Diaper"
        case .sleep: "Sleep"
        case .nursing: "Nursing"
        case .pumping: "Pumping"
        case .temperature: "Temperature"
        case .bloodPressure: "Blood pressure"
        case .heartRate: "Pulse"
        case .oxygenSaturation: "Oxygen saturation"
        case .respiratoryRate: "Breathing rate"
        case .glucose: "Blood glucose"
        case .weight: "Weight"
        case .pain: "Pain"
        case .symptom: "Symptom"
        case .activity: "Activity"
        case .note: "Note"
        case .wetDiaper: "Wet diaper"
        case .dirtyDiaper: "Dirty diaper"
        case .mixedDiaper: "Mixed diaper"
        case .potty: "Potty"
        case .pottyPee: "Potty pee"
        case .pottyPoop: "Potty poo"
        case .pottyBoth: "Potty pee and poo"
        case .solidMeal: "Solid meal"
        case .otherFeed: "Other feed"
        case .height: "Height"
        case .headCircumference: "Head circumference"
        case .littlePee: "Little pee"
        case .mediumPee: "Medium pee"
        case .bigPee: "Big pee"
        case .littlePoo: "Little poo"
        case .mediumPoo: "Medium poo"
        case .bigPoo: "Big poo"
        case .littleMixedDiaper: "Little mixed diaper"
        case .mediumMixedDiaper: "Medium mixed diaper"
        case .bigMixedDiaper: "Big mixed diaper"
        default: activityType!.displayName
        }
    }

    var eventType: EventType {
        switch self {
        case .bottle, .solidMeal, .otherFeed: .feed
        case .weight, .height, .headCircumference: .growth
        case .wetDiaper, .dirtyDiaper, .mixedDiaper,
             .littlePee, .mediumPee, .bigPee, .littlePoo, .mediumPoo, .bigPoo,
             .littleMixedDiaper, .mediumMixedDiaper, .bigMixedDiaper: .diaper
        case .pottyPee, .pottyPoop, .pottyBoth: .potty
        case .tummyTime, .storyTime, .brushTeeth, .indoorPlay, .outdoorPlay, .screenTime, .bath,
             .exercise, .physicalTherapy, .socialActivity: .activity
        case .note: .custom
        default: EventType(rawValue: rawValue)!
        }
    }

    func supports(_ profileType: CareProfileType) -> Bool {
        guard profileType != .dog else { return false }
        if self == .headCircumference, profileType != .child { return false }
        if let activityType, !activityType.isAvailable(for: profileType) { return false }
        return EventType.cases(for: profileType).contains(eventType)
    }

    var diaperKind: DiaperKind? {
        switch self {
        case .wetDiaper, .littlePee, .mediumPee, .bigPee: .wet
        case .dirtyDiaper, .littlePoo, .mediumPoo, .bigPoo: .dirty
        case .mixedDiaper, .littleMixedDiaper, .mediumMixedDiaper, .bigMixedDiaper: .both
        default: nil
        }
    }

    var pottyKind: ChildPottyKind? {
        switch self {
        case .pottyPee: .pee
        case .pottyPoop: .poo
        case .pottyBoth: .both
        default: nil
        }
    }

    var activityType: ActivityType? {
        self == .activity ? .custom : ActivityType(rawValue: rawValue)
    }

    var feedKind: FeedKind? {
        switch self {
        case .bottle: .bottle
        case .solidMeal: .solid
        case .otherFeed: .other
        default: nil
        }
    }

    var diaperAmount: DiaperAmount? {
        switch self {
        case .littlePee, .littlePoo, .littleMixedDiaper: .little
        case .mediumPee, .mediumPoo, .mediumMixedDiaper: .medium
        case .bigPee, .bigPoo, .bigMixedDiaper: .big
        default: nil
        }
    }

    func matchesSavedEntry(_ event: CareEvent) -> Bool {
        guard event.type == eventType else { return false }
        if let feedKind, event.feedKind != feedKind { return false }
        if let diaperKind {
            guard let actual = event.diaperKind else { return false }
            if diaperKind.hasPee && !actual.hasPee || diaperKind.hasPoo && !actual.hasPoo { return false }
            if let amount = diaperAmount {
                if diaperKind.hasPee && event.peeAmount != amount { return false }
                if diaperKind.hasPoo && event.pooAmount != amount { return false }
            }
        }
        if let pottyKind {
            guard let actual = event.childPottyKind else { return false }
            if pottyKind.hasPee && !actual.hasPee || pottyKind.hasPoo && !actual.hasPoo { return false }
        }
        if self != .activity, let activityType, event.activityType != activityType { return false }
        if self == .weight { return event.canonicalWeightKilograms != nil }
        if self == .height { return event.canonicalLengthCentimeters != nil }
        if self == .headCircumference { return event.canonicalHeadCircumferenceCentimeters != nil }
        return true
    }
}

enum VoiceCareUnit: String, CaseIterable, Sendable {
    case ounces, milliliters, celsius, fahrenheit, kilograms, pounds
    case milligramsPerDeciliter, millimolesPerLiter
    case grams, weightOunces, centimeters, inches
}

struct VoiceCareLog: Sendable {
    var id = UUID()
    var profileID: UUID
    var kind: VoiceCareKind
    var date: Date
    var durationMinutes: Double?
    var value: Double?
    var unit: VoiceCareUnit?
    var secondValue: Double?
    var pulse: Double?
    var text: String?
    var notes: String?
    var diaperKind: DiaperKind?
    var nursingSide: NursingSide?
    var sleepKind: SleepKind?
    var pottyKind: ChildPottyKind?
    var pottyLocation: ChildPottyLocation?
    var pottyAccident: Bool?
    var peeAmount: DiaperAmount?
    var pooAmount: DiaperAmount?
    var pooColor: PooColor?
    var pooTexture: PooTexture?
    var diaperRash: Bool?
}

enum VoiceTimerAction: String, CaseIterable, Sendable {
    case start, pause, resume, switchSide, finish, reset, discard, adjustStart
}

/// The timer catalog mirrors the app's event and activity types, rather than
/// borrowing the much broader list of care measurements used for logging.
enum VoiceTimerKind: String, CaseIterable, Sendable {
    case sleep, nap, nightSleep, nightWaking
    case nursing, nursingLeft, nursingRight, pumping
    case bottle, solidMeal, otherFeed
    case tummyTime, storyTime, brushTeeth, indoorPlay, outdoorPlay, screenTime, bath
    case exercise, physicalTherapy, socialActivity, customActivity, customTimer

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .nap: "Nap"
        case .nightSleep: "Night sleep"
        case .nightWaking: "Night waking"
        case .nursing: "Nursing"
        case .nursingLeft: "Nursing left"
        case .nursingRight: "Nursing right"
        case .pumping: "Pumping"
        case .bottle: "Bottle"
        case .solidMeal: "Solid meal"
        case .otherFeed: "Other feed"
        case .customTimer: "Custom timer"
        default: activityType!.displayName
        }
    }

    var eventType: EventType {
        switch self {
        case .sleep, .nap, .nightSleep, .nightWaking: .sleep
        case .nursing, .nursingLeft, .nursingRight: .nursing
        case .pumping: .pumping
        case .bottle, .solidMeal, .otherFeed: .feed
        case .customTimer: .custom
        default: .activity
        }
    }

    var activityType: ActivityType? {
        switch self {
        case .customActivity: .custom
        default: ActivityType(rawValue: rawValue)
        }
    }

    var sleepKind: SleepKind? {
        switch self {
        case .nap: .nap
        case .nightSleep: .nightSleep
        case .nightWaking: .nightWaking
        default: nil
        }
    }

    var nursingSide: NursingSide? {
        switch self {
        case .nursingLeft: .left
        case .nursingRight: .right
        default: nil
        }
    }

    var feedKind: FeedKind? {
        switch self {
        case .bottle: .bottle
        case .solidMeal: .solid
        case .otherFeed: .other
        default: nil
        }
    }

    var needsName: Bool { [.customActivity, .customTimer, .solidMeal, .otherFeed].contains(self) }

    func supports(_ type: CareProfileType) -> Bool {
        guard type != .dog, EventType.cases(for: type).contains(eventType) else { return false }
        if let activityType { return activityType.isAvailable(for: type) }
        return type == .child || self != .nightWaking
    }

    func matches(_ event: CareEvent) -> Bool {
        guard event.type == eventType else { return false }
        if let activityType, (event.activityType ?? .custom) != activityType { return false }
        if let sleepKind, event.sleepKind != sleepKind { return false }
        if let feedKind, event.feedKind != feedKind {
            // Older generic feed timers did not always have a subtype yet.
            if self != .otherFeed || event.feedKind != nil { return false }
        }
        if let nursingSide, (event.activeNursingSide ?? event.nursingSide) != nursingSide { return false }
        return true
    }

    static func kind(for event: CareEvent) -> Self? {
        switch event.type {
        case .sleep:
            switch event.sleepKind {
            case .nap: .nap
            case .nightSleep: .nightSleep
            case .nightWaking: .nightWaking
            case .none: .sleep
            }
        case .nursing: .nursing
        case .pumping: .pumping
        case .feed:
            switch event.feedKind {
            case .bottle: .bottle
            case .solid: .solidMeal
            default: .otherFeed
            }
        case .activity:
            event.activityType == .custom || event.activityType == nil
                ? .customActivity : Self(rawValue: event.activityType!.rawValue)
        case .custom: .customTimer
        default: nil
        }
    }
}

struct VoiceTimerOption: Identifiable, Sendable {
    var id: UUID
    var profileID: UUID
    var profileName: String
    var kind: VoiceTimerKind
    var title: String
    var isRunning: Bool
    var updatedAt: Date
    var amountOz: Double?
    var elapsedSeconds: Double
    var startDate: Date
    var profileSubtitle: String
}

struct VoiceLoggingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
