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
        let event = fetchEvent(for: command, context: context)
        guard let event else { return true }
        guard shouldApply(command.action, to: event, requestedAt: requestedAt) else {
            return true
        }

        switch command.action {
        case .stopActive, .stop:
            EventTimerService.stop(event, context: context, at: requestedAt)
        case .resume:
            EventTimerService.resume(event, context: context, at: requestedAt)
        case .switchSide:
            EventTimerService.switchNursingSide(event, context: context, at: requestedAt)
        }
        guard PersistenceService.save(context: context) else { return true }

        let timer = WidgetSnapshotService.refreshActiveTimer(event, at: requestedAt)
        Task { @MainActor in
            await LiveActivityManager.shared.updateTimer(timer)
        }
        return true
    }

    private static func fetchEvent(
        for command: TimerCommand,
        context: ModelContext
    ) -> BabyEvent? {
        switch command.action {
        case .stopActive:
            var descriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { event in
                    event.endDate == nil
                },
                sortBy: [SortDescriptor(\BabyEvent.startDate, order: .forward)]
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
            var descriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { event in
                    event.id == id
                }
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first
        }
    }

    private static func shouldApply(
        _ action: TimerAction,
        to event: BabyEvent,
        requestedAt: Date
    ) -> Bool {
        // A delayed duplicate must not undo a newer in-app timer action.
        guard event.updatedAt <= requestedAt.addingTimeInterval(0.75) else {
            return false
        }
        switch action {
        case .stopActive, .stop:
            return event.isTimerRunning
        case .resume:
            return event.isTimerDraft && !event.isTimerRunning
        case .switchSide:
            return event.type == .nursing && event.isTimerDraft
        }
    }

    private static func switchToCommandProfileIfNeeded(
        _ profileID: UUID?,
        context: ModelContext
    ) {
        guard let profileID else { return }
        var descriptor = FetchDescriptor<BabyProfile>(
            predicate: #Predicate<BabyProfile> { profile in
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
