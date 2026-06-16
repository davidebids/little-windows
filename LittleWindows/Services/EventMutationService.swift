import Foundation
import SwiftData

@MainActor
enum EventMutationService {
    static func startTimer(
        type: EventType,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        activityType: ActivityType? = nil,
        caregiverName: String?,
        events: [BabyEvent],
        profileID: UUID? = nil,
        profileType: CareProfileType? = nil,
        context: ModelContext
    ) -> BabyEvent? {
        EventTimerService.start(
            type: type,
            nursingSide: nursingSide,
            sleepKind: sleepKind,
            activityType: activityType,
            caregiverName: caregiverName,
            events: events,
            context: context,
            profileID: profileID,
            profileType: profileType
        )
    }

    static func stopTimer(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.stop(event, context: context, at: date)
    }

    static func resumeTimer(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.resume(event, context: context, at: date)
    }

    static func resetTimer(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.reset(event, context: context, at: date)
    }

    static func saveTimer(
        _ event: BabyEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.save(event, context: context, at: date)
    }

    static func delete(
        _ event: BabyEvent,
        profile: BabyProfile?,
        events: [BabyEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int
    ) async {
        if event.type == .sleep {
            for record in records where record.actualSleepEventID == event.id {
                record.actualSleepEventID = nil
                record.actualSleepStart = nil
                record.errorMinutes = nil
                record.wasInsidePredictedWindow = nil
                record.updatedAt = Date()
            }
        }
        context.delete(event)
        let remainingEvents = events.filter { $0.id != event.id }
        let prediction = event.type.affectsSleepPrediction
            ? replacePrediction(
                profile: profile,
                events: remainingEvents,
                records: records,
                context: context,
                settings: settings
            )
            : currentPrediction(in: records)
        try? context.save()
        PersistenceService.recordLocalSave()
        Task { @MainActor in
            await refreshSystemIntegrations(
                profile: profile,
                events: remainingEvents,
                prediction: prediction,
                scheduleNotification: event.type.affectsSleepPrediction,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes
            )
        }
    }

    static func eventDidChange(
        _ event: BabyEvent,
        profile: BabyProfile?,
        events: [BabyEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false
    ) async {
        event.updatedAt = Date()
        if event.type == .sleep, !event.isTimerDraft {
            PredictionTuningService.resolveLatestPrediction(with: event, records: records)
        }
        let shouldRefreshPrediction = refreshPrediction && event.type.affectsSleepPrediction
        let prediction = shouldRefreshPrediction
            ? replacePrediction(
                profile: profile,
                events: events,
                records: records,
                context: context,
                settings: settings
            )
            : currentPrediction(in: records)
        try? context.save()
        PersistenceService.recordLocalSave()
        if waitForSystemIntegrations {
            await refreshSystemIntegrations(
                profile: profile,
                events: events,
                prediction: prediction,
                scheduleNotification: shouldRefreshPrediction,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes
            )
        } else {
            Task { @MainActor in
                await refreshSystemIntegrations(
                    profile: profile,
                    events: events,
                    prediction: prediction,
                    scheduleNotification: shouldRefreshPrediction,
                    notificationsEnabled: notificationsEnabled,
                    notificationLeadMinutes: notificationLeadMinutes
                )
            }
        }
    }

    static func refreshPrediction(
        profile: BabyProfile?,
        events: [BabyEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int
    ) async {
        let prediction = replacePrediction(
            profile: profile,
            events: events,
            records: records,
            context: context,
            settings: settings
        )
        try? context.save()
        PersistenceService.recordLocalSave()
        Task { @MainActor in
            await refreshSystemIntegrations(
                profile: profile,
                events: events,
                prediction: prediction,
                scheduleNotification: true,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes
            )
        }
    }

    private static func replacePrediction(
        profile: BabyProfile?,
        events: [BabyEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings
    ) -> SleepPrediction? {
        let committedEvents = events.filter { !$0.isTimerDraft }
        for record in records where record.actualSleepEventID == nil {
            context.delete(record)
        }
        let resolved = records.filter { $0.actualSleepEventID != nil }
        let prediction = profile.flatMap {
            SleepPredictionEngine.predict(
                profile: $0,
                events: committedEvents,
                records: resolved,
                settings: settings
            )
        }
        if let prediction {
            let lastSleepID = committedEvents
                .filter { $0.type == .sleep && $0.endDate != nil }
                .max { $0.startDate < $1.startDate }?
                .id
            context.insert(SleepPredictionRecord(
                prediction: prediction,
                basedOnLastSleepEventID: lastSleepID,
                profileID: profile?.id
            ))
        }
        return prediction
    }

    private static func currentPrediction(
        in records: [SleepPredictionRecord]
    ) -> SleepPrediction? {
        records
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }?
            .prediction
    }

    private static func refreshSystemIntegrations(
        profile: BabyProfile?,
        events: [BabyEvent],
        prediction: SleepPrediction?,
        scheduleNotification: Bool,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int
    ) async {
        WidgetSnapshotService.refresh(profile: profile, events: events, prediction: prediction)
        if scheduleNotification {
            await NotificationManager.shared.schedule(
                prediction: prediction,
                babyName: profile?.name ?? "Baby",
                profileID: profile?.id,
                leadMinutes: notificationLeadMinutes,
                enabled: notificationsEnabled
            )
        }
        await LiveActivityManager.shared.synchronize(profile: profile, events: events)
    }
}
