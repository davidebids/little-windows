import Foundation
import SwiftData

struct SolidsGuidedPlanWrite: Sendable {
    var scheduledAt: Date
    var title: String
    var foodIDs: [String]
    var foodNames: [String]
    var notes: String
    var recipeID: String?
    var guidedPosition: Int
    var allergenID: String?
    var allergenIntroductionStep: Int?
    var allergenServingGuidance: String?
    var allergenObservationMinutes: Int?

    init(suggestion: SolidsGuidedMealSuggestion, guidedPosition: Int) {
        let allergenNote = suggestion.allergenID.flatMap(SolidsAllergen.init(rawValue:))
            .map { "Allergen rotation: \($0.displayName). " } ?? ""
        let names = suggestion.foods.map(\.name)
        scheduledAt = suggestion.scheduledAt
        title = suggestion.recipe?.title ?? names.joined(separator: " + ")
        foodIDs = suggestion.foods.map(\.id)
        foodNames = names
        notes = "\(suggestion.kind.displayName). \(allergenNote)\(suggestion.stage.title): \(suggestion.stage.skill). \(suggestion.preparationNotes)"
        recipeID = suggestion.recipe?.id
        self.guidedPosition = guidedPosition
        allergenID = suggestion.allergenID
        allergenIntroductionStep = suggestion.allergenIntroductionStep
        allergenServingGuidance = suggestion.allergenServingGuidance
        allergenObservationMinutes = suggestion.allergenIntroductionStep == 1 ? 10 : nil
    }
}

struct SolidsPlanEditorWrite: Sendable {
    var planID: UUID?
    var profileID: UUID
    var scheduledAt: Date
    var foodIDs: [String]
    var foodNames: [String]
    var notes: String
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var title: String? = nil
    var recipeID: String? = nil
    var isGuided: Bool = false
    var guidedPosition: Int? = nil
    var allergenID: String? = nil
    var allergenIntroductionStep: Int? = nil
    var allergenServingGuidance: String? = nil
    var allergenObservationMinutes: Int? = nil
}

struct SolidsPlanWriteResult: Sendable {
    var planID: UUID?
    var error: String?
}

struct SolidsShoppingFoodWrite: Sendable {
    var foodID: String
    var foodName: String
    var aliases: [String] = []
}

struct SolidsCustomFoodWrite: Sendable {
    var itemID: UUID?
    var name: String
    var photoDraft: PhotoAttachmentDraft?
    var removeExistingPhoto: Bool
    var allergenIDs: [String]
    var minimumAgeMonths: Int
    var preparationNotes: String
    var safetyNotes: String
}

struct SolidsCustomFoodWriteResult: Sendable {
    var itemID: UUID?
    var name: String?
    var error: String?
}

/// Immutable inputs for the comparatively expensive First 100 planning pass.
/// SwiftData models are flattened on the main actor, then this value can be
/// evaluated safely on a utility executor without touching live model objects.
struct SolidsGuidedSuggestionSnapshot: @unchecked Sendable {
    var isChild: Bool
    var birthDate: Date
    var triedFoodIDs: Set<String>
    var plannedFoodIDs: Set<String>
    var blockedAllergenIDs: Set<String>
    var toleratedAllergenIDs: Set<String>
    var confirmedExposureCountByAllergen: [String: Int]
    var plannedExposureStepByAllergen: [String: Int]
    var completedSkillIDs: Set<String>
    var startDate: Date
    var count: Int
    var calendar: Calendar
}

/// Creates and reuses the solids model actors away from SwiftUI's main actor.
///
/// Constructing a `@ModelActor` also creates its model context. Doing that from
/// individual view tasks made screen presentation and the first tap on many
/// solids controls pay setup work on the UI thread. One writer of each kind per
/// container is sufficient because every writer is already an actor and its
/// operations are profile-scoped.
actor SolidsWriterPool {
    static let shared = SolidsWriterPool()

    private final class WeakWriterBox: @unchecked Sendable {
        weak var value: AnyObject?

        init(_ value: AnyObject) {
            self.value = value
        }
    }

    private var customFoodWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var mealPrepWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var backfillWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var shoppingListWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var profileStateWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var planWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var guidedPlanWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var feedingSkillWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var foodProgressWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var recipePreferenceWriters: [ObjectIdentifier: WeakWriterBox] = [:]
    private var allergenProgressWriters: [ObjectIdentifier: WeakWriterBox] = [:]

    func customFoodWriter(for container: ModelContainer) -> SolidsCustomFoodWriter {
        resolve(container, storage: &customFoodWriters) {
            SolidsCustomFoodWriter(modelContainer: $0)
        }
    }

    func mealPrepWriter(for container: ModelContainer) -> SolidsMealPrepWriter {
        resolve(container, storage: &mealPrepWriters) {
            SolidsMealPrepWriter(modelContainer: $0)
        }
    }

    func backfillWriter(for container: ModelContainer) -> SolidsBackfillWriter {
        resolve(container, storage: &backfillWriters) {
            SolidsBackfillWriter(modelContainer: $0)
        }
    }

    func shoppingListWriter(for container: ModelContainer) -> SolidsShoppingListWriter {
        resolve(container, storage: &shoppingListWriters) {
            SolidsShoppingListWriter(modelContainer: $0)
        }
    }

    func profileStateWriter(for container: ModelContainer) -> SolidsProfileStateWriter {
        resolve(container, storage: &profileStateWriters) {
            SolidsProfileStateWriter(modelContainer: $0)
        }
    }

    func planWriter(for container: ModelContainer) -> SolidsPlanWriter {
        resolve(container, storage: &planWriters) {
            SolidsPlanWriter(modelContainer: $0)
        }
    }

    func guidedPlanWriter(for container: ModelContainer) -> SolidsGuidedPlanWriter {
        resolve(container, storage: &guidedPlanWriters) {
            SolidsGuidedPlanWriter(modelContainer: $0)
        }
    }

    func feedingSkillWriter(for container: ModelContainer) -> SolidsFeedingSkillWriter {
        resolve(container, storage: &feedingSkillWriters) {
            SolidsFeedingSkillWriter(modelContainer: $0)
        }
    }

    func foodProgressWriter(for container: ModelContainer) -> SolidsFoodProgressWriter {
        resolve(container, storage: &foodProgressWriters) {
            SolidsFoodProgressWriter(modelContainer: $0)
        }
    }

    func recipePreferenceWriter(for container: ModelContainer) -> SolidsRecipePreferenceWriter {
        resolve(container, storage: &recipePreferenceWriters) {
            SolidsRecipePreferenceWriter(modelContainer: $0)
        }
    }

    func allergenProgressWriter(for container: ModelContainer) -> SolidsAllergenProgressWriter {
        resolve(container, storage: &allergenProgressWriters) {
            SolidsAllergenProgressWriter(modelContainer: $0)
        }
    }

    private func resolve<Writer: AnyObject>(
        _ container: ModelContainer,
        storage: inout [ObjectIdentifier: WeakWriterBox],
        create: (ModelContainer) -> Writer
    ) -> Writer {
        let key = ObjectIdentifier(container)
        if let existing = storage[key]?.value as? Writer { return existing }
        let writer = create(container)
        storage[key] = WeakWriterBox(writer)
        if storage.count > 8 {
            storage = storage.filter { $0.value.value != nil }
        }
        return writer
    }
}

@ModelActor
actor SolidsCustomFoodWriter {
    func save(
        _ write: SolidsCustomFoodWrite,
        now: Date = Date()
    ) -> SolidsCustomFoodWriteResult {
        let cleanedName = SolidFoodSelection.cleanedName(write.name)
        let normalizedName = SolidFoodSelection.normalizedName(cleanedName)
        guard !normalizedName.isEmpty else {
            return SolidsCustomFoodWriteResult(error: "Enter a food name.")
        }

        let existingDescriptor = FetchDescriptor<SolidFoodCatalogItem>()
        let duplicate = ((try? modelContext.fetch(existingDescriptor)) ?? []).contains {
            $0.id != write.itemID && $0.normalizedName == normalizedName
        }
        guard !duplicate else {
            return SolidsCustomFoodWriteResult(error: "A custom food with this name already exists.")
        }

        let item: SolidFoodCatalogItem
        if let itemID = write.itemID {
            let descriptor = FetchDescriptor<SolidFoodCatalogItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            guard let existing = try? modelContext.fetch(descriptor).first else {
                return SolidsCustomFoodWriteResult(error: "This custom food is no longer available.")
            }
            item = existing
        } else {
            item = SolidFoodCatalogItem(name: cleanedName, createdAt: now, updatedAt: now)
            modelContext.insert(item)
        }

        if let photoDraft = write.photoDraft {
            if let currentPhotoID = item.photoAttachmentID {
                deletePhoto(id: currentPhotoID)
            }
            modelContext.insert(PhotoAttachment(
                id: photoDraft.id,
                profileID: nil,
                ownerKind: .solidFood,
                contentType: photoDraft.contentType,
                filename: photoDraft.filename,
                imageData: photoDraft.imageData,
                thumbnailData: photoDraft.thumbnailData,
                createdAt: photoDraft.createdAt,
                updatedAt: photoDraft.createdAt
            ))
            item.photoAttachmentID = photoDraft.id
        } else if write.removeExistingPhoto, let currentPhotoID = item.photoAttachmentID {
            deletePhoto(id: currentPhotoID)
            item.photoAttachmentID = nil
        }

        item.name = cleanedName
        item.normalizedName = normalizedName
        item.allergenIDs = write.allergenIDs
        item.minimumAgeMonths = write.minimumAgeMonths
        item.preparationNotes = write.preparationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.safetyNotes = write.safetyNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updatedAt = now

        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return SolidsCustomFoodWriteResult(itemID: item.id, name: item.name, error: nil)
        } catch {
            modelContext.rollback()
            return SolidsCustomFoodWriteResult(error: error.localizedDescription)
        }
    }

    func delete(itemID: UUID) -> String? {
        let descriptor = FetchDescriptor<SolidFoodCatalogItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        guard let item = try? modelContext.fetch(descriptor).first else { return nil }
        if let photoAttachmentID = item.photoAttachmentID {
            deletePhoto(id: photoAttachmentID)
        }
        modelContext.delete(item)
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }

    private func deletePhoto(id: UUID) {
        var descriptor = FetchDescriptor<PhotoAttachment>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let photo = try? modelContext.fetch(descriptor).first {
            modelContext.delete(photo)
        }
    }
}

struct SolidsMealPrepWrite: Sendable {
    var name: String
    var servings: Double
    var locationID: UUID
    var householdID: UUID
    var preparedDate: Date
    var notes: String
    var tags: String
}

@ModelActor
actor SolidsMealPrepWriter {
    func create(_ write: SolidsMealPrepWrite, now: Date = Date()) -> String? {
        let name = write.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = write.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = write.tags.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, write.servings >= 0 else { return "The meal prep item is invalid." }
        modelContext.insert(MealPrepItem(
            householdID: write.householdID,
            name: name,
            locationID: write.locationID,
            servingsTotal: write.servings,
            servingsRemaining: write.servings,
            servingUnit: .serving,
            preparedDate: write.preparedDate,
            notes: notes.isEmpty ? nil : notes,
            tagsJSON: tags.isEmpty ? nil : tags,
            createdAt: now,
            updatedAt: now
        ))
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }
}

