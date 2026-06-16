import Combine
import SwiftUI
import UIKit

@MainActor
final class NightLightViewModel: ObservableObject {
    @Published var settings: NightLightSettings
    @Published var isActive = false
    @Published var controlsVisible = true
    @Published var lightEnabled = true
    @Published private(set) var isSoundMuted = false
    @Published private(set) var previewingSound: NightLightSound?

    let audioService = NightLightAudioService()
    let timerService = NightLightTimerService()

    static let soundPreviewDuration: Duration = .seconds(10)

    private let storageKey = "nightLightSettingsV1"
    private let defaults: UserDefaults
    private var originalScreenBrightness: CGFloat?
    private var originalIdleTimerDisabled: Bool?
    private var hideControlsTask: Task<Void, Never>?
    private var soundPreviewTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(NightLightSettings.self, from: data) {
            var migrated = decoded
            if migrated.selectedShape == .custom {
                migrated.selectedShape = .fullScreenGlow
            }
            settings = migrated
        } else {
            settings = NightLightSettings()
        }
        timerService.onFinished = { [weak self] in
            self?.stop()
        }
        timerService.objectWillChange
            .merge(with: audioService.objectWillChange)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func start(preset kind: NightLightPresetKind? = nil) {
        if let kind {
            applyPreset(kind)
        }
        guard !isActive else { return }
        cancelSoundPreviewTimer()
        isActive = true
        lightEnabled = true
        isSoundMuted = false
        settings.lastUsedAt = Date()
        settings.updatedAt = Date()
        captureSystemState()
        applySystemState()
        if let minutes = settings.sleepTimerMinutes {
            timerService.start(minutes: minutes)
        }
        audioService.play(settings.selectedSound, volume: effectiveSoundVolume)
        persist()
        revealControls()
    }

    func stop() {
        cancelSoundPreviewTimer()
        guard isActive else {
            audioService.stop()
            timerService.cancel()
            return
        }
        isActive = false
        isSoundMuted = false
        hideControlsTask?.cancel()
        audioService.stop()
        timerService.cancel()
        restoreSystemState()
        persist()
    }

    func applyPreset(_ kind: NightLightPresetKind) {
        NightLightPresetService.apply(
            NightLightPresetService.preset(for: kind),
            to: &settings
        )
        settingsDidChange()
    }

    func selectSound(_ sound: NightLightSound) {
        settings.selectedSound = sound
        settings.selectedPreset = nil
        if sound == .none {
            isSoundMuted = false
        }
        settingsDidChange()

        guard !isActive else { return }
        if sound == .none {
            stopSoundPreview()
        } else {
            previewSound(sound)
        }
    }

    func toggleSoundPreview() {
        guard !isActive, settings.selectedSound != .none else { return }
        if previewingSound == settings.selectedSound {
            stopSoundPreview()
        } else {
            previewSound(settings.selectedSound)
        }
    }

    func stopSoundPreview() {
        guard !isActive else { return }
        cancelSoundPreviewTimer()
        audioService.stop()
    }

    func settingsDidChange() {
        settings.updatedAt = Date()
        persist()
        guard isActive else { return }
        applySystemState()
        audioService.play(settings.selectedSound, volume: effectiveSoundVolume)
        if settings.sleepTimerMinutes == nil {
            timerService.cancel()
        }
    }

    func updateSoundVolume(_ volume: Double) {
        settings.soundVolume = volume
        settings.updatedAt = Date()
        audioService.updateVolume(effectiveSoundVolume)
        persist()
    }

    func toggleSoundMuted() {
        guard settings.selectedSound != .none else { return }
        isSoundMuted.toggle()
        audioService.updateVolume(effectiveSoundVolume)
    }

    func startTimer(minutes: Int) {
        settings.sleepTimerMinutes = minutes
        timerService.start(minutes: minutes)
        persist()
    }

    func cancelTimer() {
        timerService.cancel()
    }

    func dimmer() {
        settings.brightness = max(0.03, settings.brightness - 0.05)
        settingsDidChange()
    }

    func brighter() {
        settings.brightness = min(0.8, settings.brightness + 0.05)
        settingsDidChange()
    }

    func revealControls() {
        controlsVisible = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                controlsVisible = false
            }
        }
    }

    func hideControls() {
        hideControlsTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            controlsVisible = false
        }
    }

    func toggleControls() {
        controlsVisible ? hideControls() : revealControls()
    }

    func resetShapeTransform() {
        settings.shapeScale = 1
        settings.shapeOffsetX = 0
        settings.shapeOffsetY = 0
        settingsDidChange()
    }

    var effectiveBrightness: Double {
        guard lightEnabled else { return 0 }
        let softnessMultiplier = settings.extraSoft ? 0.7 : 1
        return settings.brightness
            * softnessMultiplier
            * timerService.fadeMultiplier
    }

    var effectiveSoundVolume: Double {
        isSoundMuted ? 0 : settings.soundVolume
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func captureSystemState() {
        originalScreenBrightness = UIScreen.main.brightness
        originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    }

    private func applySystemState() {
        if settings.keepScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        UIScreen.main.brightness = CGFloat(
            min(0.72, max(0.04, settings.brightness * 0.9))
        )
    }

    private func restoreSystemState() {
        if let originalScreenBrightness {
            UIScreen.main.brightness = originalScreenBrightness
        }
        if let originalIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        }
        originalScreenBrightness = nil
        originalIdleTimerDisabled = nil
    }

    private func previewSound(_ sound: NightLightSound) {
        cancelSoundPreviewTimer()
        previewingSound = sound
        audioService.play(sound, volume: settings.soundVolume)
        soundPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: Self.soundPreviewDuration)
            guard !Task.isCancelled else { return }
            self?.stopSoundPreview()
        }
    }

    private func cancelSoundPreviewTimer() {
        soundPreviewTask?.cancel()
        soundPreviewTask = nil
        previewingSound = nil
    }
}
