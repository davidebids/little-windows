import Foundation
import SwiftData

@MainActor
enum IntegrationCommandProcessor {
    static func process(_ url: URL, container: ModelContainer) async -> Bool {
        guard let command = timerCommand(from: url) else { return false }
        guard let requestedAt = IntegrationCommandStore.requestedAt(
            forTimerMutationURL: url
        ) else {
            // Recognize but discard an expired or malformed timer mutation.
            return true
        }

        let context = container.mainContext
        switchToCommandProfileIfNeeded(command.profileID, context: context)
        guard let storedEvent = fetchEvent(for: command, context: context) else { return true }
        guard shouldApply(command.action, to: storedEvent, requestedAt: requestedAt) else {
            return true
        }
        let event = EventMutationService.detachedTimerCopy(storedEvent)

        switch command.action {
        case .stopActive, .stop:
            EventTimerService.stop(event, context: context, at: requestedAt)
        case .resume:
            EventTimerService.resume(event, context: context, at: requestedAt)
        case .switchSide:
            EventTimerService.switchNursingSide(event, context: context, at: requestedAt)
        }
        let persistenceRequest = EventMutationService.timerPersistenceRequest(for: event)
        guard await EventMutationService.persistTimerMutation(
            persistenceRequest,
            container: container
        ) else { return true }

        // The isolated writer owns the durable commit, but SwiftData does not
        // automatically merge that actor's values into an object already
        // registered in the SwiftUI main context. Mirror the committed timer
        // fields into that existing object so Today and any foreground
        // reconciliation cannot keep publishing the pre-command running state.
        // No second main-actor save is needed; the authoritative write above is
        // already complete.
        CareEventPersistenceSnapshot(event: event).apply(to: storedEvent)

        let profile = fetchProfile(id: event.profileID, context: context)
        let timer = WidgetSnapshotService.refreshActiveTimer(
            event,
            profile: profile,
            at: requestedAt
        )
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] == nil,
           environment["XCTestBundlePath"] == nil {
            // `requestedAt` is the timer's effective stop/resume time, but the
            // persisted command becomes authoritative now. A foreground
            // reconciliation may have generated a newer wall-clock snapshot
            // from the old running state while the app was waking; ordering the
            // surface update by the old tap time would incorrectly reject this
            // successfully committed mutation.
            await LiveActivityManager.shared.updateTimer(timer, revision: Date())
            WatchConnectivityService.shared.scheduleCurrentStatePublish()
        }
        return true
    }

    private static func fetchProfile(
        id profileID: UUID?,
        context: ModelContext
    ) -> CareProfile? {
        guard let profileID else { return nil }
        var descriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate { $0.id == profileID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchEvent(
        for command: TimerCommand,
        context: ModelContext
    ) -> CareEvent? {
        switch command.action {
        case .stopActive:
            var descriptor = FetchDescriptor<CareEvent>(
                predicate: #Predicate<CareEvent> { event in
                    event.endDate == nil
                },
                sortBy: [SortDescriptor(\CareEvent.startDate, order: .forward)]
            )
            descriptor.fetchLimit = 30
            let profileID = command.profileID ?? ProfileService.shared.selectedProfileID
            let events = ((try? context.fetch(descriptor)) ?? [])
            let scopedEvents = events.filter { $0.matchesProfile(profileID) }
            return EventTimerService.primaryActiveEvent(in: scopedEvents)
                ?? (command.profileID == nil
                    ? EventTimerService.primaryActiveEvent(in: events)
                    : nil)
        case .stop(let id), .resume(let id), .switchSide(let id):
            var descriptor = FetchDescriptor<CareEvent>(
                predicate: #Predicate<CareEvent> { event in
                    event.id == id
                }
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first
        }
    }

    private static func shouldApply(
        _ action: TimerAction,
        to event: CareEvent,
        requestedAt: Date
    ) -> Bool {
        switch action {
        case .stopActive, .stop:
            guard event.isTimerRunning else { return false }
            // General event metadata can change while the app is waking or
            // importing CloudKit data. Only a timer segment that began after
            // this command proves that the user resumed/restarted the timer
            // after tapping Stop.
            let activeSegmentStart = event.activeTimerSegmentStartDate
                ?? event.startDate
            return activeSegmentStart <= requestedAt.addingTimeInterval(0.75)
        case .resume:
            // A delayed Resume must not undo a newer in-app Stop.
            return event.isTimerDraft
                && !event.isTimerRunning
                && event.updatedAt <= requestedAt.addingTimeInterval(0.75)
        case .switchSide:
            // A delayed side switch must not overtake a newer nursing edit.
            return event.type == .nursing
                && event.isTimerDraft
                && event.updatedAt <= requestedAt.addingTimeInterval(0.75)
        }
    }

    private static func switchToCommandProfileIfNeeded(
        _ profileID: UUID?,
        context: ModelContext
    ) {
        guard let profileID else { return }
        var descriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate<CareProfile> { profile in
                profile.id == profileID
            }
        )
        descriptor.fetchLimit = 1
        if let profile = (try? context.fetch(descriptor))?.first,
           !profile.isArchived {
            ProfileService.shared.switchProfile(profile)
        }
    }

    private static func timerCommand(from url: URL) -> TimerCommand? {
        guard url.scheme == "littlewindows" else { return nil }
        var components = [url.host].compactMap { $0 }
            + url.pathComponents.filter { $0 != "/" }
        let profileID: UUID?
        if components.count >= 2,
           components[0] == "profile",
           let id = UUID(uuidString: components[1]) {
            profileID = id
            components.removeFirst(2)
        } else {
            profileID = nil
        }
        if components == ["action", "stop-active"] {
            return TimerCommand(action: .stopActive, profileID: profileID)
        }
        guard components.count == 3,
              components[0] == "action",
              let id = UUID(uuidString: components[2]) else {
            return nil
        }
        switch components[1] {
        case "stop": return TimerCommand(action: .stop(id), profileID: profileID)
        case "resume": return TimerCommand(action: .resume(id), profileID: profileID)
        case "switch-side": return TimerCommand(action: .switchSide(id), profileID: profileID)
        default: return nil
        }
    }

    private enum TimerAction {
        case stopActive
        case stop(UUID)
        case resume(UUID)
        case switchSide(UUID)
    }

    private struct TimerCommand {
        var action: TimerAction
        var profileID: UUID?
    }
}
