import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    func synchronize(profile: BabyProfile?, events: [BabyEvent]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        let activeEvents = events.filter(\.isTimerRunning)
        guard let primary = EventTimerService.primaryActiveEvent(in: activeEvents) else {
            await endAll()
            return
        }

        let timer = WidgetSnapshotService.activeSnapshot(
            event: primary,
            babyName: profile?.name ?? "Ethan",
            additionalActiveCount: max(0, activeEvents.count - 1)
        )
        let content = ActivityContent(
            state: LittleWindowsActivityAttributes.ContentState(timer: timer),
            staleDate: nil
        )
        let matching = Activity<LittleWindowsActivityAttributes>.activities.first {
            $0.content.state.timer.id == primary.id
        }

        if let matching {
            await matching.update(content)
            for activity in Activity<LittleWindowsActivityAttributes>.activities where activity.id != matching.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            await endAll()
            do {
                _ = try Activity.request(
                    attributes: LittleWindowsActivityAttributes(
                        babyName: timer.babyName,
                        profileID: timer.profileID,
                        profileName: timer.profileName
                    ),
                    content: content,
                    pushType: nil
                )
            } catch {
                // Timers remain fully functional when Live Activities are unavailable.
            }
        }
    }

    func endAll() async {
        for activity in Activity<LittleWindowsActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
