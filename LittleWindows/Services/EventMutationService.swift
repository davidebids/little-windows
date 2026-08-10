import Foundation
import SwiftData

/// Keeps an event pending deletion out of every in-process surface immediately
/// while its isolated persistence and reconciliation finish.
/// IDs intentionally remain tombstoned for the lifetime of the process: an
/// older cancelled integration task may still hold the deleted model object.
enum EventVisibilityStore {
    private static let lock = NSLock()
    private static var eventIDs = Set<UUID>()

    static func markPendingDeletion(_ eventID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        eventIDs.insert(eventID)
    }

    static func restore(_ eventID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        eventIDs.remove(eventID)
    }

    static func isVisible(_ event: CareEvent) -> Bool {
        let eventID = event.id
        lock.lock()
        defer { lock.unlock() }
        return !eventIDs.contains(eventID)
    }

    static func visibleEvents(in events: [CareEvent]) -> [CareEvent] {
        lock.lock()
        let hiddenEventIDs = eventIDs
        lock.unlock()
        guard !hiddenEventIDs.isEmpty else { return events }
        return events.filter { !hiddenEventIDs.contains($0.id) }
    }
}

private struct EventPersistenceResult: Sendable {
    var didSave: Bool
    var prediction: SleepPrediction?
    var refreshesSleepPrediction: Bool
    var pressure: SleepPressure? = nil
    var miniPlan: SleepMiniPlan? = nil
    var isSleeping: Bool = false
    var widgetSnapshot: WidgetSnapshot? = nil
    var removedMedicationDose: Bool = false
    var allergenProfileIDs: [UUID] = []
    var predictionRecordIDsToDelete: [UUID] = []
    var predictionBasedOnLastSleepEventID: UUID? = nil
    var errorDescription: String?
}

private struct EventDeletionRequest: Sendable {
    var eventID: UUID
    var profileID: UUID?
    var isSleepBlock: Bool
    var refreshesSleepPrediction: Bool
    var needsAllergenReconciliation: Bool
}

struct EventIntegrationAnalysis: Sendable {
    var prediction: SleepPrediction?
    var pressure: SleepPressure?
    var miniPlan: SleepMiniPlan?
    var isSleeping: Bool
    var widgetSnapshot: WidgetSnapshot?
    var isAuthoritative: Bool
}

struct CareEventPersistenceSnapshot: Sendable {
    var id: UUID
    var profileID: UUID?
    var profileTypeSnapshotRawValue: String?
    var typeRawValue: String
    var title: String?
    var startDate: Date
    var endDate: Date?
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var caregiverName: String?
    var notes: String?
    var sleepKindRawValue: String?
    var feedKindRawValue: String?
    var amountOz: Double?
    var foodDescription: String?
    var solidReactionRawValue: String?
    var solidTextureRawValue: String?
    var solidFeedingStyleRawValue: String?
    var solidAllergenExposure: Bool?
    var solidSensitivityObserved: Bool?
    var solidFoodDetailsJSON: String?
    var nursingSideRawValue: String?
    var activeNursingSideRawValue: String?
    var timerStateRawValue: String?
    var timerAccumulatedSeconds: Double?
    var activeTimerSegmentStartDate: Date?
    var leftDurationSeconds: Double?
    var rightDurationSeconds: Double?
    var diaperKindRawValue: String?
    var diaperRash: Bool?
    var childPottyKindRawValue: String?
    var childPottyLocationRawValue: String?
    var childPottyAccident: Bool?
    var peeAmountRawValue: String?
    var pooAmountRawValue: String?
    var pooColorRawValue: String?
    var pooTextureRawValue: String?
    var stoolColor: String?
    var stoolTexture: String?
    var bookTitle: String?
    var medicineName: String?
    var dose: Double?
    var doseUnit: String?
    var reason: String?
    var activityTypeRawValue: String?
    var heightFeet: Int?
    var heightInches: Double?
    var weightPounds: Int?
    var weightOunces: Double?
    var headCircumferenceInches: Double?
    var growthSexRawValue: String?
    var growthSourceRawValue: String?
    var weightKilograms: Double?
    var lengthCentimeters: Double?
    var headCircumferenceCentimeters: Double?
    var temperatureCelsius: Double?
    var temperatureUnitRawValue: String?
    var temperatureMethodRawValue: String?
    var dogDetailsData: Data?
    var healthObservationDetailsData: Data?

    @MainActor
    init(event: CareEvent) {
        id = event.id
        profileID = event.profileID
        profileTypeSnapshotRawValue = event.profileTypeSnapshotRawValue
        typeRawValue = event.typeRawValue
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        startTimeZoneIdentifier = event.startTimeZoneIdentifier
        endTimeZoneIdentifier = event.endTimeZoneIdentifier
        createdAt = event.createdAt
        updatedAt = event.updatedAt
        caregiverName = event.caregiverName
        notes = event.notes
        sleepKindRawValue = event.sleepKindRawValue
        feedKindRawValue = event.feedKindRawValue
        amountOz = event.amountOz
        foodDescription = event.foodDescription
        solidReactionRawValue = event.solidReactionRawValue
        solidTextureRawValue = event.solidTextureRawValue
        solidFeedingStyleRawValue = event.solidFeedingStyleRawValue
        solidAllergenExposure = event.solidAllergenExposure
        solidSensitivityObserved = event.solidSensitivityObserved
        solidFoodDetailsJSON = event.solidFoodDetailsJSON
        nursingSideRawValue = event.nursingSideRawValue
        activeNursingSideRawValue = event.activeNursingSideRawValue
        timerStateRawValue = event.timerStateRawValue
        timerAccumulatedSeconds = event.timerAccumulatedSeconds
        activeTimerSegmentStartDate = event.activeTimerSegmentStartDate
        leftDurationSeconds = event.leftDurationSeconds
        rightDurationSeconds = event.rightDurationSeconds
        diaperKindRawValue = event.diaperKindRawValue
        diaperRash = event.diaperRash
        childPottyKindRawValue = event.childPottyKindRawValue
        childPottyLocationRawValue = event.childPottyLocationRawValue
        childPottyAccident = event.childPottyAccident
        peeAmountRawValue = event.peeAmountRawValue
        pooAmountRawValue = event.pooAmountRawValue
        pooColorRawValue = event.pooColorRawValue
        pooTextureRawValue = event.pooTextureRawValue
        stoolColor = event.stoolColor
        stoolTexture = event.stoolTexture
        bookTitle = event.bookTitle
        medicineName = event.medicineName
        dose = event.dose
        doseUnit = event.doseUnit
        reason = event.reason
        activityTypeRawValue = event.activityTypeRawValue
        heightFeet = event.heightFeet
        heightInches = event.heightInches
        weightPounds = event.weightPounds
        weightOunces = event.weightOunces
        headCircumferenceInches = event.headCircumferenceInches
        growthSexRawValue = event.growthSexRawValue
        growthSourceRawValue = event.growthSourceRawValue
        weightKilograms = event.weightKilograms
        lengthCentimeters = event.lengthCentimeters
        headCircumferenceCentimeters = event.headCircumferenceCentimeters
        temperatureCelsius = event.temperatureCelsius
        temperatureUnitRawValue = event.temperatureUnitRawValue
        temperatureMethodRawValue = event.temperatureMethodRawValue
        dogDetailsData = event.dogDetailsData
        healthObservationDetailsData = event.healthObservationDetailsData
    }

