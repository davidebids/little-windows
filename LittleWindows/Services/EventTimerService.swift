import Foundation
import SwiftData

@MainActor
enum EventTimerService {
    static let priority: [EventType] = [
        .sleep,
        .nursing,
        .feed,
        .activity,
        .walk,
        .training,
        .rest,
        .custom
    ]

    static func start(
        type: EventType,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        activityType: ActivityType? = nil,
        caregiverName: String?,
        events: [BabyEvent],
        context: ModelContext,
        profileID: UUID? = nil,
        profileType: CareProfileType? = nil,
        at date: Date = Date()
    ) -> BabyEvent? {
        guard type.supportsTimer else { return nil }
        guard !events.contains(where: { $0.type == type && $0.isTimerDraft }) else { return nil }

        let event = BabyEvent(
            profileID: profileID,
            type: type,
            startDate: date,
            caregiverName: caregiverName
        )
        event.createdAt = date
        event.updatedAt = date
        event.profileTypeSnapshot = profileType
        event.sleepKind = sleepKind
        event.nursingSide = nursingSide
        event.activeNursingSide = nursingSide
        event.timerState = .running
        event.timerAccumulatedSeconds = 0
        event.activeTimerSegmentStartDate = date
        event.activityType = type == .activity ? activityType : nil
        context.insert(event)
        return event
    }

    static func stop(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        guard event.isTimerRunning else { return }
        accrueCurrentSegment(event, until: date)
        event.timerState = .stopped
        event.activeTimerSegmentStartDate = nil
        event.updatedAt = date
    }

    static func resume(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        guard event.isTimerDraft, !event.isTimerRunning else { return }
        event.timerState = .running
        event.activeTimerSegmentStartDate = date
        event.updatedAt = date
    }

    static func reset(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        guard event.isTimerDraft else { return }
        event.startDate = date
        event.timerAccumulatedSeconds = 0
        event.leftDurationSeconds = event.type == .nursing ? 0 : nil
        event.rightDurationSeconds = event.type == .nursing ? 0 : nil
        event.activeTimerSegmentStartDate = event.isTimerRunning ? date : nil
        event.updatedAt = date
    }

    static func save(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date(),
        endDate: Date? = nil
    ) {
        guard event.isTimerDraft else { return }
        if event.isTimerRunning {
            accrueCurrentSegment(event, until: date)
        }
        let elapsed = max(0, event.timerAccumulatedSeconds ?? 0)
        if let endDate {
            event.endDate = max(endDate, event.startDate)
        } else {
            event.endDate = event.startDate.addingTimeInterval(elapsed)
        }
        event.timerState = nil
        event.timerAccumulatedSeconds = nil
        event.activeTimerSegmentStartDate = nil
        event.activeNursingSide = nil
        event.updatedAt = date
    }

    static func switchNursingSide(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        guard event.type == .nursing, event.isTimerDraft else { return }
        let currentSide = event.activeNursingSide ?? event.nursingSide ?? .left
        setNursingSide(
            event,
            to: currentSide == .left ? .right : .left,
            context: context,
            at: date
        )
    }

    static func setNursingSide(
        _ event: BabyEvent,
        to side: NursingSide,
        context: ModelContext,
        at date: Date = Date()
    ) {
        guard event.type == .nursing, event.isTimerDraft else { return }
        if event.isTimerRunning {
            accrueCurrentSegment(event, until: date)
            event.activeTimerSegmentStartDate = date
        }
        event.nursingSide = side
        event.activeNursingSide = side
        event.updatedAt = date
    }

    @discardableResult
    static func adjustStartDate(
        _ event: BabyEvent,
        to requestedDate: Date,
        at now: Date = Date()
    ) -> Date {
        guard event.isTimerDraft else { return event.startDate }

        let oldStart = event.startDate
        let newStart = min(requestedDate, now)
        guard abs(newStart.timeIntervalSince(oldStart)) > 0.5 else {
            return oldStart
        }

        if event.type == .nursing {
            adjustActiveNursingDuration(
                event,
                oldStart: oldStart,
                newStart: newStart
            )
        }
        if event.isTimerRunning,
           abs((event.activeTimerSegmentStartDate ?? oldStart).timeIntervalSince(oldStart)) < 1 {
            event.activeTimerSegmentStartDate = newStart
        } else {
            let adjustment = oldStart.timeIntervalSince(newStart)
            event.timerAccumulatedSeconds = max(
                0,
                (event.timerAccumulatedSeconds ?? 0) + adjustment
            )
        }
        event.startDate = newStart
        event.updatedAt = now
        return newStart
    }

    static func primaryActiveEvent(in events: [BabyEvent]) -> BabyEvent? {
        events
            .filter { $0.isTimerRunning && priority.contains($0.type) }
            .sorted { left, right in
                let leftPriority = priority.firstIndex(of: left.type) ?? priority.count
                let rightPriority = priority.firstIndex(of: right.type) ?? priority.count
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                return left.startDate < right.startDate
            }
            .first
    }

    private static func accrueCurrentSegment(_ event: BabyEvent, until date: Date) {
        let reference = event.activeTimerSegmentStartDate ?? event.startDate
        let elapsed = max(0, date.timeIntervalSince(reference))
        event.timerAccumulatedSeconds = (event.timerAccumulatedSeconds ?? 0) + elapsed
        guard event.type == .nursing else { return }
        switch event.activeNursingSide {
        case .left:
            event.leftDurationSeconds = (event.leftDurationSeconds ?? 0) + elapsed
        case .right:
            event.rightDurationSeconds = (event.rightDurationSeconds ?? 0) + elapsed
        case .none:
            break
        }
    }

    private static func adjustActiveNursingDuration(
        _ event: BabyEvent,
        oldStart: Date,
        newStart: Date
    ) {
        let segmentStart = event.activeTimerSegmentStartDate ?? oldStart
        if event.isTimerRunning,
           abs(segmentStart.timeIntervalSince(oldStart)) < 1 {
            return
        }

        let adjustment = oldStart.timeIntervalSince(newStart)
        guard let side = event.activeNursingSide else { return }
        switch side {
        case .left:
            event.leftDurationSeconds = max(
                0,
                (event.leftDurationSeconds ?? 0) + adjustment
            )
        case .right:
            event.rightDurationSeconds = max(
                0,
                (event.rightDurationSeconds ?? 0) + adjustment
            )
        }
    }
}
