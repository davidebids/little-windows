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

    static func quickRepeatCandidate(
        in events: [BabyEvent],
        profileID: UUID?
    ) -> BabyEvent? {
        events
            .filter { $0.matchesProfile(profileID) && canQuickRepeat($0) }
            .max { $0.startDate < $1.startDate }
    }

    static func canQuickRepeat(_ event: BabyEvent) -> Bool {
        guard !event.isTimerDraft else { return false }
        switch event.type {
        case .feed, .pumping, .diaper, .medicine, .temperature, .activity,
             .food, .water, .treat, .potty, .grooming, .symptom, .glucose:
            return true
        case .sleep, .nursing, .growth, .walk, .rest, .training, .vaccine, .custom:
            return false
        }
    }

    static func repeatEvent(
        _ source: BabyEvent,
        caregiverName: String?,
        profileID: UUID?,
        profileType: CareProfileType?,
        context: ModelContext,
        at date: Date = Date()
    ) -> BabyEvent? {
        guard canQuickRepeat(source) else { return nil }
        let duration = source.duration ?? 0
        let endDate = duration > 0 ? date.addingTimeInterval(duration) : date
        let timeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        let event = BabyEvent(
            profileID: source.profileID ?? profileID,
            type: source.type,
            title: source.title,
            startDate: date,
            endDate: endDate,
            startTimeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: timeZoneIdentifier,
            caregiverName: caregiverName,
            notes: source.notes
        )
        event.profileTypeSnapshot = source.profileTypeSnapshot ?? profileType
        copyRepeatableDetails(from: source, to: event)
        context.insert(event)
        return event
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
        at date: Date = Date(),
        endDate: Date? = nil
    ) {
        EventTimerService.save(event, context: context, at: date, endDate: endDate)
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
        if event.isSleepBlock {
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
        let prediction = affectsSleepPredictionRefresh(event)
            ? replacePrediction(
                profile: profile,
                events: remainingEvents,
                records: records,
                context: context,
                settings: settings
            )
            : currentPrediction(in: records)
        guard PersistenceService.save(context: context) else { return }
        Task { @MainActor in
            await refreshSystemIntegrations(
                profile: profile,
                events: remainingEvents,
                prediction: prediction,
                scheduleNotification: affectsSleepPredictionRefresh(event),
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                settings: settings
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
        if event.isSleepBlock, !event.isTimerDraft {
            PredictionTuningService.resolveLatestPrediction(with: event, records: records)
        }
        let shouldRefreshPrediction = refreshPrediction && affectsSleepPredictionRefresh(event)
        let shouldRefreshNotification = shouldRefreshLittleWindowAlert(after: event)
        let prediction = shouldRefreshPrediction
            ? replacePrediction(
                profile: profile,
                events: events,
                records: records,
                context: context,
                settings: settings
            )
            : currentPrediction(in: records)
        guard PersistenceService.save(context: context) else { return }
        if waitForSystemIntegrations {
            await refreshSystemIntegrations(
                profile: profile,
                events: events,
                prediction: prediction,
                scheduleNotification: shouldRefreshNotification,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                settings: settings
            )
        } else {
            Task { @MainActor in
                await refreshSystemIntegrations(
                    profile: profile,
                    events: events,
                    prediction: prediction,
                    scheduleNotification: shouldRefreshNotification,
                    notificationsEnabled: notificationsEnabled,
                    notificationLeadMinutes: notificationLeadMinutes,
                    settings: settings
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
        guard PersistenceService.save(context: context) else { return }
        Task { @MainActor in
            await refreshSystemIntegrations(
                profile: profile,
                events: events,
                prediction: prediction,
                scheduleNotification: true,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                settings: settings
            )
        }
    }

    private static func copyRepeatableDetails(from source: BabyEvent, to event: BabyEvent) {
        event.sleepKind = source.sleepKind
        event.feedKind = source.feedKind
        event.amountOz = source.amountOz
        event.foodDescription = source.foodDescription
        event.solidReaction = source.solidReaction
        event.solidTexture = source.solidTexture
        event.solidFeedingStyle = source.solidFeedingStyle
        event.solidAllergenExposure = source.solidAllergenExposure
        event.solidSensitivityObserved = source.solidSensitivityObserved
        event.nursingSide = source.nursingSide
        event.leftDurationSeconds = source.leftDurationSeconds
        event.rightDurationSeconds = source.rightDurationSeconds
        event.diaperKind = source.diaperKind
        event.childPottyKind = source.childPottyKind
        event.childPottyLocation = source.childPottyLocation
        event.childPottyAccident = source.childPottyAccident
        event.peeAmount = source.peeAmount
        event.pooAmount = source.pooAmount
        event.pooColor = source.pooColor
        event.pooTexture = source.pooTexture
        event.stoolColor = source.stoolColor
        event.stoolTexture = source.stoolTexture
        event.bookTitle = source.bookTitle
        event.medicineName = source.medicineName
        event.dose = source.dose
        event.doseUnit = source.doseUnit
        event.reason = source.reason
        event.activityType = source.activityType
        event.temperatureCelsius = source.temperatureCelsius
        event.temperatureUnit = source.temperatureUnit
        event.temperatureMethod = source.temperatureMethod
        event.dogDetails = source.dogDetails
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
                .filter { $0.isSleepBlock && $0.endDate != nil }
                .max { $0.startDate < $1.startDate }?
                .id
            context.insert(SleepPredictionRecord(
                prediction: prediction,
                basedOnLastSleepEventID: lastSleepID,
                profileID: profile?.id,
                settings: settings
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
        notificationLeadMinutes: Int,
        settings: PredictionSettings
    ) async {
        WidgetSnapshotService.refresh(profile: profile, events: events, prediction: prediction)
        let isSleeping = events.contains {
            $0.isSleepBlock && $0.isTimerRunning
        }
        if scheduleNotification {
            await NotificationManager.shared.schedule(
                prediction: prediction,
                babyName: profile?.name ?? "Baby",
                profileID: profile?.id,
                leadMinutes: notificationLeadMinutes,
                enabled: notificationsEnabled,
                isSleeping: isSleeping
            )
            let pressure = SleepPredictionEngine.sleepPressure(
                profile: profile,
                events: events,
                now: Date(),
                settings: settings
            )
            await NotificationManager.shared.rescheduleSleepPressureAlertIfNeeded(
                pressure: pressure,
                babyName: profile?.name ?? "Baby",
                profileID: profile?.id,
                enabled: UserDefaults.standard.bool(forKey: "sleepPressureAlertsEnabled"),
                isSleeping: isSleeping
            )
        }
        await LiveActivityManager.shared.synchronize(profile: profile, events: events)
    }

    private static func affectsSleepPredictionRefresh(_ event: BabyEvent) -> Bool {
        event.isSleepBlock || (event.type.affectsSleepPrediction && event.type != .sleep)
    }

    static func shouldRefreshLittleWindowAlert(after event: BabyEvent) -> Bool {
        affectsSleepPredictionRefresh(event)
    }
}