    func makeDetachedEvent() -> CareEvent {
        let event = CareEvent(
            id: id,
            profileID: profileID,
            type: EventType.normalized(rawValue: typeRawValue),
            title: title,
            startDate: startDate,
            endDate: endDate,
            startTimeZoneIdentifier: startTimeZoneIdentifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            caregiverName: caregiverName,
            notes: notes
        )
        apply(to: event)
        return event
    }

    func apply(to event: CareEvent) {
        event.profileID = profileID
        event.profileTypeSnapshotRawValue = profileTypeSnapshotRawValue
        event.typeRawValue = typeRawValue
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.startTimeZoneIdentifier = startTimeZoneIdentifier
        event.endTimeZoneIdentifier = endTimeZoneIdentifier
        event.createdAt = createdAt
        event.updatedAt = updatedAt
        event.caregiverName = caregiverName
        event.notes = notes
        event.sleepKindRawValue = sleepKindRawValue
        event.feedKindRawValue = feedKindRawValue
        event.amountOz = amountOz
        event.foodDescription = foodDescription
        event.solidReactionRawValue = solidReactionRawValue
        event.solidTextureRawValue = solidTextureRawValue
        event.solidFeedingStyleRawValue = solidFeedingStyleRawValue
        event.solidAllergenExposure = solidAllergenExposure
        event.solidSensitivityObserved = solidSensitivityObserved
        event.solidFoodDetailsJSON = solidFoodDetailsJSON
        event.nursingSideRawValue = nursingSideRawValue
        event.activeNursingSideRawValue = activeNursingSideRawValue
        event.timerStateRawValue = timerStateRawValue
        event.timerAccumulatedSeconds = timerAccumulatedSeconds
        event.activeTimerSegmentStartDate = activeTimerSegmentStartDate
        event.leftDurationSeconds = leftDurationSeconds
        event.rightDurationSeconds = rightDurationSeconds
        event.diaperKindRawValue = diaperKindRawValue
        event.diaperRash = diaperRash
        event.childPottyKindRawValue = childPottyKindRawValue
        event.childPottyLocationRawValue = childPottyLocationRawValue
        event.childPottyAccident = childPottyAccident
        event.peeAmountRawValue = peeAmountRawValue
        event.pooAmountRawValue = pooAmountRawValue
        event.pooColorRawValue = pooColorRawValue
        event.pooTextureRawValue = pooTextureRawValue
        event.stoolColor = stoolColor
        event.stoolTexture = stoolTexture
        event.bookTitle = bookTitle
        event.medicineName = medicineName
        event.dose = dose
        event.doseUnit = doseUnit
        event.reason = reason
        event.activityTypeRawValue = activityTypeRawValue
        event.heightFeet = heightFeet
        event.heightInches = heightInches
        event.weightPounds = weightPounds
        event.weightOunces = weightOunces
        event.headCircumferenceInches = headCircumferenceInches
        event.growthSexRawValue = growthSexRawValue
        event.growthSourceRawValue = growthSourceRawValue
        event.weightKilograms = weightKilograms
        event.lengthCentimeters = lengthCentimeters
        event.headCircumferenceCentimeters = headCircumferenceCentimeters
        event.temperatureCelsius = temperatureCelsius
        event.temperatureUnitRawValue = temperatureUnitRawValue
        event.temperatureMethodRawValue = temperatureMethodRawValue
        event.dogDetailsData = dogDetailsData
        event.healthObservationDetailsData = healthObservationDetailsData
    }
}

enum TimerPersistenceOperation: Sendable {
    case upsert(CareEventPersistenceSnapshot)
    case delete
}

struct TimerPersistenceRequest: Sendable {
    var eventID: UUID
    var sequence: UInt64
    var operation: TimerPersistenceOperation
}

enum AppointmentEventLinkKind: Sendable {
    case growth
    case temperature
}

/// Reuses one serial SwiftData writer per container. The writer owns its own
/// model context, so history queries, linked-record cleanup, prediction work,
/// and the store save never execute on SwiftUI's main actor.
private actor EventPersistenceWorkerPool {
    static let shared = EventPersistenceWorkerPool()

    // Keep writers alive for the lifetime of their store. Besides avoiding
    // repeated ModelContext construction, this preserves the per-event
    // sequence ledger that prevents a delayed upsert from resurrecting a
    // timer after the user has discarded it.
    private var workers: [ObjectIdentifier: EventPersistenceWorker] = [:]
    private var recency: [ObjectIdentifier] = []

    func worker(for container: ModelContainer) -> EventPersistenceWorker {
        let key = ObjectIdentifier(container)
        if let worker = workers[key] {
            recency.removeAll { $0 == key }
            recency.append(key)
            return worker
        }
        let worker = EventPersistenceWorker(modelContainer: container)
        workers[key] = worker
        recency.append(key)
        if recency.count > 8 {
            workers[recency.removeFirst()] = nil
        }
        return worker
    }
}

