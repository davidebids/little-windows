import ActivityKit
import Foundation

struct LiveActivityReconciliationCandidate: Equatable, Sendable {
    var activityID: String
    var timerID: UUID
    var isReusable: Bool
}

enum LiveActivityReconciliationPlan: Equatable, Sendable {
    case end(activityIDs: [String])
    case preserve
    case update(activityID: String, obsoleteActivityIDs: [String])
    case requestReplacement(obsoleteActivityIDs: [String])

    static func make(
        timerID: UUID?,
        activitiesEnabled: Bool,
        candidates: [LiveActivityReconciliationCandidate]
    ) -> Self {
        guard let timerID else {
            return .end(activityIDs: candidates.map(\.activityID))
        }

        // `areActivitiesEnabled` answers whether the app may start Live
        // Activities. It is not evidence that an active timer ended. Preserve
        // any existing system surface when authorization is unavailable.
        guard activitiesEnabled else { return .preserve }

        if let matching = candidates.first(where: {
            $0.timerID == timerID && $0.isReusable
        }) {
            return .update(
                activityID: matching.activityID,
                obsoleteActivityIDs: candidates
                    .filter { $0.activityID != matching.activityID }
                    .map(\.activityID)
            )
        }

        return .requestReplacement(
            obsoleteActivityIDs: candidates.map(\.activityID)
        )
    }
}

final class LiveActivityManager: @unchecked Sendable {
    static let shared = LiveActivityManager()

    private let systemWriter = LiveActivitySystemWriter()

    private init() {}

    func updateTimer(
        _ timer: ActiveTimerSnapshot,
        revision: Date = Date()
    ) async {
        await systemWriter.synchronize(timer: timer, revision: revision)
    }

    @MainActor
    func synchronize(
        profile: CareProfile?,
        events: [CareEvent],
        revision: Date = Date()
    ) async {
        let timerDrafts = EventVisibilityStore.visibleEvents(in: events)
            .filter(\.isTimerDraft)
        guard let primary = EventTimerService.primaryActiveEvent(in: timerDrafts)
            ?? timerDrafts.max(by: { $0.updatedAt < $1.updatedAt }) else {
            await synchronize(timer: nil, revision: revision)
            return
        }

        let timer = WidgetSnapshotService.activeSnapshot(
            event: primary,
            babyName: profile?.name ?? "Baby",
            additionalActiveCount: max(0, timerDrafts.count - 1)
        )
        await synchronize(timer: timer, revision: revision)
    }

    /// Applies immutable timer state in mutation order. Slow notification or
    /// prediction work can complete after a newer timer mutation; its older
    /// snapshot must never recreate or resume a Live Activity the user already
    /// stopped or discarded.
    func synchronize(
        timer: ActiveTimerSnapshot?,
        revision: Date = Date()
    ) async {
        await systemWriter.synchronize(timer: timer, revision: revision)
    }

    func endAll(revision: Date = Date()) async {
        await systemWriter.synchronize(timer: nil, revision: revision)
    }
}

/// Serializes ActivityKit I/O away from SwiftUI's executor. `Activity.request`
/// and activity termination can take seconds while iOS coordinates the system
/// surface; running them on the main actor prevented the in-app timer and
/// scrolling from advancing during that interval.
private actor LiveActivitySystemWriter {
    private typealias TimerActivity = Activity<LittleWindowsActivityAttributes>

    private var latestAcceptedRevision: Date?
    // Swift actors are reentrant at every ActivityKit `await`. Keep an explicit
    // operation chain so an older end request cannot resume after a newer start
    // and remove the replacement Live Activity.
    private var operationTail: Task<Void, Never>?

    func synchronize(timer: ActiveTimerSnapshot?, revision: Date) async {
        if let latestAcceptedRevision, revision < latestAcceptedRevision {
            return
        }
        latestAcceptedRevision = revision
        await enqueue(timer: timer)
    }

    private func enqueue(timer: ActiveTimerSnapshot?) async {
        let precedingOperation = operationTail
        let operation = Task<Void, Never> { [weak self] in
            if let precedingOperation {
                await precedingOperation.value
            }
            guard let self else { return }
            await self.performSynchronization(timer: timer)
        }
        operationTail = operation
        await operation.value
    }

    private func performSynchronization(timer: ActiveTimerSnapshot?) async {
        let activities = TimerActivity.activities
        let candidates = activities.map {
            LiveActivityReconciliationCandidate(
                activityID: $0.id,
                timerID: $0.content.state.timer.id,
                isReusable: Self.isReusable($0.activityState)
            )
        }
        let plan = LiveActivityReconciliationPlan.make(
            timerID: timer?.id,
            activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled,
            candidates: candidates
        )

        switch plan {
        case .end(let activityIDs):
            await end(activityIDs: activityIDs, from: activities)
        case .preserve:
            return
        case .update(let activityID, let obsoleteActivityIDs):
            guard let timer,
                  let matching = activities.first(where: { $0.id == activityID }) else {
                return
            }
            if !matching.content.state.timer.isEquivalentLiveActivityState(to: timer) {
                await matching.update(content(for: timer))
            }
            // Preserve the valid match before cleaning up duplicates. This
            // prevents a transient request/update failure from blanking the
            // Lock Screen while the underlying timer is still active.
            await end(activityIDs: obsoleteActivityIDs, from: activities)
        case .requestReplacement(let obsoleteActivityIDs):
            guard let timer else { return }
            do {
                let replacement = try TimerActivity.request(
                    attributes: LittleWindowsActivityAttributes(
                        babyName: timer.babyName,
                        profileID: timer.profileID,
                        profileName: timer.profileName
                    ),
                    content: content(for: timer),
                    pushType: nil
                )
                // Only retire stale/obsolete activities after iOS has accepted
                // their replacement. If the request fails, the previous surface
                // remains available and a later foreground reconciliation can
                // retry without creating a blank interval.
                await end(
                    activityIDs: obsoleteActivityIDs.filter { $0 != replacement.id },
                    from: activities
                )
            } catch {
                // Timer state remains authoritative in SwiftData and the shared
                // widget snapshot. A later reconciliation retries creation.
            }
        }
    }

    private func content(
        for timer: ActiveTimerSnapshot
    ) -> ActivityContent<LittleWindowsActivityAttributes.ContentState> {
        let content = ActivityContent(
            state: LittleWindowsActivityAttributes.ContentState(timer: timer),
            staleDate: nil
        )
        return content
    }

    private func end(
        activityIDs: [String],
        from activities: [TimerActivity]
    ) async {
        let activityIDSet = Set(activityIDs)
        for activity in activities where activityIDSet.contains(activity.id) {
            if activity.activityState != .dismissed {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    nonisolated private static func isReusable(_ state: ActivityState) -> Bool {
        if #available(iOS 26.0, *), state == .pending {
            return true
        }
        return state == .active || state == .stale
    }
}
