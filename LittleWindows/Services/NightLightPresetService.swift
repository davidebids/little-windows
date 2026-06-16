import Foundation

enum NightLightPresetService {
    static let presets: [NightLightPreset] = [
        NightLightPreset(
            id: .diaperChange,
            name: "Diaper Change",
            subtitle: "Dim red, 10 min",
            color: .softRed,
            brightness: 0.14,
            softness: 0.88,
            shape: .fullScreenGlow,
            breathingEnabled: false,
            glowMode: .steady,
            sound: .none,
            volume: 0.18,
            timerMinutes: 10,
            systemImage: "drop.fill"
        ),
        NightLightPreset(
            id: .nursing,
            name: "Nursing / Feed",
            subtitle: "Warm amber, 20 min",
            color: .warmAmber,
            brightness: 0.22,
            softness: 0.82,
            shape: .gradientOrb,
            breathingEnabled: false,
            glowMode: .steady,
            sound: .heartbeat,
            volume: 0.16,
            timerMinutes: 20,
            systemImage: "heart.circle.fill"
        ),
        NightLightPreset(
            id: .soothing,
            name: "Soothing",
            subtitle: "Candle breath, 30 min",
            color: .candlelight,
            brightness: 0.16,
            softness: 0.9,
            shape: .halo,
            breathingEnabled: true,
            glowMode: .candle,
            sound: .whiteNoise,
            volume: 0.2,
            timerMinutes: 30,
            systemImage: "moon.stars.fill"
        ),
        NightLightPreset(
            id: .reading,
            name: "Reading",
            subtitle: "Warm white, 15 min",
            color: .warmWhite,
            brightness: 0.4,
            softness: 0.7,
            shape: .fullScreenGlow,
            breathingEnabled: false,
            glowMode: .steady,
            sound: .none,
            volume: 0.18,
            timerMinutes: 15,
            systemImage: "book.fill"
        ),
        NightLightPreset(
            id: .checkIn,
            name: "Check-in",
            subtitle: "Extra dim red, 5 min",
            color: .softRed,
            brightness: 0.08,
            softness: 0.94,
            shape: .circle,
            breathingEnabled: false,
            glowMode: .steady,
            sound: .none,
            volume: 0.12,
            timerMinutes: 5,
            systemImage: "eye.fill"
        )
    ]

    static func preset(for kind: NightLightPresetKind) -> NightLightPreset {
        presets.first { $0.id == kind } ?? presets[0]
    }

    static func apply(
        _ preset: NightLightPreset,
        to settings: inout NightLightSettings
    ) {
        settings.selectedPreset = preset.id
        settings.selectedColor = preset.color
        settings.brightness = preset.brightness
        settings.softness = preset.softness
        settings.selectedShape = preset.shape
        settings.breathingAnimationEnabled = preset.breathingEnabled
        settings.glowMode = preset.glowMode
        settings.selectedSound = preset.sound
        settings.soundVolume = preset.volume
        settings.sleepTimerMinutes = preset.timerMinutes
        settings.extraSoft = preset.id == .diaperChange || preset.id == .checkIn
        settings.updatedAt = Date()
    }
}