@ModelActor
private actor EventPersistenceWorker {
    private var latestTimerSequenceByID: [UUID: UInt64] = [:]

    func persistTimer(_ request: TimerPersistenceRequest) -> String? {
        guard request.sequence > (latestTimerSequenceByID[request.eventID] ?? 0) else {
            return nil
        }
        latestTimerSequenceByID[request.eventID] = request.sequence

        let eventID = request.eventID
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.id == eventID }
        )
        descriptor.fetchLimit = 1
        let stored = try? modelContext.fetch(descriptor).first
        switch request.operation {
        case .upsert(let snapshot):
            let event = stored ?? snapshot.makeDetachedEvent()
            if event.modelContext == nil {
                modelContext.insert(event)
            }
            snapshot.apply(to: event)
        case .delete:
            if let stored {
                modelContext.delete(stored)
            }
        }

        do {
            if modelContext.hasChanges {
                try modelContext.save()
                PersistenceService.recordLocalSave()
            }
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }

    func linkAppointment(
        appointmentID: UUID,
        eventID: UUID,
        kind: AppointmentEventLinkKind
    ) -> String? {
        var descriptor = FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate { $0.id == appointmentID }
        )
        descriptor.fetchLimit = 1
        guard let appointment = try? modelContext.fetch(descriptor).first else {
            return "The appointment could not be found."
        }
        switch kind {
        case .growth:
            appointment.growthEntryID = eventID
        case .temperature:
            appointment.temperatureEntryID = eventID
        }
        appointment.updatedAt = Date()
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }

    func delete(
        request: EventDeletionRequest,
        settings: PredictionSettings
    ) -> EventPersistenceResult {
        let eventID = request.eventID
        var eventDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.id == eventID }
        )
        eventDescriptor.fetchLimit = 1
        if let storedEvent = try? modelContext.fetch(eventDescriptor).first {
            modelContext.delete(storedEvent)
        }
        let profileID = request.profileID
        let profile = fetchProfile(profileID: profileID)
        let events = fetchEvents(profileID: profileID).filter { $0.id != eventID }
        let records = fetchPredictionRecords(
            profileID: profileID,
            linkedEventID: eventID
        )
        let refreshesSleepPrediction = request.refreshesSleepPrediction
        let predictionRecordIDsToDelete = refreshesSleepPrediction
            ? records.filter {
                $0.actualSleepEventID == nil || $0.actualSleepEventID == eventID
            }.map(\.id)
            : []
        let resolvedRecords = records.filter {
            $0.actualSleepEventID != nil && $0.actualSleepEventID != eventID
        }

        let hadTrackedSolidFeed = hasTrackedSolidFeedRecords(eventID: eventID)
        let needsAllergenReconciliation = request.needsAllergenReconciliation
            || hadTrackedSolidFeed
        var allergenProfileIDs = Set<UUID>()
        if needsAllergenReconciliation {
            allergenProfileIDs.formUnion(removeSolidFeedRecords(eventID: eventID))
            if let profileID { allergenProfileIDs.insert(profileID) }
        }

        let removedMedicationDose = prepareForMedicationEventDeletion(eventID: eventID)
        let prediction = refreshesSleepPrediction
            ? prediction(
                profile: profile,
                events: events,
                resolvedRecords: resolvedRecords,
                settings: settings
            )
            : currentPrediction(in: records)
        let basedOnLastSleepEventID = events
            .filter { !$0.isTimerDraft && $0.isSleepBlock && $0.endDate != nil }
            .max { $0.startDate < $1.startDate }?
            .id
        let pressure = SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: events,
            settings: settings
        )
        let widgetSnapshot = makeWidgetSnapshot(
            profile: profile,
            events: events,
            prediction: prediction
        )

        // Keep prediction-record cleanup in this isolated transaction. The
        // previous implementation returned these mutations to the SwiftUI
        // context and performed a second synchronous save on the main actor,
        // which is why deleting a timeline event could freeze scrolling.
        if refreshesSleepPrediction {
            let idsToDelete = Set(predictionRecordIDsToDelete)
            for record in records where idsToDelete.contains(record.id) {
                modelContext.delete(record)
            }
            if let prediction {
                modelContext.insert(SleepPredictionRecord(
                    prediction: prediction,
                    basedOnLastSleepEventID: basedOnLastSleepEventID,
                    profileID: profileID,
                    settings: settings
                ))
            }
        }

        do {
            if modelContext.hasChanges {
                try modelContext.save()
                PersistenceService.recordLocalSave()
            }
            return EventPersistenceResult(
                didSave: true,
                prediction: prediction,
                refreshesSleepPrediction: refreshesSleepPrediction,
                pressure: pressure,
                widgetSnapshot: widgetSnapshot,
                removedMedicationDose: removedMedicationDose,
                allergenProfileIDs: Array(allergenProfileIDs),
                predictionRecordIDsToDelete: [],
                predictionBasedOnLastSleepEventID: basedOnLastSleepEventID
            )
        } catch {
            modelContext.rollback()
            return EventPersistenceResult(
                didSave: false,
                prediction: nil,
                refreshesSleepPrediction: refreshesSleepPrediction,
                errorDescription: error.localizedDescription
            )
        }
    }

    func rebuildPrediction(
        afterChanging eventID: UUID,
        refreshPrediction: Bool,
        settings: PredictionSettings
    ) -> EventPersistenceResult {
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.id == eventID }
        )
        descriptor.fetchLimit = 1
        guard let event = try? modelContext.fetch(descriptor).first else {
            return EventPersistenceResult(
                didSave: true,
                prediction: nil,
                refreshesSleepPrediction: false
            )
        }
        let profileID = event.profileID
        let profile = fetchProfile(profileID: profileID)
        let events = fetchEvents(profileID: profileID)
        let records = fetchPredictionRecords(
            profileID: profileID,
            linkedEventID: eventID
        )
        if event.isSleepBlock, !event.isTimerDraft {
            resolveLatestPrediction(with: event, records: records)
        }
        let shouldRefresh = refreshPrediction && affectsSleepPredictionRefresh(event)
        let prediction = shouldRefresh
            ? replacePrediction(
                profile: profile,
                events: events,
                records: records,
                settings: settings
            )
            : currentPrediction(in: records)
        let pressure = SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: events,
            settings: settings
        )
        let widgetSnapshot = makeWidgetSnapshot(
            profile: profile,
            events: events,
            prediction: prediction
        )
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return EventPersistenceResult(
                didSave: true,
                prediction: prediction,
                refreshesSleepPrediction: shouldRefresh,
                pressure: pressure,
                widgetSnapshot: widgetSnapshot
            )
        } catch {
            modelContext.rollback()
            return EventPersistenceResult(
                didSave: false,
                prediction: nil,
                refreshesSleepPrediction: shouldRefresh,
                errorDescription: error.localizedDescription
            )
        }
    }

    func rebuildPrediction(
        profileID: UUID?,
        settings: PredictionSettings
    ) -> EventPersistenceResult {
        let profile = fetchProfile(profileID: profileID)
        let events = fetchEvents(profileID: profileID)
        let records = fetchPredictionRecords(profileID: profileID)
        let prediction = replacePrediction(
            profile: profile,
            events: events,
            records: records,
            settings: settings
        )
        let pressure = SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: events,
            settings: settings
        )
        let widgetSnapshot = makeWidgetSnapshot(
            profile: profile,
            events: events,
            prediction: prediction
        )
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return EventPersistenceResult(
                didSave: true,
                prediction: prediction,
                refreshesSleepPrediction: true,
                pressure: pressure,
                widgetSnapshot: widgetSnapshot
            )
        } catch {
            modelContext.rollback()
            return EventPersistenceResult(
                didSave: false,
                prediction: nil,
                refreshesSleepPrediction: true,
                errorDescription: error.localizedDescription
            )
        }
    }

    func integrationState(
        profileID: UUID?,
        settings: PredictionSettings
    ) -> EventPersistenceResult {
        let profile = fetchProfile(profileID: profileID)
        let events: [CareEvent]
        do {
            events = try fetchIntegrationEvents(profileID: profileID)
        } catch {
            return EventPersistenceResult(
                didSave: false,
                prediction: nil,
                refreshesSleepPrediction: false,
                errorDescription: error.localizedDescription
            )
        }
        let records = fetchPredictionRecords(profileID: profileID)
        let prediction = currentPrediction(in: records)
        let isSleeping = events.contains { $0.isSleepBlock && $0.isTimerRunning }
        let widgetSnapshot = makeWidgetSnapshot(
            profile: profile,
            events: events,
            prediction: prediction
        )
        return EventPersistenceResult(
            didSave: true,
            prediction: prediction,
            refreshesSleepPrediction: false,
            pressure: SleepPredictionEngine.sleepPressure(
                profile: profile,
                events: events,
                records: records,
                settings: settings
            ),
            miniPlan: profile.flatMap {
                SleepMiniPlanService.plan(
                    profile: $0,
                    events: events,
                    records: records,
                    prediction: prediction,
                    now: Date(),
                    calendar: .current
                )
            },
            isSleeping: isSleeping,
            widgetSnapshot: widgetSnapshot
        )
    }

    private func makeWidgetSnapshot(
        profile: CareProfile?,
        events: [CareEvent],
        prediction: SleepPrediction?
    ) -> WidgetSnapshot {
        let solidsState: SolidsProfileState?
        if let profileID = profile?.id {
            var descriptor = FetchDescriptor<SolidsProfileState>(
                predicate: #Predicate { $0.profileID == profileID },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            solidsState = try? modelContext.fetch(descriptor).first
        } else {
            solidsState = nil
        }
        return WidgetSnapshotService.makeSnapshot(
            profileID: profile?.id,
            profileType: profile?.profileType ?? .child,
            profileBirthDate: profile?.birthDate,
            solidsWorkspaceActivated: solidsState?.isActivated == true,
            babyName: profile?.name ?? "Baby",
            events: events,
            prediction: prediction
        )
    }

    private func fetchProfile(profileID: UUID?) -> CareProfile? {
        guard let profileID else { return nil }
        var descriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate { $0.id == profileID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchEvents(profileID: UUID?) -> [CareEvent] {
        (try? fetchIntegrationEvents(profileID: profileID)) ?? []
    }

    private func fetchIntegrationEvents(profileID: UUID?) throws -> [CareEvent] {
        guard let profileID else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())
            ?? .distantPast
        var descriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        descriptor.predicate = #Predicate {
            $0.profileID == profileID
                && ($0.startDate >= cutoff || $0.endDate == nil)
        }
        descriptor.fetchLimit = 1_200
        return Array(try modelContext.fetch(descriptor).reversed())
    }

    private func fetchPredictionRecords(
        profileID: UUID?,
        linkedEventID: UUID? = nil
    ) -> [SleepPredictionRecord] {
        guard let profileID else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())
            ?? .distantPast
        var descriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && ($0.generatedAt >= cutoff || $0.actualSleepEventID == nil)
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        var records = (try? modelContext.fetch(descriptor)) ?? []
        if let linkedEventID,
           !records.contains(where: { $0.actualSleepEventID == linkedEventID }) {
            var linkedDescriptor = FetchDescriptor<SleepPredictionRecord>(
                predicate: #Predicate {
                    $0.profileID == profileID && $0.actualSleepEventID == linkedEventID
                }
            )
            linkedDescriptor.fetchLimit = 1
            if let linked = try? modelContext.fetch(linkedDescriptor).first {
                records.append(linked)
            }
        }
        return records.sorted { $0.generatedAt < $1.generatedAt }
    }

    private func hasTrackedSolidFeedRecords(eventID: UUID) -> Bool {
        var descriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func removeSolidFeedRecords(eventID: UUID) -> Set<UUID> {
        let itemDescriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        let removedItems = (try? modelContext.fetch(itemDescriptor)) ?? []
        let affectedProfileIDs = Set(removedItems.map(\.profileID))
        var remainingByProfileAndFood: [UUID: [String: [SolidFoodEventItem]]] = [:]
        let foodIDsByProfile = Dictionary(grouping: removedItems, by: \.profileID)
            .mapValues { Set($0.map(\.foodID)) }
        // A deleted meal usually contains only a handful of foods. Fetch just
        // those histories instead of scanning and grouping the profile's
        // entire nutrient-intake table for every timeline deletion.
        for (profileID, foodIDs) in foodIDsByProfile {
            for foodID in foodIDs {
                let remainingDescriptor = FetchDescriptor<SolidFoodEventItem>(
                    predicate: #Predicate {
                        $0.profileID == profileID
                            && $0.foodID == foodID
                            && $0.eventID != eventID
                    },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                remainingByProfileAndFood[profileID, default: [:]][foodID] =
                    (try? modelContext.fetch(remainingDescriptor)) ?? []
            }
        }
        let now = Date()
        for removed in removedItems {
            let profileID = removed.profileID
            let foodID = removed.foodID
            modelContext.delete(removed)
            let remaining = remainingByProfileAndFood[profileID]?[foodID] ?? []
            let progressDescriptor = FetchDescriptor<SolidFoodProgress>(
                predicate: #Predicate { $0.profileID == profileID && $0.foodID == foodID }
            )
            if let record = try? modelContext.fetch(progressDescriptor).first {
                record.exposureCount = remaining.count
                record.firstTriedAt = remaining.map(\.createdAt).min()
                record.lastTriedAt = remaining.first?.createdAt
                record.lastReactionRawValue = remaining.first?.reactionRawValue
                if remaining.isEmpty, record.status == .tried {
                    record.status = .notTried
                }
                record.updatedAt = now
            }
        }
        let planDescriptor = FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.completedEventID == eventID }
        )
        for plan in (try? modelContext.fetch(planDescriptor)) ?? [] {
            plan.completedEventID = nil
            plan.updatedAt = now
        }
        return affectedProfileIDs
    }

    private func prepareForMedicationEventDeletion(eventID: UUID) -> Bool {
        var recordDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate { $0.careEventID == eventID }
        )
        recordDescriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(recordDescriptor).first else { return false }
        let medicationID = record.medicationID
        var medicationDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == medicationID }
        )
        medicationDescriptor.fetchLimit = 1
        if let medication = try? modelContext.fetch(medicationDescriptor).first {
            let refund = -record.supplyAdjustmentApplied
            if refund > 0,
               let profileID = medication.profileID,
               let currentSupply = medication.currentSupply {
                medication.currentSupply = currentSupply + refund
                record.supplyAdjustmentApplied = 0
                modelContext.insert(MedicationSupplyLog(
                    profileID: profileID,
                    medicationID: medication.id,
                    doseRecordID: record.id,
                    adjustment: refund,
                    resultingSupply: medication.currentSupply,
                    reason: .correction,
                    notes: "Medication timeline entry deleted."
                ))
            } else {
                record.supplyAdjustmentApplied = 0
            }
            medication.updatedAt = Date()
        }
        modelContext.delete(record)
        return true
    }

    private func replacePrediction(
        profile: CareProfile?,
        events: [CareEvent],
        records: [SleepPredictionRecord],
        settings: PredictionSettings
    ) -> SleepPrediction? {
        let committedEvents = events.filter { !$0.isTimerDraft }
        for record in records where record.actualSleepEventID == nil {
            modelContext.delete(record)
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
            modelContext.insert(SleepPredictionRecord(
                prediction: prediction,
                basedOnLastSleepEventID: lastSleepID,
                profileID: profile?.id,
                settings: settings
            ))
        }
        return prediction
    }

    private func prediction(
        profile: CareProfile?,
        events: [CareEvent],
        resolvedRecords: [SleepPredictionRecord],
        settings: PredictionSettings
    ) -> SleepPrediction? {
        let committedEvents = events.filter { !$0.isTimerDraft }
        return profile.flatMap {
            SleepPredictionEngine.predict(
                profile: $0,
                events: committedEvents,
                records: resolvedRecords,
                settings: settings
            )
        }
    }

    private func resolveLatestPrediction(
        with sleepEvent: CareEvent,
        records: [SleepPredictionRecord]
    ) {
        guard sleepEvent.isSleepBlock else { return }
        let linkedRecord = records.first { $0.actualSleepEventID == sleepEvent.id }
        let candidate = linkedRecord ?? records
            .filter {
                $0.actualSleepEventID == nil
                    && $0.generatedAt <= sleepEvent.startDate
                    && sleepEvent.startDate.timeIntervalSince($0.generatedAt) <= 18 * 60 * 60
            }
            .max { $0.generatedAt < $1.generatedAt }
        guard let candidate else { return }
        candidate.actualSleepEventID = sleepEvent.id
        candidate.actualSleepStart = sleepEvent.startDate
        candidate.errorMinutes = sleepEvent.startDate.timeIntervalSince(candidate.predictedStart) / 60
        candidate.wasInsidePredictedWindow = (
            candidate.predictedWindowStart...candidate.predictedWindowEnd
        ).contains(sleepEvent.startDate)
        candidate.updatedAt = Date()
    }

    private func currentPrediction(in records: [SleepPredictionRecord]) -> SleepPrediction? {
        records
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }?
            .prediction
    }

    private func affectsSleepPredictionRefresh(_ event: CareEvent) -> Bool {
        event.isSleepBlock || (event.type.affectsSleepPrediction && event.type != .sleep)
    }
}