@ModelActor
actor SolidsBackfillWriter {
    func backfill(profileID: UUID) async -> (count: Int, error: String?) {
        let feedRawValue = EventType.feed.rawValue
        let solidRawValue = FeedKind.solid.rawValue
        let eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && $0.typeRawValue == feedRawValue
                    && $0.feedKindRawValue == solidRawValue
            }
        )
        let currentEventCount = (try? modelContext.fetchCount(eventDescriptor)) ?? 0
        let completionKey = "solids.backfill.v2.\(profileID.uuidString).eventCount"
        let latestUpdateKey = "solids.backfill.v2.\(profileID.uuidString).latestUpdate"
        let defaults = UserDefaults.standard
        var latestDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && $0.typeRawValue == feedRawValue
                    && $0.feedKindRawValue == solidRawValue
            },
            sortBy: [SortDescriptor(\BabyEvent.updatedAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1
        let latestUpdate = (try? modelContext.fetch(latestDescriptor).first)?
            .updatedAt.timeIntervalSinceReferenceDate ?? 0

        func markBackfillComplete() {
            defaults.set(currentEventCount, forKey: completionKey)
            defaults.set(latestUpdate, forKey: latestUpdateKey)
        }

        if defaults.object(forKey: completionKey) != nil,
           defaults.integer(forKey: completionKey) == currentEventCount,
           defaults.object(forKey: latestUpdateKey) != nil,
           defaults.double(forKey: latestUpdateKey) == latestUpdate {
            return (0, nil)
        }
        let events = (try? modelContext.fetch(eventDescriptor)) ?? []
        guard !events.isEmpty else {
            markBackfillComplete()
            return (0, nil)
        }

        let itemDescriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        var storedItems = (try? modelContext.fetch(itemDescriptor)) ?? []
        let recordedEventIDs = Set(storedItems.map(\.eventID))
        let missingEvents = events.filter { !recordedEventIDs.contains($0.id) }
        guard !missingEvents.isEmpty else {
            markBackfillComplete()
            return (0, nil)
        }

        let customFoods = (try? modelContext.fetch(FetchDescriptor<SolidFoodCatalogItem>())) ?? []
        let customByName = customFoods.reduce(into: [String: SolidFoodCatalogItem]()) { result, food in
            if result[food.normalizedName] == nil { result[food.normalizedName] = food }
        }
        let progressDescriptor = FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        var progressByFoodID = Dictionary(uniqueKeysWithValues:
            ((try? modelContext.fetch(progressDescriptor)) ?? []).map { ($0.foodID, $0) }
        )
        let allergenDescriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        var allergenByID = Dictionary(uniqueKeysWithValues:
            ((try? modelContext.fetch(allergenDescriptor)) ?? []).map { ($0.allergenID, $0) }
        )
        let stateDescriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = (try? modelContext.fetch(stateDescriptor).first)
            ?? SolidsProfileState(profileID: profileID)
        if state.modelContext == nil { modelContext.insert(state) }
        state.isActivated = true
        state.startedAt = state.startedAt ?? missingEvents.map(\.updatedAt).min()

        for event in missingEvents {
            var details = event.solidFoodDetails
            if details.isEmpty {
                details = SolidFoodSelection.names(from: event.foodDescription).map { name in
                    let normalizedName = SolidFoodSelection.normalizedName(name)
                    let reference = SolidsReferenceCatalog.food(named: name)
                    let custom = customByName[normalizedName]
                    let foodID = reference?.id
                        ?? custom.map { "custom-\($0.id.uuidString.lowercased())" }
                        ?? "custom-\(Self.slug(name))"
                    return SolidFoodLogDetail(
                        foodID: foodID,
                        foodName: reference?.name ?? custom?.name ?? name,
                        allergenIDs: reference?.allergenIDs ?? custom?.allergenIDs ?? [],
                        confirmedAllergenPortionIDs: [],
                        preference: event.solidReaction ?? .unknown,
                        suspectedReaction: event.solidSensitivityObserved == true
                    )
                }
                event.solidFoodDetails = details
            }

            for detail in details {
                if detail.suspectedReaction || detail.followUp == .avoidPendingAdvice {
                    for allergenID in detail.allergenIDs {
                        allergenByID[allergenID]?.statusOverride = nil
                        allergenByID[allergenID]?.updatedAt = event.updatedAt
                    }
                }
                let item = SolidFoodEventItem(
                    eventID: event.id,
                    profileID: profileID,
                    foodID: detail.foodID,
                    foodNameSnapshot: detail.foodName,
                    allergenIDs: detail.allergenIDs,
                    confirmedAllergenPortionIDs: detail.confirmedAllergenPortionIDs,
                    reactionRawValue: detail.preference.rawValue,
                    servingAmount: detail.servingAmount ?? "",
                    notes: detail.notes ?? "",
                    suspectedReaction: detail.suspectedReaction,
                    symptoms: detail.symptoms,
                    severity: detail.severity,
                    onsetMinutes: detail.onsetMinutes,
                    durationMinutes: detail.durationMinutes,
                    responseNotes: detail.responseNotes,
                    followUp: detail.followUp,
                    createdAt: event.startDate,
                    updatedAt: event.updatedAt
                )
                modelContext.insert(item)
                storedItems.append(item)

                let record = progressByFoodID[detail.foodID]
                    ?? SolidFoodProgress(
                        profileID: profileID,
                        foodID: detail.foodID,
                        foodNameSnapshot: detail.foodName,
                        createdAt: event.updatedAt,
                        updatedAt: event.updatedAt
                    )
                if record.modelContext == nil { modelContext.insert(record) }
                progressByFoodID[detail.foodID] = record
                record.foodNameSnapshot = detail.foodName
                record.status = .tried
                let previousLastTriedAt = record.lastTriedAt
                record.exposureCount += 1
                record.firstTriedAt = min(record.firstTriedAt ?? event.startDate, event.startDate)
                record.lastTriedAt = max(previousLastTriedAt ?? event.startDate, event.startDate)
                if previousLastTriedAt.map({ $0 <= event.startDate }) ?? true {
                    record.lastReactionRawValue = detail.preference.rawValue
                }
                record.updatedAt = event.updatedAt
            }
        }

        let completedAt = missingEvents.map(\.updatedAt).max() ?? Date()
        state.updatedAt = completedAt
        let reminderSnapshots = reconcileAllergens(
            profileID: profileID,
            items: storedItems,
            allergenByID: &allergenByID,
            now: completedAt
        )
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
        } catch {
            modelContext.rollback()
            return (0, error.localizedDescription)
        }
        for snapshot in reminderSnapshots {
            await NotificationManager.shared.scheduleSolidAllergenReminder(snapshot: snapshot)
        }
        markBackfillComplete()
        return (missingEvents.count, nil)
    }

    private func reconcileAllergens(
        profileID: UUID,
        items: [SolidFoodEventItem],
        allergenByID: inout [String: SolidAllergenProgress],
        now: Date
    ) -> [SolidAllergenReminderSnapshot] {
        let recognizedIDs = Set(SolidsAllergen.allCases.map(\.rawValue))
        var itemsByAllergenID: [String: [SolidFoodEventItem]] = [:]
        for item in items {
            for allergenID in item.allergenIDs where recognizedIDs.contains(allergenID) {
                itemsByAllergenID[allergenID, default: []].append(item)
            }
        }
        var snapshots: [SolidAllergenReminderSnapshot] = []
        for allergen in SolidsAllergen.allCases {
            let matching = itemsByAllergenID[allergen.rawValue] ?? []
            guard !matching.isEmpty || allergenByID[allergen.rawValue] != nil else { continue }
            let record = allergenByID[allergen.rawValue]
                ?? SolidAllergenProgress(profileID: profileID, allergenID: allergen.rawValue)
            if record.modelContext == nil { modelContext.insert(record) }
            allergenByID[allergen.rawValue] = record
            var exposureByEventID: [UUID: Date] = [:]
            var confirmedByEventID: [UUID: Date] = [:]
            var hasAvoidance = false
            var hasReaction = false
            for item in matching {
                exposureByEventID[item.eventID] = max(
                    exposureByEventID[item.eventID] ?? .distantPast,
                    item.createdAt
                )
                if item.confirmsIntroductionPortion(for: allergen.rawValue) {
                    confirmedByEventID[item.eventID] = max(
                        confirmedByEventID[item.eventID] ?? .distantPast,
                        item.createdAt
                    )
                }
                hasAvoidance = hasAvoidance || item.followUp == .avoidPendingAdvice
                hasReaction = hasReaction || item.suspectedReaction
            }
            let confirmedDates = confirmedByEventID.values
            record.exposureMealCount = exposureByEventID.count
            record.introductionStep = min(3, confirmedDates.count)
            record.firstIntroducedAt = confirmedDates.min()
            record.lastExposureAt = exposureByEventID.values.max()
            if let override = record.statusOverride {
                record.status = override
            } else if hasAvoidance {
                record.status = .avoidPendingAdvice
            } else if hasReaction {
                record.status = .suspectedReaction
            } else if confirmedDates.count >= 3 {
                record.status = .tolerated
            } else if exposureByEventID.isEmpty {
                record.status = .notStarted
            } else {
                record.status = .introducing
            }
            switch record.status {
            case .tolerated:
                record.nextExposureDueAt = exposureByEventID.values.max().flatMap {
                    Calendar.current.date(byAdding: .day, value: 7, to: $0)
                }
            case .introducing:
                record.nextExposureDueAt = confirmedDates.max().flatMap {
                    Calendar.current.date(byAdding: .day, value: 7, to: $0)
                }
            case .notStarted, .suspectedReaction, .avoidPendingAdvice:
                record.nextExposureDueAt = nil
            }
            record.updatedAt = now
            snapshots.append(SolidAllergenReminderSnapshot(
                profileID: record.profileID,
                allergenID: record.allergenID,
                statusRawValue: record.statusRawValue,
                nextExposureDueAt: record.nextExposureDueAt,
                reminderEnabled: record.reminderEnabled
            ))
        }
        return snapshots
    }

    private static func slug(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

@ModelActor
actor SolidsShoppingListWriter {
    func addFoods(
        _ writes: [SolidsShoppingFoodWrite],
        listID: UUID,
        householdID: UUID,
        now: Date = Date()
    ) -> (count: Int, error: String?) {
        guard !writes.isEmpty else { return (0, nil) }
        let listDescriptor = FetchDescriptor<ShoppingList>(
            predicate: #Predicate { $0.id == listID && $0.householdID == householdID }
        )
        guard let list = try? modelContext.fetch(listDescriptor).first else {
            return (0, "The shopping list is no longer available.")
        }
        let itemDescriptor = FetchDescriptor<ShoppingListItem>(
            predicate: #Predicate { $0.shoppingListID == listID }
        )
        var existingItems = (try? modelContext.fetch(itemDescriptor)) ?? []
        let foodDescriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.householdID == householdID }
        )
        var canonicalByReferenceID: [String: UUID] = [:]
        for item in (try? modelContext.fetch(foodDescriptor)) ?? [] {
            if let referenceID = item.foodReferenceID,
               canonicalByReferenceID[referenceID] == nil {
                canonicalByReferenceID[referenceID] = item.id
            }
        }
        var changedCount = 0
        for write in writes {
            let normalizedName = SolidFoodSelection.normalizedName(write.foodName)
            if let existing = existingItems.first(where: {
                SolidFoodSelection.normalizedName($0.name) == normalizedName
            }) {
                if existing.isChecked {
                    existing.isChecked = false
                    existing.checkedAt = nil
                    existing.lastUncheckedAt = now
                    existing.updatedAt = now
                    changedCount += 1
                }
                continue
            }

            let canonicalID: UUID
            if let existingID = canonicalByReferenceID[write.foodID] {
                canonicalID = existingID
            } else {
                let aliasesJSON = (try? JSONEncoder().encode(write.aliases))
                    .flatMap { String(data: $0, encoding: .utf8) }
                let canonical = FoodItem(
                    householdID: householdID,
                    canonicalName: write.foodName,
                    foodReferenceID: write.foodID,
                    aliasesJSON: aliasesJSON,
                    createdAt: now,
                    updatedAt: now
                )
                modelContext.insert(canonical)
                canonicalID = canonical.id
                canonicalByReferenceID[write.foodID] = canonical.id
            }
            let nextOrder = (existingItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
            let item = ShoppingListItem(
                householdID: householdID,
                shoppingListID: listID,
                foodItemID: canonicalID,
                name: write.foodName,
                createdAt: now,
                updatedAt: now,
                sortOrder: nextOrder
            )
            modelContext.insert(item)
            existingItems.append(item)
            changedCount += 1
        }
        guard changedCount > 0 else { return (0, nil) }
        list.updatedAt = now
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return (changedCount, nil)
        } catch {
            modelContext.rollback()
            return (0, error.localizedDescription)
        }
    }
}

@ModelActor
actor SolidsProfileStateWriter {
    func activate(profileID: UUID, now: Date = Date()) -> String? {
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = (try? modelContext.fetch(descriptor).first)
            ?? SolidsProfileState(profileID: profileID)
        if state.modelContext == nil { modelContext.insert(state) }
        state.isActivated = true
        state.startedAt = state.startedAt ?? now
        state.updatedAt = now
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }
}

@ModelActor
actor SolidsPlanWriter {
    func saveEditorPlan(
        _ write: SolidsPlanEditorWrite,
        now: Date = Date()
    ) async -> SolidsPlanWriteResult {
        guard !write.foodIDs.isEmpty, write.foodIDs.count == write.foodNames.count else {
            return SolidsPlanWriteResult(planID: nil, error: "Choose at least one food.")
        }

        let plan: PlannedSolidMeal
        if let planID = write.planID {
            let profileID = write.profileID
            let descriptor = FetchDescriptor<PlannedSolidMeal>(
                predicate: #Predicate { $0.id == planID && $0.profileID == profileID }
            )
            guard let existing = try? modelContext.fetch(descriptor).first else {
                return SolidsPlanWriteResult(planID: nil, error: "The planned meal is no longer available.")
            }
            let foodSelectionChanged = Set(existing.foodIDs) != Set(write.foodIDs)
            existing.scheduledAt = write.scheduledAt
            if foodSelectionChanged || existing.recipeID == nil {
                existing.title = write.foodNames.joined(separator: " + ")
            }
            if foodSelectionChanged { existing.recipeID = nil }
            existing.foodIDs = write.foodIDs
            existing.foodNames = write.foodNames
            existing.notes = write.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.reminderEnabled = write.reminderEnabled
            existing.reminderOffsetMinutes = max(0, write.reminderOffsetMinutes)
            existing.updatedAt = now
            plan = existing
        } else {
            plan = makePlan(from: write, now: now)
            modelContext.insert(plan)
        }

        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
        } catch {
            modelContext.rollback()
            return SolidsPlanWriteResult(planID: nil, error: error.localizedDescription)
        }
        let snapshot = SolidMealReminderSnapshot(
            id: plan.id,
            profileID: plan.profileID,
            scheduledAt: plan.scheduledAt,
            title: plan.title,
            reminderEnabled: plan.reminderEnabled,
            reminderOffsetMinutes: plan.reminderOffsetMinutes,
            isCompleted: plan.isCompleted
        )
        // The local SwiftData save is the user-visible completion point. Updating
        // the system reminder can safely follow without keeping the editor open.
        Task {
            await NotificationManager.shared.scheduleSolidMealReminder(snapshot: snapshot)
        }
        return SolidsPlanWriteResult(planID: plan.id, error: nil)
    }

    func createPlans(
        _ writes: [SolidsPlanEditorWrite],
        now: Date = Date()
    ) async -> (count: Int, error: String?) {
        guard !writes.isEmpty else { return (0, nil) }
        guard writes.allSatisfy({ !$0.foodIDs.isEmpty && $0.foodIDs.count == $0.foodNames.count }) else {
            return (0, "Every planned meal needs at least one food.")
        }
        let plans = writes.map { makePlan(from: $0, now: now) }
        do {
            try modelContext.transaction {
                for plan in plans { modelContext.insert(plan) }
                try modelContext.save()
            }
            PersistenceService.recordLocalSave()
        } catch {
            modelContext.rollback()
            return (0, error.localizedDescription)
        }
        let reminderSnapshots = plans.map {
            SolidMealReminderSnapshot(
                id: $0.id,
                profileID: $0.profileID,
                scheduledAt: $0.scheduledAt,
                title: $0.title,
                reminderEnabled: $0.reminderEnabled,
                reminderOffsetMinutes: $0.reminderOffsetMinutes,
                isCompleted: $0.isCompleted
            )
        }
        Task {
            for snapshot in reminderSnapshots {
                await NotificationManager.shared.scheduleSolidMealReminder(snapshot: snapshot)
            }
        }
        return (plans.count, nil)
    }

    func deletePlans(_ planIDs: [UUID]) async -> String? {
        guard !planIDs.isEmpty else { return nil }
        let ids = Set(planIDs)
        let descriptor = FetchDescriptor<PlannedSolidMeal>()
        let matching = ((try? modelContext.fetch(descriptor)) ?? []).filter { ids.contains($0.id) }
        for plan in matching { modelContext.delete(plan) }
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
        for id in planIDs {
            await NotificationManager.shared.cancelSolidMealReminder(planID: id)
        }
        return nil
    }

    private func makePlan(from write: SolidsPlanEditorWrite, now: Date) -> PlannedSolidMeal {
        let cleanedTitle = write.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanedTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? write.foodNames.joined(separator: " + ")
        return PlannedSolidMeal(
            profileID: write.profileID,
            scheduledAt: write.scheduledAt,
            title: resolvedTitle,
            foodIDs: write.foodIDs,
            foodNames: write.foodNames,
            notes: write.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            recipeID: write.recipeID,
            isGuided: write.isGuided,
            guidedPosition: write.guidedPosition,
            allergenID: write.allergenID,
            allergenIntroductionStep: write.allergenIntroductionStep,
            allergenServingGuidance: write.allergenServingGuidance,
            allergenObservationMinutes: write.allergenObservationMinutes,
            reminderEnabled: write.reminderEnabled,
            reminderOffsetMinutes: max(0, write.reminderOffsetMinutes),
            createdAt: now,
            updatedAt: now
        )
    }
}

