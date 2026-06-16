import Foundation

@MainActor
final class NightLightTimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var fadeMultiplier = 1.0

    private var timer: Timer?
    private var endDate: Date?
    private var totalDuration: TimeInterval = 0
    var onFinished: (() -> Void)?

    deinit {
        timer?.invalidate()
    }

    func start(minutes: Int) {
        cancel()
        totalDuration = TimeInterval(max(1, minutes) * 60)
        remaining = totalDuration
        endDate = Date().addingTimeInterval(totalDuration)
        isRunning = true
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remaining = 0
        isRunning = false
        fadeMultiplier = 1
    }

    var remainingText: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func fadeMultiplier(
        remaining: TimeInterval,
        totalDuration: TimeInterval
    ) -> Double {
        let fadeDuration = min(60, max(15, totalDuration * 0.12))
        return remaining < fadeDuration
            ? max(0, remaining / fadeDuration)
            : 1
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        fadeMultiplier = Self.fadeMultiplier(
            remaining: remaining,
            totalDuration: totalDuration
        )
        guard remaining <= 0 else { return }
        cancel()
        onFinished?()
    }
}
