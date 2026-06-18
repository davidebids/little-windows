import Foundation
import SwiftData

@MainActor
enum HouseholdService {
    static func ensureDefaultHousehold(context: ModelContext) -> Household {
        if let household = try? context.fetch(FetchDescriptor<Household>()).first {
            return household
        }
        let household = Household(name: "Home")
        context.insert(household)
        try? context.save()
        PersistenceService.recordLocalSave()
        return household
    }
}

@MainActor
enum FoodHomeBootstrapService {
    static func seedIfNeeded(context: ModelContext) {
        _ = HouseholdService.ensureDefaultHousehold(context: context)
    }
}

@MainActor
enum StoreLayoutService {
    static func createStore(
        name: String,
        householdID: UUID,
        context: ModelContext
    ) -> FoodStore? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let store = FoodStore(householdID: householdID, name: trimmed)
        context.insert(store)
        createSections(
            ["Produce", "Refrigerated", "Frozen", "Pantry", "Household", "Other"],
            householdID: householdID,
            storeID: store.id,
            context: context
        )
        save(context)
        return store
    }

    static func createSection(
        name: String,
        store: FoodStore,
        existingSections: [FoodStoreSection],
        context: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (existingSections.map(\.sortOrder).max() ?? -1) + 1
        context.insert(FoodStoreSection(
            householdID: store.householdID,
            storeID: store.id,
            name: trimmed,
            sortOrder: nextOrder
        ))
        store.updatedAt = Date()
        save(context)
    }

    static func archiveStore(_ store: FoodStore, context: ModelContext) {
        store.isArchived = true
        store.updatedAt = Date()
        save(context)
    }

    private static func createSections(
        _ names: [String],
        householdID: UUID,
        storeID: UUID,
        context: ModelContext
    ) {
        for (index, name) in names.enumerated() {
            context.insert(FoodStoreSection(
                householdID: householdID,
                storeID: storeID,
                name: name,
                sortOrder: index
            ))
        }
    }
}

@MainActor
enum ShoppingListService {
    static func createList(
        name: String,
        householdID: UUID,
        storeID: UUID?,
        context: ModelContext
    ) -> ShoppingList? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let list = ShoppingList(
            householdID: householdID,
            name: trimmed,
            storeID: storeID,
            listType: storeID == nil ? .general : .store
        )
        context.insert(list)
        save(context)
        return list
    }

    static func addItem(
        named name: String,
        to list: ShoppingList,
        sectionID: UUID?,
        existingItems: [ShoppingListItem],
        context: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (existingItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        context.insert(ShoppingListItem(
            householdID: list.householdID,
            shoppingListID: list.id,
            name: trimmed,
            storeSectionID: sectionID,
            sortOrder: nextOrder
        ))
        list.updatedAt = Date()
        save(context)
    }

    static func updateItem(
        _ item: ShoppingListItem,
        name: String,
        quantity: Double?,
        unit: String,
        notes: String,
        sectionID: UUID?,
        isRecurringStaple: Bool,
        priority: ShoppingItemPriority,
        inventoryLinkBehavior: InventoryLinkBehavior,
        context: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
        item.quantity = quantity
        item.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.storeSectionID = sectionID
        item.isRecurringStaple = isRecurringStaple
        item.priority = priority
        item.inventoryLinkBehavior = inventoryLinkBehavior
        item.updatedAt = Date()
        save(context)
    }

    static func setChecked(
        _ item: ShoppingListItem,
        isChecked: Bool,
        context: ModelContext,
        now: Date = Date()
    ) {
        item.isChecked = isChecked
        item.updatedAt = now
        if isChecked {
            item.checkedAt = now
        } else {
            item.lastUncheckedAt = now
            item.checkedAt = nil
        }
        save(context)
    }

    static func reactivateAllChecked(
        in list: ShoppingList,
        items: [ShoppingListItem],
        context: ModelContext
    ) {
        for item in items where item.shoppingListID == list.id && item.isChecked {
            item.isChecked = false
            item.lastUncheckedAt = Date()
            item.updatedAt = Date()
        }
        list.updatedAt = Date()
        save(context)
    }

    static func reactivateStaples(
        in list: ShoppingList,
        items: [ShoppingListItem],
        context: ModelContext
    ) {
        for item in items where item.shoppingListID == list.id && item.isRecurringStaple {
            item.isChecked = false
            item.lastUncheckedAt = Date()
            item.updatedAt = Date()
        }
        list.updatedAt = Date()
        save(context)
    }

    static func reactivateLastTrip(
        in list: ShoppingList,
        items: [ShoppingListItem],
        context: ModelContext
    ) {
        let lastTripDate = items
            .filter { $0.shoppingListID == list.id }
            .compactMap(\.lastPurchasedAt)
            .max()
        guard let lastTripDate else { return }
        for item in items
            where item.shoppingListID == list.id
                && item.lastPurchasedAt == lastTripDate {
            item.isChecked = false
            item.lastUncheckedAt = Date()
            item.updatedAt = Date()
        }
        list.updatedAt = Date()
        save(context)
    }

    static func reactivateSection(
        sectionID: UUID?,
        in list: ShoppingList,
        items: [ShoppingListItem],
        context: ModelContext
    ) {
        for item in items
            where item.shoppingListID == list.id
                && item.storeSectionID == sectionID
                && item.isChecked {
            item.isChecked = false
            item.lastUncheckedAt = Date()
            item.updatedAt = Date()
        }
        list.updatedAt = Date()
        save(context)
    }

    static func finishTrip(
        list: ShoppingList,
        items: [ShoppingListItem],
        addToInventory: Bool,
        locations: [InventoryLocation],
        context: ModelContext,
        now: Date = Date()
    ) {
        let checked = items.filter { $0.shoppingListID == list.id && $0.isChecked }
        for item in checked {
            item.lastPurchasedAt = now
            item.purchaseCount += 1
            item.updatedAt = now
            if addToInventory,
               item.inventoryLinkBehavior != .none,
               let location = locations.first(where: { $0.locationType == .pantry })
                    ?? locations.first {
                FoodInventoryService.addInventoryItem(
                    name: item.name,
                    quantity: item.quantity ?? 1,
                    unit: item.unit ?? "",
                    locationID: location.id,
                    householdID: list.householdID,
                    context: context,
                    saveImmediately: false
                )
            }
        }
        list.lastUsedAt = now
        list.updatedAt = now
        save(context)
    }
}