@ModelActor
actor SolidsGuidedPlanWriter {
    func buildJourney(
        profileID: UUID,
        startDate: Date,
        writes: [SolidsGuidedPlanWrite],
        now: Date = Date()
    ) -> (count: Int, error: String?) {
        guard !writes.isEmpty else { return (0, nil) }
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = (try? modelContext.fetch(descriptor).first)
            ?? SolidsProfileState(profileID: profileID)
        if state.modelContext == nil { modelContext.insert(state) }
        let plans = writes.map { write in
            PlannedSolidMeal(
                profileID: profileID,
                scheduledAt: write.scheduledAt,
                title: write.title,
                foodIDs: write.foodIDs,
                foodNames: write.foodNames,
                notes: write.notes,
                recipeID: write.recipeID,
                isGuided: true,
                guidedPosition: write.guidedPosition,
                allergenID: write.allergenID,
                allergenIntroductionStep: write.allergenIntroductionStep,
                allergenServingGuidance: write.allergenServingGuidance,
                allergenObservationMinutes: write.allergenObservationMinutes,
                createdAt: now,
                updatedAt: now
            )
        }
        state.isActivated = true
        state.startedAt = state.startedAt ?? now
        state.guidedStartDate = state.guidedStartDate ?? startDate
        state.updatedAt = now
        do {
            try modelContext.transaction {
                for plan in plans { modelContext.insert(plan) }
                try modelContext.save()
            }
            PersistenceService.recordLocalSave()
            return (plans.count, nil)
        } catch {
            modelContext.rollback()
            return (0, error.localizedDescription)
        }
    }

    func replacePlan(
        planID: UUID,
        profileID: UUID,
        write: SolidsGuidedPlanWrite,
        now: Date = Date()
    ) async -> String? {
        let descriptor = FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.id == planID && $0.profileID == profileID }
        )
        guard let plan = try? modelContext.fetch(descriptor).first else {
            return "The planned meal is no longer available."
        }
        plan.scheduledAt = write.scheduledAt
        plan.title = write.title
        plan.foodIDs = write.foodIDs
        plan.foodNames = write.foodNames
        plan.notes = write.notes
        plan.recipeID = write.recipeID
        plan.guidedPosition = write.guidedPosition
        plan.allergenID = write.allergenID
        plan.allergenIntroductionStep = write.allergenIntroductionStep
        plan.allergenServingGuidance = write.allergenServingGuidance
        plan.allergenObservationMinutes = write.allergenObservationMinutes
        plan.updatedAt = now
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
        let snapshot = SolidMealReminderSnapshot(
            id: plan.id,
            profileID: plan.profileID,
            scheduledAt: plan.scheduledAt,
            title: plan.title,
            reminderEnabled: plan.reminderEnabled,
            reminderOffsetMinutes: plan.reminderOffsetMinutes,
            isCompleted: plan.isCompleted
        )
        await NotificationManager.shared.scheduleSolidMealReminder(snapshot: snapshot)
        return nil
    }

    func shiftUpcomingPlans(
        profileID: UUID,
        onOrAfter date: Date,
        byDays days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> (count: Int, error: String?) {
        guard days != 0 else { return (0, nil) }
        let descriptor = FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let matching = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.isGuided && !$0.isCompleted && $0.scheduledAt >= date
        }
        guard !matching.isEmpty else { return (0, nil) }
        for plan in matching {
            plan.scheduledAt = calendar.date(byAdding: .day, value: days, to: plan.scheduledAt)
                ?? plan.scheduledAt
            plan.updatedAt = now
        }
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
        } catch {
            modelContext.rollback()
            return (0, error.localizedDescription)
        }
        let snapshots = matching.map {
            SolidMealReminderSnapshot(
                id: $0.id,
                profileID: $0.profileID,
                scheduledAt: $0.scheduledAt,
                title: $0.title,
                reminderEnabled: $0.reminderEnabled,
                reminderOffsetMinutes: $0.reminderOffsetMinutes,
                isCompleted: $0.isCompleted
            )
        }
        for snapshot in snapshots {
            await NotificationManager.shared.scheduleSolidMealReminder(snapshot: snapshot)
        }
        return (matching.count, nil)
    }
}

@ModelActor
actor SolidsFeedingSkillWriter {
    private var latestRevision = 0
    private var pendingWriteItem: DispatchWorkItem?

    /// Debounces rapid taps independently of the view lifecycle. The writer
    /// retains this task until it finishes, so navigating back immediately
    /// after checking a skill cannot discard the pending change.
    func schedulePersistence(
        profileID: UUID,
        completedSkillIDs: Set<String>,
        revision: Int
    ) {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        pendingWriteItem?.cancel()

        // A delayed Swift concurrency task keeps SwiftUI's interaction
        // transaction active even while it is sleeping. Use a background
        // dispatch item for the debounce, then enter the model actor only
        // when the coalesced write is ready.
        let writeItem = DispatchWorkItem { [self] in
            Task.detached(priority: .utility) { [self] in
                await persistScheduled(
                    profileID: profileID,
                    completedSkillIDs: completedSkillIDs,
                    revision: revision
                )
            }
        }
        pendingWriteItem = writeItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(150),
            execute: writeItem
        )
    }

    private func persistScheduled(
        profileID: UUID,
        completedSkillIDs: Set<String>,
        revision: Int
    ) async {
        guard latestRevision == revision else { return }
        if let errorDescription = persist(
            profileID: profileID,
            completedSkillIDs: completedSkillIDs,
            revision: revision
        ) {
            await PersistenceService.recordLocalSaveFailure(errorDescription)
        }
        guard latestRevision == revision else { return }
        pendingWriteItem = nil
    }

    /// Writes the complete observed-skill snapshot on this model actor so a
    /// CloudKit-backed context save can never block the tap that changed it.
    /// Revisions prevent a delayed older request from overwriting newer taps.
    func persist(
        profileID: UUID,
        completedSkillIDs: Set<String>,
        revision: Int,
        now: Date = Date()
    ) -> String? {
        guard revision >= latestRevision else { return nil }
        latestRevision = revision
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = (try? modelContext.fetch(descriptor).first)
            ?? SolidsProfileState(profileID: profileID)
        if state.modelContext == nil { modelContext.insert(state) }
        state.completedFeedingSkillIDs = completedSkillIDs.sorted()
        state.updatedAt = now
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }
}

@ModelActor
actor SolidsFoodProgressWriter {
    private var revisions: [String: Int] = [:]
    private var pendingWrites: [String: DispatchWorkItem] = [:]

    func scheduleStatus(
        _ status: SolidsFoodStatus,
        profileID: UUID,
        foodID: String,
        foodName: String,
        revision: Int
    ) {
        schedule(key: "status-\(profileID)-\(foodID)", revision: revision) { [self] revision in
            await persistStatus(
                status,
                profileID: profileID,
                foodID: foodID,
                foodName: foodName,
                revision: revision
            )
        }
    }

    func scheduleFavorite(
        _ isFavorite: Bool,
        profileID: UUID,
        foodID: String,
        foodName: String,
        revision: Int
    ) {
        schedule(key: "favorite-\(profileID)-\(foodID)", revision: revision) { [self] revision in
            await persistFavorite(
                isFavorite,
                profileID: profileID,
                foodID: foodID,
                foodName: foodName,
                revision: revision
            )
        }
    }

    func scheduleNotes(
        _ notes: String,
        profileID: UUID,
        foodID: String,
        foodName: String,
        revision: Int
    ) {
        schedule(key: "notes-\(profileID)-\(foodID)", revision: revision) { [self] revision in
            await persistNotes(
                notes,
                profileID: profileID,
                foodID: foodID,
                foodName: foodName,
                revision: revision
            )
        }
    }

    private func schedule(
        key: String,
        revision: Int,
        write: @escaping @Sendable (Int) async -> String?
    ) {
        guard revision >= (revisions[key] ?? 0) else { return }
        revisions[key] = revision
        pendingWrites[key]?.cancel()

        let writeItem = DispatchWorkItem { [self] in
            Task.detached(priority: .utility) { [self] in
                await persistScheduled(key: key, revision: revision, write: write)
            }
        }
        pendingWrites[key] = writeItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(150),
            execute: writeItem
        )
    }

    private func persistScheduled(
        key: String,
        revision: Int,
        write: @escaping @Sendable (Int) async -> String?
    ) async {
        guard revisions[key] == revision else { return }
        if let errorDescription = await write(revision) {
            await PersistenceService.recordLocalSaveFailure(errorDescription)
        }
        guard revisions[key] == revision else { return }
        pendingWrites[key] = nil
    }

    private func progress(
        profileID: UUID,
        foodID: String,
        foodName: String,
        now: Date
    ) -> SolidFoodProgress {
        let descriptor = FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.foodID == foodID }
        )
        let record = (try? modelContext.fetch(descriptor).first)
            ?? SolidFoodProgress(
                profileID: profileID,
                foodID: foodID,
                foodNameSnapshot: foodName,
                createdAt: now,
                updatedAt: now
            )
        if record.modelContext == nil { modelContext.insert(record) }
        record.foodNameSnapshot = foodName
        return record
    }

    private func persistStatus(
        _ status: SolidsFoodStatus,
        profileID: UUID,
        foodID: String,
        foodName: String,
        revision: Int,
        now: Date = Date()
    ) -> String? {
        let key = "status-\(profileID)-\(foodID)"
        guard revisions[key] == revision else { return nil }
        let record = progress(profileID: profileID, foodID: foodID, foodName: foodName, now: now)
        record.status = status
        record.updatedAt = now
        return save()
    }

    private func persistFavorite(
        _ isFavorite: Bool,
        profileID: UUID,
        foodID: String,
        foodName: String,
        revision: Int,
        now: Date = Date()
    ) -> String? {
        let key = "favorite-\(profileID)-\(foodID)"
        guard revisions[key] == revision else { return nil }
        let record = progress(profileID: profileID, foodID: foodID, foodName: foodName, now: now)
        record.isFavorite = isFavorite
        record.updatedAt = now
        return save()
    }

    private func persistNotes(
        _ notes: String,
        profileID: UUID,
        foodID: String,
        foodName: String,
        revision: Int,
        now: Date = Date()
    ) -> String? {
        let key = "notes-\(profileID)-\(foodID)"
        guard revisions[key] == revision else { return nil }
        let record = progress(profileID: profileID, foodID: foodID, foodName: foodName, now: now)
        record.notes = notes
        record.updatedAt = now
        return save()
    }

    private func save() -> String? {
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }
}

@ModelActor
actor SolidsRecipePreferenceWriter {
    private var revisions: [String: Int] = [:]

    func setFavorite(
        _ isFavorite: Bool,
        recipeID: String,
        profileID: UUID,
        revision: Int
    ) -> String? {
        guard accept(revision, key: "favorite-\(profileID)-\(recipeID)") else { return nil }
        let state = profileState(profileID: profileID)
        var values = Set(state.favoriteRecipeIDs)
        if isFavorite { values.insert(recipeID) } else { values.remove(recipeID) }
        state.favoriteRecipeIDs = values.sorted()
        state.updatedAt = Date()
        return save()
    }

    func setWantToTry(
        _ wantsToTry: Bool,
        recipeID: String,
        profileID: UUID,
        revision: Int
    ) -> String? {
        guard accept(revision, key: "want-\(profileID)-\(recipeID)") else { return nil }
        let state = profileState(profileID: profileID)
        var values = Set(state.wantToTryRecipeIDs)
        if wantsToTry { values.insert(recipeID) } else { values.remove(recipeID) }
        state.wantToTryRecipeIDs = values.sorted()
        state.updatedAt = Date()
        return save()
    }

    func setMembership(
        _ isIncluded: Bool,
        recipeID: String,
        collectionID: UUID,
        profileID: UUID,
        revision: Int
    ) -> String? {
        guard accept(revision, key: "collection-\(profileID)-\(recipeID)-\(collectionID)") else { return nil }
        let state = profileState(profileID: profileID)
        var collections = state.recipeCollections
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return nil }
        var recipeIDs = Set(collections[index].recipeIDs)
        if isIncluded { recipeIDs.insert(recipeID) } else { recipeIDs.remove(recipeID) }
        collections[index].recipeIDs = recipeIDs.sorted()
        collections[index].updatedAt = Date()
        state.recipeCollections = collections
        state.updatedAt = Date()
        return save()
    }

    func createCollection(
        id: UUID,
        name: String,
        initialRecipeIDs: [String] = [],
        profileID: UUID,
        now: Date = Date()
    ) -> String? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return "Enter a list name." }
        let state = profileState(profileID: profileID)
        var collections = state.recipeCollections
        guard !collections.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame
        }) else { return "A recipe list with that name already exists." }
        collections.append(SolidRecipeCollection(
            id: id,
            name: cleanedName,
            recipeIDs: initialRecipeIDs,
            createdAt: now,
            updatedAt: now
        ))
        state.recipeCollections = collections.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        state.updatedAt = now
        return save()
    }

    func renameCollection(
        id: UUID,
        name: String,
        profileID: UUID,
        now: Date = Date()
    ) -> String? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return "Enter a list name." }
        let state = profileState(profileID: profileID)
        var collections = state.recipeCollections
        guard !collections.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame
        }) else { return "A recipe list with that name already exists." }
        guard let index = collections.firstIndex(where: { $0.id == id }) else {
            return "The recipe list is no longer available."
        }
        collections[index].name = cleanedName
        collections[index].updatedAt = now
        state.recipeCollections = collections.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        state.updatedAt = now
        return save()
    }

    func deleteCollection(id: UUID, profileID: UUID, now: Date = Date()) -> String? {
        let state = profileState(profileID: profileID)
        var collections = state.recipeCollections
        let oldCount = collections.count
        collections.removeAll { $0.id == id }
        guard collections.count != oldCount else { return nil }
        state.recipeCollections = collections
        state.updatedAt = now
        return save()
    }

    private func profileState(profileID: UUID) -> SolidsProfileState {
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = (try? modelContext.fetch(descriptor).first)
            ?? SolidsProfileState(profileID: profileID, isActivated: true, startedAt: Date())
        if state.modelContext == nil { modelContext.insert(state) }
        return state
    }

    private func accept(_ revision: Int, key: String) -> Bool {
        guard revision >= (revisions[key] ?? 0) else { return false }
        revisions[key] = revision
        return true
    }

    private func save() -> String? {
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }
}

