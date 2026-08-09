import Foundation

enum EventType: String, Codable, CaseIterable, Identifiable {
    case sleep
    case feed
    case nursing
    case pumping
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
    case bloodPressure
    case heartRate
    case oxygenSaturation
    case respiratoryRate
    case pain
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: "Sleep"
        case .feed: "Feed"
        case .nursing: "Nursing"
        case .pumping: "Pumping"
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
        case .bloodPressure: "Blood Pressure"
        case .heartRate: "Pulse"
        case .oxygenSaturation: "Oxygen Saturation"
        case .respiratoryRate: "Respiratory Rate"
        case .pain: "Pain"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .feed: "waterbottle.fill"
        case .nursing: "figure.and.child.holdinghands"
        case .pumping: "drop.circle.fill"
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
        case .bloodPressure: "heart.text.square.fill"
        case .heartRate: "waveform.path.ecg"
        case .oxygenSaturation: "lungs.fill"
        case .respiratoryRate: "wind"
        case .pain: "bandage.fill"
        case .custom: "sparkles"
        }
    }

    func systemImage(for profileType: CareProfileType?) -> String {
        if self == .potty, profileType != .dog {
            return "figure.child"
        }
        return systemImage
    }

    var supportsTimer: Bool {
        [.sleep, .feed, .nursing, .pumping, .activity, .walk, .rest, .training, .grooming, .custom].contains(self)
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
            return [.sleep, .feed, .nursing, .pumping, .diaper, .potty, .medicine, .growth, .temperature, .activity, .custom]
        case .adult:
            return [.medicine, .symptom, .bloodPressure, .heartRate, .oxygenSaturation,
                    .respiratoryRate, .glucose, .temperature, .growth, .pain, .sleep,
                    .activity, .custom]
        case .dog:
            return [.food, .water, .treat, .potty, .walk, .rest, .training, .grooming, .medicine, .symptom, .growth, .temperature, .vaccine, .glucose, .custom]
        }
    }
}

extension ActivityType {
    static func cases(for profileType: CareProfileType) -> [ActivityType] {
        switch profileType {
        case .child:
            return [.tummyTime, .storyTime, .brushTeeth, .indoorPlay,
                    .outdoorPlay, .screenTime, .bath, .custom]
        case .adult:
            return [.exercise, .physicalTherapy, .socialActivity, .brushTeeth,
                    .screenTime, .bath, .custom]
        case .dog:
            return []
        }
    }

    static func defaultValue(for profileType: CareProfileType) -> ActivityType {
        cases(for: profileType).first ?? .custom
    }

    func isAvailable(for profileType: CareProfileType) -> Bool {
        Self.cases(for: profileType).contains(self)
    }
}
