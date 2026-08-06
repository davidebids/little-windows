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
    private var lastPublishedState: WatchCompanionState?

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

    @MainActor
    @discardableResult
    func publishCurrentState(force: Bool = false) -> Bool {
        guard let container = installedContainer() else { return false }
        return publish(
            WatchStateFactory.make(context: container.mainContext),
            force: force
        )
    }

    @discardableResult
    func publish(_ state: WatchCompanionState, force: Bool = false) -> Bool {
        guard WCSession.isSupported(),
            WCSession.default.activationState == .activated,
            WCSession.default.isPaired,
            WCSession.default.isWatchAppInstalled else {
            notifyStatusDidChange()
            return false
        }
        if !force,
           let lastPublishedState = publishedState(),
           state.hasSameContent(as: lastPublishedState) {
            return true
        }
        guard let data = try? JSONEncoder().encode(state) else { return false }
        do {
            try WCSession.default.updateApplicationContext([
                WatchCompanionProtocol.stateMessageKey: data
            ])
            setPublishedState(state)
            recordStateQueued(state)
            return true
        } catch {
            notifyStatusDidChange()
            return false
        }
    }

    func statusSnapshot() -> WatchConnectivityStatus {
        guard WCSession.isSupported() else { return .unavailable }
        let defaults = UserDefaults.standard
        let queuedRevision = defaults.string(forKey: Self.lastQueuedRevisionKey)
        let confirmedRevision = defaults.string(forKey: Self.lastConfirmedRevisionKey)
        let session = WCSession.default
        return WatchConnectivityStatus(
            isSupported: true,
            isActivated: session.activationState == .activated,
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable,
            lastConfirmedContactAt: defaults.object(
                forKey: Self.lastConfirmedContactAtKey
            ) as? Date,
            lastStateQueuedAt: defaults.object(
                forKey: Self.lastStateQueuedAtKey
            ) as? Date,
            lastStateReceiptAt: defaults.object(
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
        Task { @MainActor in
            publishCurrentState()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        notifyStatusDidChange()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        notifyStatusDidChange()
        Task { @MainActor in
            publishCurrentState(force: true)
        }
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
            Task { @MainActor in
                guard let container = installedContainer() else {
                    replyHandler([:])
                    return
                }
                let state = WatchStateFactory.make(context: container.mainContext)
                publish(state, force: true)
                let data = try? JSONEncoder().encode(state)
                replyHandler(data.map {
                    [WatchCompanionProtocol.stateMessageKey: $0]
                } ?? [:])
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

    private func publishedState() -> WatchCompanionState? {
        lock.lock()
        defer { lock.unlock() }
        return lastPublishedState
    }

    private func setPublishedState(_ state: WatchCompanionState) {
        lock.lock()
        lastPublishedState = state
        lock.unlock()
    }

    private func recordStateQueued(_ state: WatchCompanionState) {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: Self.lastStateQueuedAtKey)
        defaults.set(state.revision.uuidString, forKey: Self.lastQueuedRevisionKey)
        notifyStatusDidChange()
    }

    private func recordWatchContact(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Self.lastConfirmedContactAtKey)
        notifyStatusDidChange()
    }

    private func recordStateReceipt(_ receipt: WatchStateReceipt) {
        let receivedAt = Date()
        let defaults = UserDefaults.standard
        defaults.set(receivedAt, forKey: Self.lastConfirmedContactAtKey)
        defaults.set(receivedAt, forKey: Self.lastStateReceiptAtKey)
        defaults.set(
            receipt.stateRevision.uuidString,
            forKey: Self.lastConfirmedRevisionKey
        )
        notifyStatusDidChange()
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
