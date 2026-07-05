import Foundation

enum SleepKind: String, Codable, CaseIterable, Identifiable {
    case nap
    case nightSleep
    var id: String { rawValue }
    var displayName: String { self == .nap ? "Nap" : "Night sleep" }
}

enum FeedKind: String, Codable, CaseIterable, Identifiable {
    case bottle
    case solid
    case other
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum SolidReaction: String, Codable, CaseIterable, Identifiable {
    case loved
    case liked
    case neutral
    case disliked
    case sensitivity
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loved: "Loved"
        case .liked: "Liked"
        case .neutral: "Neutral"
        case .disliked: "Disliked"
        case .sensitivity: "Sensitivity"
        case .unknown: "Unknown"
        }
    }
}

enum SolidTexture: String, Codable, CaseIterable, Identifiable {
    case puree
    case mashed
    case fingerFood
    case mixed
    case other
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fingerFood: "Finger food"
        default: rawValue.capitalized
        }
    }
}

enum SolidFeedingStyle: String, Codable, CaseIterable, Identifiable {
    case pureeSpoonFed
    case babyLedWeaning
    case combination
    case other
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pureeSpoonFed: "Puree / spoon-fed"
        case .babyLedWeaning: "Baby-led weaning"
        case .combination: "Combination"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}

enum NursingSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DiaperKind: String, Codable, CaseIterable, Identifiable {
    case wet
    case dirty
    case both
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .wet: "Pee"
        case .dirty: "Poo"
        case .both: "Mixed"
        }
    }
    var hasPee: Bool { self == .wet || self == .both }
    var hasPoo: Bool { self == .dirty || self == .both }
}

enum ChildPottyKind: String, Codable, CaseIterable, Identifiable {
    case pee
    case poo
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pee: "Pee"
        case .poo: "Poo"
        case .both: "Both"
        }
    }

    var hasPee: Bool { self == .pee || self == .both }
    var hasPoo: Bool { self == .poo || self == .both }
}

enum ChildPottyLocation: String, Codable, CaseIterable, Identifiable {
    case toilet
    case pottyChair
    case trainingPants
    case diaper
    case accident
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pottyChair: "Potty chair"
        case .trainingPants: "Training pants"
        default: rawValue.capitalized
        }
    }
}

enum DiaperAmount: String, Codable, CaseIterable, Identifiable {
    case little
    case medium
    case big
    case unknown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PooColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case green
    case brown
    case black
    case red
    case other
    case unknown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PooTexture: String, Codable, CaseIterable, Identifiable {
    case seedy
    case runny
    case soft
    case formed
    case hard
    case mucus
    case unknown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case tummyTime
    case storyTime
    case brushTeeth
    case indoorPlay
    case outdoorPlay
    case screenTime
    case bath
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tummyTime: "Tummy Time"
        case .storyTime: "Story Time"
        case .brushTeeth: "Brush Teeth"
        case .indoorPlay: "Indoor Play"
        case .outdoorPlay: "Outdoor Play"
        case .screenTime: "Screen Time"
        case .bath: "Bath"
        case .custom: "Custom Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .tummyTime: "figure.play"
        case .storyTime: "book.fill"
        case .brushTeeth: "mouth.fill"
        case .indoorPlay: "house.fill"
        case .outdoorPlay: "sun.max.fill"
        case .screenTime: "tv.fill"
        case .bath: "bathtub.fill"
        case .custom: "sparkles"
        }
    }

    static func legacyType(rawValue: String) -> ActivityType? {
        switch rawValue {
        case "tummyTime": .tummyTime
        case "reading": .storyTime
        case "bath": .bath
        default: nil
        }
    }
}

enum MedicineUnit: String, Codable, CaseIterable, Identifiable {
    case ounces = "oz"
    case milliliters = "mL"
    case drops
    case teaspoons = "tsp"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case fahrenheit
    case celsius

    var id: String { rawValue }
    var displayName: String { self == .fahrenheit ? "°F" : "°C" }
}

enum TemperatureMethod: String, Codable, CaseIterable, Identifiable {
    case forehead
    case ear
    case rectal
    case oral
    case armpit
    case unknown

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PredictionKind: String, Codable, CaseIterable, Identifiable {
    case nap
    case bedtime
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ConfidenceLabel: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}
