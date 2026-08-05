import Foundation
import WatchConnectivity
import WatchKit

@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject {
    static let shared = WatchConnectivityClient()

    @Published private(set) var state: WatchCompanionState
    @Published private(set) var pendingCommandIDs: Set<UUID>
    @Published private(set) var isReachable = false
    @Published var lastErrorMessage: String?

    private let session = WCSession.default
    private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var refreshInFlight = false
    private var directCommandInFlightID: UUID?
    private var lastAuthoritativeGeneratedAt = Date.distantPast
    private var lastReceiptRevision: UUID?

    private override init() {
        state = WatchSharedStorage.readState()
        pendingCommandIDs = Set(WatchSharedStorage.readOutbox().map(\.id))
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        isReachable = session.isReachable
    }

    func requestRefresh() {
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        if let data = session.receivedApplicationContext[
            WatchCompanionProtocol.stateMessageKey
        ] as? Data {
            applyStateData(data)
        }
        retryPendingCommands()
        guard session.isReachable, !refreshInFlight else { return }
        refreshInFlight = true
        session.sendMessage([
            WatchCompanionProtocol.stateRequestMessageKey: true
        ]) { [weak self] reply in
            Task { @MainActor in
                self?.refreshInFlight = false
                guard let data = reply[
                    WatchCompanionProtocol.stateMessageKey
                ] as? Data else { return }
                self?.applyStateData(data)
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.refreshInFlight = false
            }
        }
    }

    func selectProfile(_ profileID: UUID) {
        let command = WatchCommand(kind: .selectProfile, profileID: profileID)
        applyOptimistic(command, action: nil)
        submit(command)
    }

    @discardableResult
    func perform(
        _ action: WatchActionSnapshot,
        optionID: String? = nil,
        timerStartDate: Date? = nil
    ) -> Bool {
        guard let profileID = state.selectedProfileID else { return false }
        let eventID = UUID()
        let command = WatchCommand(
            kind: .performAction,
            profileID: profileID,
            eventID: eventID,
            actionID: action.id,
            optionID: optionID,
            timerStartDate: timerStartDate
        )
        applyOptimistic(command, action: action)
        submit(command)
        return true
    }

    func stopTimer(_ timerID: UUID, save: Bool) {
        guard let timer = state.activeTimers.first(where: { $0.id == timerID }) else {
            return
        }
        let command = WatchCommand(
            kind: save ? .stopAndSaveTimer : .stopTimer,
            profileID: timer.profileID,
            eventID: timer.id,
            expectedEventUpdatedAt: timer.updatedAt
        )
        applyOptimistic(command, action: nil)
        submit(command)
    }

    func resumeTimer(_ timerID: UUID) {
        guard let timer = state.activeTimers.first(where: { $0.id == timerID }) else {
            return
        }
        let command = WatchCommand(
            kind: .resumeTimer,
            profileID: timer.profileID,
            eventID: timer.id,
            expectedEventUpdatedAt: timer.updatedAt
        )
        applyOptimistic(command, action: nil)
        submit(command)
    }

    func discardTimer(_ timerID: UUID) {
        guard let timer = state.activeTimers.first(where: { $0.id == timerID }),
              !timer.isRunning else { return }
        let command = WatchCommand(
            kind: .discardTimer,
            profileID: timer.profileID,
            eventID: timer.id,
            expectedEventUpdatedAt: timer.updatedAt
        )
        applyOptimistic(command, action: nil)
        submit(command)
    }

    func selectNursingSide(_ sideRawValue: String, timerID: UUID) {
        guard let timer = state.activeTimers.first(where: { $0.id == timerID }),
              ["left", "right"].contains(sideRawValue),
              timer.activeNursingSideRawValue != sideRawValue else { return }
        let command = WatchCommand(
            kind: .switchNursingSide,
            profileID: timer.profileID,
            eventID: timer.id,
            optionID: sideRawValue,
            expectedEventUpdatedAt: timer.updatedAt
        )
        applyOptimistic(command, action: nil)
        submit(command)
    }

    func handle(_ tasks: Set<WKRefreshBackgroundTask>) {
        for task in tasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                backgroundTasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        session.activate()
        Task { @MainActor in
            for _ in 0..<20 where session.hasContentPending {
                try? await Task.sleep(for: .milliseconds(100))
            }
            completeBackgroundTasks()
        }
    }

    private func submit(_ command: WatchCommand) {
        WatchSharedStorage.enqueue(command)
        pendingCommandIDs.insert(command.id)
        retryPendingCommands()
    }

    private func sendDirect(_ command: WatchCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        let payload: [String: Any] = [
            WatchCompanionProtocol.commandMessageKey: data
        ]
        directCommandInFlightID = command.id
        session.sendMessage(payload) { [weak self] reply in
            guard let acknowledgementData = reply[
                WatchCompanionProtocol.acknowledgementMessageKey
            ] as? Data else {
                Task { @MainActor in
                    self?.handleDirectDeliveryFailure(
                        payload,
                        commandID: command.id
                    )
                }
                return
            }
            Task { @MainActor in
                self?.handleDirectAcknowledgement(
                    acknowledgementData,
                    payload: payload,
                    commandID: command.id
                )
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.handleDirectDeliveryFailure(payload, commandID: command.id)
            }
        }
    }

    private func handleDirectDeliveryFailure(
        _ payload: [String: Any],
        commandID: UUID
    ) {
        if directCommandInFlightID == commandID {
            directCommandInFlightID = nil
        }
        queueForBackgroundDelivery(payload)
        retryPendingCommands()
    }

    private func handleDirectAcknowledgement(
        _ data: Data,
        payload: [String: Any],
        commandID: UUID
    ) {
        guard let acknowledgement = try? JSONDecoder().decode(
            WatchAcknowledgement.self,
            from: data
        ), acknowledgement.commandID == commandID else {
            handleDirectDeliveryFailure(payload, commandID: commandID)
            return
        }
        applyAcknowledgement(acknowledgement)
    }

    private func queueForBackgroundDelivery(_ payload: [String: Any]) {
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        if let data = payload[WatchCompanionProtocol.commandMessageKey] as? Data,
           let command = try? JSONDecoder().decode(WatchCommand.self, from: data),
           backgroundTransferIsAlreadyQueued(command.id) {
            return
        }
        session.transferUserInfo(payload)
    }

    private func queueForBackgroundDelivery(_ commands: [WatchCommand]) {
        var queuedIDs = outstandingBackgroundCommandIDs()
        for command in commands where !queuedIDs.contains(command.id) {
            guard let data = try? JSONEncoder().encode(command) else { continue }
            session.transferUserInfo([
                WatchCompanionProtocol.commandMessageKey: data
            ])
            queuedIDs.insert(command.id)
        }
    }

    private func backgroundTransferIsAlreadyQueued(_ commandID: UUID) -> Bool {
        outstandingBackgroundCommandIDs().contains(commandID)
    }

    private func outstandingBackgroundCommandIDs() -> Set<UUID> {
        Set(session.outstandingUserInfoTransfers.compactMap { transfer in
            guard let data = transfer.userInfo[
                WatchCompanionProtocol.commandMessageKey
            ] as? Data,
            let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else {
                return nil
            }
            return command.id
        })
    }

    private func retryPendingCommands() {
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        let commands = WatchCommandDeliveryOrder.ordered(
            WatchSharedStorage.readOutbox()
        )
        guard !commands.isEmpty else { return }

        if !session.isReachable {
            queueForBackgroundDelivery(commands)
            return
        }

        let outstandingIDs = outstandingBackgroundCommandIDs()
        if let command = WatchCommandDeliveryOrder.nextDirectCommand(
            in: commands,
            outstandingBackgroundCommandIDs: outstandingIDs,
            directCommandInFlightID: directCommandInFlightID
        ) {
            sendDirect(command)
        } else if directCommandInFlightID == nil {
            // The oldest mutation is already using WatchConnectivity's ordered
            // background queue, so keep all later mutations on that same route.
            queueForBackgroundDelivery(commands)
        }
    }

    private func applyStateData(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchCompanionState.self, from: data),
              decoded.schemaVersion == WatchCompanionProtocol.schemaVersion else {
            return
        }
        if applyAuthoritativeState(decoded) {
            sendStateReceipt(for: decoded)
        }
    }

    private func applyState(_ updated: WatchCompanionState) {
        let contentChanged = !state.hasSameContent(as: updated)
        state = updated
        WatchSharedStorage.writeState(updated, reloadWidgets: contentChanged)
    }

    @discardableResult
    private func applyAuthoritativeState(_ updated: WatchCompanionState) -> Bool {
        guard updated.generatedAt.addingTimeInterval(1) >= lastAuthoritativeGeneratedAt else {
            return false
        }
        lastAuthoritativeGeneratedAt = max(
            lastAuthoritativeGeneratedAt,
            updated.generatedAt
        )
        let rebased = WatchCommandDeliveryOrder.ordered(
            WatchSharedStorage.readOutbox()
        )
            .reduce(updated) { current, command in
                optimisticState(
                    applying: command,
                    to: current,
                    action: action(for: command, in: current)
                )
            }
        applyState(rebased)
        return true
    }

    private func applyAcknowledgementData(_ data: Data) {
        guard let acknowledgement = try? JSONDecoder().decode(
            WatchAcknowledgement.self,
            from: data
        ) else {
            return
        }
        applyAcknowledgement(acknowledgement)
    }

    private func applyAcknowledgement(_ acknowledgement: WatchAcknowledgement) {
        if directCommandInFlightID == acknowledgement.commandID {
            directCommandInFlightID = nil
        }
        let wasPending = pendingCommandIDs.contains(acknowledgement.commandID)
        WatchSharedStorage.removeCommand(id: acknowledgement.commandID)
        pendingCommandIDs.remove(acknowledgement.commandID)
        if let acknowledgedState = acknowledgement.state {
            if applyAuthoritativeState(acknowledgedState) {
                sendStateReceipt(for: acknowledgedState)
            }
        }
        retryPendingCommands()
        guard wasPending else { return }
        switch acknowledgement.status {
        case .applied, .duplicate:
            WKInterfaceDevice.current().play(.success)
        case .rejected, .unsupported:
            lastErrorMessage = acknowledgement.message ?? "The action could not be applied."
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func applyOptimistic(
        _ command: WatchCommand,
        action: WatchActionSnapshot?
    ) {
        applyState(optimisticState(applying: command, to: state, action: action))
    }

    private func optimisticState(
        applying command: WatchCommand,
        to baseState: WatchCompanionState,
        action: WatchActionSnapshot?
    ) -> WatchCompanionState {
        var optimisticState = baseState
        optimisticState.generatedAt = command.issuedAt
        optimisticState.revision = UUID()
        switch command.kind {
        case .performAction:
            guard let action, timerActionIDs.contains(action.id),
                  let eventID = command.eventID else { break }
            let timerStartDate = command.timerStartDate ?? command.issuedAt
            let optionTitle = action.options.first { $0.id == command.optionID }?.title
            let timer = WatchTimerSnapshot(
                id: eventID,
                profileID: command.profileID,
                title: optionTitle.map { "\(action.title): \($0)" } ?? action.title,
                systemImage: action.systemImage,
                displayStartDate: timerStartDate,
                isRunning: true,
                elapsedSeconds: 0,
                activeNursingSideRawValue: action.id == "nursing" ? command.optionID : nil,
                leftDurationSeconds: 0,
                rightDurationSeconds: 0,
                updatedAt: command.issuedAt,
                elapsedReferenceDate: timerStartDate
            )
            optimisticState.activeTimers.removeAll { $0.id == eventID }
            optimisticState.activeTimers.insert(timer, at: 0)
            optimisticState.favoriteActions.removeAll {
                $0.startsTimer && $0.categoryRawValue == action.categoryRawValue
            }
            optimisticState.allActions.removeAll {
                $0.startsTimer && $0.categoryRawValue == action.categoryRawValue
            }
        case .stopTimer:
            if let eventID = command.eventID,
               let index = optimisticState.activeTimers.firstIndex(where: {
                   $0.id == eventID
               }) {
                var timer = optimisticState.activeTimers[index]
                timer.accrueLiveDurations(at: command.issuedAt)
                timer.isRunning = false
                timer.updatedAt = command.issuedAt
                optimisticState.activeTimers[index] = timer
            }
        case .stopAndSaveTimer, .discardTimer:
            if let eventID = command.eventID {
                optimisticState.activeTimers.removeAll { $0.id == eventID }
            }
        case .resumeTimer:
            if let eventID = command.eventID,
               let index = optimisticState.activeTimers.firstIndex(where: {
                   $0.id == eventID
               }) {
                var timer = optimisticState.activeTimers[index]
                timer.isRunning = true
                timer.updatedAt = command.issuedAt
                timer.elapsedReferenceDate = command.issuedAt
                optimisticState.activeTimers[index] = timer
            }
        case .switchNursingSide:
            if let eventID = command.eventID,
               let index = optimisticState.activeTimers.firstIndex(where: {
                   $0.id == eventID
               }) {
                var timer = optimisticState.activeTimers[index]
                timer.accrueLiveDurations(at: command.issuedAt)
                if let requestedSide = command.optionID,
                   ["left", "right"].contains(requestedSide) {
                    timer.activeNursingSideRawValue = requestedSide
                } else {
                    timer.activeNursingSideRawValue = timer.activeNursingSideRawValue == "left"
                        ? "right"
                        : "left"
                }
                timer.updatedAt = command.issuedAt
                optimisticState.activeTimers[index] = timer
            }
        case .selectProfile:
            optimisticState.selectedProfileID = command.profileID
            if let profile = optimisticState.profiles.first(where: {
                $0.id == command.profileID
            }) {
                let hiddenCategories = Set(profile.hiddenCategoryRawValues ?? [])
                let activeTimerCategories = Set(
                    profile.activeTimerCategoryRawValues ?? []
                )
                let actions = WatchActionCatalog.actions(
                    profileTypeRawValue: profile.profileTypeRawValue
                ).filter {
                    !hiddenCategories.contains($0.categoryRawValue)
                        && !($0.startsTimer
                            && activeTimerCategories.contains($0.categoryRawValue))
                }
                optimisticState.favoriteActions = Array(actions.prefix(6))
                optimisticState.allActions = actions
                optimisticState.activeTimers = []
                optimisticState.prediction = nil
                optimisticState.todayMetrics = []
            }
        }
        return optimisticState
    }

    private func action(
        for command: WatchCommand,
        in state: WatchCompanionState
    ) -> WatchActionSnapshot? {
        guard let actionID = command.actionID else { return nil }
        if let action = state.allActions.first(where: { $0.id == actionID })
            ?? state.favoriteActions.first(where: { $0.id == actionID }) {
            return action
        }
        guard let profile = state.profiles.first(where: { $0.id == command.profileID }) else {
            return nil
        }
        return WatchActionCatalog.actions(
            profileTypeRawValue: profile.profileTypeRawValue
        ).first { $0.id == actionID }
    }

    private func completeBackgroundTasks() {
        let tasks = backgroundTasks
        backgroundTasks.removeAll()
        tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
    }

    private func sendStateReceipt(for confirmedState: WatchCompanionState) {
        guard session.activationState == .activated,
              lastReceiptRevision != confirmedState.revision,
              let data = try? JSONEncoder().encode(WatchStateReceipt(
                schemaVersion: WatchCompanionProtocol.schemaVersion,
                stateRevision: confirmedState.revision,
                receivedAt: Date()
              )) else {
            return
        }
        do {
            try session.updateApplicationContext([
                WatchCompanionProtocol.stateReceiptMessageKey: data
            ])
            lastReceiptRevision = confirmedState.revision
        } catch {
            return
        }
    }

    private let timerActionIDs: Set<String> = [
        "sleep", "nursing", "pumping", "tummy-time", "story-time",
        "brush-teeth", "indoor-play", "outdoor-play", "screen-time", "bath",
        "walk", "rest", "training", "grooming"
    ]
}

extension WatchConnectivityClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isReachable = activationState == .activated && session.isReachable
            if activationState == .activated {
                requestRefresh()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            if session.isReachable { retryPendingCommands() }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[
            WatchCompanionProtocol.stateMessageKey
        ] as? Data else { return }
        Task { @MainActor in applyStateData(data) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        if let data = userInfo[WatchCompanionProtocol.acknowledgementMessageKey] as? Data {
            Task { @MainActor in applyAcknowledgementData(data) }
        } else if let data = userInfo[WatchCompanionProtocol.stateMessageKey] as? Data {
            Task { @MainActor in applyStateData(data) }
        }
    }
}