@MainActor
enum InventoryLocationService {
    @discardableResult
    static func addLocation(
        name: String,
        locationType: InventoryLocationType,
        householdID: UUID,
        notes: String,
        existingLocations: [InventoryLocation],
        context: ModelContext
    ) -> InventoryLocation? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let activeLocations = existingLocations.filter { $0.householdID == householdID && !$0.isArchived }
        guard !activeLocations.contains(where: { normalized($0.name) == normalized(trimmed) }) else { return nil }
        let sortOrder = (activeLocations.map(\.sortOrder).max() ?? -1) + 1
        let location = InventoryLocation(
            householdID: householdID,
            name: trimmed,
            locationType: locationType,
            sortOrder: sortOrder,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        context.insert(location)
        save(context)
        return location
    }

    static func updateLocation(
        _ location: InventoryLocation,
        name: String,
        locationType: InventoryLocationType,
        notes: String,
        existingLocations: [InventoryLocation],
        context: ModelContext
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let duplicate = existingLocations.contains {
            $0.id != location.id
                && $0.householdID == location.householdID
                && !$0.isArchived
                && normalized($0.name) == normalized(trimmed)
        }
        guard !duplicate else { return false }
        location.name = trimmed
        location.locationType = locationType
        location.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        location.updatedAt = Date()
        save(context)
        return true
    }

    static func archiveLocation(
        _ location: InventoryLocation,
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        context: ModelContext
    ) -> Bool {
        let inventoryUsesLocation = inventoryItems.contains { $0.locationID == location.id }
        let mealPrepUsesLocation = mealPrepItems.contains { $0.locationID == location.id && !$0.isArchived }
        guard !inventoryUsesLocation && !mealPrepUsesLocation else { return false }
        location.isArchived = true
        location.updatedAt = Date()
        save(context)
        return true
    }
}

@MainActor
enum FoodInventoryService {
    @discardableResult
    static func addInventoryItem(
        name: String,
        quantity: Double,
        unit: String,
        locationID: UUID,
        householdID: UUID,
        context: ModelContext,
        storageDetail: String = "",
        notes: String = "",
        saveImmediately: Bool = true
    ) -> InventoryItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, quantity > 0 else { return nil }
        let item = InventoryItem(
            householdID: householdID,
            name: trimmed,
            quantity: quantity,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            locationID: locationID,
            storageDetail: storageDetail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        context.insert(item)
        if saveImmediately { save(context) }
        return item
    }