@MainActor
enum EventMutationService {
    private static var pendingSystemIntegrationTask: Task<Void, Never>?
    private static var systemIntegrationRevision = 0
    private static var timerPersistenceSequence: UInt64 = 0

    static func startTimer(
        type: EventType,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        activityType: ActivityType? = nil,
        caregiverName: String?,
        events: [CareEvent],
        profileID: UUID? = nil,
        profileType: CareProfileType? = nil,
        context: ModelContext,
        insertIntoContext: Bool = true
    ) -> CareEvent? {
        EventTimerService.start(
            type: type,
            nursingSide: nursingSide,
            sleepKind: sleepKind,
            activityType: activityType,
            caregiverName: caregiverName,
            events: events,
            context: context,
            profileID: profileID,
            profileType: profileType,
            insertIntoContext: insertIntoContext
        )
    }

    static func detachedTimerCopy(_ event: CareEvent) -> CareEvent {
        CareEventPersistenceSnapshot(event: event).makeDetachedEvent()
    }

    static func detachedEventCopy(_ event: CareEvent) -> CareEvent {
        CareEventPersistenceSnapshot(event: event).makeDetachedEvent()
    }

    static func timerPersistenceRequest(
        for event: CareEvent,
        deleting: Bool = false
    ) -> TimerPersistenceRequest {
        timerPersistenceSequence &+= 1
        return TimerPersistenceRequest(
            eventID: event.id,
            sequence: timerPersistenceSequence,
            operation: deleting
                ? .delete
                : .upsert(CareEventPersistenceSnapshot(event: event))
        )
    }

