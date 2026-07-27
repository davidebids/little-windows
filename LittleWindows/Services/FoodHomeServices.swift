import Foundation
import SwiftData

@MainActor
enum HouseholdService {
    static func ensureDefaultHousehold(context: ModelContext) -> Household {
        var descriptor = FetchDescriptor<Household>(
            sortBy: [SortDescriptor(\Household.createdAt)]
        )
        descriptor.fetchLimit = 1
        if let household = try? context.fetch(descriptor).first {
            return household
        }
        let household = Household(name: "Home")
        context.insert(household)
        _ = PersistenceService.save(context: context)
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

    @discardableResult
    static func createSection(
        name: String,
        store: FoodStore,
        existingSections: [FoodStoreSection],
        context: ModelContext
    ) -> FoodStoreSection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (existingSections.map(\.sortOrder).max() ?? -1) + 1
        let section = FoodStoreSection(
            householdID: store.householdID,
            storeID: store.id,
            name: trimmed,
            sortOrder: nextOrder
        )
        context.insert(section)
        store.updatedAt = Date()
        save(context)
        return section
    }

    @discardableResult
    static func reorderSections(
        _ orderedSections: [FoodStoreSection],
        in store: FoodStore,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard orderedSections.allSatisfy({ $0.storeID == store.id }) else { return false }
        var changed = false
        for (index, section) in orderedSections.enumerated() where section.sortOrder != index {
            section.sortOrder = index
            section.updatedAt = now
            changed = true
        }
        guard changed else { return false }
        store.updatedAt = now
        save(context)
        return true
    }

