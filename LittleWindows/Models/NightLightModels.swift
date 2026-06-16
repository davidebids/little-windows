import Foundation
import SwiftUI

enum NightLightColor: String, Codable, CaseIterable, Identifiable {
    case softRed
    case warmAmber
    case candlelight
    case softOrange
    case softPink
    case warmWhite
    case coolWhite
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .softRed: "Soft Red"
        case .warmAmber: "Warm Amber"
        case .candlelight: "Candlelight"
        case .softOrange: "Soft Orange"
        case .softPink: "Soft Pink"
        case .warmWhite: "Warm White"
        case .coolWhite: "Cool White"
        case .custom: "Custom"
        }
    }

    var color: Color {
        switch self {
        case .softRed: Color(red: 0.72, green: 0.08, blue: 0.06)
        case .warmAmber: Color(red: 0.96, green: 0.43, blue: 0.08)
        case .candlelight: Color(red: 1.0, green: 0.57, blue: 0.18)
        case .softOrange: Color(red: 0.96, green: 0.31, blue: 0.10)
        case .softPink: Color(red: 0.90, green: 0.25, blue: 0.34)
        case .warmWhite: Color(red: 1.0, green: 0.82, blue: 0.58)
        case .coolWhite: Color(red: 0.78, green: 0.88, blue: 1.0)
        case .custom: .orange
        }
    }

    var isBrightWhite: Bool {
        self == .warmWhite || self == .coolWhite
    }
}

enum NightLightShape: String, Codable, CaseIterable, Identifiable {
    case fullScreenGlow
    case circle
    case oval
    case roundedRectangle
    case crescent
    case star
    case heart
    case moon
    case cloud
    case teddyBear
    case duck
    case bunny
    case elephant
    case whale
    case bird
    case leaf
    case flower
    case sun
    case mountain
    case raindrop
    case sleepyFace
    case blanket
    case crib
    case nightSky
    case blob
    case wave
    case gradientOrb
    case halo
    case lantern
    case windowGlow
    case custom

    var id: String { rawValue }

    static var selectableCases: [NightLightShape] {
        allCases.filter { $0 != .custom }
    }

    var displayName: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }

    var systemImage: String {
        switch self {
        case .fullScreenGlow: "rectangle.inset.filled"
        case .circle: "circle.fill"
        case .oval: "oval.fill"
        case .roundedRectangle: "rectangle.roundedtop.fill"
        case .crescent, .moon: "moon.fill"
        case .star: "star.fill"
        case .heart: "heart.fill"
        case .cloud: "cloud.fill"
        case .teddyBear: "teddybear.fill"
        case .duck, .bird: "bird.fill"
        case .bunny: "hare.fill"
        case .elephant: "elephant.fill"
        case .whale: "fish.fill"
        case .leaf: "leaf.fill"
        case .flower: "camera.macro"
        case .sun: "sun.max.fill"
        case .mountain: "mountain.2.fill"
        case .raindrop: "drop.fill"
        case .sleepyFace: "face.smiling.inverse"
        case .blanket: "square.fill"
        case .crib: "bed.double.fill"
        case .nightSky: "sparkles"
        case .blob: "seal.fill"
        case .wave: "water.waves"
        case .gradientOrb: "circle.hexagongrid.fill"
        case .halo: "circle.circle.fill"
        case .lantern: "lamp.table.fill"
        case .windowGlow: "window.vertical.closed"
        case .custom: "scribble.variable"
        }
    }
}

enum NightLightSound: String, Codable, CaseIterable, Identifiable {
    case none
    case whiteNoise
    case rain
    case lullaby
    case heartbeat
    case ocean
    case shushing
    case fan
    case fireplace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .whiteNoise: "White Noise"
        case .rain: "Rain"
        case .lullaby: "Lullaby"
        case .heartbeat: "Heartbeat"
        case .ocean: "Ocean"
        case .shushing: "Shushing"
        case .fan: "Soft Fan"
        case .fireplace: "Fireplace"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "speaker.slash.fill"
        case .whiteNoise: "waveform"
        case .rain: "cloud.rain.fill"
        case .lullaby: "music.note"
        case .heartbeat: "heart.fill"
        case .ocean: "water.waves"
        case .shushing: "mouth.fill"
        case .fan: "fan.fill"
        case .fireplace: "flame.fill"
        }
    }
}

