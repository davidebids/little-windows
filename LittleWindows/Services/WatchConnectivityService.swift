import Foundation
import SwiftData
import WatchConnectivity

struct WatchConnectivityStatus: Equatable {
    var isSupported: Bool
    var isActivated: Bool
    var isPaired: Bool
    var isWatchAppInstalled: Bool
    var isReachable: Bool
    var lastConfirmedContactAt: Date?
    var lastStateQueuedAt: Date?
    var lastStateReceiptAt: Date?
    var isLatestStateConfirmed: Bool

    static let unavailable = WatchConnectivityStatus(
        isSupported: false,
        isActivated: false,
        isPaired: false,
        isWatchAppInstalled: false,
        isReachable: false,
        lastConfirmedContactAt: nil,
        lastStateQueuedAt: nil,
        lastStateReceiptAt: nil,
        isLatestStateConfirmed: false
    )
}

extension Notification.Name {
    static let watchConnectivityStatusDidChange = Notification.Name(
        "LittleWindows.watchConnectivityStatusDidChange"
    )
}

final class WatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchConnectivityService()

    private static let lastConfirmedContactAtKey = "watch.lastConfirmedContactAt"
    private static let lastStateQueuedAtKey = "watch.lastStateQueuedAt"
    private static let lastStateReceiptAtKey = "watch.lastStateReceiptAt"
    private static let lastQueuedRevisionKey = "watch.lastQueuedRevision"
    private static let lastConfirmedRevisionKey = "watch.lastConfirmedRevision"

    private let lock = NSLock()
    private var modelContainer: ModelContainer?
    private let publication = WatchStatePublicationCoordinator()
    private var stateBuildInFlight = false
    private var stateBuildPending = false
    private var pendingForce = false

    private override init() {
        super.init()
    }

    func install(container: ModelContainer) {
        lock.lock()
        modelContainer = container
        lock.unlock()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @discardableResult
    func publishCurrentState(force: Bool = false) async -> Bool {
        guard let container = installedContainer(), canPublishState else {
            notifyStatusDidChange()
            return false
        }
        return await Task.detached(priority: .userInitiated) { [self, container] in
            publish(WatchStateFactory.make(context: ModelContext(container)), force: force)
        }.value
    }

    /// Builds the Watch payload in its own SwiftData context. Automatic
    /// system-surface refreshes use this path so a paired Watch can never turn
    /// an event save, timer control, or Today scroll into a main-thread query.
    func scheduleCurrentStatePublish(force: Bool = false, onlyIfMissing: Bool = false) {
        guard let container = installedContainer(), canPublishState else {
            notifyStatusDidChange()
            return
        }
        let startsWorker = lock.withLock {
            if onlyIfMissing && stateBuildInFlight { return false }
            stateBuildPending = true
            pendingForce = pendingForce || force
            guard !stateBuildInFlight else { return false }
            stateBuildInFlight = true
            return true
        }
        guard startsWorker else { return }
        Task.detached(priority: .utility) { [weak self, container] in
            guard let self else { return }
            while true {
                let force = self.lock.withLock {
                    self.stateBuildPending = false
                    let force = self.pendingForce
                    self.pendingForce = false
                    return force
                }
                let state = WatchStateFactory.make(context: ModelContext(container))
                _ = self.publish(state, force: force)
                let again = self.lock.withLock {
                    if self.stateBuildPending { return true }
                    self.stateBuildInFlight = false
                    return false
                }
                if !again { return }
            }
        }
    }

    /// Forecast phases and minute rain update only the weather portion. Care
    /// history is read once on activation, and again only for care changes.
    func publishWeather(_ weather: WeatherSurfaceState?) {
        guard canPublishState else { return }
        if !publication.publishWeather(weather, deliver: deliver) {
            scheduleCurrentStatePublish(onlyIfMissing: true)
        }
    }

    /// Avoid fetching and summarizing hundreds of records when there is no
    /// installed Watch app that can receive the result.
    private var canPublishState: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated
            && session.isPaired
            && session.isWatchAppInstalled
    }

    @discardableResult
    func publish(_ state: WatchCompanionState, force: Bool = false) -> Bool {
        guard canPublishState else {
            notifyStatusDidChange()
            return false
        }
        return publication.publish(state, force: force, deliver: deliver)
    }

    private func deliver(_ state: WatchCompanionState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        do {
            try WCSession.default.updateApplicationContext([
                WatchCompanionProtocol.stateMessageKey: data
            ])
            recordStateQueued(state)
            return true
        } catch {
            notifyStatusDidChange()
            return false
        }
    }

    func statusSnapshot() -> WatchConnectivityStatus {
        guard WCSession.isSupported() else { return .unavailable }
        let defaults = Self.statusDefaults
        let legacyDefaults = UserDefaults.standard
        let queuedRevision = defaults.string(forKey: Self.lastQueuedRevisionKey)
            ?? legacyDefaults.string(forKey: Self.lastQueuedRevisionKey)
        let confirmedRevision = defaults.string(forKey: Self.lastConfirmedRevisionKey)
            ?? legacyDefaults.string(forKey: Self.lastConfirmedRevisionKey)
        let session = WCSession.default
        return WatchConnectivityStatus(
            isSupported: true,
            isActivated: session.activationState == .activated,
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable,
            lastConfirmedContactAt: defaults.object(
                forKey: Self.lastConfirmedContactAtKey
            ) as? Date ?? legacyDefaults.object(
                forKey: Self.lastConfirmedContactAtKey
            ) as? Date,
            lastStateQueuedAt: defaults.object(
                forKey: Self.lastStateQueuedAtKey
            ) as? Date ?? legacyDefaults.object(
                forKey: Self.lastStateQueuedAtKey
            ) as? Date,
            lastStateReceiptAt: defaults.object(
                forKey: Self.lastStateReceiptAtKey
            ) as? Date ?? legacyDefaults.object(
                forKey: Self.lastStateReceiptAtKey
            ) as? Date,
            isLatestStateConfirmed: queuedRevision != nil
                && queuedRevision == confirmedRevision
        )
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        notifyStatusDidChange()
        guard activationState == .activated, error == nil else { return }
        scheduleCurrentStatePublish()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        notifyStatusDidChange()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        notifyStatusDidChange()
        scheduleCurrentStatePublish(force: true)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        notifyStatusDidChange()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message[WatchCompanionProtocol.stateRequestMessageKey] as? Bool == true {
            recordWatchContact()
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    replyHandler([:])
                    return
                }
                guard let container = installedContainer() else {
                    replyHandler([:])
                    return
                }
                // Reply from cache promptly; a slow weather request must not hold
                // up the Watch's care state or exceed its message reply window.
                let state = WatchStateFactory.make(context: ModelContext(container))
                publish(state, force: true)
                let data = try? JSONEncoder().encode(publication.currentState ?? state)
                replyHandler(data.map {
                    [WatchCompanionProtocol.stateMessageKey: $0]
                } ?? [:])
                // A successful refresh publishes a newer payload separately.
                // Never acquire a background location fix or request permission.
                await DailyWeatherStore.shared.refresh(minuteSensitive: true, resolveCurrentLocation: false)
            }
            return
        }
        guard let command = decodeCommand(message) else {
            replyHandler([:])
            return
        }
        recordWatchContact()
        Task { @MainActor in
            let acknowledgement = await process(command)
            let data = try? JSONEncoder().encode(acknowledgement)
            replyHandler(data.map {
                [WatchCompanionProtocol.acknowledgementMessageKey: $0]
            } ?? [:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = decodeCommand(userInfo) else { return }
        recordWatchContact()
        Task { @MainActor in
            let acknowledgement = await process(command)
            guard let data = try? JSONEncoder().encode(acknowledgement),
                  session.isWatchAppInstalled else {
                return
            }
            session.transferUserInfo([
                WatchCompanionProtocol.acknowledgementMessageKey: data
            ])
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[
            WatchCompanionProtocol.stateReceiptMessageKey
        ] as? Data,
              let receipt = try? JSONDecoder().decode(WatchStateReceipt.self, from: data),
              receipt.schemaVersion == WatchCompanionProtocol.schemaVersion else {
            return
        }
        recordStateReceipt(receipt)
    }

    @MainActor
    private func process(_ command: WatchCommand) async -> WatchAcknowledgement {
        guard let container = installedContainer() else {
            return WatchAcknowledgement(
                schemaVersion: WatchCompanionProtocol.schemaVersion,
                commandID: command.id,
                status: .rejected,
                message: "Little Windows is still opening its data store.",
                state: nil
            )
        }
        let acknowledgement = await WatchCommandProcessor.process(
            command,
            container: container
        )
        if let state = acknowledgement.state {
            publish(state, force: true)
        }
        return acknowledgement
    }

    private func decodeCommand(_ message: [String: Any]) -> WatchCommand? {
        guard let data = message[WatchCompanionProtocol.commandMessageKey] as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(WatchCommand.self, from: data)
    }

    private func installedContainer() -> ModelContainer? {
        lock.lock()
        defer { lock.unlock() }
        return modelContainer
    }

    private func recordStateQueued(_ state: WatchCompanionState) {
        let defaults = Self.statusDefaults
        defaults.set(Date(), forKey: Self.lastStateQueuedAtKey)
        defaults.set(state.revision.uuidString, forKey: Self.lastQueuedRevisionKey)
        notifyStatusDidChange()
    }

    private func recordWatchContact(at date: Date = Date()) {
        Self.statusDefaults.set(date, forKey: Self.lastConfirmedContactAtKey)
        notifyStatusDidChange()
    }

    private func recordStateReceipt(_ receipt: WatchStateReceipt) {
        let receivedAt = Date()
        let defaults = Self.statusDefaults
        defaults.set(receivedAt, forKey: Self.lastConfirmedContactAtKey)
        defaults.set(receivedAt, forKey: Self.lastStateReceiptAtKey)
        defaults.set(
            receipt.stateRevision.uuidString,
            forKey: Self.lastConfirmedRevisionKey
        )
        notifyStatusDidChange()
    }

    private static var statusDefaults: UserDefaults {
        PersistenceService.operationalDefaults()
    }

    private func notifyStatusDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .watchConnectivityStatusDidChange,
                object: nil
            )
        }
    }
}