    nonisolated static func persistTimerMutation(
        _ request: TimerPersistenceRequest,
        container: ModelContainer
    ) async -> Bool {
        let worker = await EventPersistenceWorkerPool.shared.worker(for: container)
        if let error = await worker.persistTimer(request) {
            await PersistenceService.recordLocalSaveFailure(error)
            return false
        }
        return true
    }

    /// Persists a detached editor result without ever registering it in the
    /// SwiftUI-owned context. This is appropriate for event editors that do
    /// not need the full sleep/widget reconciliation pipeline.
    static func persistStandaloneEvent(
        _ event: CareEvent,
        container: ModelContainer
    ) async -> Bool {
        let request = timerPersistenceRequest(for: event)
        return await persistTimerMutation(request, container: container)
    }

    static func persistStandaloneEvent(
        _ event: CareEvent,
        appointmentID: UUID,
        appointmentLinkKind: AppointmentEventLinkKind,
        container: ModelContainer
    ) async -> Bool {
        guard await persistStandaloneEvent(event, container: container) else {
            return false
        }
        let worker = await EventPersistenceWorkerPool.shared.worker(for: container)
        if let error = await worker.linkAppointment(
            appointmentID: appointmentID,
            eventID: event.id,
            kind: appointmentLinkKind
        ) {
            PersistenceService.recordLocalSaveFailure(error)
            return false
        }
        return true
    }