enum NightLightGlowMode: String, Codable, CaseIterable, Identifiable {
    case steady
    case fireplace
    case candle
    case shimmer
    case rainyWindow
    case starryNight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steady: "Steady"
        case .fireplace: "Fireplace"
        case .candle: "Candle Glow"
        case .shimmer: "Gentle Shimmer"
        case .rainyWindow: "Rainy Window"
        case .starryNight: "Starry Night"
        }
    }

    var systemImage: String {
        switch self {
        case .steady: "lightbulb.fill"
        case .fireplace: "flame.fill"
        case .candle: "flame"
        case .shimmer: "sparkles"
        case .rainyWindow: "cloud.rain.fill"
        case .starryNight: "moon.stars.fill"
        }
    }

    var displaysSelectedShape: Bool {
        self == .steady || self == .shimmer
    }
}

enum NightLightBreathingSpeed: String, Codable, CaseIterable, Identifiable {
    case slow
    case medium
    case fast

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var duration: TimeInterval {
        switch self {
        case .slow: 7
        case .medium: 5
        case .fast: 3.5
        }
    }
}

enum NightLightBreathingIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle
    case normal
    case strong

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var scaleRange: CGFloat {
        switch self {
        case .subtle: 0.06
        case .normal: 0.11
        case .strong: 0.17
        }
    }

    var brightnessRange: Double {
        switch self {
        case .subtle: 0.08
        case .normal: 0.14
        case .strong: 0.20
        }
    }
}

enum NightLightPresetKind: String, Codable, CaseIterable, Identifiable {
    case diaperChange
    case nursing
    case soothing
    case reading
    case checkIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diaperChange: "Diaper Change"
        case .nursing: "Nursing / Feed"
        case .soothing: "Soothing"
        case .reading: "Reading"
        case .checkIn: "Check-in"
        }
    }

    var slug: String {
        switch self {
        case .diaperChange: "diaper-change"
        case .nursing: "nursing"
        case .soothing: "soothing"
        case .reading: "reading"
        case .checkIn: "check-in"
        }
    }

    init?(slug: String) {
        guard let value = Self.allCases.first(where: { $0.slug == slug }) else {
            return nil
        }
        self = value
    }
}

struct NightLightSettings: Codable, Equatable {
    var id = UUID()
    var selectedColor: NightLightColor = .softRed
    var customColorHex = "#C8211B"
    var selectedPreset: NightLightPresetKind?
    var brightness = 0.16
    var softness = 0.82
    var extraSoft = true
    var selectedShape: NightLightShape = .fullScreenGlow
    var shapeScale = 1.0
    var shapeOffsetX = 0.0
    var shapeOffsetY = 0.0
    var breathingAnimationEnabled = true
    var breathingSpeed: NightLightBreathingSpeed = .slow
    var breathingIntensity: NightLightBreathingIntensity = .subtle
    var glowMode: NightLightGlowMode = .steady
    var selectedSound: NightLightSound = .none
    var soundVolume = 0.22
    var sleepTimerMinutes: Int? = 10
    var keepScreenAwake = true
    var lastUsedAt: Date?
    var createdAt = Date()
    var updatedAt = Date()

    var resolvedColor: Color {
        selectedColor == .custom
            ? Color(hex: customColorHex) ?? NightLightColor.softRed.color
            : selectedColor.color
    }
}

struct NightLightPreset: Identifiable, Equatable {
    var id: NightLightPresetKind
    var name: String
    var subtitle: String
    var color: NightLightColor
    var brightness: Double
    var softness: Double
    var shape: NightLightShape
    var breathingEnabled: Bool
    var glowMode: NightLightGlowMode
    var sound: NightLightSound
    var volume: Double
    var timerMinutes: Int
    var systemImage: String
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(cleaned, radix: 16) else { return nil }
        let red: Double
        let green: Double
        let blue: Double
        switch cleaned.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self = Color(red: red, green: green, blue: blue)
    }
}
