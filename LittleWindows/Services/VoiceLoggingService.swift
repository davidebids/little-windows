import Foundation
import SwiftData

/// Only the main app includes this service. Siri actions use the app's opened
/// container; widgets never open a second history store or write care events.
@MainActor
enum VoiceLoggingService {
    private static var mutationsInFlight = Set<UUID>()
    private static var timerMutationsInFlight = Set<String>()

    static func container() async throws -> ModelContainer {
        let startup = PersistenceStartupController.shared
        await startup.start()
        // Entity resolution and the app's launch task can request startup at
        // the same time. start() is intentionally idempotent, so let its first
        // caller finish the launch-frame yield before treating this as failure.
        for _ in 0..<40 {
            if let container = startup.modelContainer { return container }
            if startup.failure != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw VoiceLoggingError("Open Little Windows to finish setup or recover your data, then try again.")
    }

    static func profiles(in container: ModelContainer) throws -> [CareProfile] {
        let context = ModelContext(container)
        let profiles = try context.fetch(FetchDescriptor<CareProfile>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\CareProfile.createdAt)]
        )).filter { $0.profileType != .dog }
        var seen = Set<UUID>()
        return profiles.filter { seen.insert($0.id).inserted }
    }

    static func profile(_ id: UUID, context: ModelContext) throws -> CareProfile {
        var descriptor = FetchDescriptor<CareProfile>(predicate: #Predicate { $0.id == id && !$0.isArchived })
        descriptor.fetchLimit = 1
        guard let profile = try context.fetch(descriptor).first, profile.profileType != .dog else {
            throw VoiceLoggingError("That care profile is no longer available. Choose a child or adult profile.")
        }
        return profile
    }

    static func validateDate(_ date: Date, now: Date) throws {
        guard date.timeIntervalSince1970.isFinite, date <= now.addingTimeInterval(5) else {
            throw VoiceLoggingError("Choose when this happened, rather than a future time.")
        }
    }

    static func makeEvent(_ request: VoiceCareLog, profile: CareProfile, now: Date) throws -> CareEvent {
        guard profile.id == request.profileID, !profile.isArchived, request.kind.supports(profile.profileType) else {
            throw VoiceLoggingError("That log is not available for this profile.")
        }
        try validateDate(request.date, now: now)
        let duration = request.durationMinutes ?? 0
        if duration != 0, ![.sleep, .nursing, .pumping, .feed, .activity].contains(request.kind.eventType) {
            throw VoiceLoggingError("A duration is only available for sleep, feeding, nursing, pumping, or activity.")
        }
        guard duration.isFinite, duration >= 0, duration <= 7 * 24 * 60 else {
            throw VoiceLoggingError("Use a duration between zero and seven days.")
        }
        if [.sleep, .nursing].contains(request.kind), duration <= 0 {
            throw VoiceLoggingError("Include how many minutes this lasted.")
        }
        // A duration describes a completed interval ending at the supplied time.
        let start = request.date.addingTimeInterval(-duration * 60)
        let zone = CareTimeZoneSettings.effectiveIdentifier()
        let event = CareEvent(
            id: request.id, profileID: profile.id, type: request.kind.eventType,
            startDate: start, endDate: request.date,
            startTimeZoneIdentifier: zone, endTimeZoneIdentifier: zone,
            caregiverName: CaregiverIdentityService.currentCaregiverName(),
            notes: request.notes
        )
        event.profileTypeSnapshot = profile.profileType
        var health = HealthObservationDetails()
        switch request.kind {
        case .bottle, .pumping:
            let value = try positive(request.value, name: "amount")
            switch request.unit {
            case .ounces: event.amountOz = value
            case .milliliters: event.amountOz = value / 29.5735295625
            default: throw VoiceLoggingError("Choose ounces or milliliters.")
            }
            if request.kind == .bottle { event.feedKind = .bottle }
        case .diaper, .wetDiaper, .dirtyDiaper, .mixedDiaper,
             .littlePee, .mediumPee, .bigPee, .littlePoo, .mediumPoo, .bigPoo,
             .littleMixedDiaper, .mediumMixedDiaper, .bigMixedDiaper:
            if let preset = request.kind.diaperKind, let supplied = request.diaperKind, preset != supplied {
                throw VoiceLoggingError("The diaper phrase and type conflict. Choose wet, dirty, or mixed.")
            }
            guard let kind = request.kind.diaperKind ?? request.diaperKind else { throw VoiceLoggingError("Choose wet, dirty, or both.") }
            event.diaperKind = kind
            try applyEliminationDetails(request, to: event, hasPee: kind.hasPee, hasPoo: kind.hasPoo)
            event.diaperRash = request.diaperRash
        case .potty, .pottyPee, .pottyPoop, .pottyBoth:
            if let preset = request.kind.pottyKind, let supplied = request.pottyKind, preset != supplied {
                throw VoiceLoggingError("The potty phrase and type conflict. Choose pee, poo, or both.")
            }
            guard let kind = request.kind.pottyKind ?? request.pottyKind else { throw VoiceLoggingError("Was this potty pee, poo, or both?") }
            guard request.pottyLocation != .accident || request.pottyAccident != false else {
                throw VoiceLoggingError("An accident location cannot be marked as not an accident.")
            }
            event.childPottyKind = kind
            event.childPottyLocation = request.pottyLocation
            event.childPottyAccident = request.pottyLocation == .accident ? true : request.pottyAccident
            try applyEliminationDetails(request, to: event, hasPee: kind.hasPee, hasPoo: kind.hasPoo)
        case .solidMeal, .otherFeed:
            event.feedKind = request.kind.feedKind
            event.foodDescription = try requiredText(request.text)
        case .sleep:
            guard let kind = request.sleepKind,
                  profile.profileType == .child || kind != .nightWaking else {
                throw VoiceLoggingError("Choose a nap or night sleep.")
            }
            event.sleepKind = kind
        case .nursing:
            guard let side = request.nursingSide, side == .left || side == .right else {
                throw VoiceLoggingError("Choose the left or right nursing side.")
            }
            event.nursingSide = side
            event.leftDurationSeconds = side == .left ? duration * 60 : 0
            event.rightDurationSeconds = side == .right ? duration * 60 : 0
        case .temperature:
            let value = try finite(request.value, name: "temperature")
            switch request.unit {
            case .celsius:
                event.temperatureCelsius = value
                event.temperatureUnit = .celsius
            case .fahrenheit:
                event.temperatureCelsius = (value - 32) * 5 / 9
                event.temperatureUnit = .fahrenheit
            default: throw VoiceLoggingError("Choose Celsius or Fahrenheit.")
            }
            guard event.temperatureCelsius.map({ $0 > 0 && $0 < 100 }) == true else {
                throw VoiceLoggingError("Check the temperature and its unit.")
            }
        case .bloodPressure:
            health.systolicBloodPressure = try positiveInteger(request.value, name: "top blood pressure number")
            health.diastolicBloodPressure = try positiveInteger(request.secondValue, name: "bottom blood pressure number")
            if let pulse = request.pulse { health.heartRateBPM = try positiveInteger(pulse, name: "pulse") }
        case .heartRate:
            health.heartRateBPM = try positiveInteger(request.value, name: "pulse")
        case .oxygenSaturation:
            let value = try positive(request.value, name: "oxygen percentage")
            guard value <= 100 else { throw VoiceLoggingError("Oxygen saturation must be at most 100 percent.") }
            health.oxygenSaturationPercent = value
        case .respiratoryRate:
            health.respiratoryRatePerMinute = try positiveInteger(request.value, name: "breaths per minute")
        case .glucose:
            health.bloodGlucoseValue = try positive(request.value, name: "blood glucose")
            switch request.unit {
            case .milligramsPerDeciliter: health.bloodGlucoseUnit = .milligramsPerDeciliter
            case .millimolesPerLiter: health.bloodGlucoseUnit = .millimolesPerLiter
            default: throw VoiceLoggingError("Choose milligrams per deciliter or millimoles per liter.")
            }
        case .weight:
            let value = try positive(request.value, name: "weight")
            switch request.unit {
            case .kilograms: event.weightKilograms = value
            case .pounds: event.weightKilograms = value * 0.45359237
            case .grams: event.weightKilograms = value / 1_000
            case .weightOunces: event.weightKilograms = value * 0.028349523125
            default: throw VoiceLoggingError("Choose kilograms, grams, pounds, or ounces by weight.")
            }
        case .height, .headCircumference:
            let value = try positive(request.value, name: request.kind.title.lowercased())
            let centimeters: Double
            switch request.unit {
            case .centimeters: centimeters = value
            case .inches: centimeters = value * 2.54
            default: throw VoiceLoggingError("Choose centimeters or inches.")
            }
            if request.kind == .height { event.lengthCentimeters = centimeters }
            else { event.headCircumferenceCentimeters = centimeters }
        case .pain:
            health.painScore = try score(request.value)
            health.painLocation = request.text
        case .symptom:
            health.symptomName = try requiredText(request.text)
            if request.value != nil { health.symptomSeverity = try score(request.value) }
        case .activity, .tummyTime, .storyTime, .brushTeeth, .indoorPlay, .outdoorPlay, .screenTime, .bath,
             .exercise, .physicalTherapy, .socialActivity:
            event.activityType = request.kind.activityType
            event.title = request.kind == .activity ? try requiredText(request.text) : request.kind.title
            if request.kind == .storyTime {
                let book = request.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                event.bookTitle = book?.isEmpty == false ? book : nil
            }
        case .note:
            event.title = "Care note"
            event.notes = try requiredText(request.text)
        }
        event.healthObservationDetails = health
        return event
    }

    private static func applyEliminationDetails(_ request: VoiceCareLog, to event: CareEvent, hasPee: Bool, hasPoo: Bool) throws {
        let preset = request.kind.diaperAmount
        if let preset {
            guard (!hasPee || request.peeAmount == nil || request.peeAmount == preset),
                  (!hasPoo || request.pooAmount == nil || request.pooAmount == preset) else {
                throw VoiceLoggingError("The spoken amount and supplied amount conflict. Choose one amount.")
            }
        }
        guard hasPee || request.peeAmount == nil || request.peeAmount == .unknown else {
            throw VoiceLoggingError("A pee amount requires pee or a mixed entry.")
        }
        guard hasPoo || (request.pooAmount == nil || request.pooAmount == .unknown)
                && (request.pooColor == nil || request.pooColor == .unknown)
                && (request.pooTexture == nil || request.pooTexture == .unknown) else {
            throw VoiceLoggingError("Poo details require poo or a mixed entry.")
        }
        event.peeAmount = hasPee ? (preset ?? request.peeAmount) : nil
        event.pooAmount = hasPoo ? (preset ?? request.pooAmount) : nil
        event.pooColor = hasPoo ? request.pooColor : nil
        event.pooTexture = hasPoo ? request.pooTexture : nil
    }

    private static func validateSolidsAccess(profile: CareProfile, context: ModelContext, now: Date) throws {
        let profileID = profile.id
        var descriptor = FetchDescriptor<CareEvent>(predicate: #Predicate { $0.profileID == profileID && $0.feedKindRawValue == "solid" })
        descriptor.fetchLimit = 1
        let history = try context.fetch(descriptor)
        let state = try context.fetch(FetchDescriptor<SolidsProfileState>(predicate: #Predicate { $0.profileID == profileID })).first
        guard SolidsTrackingService.accessLevel(for: profile, events: history, state: state, now: now) == .full else {
            throw VoiceLoggingError("Open the Solids workspace to review readiness before logging a solid meal.")
        }
    }

    static func log(_ request: VoiceCareLog, in container: ModelContainer, now: Date = Date()) async throws -> String {
        guard mutationsInFlight.insert(request.id).inserted else {
            throw VoiceLoggingError("This entry is already being saved.")
        }
        defer { mutationsInFlight.remove(request.id) }
        let context = ModelContext(container)
        let profile = try profile(request.profileID, context: context)
        if let existing = try event(request.id, context: context) {
            guard existing.profileID == request.profileID else { throw VoiceLoggingError("That entry conflicts with another profile.") }
            return "Already saved for \(profile.name): \(summary(existing))."
        }
        if request.kind == .solidMeal { try validateSolidsAccess(profile: profile, context: context, now: now) }
        let event = try makeEvent(request, profile: profile, now: now)
        try Task.checkCancellation()
        guard await EventMutationService.persistStandaloneEvent(event, container: container) else {
            throw VoiceLoggingError("The entry could not be saved. Please try again.")
        }
        remember(event, now: now)
        await reconcile(event, profile: profile, context: context)
        return confirmation(event, profile: profile)
    }

    // Compatibility for saved shortcuts and the dedicated nursing actions.
    static func manageTimer(
        action: VoiceTimerAction, kind: VoiceCareKind, profileID: UUID,
        side: NursingSide? = nil, sleepKind: SleepKind? = nil,
        amount: Double? = nil, unit: VoiceCareUnit? = nil,
        continueExistingNursing: Bool = false,
        at date: Date, in container: ModelContainer, now: Date = Date()
    ) async throws -> String {
        let timerKind: VoiceTimerKind
        switch kind {
        case .sleep: timerKind = .sleep
        case .nursing: timerKind = .nursing
        case .pumping: timerKind = .pumping
        case .bottle: timerKind = .bottle
        case .activity: timerKind = .customActivity
        case .note: timerKind = .customTimer
        default: throw VoiceLoggingError("Choose a care timer rather than a measurement or quick log.")
        }
        return try await manageTimer(
            action: action, timerKind: timerKind, profileID: profileID,
            side: side, sleepKind: sleepKind, amount: amount, unit: unit,
            continueExistingNursing: continueExistingNursing,
            at: date, in: container, now: now
        )
    }

    static func timerOptions(
        profileID: UUID? = nil, kind: VoiceTimerKind? = nil,
        action: VoiceTimerAction? = nil, now: Date = Date(), in container: ModelContainer
    ) throws -> [VoiceTimerOption] {
        let context = ModelContext(container)
        let profiles = try profiles(in: container)
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let drafts = try context.fetch(FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.endDate == nil },
            sortBy: [SortDescriptor(\CareEvent.startDate)]
        ))
        return drafts.compactMap { event in
            guard event.isTimerDraft, EventVisibilityStore.isVisible(event),
                  let id = event.profileID, let profile = byID[id],
                  profileID == nil || profileID == id,
                  let actualKind = VoiceTimerKind.kind(for: event), actualKind.supports(profile.profileType),
                  kind == nil || kind!.matches(event) else { return nil }
            if action == .pause && !event.isTimerRunning { return nil }
            if action == .resume && event.isTimerRunning { return nil }
            if action == .switchSide && (event.type != .nursing || !event.isTimerRunning) { return nil }
            return VoiceTimerOption(
                id: event.id, profileID: id, profileName: profile.name,
                kind: actualKind, title: event.displayTitle, isRunning: event.isTimerRunning,
                updatedAt: event.updatedAt, amountOz: event.amountOz,
                elapsedSeconds: event.timerElapsed(at: now), startDate: event.startDate,
                profileSubtitle: [profile.profileType.displayName, profile.birthDate?.formatted(date: .abbreviated, time: .omitted)]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
    }

    static func manageTimer(
        action: VoiceTimerAction, timerKind kind: VoiceTimerKind, profileID: UUID,
        eventID: UUID? = nil, expectedUpdatedAt: Date? = nil,
        side: NursingSide? = nil, sleepKind: SleepKind? = nil,
        amount: Double? = nil, unit: VoiceCareUnit? = nil,
        name: String? = nil, adjustedStart: Date? = nil,
        continueExistingNursing: Bool = false,
        at date: Date, in container: ModelContainer, now: Date = Date()
    ) async throws -> String {
        try validateDate(date, now: now)
        let context = ModelContext(container)
        let profile = try profile(profileID, context: context)
        guard kind.supports(profile.profileType) else { throw VoiceLoggingError("That timer is not available for this profile.") }
        let rawType = kind.eventType.rawValue
        // All activity subtypes share the app's one-activity-draft rule.
        let reservation = "\(profileID.uuidString).\(rawType)"
        guard timerMutationsInFlight.insert(reservation).inserted else {
            throw VoiceLoggingError("That timer is already being updated. Please try again.")
        }
        defer { timerMutationsInFlight.remove(reservation) }
        let drafts = try context.fetch(FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.profileID == profileID && $0.typeRawValue == rawType && $0.endDate == nil }
        )).filter { $0.isTimerDraft && EventVisibilityStore.isVisible($0) }
        let event: CareEvent
        var appliedAction = action
        if action == .start, drafts.isEmpty {
            guard eventID == nil, date >= now.addingTimeInterval(-7 * 86_400) else {
                throw VoiceLoggingError("Start a new timer within the previous seven days.")
            }
            let chosenSide = kind.nursingSide ?? side
            let chosenSleep = kind.sleepKind ?? sleepKind
            if let preset = kind.nursingSide, let side, preset != side {
                throw VoiceLoggingError("The nursing type and side do not match.")
            }
            if let preset = kind.sleepKind, let sleepKind, preset != sleepKind {
                throw VoiceLoggingError("The sleep type does not match this timer.")
            }
            if kind.eventType == .nursing, chosenSide == nil { throw VoiceLoggingError("Choose the left or right nursing side.") }
            if kind.eventType == .sleep, chosenSleep == nil || (profile.profileType == .adult && chosenSleep == .nightWaking) {
                throw VoiceLoggingError("Choose a nap or night sleep.")
            }
            let title = kind.needsName ? try requiredText(name) : nil
            if kind == .solidMeal {
                try validateSolidsAccess(profile: profile, context: context, now: now)
            }
            guard let started = EventTimerService.start(
                type: kind.eventType, nursingSide: chosenSide, sleepKind: chosenSleep, activityType: kind.activityType,
                caregiverName: CaregiverIdentityService.currentCaregiverName(),
                events: drafts, context: context, profileID: profile.id,
                profileType: profile.profileType, at: date, insertIntoContext: false
            ) else { throw VoiceLoggingError("A timer in that category is already open for \(profile.name).") }
            started.title = title
            started.feedKind = kind.feedKind
            if kind.eventType == .feed { started.foodDescription = title }
            if amount != nil {
                guard kind.eventType == .pumping || kind == .bottle else {
                    throw VoiceLoggingError("Milk amounts belong to bottle and pumping timers.")
                }
                started.amountOz = try milkAmount(amount, unit: unit)
            }
            event = started
        } else {
            if action == .start, kind.eventType != .nursing || !continueExistingNursing {
                throw VoiceLoggingError("A timer in that category is already open for \(profile.name). Resume or finish it first.")
            }
            let candidates = drafts.filter { event in
                (eventID == nil || event.id == eventID)
                    && (action == .start || kind.matches(event))
            }
            guard candidates.count == 1, let stored = candidates.first else {
                throw VoiceLoggingError("Choose the exact \(kind.title.lowercased()) timer for \(profile.name); no other session was changed.")
            }
            guard expectedUpdatedAt == nil || stored.updatedAt == expectedUpdatedAt,
                  date >= stored.updatedAt.addingTimeInterval(-0.75), date >= stored.startDate else {
                throw VoiceLoggingError("That timer changed while this action was being requested. Review its current state and try again.")
            }
            guard mutationsInFlight.insert(stored.id).inserted else { throw VoiceLoggingError("That timer is already being updated.") }
            defer { mutationsInFlight.remove(stored.id) }
            event = EventMutationService.detachedTimerCopy(stored)
            switch action {
            case .start:
                guard let chosenSide = kind.nursingSide ?? side else { throw VoiceLoggingError("Choose the left or right nursing side.") }
                appliedAction = stored.isTimerRunning ? .switchSide : .resume
                if !event.isTimerRunning { EventMutationService.resumeTimer(event, context: context, at: date) }
                EventTimerService.setNursingSide(event, to: chosenSide, context: context, at: date)
            case .pause:
                guard event.isTimerRunning else { throw VoiceLoggingError("That timer is already paused.") }
                EventMutationService.stopTimer(event, context: context, at: date)
            case .resume:
                guard !event.isTimerRunning else { throw VoiceLoggingError("That timer is already running.") }
                EventMutationService.resumeTimer(event, context: context, at: date)
            case .switchSide:
                guard kind.eventType == .nursing, event.isTimerRunning else { throw VoiceLoggingError("Start or resume nursing before switching sides.") }
                if let side { EventTimerService.setNursingSide(event, to: side, context: context, at: date) }
                else { EventTimerService.switchNursingSide(event, context: context, at: date) }
            case .finish:
                if kind.eventType == .pumping || event.feedKind == .bottle {
                    if let amount { event.amountOz = try milkAmount(amount, unit: unit) }
                }
                guard EventMutationService.saveTimer(event, context: context, at: date) else {
                    throw VoiceLoggingError("That timer could not be finished.")
                }
            case .reset:
                EventMutationService.resetTimer(event, context: context, at: date)
            case .adjustStart:
                guard let adjustedStart else { throw VoiceLoggingError("Include the corrected start time.") }
                try validateDate(adjustedStart, now: now)
                guard adjustedStart >= now.addingTimeInterval(-7 * 86_400), adjustedStart <= date else {
                    throw VoiceLoggingError("Choose a start time within the previous seven days.")
                }
                _ = EventTimerService.adjustStartDate(event, to: adjustedStart, at: date)
            case .discard:
                try Task.checkCancellation()
                guard EventMutationService.discardTimer(event, context: context, deleteFromContext: false) else {
                    throw VoiceLoggingError("That timer is no longer available.")
                }
                let request = EventMutationService.timerPersistenceRequest(for: event, deleting: true)
                guard await EventMutationService.persistTimerMutation(request, container: container) else {
                    EventVisibilityStore.restore(event.id)
                    throw VoiceLoggingError("The timer could not be discarded. Please try again.")
                }
                SystemIntegrationReconciler.requestReconciliation()
                WatchConnectivityService.shared.scheduleCurrentStatePublish()
                return "Discarded \(stored.displayTitle) for \(profile.name)."
            }
        }
        return try await persistTimer(event, action: appliedAction, profile: profile, context: context)
    }

    private static func milkAmount(_ amount: Double?, unit: VoiceCareUnit?) throws -> Double {
        let value = try positive(amount, name: "milk amount")
        switch unit {
        case .ounces: return value
        case .milliliters: return value / 29.5735295625
        default: throw VoiceLoggingError("Choose fluid ounces or milliliters.")
        }
    }

    static func runningNursingProfileIDs(in container: ModelContainer) throws -> Set<UUID> {
        let context = ModelContext(container)
        let rawType = EventType.nursing.rawValue
        let events = try context.fetch(FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.typeRawValue == rawType && $0.endDate == nil }
        ))
        return Set(events.filter { $0.isTimerRunning && EventVisibilityStore.isVisible($0) }.compactMap(\.profileID))
    }

    private static func persistTimer(_ event: CareEvent, action: VoiceTimerAction, profile: CareProfile, context: ModelContext) async throws -> String {
        try Task.checkCancellation()
        guard await EventMutationService.persistStandaloneEvent(event, container: context.container) else {
            throw VoiceLoggingError("The timer could not be saved. Please try again.")
        }
        if let registered = try? self.event(event.id, context: context.container.mainContext) {
            CareEventPersistenceSnapshot(event: event).apply(to: registered)
        }
        await reconcile(event, profile: profile, context: context)
        let verb: String = switch action {
        case .start: "Started"
        case .pause: "Paused"
        case .resume: "Resumed"
        case .switchSide: "Nursing side set"
        case .finish: "Saved"
        case .reset: "Reset"
        case .discard: "Discarded"
        case .adjustStart: "Updated start time"
        }
        return "\(verb) for \(profile.name): \(summary(event))."
    }

    static func last(kind: VoiceCareKind, profileID: UUID, in container: ModelContainer) throws -> String {
        let context = ModelContext(container)
        let profile = try profile(profileID, context: context)
        guard kind.supports(profile.profileType) else { throw VoiceLoggingError("That log is not available for this profile.") }
        let raw = kind.eventType.rawValue
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.profileID == profileID && $0.typeRawValue == raw && $0.endDate != nil },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        // Apply subtype filters in the store before the bounded history read.
        if let feed = kind.feedKind?.rawValue {
            descriptor.predicate = #Predicate { $0.profileID == profileID && $0.typeRawValue == raw && $0.endDate != nil && $0.feedKindRawValue == feed }
        } else if kind != .activity, let activity = kind.activityType?.rawValue {
            descriptor.predicate = #Predicate { $0.profileID == profileID && $0.typeRawValue == raw && $0.endDate != nil && $0.activityTypeRawValue == activity }
        }
        descriptor.fetchLimit = 100
        while true {
            let batch = try context.fetch(descriptor)
            if let event = batch.first(where: { !$0.isTimerDraft && EventVisibilityStore.isVisible($0) && kind.matchesSavedEntry($0) }) {
                return "\(profile.name)'s last recorded \(kind.title.lowercased()): \(summary(event)), \(spokenDate(event.startDate))."
            }
            if batch.count < 100 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
        return "There is no recorded \(kind.title.lowercased()) entry for \(profile.name)."
    }

    private struct UndoReceipt: Codable {
        var eventID: UUID
        var profileID: UUID
        var updatedAt: Date
        var expiresAt: Date
    }
    private static func undoKey(_ profileID: UUID) -> String { "voiceLogging.undo.\(profileID.uuidString)" }

    private static func remember(_ event: CareEvent, now: Date) {
        guard let profileID = event.profileID else { return }
        let receipt = UndoReceipt(eventID: event.id, profileID: profileID, updatedAt: event.updatedAt, expiresAt: now.addingTimeInterval(10 * 60))
        UserDefaults.standard.set(try? JSONEncoder().encode(receipt), forKey: undoKey(profileID))
    }

    static func undo(profileID: UUID, in container: ModelContainer, now: Date = Date()) async throws -> String {
        let context = ModelContext(container)
        let profile = try profile(profileID, context: context)
        guard let data = UserDefaults.standard.data(forKey: undoKey(profileID)),
              let receipt = try? JSONDecoder().decode(UndoReceipt.self, from: data),
              receipt.profileID == profileID, receipt.expiresAt >= now,
              let event = try event(receipt.eventID, context: context),
              event.profileID == profileID, event.updatedAt == receipt.updatedAt,
              !event.isTimerDraft, EventVisibilityStore.isVisible(event) else {
            throw VoiceLoggingError("There is no unchanged voice entry from the last ten minutes to undo. You can edit history in Little Windows.")
        }
        let result = await EventMutationService.delete(
            event, profile: profile, context: context, settings: predictionSettings,
            notificationsEnabled: UserDefaults.standard.bool(forKey: "predictionNotificationsEnabled"),
            notificationLeadMinutes: notificationLeadMinutes,
            refreshSystemSurfaces: ProfileService.shared.selectedProfileID == profileID
        )
        guard result.didPersist else {
            EventVisibilityStore.restore(event.id)
            throw VoiceLoggingError("The entry could not be removed. Please try again.")
        }
        UserDefaults.standard.removeObject(forKey: undoKey(profileID))
        SystemIntegrationReconciler.requestReconciliation()
        return "Removed the last voice entry for \(profile.name)."
    }

    private static func reconcile(_ event: CareEvent, profile: CareProfile, context: ModelContext) async {
        _ = await EventMutationService.eventDidChange(
            event, profile: profile, context: context, settings: predictionSettings,
            notificationsEnabled: UserDefaults.standard.bool(forKey: "predictionNotificationsEnabled"),
            notificationLeadMinutes: notificationLeadMinutes,
            eventAlreadyPersisted: true,
            refreshSystemSurfaces: ProfileService.shared.selectedProfileID == profile.id
        )
        SystemIntegrationReconciler.requestReconciliation()
        WatchConnectivityService.shared.scheduleCurrentStatePublish()
    }

    private static var predictionSettings: PredictionSettings {
        let defaults = UserDefaults.standard
        return PredictionSettings(
            feedAdjustmentEnabled: defaults.object(forKey: "feedAdjustmentEnabled") as? Bool ?? true,
            nursingAdjustmentEnabled: defaults.object(forKey: "nursingAdjustmentEnabled") as? Bool ?? true,
            bedtimePredictionEnabled: defaults.object(forKey: "bedtimePredictionEnabled") as? Bool ?? true,
            customBaselineMinimum: defaults.double(forKey: "customWakeMinimum") > 0 ? defaults.double(forKey: "customWakeMinimum") : nil,
            customBaselineMaximum: defaults.double(forKey: "customWakeMaximum") > 0 ? defaults.double(forKey: "customWakeMaximum") : nil
        )
    }
    private static var notificationLeadMinutes: Int {
        UserDefaults.standard.object(forKey: "notificationLeadMinutes") as? Int ?? 10
    }

    private static func event(_ id: UUID, context: ModelContext) throws -> CareEvent? {
        var descriptor = FetchDescriptor<CareEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func confirmation(_ event: CareEvent, profile: CareProfile) -> String {
        "Saved for \(profile.name): \(summary(event)), \(spokenDate(event.startDate))."
    }
    private static func summary(_ event: CareEvent) -> String {
        var text = event.displayTitle
        if event.type == .feed, let amount = event.amountOz {
            text += ", \(amount.formatted(.number.precision(.fractionLength(0...2)))) fluid ounces"
        }
        if event.type == .feed, event.feedKind == .other, let food = event.foodDescription { text += ": \(food)" }
        if event.type == .activity, let book = event.bookTitle { text += ": \(book)" }
        if let duration = event.duration, duration > 0 {
            text += ", \((duration / 60).formatted(.number.precision(.fractionLength(0...1)))) minutes"
        } else if event.isTimerDraft {
            text += ", \((event.timerElapsed(at: event.updatedAt) / 60).formatted(.number.precision(.fractionLength(0...1)))) minutes elapsed"
        }
        if event.type == .custom, let notes = event.notes { text += ": \(notes.prefix(150))" }
        return text
    }
    private static func spokenDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
    private static func finite(_ value: Double?, name: String) throws -> Double {
        guard let value, value.isFinite else { throw VoiceLoggingError("Include a valid \(name).") }
        return value
    }
    private static func positive(_ value: Double?, name: String) throws -> Double {
        let value = try finite(value, name: name)
        guard value > 0 else { throw VoiceLoggingError("The \(name) must be greater than zero.") }
        return value
    }
    private static func positiveInteger(_ value: Double?, name: String) throws -> Int {
        let value = try positive(value, name: name)
        guard value.rounded() == value, value < Double(Int.max) else { throw VoiceLoggingError("Use a whole number for \(name).") }
        return Int(value)
    }
    private static func score(_ value: Double?) throws -> Int {
        let value = try finite(value, name: "score")
        guard (0...10).contains(value), value.rounded() == value else { throw VoiceLoggingError("Use a whole-number score from zero to ten.") }
        return Int(value)
    }
    private static func requiredText(_ text: String?) throws -> String {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 4_000 else {
            throw VoiceLoggingError("Include a description of up to 4,000 characters.")
        }
        return text
    }
}