    @discardableResult
    static func deleteSection(
        _ section: FoodStoreSection,
        from store: FoodStore,
        shoppingItems: [ShoppingListItem],
        remainingSections: [FoodStoreSection],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard section.storeID == store.id else { return false }

        for item in shoppingItems where item.storeSectionID == section.id {
            item.storeSectionID = nil
            item.updatedAt = now
        }
        context.delete(section)

        let orderedRemainingSections = remainingSections
            .filter { $0.id != section.id && $0.storeID == store.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        for (index, remainingSection) in orderedRemainingSections.enumerated() {
            remainingSection.sortOrder = index
            remainingSection.updatedAt = now
        }
        store.updatedAt = now
        save(context)
        return true
    }

    @discardableResult
    static func archiveStore(_ store: FoodStore, context: ModelContext) -> Bool {
        guard !store.isArchived else { return false }
        store.isArchived = true
        store.updatedAt = Date()
        save(context)
        return true
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

    @discardableResult
    static func updateList(
        _ list: ShoppingList,
        name: String,
        notes: String,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard list.name != trimmedName || list.notes != trimmedNotes.nilIfEmpty else { return false }
        list.name = trimmedName
        list.notes = trimmedNotes.nilIfEmpty
        list.updatedAt = now
        save(context)
        return true
    }

    @discardableResult
    static func duplicateList(
        _ list: ShoppingList,
        items: [ShoppingListItem],
        existingLists: [ShoppingList],
        context: ModelContext,
        now: Date = Date()
    ) -> ShoppingList {
        let existingNames = Set(existingLists.map { normalizedShoppingName($0.name) })
        let baseName = "\(list.name) Copy"
        var name = baseName
        var suffix = 2
        while existingNames.contains(normalizedShoppingName(name)) {
            name = "\(baseName) \(suffix)"
            suffix += 1
        }

        let copy = ShoppingList(
            householdID: list.householdID,
            name: name,
            storeID: list.storeID,
            listType: list.listType,
            createdAt: now,
            updatedAt: now,
            sortOrder: (existingLists.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1,
            notes: list.notes
        )
        context.insert(copy)

        for source in items
            .filter({ $0.shoppingListID == list.id })
            .sorted(by: shoppingItemOrder) {
            context.insert(ShoppingListItem(
                householdID: copy.householdID,
                shoppingListID: copy.id,
                foodItemID: source.foodItemID,
                name: source.name,
                quantity: source.quantity,
                unit: source.unit,
                notes: source.notes,
                storeSectionID: source.storeSectionID,
                categoryName: source.categoryName,
                isRecurringStaple: source.isRecurringStaple,
                isFavorite: source.isFavorite,
                priority: source.priority,
                addedBy: source.addedBy,
                createdAt: now,
                updatedAt: now,
                sortOrder: source.sortOrder,
                inventoryLinkBehavior: source.inventoryLinkBehavior
            ))
        }
        save(context)
        return copy
    }

    @discardableResult
    static func reorderLists(
        _ orderedLists: [ShoppingList],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard let householdID = orderedLists.first?.householdID,
              orderedLists.allSatisfy({ $0.householdID == householdID && !$0.isArchived }) else {
            return false
        }
        for (index, list) in orderedLists.enumerated() {
            list.sortOrder = index
            list.updatedAt = now
        }
        save(context)
        return true
    }

    @discardableResult
    static func archiveList(
        _ list: ShoppingList,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !list.isArchived else { return false }
        list.isArchived = true
        list.updatedAt = now
        save(context)
        return true
    }

    @discardableResult
    static func addItem(
        named name: String,
        to list: ShoppingList,
        sectionID: UUID?,
        existingItems: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date(),
        saveImmediately: Bool = true
    ) -> ShoppingListItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = existingItems.first(where: {
            $0.shoppingListID == list.id
                && normalizedShoppingName($0.name) == normalizedShoppingName(trimmed)
        }) {
            var changed = false
            if existing.isChecked {
                existing.isChecked = false
                existing.checkedAt = nil
                existing.lastUncheckedAt = now
                changed = true
            }
            if let sectionID, existing.storeSectionID != sectionID {
                existing.storeSectionID = sectionID
                changed = true
            }
            if changed {
                existing.updatedAt = now
                list.updatedAt = now
                if saveImmediately { save(context) }
            }
            return existing
        }

        let nextOrder = (existingItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        let item = ShoppingListItem(
            householdID: list.householdID,
            shoppingListID: list.id,
            name: trimmed,
            storeSectionID: sectionID,
            createdAt: now,
            updatedAt: now,
            sortOrder: nextOrder
        )
        context.insert(item)
        list.updatedAt = now
        if saveImmediately { save(context) }
        return item
    }

    @discardableResult
    static func addItems(
        from text: String,
        to list: ShoppingList,
        sectionID: UUID?,
        existingItems: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Int {
        let names = text
            .components(separatedBy: .newlines)
            .flatMap { line in
                line.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var workingItems = existingItems
        var changedCount = 0
        for name in names {
            let normalizedName = normalizedShoppingName(name)
            let previous = workingItems.first {
                $0.shoppingListID == list.id
                    && normalizedShoppingName($0.name) == normalizedName
            }
            let wasChecked = previous?.isChecked == true
            let previousSectionID = previous?.storeSectionID
            guard let item = addItem(
                named: name,
                to: list,
                sectionID: sectionID,
                existingItems: workingItems,
                context: context,
                now: now,
                saveImmediately: false
            ) else { continue }
            if previous == nil {
                workingItems.append(item)
                changedCount += 1
            } else if wasChecked || (sectionID != nil && previousSectionID != sectionID) {
                changedCount += 1
            }
        }
        guard changedCount > 0 else { return 0 }
        save(context)
        return changedCount
    }

    static func updateItem(
        _ item: ShoppingListItem,
        name: String,
        quantity: Double?,
        unit: String,
        notes: String,
        sectionID: UUID?,
        isRecurringStaple: Bool,
        isFavorite: Bool,
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
        item.isFavorite = isFavorite
        item.priority = priority
        item.inventoryLinkBehavior = inventoryLinkBehavior
        item.updatedAt = Date()
        save(context)
    }

    static func setFavorite(
        _ item: ShoppingListItem,
        isFavorite: Bool,
        context: ModelContext
    ) {
        item.isFavorite = isFavorite
        item.updatedAt = Date()
        save(context)
    }

    static func deleteItem(_ item: ShoppingListItem, context: ModelContext) {
        context.delete(item)
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

    static func reactivateFrequentItems(
        in list: ShoppingList,
        items: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date()
    ) {
        var changed = false
        for item in items
            where item.shoppingListID == list.id
                && item.purchaseCount >= 2
                && item.isChecked {
            item.isChecked = false
            item.checkedAt = nil
            item.lastUncheckedAt = now
            item.updatedAt = now
            changed = true
        }
        guard changed else { return }
        list.updatedAt = now
        save(context)
    }

    @discardableResult
    static func addUsedUpInventoryItems(
        _ inventoryItems: [InventoryItem],
        to list: ShoppingList,
        existingItems: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Int {
        let names = inventoryItems
            .filter { $0.householdID == list.householdID && $0.status == .usedUp }
            .map(\.name)
            .joined(separator: "\n")
        return addItems(
            from: names,
            to: list,
            sectionID: nil,
            existingItems: existingItems,
            context: context,
            now: now
        )
    }

    @discardableResult
    static func moveItem(
        _ item: ShoppingListItem,
        from sourceList: ShoppingList,
        to destinationList: ShoppingList,
        existingDestinationItems: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard item.shoppingListID == sourceList.id,
              sourceList.householdID == destinationList.householdID,
              sourceList.id != destinationList.id else { return false }

        if let duplicate = existingDestinationItems.first(where: {
            $0.shoppingListID == destinationList.id
                && normalizedShoppingName($0.name) == normalizedShoppingName(item.name)
        }) {
            if duplicate.isChecked && !item.isChecked {
                duplicate.isChecked = false
                duplicate.checkedAt = nil
                duplicate.lastUncheckedAt = now
                duplicate.updatedAt = now
            }
            context.delete(item)
        } else {
            item.shoppingListID = destinationList.id
            item.sortOrder = (existingDestinationItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
            if sourceList.storeID != destinationList.storeID {
                item.storeSectionID = nil
            }
            item.updatedAt = now
        }
        sourceList.updatedAt = now
        destinationList.updatedAt = now
        save(context)
        return true
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

    private static func shoppingItemOrder(_ lhs: ShoppingListItem, _ rhs: ShoppingListItem) -> Bool {
        (lhs.sortOrder ?? 0, lhs.name) < (rhs.sortOrder ?? 0, rhs.name)
    }
}

private func normalizedShoppingName(_ value: String) -> String {
    value
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

@MainActor
enum HomeTodoService {
    @discardableResult
    static func createList(
        name: String,
        householdID: UUID,
        existingLists: [HomeTodoList],
        context: ModelContext,
        now: Date = Date()
    ) -> HomeTodoList? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (existingLists.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        let list = HomeTodoList(
            householdID: householdID,
            name: trimmed,
            createdAt: now,
            updatedAt: now,
            sortOrder: nextOrder
        )
        context.insert(list)
        save(context)
        return list
    }

    static func updateList(
        _ list: HomeTodoList,
        name: String,
        notes: String,
        context: ModelContext,
        now: Date = Date()
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        list.name = trimmed
        list.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        list.updatedAt = now
        save(context)
    }

    @discardableResult
    static func archiveList(
        _ list: HomeTodoList,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !list.isArchived else { return false }
        list.isArchived = true
        list.updatedAt = now
        save(context)
        return true
    }

    static func reorderLists(
        _ lists: [HomeTodoList],
        from source: IndexSet,
        to destination: Int,
        context: ModelContext,
        now: Date = Date()
    ) {
        guard let reordered = reorderedValues(lists, from: source, to: destination) else { return }
        guard reordered.map(\.id) != lists.map(\.id) else { return }
        for (index, list) in reordered.enumerated() {
            list.sortOrder = index
            list.updatedAt = now
        }
        save(context)
    }

    @discardableResult
    static func addItem(
        title: String,
        notes: String,
        addedBy: String,
        to list: HomeTodoList,
        existingItems: [HomeTodoItem],
        context: ModelContext,
        now: Date = Date()
    ) -> HomeTodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (existingItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        let item = HomeTodoItem(
            householdID: list.householdID,
            todoListID: list.id,
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            addedBy: normalizedActorName(addedBy),
            createdAt: now,
            updatedAt: now,
            sortOrder: nextOrder
        )
        context.insert(item)
        list.updatedAt = now
        save(context)
        return item
    }

    static func updateItem(
        _ item: HomeTodoItem,
        title: String,
        notes: String,
        addedBy: String,
        context: ModelContext,
        now: Date = Date()
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.title = trimmed
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.addedBy = normalizedActorName(addedBy)
        item.updatedAt = now
        save(context)
    }

    static func setCompleted(
        _ item: HomeTodoItem,
        isCompleted: Bool,
        completedBy: String,
        siblingItems: [HomeTodoItem] = [],
        context: ModelContext,
        now: Date = Date()
    ) {
        let targetItems = siblingItems.filter {
            $0.id != item.id && $0.todoListID == item.todoListID && $0.isCompleted == isCompleted
        }
        item.isCompleted = isCompleted
        item.updatedAt = now
        item.sortOrder = (targetItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        if isCompleted {
            item.completedAt = now
            item.completedBy = normalizedActorName(completedBy)
        } else {
            item.completedAt = nil
            item.completedBy = nil
            item.lastReopenedAt = now
        }
        save(context)
    }

    static func deleteItem(_ item: HomeTodoItem, context: ModelContext) {
        context.delete(item)
        save(context)
    }

    static func reorderItems(
        _ items: [HomeTodoItem],
        from source: IndexSet,
        to destination: Int,
        context: ModelContext,
        now: Date = Date()
    ) {
        guard let reordered = reorderedValues(items, from: source, to: destination) else { return }
        guard reordered.map(\.id) != items.map(\.id) else { return }
        for (index, item) in reordered.enumerated() {
            item.sortOrder = index
            item.updatedAt = now
        }
        save(context)
    }

    private static func reorderedValues<T>(
        _ values: [T],
        from source: IndexSet,
        to destination: Int
    ) -> [T]? {
        guard !source.isEmpty else { return nil }
        let sourceIndexes = source.sorted()
        guard let lastIndex = sourceIndexes.last, lastIndex < values.count else { return nil }
        var reordered = values
        let movedValues = sourceIndexes.map { reordered[$0] }
        for index in sourceIndexes.reversed() {
            reordered.remove(at: index)
        }
        let adjustedDestination = destination - sourceIndexes.filter { $0 < destination }.count
        reordered.insert(contentsOf: movedValues, at: max(0, min(adjustedDestination, reordered.count)))
        return reordered
    }

    private static func normalizedActorName(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

    static func deleteInventoryItem(_ item: InventoryItem, context: ModelContext) {
        context.delete(item)
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
        servingsTotal: Double? = nil,
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
            servingsTotal: servingsTotal ?? servingsRemaining,
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
        archive(item, context: context)
    }

    static func archive(_ item: MealPrepItem, context: ModelContext) {
        guard !item.isArchived else { return }
        item.isArchived = true
        item.updatedAt = Date()
        save(context)
    }
}

@MainActor
enum ReturnTrackingService {
    @discardableResult
    static func createReturn(
        householdID: UUID,
        sortOrder: Int,
        itemName: String,
        itemQuantity: Double?,
        itemReason: String,
        returnURLString: String,
        packageName: String,
        carrier: ReturnPackageCarrier,
        method: ReturnPackageMethod,
        trackingNumber: String,
        returnByDate: Date?,
        photoAttachmentIDs: [UUID],
        context: ModelContext
    ) -> ReturnRequest? {
        let trimmedItemName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPackageName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrackingNumber = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasItem = !trimmedItemName.isEmpty
        let hasExplicitPackageDetails = !trimmedPackageName.isEmpty
            || carrier != .wholeFoods
            || method != .dropOff
            || !trimmedTrackingNumber.isEmpty
            || returnByDate != nil
            || !photoAttachmentIDs.isEmpty
        guard hasItem || hasExplicitPackageDetails else { return nil }

        let request = ReturnRequest(
            householdID: householdID,
            sortOrder: sortOrder
        )
        context.insert(request)

        // The creation form always presents a populated send-back method and
        // partner. Persist those selections on the first save, including when
        // they are still the defaults, so the saved return matches the form.
        let package = ReturnPackage(
            householdID: householdID,
            returnRequestID: request.id,
            name: trimmedPackageName,
            carrier: carrier,
            method: method,
            trackingNumber: trimmedTrackingNumber.nilIfEmpty,
            returnByDate: returnByDate,
            photoAttachmentIDs: photoAttachmentIDs,
            sortOrder: 0
        )
        context.insert(package)

        if hasItem {
            context.insert(ReturnItem(
                householdID: householdID,
                returnRequestID: request.id,
                packageID: package.id,
                name: trimmedItemName,
                quantity: itemQuantity,
                reason: itemReason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                returnURLString: returnURLString.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                sortOrder: 0
            ))
        }

        save(context)
        return request
    }

    @discardableResult
    static func addItem(
        name: String,
        quantity: Double?,
        reason: String,
        returnURLString: String,
        packageID: UUID?,
        to request: ReturnRequest,
        existingItems: [ReturnItem],
        context: ModelContext
    ) -> ReturnItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (existingItems.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        let item = ReturnItem(
            householdID: request.householdID,
            returnRequestID: request.id,
            packageID: packageID,
            name: trimmed,
            quantity: quantity,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            returnURLString: returnURLString.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sortOrder: nextOrder
        )
        context.insert(item)
        request.updatedAt = Date()
        save(context)
        return item
    }

    static func updateItem(
        _ item: ReturnItem,
        name: String,
        quantity: Double?,
        reason: String,
        returnURLString: String,
        packageID: UUID?,
        context: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
        item.quantity = quantity
        item.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.returnURLString = returnURLString.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.packageID = packageID
        item.updatedAt = Date()
        save(context)
    }

    static func deleteItem(
        _ item: ReturnItem,
        from request: ReturnRequest,
        items: [ReturnItem],
        packages: [ReturnPackage],
        attachments: [PhotoAttachment],
        context: ModelContext
    ) {
        let remainingItems = items.filter {
            $0.returnRequestID == request.id && $0.id != item.id
        }
        if remainingItems.isEmpty {
            archive(
                request,
                items: items,
                packages: packages,
                attachments: attachments,
                context: context
            )
            return
        }
        context.delete(item)
        request.updatedAt = Date()
        save(context)
    }

    @discardableResult
    static func addPackage(
        name: String,
        carrier: ReturnPackageCarrier,
        method: ReturnPackageMethod,
        trackingNumber: String,
        returnByDate: Date?,
        photoAttachmentIDs: [UUID],
        to request: ReturnRequest,
        existingPackages: [ReturnPackage],
        context: ModelContext
    ) -> ReturnPackage {
        let nextOrder = (existingPackages.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        let package = ReturnPackage(
            householdID: request.householdID,
            returnRequestID: request.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            carrier: carrier,
            method: method,
            trackingNumber: trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            returnByDate: returnByDate,
            photoAttachmentIDs: photoAttachmentIDs,
            sortOrder: nextOrder
        )
        context.insert(package)
        request.updatedAt = Date()
        save(context)
        return package
    }

    static func updatePackage(
        _ package: ReturnPackage,
        name: String,
        carrier: ReturnPackageCarrier,
        method: ReturnPackageMethod,
        trackingNumber: String,
        returnByDate: Date?,
        photoAttachmentIDs: [UUID],
        context: ModelContext
    ) {
        package.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        package.carrier = carrier
        package.method = method
        package.trackingNumber = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        package.returnByDate = returnByDate
        package.photoAttachmentIDs = photoAttachmentIDs
        package.updatedAt = Date()
        save(context)
    }

    static func deletePackage(
        _ package: ReturnPackage,
        items: [ReturnItem],
        attachments: [PhotoAttachment],
        context: ModelContext
    ) {
        for item in items where item.packageID == package.id {
            item.packageID = nil
            item.updatedAt = Date()
        }
        PhotoAttachmentStore.deleteAttachments(
            with: package.photoAttachmentIDs,
            in: attachments,
            context: context
        )
        context.delete(package)
        save(context)
    }

    static func markDroppedOff(_ package: ReturnPackage, at date: Date = Date(), context: ModelContext) {
        guard package.completedAt == nil else { return }
        package.droppedOffAt = date
        package.updatedAt = date
        save(context)
    }

    static func markDroppedOff(
        _ request: ReturnRequest,
        packages: [ReturnPackage],
        at date: Date = Date(),
        context: ModelContext
    ) {
        guard request.completedAt == nil else { return }
        var changed = false
        for package in packages
            where package.returnRequestID == request.id
                && package.completedAt == nil
                && package.droppedOffAt == nil {
            package.droppedOffAt = date
            package.updatedAt = date
            changed = true
        }
        guard changed else { return }
        request.updatedAt = date
        save(context)
    }

    static func markInProgress(_ package: ReturnPackage, at date: Date = Date(), context: ModelContext) {
        guard package.completedAt == nil else { return }
        package.droppedOffAt = nil
        package.updatedAt = date
        save(context)
    }

    static func markInProgress(
        _ request: ReturnRequest,
        packages: [ReturnPackage],
        at date: Date = Date(),
        context: ModelContext
    ) {
        guard request.completedAt == nil else { return }
        var changed = false
        for package in packages
            where package.returnRequestID == request.id
                && package.completedAt == nil
                && package.droppedOffAt != nil {
            package.droppedOffAt = nil
            package.updatedAt = date
            changed = true
        }
        guard changed else { return }
        request.updatedAt = date
        save(context)
    }

    static func markComplete(_ package: ReturnPackage, at date: Date = Date(), context: ModelContext) {
        if package.droppedOffAt == nil {
            package.droppedOffAt = date
        }
        package.completedAt = date
        package.updatedAt = date
        save(context)
    }

    static func markComplete(
        _ request: ReturnRequest,
        packages: [ReturnPackage],
        at date: Date = Date(),
        context: ModelContext
    ) {
        request.completedAt = date
        request.updatedAt = date
        for package in packages where package.returnRequestID == request.id {
            if package.droppedOffAt == nil {
                package.droppedOffAt = date
            }
            package.completedAt = date
            package.updatedAt = date
        }
        save(context)
    }

    static func archive(
        _ request: ReturnRequest,
        items: [ReturnItem],
        packages: [ReturnPackage],
        attachments: [PhotoAttachment],
        context: ModelContext
    ) {
        request.isArchived = true
        request.updatedAt = Date()
        let packageIDs = packages
            .filter { $0.returnRequestID == request.id }
            .flatMap(\.photoAttachmentIDs)
        PhotoAttachmentStore.deleteAttachments(with: packageIDs, in: attachments, context: context)
        for item in items where item.returnRequestID == request.id {
            context.delete(item)
        }
        for package in packages where package.returnRequestID == request.id {
            context.delete(package)
        }
        save(context)
    }

    static func status(for request: ReturnRequest, packages: [ReturnPackage]) -> ReturnRequestStatus {
        if request.isArchived { return .archived }
        let requestPackages = packages.filter { $0.returnRequestID == request.id }
        if request.completedAt != nil || (!requestPackages.isEmpty && requestPackages.allSatisfy { $0.completedAt != nil }) {
            return .completed
        }
        guard !requestPackages.isEmpty else { return .needsAction }
        let droppedCount = requestPackages.filter { $0.droppedOffAt != nil }.count
        if droppedCount == requestPackages.count {
            return .droppedOff
        }
        if droppedCount > 0 {
            return .partiallyDroppedOff
        }
        return .readyToDropOff
    }
}

struct FoodSuggestion: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var systemImage: String
    var action: FoodSuggestionAction
}

enum FoodSuggestionAction: Equatable {
    case reactivateStaples
    case reactivateFrequent
    case addUsedUpInventory
    case reviewMealPrep
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
                systemImage: "arrow.clockwise.circle.fill",
                action: .reactivateStaples
            ))
        }
        let frequent = items.filter { $0.shoppingListID == list.id && $0.purchaseCount >= 2 && $0.isChecked }.count
        if frequent > 0 {
            result.append(FoodSuggestion(
                title: "Add usual \(list.name) items",
                detail: "\(frequent) frequently purchased items are checked off.",
                systemImage: "cart.badge.plus",
                action: .reactivateFrequent
            ))
        }
        let activeNames = Set(items.lazy.filter {
            $0.shoppingListID == list.id && !$0.isChecked
        }.map { normalizedShoppingName($0.name) })
        let usedUp = inventoryItems.filter {
            $0.householdID == list.householdID
                && $0.status == .usedUp
                && !activeNames.contains(normalizedShoppingName($0.name))
        }.count
        if usedUp > 0 {
            result.append(FoodSuggestion(
                title: "Add items used up recently",
                detail: "\(usedUp) inventory items are marked used up.",
                systemImage: "tray.and.arrow.up.fill",
                action: .addUsedUpInventory
            ))
        }
        let lowMealPrep = mealPrepItems.filter {
            $0.householdID == list.householdID && !$0.isArchived && $0.servingsRemaining <= 2
        }.count
        if lowMealPrep > 0 {
            result.append(FoodSuggestion(
                title: "Check meal prep",
                detail: "\(lowMealPrep) prepared items are low or finished.",
                systemImage: "fork.knife.circle.fill",
                action: .reviewMealPrep
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

@MainActor
enum FoodInsightsService {
    static func metrics(
        householdID: UUID,
        locations: [InventoryLocation],
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        shoppingLists: [ShoppingList],
        shoppingItems: [ShoppingListItem],
        todoLists: [HomeTodoList],
        todoItems: [HomeTodoItem],
        returnRequests: [ReturnRequest],
        returnPackages: [ReturnPackage],
        returnStatusesByRequestID: [UUID: ReturnRequestStatus] = [:]
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
        let activeTodoLists = todoLists.filter {
            $0.householdID == householdID && !$0.isArchived
        }
        let activeTodoListIDs = Set(activeTodoLists.map(\.id))
        let householdTodoItems = todoItems.filter {
            $0.householdID == householdID && activeTodoListIDs.contains($0.todoListID)
        }
        let openTodoItems = householdTodoItems.filter { !$0.isCompleted }
        let completedTodoItems = householdTodoItems.filter(\.isCompleted)
        let householdReturnRequests = returnRequests.filter {
            $0.householdID == householdID && !$0.isArchived
        }
        let returnPackagesByRequestID = Dictionary(
            grouping: returnPackages.filter { $0.householdID == householdID },
            by: \.returnRequestID
        )
        let returnStatuses = householdReturnRequests.map { request in
            returnStatusesByRequestID[request.id]
                ?? ReturnTrackingService.status(for: request, packages: returnPackagesByRequestID[request.id] ?? [])
        }
        let activeReturnCount = returnStatuses.filter { $0 != .completed }.count
        let returnStatusCounts = Dictionary(grouping: returnStatuses, by: { $0 }).mapValues(\.count)
        let activeListText = itemCountText(activeTodoLists.count, singular: "list", plural: "lists")
        let preparedItemText = itemCountText(activeMealPrep.count, singular: "prepared item", plural: "prepared items")
        let purchaseText = busiestStore.map {
            itemCountText($0.purchaseCount, singular: "purchase", plural: "purchases")
        }

        return [
            FoodInsightMetric(
                title: "To-Do",
                value: "\(openTodoItems.count)",
                detail: "Open items across \(activeListText).",
                systemImage: "checklist"
            ),
            FoodInsightMetric(
                title: "Completed To-Dos",
                value: "\(completedTodoItems.count)",
                detail: "Items checked off in active lists.",
                systemImage: "checkmark.circle.fill"
            ),
            FoodInsightMetric(
                title: "Returns",
                value: "\(activeReturnCount)",
                detail: "\(returnStatusCounts[.needsAction, default: 0]) need action, \(returnStatusCounts[.readyToDropOff, default: 0]) ready.",
                systemImage: "shippingbox.fill"
            ),
            FoodInsightMetric(
                title: "Inventory",
                value: "\(availableInventory.count)",
                detail: "Available items across \(locations.filter { $0.householdID == householdID && !$0.isArchived }.count) locations.",
                systemImage: "cabinet.fill"
            ),
            FoodInsightMetric(
                title: "Meal Prep",
                value: formatted(totalServings),
                detail: "Servings available in \(preparedItemText).",
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
                detail: purchaseText.map { "\($0) recorded." } ?? "Finish a trip to build history.",
                systemImage: "repeat.circle.fill"
            )
        ]
    }

    private static func itemCountText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

@MainActor
enum FoodReminderService {
    static func createReminder(
        householdID: UUID,
        type: FoodReminderType,
        title: String,
        dateTime: Date,
        timeZoneIdentifier: String = CareTimeZoneSettings.effectiveIdentifier(),
        relatedTodoListID: UUID?,
        relatedShoppingListID: UUID?,
        relatedMealPrepItemID: UUID?,
        relatedReturnRequestID: UUID?,
        context: ModelContext
    ) async {
        let reminder = FoodReminder(
            householdID: householdID,
            type: type,
            title: title,
            relatedTodoListID: relatedTodoListID,
            relatedShoppingListID: relatedShoppingListID,
            relatedMealPrepItemID: relatedMealPrepItemID,
            relatedReturnRequestID: relatedReturnRequestID,
            dateTime: dateTime,
            timeZoneIdentifier: timeZoneIdentifier
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
    guard PersistenceService.save(context: context) else { return }
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