    static func updateInventoryItem(
        _ item: InventoryItem,
        name: String,
        quantity: Double,
        unit: String,
        locationID: UUID,
        storageDetail: String,
        notes: String,
        context: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
        item.quantity = max(0, quantity)
        item.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        item.locationID = locationID
        item.storageDetail = storageDetail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.status = item.quantity > 0 ? .available : .usedUp
        item.updatedAt = Date()
        save(context)
    }

    static func useOne(_ item: InventoryItem, context: ModelContext) {
        item.quantity = max(0, item.quantity - 1)
        item.lastUsedAt = Date()
        item.updatedAt = Date()
        if item.quantity == 0 {
            item.status = .usedUp
        }
        save(context)
    }

    static func markUsedUp(_ item: InventoryItem, context: ModelContext) {
        item.quantity = 0
        item.status = .usedUp
        item.lastUsedAt = Date()
        item.updatedAt = Date()
        save(context)
    }

    static func duplicate(_ item: InventoryItem, context: ModelContext) {
        context.insert(InventoryItem(
            householdID: item.householdID,
            foodItemID: item.foodItemID,
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            locationID: item.locationID,
            storageDetail: item.storageDetail,
            notes: item.notes
        ))
        save(context)
    }

    static func addToShoppingList(
        item: InventoryItem,
        list: ShoppingList,
        existingItems: [ShoppingListItem],
        context: ModelContext
    ) {
        ShoppingListService.addItem(
            named: item.name,
            to: list,
            sectionID: nil,
            existingItems: existingItems,
            context: context
        )
    }
}

@MainActor
enum MealPrepService {
    @discardableResult
    static func createMealPrepItem(
        name: String,
        servingsRemaining: Double,
        servingUnit: MealPrepServingUnit,
        locationID: UUID,
        householdID: UUID,
        preparedDate: Date?,
        notes: String,
        tags: String,
        context: ModelContext
    ) -> MealPrepItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, servingsRemaining >= 0 else { return nil }
        let item = MealPrepItem(
            householdID: householdID,
            name: trimmed,
            locationID: locationID,
            servingsTotal: servingsRemaining,
            servingsRemaining: servingsRemaining,
            servingUnit: servingUnit,
            preparedDate: preparedDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tagsJSON: tags.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        context.insert(item)
        save(context)
        return item
    }

    static func updateMealPrepItem(
        _ item: MealPrepItem,
        name: String,
        servingsTotal: Double?,
        servingsRemaining: Double,
        servingUnit: MealPrepServingUnit,
        locationID: UUID,
        preparedDate: Date?,
        notes: String,
        tags: String,
        context: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
        item.servingsTotal = servingsTotal
        item.servingsRemaining = max(0, servingsRemaining)
        item.servingUnit = servingUnit
        item.locationID = locationID
        item.preparedDate = preparedDate
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.tagsJSON = tags.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.updatedAt = Date()
        save(context)
    }

    static func use(
        _ item: MealPrepItem,
        servings: Double,
        notes: String,
        context: ModelContext
    ) {
        guard servings > 0 else { return }
        let now = Date()
        let used = min(servings, item.servingsRemaining)
        item.servingsRemaining = max(0, item.servingsRemaining - used)
        item.lastUsedAt = now
        item.updatedAt = now
        context.insert(MealPrepUsage(
            householdID: item.householdID,
            mealPrepItemID: item.id,
            dateTime: now,
            servingsUsed: used,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ))
        save(context)
    }

    static func archiveIfFinished(_ item: MealPrepItem, context: ModelContext) {
        guard item.servingsRemaining <= 0 else { return }
        item.isArchived = true
        item.updatedAt = Date()
        save(context)
    }
}

struct FoodSuggestion: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var systemImage: String
}