struct VoiceMedicationPlan {
    var medicationID: UUID
    var regimenID: UUID
    var profileID: UUID
    var medicationUpdatedAt: Date
    var regimenUpdatedAt: Date
    var doseAmount: Double
    var doseUnit: String
    var label: String
    var occurrences: [MedicationOccurrence]
    var isAsNeeded: Bool

    func doseLabel(_ occurrence: MedicationOccurrence) -> String {
        "\(occurrence.scheduledAt.formatted(date: .abbreviated, time: .shortened)), \(occurrence.doseAmount.formatted()) \(occurrence.doseUnit)"
    }
}

extension VoiceLoggingService {
    static func medicationPlan(
        medicationID: UUID, profileID: UUID, at date: Date,
        in container: ModelContainer, now: Date = Date()
    ) throws -> VoiceMedicationPlan {
        try validateDate(date, now: now)
        let context = ModelContext(container)
        let profile = try profile(profileID, context: context)
        var descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medicationID && !$0.isArchived })
        descriptor.fetchLimit = 1
        guard let medication = try context.fetch(descriptor).first, medication.profileID == profile.id else {
            throw VoiceLoggingError("That medication is not available for this profile.")
        }
        let regimens = try context.fetch(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { $0.medicationID == medicationID && $0.isActive }
        )).filter { $0.profileID == profileID && $0.startDate <= date && ($0.endDate == nil || $0.endDate! >= date) }
        guard regimens.count == 1, let regimen = regimens.first,
              regimen.doseAmount.isFinite, regimen.doseAmount > 0, !regimen.doseUnit.isEmpty else {
            throw VoiceLoggingError("Open Medications to review the current plan before logging this dose.")
        }
        let regimenID = regimen.id
        let phases = try context.fetch(FetchDescriptor<MedicationSchedulePhase>(predicate: #Predicate { $0.regimenID == regimenID }))
        let isAsNeeded = !regimen.scheduleKind.isScheduled
        let calendar = MedicationScheduleDate.currentCalendar()
        let occurrences = isAsNeeded ? [] : MedicationScheduleEngine.occurrences(
            regimen: regimen, phases: phases,
            from: calendar.startOfDay(for: date), through: date
        )
        if !isAsNeeded, occurrences.isEmpty {
            throw VoiceLoggingError("No scheduled dose is available on that date at or before that time. Open Medications to review the plan.")
        }
        return VoiceMedicationPlan(
            medicationID: medication.id, regimenID: regimen.id, profileID: profile.id,
            medicationUpdatedAt: medication.updatedAt, regimenUpdatedAt: regimen.updatedAt,
            doseAmount: regimen.doseAmount, doseUnit: regimen.doseUnit,
            label: "\(medication.name)\(medication.strengthDescription.map { ", \($0)" } ?? "") for \(profile.name)",
            occurrences: occurrences, isAsNeeded: isAsNeeded
        )
    }

    static func recordMedication(
        plan: VoiceMedicationPlan, occurrenceKey: String?, status: MedicationDoseStatus,
        at date: Date, in container: ModelContainer, now: Date = Date()
    ) throws -> String {
        guard status == .taken || status == .skipped else { throw VoiceLoggingError("Choose taken or skipped.") }
        if let occurrenceKey {
            let context = ModelContext(container)
            let profileID = plan.profileID
            let medicationID = plan.medicationID
            let regimenID = plan.regimenID
            let records = try context.fetch(FetchDescriptor<MedicationDoseRecord>(predicate: #Predicate {
                $0.profileID == profileID && $0.medicationID == medicationID && $0.regimenID == regimenID && $0.occurrenceKey == occurrenceKey
            }))
            if let existing = records.first {
                guard existing.status == status else { throw VoiceLoggingError("That dose was already recorded with a different outcome. Review it in Medications.") }
                return "That dose of \(plan.label) is already recorded as \(status.displayName.lowercased())."
            }
        }
        let fresh = try medicationPlan(medicationID: plan.medicationID, profileID: plan.profileID, at: date, in: container, now: now)
        guard fresh.regimenID == plan.regimenID, fresh.medicationUpdatedAt == plan.medicationUpdatedAt,
              fresh.regimenUpdatedAt == plan.regimenUpdatedAt else {
            throw VoiceLoggingError("The medication plan changed. Review it before recording a dose.")
        }
        let context = ModelContext(container)
        let medicationID = plan.medicationID
        let regimenID = plan.regimenID
        guard let medication = try context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medicationID })).first,
              let regimen = try context.fetch(FetchDescriptor<MedicationRegimen>(predicate: #Predicate { $0.id == regimenID })).first else {
            throw VoiceLoggingError("That medication plan is no longer available.")
        }
        if plan.isAsNeeded {
            guard occurrenceKey == nil else { throw VoiceLoggingError("This as-needed medication has no scheduled dose.") }
            if status == .taken {
                guard let decision = MedicationService.asNeededDecision(regimen: regimen, at: date, context: context), decision == .allowed else {
                    throw VoiceLoggingError("This entry needs review against the saved as-needed interval or daily limit. Open Medications.")
                }
            }
            guard MedicationService.recordDose(
                medication: medication, regimen: regimen, status: status, at: now,
                takenAt: status == .taken ? date : nil,
                actualDoseAmount: plan.doseAmount, context: context
            ) != nil else { throw VoiceLoggingError("The dose could not be saved. Please try again.") }
        } else {
            guard let occurrence = fresh.occurrences.first(where: { $0.occurrenceKey == occurrenceKey }),
                  let confirmed = plan.occurrences.first(where: { $0.occurrenceKey == occurrenceKey }),
                  occurrence == confirmed else {
                throw VoiceLoggingError("Choose the scheduled dose you want to record.")
            }
            let reference = MedicationScheduledDoseReference(
                profileID: plan.profileID, medicationID: plan.medicationID, regimenID: plan.regimenID,
                phaseID: occurrence.phaseID, occurrenceKey: occurrence.occurrenceKey,
                scheduledAt: occurrence.scheduledAt, doseAmount: occurrence.doseAmount, doseUnit: occurrence.doseUnit
            )
            switch MedicationService.recordScheduledDose(
                reference, status: status, at: now, takenAt: status == .taken ? date : nil, context: context
            ) {
            case .applied: break
            case .duplicate: return "That dose of \(plan.label) is already recorded as \(status.displayName.lowercased())."
            case .rejected(let message): throw VoiceLoggingError(message)
            }
        }
        SystemIntegrationReconciler.requestReconciliation()
        WatchConnectivityService.shared.scheduleCurrentStatePublish()
        return "Recorded \(plan.label) as \(status.displayName.lowercased()), \(date.formatted(date: .abbreviated, time: .shortened))."
    }
}
