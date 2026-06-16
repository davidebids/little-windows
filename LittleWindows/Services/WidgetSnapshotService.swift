import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func refresh(
        profile: BabyProfile?,
        events: [BabyEvent],
        prediction: SleepPrediction?
    ) {
        let snapshot = makeSnapshot(
            profileID: profile?.id,
            babyName: profile?.name ?? "Baby",
            events: events,
            prediction: prediction
        )
        write(snapshot)
    }

    static func makeSnapshot(
        profileID: UUID? = nil,
        babyName: String,
        events: [BabyEvent],
        prediction: SleepPrediction?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let timerDrafts = events.filter(\.isTimerDraft)
        let primary = EventTimerService.primaryActiveEvent(in: timerDrafts)
            ?? timerDrafts.sorted { $0.updatedAt > $1.updatedAt }.first
        let activeTimer = primary.map {
            activeSnapshot(
                event: $0,
                profileID: profileID ?? $0.profileID,
                babyName: babyName,
                additionalActiveCount: max(0, timerDrafts.count - 1),
                now: now
            )
        }
        let todayEvents = events.filter {
            !$0.isTimerDraft && calendar.isDate($0.startDate, inSameDayAs: now)
        }
        let daily = DailySummaryService.summary(for: todayEvents)
        let careSessions = groupedCareSessions(todayEvents).count

        return WidgetSnapshot(
            generatedAt: now,
            profileID: profileID,
            profileName: babyName,
            babyName: babyName,
            activeTimer: activeTimer,
            prediction: prediction.map {
                PredictionSnapshot(
                    profileID: profileID,
                    profileName: babyName,
                    kind: $0.predictionKind.displayName,
                    expectedStart: $0.predictedStart,
                    windowStart: $0.predictedWindowStart,
                    windowEnd: $0.predictedWindowEnd,
                    confidenceLabel: $0.confidenceLabel.displayName
                )
            },
            todaySummary: TodaySummarySnapshot(
                profileID: profileID,
                profileName: babyName,
                totalSleepSeconds: daily.totalSleep,
                napCount: daily.napCount,
                careSessionCount: careSessions,
                diaperCount: daily.wetDiapers + daily.dirtyDiapers + daily.bothDiapers
            )
        )
    }

    static func activeSnapshot(
        event: BabyEvent,
        profileID: UUID? = nil,
        babyName: String,
        additionalActiveCount: Int,
        now: Date = Date()
    ) -> ActiveTimerSnapshot {
        ActiveTimerSnapshot(
            id: event.id,
            profileID: profileID ?? event.profileID,
            profileName: babyName,
            babyName: babyName,
            typeRawValue: event.type.rawValue,
            eventLabel: runningLabel(for: event),
            systemImage: event.activityType?.systemImage ?? event.type.systemImage,
            startDate: event.timerDisplayStartDate(at: now),
            isRunning: event.isTimerRunning,
            elapsedSeconds: event.timerElapsed(at: now),
            caregiverName: event.caregiverName,
            activeNursingSideRawValue: event.activeNursingSide?.rawValue,
            leftDurationSeconds: event.leftDurationSeconds ?? 0,
            rightDurationSeconds: event.rightDurationSeconds ?? 0,
            additionalActiveCount: additionalActiveCount
        )
    }

    static func read() -> WidgetSnapshot {
        let url = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.widgetSnapshotFilename
        )
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private static func write(_ snapshot: WidgetSnapshot) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            let url = SystemIntegrationConstants.sharedFileURL(
                SystemIntegrationConstants.widgetSnapshotFilename
            )
            try? data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func groupedCareSessions(_ events: [BabyEvent]) -> [Date] {
        let dates = events.filter {
            $0.type == .feed || $0.type == .nursing
        }.map(\.startDate).sorted()
        var sessions = [Date]()
        for date in dates {
            if let last = sessions.last, date.timeIntervalSince(last) < 45 * 60 {
                continue
            }
            sessions.append(date)
        }
        return sessions
    }

    private static func runningLabel(for event: BabyEvent) -> String {
        switch event.type {
        case .sleep: "Sleeping"
        case .nursing: "Nursing"
        case .feed: "Feeding"
        case .activity: event.activityType?.displayName ?? "Activity"
        default: event.type.displayName
        }
    }
}