enum FoodSuggestionService {
    static func suggestions(
        for list: ShoppingList,
        items: [ShoppingListItem],
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem]
    ) -> [FoodSuggestion] {
        var result = [FoodSuggestion]()
        let staples = items.filter { $0.shoppingListID == list.id && $0.isRecurringStaple && $0.isChecked }.count
        if staples > 0 {
            result.append(FoodSuggestion(
                title: "Reactivate staples",
                detail: "\(staples) checked staple items are ready for the next trip.",
                systemImage: "arrow.clockwise.circle.fill"
            ))
        }
        let frequent = items.filter { $0.shoppingListID == list.id && $0.purchaseCount >= 2 && $0.isChecked }.count
        if frequent > 0 {
            result.append(FoodSuggestion(
                title: "Add usual \(list.name) items",
                detail: "\(frequent) frequently purchased items are checked off.",
                systemImage: "cart.badge.plus"
            ))
        }
        let usedUp = inventoryItems.filter { $0.householdID == list.householdID && $0.status == .usedUp }.count
        if usedUp > 0 {
            result.append(FoodSuggestion(
                title: "Add items used up recently",
                detail: "\(usedUp) inventory items are marked used up.",
                systemImage: "tray.and.arrow.up.fill"
            ))
        }
        let lowMealPrep = mealPrepItems.filter {
            $0.householdID == list.householdID && !$0.isArchived && $0.servingsRemaining <= 2
        }.count
        if lowMealPrep > 0 {
            result.append(FoodSuggestion(
                title: "Check meal prep",
                detail: "\(lowMealPrep) prepared items are low or finished.",
                systemImage: "fork.knife.circle.fill"
            ))
        }
        return result
    }
}

struct FoodInsightMetric: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var value: String
    var detail: String
    var systemImage: String
}

enum FoodInsightsService {
    static func metrics(
        householdID: UUID,
        locations: [InventoryLocation],
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        shoppingLists: [ShoppingList],
        shoppingItems: [ShoppingListItem]
    ) -> [FoodInsightMetric] {
        let availableInventory = inventoryItems.filter {
            $0.householdID == householdID && $0.status == .available
        }
        let activeMealPrep = mealPrepItems.filter {
            $0.householdID == householdID && !$0.isArchived
        }
        let totalServings = activeMealPrep.reduce(0) { $0 + $1.servingsRemaining }
        let activeShopping = shoppingItems.filter {
            $0.householdID == householdID && !$0.isChecked
        }
        let finishedTrips = shoppingLists.filter {
            $0.householdID == householdID && $0.lastUsedAt != nil
        }.count
        let busiestStore = shoppingItems
            .filter { $0.householdID == householdID }
            .max { $0.purchaseCount < $1.purchaseCount }

        return [
            FoodInsightMetric(
                title: "Inventory",
                value: "\(availableInventory.count)",
                detail: "Available items across \(locations.filter { $0.householdID == householdID && !$0.isArchived }.count) locations.",
                systemImage: "cabinet.fill"
            ),
            FoodInsightMetric(
                title: "Meal Prep",
                value: formatted(totalServings),
                detail: "Servings available in \(activeMealPrep.count) prepared items.",
                systemImage: "takeoutbag.and.cup.and.straw.fill"
            ),
            FoodInsightMetric(
                title: "Shopping",
                value: "\(activeShopping.count)",
                detail: "Active items across reusable lists.",
                systemImage: "cart.fill"
            ),
            FoodInsightMetric(
                title: "Trips",
                value: "\(finishedTrips)",
                detail: "Shopping lists finished at least once.",
                systemImage: "checkmark.circle.fill"
            ),
            FoodInsightMetric(
                title: "Frequent Buy",
                value: busiestStore?.name ?? "None yet",
                detail: busiestStore.map { "\($0.purchaseCount) purchases recorded." } ?? "Finish a trip to build history.",
                systemImage: "repeat.circle.fill"
            )
        ]
    }
}

@MainActor
enum FoodReminderService {
    static func createReminder(
        householdID: UUID,
        type: FoodReminderType,
        title: String,
        dateTime: Date,
        relatedShoppingListID: UUID?,
        relatedMealPrepItemID: UUID?,
        context: ModelContext
    ) async {
        let reminder = FoodReminder(
            householdID: householdID,
            type: type,
            title: title,
            relatedShoppingListID: relatedShoppingListID,
            relatedMealPrepItemID: relatedMealPrepItemID,
            dateTime: dateTime
        )
        context.insert(reminder)
        save(context)
        await NotificationManager.shared.scheduleFoodReminder(reminder: reminder)
    }

    static func cancel(_ reminder: FoodReminder, context: ModelContext) async {
        let reminderID = reminder.id
        await NotificationManager.shared.cancelFoodReminder(reminderID: reminderID)
        context.delete(reminder)
        save(context)
    }
}

@MainActor
func save(_ context: ModelContext) {
    try? context.save()
    PersistenceService.recordLocalSave()
    WidgetSnapshotService.refreshFood(context: context)
}

func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func formatted(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
