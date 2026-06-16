import Foundation
import SwiftData

@MainActor
enum IntegrationCommandProcessor {
    static func process(_ url: URL, container: ModelContainer) async -> Bool {
        guard let command = timerCommand(from: url) else { return false }

        let context = container.mainContext
        let profiles = (try? context.fetch(FetchDescriptor<BabyProfile>())) ?? []
        let profile: BabyProfile?
        if let profileID = command.profileID {
            ProfileService.shared.switchProfile(id: profileID, profiles: profiles)
            profile = ProfileService.shared.selectedProfile(in: profiles)
        } else {
            profile = ProfileService.shared.ensureSelection(in: profiles)
        }
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { event in
                event.startDate >= recentCutoff || event.endDate == nil
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        let events = ((try? context.fetch(eventDescriptor)) ?? [])
            .filter { $0.matchesProfile(profile?.id) }
        let event: BabyEvent?
        switch command.action {
        case .stopActive:
            event = EventTimerService.primaryActiveEvent(in: events)
        case .stop(let id), .resume(let id), .switchSide(let id):
            event = events.first { $0.id == id && $0.isTimerDraft }
        }
        guard let event else { return true }

        switch command.action {
        case .stopActive, .stop:
            EventTimerService.stop(event, context: context)
        case .resume:
            EventTimerService.resume(event, context: context)
        case .switchSide:
            EventTimerService.switchNursingSide(event, context: context)
        }

        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.actualSleepEventID == nil || record.generatedAt >= recentCutoff
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        let records = ((try? context.fetch(recordDescriptor)) ?? [])
            .filter { $0.matchesProfile(profile?.id) }
        let defaults = UserDefaults.standard
        await EventMutationService.eventDidChange(
            event,
            profile: profile,
            events: events,
            records: records,
            context: context,
            settings: PredictionSettings(
                feedAdjustmentEnabled: defaultBool(
                    "feedAdjustmentEnabled",
                    fallback: true,
                    defaults: defaults
                ),
                nursingAdjustmentEnabled: defaultBool(
                    "nursingAdjustmentEnabled",
                    fallback: true,
                    defaults: defaults
                ),
                bedtimePredictionEnabled: defaultBool(
                    "bedtimePredictionEnabled",
                    fallback: true,
                    defaults: defaults
                ),
                customBaselineMinimum: positiveDouble(
                    "customWakeMinimum",
                    defaults: defaults
                ),
                customBaselineMaximum: positiveDouble(
                    "customWakeMaximum",
                    defaults: defaults
                )
            ),
            notificationsEnabled: defaultBool(
                "predictionNotificationsEnabled",
                fallback: false,
                defaults: defaults
            ),
            notificationLeadMinutes: defaults.object(forKey: "notificationLeadMinutes") == nil
                ? 10
                : defaults.integer(forKey: "notificationLeadMinutes"),
            refreshPrediction: command.action.shouldRefreshPrediction,
            waitForSystemIntegrations: true
        )
        return true
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

    private static func defaultBool(
        _ key: String,
        fallback: Bool,
        defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func positiveDouble(
        _ key: String,
        defaults: UserDefaults
    ) -> Double? {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    private enum TimerAction {
        case stopActive
        case stop(UUID)
        case resume(UUID)
        case switchSide(UUID)

        var shouldRefreshPrediction: Bool {
            switch self {
            case .stopActive, .stop, .resume, .switchSide: false
            }
        }
    }

    private struct TimerCommand {
        var action: TimerAction
        var profileID: UUID?
    }
}