/// Serializes payload comparison and delivery. A late care build cannot restore
/// old weather or replace a newer care snapshot. Weather-only updates never
/// fetch SwiftData, and a disabled forecast remains cleared across care builds.
final class WatchStatePublicationCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var lastState: WatchCompanionState?
    private var lastCareGeneratedAt = Date.distantPast
    private var hasWeatherOverride = false
    private var latestWeather: WeatherSurfaceState?
    var currentState: WatchCompanionState? { lock.withLock { lastState } }

    @discardableResult
    func publish(_ state: WatchCompanionState, force: Bool = false, now: Date = Date(),
                 deliver: (WatchCompanionState) -> Bool) -> Bool {
        lock.withLock {
            guard state.generatedAt >= lastCareGeneratedAt else { return true }
            var next = state
            if hasWeatherOverride {
                next.weather = latestWeather?.watchSnapshot(profileID: state.selectedProfileID, now: now)
            }
            if let lastState, !force, next.hasSameContent(as: lastState) {
                lastCareGeneratedAt = state.generatedAt
                return true
            }
            guard deliver(next) else { return false }
            lastCareGeneratedAt = state.generatedAt
            lastState = next
            return true
        }
    }

    /// Returns false only when an initial care snapshot is needed.
    @discardableResult
    func publishWeather(_ weather: WeatherSurfaceState?, now: Date = Date(),
                        deliver: (WatchCompanionState) -> Bool) -> Bool {
        lock.withLock {
            hasWeatherOverride = true
            latestWeather = weather
            guard let previous = lastState else { return false }
            var next = previous
            next.weather = weather?.watchSnapshot(profileID: next.selectedProfileID, now: now)
            guard !next.hasSameContent(as: previous) else { return true }
            next.generatedAt = now
            next.revision = UUID()
            if deliver(next) { lastState = next }
            return true
        }
    }
}