@ModelActor
actor SolidsAllergenProgressWriter {
    private var revisions: [String: Int] = [:]

    func setStatus(
        _ status: SolidAllergenStatus,
        allergenID: String,
        profileID: UUID,
        revision: Int
    ) async -> String? {
        guard accept(revision, key: "status-\(profileID)-\(allergenID)") else { return nil }
        let record = progress(profileID: profileID, allergenID: allergenID)
        record.status = status
        record.statusOverride = status
        record.updatedAt = Date()
        return await saveAndRefreshReminder(record)
    }

    func setNotes(
        _ notes: String,
        allergenID: String,
        profileID: UUID,
        revision: Int
    ) -> String? {
        guard accept(revision, key: "notes-\(profileID)-\(allergenID)") else { return nil }
        let record = progress(profileID: profileID, allergenID: allergenID)
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = Date()
        return save()
    }

    func setReminder(
        _ enabled: Bool,
        allergenID: String,
        profileID: UUID,
        revision: Int
    ) async -> String? {
        guard accept(revision, key: "reminder-\(profileID)-\(allergenID)") else { return nil }
        let record = progress(profileID: profileID, allergenID: allergenID)
        record.reminderEnabled = enabled
        record.updatedAt = Date()
        return await saveAndRefreshReminder(record)
    }

    func clearStatusOverride(
        allergenID: String,
        profileID: UUID,
        revision: Int,
        now: Date = Date()
    ) async -> String? {
        guard accept(revision, key: "status-\(profileID)-\(allergenID)") else { return nil }
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.allergenID == allergenID }
        )
        guard let record = try? modelContext.fetch(descriptor).first else { return nil }
        let itemDescriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let matching = ((try? modelContext.fetch(itemDescriptor)) ?? []).filter {
            $0.allergenIDs.contains(allergenID)
        }
        var latestExposureByEventID: [UUID: Date] = [:]
        var latestConfirmedExposureByEventID: [UUID: Date] = [:]
        var hasAvoidance = false
        var hasReaction = false
        for item in matching {
            if item.createdAt > (latestExposureByEventID[item.eventID] ?? .distantPast) {
                latestExposureByEventID[item.eventID] = item.createdAt
            }
            if item.confirmsIntroductionPortion(for: allergenID),
               item.createdAt > (latestConfirmedExposureByEventID[item.eventID] ?? .distantPast) {
                latestConfirmedExposureByEventID[item.eventID] = item.createdAt
            }
            hasAvoidance = hasAvoidance || item.followUp == .avoidPendingAdvice
            hasReaction = hasReaction || item.suspectedReaction
        }
        let confirmedDates = latestConfirmedExposureByEventID.values
        record.statusOverride = nil
        record.exposureMealCount = latestExposureByEventID.count
        record.introductionStep = min(3, confirmedDates.count)
        record.firstIntroducedAt = confirmedDates.min()
        record.lastExposureAt = latestExposureByEventID.values.max()
        if hasAvoidance {
            record.status = .avoidPendingAdvice
        } else if hasReaction {
            record.status = .suspectedReaction
        } else if confirmedDates.count >= 3 {
            record.status = .tolerated
        } else if latestExposureByEventID.isEmpty {
            record.status = .notStarted
        } else {
            record.status = .introducing
        }
        let rotationBase: Date?
        switch record.status {
        case .tolerated:
            rotationBase = latestExposureByEventID.values.max()
        case .introducing:
            rotationBase = confirmedDates.max()
        case .notStarted, .suspectedReaction, .avoidPendingAdvice:
            rotationBase = nil
        }
        record.nextExposureDueAt = rotationBase.flatMap {
            Calendar.current.date(byAdding: .day, value: 7, to: $0)
        }
        record.updatedAt = now
        return await saveAndRefreshReminder(record)
    }

    private func progress(profileID: UUID, allergenID: String) -> SolidAllergenProgress {
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.allergenID == allergenID }
        )
        let record = (try? modelContext.fetch(descriptor).first)
            ?? SolidAllergenProgress(profileID: profileID, allergenID: allergenID)
        if record.modelContext == nil { modelContext.insert(record) }
        return record
    }

    private func accept(_ revision: Int, key: String) -> Bool {
        guard revision >= (revisions[key] ?? 0) else { return false }
        revisions[key] = revision
        return true
    }

    private func saveAndRefreshReminder(_ record: SolidAllergenProgress) async -> String? {
        let snapshot = SolidAllergenReminderSnapshot(
            profileID: record.profileID,
            allergenID: record.allergenID,
            statusRawValue: record.statusRawValue,
            nextExposureDueAt: record.nextExposureDueAt,
            reminderEnabled: record.reminderEnabled
        )
        if let error = save() { return error }
        await NotificationManager.shared.scheduleSolidAllergenReminder(snapshot: snapshot)
        return nil
    }

    private func save() -> String? {
        do {
            try modelContext.save()
            PersistenceService.recordLocalSave()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }
}

enum SolidsAccessLevel: Equatable {
    case hidden
    case readinessPreview
    case full
}