    static func quickRepeatCandidate(
        in events: [CareEvent],
        profileID: UUID?
    ) -> CareEvent? {
        events
            .filter { $0.matchesProfile(profileID) && canQuickRepeat($0) }
            .max { $0.startDate < $1.startDate }
    }

    nonisolated static func canQuickRepeat(_ event: CareEvent) -> Bool {
        guard !event.isTimerDraft else { return false }
        if let profileType = event.profileTypeSnapshot {
            guard EventType.cases(for: profileType).contains(event.type) else { return false }
            if event.type == .activity, let activityType = event.activityType {
                guard activityType.isAvailable(for: profileType) else { return false }
            }
        }
        switch event.type {
        case .feed, .pumping, .diaper, .temperature, .activity,
             .food, .water, .treat, .potty, .grooming:
            return true
        case .sleep, .nursing, .growth, .walk, .rest, .training, .vaccine,
             .medicine, .symptom, .glucose, .bloodPressure, .heartRate, .oxygenSaturation,
             .respiratoryRate, .pain, .custom:
            return false
        }
    }

    static func repeatEvent(
        _ source: CareEvent,
        caregiverName: String?,
        profileID: UUID?,
        profileType: CareProfileType?,
        context: ModelContext,
        at date: Date = Date(),
        insertIntoContext: Bool = true
    ) -> CareEvent? {
        guard canQuickRepeat(source) else { return nil }
        let effectiveProfileType = source.profileTypeSnapshot ?? profileType
        if let effectiveProfileType {
            guard EventType.cases(for: effectiveProfileType).contains(source.type) else { return nil }
            if source.type == .activity, let activityType = source.activityType {
                guard activityType.isAvailable(for: effectiveProfileType) else { return nil }
            }
        }
        let duration = source.duration ?? 0
        let endDate = duration > 0 ? date.addingTimeInterval(duration) : date
        let timeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        let event = CareEvent(
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
        if insertIntoContext {
            context.insert(event)
        }
        return event
    }

    static func stopTimer(
        _ event: CareEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.stop(event, context: context, at: date)
    }

    static func resumeTimer(
        _ event: CareEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.resume(event, context: context, at: date)
    }

    static func resetTimer(
        _ event: CareEvent,
        context: ModelContext,
        at date: Date = Date()
    ) {
        EventTimerService.reset(event, context: context, at: date)
    }

    @discardableResult
    static func saveTimer(
        _ event: CareEvent,
        context: ModelContext,
        at date: Date = Date(),
        endDate: Date? = nil
    ) -> Bool {
        EventTimerService.save(event, context: context, at: date, endDate: endDate)
    }

    @discardableResult
    static func discardTimer(
        _ event: CareEvent,
        context: ModelContext,
        deleteFromContext: Bool = true
    ) -> Bool {
        guard event.isTimerDraft else { return false }
        EventVisibilityStore.markPendingDeletion(event.id)
        // The tombstone removes the draft from every UI/system surface first.
        // The isolated writer performs the actual delete so no store commit can
        // block gestures on the main actor.
        if deleteFromContext {
            context.delete(event)
        }
        return true
    }

    /// Compatibility path for non-interactive contexts. Today and History use
    /// ordered isolated requests so this synchronous save never runs while a
    /// user is scrolling or editing a timer.
    @discardableResult
    static func persistTimerMutations(context: ModelContext) -> Bool {
        PersistenceService.save(context: context)
    }

    static func integrationAnalysis(
        profileID: UUID?,
        context: ModelContext,
        settings: PredictionSettings
    ) async -> EventIntegrationAnalysis {
        await integrationAnalysis(
            profileID: profileID,
            container: context.container,
            settings: settings
        )
    }

    /// Performs the history scan entirely through the model actor. Callers that
    /// only need immutable analysis can start this from a detached utility task
    /// without carrying a SwiftUI-owned `ModelContext` across executors.
    nonisolated static func integrationAnalysis(
        profileID: UUID?,
        container: ModelContainer,
        settings: PredictionSettings
    ) async -> EventIntegrationAnalysis {
        let worker = await EventPersistenceWorkerPool.shared.worker(for: container)
        let result = await worker.integrationState(
            profileID: profileID,
            settings: settings
        )
        return EventIntegrationAnalysis(
            prediction: result.prediction,
            pressure: result.pressure,
            miniPlan: result.miniPlan,
            isSleeping: result.isSleeping,
            widgetSnapshot: result.widgetSnapshot,
            isAuthoritative: result.didSave
        )
    }

    @discardableResult
    static func delete(
        _ event: CareEvent,
        profile: CareProfile?,
        events: [CareEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int
    ) async -> Bool {
        EventVisibilityStore.markPendingDeletion(event.id)
        let request = EventDeletionRequest(
            eventID: event.id,
            profileID: event.profileID,
            isSleepBlock: event.isSleepBlock,
            refreshesSleepPrediction: affectsSleepPredictionRefresh(event),
            needsAllergenReconciliation: event.type == .feed && event.feedKind == .solid
        )
        _ = events
        // Keep the SwiftUI-owned context read-only. The optimistic tombstone
        // removes the row immediately while the model actor deletes and saves
        // the stored event together with all linked cleanup.
        let worker = await EventPersistenceWorkerPool.shared.worker(for: context.container)
        let result = await worker.delete(request: request, settings: settings)
        guard result.didSave else {
            if let errorDescription = result.errorDescription {
                PersistenceService.recordLocalSaveFailure(errorDescription)
            }
            // The requested event deletion already committed. Keep it deleted
            // and report the derived-data failure instead of resurrecting a
            // partially deleted timeline row.
            return true
        }
        _ = records
        if result.removedMedicationDose {
            SystemIntegrationReconciler.requestReconciliation()
        }
        for profileID in result.allergenProfileIDs {
            let writer = await SolidsWriterPool.shared.allergenProgressWriter(for: context.container)
            _ = await writer.reconcileDerivedProgress(profileID: profileID)
        }
        let container = context.container
        let revision = beginSystemIntegrationUpdate()
        pendingSystemIntegrationTask = Task { @MainActor [container] in
            await Task.yield()
            guard isCurrentSystemIntegrationUpdate(revision) else { return }
            await refreshSystemIntegrations(
                profile: profile,
                widgetSnapshot: result.widgetSnapshot,
                prediction: result.prediction,
                pressure: result.pressure,
                scheduleNotification: request.refreshesSleepPrediction,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                revision: revision
            )
            _ = container
            if revision == systemIntegrationRevision {
                pendingSystemIntegrationTask = nil
            }
        }
        return true
    }

    static func eventDidChange(
        _ event: CareEvent,
        profile: CareProfile?,
        events: [CareEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false,
        solidPreset: SolidFeedEditorPreset? = nil,
        eventAlreadyPersisted: Bool = false
    ) async {
        if !eventAlreadyPersisted {
            event.updatedAt = Date()
        }
        let shouldRefreshPrediction = refreshPrediction && affectsSleepPredictionRefresh(event)
        let shouldRefreshNotification = shouldRefreshLittleWindowAlert(after: event)
        if !eventAlreadyPersisted {
            let request = timerPersistenceRequest(for: event)
            guard await persistTimerMutation(
                request,
                container: context.container
            ) else { return }
        }
        let eventUpdatedAt = event.updatedAt
        let solidsWriter = await SolidsWriterPool.shared.eventWriter(for: context.container)
        let solidsResult = await solidsWriter.reconcile(
            eventID: event.id,
            preset: solidPreset,
            now: eventUpdatedAt
        )
        if let error = solidsResult.error {
            PersistenceService.recordLocalSaveFailure(error)
            return
        }
        if solidsResult.changedLinkedRecords,
           !solidsResult.allergenIDsToReconcile.isEmpty,
           let profileID = solidsResult.profileID {
            let writer = await SolidsWriterPool.shared.allergenProgressWriter(for: context.container)
            _ = await writer.reconcileDerivedProgress(
                profileID: profileID,
                allergenIDs: Set(solidsResult.allergenIDsToReconcile),
                now: eventUpdatedAt
            )
        }
        let worker = await EventPersistenceWorkerPool.shared.worker(for: context.container)
        let result = await worker.rebuildPrediction(
            afterChanging: event.id,
            refreshPrediction: shouldRefreshPrediction,
            settings: settings
        )
        guard result.didSave else {
            if let errorDescription = result.errorDescription {
                PersistenceService.recordLocalSaveFailure(errorDescription)
            }
            return
        }
        let prediction = result.prediction
        if waitForSystemIntegrations {
            let revision = beginSystemIntegrationUpdate()
            await refreshSystemIntegrations(
                profile: profile,
                widgetSnapshot: result.widgetSnapshot,
                prediction: prediction,
                pressure: result.pressure,
                scheduleNotification: shouldRefreshNotification,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                revision: revision
            )
        } else {
            let container = context.container
            let revision = beginSystemIntegrationUpdate()
            pendingSystemIntegrationTask = Task { @MainActor [container] in
                await Task.yield()
                guard isCurrentSystemIntegrationUpdate(revision) else { return }
                await refreshSystemIntegrations(
                    profile: profile,
                    widgetSnapshot: result.widgetSnapshot,
                    prediction: prediction,
                    pressure: result.pressure,
                    scheduleNotification: shouldRefreshNotification,
                    notificationsEnabled: notificationsEnabled,
                    notificationLeadMinutes: notificationLeadMinutes,
                    revision: revision
                )
                _ = container
                if revision == systemIntegrationRevision {
                    pendingSystemIntegrationTask = nil
                }
            }
        }
    }

    static func refreshPrediction(
        profile: CareProfile?,
        events: [CareEvent],
        records: [SleepPredictionRecord],
        context: ModelContext,
        settings: PredictionSettings,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int
    ) async {
        _ = records
        let worker = await EventPersistenceWorkerPool.shared.worker(for: context.container)
        let result = await worker.rebuildPrediction(
            profileID: profile?.id,
            settings: settings
        )
        guard result.didSave else {
            if let errorDescription = result.errorDescription {
                PersistenceService.recordLocalSaveFailure(errorDescription)
            }
            return
        }
        let container = context.container
        let revision = beginSystemIntegrationUpdate()
        pendingSystemIntegrationTask = Task { @MainActor [container] in
            await Task.yield()
            guard isCurrentSystemIntegrationUpdate(revision) else { return }
            await refreshSystemIntegrations(
                profile: profile,
                widgetSnapshot: result.widgetSnapshot,
                prediction: result.prediction,
                pressure: result.pressure,
                scheduleNotification: true,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes,
                revision: revision
            )
            _ = container
            if revision == systemIntegrationRevision {
                pendingSystemIntegrationTask = nil
            }
        }
    }

    private static func copyRepeatableDetails(from source: CareEvent, to event: CareEvent) {
        event.sleepKind = source.sleepKind
        event.feedKind = source.feedKind
        event.amountOz = source.amountOz
        event.foodDescription = source.foodDescription
        event.solidReaction = source.solidReaction
        event.solidTexture = source.solidTexture
        event.solidFeedingStyle = source.solidFeedingStyle
        event.solidAllergenExposure = source.solidAllergenExposure
        event.solidSensitivityObserved = source.solidSensitivityObserved
        event.solidFoodDetails = source.solidFoodDetails
        event.nursingSide = source.nursingSide
        event.leftDurationSeconds = source.leftDurationSeconds
        event.rightDurationSeconds = source.rightDurationSeconds
        event.diaperKind = source.diaperKind
        event.diaperRash = source.diaperRash
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

    private static func currentPrediction(
        in records: [SleepPredictionRecord]
    ) -> SleepPrediction? {
        records
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }?
            .prediction
    }

    private static func refreshSystemIntegrations(
        profile: CareProfile?,
        widgetSnapshot: WidgetSnapshot?,
        prediction: SleepPrediction?,
        pressure: SleepPressure?,
        scheduleNotification: Bool,
        notificationsEnabled: Bool,
        notificationLeadMinutes: Int,
        revision: Int
    ) async {
        guard isCurrentSystemIntegrationUpdate(revision) else { return }
        if let widgetSnapshot {
            WidgetSnapshotService.publish(widgetSnapshot)
        }
        WatchConnectivityService.shared.scheduleCurrentStatePublish()
        let activeTimer = widgetSnapshot?.activeTimer
        let isSleeping = activeTimer?.typeRawValue == EventType.sleep.rawValue
            && activeTimer?.resolvedIsRunning == true
        // Timer surfaces are interaction-critical and carry a snapshot
        // revision. Apply them before notification scheduling can suspend, and
        // let LiveActivityManager reject any older job that finishes late.
        await LiveActivityManager.shared.synchronize(
            timer: activeTimer,
            revision: widgetSnapshot?.generatedAt ?? Date()
        )
        guard isCurrentSystemIntegrationUpdate(revision) else { return }
        if scheduleNotification {
            await NotificationManager.shared.schedule(
                prediction: prediction,
                babyName: profile?.name ?? "Baby",
                profileID: profile?.id,
                leadMinutes: notificationLeadMinutes,
                enabled: notificationsEnabled,
                isSleeping: isSleeping
            )
            guard isCurrentSystemIntegrationUpdate(revision) else { return }
            await NotificationManager.shared.rescheduleSleepPressureAlertIfNeeded(
                pressure: pressure,
                babyName: profile?.name ?? "Baby",
                profileID: profile?.id,
                enabled: UserDefaults.standard.bool(forKey: "sleepPressureAlertsEnabled"),
                isSleeping: isSleeping
            )
        }
    }

    private static func beginSystemIntegrationUpdate() -> Int {
        SystemIntegrationReconciler.invalidateInFlightReconciliation()
        systemIntegrationRevision &+= 1
        pendingSystemIntegrationTask?.cancel()
        pendingSystemIntegrationTask = nil
        return systemIntegrationRevision
    }

    private static func isCurrentSystemIntegrationUpdate(_ revision: Int) -> Bool {
        !Task.isCancelled && revision == systemIntegrationRevision
    }

    private static func affectsSleepPredictionRefresh(_ event: CareEvent) -> Bool {
        event.isSleepBlock || (event.type.affectsSleepPrediction && event.type != .sleep)
    }

    static func shouldRefreshLittleWindowAlert(after event: CareEvent) -> Bool {
        affectsSleepPredictionRefresh(event)
    }
}
