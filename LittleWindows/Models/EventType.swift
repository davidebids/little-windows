import Foundation

enum EventType: String, Codable, CaseIterable, Identifiable {
    case sleep
    case feed
    case nursing
    case diaper
    case medicine
    case growth
    case temperature
    case activity
    case food
    case water
    case treat
    case potty
    case walk
    case rest
    case training
    case grooming
    case symptom
    case vaccine
    case glucose
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: "Sleep"
        case .feed: "Feed"
        case .nursing: "Nursing"
        case .diaper: "Diaper"
        case .medicine: "Medicine"
        case .growth: "Growth"
        case .temperature: "Temperature"
        case .activity: "Activity"
        case .food: "Food"
        case .water: "Water"
        case .treat: "Treat"
        case .potty: "Potty"
        case .walk: "Walk"
        case .rest: "Rest"
        case .training: "Training"
        case .grooming: "Grooming"
        case .symptom: "Symptom"
        case .vaccine: "Vaccine"
        case .glucose: "Glucose"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .feed: "waterbottle.fill"
        case .nursing: "figure.and.child.holdinghands"
        case .diaper: "drop.fill"
        case .medicine: "cross.case.fill"
        case .growth: "ruler.fill"
        case .temperature: "thermometer.medium"
        case .activity: "figure.play"
        case .food: "fork.knife"
        case .water: "drop.fill"
        case .treat: "birthday.cake.fill"
        case .potty: "pawprint.fill"
        case .walk: "figure.walk"
        case .rest: "bed.double.fill"
        case .training: "graduationcap.fill"
        case .grooming: "comb.fill"
        case .symptom: "exclamationmark.triangle.fill"
        case .vaccine: "syringe.fill"
        case .glucose: "drop.triangle.fill"
        case .custom: "sparkles"
        }
    }

    var supportsTimer: Bool {
        [.sleep, .feed, .nursing, .activity, .walk, .rest, .training, .grooming, .custom].contains(self)
    }

    var affectsSleepPrediction: Bool {
        self == .sleep || self == .feed || self == .nursing
    }

    static func normalized(rawValue: String) -> EventType {
        switch rawValue {
        case "tummyTime", "reading", "bath":
            return .activity
        default:
            return EventType(rawValue: rawValue) ?? .custom
        }
    }

    static func cases(for profileType: CareProfileType) -> [EventType] {
        switch profileType {
        case .child:
            return [.sleep, .feed, .nursing, .diaper, .medicine, .growth, .temperature, .activity, .custom]
        case .dog:
            return [.food, .water, .treat, .potty, .walk, .rest, .training, .grooming, .medicine, .symptom, .growth, .temperature, .vaccine, .glucose, .custom]
        }
    }
}
