import Foundation
import SwiftData

@MainActor
enum WatchCommandProcessor {
    private static let processedCommandIDsKey = "watchCompanion.processedCommandIDs.v1"
    private static let maximumProcessedCommandCount = 2_048

    static func process(
        _ command: WatchCommand,
        container: ModelContainer
    ) async -> WatchAcknowledgement {
        guard command.schemaVersion == WatchCompanionProtocol.schemaVersion else {
            return acknowledgement(
                for: command,
                status: .unsupported,
                message: "Update Little Windows on Apple Watch and iPhone."
            )
        }
        guard command.issuedAt <= Date().addingTimeInterval(5 * 60),
              command.issuedAt >= Date().addingTimeInterval(-7 * 24 * 60 * 60) else {
            return acknowledgement(
                for: command,
                status: .rejected,
                message: "This pending action is too old to apply safely."
            )
        }

        let context = container.mainContext
        if hasProcessed(command.id) {
            return acknowledgement(
                for: command,
                status: .duplicate,
                state: WatchStateFactory.make(context: context)
            )
        }
        guard let profile = fetchProfile(command.profileID, context: context) else {
            return acknowledgement(
                for: command,
                status: .rejected,
                message: "That profile is no longer available.",
                state: WatchStateFactory.make(context: context)
            )
        }

        let outcome: MutationOutcome
        switch command.kind {
        case .selectProfile:
            if ProfileService.shared.selectedProfileID == profile.id {
                outcome = .duplicate
            } else {
                ProfileService.shared.switchProfile(profile)
                outcome = .applied
            }
        case .performAction:
            outcome = performAction(command, profile: profile, context: context)
        case .stopTimer, .stopAndSaveTimer, .discardTimer,
             .resumeTimer, .switchNursingSide:
            outcome = mutateTimer(command, profile: profile, context: context)
        case .logMedicationTaken, .logMedicationSkipped, .snoozeMedication:
            outcome = await performMedicationAction(
                command,
                profile: profile,
                context: context
            )
        }

        switch outcome {
        case .rejected(let message):
            return acknowledgement(
                for: command,
                status: .rejected,
                message: message,
                state: WatchStateFactory.make(context: context)
            )
        case .duplicate:
            rememberProcessed(command.id)
            return acknowledgement(
                for: command,
                status: .duplicate,
                state: WatchStateFactory.make(context: context)
            )
        case .applied:
            if command.kind != .selectProfile,
               command.kind != .snoozeMedication,
               !PersistenceService.save(context: context) {
                if command.kind == .discardTimer, let eventID = command.eventID {
                    EventVisibilityStore.restore(eventID)
                }
                return acknowledgement(
                    for: command,
                    status: .rejected,
                    message: "The change could not be saved. Please try again.",
                    state: WatchStateFactory.make(context: context)
                )
            }
        }

        rememberProcessed(command.id)
        let state = WatchStateFactory.make(context: context)
        if command.kind != .snoozeMedication {
            SystemIntegrationReconciler.requestReconciliation()
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                Task { @MainActor [container] in
                    await SystemIntegrationReconciler.reconcile(context: container.mainContext)
                    WatchConnectivityService.shared.scheduleCurrentStatePublish()
                }
            }
        }
        return acknowledgement(for: command, status: .applied, state: state)
    }

    private static func performMedicationAction(
        _ command: WatchCommand,
        profile: CareProfile,
        context: ModelContext
    ) async -> MutationOutcome {
        guard profile.profileType == .adult else {
            return .rejected("Medication actions are available for adult profiles.")
        }
        guard let payload = command.medication,
              payload.profileID == profile.id,
              !payload.occurrenceKey.isEmpty,
              payload.doseAmount > 0,
              !payload.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected("That medication reminder is incomplete. Refresh the Watch and try again.")
        }
        let reference = MedicationScheduledDoseReference(
            profileID: profile.id,
            medicationID: payload.medicationID,
            regimenID: payload.regimenID,
            phaseID: payload.phaseID,
            occurrenceKey: payload.occurrenceKey,
            scheduledAt: payload.scheduledAt,
            doseAmount: payload.doseAmount,
            doseUnit: payload.doseUnit
        )
        let medication: Medication
        let regimen: MedicationRegimen
        let occurrence: MedicationOccurrence
        let existingRecord: MedicationDoseRecord?
        switch MedicationService.resolveScheduledDose(reference, context: context) {
        case .rejected:
            return .rejected("That medication schedule changed. Refresh the Watch before logging it.")
        case .valid(
            let resolvedMedication,
            let resolvedRegimen,
            let resolvedOccurrence,
            let resolvedRecord
        ):
            medication = resolvedMedication
            regimen = resolvedRegimen
            occurrence = resolvedOccurrence
            existingRecord = resolvedRecord
        }
        if let existingRecord {
            switch command.kind {
            case .logMedicationTaken where existingRecord.status == .taken,
                 .logMedicationSkipped where existingRecord.status == .skipped:
                return .duplicate
            default:
                return .rejected("That dose was already recorded on another device.")
            }
        }

        switch command.kind {
        case .logMedicationTaken, .logMedicationSkipped:
            let status: MedicationDoseStatus = command.kind == .logMedicationTaken
                ? .taken
                : .skipped
            guard MedicationService.recordDose(
                medication: medication,
                regimen: regimen,
                occurrence: occurrence,
                status: status,
                at: command.issuedAt,
                context: context
            ) != nil else {
                return .rejected("That dose could not be recorded. Refresh the Watch and try again.")
            }
            return .applied
        case .snoozeMedication:
            guard regimen.remindersEnabled,
                  abs(occurrence.scheduledAt.timeIntervalSince(command.issuedAt)) <= 30 * 60 else {
                return .rejected("Snooze becomes available near the scheduled time.")
            }
            if MedicationSnoozeStateStore.isSnoozed(
                occurrenceKey: occurrence.occurrenceKey,
                now: command.issuedAt
            ) {
                return .duplicate
            }
            let fireDate = command.issuedAt.addingTimeInterval(10 * 60)
            guard fireDate > Date().addingTimeInterval(1) else {
                return .rejected("That snooze expired while the Watch was disconnected.")
            }
            let currentSnapshot = WatchMedicationSnapshot(
                profileID: profile.id,
                medicationID: medication.id,
                regimenID: regimen.id,
                phaseID: occurrence.phaseID,
                occurrenceKey: occurrence.occurrenceKey,
                medicationName: medication.name,
                scheduledAt: occurrence.scheduledAt,
                doseAmount: occurrence.doseAmount,
                doseUnit: occurrence.doseUnit,
                snoozeAvailable: true
            )
            guard await MedicationNotificationScheduler.scheduleWatchSnooze(
                medication: currentSnapshot,
                fireDate: fireDate
            ) else {
                return .rejected("Medication notifications are unavailable. Check notification settings on the iPhone.")
            }
            return .applied
        default:
            return .rejected("That medication action is not supported.")
        }
    }

    private static func performAction(
        _ command: WatchCommand,
        profile: CareProfile,
        context: ModelContext
    ) -> MutationOutcome {
        guard let actionID = command.actionID,
              let action = WatchActionCatalog.actions(
                profileTypeRawValue: profile.profileType.rawValue
              ).first(where: { $0.id == actionID }) else {
            return .rejected("That action is not available for this profile.")
        }
        guard command.timerStartDate == nil || action.startsTimer else {
            return .rejected("A custom start time is only available for timers.")
        }
        let hiddenTypes = CareCategoryPreferenceStore.hiddenTypes(profileID: profile.id)
        guard !hiddenTypes.contains(where: { $0.rawValue == action.categoryRawValue }) else {
            return .rejected("That care category is hidden on the iPhone.")
        }
        if action.requiresChoice,
           !action.options.contains(where: { $0.id == command.optionID }) {
            return .rejected("Choose an option before logging this action.")
        }
        guard let eventID = command.eventID else {
            return .rejected("Update Little Windows on Apple Watch and try again.")
        }
        if let existingEvent = fetchEvent(eventID, context: context) {
            return existingEvent.profileID == profile.id
                ? .duplicate
                : .rejected("That action conflicts with an existing event.")
        }

        switch actionID {
        case "sleep":
            return startTimer(
                command,
                profile: profile,
                type: .sleep,
                sleepKind: command.optionID.flatMap(SleepKind.init(rawValue:)),
                context: context
            )
        case "nursing":
            return startTimer(
                command,
                profile: profile,
                type: .nursing,
                nursingSide: command.optionID.flatMap(NursingSide.init(rawValue:)),
                context: context
            )
        case "pumping":
            return startTimer(command, profile: profile, type: .pumping, context: context)
        case "activity":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: command.optionID.flatMap(ActivityType.init(rawValue:)),
                context: context
            )
        case "tummy-time":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .tummyTime,
                context: context
            )
        case "story-time":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .storyTime,
                context: context
            )
        case "brush-teeth":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .brushTeeth,
                context: context
            )
        case "indoor-play":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .indoorPlay,
                context: context
            )
        case "outdoor-play":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .outdoorPlay,
                context: context
            )
        case "screen-time":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .screenTime,
                context: context
            )
        case "bath":
            return startTimer(
                command,
                profile: profile,
                type: .activity,
                activityType: .bath,
                context: context
            )
        case "walk":
            return startTimer(command, profile: profile, type: .walk, context: context)
        case "rest":
            return startTimer(command, profile: profile, type: .rest, context: context)
        case "training":
            return startTimer(command, profile: profile, type: .training, context: context)
        case "grooming":
            return startTimer(command, profile: profile, type: .grooming, context: context)
        case "feed", "diaper", "potty", "food", "water", "treat":
            return logEvent(command, profile: profile, actionID: actionID, context: context)
        default:
            return .rejected("That action is not supported on Apple Watch yet.")
        }
    }

    private static func startTimer(
        _ command: WatchCommand,
        profile: CareProfile,
        type: EventType,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        activityType: ActivityType? = nil,
        context: ModelContext
    ) -> MutationOutcome {
        let timerStartDate = command.timerStartDate ?? command.issuedAt
        guard WatchTimerStartPolicy.isValid(
            startDate: timerStartDate,
            issuedAt: command.issuedAt
        ) else {
            return .rejected("Choose a start time within the previous seven days.")
        }
        let events = fetchActiveEvents(profileID: profile.id, context: context)
        guard let event = EventMutationService.startTimer(
            type: type,
            nursingSide: nursingSide,
            sleepKind: sleepKind,
            activityType: activityType,
            caregiverName: currentCaregiverName(),
            events: events,
            profileID: profile.id,
            profileType: profile.profileType,
            context: context
        ) else {
            return .rejected("A \(type.displayName.lowercased()) timer is already active.")
        }
        if let eventID = command.eventID {
            event.id = eventID
        }
        event.createdAt = command.issuedAt
        event.updatedAt = command.issuedAt
        event.startDate = timerStartDate
        event.activeTimerSegmentStartDate = timerStartDate
        event.startTimeZoneIdentifier = validTimeZoneIdentifier(command.timeZoneIdentifier)
        return .applied
    }

    private static func logEvent(
        _ command: WatchCommand,
        profile: CareProfile,
        actionID: String,
        context: ModelContext
    ) -> MutationOutcome {
        let type: EventType = switch actionID {
        case "feed": .feed
        case "diaper": .diaper
        case "potty": .potty
        case "food": .food
        case "water": .water
        case "treat": .treat
        default: .custom
        }
        let timeZoneIdentifier = validTimeZoneIdentifier(command.timeZoneIdentifier)
        let event = CareEvent(
            id: command.eventID ?? UUID(),
            profileID: profile.id,
            type: type,
            startDate: command.issuedAt,
            endDate: command.issuedAt,
            startTimeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: timeZoneIdentifier,
            caregiverName: currentCaregiverName()
        )
        event.createdAt = command.issuedAt
        event.updatedAt = command.issuedAt
        event.profileTypeSnapshot = profile.profileType
        switch actionID {
        case "feed":
            event.feedKind = command.optionID.flatMap(FeedKind.init(rawValue:))
        case "diaper":
            event.diaperKind = command.optionID.flatMap(DiaperKind.init(rawValue:))
        case "potty" where profile.profileType == .child:
            event.childPottyKind = command.optionID.flatMap(ChildPottyKind.init(rawValue:))
            event.childPottyLocation = .pottyChair
        case "potty":
            var details = DogEventDetails()
            details.pottyType = command.optionID.flatMap(DogPottyType.init(rawValue:))
            details.pottyLocation = .outside
            event.dogDetails = details
        default:
            break
        }
        context.insert(event)
        return .applied
    }

    private static func mutateTimer(
        _ command: WatchCommand,
        profile: CareProfile,
        context: ModelContext
    ) -> MutationOutcome {
        guard let eventID = command.eventID,
              let event = fetchEvent(eventID, context: context),
              event.profileID == profile.id else {
            return .rejected("That timer is no longer available.")
        }
        if let expectedUpdatedAt = command.expectedEventUpdatedAt,
           event.updatedAt > expectedUpdatedAt.addingTimeInterval(0.75) {
            return .rejected("The timer changed on another device. The latest version is shown.")
        }
        switch command.kind {
        case .stopTimer:
            guard event.isTimerRunning else {
                return event.isTimerDraft ? .duplicate : .rejected("That timer was already saved.")
            }
            let segmentStart = event.activeTimerSegmentStartDate ?? event.startDate
            guard segmentStart <= command.issuedAt.addingTimeInterval(0.75) else {
                return .rejected("The timer was restarted after this action was requested.")
            }
            EventMutationService.stopTimer(event, context: context, at: command.issuedAt)
        case .stopAndSaveTimer:
            guard event.isTimerDraft else { return .rejected("That timer was already saved.") }
            if event.isTimerRunning {
                let segmentStart = event.activeTimerSegmentStartDate ?? event.startDate
                guard segmentStart <= command.issuedAt.addingTimeInterval(0.75) else {
                    return .rejected("The timer was restarted after this action was requested.")
                }
                EventMutationService.stopTimer(event, context: context, at: command.issuedAt)
            }
            EventMutationService.saveTimer(event, context: context, at: command.issuedAt)
        case .discardTimer:
            guard event.isTimerDraft else {
                return .rejected("That timer was already saved.")
            }
            guard !event.isTimerRunning else {
                return .rejected("Pause the timer before discarding it.")
            }
            guard EventMutationService.discardTimer(event, context: context) else {
                return .rejected("That timer is no longer available.")
            }
        case .resumeTimer:
            guard event.isTimerDraft, !event.isTimerRunning else {
                return .rejected("That timer is already running.")
            }
            guard event.updatedAt <= command.issuedAt.addingTimeInterval(0.75) else {
                return .rejected("The timer changed after this action was requested.")
            }
            EventMutationService.resumeTimer(event, context: context, at: command.issuedAt)
        case .switchNursingSide:
            guard event.type == .nursing, event.isTimerDraft else {
                return .rejected("That nursing timer is no longer available.")
            }
            guard event.updatedAt <= command.issuedAt.addingTimeInterval(0.75) else {
                return .rejected("The nursing timer changed after this action was requested.")
            }
            if let requestedSide = command.optionID.flatMap(NursingSide.init(rawValue:)) {
                EventTimerService.setNursingSide(
                    event,
                    to: requestedSide,
                    context: context,
                    at: command.issuedAt
                )
            } else {
                EventTimerService.switchNursingSide(
                    event,
                    context: context,
                    at: command.issuedAt
                )
            }
        case .selectProfile, .performAction, .logMedicationTaken,
             .logMedicationSkipped, .snoozeMedication:
            return .rejected("Unsupported timer action.")
        }
        return .applied
    }

    private static func fetchProfile(
        _ id: UUID,
        context: ModelContext
    ) -> CareProfile? {
        var descriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate { $0.id == id && !$0.isArchived }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchEvent(
        _ id: UUID,
        context: ModelContext
    ) -> CareEvent? {
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchActiveEvents(
        profileID: UUID,
        context: ModelContext
    ) -> [CareEvent] {
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { event in
                event.profileID == profileID && event.endDate == nil
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func currentCaregiverName() -> String {
        CaregiverIdentityService.currentCaregiverName()
    }

    private static func validTimeZoneIdentifier(_ identifier: String) -> String {
        TimeZone(identifier: identifier)?.identifier
            ?? CareTimeZoneSettings.effectiveIdentifier()
    }

    private static func acknowledgement(
        for command: WatchCommand,
        status: WatchAcknowledgementStatus,
        message: String? = nil,
        state: WatchCompanionState? = nil
    ) -> WatchAcknowledgement {
        WatchAcknowledgement(
            schemaVersion: WatchCompanionProtocol.schemaVersion,
            commandID: command.id,
            status: status,
            message: message,
            state: state
        )
    }

    private static func hasProcessed(_ id: UUID) -> Bool {
        processedCommandIDs().contains(id.uuidString)
    }

    private static func rememberProcessed(_ id: UUID) {
        var ids = processedCommandIDs()
        ids.removeAll { $0 == id.uuidString }
        ids.append(id.uuidString)
        if ids.count > maximumProcessedCommandCount {
            ids.removeFirst(ids.count - maximumProcessedCommandCount)
        }
        UserDefaults.standard.set(ids, forKey: processedCommandIDsKey)
    }

    private static func processedCommandIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: processedCommandIDsKey) ?? []
    }

    private enum MutationOutcome {
        case applied
        case duplicate
        case rejected(String)
    }
}