@MainActor
enum SolidsTrackingService {
    private static var pendingAllergenReconciliationTasks: [UUID: Task<Void, Never>] = [:]
    static func accessLevel(
        for profile: BabyProfile?,
        events: [BabyEvent],
        state: SolidsProfileState?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SolidsAccessLevel {
        guard let profile, profile.profileType == .child else { return .hidden }
        let hasSolidHistory = events.contains {
            $0.profileID == profile.id && $0.type == .feed && $0.feedKind == .solid
        }
        if hasSolidHistory || state?.isActivated == true { return .full }
        let months = calendar.dateComponents([.month], from: profile.birthDate, to: now).month ?? 0
        if months < 4 { return .hidden }
        if months < 6 { return .readinessPreview }
        return .full
    }

    static func ageMonths(
        for profile: BabyProfile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        max(0, calendar.dateComponents([.month], from: profile.birthDate, to: now).month ?? 0)
    }

    @discardableResult
    static func activate(
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date(),
        persist: Bool = true
    ) -> SolidsProfileState {
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = existingState
            ?? (try? context.fetch(descriptor).first)
            ?? SolidsProfileState(profileID: profileID)
        let accessChanged = state.isActivated == false
        if state.modelContext == nil { context.insert(state) }
        state.isActivated = true
        state.startedAt = state.startedAt ?? now
        state.updatedAt = now
        if persist { _ = PersistenceService.save(context: context) }
        if accessChanged { SystemIntegrationReconciler.requestReconciliation() }
        return state
    }

    static func setStatus(
        _ status: SolidsFoodStatus,
        food: SolidsReferenceFood,
        profileID: UUID,
        progress: [SolidFoodProgress],
        context: ModelContext,
        now: Date = Date()
    ) {
        setStatus(
            status,
            foodID: food.id,
            foodName: food.name,
            profileID: profileID,
            progress: progress,
            context: context,
            now: now
        )
    }

    static func setStatus(
        _ status: SolidsFoodStatus,
        foodID: String,
        foodName: String,
        profileID: UUID,
        progress: [SolidFoodProgress],
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.foodID == foodID }
        )
        let record = progress.first { $0.profileID == profileID && $0.foodID == foodID }
            ?? (try? context.fetch(descriptor).first)
            ?? SolidFoodProgress(
                profileID: profileID,
                foodID: foodID,
                foodNameSnapshot: foodName,
                createdAt: now,
                updatedAt: now
            )
        if record.modelContext == nil { context.insert(record) }
        record.status = status
        record.foodNameSnapshot = foodName
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func updateFoodNotes(
        foodID: String,
        foodName: String,
        profileID: UUID,
        notes: String,
        progress: [SolidFoodProgress],
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.foodID == foodID }
        )
        let record = progress.first { $0.profileID == profileID && $0.foodID == foodID }
            ?? (try? context.fetch(descriptor).first)
            ?? SolidFoodProgress(
                profileID: profileID,
                foodID: foodID,
                foodNameSnapshot: foodName,
                createdAt: now,
                updatedAt: now
            )
        if record.modelContext == nil { context.insert(record) }
        record.foodNameSnapshot = foodName
        record.notes = notes
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func toggleFavorite(
        food: SolidsReferenceFood,
        profileID: UUID,
        progress: [SolidFoodProgress],
        context: ModelContext,
        now: Date = Date()
    ) {
        toggleFavorite(
            foodID: food.id,
            foodName: food.name,
            profileID: profileID,
            progress: progress,
            context: context,
            now: now
        )
    }

    static func toggleFavorite(
        foodID: String,
        foodName: String,
        profileID: UUID,
        progress: [SolidFoodProgress],
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.foodID == foodID }
        )
        let record = progress.first { $0.profileID == profileID && $0.foodID == foodID }
            ?? (try? context.fetch(descriptor).first)
            ?? SolidFoodProgress(
                profileID: profileID,
                foodID: foodID,
                foodNameSnapshot: foodName,
                createdAt: now,
                updatedAt: now
            )
        if record.modelContext == nil { context.insert(record) }
        record.isFavorite.toggle()
        record.foodNameSnapshot = foodName
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func toggleRecipeFavorite(
        recipeID: String,
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) {
        let state = activate(
            profileID: profileID,
            existingState: existingState,
            context: context,
            now: now,
            persist: false
        )
        var values = Set(state.favoriteRecipeIDs)
        if !values.insert(recipeID).inserted { values.remove(recipeID) }
        state.favoriteRecipeIDs = values.sorted()
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func startGuidedPath(
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        startDate: Date? = nil,
        now: Date = Date()
    ) {
        let state = activate(
            profileID: profileID,
            existingState: existingState,
            context: context,
            now: now,
            persist: false
        )
        state.guidedStartDate = state.guidedStartDate ?? startDate ?? now
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func toggleFeedingSkill(
        _ skill: SolidsFeedingSkill,
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = existingState
            ?? (try? context.fetch(descriptor).first)
            ?? SolidsProfileState(profileID: profileID)
        if state.modelContext == nil { context.insert(state) }
        var completed = Set(state.completedFeedingSkillIDs)
        if !completed.insert(skill.rawValue).inserted { completed.remove(skill.rawValue) }
        state.completedFeedingSkillIDs = completed.sorted()
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func guidedSuggestions(
        for profile: BabyProfile,
        progress: [SolidFoodProgress],
        eventItems: [SolidFoodEventItem],
        allergenProgress: [SolidAllergenProgress],
        plans: [PlannedSolidMeal],
        completedSkillIDs: Set<String> = [],
        startingAt startDate: Date = Date(),
        count: Int = 7,
        calendar: Calendar = .current
    ) -> [SolidsGuidedMealSuggestion] {
        guidedSuggestions(from: guidedSuggestionSnapshot(
            for: profile,
            progress: progress,
            eventItems: eventItems,
            allergenProgress: allergenProgress,
            plans: plans,
            completedSkillIDs: completedSkillIDs,
            startingAt: startDate,
            count: count,
            calendar: calendar
        ))
    }

    static func guidedSuggestionSnapshot(
        for profile: BabyProfile,
        progress: [SolidFoodProgress],
        eventItems: [SolidFoodEventItem],
        allergenProgress: [SolidAllergenProgress],
        plans: [PlannedSolidMeal],
        completedSkillIDs: Set<String> = [],
        startingAt startDate: Date = Date(),
        count: Int = 7,
        calendar: Calendar = .current
    ) -> SolidsGuidedSuggestionSnapshot {
        let profileID = profile.id
        let scopedItems = eventItems.filter { $0.profileID == profileID }
        let triedFoodIDs = Set(progress.lazy.filter {
            $0.profileID == profileID && $0.status == .tried
        }.map(\.foodID))
        let plannedFoodIDs = Set(plans.lazy.filter {
            $0.profileID == profileID && !$0.isCompleted
        }.flatMap(\.foodIDs))
        let blockedAllergenIDs = Set(
            allergenProgress.lazy.filter {
                $0.profileID == profileID
                    && ($0.status == .suspectedReaction || $0.status == .avoidPendingAdvice)
            }.map(\.allergenID)
        ).union(scopedItems.filter(\.suspectedReaction).flatMap(\.allergenIDs))
        let toleratedAllergenIDs = Set(allergenProgress.lazy.filter {
            $0.profileID == profileID && $0.status == .tolerated
        }.map(\.allergenID))
        var confirmedEventIDsByAllergen: [String: Set<UUID>] = [:]
        for item in scopedItems {
            for allergenID in item.allergenIDs where item.confirmsIntroductionPortion(for: allergenID) {
                confirmedEventIDsByAllergen[allergenID, default: []].insert(item.eventID)
            }
        }
        var plannedExposureStepByAllergen: [String: Int] = [:]
        for plan in plans where plan.profileID == profileID && !plan.isCompleted {
            guard let allergenID = plan.allergenID,
                  let step = plan.allergenIntroductionStep else { continue }
            plannedExposureStepByAllergen[allergenID] = max(
                plannedExposureStepByAllergen[allergenID] ?? 0,
                step
            )
        }
        return SolidsGuidedSuggestionSnapshot(
            isChild: profile.profileType == .child,
            birthDate: profile.birthDate,
            triedFoodIDs: triedFoodIDs,
            plannedFoodIDs: plannedFoodIDs,
            blockedAllergenIDs: blockedAllergenIDs,
            toleratedAllergenIDs: toleratedAllergenIDs,
            confirmedExposureCountByAllergen: confirmedEventIDsByAllergen.mapValues(\.count),
            plannedExposureStepByAllergen: plannedExposureStepByAllergen,
            completedSkillIDs: completedSkillIDs,
            startDate: startDate,
            count: count,
            calendar: calendar
        )
    }

    nonisolated static func guidedSuggestions(
        from snapshot: SolidsGuidedSuggestionSnapshot
    ) -> [SolidsGuidedMealSuggestion] {
        guard snapshot.isChild, snapshot.count > 0 else { return [] }
        // `count` is the number of new foods to plan, not the number of meals.
        // The returned journey can be longer because the opening foods and
        // allergen introductions deliberately include familiar repeats.
        let triedIDs = snapshot.triedFoodIDs
        let blockedAllergens = snapshot.blockedAllergenIDs
        let toleratedAllergens = snapshot.toleratedAllergenIDs
        let calendar = snapshot.calendar
        let startDate = snapshot.startDate
        let candidatePool = SolidsReferenceCatalog.guidedCandidateFoods
        let eligibleCandidatePool = candidatePool.filter {
            $0.isEligibleForGuidedPath
                && $0.possibleAllergenIDs.isEmpty
                && Set($0.allergenIDs).isDisjoint(with: blockedAllergens)
        }
        var remainingNewFoods = eligibleCandidatePool.filter {
            !triedIDs.contains($0.id) && !snapshot.plannedFoodIDs.contains($0.id)
        }
        var allergenCounts = Dictionary(uniqueKeysWithValues: SolidsAllergen.allCases.map {
            let confirmedCount = snapshot.confirmedExposureCountByAllergen[$0.rawValue] ?? 0
            let plannedStep = snapshot.plannedExposureStepByAllergen[$0.rawValue] ?? 0
            return ($0.rawValue, max(confirmedCount, plannedStep))
        })
        var completedAllergenIDs = toleratedAllergens.union(
            allergenCounts.compactMap { $0.value >= 3 ? $0.key : nil }
        )
        var familiarFoodIDs = triedIDs.union(snapshot.plannedFoodIDs)
        var newlyPlannedFoodIDs = Set<String>()
        var pendingFoundationRepeat: SolidsReferenceFood?
        var activeAllergenID = guidedAllergenPriority.map(\.rawValue).first {
            !blockedAllergens.contains($0)
                && !completedAllergenIDs.contains($0)
                && (allergenCounts[$0] ?? 0) > 0
                && (allergenCounts[$0] ?? 0) < 3
        }
        var activeAllergenFood: SolidsReferenceFood?
        var unavailableAllergenIDs = Set<String>()
        var newFoodsSinceAllergenSeries = 2
        var newFoodCount = 0
        var dayOffset = 0
        var results: [SolidsGuidedMealSuggestion] = []

        func makeSuggestion(
            primary: SolidsReferenceFood,
            foods: [SolidsReferenceFood],
            recipe: SolidsReferenceRecipe?,
            kind: SolidsGuidedMealKind,
            allergenID: String? = nil,
            introductionStep: Int? = nil,
            scheduledDay: Date,
            age: Int,
            knownFoodCount: Int
        ) -> SolidsGuidedMealSuggestion {
            let scheduledAt = calendar.date(
                bySettingHour: 11,
                minute: 30,
                second: 0,
                of: scheduledDay
            ) ?? scheduledDay
            let servingGuidance: String?
            if let allergenID,
               let allergen = SolidsAllergen(rawValue: allergenID),
               let introductionStep {
                servingGuidance = SolidsReferenceCatalog.introductionServingGuidance(
                    for: allergen,
                    step: introductionStep
                )
            } else {
                servingGuidance = nil
            }
            let basePreparation = personalizedPreparationNotes(
                for: primary,
                ageMonths: age,
                completedSkillIDs: snapshot.completedSkillIDs
            )
            let preparationNotes = kind == .familiarRepeat
                ? "Repeat this familiar food in the same safe form. \(basePreparation)"
                : basePreparation
            return SolidsGuidedMealSuggestion(
                dayOffset: dayOffset,
                scheduledAt: scheduledAt,
                foods: foods,
                recipe: recipe,
                stage: .stage(forTriedCount: min(100, knownFoodCount)),
                kind: kind,
                allergenID: allergenID,
                allergenIntroductionStep: introductionStep,
                allergenServingGuidance: servingGuidance,
                preparationNotes: preparationNotes
            )
        }

        let maximumMealCount = snapshot.count + (SolidsAllergen.allCases.count * 3) + 8
        while (newFoodCount < snapshot.count
               || pendingFoundationRepeat != nil
               || activeAllergenID != nil)
              && results.count < maximumMealCount {
            let scheduledDay = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
            let age = max(
                0,
                calendar.dateComponents([.month], from: snapshot.birthDate, to: scheduledDay).month ?? 0
            )
            let knownFoodCount = triedIDs
                .union(snapshot.plannedFoodIDs)
                .union(newlyPlannedFoodIDs)
                .count

            if let repeatFood = pendingFoundationRepeat {
                results.append(makeSuggestion(
                    primary: repeatFood,
                    foods: [repeatFood],
                    recipe: nil,
                    kind: .familiarRepeat,
                    scheduledDay: scheduledDay,
                    age: age,
                    knownFoodCount: knownFoodCount
                ))
                pendingFoundationRepeat = nil
                dayOffset += 1
                continue
            }

            if let allergenID = activeAllergenID {
                let carrier = activeAllergenFood ?? guidedAllergenCarrier(
                    for: allergenID,
                    candidates: eligibleCandidatePool,
                    familiarFoodIDs: familiarFoodIDs,
                    ageMonths: age
                )
                guard let carrier else {
                    unavailableAllergenIDs.insert(allergenID)
                    activeAllergenID = nil
                    activeAllergenFood = nil
                    continue
                }
                activeAllergenFood = carrier
                let isNewFood = !familiarFoodIDs.contains(carrier.id)
                if isNewFood && newFoodCount >= snapshot.count {
                    activeAllergenID = nil
                    activeAllergenFood = nil
                    break
                }
                let introductionStep = min(3, (allergenCounts[allergenID] ?? 0) + 1)
                results.append(makeSuggestion(
                    primary: carrier,
                    foods: [carrier],
                    recipe: nil,
                    kind: isNewFood ? .firstTaste : .familiarRepeat,
                    allergenID: allergenID,
                    introductionStep: introductionStep,
                    scheduledDay: scheduledDay,
                    age: age,
                    knownFoodCount: knownFoodCount
                ))
                if isNewFood {
                    newFoodCount += 1
                    newlyPlannedFoodIDs.insert(carrier.id)
                    remainingNewFoods.removeAll { $0.id == carrier.id }
                }
                familiarFoodIDs.insert(carrier.id)
                allergenCounts[allergenID] = introductionStep
                if introductionStep >= 3 {
                    completedAllergenIDs.insert(allergenID)
                    activeAllergenID = nil
                    activeAllergenFood = nil
                    newFoodsSinceAllergenSeries = 0
                }
                dayOffset += 1
                continue
            }

            let familiarFoundationFoods = eligibleCandidatePool.filter {
                familiarFoodIDs.contains($0.id)
                    && $0.minimumAgeMonths <= age
                    && $0.allergenIDs.isEmpty
            }
            if familiarFoundationFoods.count < 3, newFoodCount < snapshot.count {
                let ageEligibleFoundationFoods = remainingNewFoods.filter {
                    $0.minimumAgeMonths <= age && $0.allergenIDs.isEmpty
                }
                let familiarFoundationHasIron = familiarFoundationFoods.contains(where: \.isIronRich)
                let openingFoods = guidedOpeningFoodNames.compactMap(SolidsReferenceCatalog.food(named:))
                let primary: SolidsReferenceFood?
                if !familiarFoundationHasIron && !familiarFoundationFoods.isEmpty {
                    primary = openingFoods.first { openingFood in
                        openingFood.isIronRich && ageEligibleFoundationFoods.contains {
                            $0.id == openingFood.id
                        }
                    } ?? ageEligibleFoundationFoods.first(where: \.isIronRich)
                } else {
                    primary = openingFoods.first { openingFood in
                        ageEligibleFoundationFoods.contains { $0.id == openingFood.id }
                    } ?? ageEligibleFoundationFoods.first
                }
                guard let primary else { break }
                results.append(makeSuggestion(
                    primary: primary,
                    foods: [primary],
                    recipe: nil,
                    kind: .firstTaste,
                    scheduledDay: scheduledDay,
                    age: age,
                    knownFoodCount: knownFoodCount
                ))
                newFoodCount += 1
                newlyPlannedFoodIDs.insert(primary.id)
                familiarFoodIDs.insert(primary.id)
                remainingNewFoods.removeAll { $0.id == primary.id }
                pendingFoundationRepeat = primary
                dayOffset += 1
                continue
            }

            if newFoodCount >= snapshot.count { break }

            if newFoodsSinceAllergenSeries >= 2 {
                var nextAllergen: (id: String, food: SolidsReferenceFood)?
                for allergen in guidedAllergenPriority {
                    let allergenID = allergen.rawValue
                    guard !blockedAllergens.contains(allergenID),
                          !completedAllergenIDs.contains(allergenID),
                          !unavailableAllergenIDs.contains(allergenID),
                          (allergenCounts[allergenID] ?? 0) < 3 else { continue }
                    guard let carrier = guidedAllergenCarrier(
                        for: allergenID,
                        candidates: eligibleCandidatePool,
                        familiarFoodIDs: familiarFoodIDs,
                        ageMonths: age
                    ) else {
                        unavailableAllergenIDs.insert(allergenID)
                        continue
                    }
                    nextAllergen = (allergenID, carrier)
                    break
                }
                if let nextAllergen {
                    activeAllergenID = nextAllergen.id
                    activeAllergenFood = nextAllergen.food
                    continue
                }
            }

            let permittedRecipeAllergens = toleratedAllergens
            let ageEligibleNewFoods = remainingNewFoods.filter { food in
                food.minimumAgeMonths <= age
                    && (food.allergenIDs.isEmpty
                        || Set(food.allergenIDs).isSubset(of: toleratedAllergens))
            }
            guard let primary = ageEligibleNewFoods.first else {
                if newFoodsSinceAllergenSeries < 2 {
                    newFoodsSinceAllergenSeries = 2
                    continue
                }
                break
            }
            let recipe = knownFoodCount >= 5 ? bestRecipe(
                containing: primary,
                ageMonths: age,
                blockedAllergens: blockedAllergens,
                permittedAllergens: permittedRecipeAllergens,
                familiarFoodIDs: familiarFoodIDs
            ) : nil
            let mealFoods: [SolidsReferenceFood]
            if let recipe {
                let recipeFoods = recipe.foodNames.compactMap(SolidsReferenceCatalog.food(named:))
                mealFoods = [primary] + recipeFoods.filter { $0.id != primary.id }
            } else {
                mealFoods = [primary]
            }
            results.append(makeSuggestion(
                primary: primary,
                foods: mealFoods,
                recipe: recipe,
                kind: recipe == nil ? .firstTaste : .recipe,
                scheduledDay: scheduledDay,
                age: age,
                knownFoodCount: knownFoodCount
            ))
            newFoodCount += 1
            newlyPlannedFoodIDs.insert(primary.id)
            familiarFoodIDs.insert(primary.id)
            remainingNewFoods.removeAll { $0.id == primary.id }
            if primary.allergenIDs.isEmpty {
                newFoodsSinceAllergenSeries += 1
            }
            dayOffset += 1
        }
        return results
    }

    /// Re-personalizes already selected meals without repeating the much more
    /// expensive food, recipe, and allergen planning pass.
    static func applyingFeedingSkills(
        to suggestions: [SolidsGuidedMealSuggestion],
        for profile: BabyProfile,
        completedSkillIDs: Set<String>,
        calendar: Calendar = .current
    ) -> [SolidsGuidedMealSuggestion] {
        suggestions.map { suggestion in
            var updated = suggestion
            updated.preparationNotes = preparationNotes(
                for: suggestion,
                profile: profile,
                completedSkillIDs: completedSkillIDs,
                calendar: calendar
            )
            return updated
        }
    }

    static func preparationNotes(
        for suggestion: SolidsGuidedMealSuggestion,
        profile: BabyProfile,
        completedSkillIDs: Set<String>,
        calendar: Calendar = .current
    ) -> String {
        guard let primaryFood = suggestion.foods.first else {
            return suggestion.preparationNotes
        }
        let age = ageMonths(
            for: profile,
            now: suggestion.scheduledAt,
            calendar: calendar
        )
        return personalizedPreparationNotes(
            for: primaryFood,
            ageMonths: age,
            completedSkillIDs: completedSkillIDs
        )
    }

    @discardableResult
    static func buildGuidedPlan(
        from suggestions: [SolidsGuidedMealSuggestion],
        profileID: UUID,
        startingPosition: Int,
        context: ModelContext,
        now: Date = Date()
    ) -> [PlannedSolidMeal] {
        guard !suggestions.isEmpty else { return [] }
        let created = suggestions.map { suggestion in
            let allergenNote = suggestion.allergenID.flatMap(SolidsAllergen.init(rawValue:))
                .map { "Allergen rotation: \($0.displayName). " } ?? ""
            let names = suggestion.foods.map(\.name)
            let plan = PlannedSolidMeal(
                profileID: profileID,
                scheduledAt: suggestion.scheduledAt,
                title: suggestion.recipe?.title ?? names.joined(separator: " + "),
                foodIDs: suggestion.foods.map(\.id),
                foodNames: names,
                notes: "\(allergenNote)\(suggestion.stage.title): \(suggestion.stage.skill). \(suggestion.preparationNotes)",
                recipeID: suggestion.recipe?.id,
                isGuided: true,
                guidedPosition: startingPosition + suggestion.dayOffset,
                allergenID: suggestion.allergenID,
                allergenIntroductionStep: suggestion.allergenIntroductionStep,
                allergenServingGuidance: suggestion.allergenServingGuidance,
                allergenObservationMinutes: suggestion.allergenIntroductionStep == 1 ? 10 : nil,
                createdAt: now,
                updatedAt: now
            )
            return plan
        }
        do {
            try context.transaction {
                for plan in created { context.insert(plan) }
                try context.save()
            }
        } catch {
            return []
        }
        return created
    }

    static func replaceGuidedPlan(
        _ plan: PlannedSolidMeal,
        with suggestion: SolidsGuidedMealSuggestion,
        context: ModelContext,
        now: Date = Date()
    ) {
        do {
            try context.transaction {
                plan.title = suggestion.recipe?.title ?? suggestion.foods.map(\.name).joined(separator: " + ")
                plan.foodIDs = suggestion.foods.map(\.id)
                plan.foodNames = suggestion.foods.map(\.name)
                plan.recipeID = suggestion.recipe?.id
                let allergenNote = suggestion.allergenID.flatMap(SolidsAllergen.init(rawValue:))
                    .map { "Allergen rotation: \($0.displayName). " } ?? ""
                plan.notes = "\(allergenNote)\(suggestion.stage.title): \(suggestion.stage.skill). \(suggestion.preparationNotes)"
                plan.allergenID = suggestion.allergenID
                plan.allergenIntroductionStep = suggestion.allergenIntroductionStep
                plan.allergenServingGuidance = suggestion.allergenServingGuidance
                plan.allergenObservationMinutes = suggestion.allergenIntroductionStep == 1 ? 10 : nil
                plan.updatedAt = now
                try context.save()
            }
        } catch { return }
        let reminder = SolidMealReminderSnapshot(plan: plan)
        Task { await NotificationManager.shared.scheduleSolidMealReminder(snapshot: reminder) }
    }

    static func shiftUpcomingGuidedPlans(
        profileID: UUID,
        onOrAfter date: Date,
        byDays days: Int,
        plans: [PlannedSolidMeal],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard days != 0 else { return }
        let matching = plans.filter {
            $0.profileID == profileID && $0.isGuided && !$0.isCompleted && $0.scheduledAt >= date
        }
        do {
            try context.transaction {
                for plan in matching {
                    plan.scheduledAt = calendar.date(byAdding: .day, value: days, to: plan.scheduledAt)
                        ?? plan.scheduledAt
                    plan.updatedAt = now
                }
                try context.save()
            }
        } catch { return }
        for reminder in matching.map(SolidMealReminderSnapshot.init(plan:)) {
            Task { await NotificationManager.shared.scheduleSolidMealReminder(snapshot: reminder) }
        }
    }

    static func recommendedRecipes(
        for allergen: SolidsAllergen,
        ageMonths: Int,
        introducedAllergenIDs: Set<String> = []
    ) -> [SolidsReferenceRecipe] {
        SolidsReferenceCatalog.recipes(containingAllergenID: allergen.rawValue).filter {
            $0.minimumAgeMonths <= ageMonths
                && $0.allergenIDs.allSatisfy {
                    $0 == allergen.rawValue || introducedAllergenIDs.contains($0)
                }
        }.prefix(8).map { $0 }
    }

    static func allergenPlanWrites(
        for allergen: SolidsAllergen,
        profile: BabyProfile,
        progress: SolidAllergenProgress?,
        allProgress: [SolidAllergenProgress],
        existingPlans: [PlannedSolidMeal],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SolidsPlanEditorWrite] {
        guard profile.profileType == .child,
              progress?.status != .suspectedReaction,
              progress?.status != .avoidPendingAdvice else { return [] }
        let toleratedIDs = Set(allProgress.filter {
            $0.profileID == profile.id && $0.status == .tolerated
        }.map(\.allergenID))
        guard let recipe = recommendedRecipes(
            for: allergen,
            ageMonths: ageMonths(for: profile, now: now, calendar: calendar),
            introducedAllergenIDs: toleratedIDs
        ).first else { return [] }
        let foods = recipe.foodNames.compactMap(SolidsReferenceCatalog.food(named:))
        guard !foods.isEmpty else { return [] }
        let existing = existingPlans.filter {
            $0.profileID == profile.id && !$0.isCompleted && $0.allergenID == allergen.rawValue
        }
        let completedSteps = Set(existing.compactMap(\.allergenIntroductionStep))
        let currentStep = min(3, max(0, progress?.introductionStep ?? 0))
        let stepsToPlan = currentStep < 3
            ? Array((currentStep + 1)...3).filter { !completedSteps.contains($0) }
            : []
        let planned: [SolidsPlanEditorWrite]
        if !stepsToPlan.isEmpty {
            planned = stepsToPlan.enumerated().map { index, step in
                let day = calendar.date(byAdding: .day, value: 1 + (index * 2), to: now) ?? now
                let scheduledAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
                return SolidsPlanEditorWrite(
                    planID: nil,
                    profileID: profile.id,
                    scheduledAt: scheduledAt,
                    foodIDs: foods.map(\.id),
                    foodNames: foods.map(\.name),
                    notes: "\(allergen.displayName) introduction portion \(step) of 3. This example schedule is editable.",
                    reminderEnabled: false,
                    reminderOffsetMinutes: 30,
                    title: recipe.title,
                    recipeID: recipe.id,
                    allergenID: allergen.rawValue,
                    allergenIntroductionStep: step,
                    allergenServingGuidance: SolidsReferenceCatalog.introductionServingGuidance(
                        for: allergen,
                        step: step
                    ),
                    allergenObservationMinutes: step == 1 ? 10 : nil
                )
            }
        } else {
            guard currentStep >= 3 else { return [] }
            guard !existing.contains(where: { $0.allergenIntroductionStep == nil }) else { return [] }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let baseDate = max(progress?.nextExposureDueAt ?? tomorrow, tomorrow)
            let scheduledAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: baseDate)
                ?? baseDate
            planned = [SolidsPlanEditorWrite(
                planID: nil,
                profileID: profile.id,
                scheduledAt: scheduledAt,
                foodIDs: foods.map(\.id),
                foodNames: foods.map(\.name),
                notes: "\(allergen.displayName) weekly rotation meal.",
                reminderEnabled: false,
                reminderOffsetMinutes: 30,
                title: recipe.title,
                recipeID: recipe.id,
                allergenID: allergen.rawValue,
                allergenServingGuidance: SolidsReferenceCatalog.introductionServingGuidance(
                    for: allergen,
                    step: 3
                )
            )]
        }
        return planned
    }

    @discardableResult
    static func buildAllergenPlan(
        for allergen: SolidsAllergen,
        profile: BabyProfile,
        progress: SolidAllergenProgress?,
        allProgress: [SolidAllergenProgress],
        existingPlans: [PlannedSolidMeal],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlannedSolidMeal] {
        let writes = allergenPlanWrites(
            for: allergen,
            profile: profile,
            progress: progress,
            allProgress: allProgress,
            existingPlans: existingPlans,
            now: now,
            calendar: calendar
        )
        let planned = writes.map { write in
            PlannedSolidMeal(
                profileID: write.profileID,
                scheduledAt: write.scheduledAt,
                title: write.title ?? write.foodNames.joined(separator: " + "),
                foodIDs: write.foodIDs,
                foodNames: write.foodNames,
                notes: write.notes,
                recipeID: write.recipeID,
                isGuided: write.isGuided,
                guidedPosition: write.guidedPosition,
                allergenID: write.allergenID,
                allergenIntroductionStep: write.allergenIntroductionStep,
                allergenServingGuidance: write.allergenServingGuidance,
                allergenObservationMinutes: write.allergenObservationMinutes,
                reminderEnabled: write.reminderEnabled,
                reminderOffsetMinutes: write.reminderOffsetMinutes,
                createdAt: now,
                updatedAt: now
            )
        }
        guard !planned.isEmpty else { return [] }
        do {
            try context.transaction {
                for plan in planned { context.insert(plan) }
                try context.save()
            }
        } catch {
            return []
        }
        return planned
    }

    nonisolated private static var guidedOpeningFoodNames: [String] {
        ["Avocado", "Lentil", "Oatmeal", "Sweet potato", "Banana"]
    }

    nonisolated private static var guidedAllergenPriority: [SolidsAllergen] {
        [
            .egg,
            .peanuts,
            .milk,
            .wheat,
            .soy,
            .sesame,
            .treeNuts,
            .fish,
            .crustaceanShellfish
        ]
    }

    nonisolated private static var guidedAllergenCarrierNames: [String: [String]] {
        [
            SolidsAllergen.egg.rawValue: ["Egg"],
            SolidsAllergen.peanuts.rawValue: ["Peanut butter"],
            SolidsAllergen.milk.rawValue: ["Plain whole-milk yogurt"],
            SolidsAllergen.wheat.rawValue: ["Wheat cereal", "Whole-wheat toast"],
            SolidsAllergen.soy.rawValue: ["Silken tofu", "Tofu"],
            SolidsAllergen.sesame.rawValue: ["Tahini"],
            SolidsAllergen.treeNuts.rawValue: ["Almond butter"],
            SolidsAllergen.fish.rawValue: ["Salmon", "Cod"],
            SolidsAllergen.crustaceanShellfish.rawValue: ["Shrimp"]
        ]
    }

    nonisolated private static func guidedAllergenCarrier(
        for allergenID: String,
        candidates: [SolidsReferenceFood],
        familiarFoodIDs: Set<String>,
        ageMonths: Int
    ) -> SolidsReferenceFood? {
        let matching = candidates.filter { food in
            food.minimumAgeMonths <= ageMonths
                && food.allergenIDs.contains(allergenID)
                && Set(food.allergenIDs).subtracting([allergenID]).isEmpty
        }
        var ordered: [SolidsReferenceFood] = []
        var seen = Set<String>()
        for name in guidedAllergenCarrierNames[allergenID] ?? [] {
            guard let food = SolidsReferenceCatalog.food(named: name),
                  matching.contains(where: { $0.id == food.id }),
                  seen.insert(food.id).inserted else { continue }
            ordered.append(food)
        }
        for food in matching where seen.insert(food.id).inserted {
            ordered.append(food)
        }
        return ordered.first(where: { familiarFoodIDs.contains($0.id) }) ?? ordered.first
    }

    nonisolated private static func bestRecipe(
        containing food: SolidsReferenceFood,
        ageMonths: Int,
        blockedAllergens: Set<String>,
        permittedAllergens: Set<String>,
        familiarFoodIDs: Set<String>
    ) -> SolidsReferenceRecipe? {
        SolidsReferenceCatalog.recipes(containingFoodID: food.id).first { recipe in
            let recipeFoodIDs = Set(recipe.foodNames.compactMap {
                SolidsReferenceCatalog.food(named: $0)?.id
            })
            return recipe.minimumAgeMonths <= ageMonths
                && Set(recipe.allergenIDs).isDisjoint(with: blockedAllergens)
                && Set(recipe.allergenIDs).isSubset(of: permittedAllergens)
                && recipeFoodIDs.subtracting([food.id]).isSubset(of: familiarFoodIDs)
        }
    }

    nonisolated private static func personalizedPreparationNotes(
        for food: SolidsReferenceFood,
        ageMonths: Int,
        completedSkillIDs: Set<String>
    ) -> String {
        let advancedTextureSkills: Set<String> = [
            SolidsFeedingSkill.managesLumpyTexture.rawValue,
            SolidsFeedingSkill.holdsLargeSoftPiece.rawValue,
            SolidsFeedingSkill.usesPreloadedSpoon.rawValue
        ]
        let biteSizeSkills: Set<String> = [
            SolidsFeedingSkill.picksUpBiteSizeFood.rawValue,
            SolidsFeedingSkill.usesPincerGrasp.rawValue,
            SolidsFeedingSkill.takesBitesFromLargerFood.rawValue
        ]
        let utensilSkills: Set<String> = [SolidsFeedingSkill.scoopsWithUtensil.rawValue]
        let skillAge: Int
        if !completedSkillIDs.isDisjoint(with: utensilSkills) {
            skillAge = 12
        } else if !completedSkillIDs.isDisjoint(with: biteSizeSkills) {
            skillAge = 9
        } else if !completedSkillIDs.isDisjoint(with: advancedTextureSkills) {
            skillAge = 8
        } else {
            skillAge = 6
        }
        let preparation = food.preparation(forAgeMonths: min(ageMonths, skillAge))
        return "For observed skills: \(preparation.instructions)"
    }

    static func toggleRecipeWantToTry(
        recipeID: String,
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) {
        let state = activate(
            profileID: profileID,
            existingState: existingState,
            context: context,
            now: now,
            persist: false
        )
        var values = Set(state.wantToTryRecipeIDs)
        if !values.insert(recipeID).inserted { values.remove(recipeID) }
        state.wantToTryRecipeIDs = values.sorted()
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    @discardableResult
    static func createRecipeCollection(
        name: String,
        initialRecipeIDs: [String] = [],
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) -> SolidRecipeCollection? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let state = activate(
            profileID: profileID,
            existingState: existingState,
            context: context,
            now: now,
            persist: false
        )
        guard !state.recipeCollections.contains(where: {
            $0.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }
        let collection = SolidRecipeCollection(
            name: cleaned,
            recipeIDs: initialRecipeIDs,
            createdAt: now,
            updatedAt: now
        )
        var collections = state.recipeCollections
        collections.append(collection)
        state.recipeCollections = collections.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
        return collection
    }

    static func toggleRecipe(
        recipeID: String,
        collectionID: UUID,
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) {
        let state = activate(
            profileID: profileID,
            existingState: existingState,
            context: context,
            now: now,
            persist: false
        )
        var collections = state.recipeCollections
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        var recipeIDs = Set(collections[index].recipeIDs)
        if !recipeIDs.insert(recipeID).inserted { recipeIDs.remove(recipeID) }
        collections[index].recipeIDs = recipeIDs.sorted()
        collections[index].updatedAt = now
        state.recipeCollections = collections
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func deleteRecipeCollection(
        collectionID: UUID,
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) {
        guard let state = existingState, state.profileID == profileID else { return }
        state.recipeCollections = state.recipeCollections.filter { $0.id != collectionID }
        state.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    @discardableResult
    static func renameRecipeCollection(
        collectionID: UUID,
        name: String,
        profileID: UUID,
        existingState: SolidsProfileState?,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let state = existingState,
              state.profileID == profileID else { return false }
        var collections = state.recipeCollections
        guard let index = collections.firstIndex(where: { $0.id == collectionID }),
              !collections.contains(where: {
                  $0.id != collectionID
                      && $0.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
              }) else { return false }
        collections[index].name = cleaned
        collections[index].updatedAt = now
        state.recipeCollections = collections.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        state.updatedAt = now
        return PersistenceService.save(context: context)
    }

    @discardableResult
    static func createPlan(
        profileID: UUID,
        scheduledAt: Date,
        foods: [SolidsReferenceFood],
        title: String? = nil,
        notes: String,
        recipeID: String? = nil,
        isGuided: Bool = false,
        guidedPosition: Int? = nil,
        allergenID: String? = nil,
        allergenIntroductionStep: Int? = nil,
        allergenServingGuidance: String? = nil,
        allergenObservationMinutes: Int? = nil,
        reminderEnabled: Bool = false,
        reminderOffsetMinutes: Int = 30,
        context: ModelContext,
        now: Date = Date()
    ) -> PlannedSolidMeal? {
        createPlan(
            profileID: profileID,
            scheduledAt: scheduledAt,
            foodIDs: foods.map(\.id),
            foodNames: foods.map(\.name),
            title: title,
            notes: notes,
            recipeID: recipeID,
            isGuided: isGuided,
            guidedPosition: guidedPosition,
            allergenID: allergenID,
            allergenIntroductionStep: allergenIntroductionStep,
            allergenServingGuidance: allergenServingGuidance,
            allergenObservationMinutes: allergenObservationMinutes,
            reminderEnabled: reminderEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes,
            context: context,
            now: now
        )
    }

    @discardableResult
    static func createPlan(
        profileID: UUID,
        scheduledAt: Date,
        foodIDs: [String],
        foodNames: [String],
        title: String? = nil,
        notes: String,
        recipeID: String? = nil,
        isGuided: Bool = false,
        guidedPosition: Int? = nil,
        allergenID: String? = nil,
        allergenIntroductionStep: Int? = nil,
        allergenServingGuidance: String? = nil,
        allergenObservationMinutes: Int? = nil,
        reminderEnabled: Bool = false,
        reminderOffsetMinutes: Int = 30,
        context: ModelContext,
        now: Date = Date()
    ) -> PlannedSolidMeal? {
        guard !foodIDs.isEmpty, foodIDs.count == foodNames.count else { return nil }
        let foodTitle = foodNames.joined(separator: " + ")
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? foodTitle
        let plan = PlannedSolidMeal(
            profileID: profileID,
            scheduledAt: scheduledAt,
            title: resolvedTitle,
            foodIDs: foodIDs,
            foodNames: foodNames,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            recipeID: recipeID,
            isGuided: isGuided,
            guidedPosition: guidedPosition,
            allergenID: allergenID,
            allergenIntroductionStep: allergenIntroductionStep,
            allergenServingGuidance: allergenServingGuidance,
            allergenObservationMinutes: allergenObservationMinutes,
            reminderEnabled: reminderEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes,
            createdAt: now,
            updatedAt: now
        )
        do {
            try context.transaction {
                context.insert(plan)
                try context.save()
            }
        } catch { return nil }
        let reminder = SolidMealReminderSnapshot(plan: plan)
        Task { await NotificationManager.shared.scheduleSolidMealReminder(snapshot: reminder) }
        return plan
    }

    @discardableResult
    static func updatePlan(
        _ plan: PlannedSolidMeal,
        scheduledAt: Date,
        foods: [SolidsReferenceFood],
        notes: String,
        reminderEnabled: Bool,
        reminderOffsetMinutes: Int,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        updatePlan(
            plan,
            scheduledAt: scheduledAt,
            foodIDs: foods.map(\.id),
            foodNames: foods.map(\.name),
            notes: notes,
            reminderEnabled: reminderEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes,
            context: context,
            now: now
        )
    }

    @discardableResult
    static func updatePlan(
        _ plan: PlannedSolidMeal,
        scheduledAt: Date,
        foodIDs: [String],
        foodNames: [String],
        notes: String,
        reminderEnabled: Bool,
        reminderOffsetMinutes: Int,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !foodIDs.isEmpty, foodIDs.count == foodNames.count else { return false }
        do {
            try context.transaction {
                let foodSelectionChanged = Set(plan.foodIDs) != Set(foodIDs)
                plan.scheduledAt = scheduledAt
                if foodSelectionChanged || plan.recipeID == nil {
                    plan.title = foodNames.joined(separator: " + ")
                }
                if foodSelectionChanged { plan.recipeID = nil }
                plan.foodIDs = foodIDs
                plan.foodNames = foodNames
                plan.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                plan.reminderEnabled = reminderEnabled
                plan.reminderOffsetMinutes = max(0, reminderOffsetMinutes)
                plan.updatedAt = now
                try context.save()
            }
        } catch { return false }
        let reminder = SolidMealReminderSnapshot(plan: plan)
        Task { await NotificationManager.shared.scheduleSolidMealReminder(snapshot: reminder) }
        return true
    }

    static func deletePlan(_ plan: PlannedSolidMeal, context: ModelContext) {
        let id = plan.id
        do {
            try context.transaction {
                context.delete(plan)
                try context.save()
            }
        } catch { return }
        Task { await NotificationManager.shared.cancelSolidMealReminder(planID: id) }
    }

    @discardableResult
    static func addToShoppingList(
        food: SolidsReferenceFood,
        list: ShoppingList,
        existingItems: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date(),
        saveImmediately: Bool = true
    ) -> ShoppingListItem? {
        let householdID = list.householdID
        let foodReferenceID = food.id
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate {
                $0.householdID == householdID && $0.foodReferenceID == foodReferenceID
            }
        )
        let canonicalItem: FoodItem
        if let existing = try? context.fetch(descriptor).first {
            canonicalItem = existing
        } else {
            let aliasesJSON = (try? JSONEncoder().encode(food.aliases))
                .flatMap { String(data: $0, encoding: .utf8) }
            canonicalItem = FoodItem(
                householdID: householdID,
                canonicalName: food.name,
                foodReferenceID: food.id,
                aliasesJSON: aliasesJSON,
                createdAt: now,
                updatedAt: now
            )
            context.insert(canonicalItem)
        }
        let shoppingItem = ShoppingListService.addItem(
            named: food.name,
            to: list,
            sectionID: nil,
            existingItems: existingItems,
            context: context,
            now: now,
            saveImmediately: false
        )
        shoppingItem?.foodItemID = canonicalItem.id
        shoppingItem?.updatedAt = now
        if saveImmediately {
            _ = PersistenceService.save(context: context)
        }
        return shoppingItem
    }

    @discardableResult
    static func addFoodsToShoppingList(
        foods: [SolidsReferenceFood],
        list: ShoppingList,
        existingItems: [ShoppingListItem],
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem],
        skipAvailableInventory: Bool,
        context: ModelContext,
        now: Date = Date()
    ) -> Int {
        var added = 0
        var currentItems = existingItems
        for food in foods {
            if skipAvailableInventory,
               isAvailableInInventory(food: food, inventoryItems: inventoryItems, foodItems: foodItems) {
                continue
            }
            if let item = addToShoppingList(
                food: food,
                list: list,
                existingItems: currentItems,
                context: context,
                now: now,
                saveImmediately: false
            ) {
                currentItems.append(item)
                added += 1
            }
        }
        if added > 0 {
            _ = PersistenceService.save(context: context)
        }
        return added
    }

    @discardableResult
    static func addPlannedFoodsToShoppingList(
        foodIDs: [String],
        foodNames: [String],
        list: ShoppingList,
        existingItems: [ShoppingListItem],
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem],
        skipAvailableInventory: Bool,
        context: ModelContext,
        now: Date = Date()
    ) -> Int {
        var added = 0
        var currentItems = existingItems
        for (foodID, foodName) in zip(foodIDs, foodNames) {
            if let food = SolidsReferenceCatalog.food(id: foodID) {
                if skipAvailableInventory,
                   isAvailableInInventory(food: food, inventoryItems: inventoryItems, foodItems: foodItems) {
                    continue
                }
                if let item = addToShoppingList(
                    food: food,
                    list: list,
                    existingItems: currentItems,
                    context: context,
                    now: now,
                    saveImmediately: false
                ) {
                    currentItems.append(item)
                    added += 1
                }
            } else {
                if skipAvailableInventory,
                   isAvailableInInventory(
                    foodID: foodID,
                    foodName: foodName,
                    inventoryItems: inventoryItems,
                    foodItems: foodItems
                   ) {
                    continue
                }
                let householdID = list.householdID
                let referenceID = foodID
                let descriptor = FetchDescriptor<FoodItem>(
                    predicate: #Predicate {
                        $0.householdID == householdID && $0.foodReferenceID == referenceID
                    }
                )
                let canonical = (try? context.fetch(descriptor).first) ?? FoodItem(
                    householdID: householdID,
                    canonicalName: foodName,
                    foodReferenceID: foodID,
                    createdAt: now,
                    updatedAt: now
                )
                if canonical.modelContext == nil { context.insert(canonical) }
                if let item = ShoppingListService.addItem(
                    named: foodName,
                    to: list,
                    sectionID: nil,
                    existingItems: currentItems,
                    context: context,
                    now: now,
                    saveImmediately: false
                ) {
                    item.foodItemID = canonical.id
                    item.updatedAt = now
                    currentItems.append(item)
                    added += 1
                }
            }
        }
        if added > 0 {
            _ = PersistenceService.save(context: context)
        }
        return added
    }

    static func isAvailableInInventory(
        food: SolidsReferenceFood,
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem]
    ) -> Bool {
        isAvailableInInventory(
            foodID: food.id,
            foodName: food.name,
            inventoryItems: inventoryItems,
            foodItems: foodItems
        )
    }

    static func shoppingWrites(
        foods: [SolidsReferenceFood],
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem],
        skipAvailableInventory: Bool
    ) -> [SolidsShoppingFoodWrite] {
        foods.compactMap { food in
            if skipAvailableInventory,
               isAvailableInInventory(
                   food: food,
                   inventoryItems: inventoryItems,
                   foodItems: foodItems
               ) {
                return nil
            }
            return SolidsShoppingFoodWrite(
                foodID: food.id,
                foodName: food.name,
                aliases: food.aliases
            )
        }
    }

    static func shoppingWrites(
        foodIDs: [String],
        foodNames: [String],
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem],
        skipAvailableInventory: Bool
    ) -> [SolidsShoppingFoodWrite] {
        zip(foodIDs, foodNames).compactMap { foodID, foodName in
            if skipAvailableInventory,
               isAvailableInInventory(
                   foodID: foodID,
                   foodName: foodName,
                   inventoryItems: inventoryItems,
                   foodItems: foodItems
               ) {
                return nil
            }
            return SolidsShoppingFoodWrite(
                foodID: foodID,
                foodName: foodName,
                aliases: SolidsReferenceCatalog.food(id: foodID)?.aliases ?? []
            )
        }
    }

    static func isAvailableInInventory(
        foodID: String,
        foodName: String,
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem]
    ) -> Bool {
        let linkedFoodIDs = Set(foodItems.filter { $0.foodReferenceID == foodID }.map(\.id))
        let normalizedName = SolidFoodSelection.normalizedName(foodName)
        return inventoryItems.contains { item in
            item.status == .available && item.quantity > 0
                && (item.foodItemID.map(linkedFoodIDs.contains) == true
                    || SolidFoodSelection.normalizedName(item.name) == normalizedName)
        }
    }

    static func preset(for plan: PlannedSolidMeal) -> SolidFeedEditorPreset {
        let allergenEntries: [(String, [String])] = plan.foodIDs.compactMap { foodID in
            guard let allergenIDs = SolidsReferenceCatalog.food(id: foodID)?.allergenIDs else { return nil }
            return (foodID, allergenIDs)
        }
        let allergenIDsByFoodID = Dictionary(uniqueKeysWithValues: allergenEntries)
        return SolidFeedEditorPreset(
            foodIDs: plan.foodIDs,
            foodNames: plan.foodNames,
            allergenIDsByFoodID: allergenIDsByFoodID,
            confirmedAllergenPortionIDs: plan.allergenIntroductionStep == nil
                ? []
                : [plan.allergenID].compactMap { $0 },
            plannedMealID: plan.id,
            recipeID: plan.recipeID
        )
    }

    static func hasTrackedSolidFeedRecords(
        eventID: UUID,
        context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    static func reconcileSolidFeed(
        event: BabyEvent,
        preset: SolidFeedEditorPreset? = nil,
        context: ModelContext,
        now: Date = Date(),
        persist: Bool = true
    ) {
        guard event.type == .feed, event.feedKind == .solid else {
            guard hasTrackedSolidFeedRecords(eventID: event.id, context: context) else { return }
            removeSolidFeedRecords(
                eventID: event.id,
                context: context,
                now: now,
                persist: persist
            )
            return
        }

        guard let profileID = event.profileID else { return }
        let profileStates = (try? context.fetch(FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        recordSolidFeed(
            event: event,
            preset: preset,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: profileStates,
            context: context,
            now: now,
            persist: persist
        )
    }

    static func recordSolidFeed(
        event: BabyEvent,
        preset: SolidFeedEditorPreset?,
        eventItems: [SolidFoodEventItem],
        progress: [SolidFoodProgress],
        plans: [PlannedSolidMeal],
        profileStates: [SolidsProfileState],
        context: ModelContext,
        now: Date = Date(),
        finalize: Bool = true,
        activateProfile: Bool = true,
        replaceExistingRecords: Bool = true,
        persist: Bool = true
    ) {
        guard event.type == .feed,
              event.feedKind == .solid,
              let profileID = event.profileID else { return }

        let eventID = event.id
        let previouslyLinkedPlanID: UUID?
        if let passedPlanID = plans.first(where: { $0.completedEventID == eventID })?.id {
            previouslyLinkedPlanID = passedPlanID
        } else if finalize {
            previouslyLinkedPlanID = try? context.fetch(FetchDescriptor<PlannedSolidMeal>(
                predicate: #Predicate { $0.completedEventID == eventID }
            )).first?.id
        } else {
            previouslyLinkedPlanID = nil
        }
        if replaceExistingRecords {
            removeSolidFeedRecords(
                eventID: event.id,
                context: context,
                now: now,
                reconcileAllergens: false
            )
        }

        let names = SolidFoodSelection.names(from: event.foodDescription)
        let presetPairs = zip(preset?.foodIDs ?? [], preset?.foodNames ?? [])
        var foodByNormalizedName: [String: (String, String)] = [:]
        for (foodID, foodName) in presetPairs {
            foodByNormalizedName[SolidFoodSelection.normalizedName(foodName)] = (foodID, foodName)
        }
        var details = event.solidFoodDetails
        if details.isEmpty {
            var customFoodsByNormalizedName: [String: SolidFoodCatalogItem] = [:]
            for name in names {
                let normalizedName = SolidFoodSelection.normalizedName(name)
                var descriptor = FetchDescriptor<SolidFoodCatalogItem>(
                    predicate: #Predicate { $0.normalizedName == normalizedName }
                )
                descriptor.fetchLimit = 1
                if let customFood = try? context.fetch(descriptor).first {
                    customFoodsByNormalizedName[normalizedName] = customFood
                }
            }
            details = names.map { name in
                let normalizedName = SolidFoodSelection.normalizedName(name)
                let reference = SolidsReferenceCatalog.food(named: name)
                let custom = customFoodsByNormalizedName[normalizedName]
                let pair = foodByNormalizedName[normalizedName]
                let foodID = pair?.0
                    ?? reference?.id
                    ?? custom.map { "custom-\($0.id.uuidString.lowercased())" }
                    ?? "custom-\(slug(name))"
                let allergenIDs = preset?.allergenIDsByFoodID[foodID]
                    ?? reference?.allergenIDs
                    ?? custom?.allergenIDs
                    ?? []
                let confirmedAllergens = Set(preset?.confirmedAllergenPortionIDs ?? [])
                return SolidFoodLogDetail(
                    foodID: foodID,
                    foodName: pair?.1 ?? reference?.name ?? custom?.name ?? name,
                    allergenIDs: allergenIDs,
                    confirmedAllergenPortionIDs: allergenIDs.filter(confirmedAllergens.contains),
                    preference: event.solidReaction ?? .unknown,
                    suspectedReaction: event.solidSensitivityObserved == true
                )
            }
            event.solidFoodDetails = details
        }

        var progressByFoodID = progress.reduce(into: [String: SolidFoodProgress]()) { result, item in
            guard item.profileID == profileID else { return }
            result[item.foodID] = item
        }
        for detail in details {
            let foodID = detail.foodID
            let snapshot = detail.foodName
            if detail.suspectedReaction || detail.followUp == .avoidPendingAdvice {
                for allergenID in detail.allergenIDs {
                    let descriptor = FetchDescriptor<SolidAllergenProgress>(
                        predicate: #Predicate {
                            $0.profileID == profileID && $0.allergenID == allergenID
                        }
                    )
                    if let allergenProgress = try? context.fetch(descriptor).first {
                        allergenProgress.statusOverride = nil
                        allergenProgress.updatedAt = now
                    }
                }
            }
            context.insert(SolidFoodEventItem(
                eventID: event.id,
                profileID: profileID,
                foodID: foodID,
                foodNameSnapshot: snapshot,
                allergenIDs: detail.allergenIDs,
                confirmedAllergenPortionIDs: detail.confirmedAllergenPortionIDs,
                reactionRawValue: detail.preference.rawValue,
                servingAmount: detail.servingAmount ?? "",
                notes: detail.notes ?? "",
                suspectedReaction: detail.suspectedReaction,
                symptoms: detail.symptoms,
                severity: detail.severity,
                onsetMinutes: detail.onsetMinutes,
                durationMinutes: detail.durationMinutes,
                responseNotes: detail.responseNotes,
                followUp: detail.followUp,
                createdAt: event.startDate,
                updatedAt: now
            ))

            let progressDescriptor = FetchDescriptor<SolidFoodProgress>(
                predicate: #Predicate {
                    $0.profileID == profileID && $0.foodID == foodID
                }
            )
            let record = progressByFoodID[foodID]
                ?? (try? context.fetch(progressDescriptor).first)
                ?? SolidFoodProgress(
                profileID: profileID,
                foodID: foodID,
                foodNameSnapshot: snapshot,
                createdAt: now,
                updatedAt: now
            )
            if record.modelContext == nil { context.insert(record) }
            progressByFoodID[foodID] = record
            record.foodNameSnapshot = snapshot
            record.status = .tried
            let previousLastTriedAt = record.lastTriedAt
            record.exposureCount += 1
            record.firstTriedAt = min(record.firstTriedAt ?? event.startDate, event.startDate)
            record.lastTriedAt = max(previousLastTriedAt ?? event.startDate, event.startDate)
            if previousLastTriedAt.map({ $0 <= event.startDate }) ?? true {
                record.lastReactionRawValue = detail.preference.rawValue
            }
            record.updatedAt = now
        }

        if let plannedMealID = preset?.plannedMealID ?? previouslyLinkedPlanID,
           let plan = plans.first(where: { $0.id == plannedMealID && $0.profileID == profileID })
            ?? (try? context.fetch(FetchDescriptor<PlannedSolidMeal>(
                predicate: #Predicate { $0.id == plannedMealID && $0.profileID == profileID }
            )).first) {
            plan.completedEventID = event.id
            plan.updatedAt = now
        }
        let stateDescriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        if activateProfile {
            _ = activate(
                profileID: profileID,
                existingState: profileStates.first { $0.profileID == profileID }
                    ?? (try? context.fetch(stateDescriptor).first),
                context: context,
                now: now,
                persist: false
            )
        }
        if finalize {
            if persist {
                reconcileAllergenProgress(
                    profileID: profileID,
                    context: context,
                    now: now,
                    persist: true
                )
            }
        }
    }

    static func backfillProgress(
        profileID: UUID,
        events: [BabyEvent],
        eventItems: [SolidFoodEventItem],
        progress: [SolidFoodProgress],
        plans: [PlannedSolidMeal],
        profileStates: [SolidsProfileState],
        context: ModelContext
    ) {
        let recordedEventIDs = Set(eventItems.filter { $0.profileID == profileID }.map(\.eventID))
        let candidateEvents = events.filter { event in
            event.profileID == profileID
            && event.type == .feed
            && event.feedKind == .solid
            && !recordedEventIDs.contains(event.id)
        }
        guard !candidateEvents.isEmpty else { return }

        // The query arrays can briefly lag a save from another screen. Confirm
        // candidates once in the context before using the faster insert-only path.
        let storedItemsDescriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let storedEventIDs = Set(
            ((try? context.fetch(storedItemsDescriptor)) ?? []).map(\.eventID)
        )
        let missingEvents = candidateEvents.filter { !storedEventIDs.contains($0.id) }
        guard !missingEvents.isEmpty else { return }

        let stateDescriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = activate(
            profileID: profileID,
            existingState: profileStates.first { $0.profileID == profileID }
                ?? (try? context.fetch(stateDescriptor).first),
            context: context,
            now: missingEvents.map(\.updatedAt).min() ?? Date(),
            persist: false
        )
        for event in missingEvents {
            recordSolidFeed(
                event: event,
                preset: nil,
                eventItems: eventItems,
                progress: progress,
                plans: plans,
                profileStates: profileStates,
                context: context,
                now: event.updatedAt,
                finalize: false,
                activateProfile: false,
                replaceExistingRecords: false
            )
        }
        let completedAt = missingEvents.map(\.updatedAt).max() ?? Date()
        state.updatedAt = completedAt
        reconcileAllergenProgress(profileID: profileID, context: context, now: completedAt)
    }

    static func removeSolidFeedRecords(
        eventID: UUID,
        context: ModelContext,
        now: Date = Date(),
        reconcileAllergens: Bool = true,
        persist: Bool = true
    ) {
        let itemDescriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        let removedItems = (try? context.fetch(itemDescriptor)) ?? []
        let affectedProfileIDs = Set(removedItems.map(\.profileID))
        var remainingByProfileAndFood: [UUID: [String: [SolidFoodEventItem]]] = [:]
        for profileID in affectedProfileIDs {
            let remainingDescriptor = FetchDescriptor<SolidFoodEventItem>(
                predicate: #Predicate {
                    $0.profileID == profileID && $0.eventID != eventID
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let remaining = (try? context.fetch(remainingDescriptor)) ?? []
            remainingByProfileAndFood[profileID] = Dictionary(grouping: remaining, by: \.foodID)
        }
        for removed in removedItems {
            let profileID = removed.profileID
            let foodID = removed.foodID
            context.delete(removed)

            let remaining = remainingByProfileAndFood[profileID]?[foodID] ?? []
            let progressDescriptor = FetchDescriptor<SolidFoodProgress>(
                predicate: #Predicate { $0.profileID == profileID && $0.foodID == foodID }
            )
            if let record = try? context.fetch(progressDescriptor).first {
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
        for plan in (try? context.fetch(planDescriptor)) ?? [] {
            plan.completedEventID = nil
            plan.updatedAt = now
        }

        if reconcileAllergens {
            for profileID in affectedProfileIDs {
                if persist {
                    reconcileAllergenProgress(
                        profileID: profileID,
                        context: context,
                        now: now,
                        persist: true
                    )
                }
            }
        }
    }

    static func setAllergenReminder(
        _ enabled: Bool,
        allergenID: String,
        profileID: UUID,
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.allergenID == allergenID }
        )
        let record = (try? context.fetch(descriptor).first)
            ?? SolidAllergenProgress(profileID: profileID, allergenID: allergenID)
        if record.modelContext == nil { context.insert(record) }
        record.reminderEnabled = enabled
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
        let reminder = SolidAllergenReminderSnapshot(progress: record)
        Task { await NotificationManager.shared.scheduleSolidAllergenReminder(snapshot: reminder) }
    }

    static func updateAllergenStatus(
        _ status: SolidAllergenStatus,
        allergenID: String,
        profileID: UUID,
        notes: String,
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.allergenID == allergenID }
        )
        let record = (try? context.fetch(descriptor).first)
            ?? SolidAllergenProgress(profileID: profileID, allergenID: allergenID)
        if record.modelContext == nil { context.insert(record) }
        record.status = status
        record.statusOverride = status
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
        let reminder = SolidAllergenReminderSnapshot(progress: record)
        Task { await NotificationManager.shared.scheduleSolidAllergenReminder(snapshot: reminder) }
    }

    static func updateAllergenNotes(
        allergenID: String,
        profileID: UUID,
        notes: String,
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.allergenID == allergenID }
        )
        let record = (try? context.fetch(descriptor).first)
            ?? SolidAllergenProgress(profileID: profileID, allergenID: allergenID)
        if record.modelContext == nil { context.insert(record) }
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
    }

    static func clearAllergenStatusOverride(
        allergenID: String,
        profileID: UUID,
        context: ModelContext,
        now: Date = Date()
    ) {
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.allergenID == allergenID }
        )
        guard let record = try? context.fetch(descriptor).first else { return }
        record.statusOverride = nil
        record.updatedAt = now
        _ = PersistenceService.save(context: context)
        reconcileAllergenProgress(profileID: profileID, context: context, now: now)
    }

    static func reconcileAllergenProgress(
        profileID: UUID,
        context: ModelContext,
        now: Date = Date(),
        persist: Bool = true
    ) {
        let itemsDescriptor = FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let items = (try? context.fetch(itemsDescriptor)) ?? []
        let progressDescriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let existing = (try? context.fetch(progressDescriptor)) ?? []
        applyAllergenProgress(
            profileID: profileID,
            items: items,
            existing: existing,
            context: context,
            now: now
        )
        if persist {
            _ = PersistenceService.save(context: context)
        }
    }

    private static func applyAllergenProgress(
        profileID: UUID,
        items: [SolidFoodEventItem],
        existing: [SolidAllergenProgress],
        context: ModelContext,
        now: Date
    ) {
        let existingByAllergenID = Dictionary(uniqueKeysWithValues: existing.map { ($0.allergenID, $0) })
        let recognizedAllergenIDs = Set(SolidsAllergen.allCases.map(\.rawValue))
        var itemsByAllergenID: [String: [SolidFoodEventItem]] = [:]
        for item in items {
            for allergenID in item.allergenIDs where recognizedAllergenIDs.contains(allergenID) {
                itemsByAllergenID[allergenID, default: []].append(item)
            }
        }

        for allergen in SolidsAllergen.allCases {
            let matching = itemsByAllergenID[allergen.rawValue] ?? []
            guard !matching.isEmpty || existingByAllergenID[allergen.rawValue] != nil else {
                continue
            }
            let record = existingByAllergenID[allergen.rawValue]
                ?? SolidAllergenProgress(profileID: profileID, allergenID: allergen.rawValue)
            if record.modelContext == nil { context.insert(record) }
            var latestExposureByEventID: [UUID: Date] = [:]
            var latestConfirmedExposureByEventID: [UUID: Date] = [:]
            var hasAvoidance = false
            var hasReaction = false
            for item in matching {
                if item.createdAt > (latestExposureByEventID[item.eventID] ?? .distantPast) {
                    latestExposureByEventID[item.eventID] = item.createdAt
                }
                if item.confirmsIntroductionPortion(for: allergen.rawValue),
                   item.createdAt > (latestConfirmedExposureByEventID[item.eventID] ?? .distantPast) {
                    latestConfirmedExposureByEventID[item.eventID] = item.createdAt
                }
                hasAvoidance = hasAvoidance || item.followUp == .avoidPendingAdvice
                hasReaction = hasReaction || item.suspectedReaction
            }
            let confirmedExposureDates = latestConfirmedExposureByEventID.values
            record.exposureMealCount = latestExposureByEventID.count
            record.introductionStep = min(3, confirmedExposureDates.count)
            record.firstIntroducedAt = confirmedExposureDates.min()
            record.lastExposureAt = latestExposureByEventID.values.max()
            if let override = record.statusOverride {
                record.status = override
            } else if hasAvoidance {
                record.status = .avoidPendingAdvice
            } else if hasReaction {
                record.status = .suspectedReaction
            } else if confirmedExposureDates.count >= 3 {
                record.status = .tolerated
            } else if latestExposureByEventID.isEmpty {
                record.status = .notStarted
            } else {
                record.status = .introducing
            }
            let rotationBase: Date?
            switch record.status {
            case .tolerated:
                rotationBase = latestExposureByEventID.values.max()
            case .introducing:
                rotationBase = confirmedExposureDates.max()
            case .notStarted, .suspectedReaction, .avoidPendingAdvice:
                rotationBase = nil
            }
            record.nextExposureDueAt = rotationBase.flatMap {
                Calendar.current.date(byAdding: .day, value: 7, to: $0)
            }
            record.updatedAt = now
            let reminder = SolidAllergenReminderSnapshot(progress: record)
            Task { await NotificationManager.shared.scheduleSolidAllergenReminder(snapshot: reminder) }
        }
    }

    static func scheduleAllergenReconciliation(
        profileID: UUID,
        context: ModelContext,
        now: Date
    ) {
        pendingAllergenReconciliationTasks[profileID]?.cancel()
        pendingAllergenReconciliationTasks[profileID] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await AppInteractionMonitor.waitUntilIdle()
            guard !Task.isCancelled else { return }
            await reconcileAllergenProgressWhenIdle(
                profileID: profileID,
                context: context,
                now: now
            )
        }
    }

    private static func reconcileAllergenProgressWhenIdle(
        profileID: UUID,
        context: ModelContext,
        now: Date
    ) async {
        var items: [SolidFoodEventItem] = []
        var offset = 0
        let pageSize = 200
        while !Task.isCancelled {
            await AppInteractionMonitor.waitUntilIdle()
            guard !Task.isCancelled else { return }
            var descriptor = FetchDescriptor<SolidFoodEventItem>(
                predicate: #Predicate { $0.profileID == profileID },
                sortBy: [SortDescriptor(\SolidFoodEventItem.createdAt)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            let page = (try? context.fetch(descriptor)) ?? []
            items.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += page.count
            await Task.yield()
        }
        guard !Task.isCancelled else { return }
        let progressDescriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let existing = (try? context.fetch(progressDescriptor)) ?? []
        applyAllergenProgress(
            profileID: profileID,
            items: items,
            existing: existing,
            context: context,
            now: now
        )
        _ = PersistenceService.save(context: context)
    }

    private static func slug(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
