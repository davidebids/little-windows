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
        assignedCaregiverName: String? = nil,
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
            assignedCaregiverName: normalizedActorName(assignedCaregiverName),
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
        assignedCaregiverName: String?,
        context: ModelContext,
        now: Date = Date()
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.title = trimmed
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.addedBy = normalizedActorName(addedBy)
        item.assignedCaregiverName = normalizedActorName(assignedCaregiverName)
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

    private static func normalizedActorName(_ name: String?) -> String? {
        name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private protocol SyncedDuplicateRepairModel: PersistentModel {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
}

extension HomeTodoItem: SyncedDuplicateRepairModel {}
extension HomeTodoList: SyncedDuplicateRepairModel {}
extension ShoppingList: SyncedDuplicateRepairModel {}
extension ShoppingListItem: SyncedDuplicateRepairModel {}

enum FoodHomeDuplicateRepairService {
    // CloudKit schedules work for every deleted managed object. Bound launch
    // maintenance so a damaged store cannot create hundreds of overlapping
    // background tasks or hold SQLite's WAL open for minutes.
    private static let maximumDeletesPerRun = 32

    @discardableResult
    @MainActor
    static func repair(context: ModelContext, saveChanges: Bool = true) -> Int {
        repairCore(context: context, saveChanges: saveChanges)
    }

    nonisolated static func repairInBackground(context: ModelContext) -> Int {
        repairCore(context: context, saveChanges: true)
    }

    nonisolated private static func repairCore(
        context: ModelContext,
        saveChanges: Bool
    ) -> Int {
        var duplicateCount = 0
        duplicateCount += deleteDuplicateModels(
            HomeTodoList.self,
            context: context,
            maximumCount: maximumDeletesPerRun - duplicateCount
        )
        duplicateCount += deleteDuplicateModels(
            HomeTodoItem.self,
            context: context,
            maximumCount: maximumDeletesPerRun - duplicateCount
        )
        duplicateCount += deleteDuplicateModels(
            ShoppingList.self,
            context: context,
            maximumCount: maximumDeletesPerRun - duplicateCount
        )
        duplicateCount += deleteDuplicateModels(
            ShoppingListItem.self,
            context: context,
            maximumCount: maximumDeletesPerRun - duplicateCount
        )
        guard duplicateCount > 0 else { return 0 }

        if saveChanges, !PersistenceService.save(context: context) {
            return 0
        }
        return duplicateCount
    }

    nonisolated private static func deleteDuplicateModels<Model: SyncedDuplicateRepairModel>(
        _ modelType: Model.Type,
        context: ModelContext,
        maximumCount: Int
    ) -> Int {
        guard maximumCount > 0 else { return 0 }
        let duplicates = duplicateModels(
            (try? context.fetch(FetchDescriptor<Model>())) ?? [],
            id: \.id,
            createdAt: \.createdAt,
            updatedAt: \.updatedAt
        )
        let boundedDuplicates = duplicates.prefix(maximumCount)
        boundedDuplicates.forEach(context.delete)
        return boundedDuplicates.count
    }

    nonisolated private static func duplicateModels<Model: PersistentModel>(
        _ models: [Model],
        id: KeyPath<Model, UUID>,
        createdAt: KeyPath<Model, Date>,
        updatedAt: KeyPath<Model, Date>
    ) -> [Model] {
        var canonicalByID = [UUID: Model]()
        var duplicates = [Model]()

        for model in models {
            let modelID = model[keyPath: id]
            guard let canonical = canonicalByID[modelID] else {
                canonicalByID[modelID] = model
                continue
            }
            let modelIsPreferred = model[keyPath: updatedAt] > canonical[keyPath: updatedAt]
                || (
                    model[keyPath: updatedAt] == canonical[keyPath: updatedAt]
                        && model[keyPath: createdAt] < canonical[keyPath: createdAt]
                )
            if modelIsPreferred {
                duplicates.append(canonical)
                canonicalByID[modelID] = model
            } else {
                duplicates.append(model)
            }
        }
        return duplicates
    }
}

@ModelActor
actor FoodHomeDuplicateRepairWorker {
    func repair() -> Int {
        FoodHomeDuplicateRepairService.repairInBackground(context: modelContext)
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

enum TodayHomeSummaryCategory: String, CaseIterable, Identifiable {
    case todos
    case shopping
    case kitchen
    case trips
    case returns
    case medications
    case appointments
    case routines
    case solids

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todos: "To-Do"
        case .shopping: "Shopping"
        case .kitchen: "Kitchen"
        case .trips: "Trips"
        case .returns: "Returns"
        case .medications: "Medication"
        case .appointments: "Appointment"
        case .routines: "Routine"
        case .solids: "Solids"
        }
    }

    var systemImage: String {
        switch self {
        case .todos: "checklist"
        case .shopping: "cart.fill"
        case .kitchen: "takeoutbag.and.cup.and.straw.fill"
        case .trips: "suitcase.rolling.fill"
        case .returns: "shippingbox.fill"
        case .medications: "pills.fill"
        case .appointments: "calendar.badge.clock"
        case .routines: "checklist"
        case .solids: "carrot.fill"
        }
    }

    var route: TodayHomeSummaryRoute {
        switch self {
        case .todos: .food(.todos)
        case .shopping: .food(.shopping)
        case .kitchen: .food(.mealPrep)
        case .trips: .food(.trips)
        case .returns: .food(.returns)
        case .medications, .appointments, .routines, .solids: .todayCare
        }
    }
}

enum TodayHomeSummaryRoute: Equatable {
    case food(FoodRouteCommand)
    case appointment(UUID, profileID: UUID?)
    case medications(profileID: UUID)
    case medication(UUID, profileID: UUID)
    case routines(profileID: UUID?)
    case plannedSolidMeal(UUID, profileID: UUID)
    case solidAllergen(String, profileID: UUID)
    case todayCare
}

struct TodayMedicationAttention: Equatable {
    var profileID: UUID
    var medicationID: UUID
    var regimenID: UUID
    var phaseID: UUID?
    var occurrenceKey: String
    var scheduledAt: Date
    var doseAmount: Double
    var doseUnit: String
}

enum TodayHomeSummaryUrgency: Int, Equatable {
    case normal
    case attention
    case urgent
}

struct TodayHomeSummaryItem: Identifiable, Equatable {
    var id: String
    var category: TodayHomeSummaryCategory
    var title: String
    var detail: String
    var badge: String?
    var systemImage: String
    var urgency: TodayHomeSummaryUrgency = .normal
    var route: TodayHomeSummaryRoute
    var sortDate: Date?
    var sourceKey: String?
    var sourceUpdatedAt: Date?
    var profileID: UUID?
    var profileName: String?
    var sourceLabel: String?
    var dueLabel: String?
    var isFamilyShared: Bool = false
    var acknowledgedByNames: [String] = []
    var currentCaregiverHasAcknowledged: Bool = false
    var claimedCaregiverIdentifier: String?
    var claimedCaregiverName: String?
    var supportsClaim: Bool = false
    var followUpID: UUID?
    var refillTaskID: UUID?
    var completionLabel: String?
    var medicationAttention: TodayMedicationAttention?
}

struct TodaySnoozedAttentionItem: Identifiable, Equatable {
    var item: TodayHomeSummaryItem
    var until: Date

    var id: String { item.id }
}

struct TodayHandoffNoteSummary: Identifiable, Equatable {
    var id: UUID
    var authorCaregiverIdentifier: String
    var authorName: String
    var body: String
    var sourceTitle: String?
    var sourceRoute: TodayHomeSummaryRoute?
    var createdAt: Date
    var updatedAt: Date
}

struct TodayHandoffActivitySummary: Identifiable, Equatable {
    var id: String
    var text: String
    var occurredAt: Date
}

struct TodayCaregiverHandoffSummary: Equatable {
    var activityCount: Int
    var newNoteCount: Int
    var recentActivities: [TodayHandoffActivitySummary]
    var notes: [TodayHandoffNoteSummary]
    var needsAcknowledgementItemID: String?
    var nextUpItemID: String?
    var latestObservedActivityAt: Date?

    var recentNotes: [TodayHandoffNoteSummary] {
        Array(notes.prefix(3))
    }

    var isEmpty: Bool {
        activityCount == 0
            && notes.isEmpty
            && needsAcknowledgementItemID == nil
            && nextUpItemID == nil
    }
}

struct TodayHomeSummarySection: Identifiable, Equatable {
    var id: TodayHomeSummaryCategory { category }
    var category: TodayHomeSummaryCategory
    var countLabel: String
    var summary: String
    var items: [TodayHomeSummaryItem]
    var remainderText: String?
    var emptyMessage: String
}

struct TodayHomeSummary: Equatable {
    var attentionItems: [TodayHomeSummaryItem]
    var allAttentionItems: [TodayHomeSummaryItem]
    var snoozedAttentionItems: [TodaySnoozedAttentionItem]
    var sections: [TodayHomeSummarySection]
    var handoff: TodayCaregiverHandoffSummary?

    var isQuiet: Bool {
        attentionItems.isEmpty
            && snoozedAttentionItems.isEmpty
            && sections.allSatisfy { $0.items.isEmpty }
            && (handoff?.isEmpty ?? true)
    }
}

@MainActor
enum TodayHomeSummaryService {
    static let visibleItemLimit = 3
    static let attentionItemLimit = 5

    static func summary(
        householdID: UUID,
        currentCaregiverName: String,
        todoLists: [HomeTodoList],
        todoItems: [HomeTodoItem],
        shoppingLists: [ShoppingList],
        shoppingItems: [ShoppingListItem],
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        mealPrepUsages: [MealPrepUsage],
        packingTrips: [PackingTrip],
        packingItems: [PackingItem],
        itineraryItems: [TripItineraryItem],
        returnRequests: [ReturnRequest],
        returnItems: [ReturnItem],
        returnPackages: [ReturnPackage],
        reminders: [FoodReminder],
        profiles: [CareProfile] = [],
        medications: [Medication] = [],
        medicationRegimens: [MedicationRegimen] = [],
        medicationPhases: [MedicationSchedulePhase] = [],
        medicationDoseRecords: [MedicationDoseRecord] = [],
        medicationRefillTasks: [MedicationRefillTask] = [],
        appointmentFollowUps: [AppointmentFollowUp] = [],
        careRoutines: [CareRoutine] = [],
        careRoutineRuns: [CareRoutineRun] = [],
        plannedSolidMeals: [PlannedSolidMeal] = [],
        solidAllergenProgress: [SolidAllergenProgress] = [],
        acknowledgements: [HouseholdAttentionAcknowledgement] = [],
        claims: [HouseholdAttentionClaim] = [],
        handoffNotes: [CaregiverHandoffNote] = [],
        familyCaregiverIdentities: [FamilyCaregiverIdentity] = [],
        currentCaregiverIdentifier: String = "",
        familySyncEnabled: Bool = false,
        handoffCheckpoint: Date? = nil,
        snoozeDefaults: UserDefaults = .standard,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayHomeSummary {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now.addingTimeInterval(86_400)

        let todoSection = todoSummary(
            householdID: householdID,
            caregiverName: currentCaregiverName,
            lists: todoLists,
            items: todoItems,
            dayStart: dayStart,
            dayEnd: dayEnd
        )
        let shoppingSection = shoppingSummary(
            householdID: householdID,
            lists: shoppingLists,
            items: shoppingItems,
            dayStart: dayStart,
            dayEnd: dayEnd
        )
        let kitchenResult = kitchenSummary(
            householdID: householdID,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems,
            usages: mealPrepUsages,
            dayStart: dayStart,
            dayEnd: dayEnd
        )
        let tripResult = tripSummary(
            householdID: householdID,
            trips: packingTrips,
            packingItems: packingItems,
            itineraryItems: itineraryItems,
            now: now,
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: calendar
        )
        let returnResult = returnsSummary(
            householdID: householdID,
            requests: returnRequests,
            items: returnItems,
            packages: returnPackages,
            dayStart: dayStart,
            dayEnd: dayEnd
        )
        let reminderAttention = reminderItems(
            householdID: householdID,
            reminders: reminders,
            now: now,
            dayEnd: dayEnd
        )
        let careAttention = careAttentionItems(
            householdID: householdID,
            profiles: profiles,
            medications: medications,
            medicationRegimens: medicationRegimens,
            medicationPhases: medicationPhases,
            medicationDoseRecords: medicationDoseRecords,
            medicationRefillTasks: medicationRefillTasks,
            appointmentFollowUps: appointmentFollowUps,
            careRoutines: careRoutines,
            careRoutineRuns: careRoutineRuns,
            plannedSolidMeals: plannedSolidMeals,
            solidAllergenProgress: solidAllergenProgress,
            now: now,
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: calendar
        )
        let allAttention = reminderAttention
            + kitchenResult.attention
            + tripResult.attention
            + returnResult.attention
            + careAttention
        let coordinatedAttention = applyCollaboration(
            to: allAttention,
            profiles: profiles,
            acknowledgements: acknowledgements,
            claims: claims,
            familyCaregiverIdentities: familyCaregiverIdentities,
            currentCaregiverIdentifier: currentCaregiverIdentifier,
            familySyncEnabled: familySyncEnabled
        )
        let sortedAttention = coordinatedAttention
            .sorted {
                if $0.urgency != $1.urgency {
                    return $0.urgency.rawValue > $1.urgency.rawValue
                }
                return ($0.sortDate ?? .distantFuture) < ($1.sortDate ?? .distantFuture)
            }
        let snoozes = HouseholdAttentionSnoozeStore.activeSnoozes(
            now: now,
            defaults: snoozeDefaults
        )
        let attention = sortedAttention.filter { item in
            guard let sourceKey = item.sourceKey else { return true }
            return snoozes[sourceKey] == nil
        }
        let snoozedAttention = sortedAttention.compactMap { item -> TodaySnoozedAttentionItem? in
            guard let sourceKey = item.sourceKey,
                  let until = snoozes[sourceKey] else { return nil }
            return TodaySnoozedAttentionItem(item: item, until: until)
        }.sorted { $0.until < $1.until }
        let sharedProfileIDs = Set(profiles.filter { $0.sharingScope == .family }.map(\.id))
        let handoff = familySyncEnabled ? handoffSummary(
            items: attention,
            followUps: appointmentFollowUps,
            acknowledgements: acknowledgements,
            claims: claims,
            notes: handoffNotes,
            sharedProfileIDs: sharedProfileIDs,
            caregiverNamesByIdentifier: Dictionary(
                familyCaregiverIdentities.map { ($0.caregiverIdentifier, $0.displayName) },
                uniquingKeysWith: { first, _ in first }
            ),
            currentCaregiverIdentifier: currentCaregiverIdentifier,
            checkpoint: handoffCheckpoint ?? now.addingTimeInterval(-12 * 60 * 60),
            sourceRoutesByKey: handoffSourceRoutes(
                householdID: householdID,
                items: sortedAttention,
                notes: handoffNotes,
                sharedProfileIDs: sharedProfileIDs,
                inventoryItems: inventoryItems,
                mealPrepItems: mealPrepItems,
                packingTrips: packingTrips,
                returnRequests: returnRequests,
                reminders: reminders,
                medicationRegimens: medicationRegimens,
                medicationRefillTasks: medicationRefillTasks,
                appointmentFollowUps: appointmentFollowUps,
                careRoutines: careRoutines,
                careRoutineRuns: careRoutineRuns,
                plannedSolidMeals: plannedSolidMeals,
                solidAllergenProgress: solidAllergenProgress
            )
        ) : nil

        return TodayHomeSummary(
            attentionItems: Array(attention.prefix(attentionItemLimit)),
            allAttentionItems: attention,
            snoozedAttentionItems: snoozedAttention,
            sections: [
                todoSection,
                shoppingSection,
                kitchenResult.section,
                tripResult.section,
                returnResult.section
            ],
            handoff: handoff
        )
    }

    private static func careAttentionItems(
        householdID: UUID,
        profiles: [CareProfile],
        medications: [Medication],
        medicationRegimens: [MedicationRegimen],
        medicationPhases: [MedicationSchedulePhase],
        medicationDoseRecords: [MedicationDoseRecord],
        medicationRefillTasks: [MedicationRefillTask],
        appointmentFollowUps: [AppointmentFollowUp],
        careRoutines: [CareRoutine],
        careRoutineRuns: [CareRoutineRun],
        plannedSolidMeals: [PlannedSolidMeal],
        solidAllergenProgress: [SolidAllergenProgress],
        now: Date,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [TodayHomeSummaryItem] {
        let activeProfiles = profiles.filter { !$0.isArchived }
        let profilesByID = latestValuesByID(
            activeProfiles,
            id: \.id,
            updatedAt: \.updatedAt
        )
        var items = medicationAttentionItems(
            profilesByID: profilesByID,
            medications: medications,
            regimens: medicationRegimens,
            phases: medicationPhases,
            records: medicationDoseRecords,
            now: now
        )
        let medicationIDsWithOpenRefills = Set(
            medicationRefillTasks.filter(\.isOpen).map(\.medicationID)
        )
        let supplyProjections = MedicationService.supplyProjections(
            medications: medications,
            doseRecords: medicationDoseRecords,
            now: now,
            calendar: calendar
        )
        let medicationsByID = latestValuesByID(
            medications,
            id: \.id,
            updatedAt: \.updatedAt
        )
        items.append(contentsOf: medications.compactMap { medication in
            guard !medication.isArchived,
                  !medicationIDsWithOpenRefills.contains(medication.id),
                  let profileID = medication.profileID,
                  let profile = profilesByID[profileID] else { return nil }
            let projection = supplyProjections[medication.id]
            let projectedPlanningDate = projection.flatMap {
                calendar.date(
                    byAdding: .day,
                    value: -medication.refillLeadDays,
                    to: $0.estimatedRunOutDate
                )
            }
            let planningDate: Date
            if medication.needsRefill {
                planningDate = min(projectedPlanningDate ?? now, now)
            } else if let projectedPlanningDate {
                planningDate = projectedPlanningDate
            } else {
                return nil
            }
            guard planningDate < dayEnd else { return nil }
            let renewalNeeded = medication.refillsRemaining == 0
                || medication.prescriptionExpirationDate.map { $0 < now } == true
            let detail = projection.map {
                "Estimated run-out \($0.estimatedRunOutDate.formatted(date: .abbreviated, time: .omitted)) · \(profile.name)"
            } ?? "Supply is at or below the refill alert · \(profile.name)"
            return TodayHomeSummaryItem(
                id: "attention-refill-plan-\(medication.id.uuidString)",
                category: .medications,
                title: renewalNeeded
                    ? "Renew prescription for \(medication.name)"
                    : "Start refill for \(medication.name)",
                detail: detail,
                badge: renewalNeeded ? "Renewal" : "Refill due",
                systemImage: renewalNeeded
                    ? "doc.badge.clock.fill"
                    : "calendar.badge.exclamationmark",
                urgency: planningDate <= now ? .attention : .normal,
                route: .medication(medication.id, profileID: profileID),
                sortDate: planningDate,
                sourceUpdatedAt: medication.updatedAt,
                profileID: profileID,
                profileName: profile.name,
                sourceLabel: renewalNeeded ? "Prescription renewal" : "Medication refill",
                dueLabel: dueText(planningDate, now: now, calendar: calendar)
            )
        })
        items.append(contentsOf: medicationRefillTasks.compactMap { task in
            guard task.householdID == householdID,
                  task.isOpen,
                  let profileID = task.profileID,
                  let profile = profilesByID[profileID],
                  let medication = medicationsByID[task.medicationID],
                  !medication.isArchived else { return nil }
            let urgency = task.status == .readyForPickup
                ? TodayHomeSummaryUrgency.attention
                : dueUrgency(task.dueDate, now: now, dayEnd: dayEnd)
            let timing = task.dueDate.map { dueText($0, now: now, calendar: calendar) }
                ?? "No due date"
            let actionLabel: String = switch task.status {
            case .needsRequest: "Mark requested"
            case .requested: "Ready for pickup"
            case .readyForPickup: "Picked up"
            case .pickedUp, .cancelled: "Complete"
            }
            return TodayHomeSummaryItem(
                id: "attention-refill-\(task.id.uuidString)",
                category: .medications,
                title: "Refill \(medication.name)",
                detail: "\(task.status.displayName) · \(profile.name)",
                badge: task.status == .readyForPickup ? "Pickup" : "Refill",
                systemImage: task.status == .readyForPickup
                    ? "bag.badge.checkmark.fill"
                    : "pills.circle.fill",
                urgency: urgency,
                route: .medication(medication.id, profileID: profileID),
                sortDate: task.dueDate ?? task.updatedAt,
                sourceKey: task.attentionSourceKey,
                sourceUpdatedAt: task.updatedAt,
                profileID: profileID,
                profileName: profile.name,
                sourceLabel: "Medication refill",
                dueLabel: timing,
                claimedCaregiverIdentifier: task.assignedCaregiverIdentifier,
                claimedCaregiverName: task.assignedCaregiverName,
                supportsClaim: true,
                refillTaskID: task.id,
                completionLabel: actionLabel
            )
        })
        items.append(contentsOf: appointmentFollowUps.compactMap { followUp in
            guard followUp.householdID == householdID,
                  !followUp.isCompleted,
                  followUp.profileID.map({ profilesByID[$0] != nil }) ?? true else {
                return nil
            }
            let profile = followUp.profileID.flatMap { profilesByID[$0] }
            let urgency = dueUrgency(followUp.dueDate, now: now, dayEnd: dayEnd)
            let timing = followUp.dueDate.map { dueText($0, now: now, calendar: calendar) }
                ?? "No due date"
            return TodayHomeSummaryItem(
                id: "attention-follow-up-\(followUp.id.uuidString)",
                category: .appointments,
                title: followUp.title,
                detail: [timing, profile?.name].compactMap { $0 }.joined(separator: " · "),
                badge: urgency == .urgent ? "Overdue" : "Follow-up",
                systemImage: "checklist.checked",
                urgency: urgency,
                route: .appointment(followUp.appointmentID, profileID: followUp.profileID),
                sortDate: followUp.dueDate ?? followUp.updatedAt,
                sourceKey: followUp.attentionSourceKey,
                sourceUpdatedAt: followUp.updatedAt,
                profileID: followUp.profileID,
                profileName: profile?.name,
                sourceLabel: "Appointment",
                dueLabel: timing,
                supportsClaim: true,
                followUpID: followUp.id
            )
        })
        items.append(contentsOf: routineAttentionItems(
            householdID: householdID,
            profilesByID: profilesByID,
            routines: careRoutines,
            runs: careRoutineRuns,
            now: now,
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: calendar
        ))
        items.append(contentsOf: plannedSolidMeals.compactMap { plan in
            guard !plan.isCompleted,
                  plan.scheduledAt < dayEnd,
                  let profile = profilesByID[plan.profileID] else { return nil }
            let overdue = plan.scheduledAt < now
            return TodayHomeSummaryItem(
                id: "attention-solids-plan-\(plan.id.uuidString)",
                category: .solids,
                title: plan.title,
                detail: "\(dueText(plan.scheduledAt, now: now, calendar: calendar)) · \(profile.name)",
                badge: overdue ? "Overdue" : "Planned meal",
                systemImage: "fork.knife.circle.fill",
                urgency: overdue ? .urgent : .attention,
                route: .plannedSolidMeal(plan.id, profileID: plan.profileID),
                sortDate: plan.scheduledAt,
                sourceKey: "\(HouseholdAttentionSourceKind.plannedSolidMeal.rawValue):\(plan.id.uuidString.lowercased())",
                sourceUpdatedAt: plan.updatedAt,
                profileID: plan.profileID,
                profileName: profile.name,
                sourceLabel: "Planned Solids",
                dueLabel: dueText(plan.scheduledAt, now: now, calendar: calendar)
            )
        })
        items.append(contentsOf: solidAllergenProgress.compactMap { progress in
            guard let dueDate = progress.nextExposureDueAt,
                  dueDate < dayEnd,
                  progress.status != .suspectedReaction,
                  progress.status != .avoidPendingAdvice,
                  let profile = profilesByID[progress.profileID],
                  let allergen = SolidsAllergen(rawValue: progress.allergenID) else {
                return nil
            }
            let overdue = dueDate < now
            return TodayHomeSummaryItem(
                id: "attention-allergen-\(progress.id.uuidString)",
                category: .solids,
                title: "\(allergen.displayName) follow-up",
                detail: "\(dueText(dueDate, now: now, calendar: calendar)) · \(profile.name)",
                badge: overdue ? "Overdue" : "Allergen",
                systemImage: "checklist",
                urgency: overdue ? .urgent : .attention,
                route: .solidAllergen(progress.allergenID, profileID: progress.profileID),
                sortDate: dueDate,
                sourceKey: "\(HouseholdAttentionSourceKind.solidAllergen.rawValue):\(progress.id.uuidString.lowercased())",
                sourceUpdatedAt: progress.updatedAt,
                profileID: progress.profileID,
                profileName: profile.name,
                sourceLabel: "Allergen",
                dueLabel: dueText(dueDate, now: now, calendar: calendar)
            )
        })
        return items
    }

    private static func medicationAttentionItems(
        profilesByID: [UUID: CareProfile],
        medications: [Medication],
        regimens: [MedicationRegimen],
        phases: [MedicationSchedulePhase],
        records: [MedicationDoseRecord],
        now: Date
    ) -> [TodayHomeSummaryItem] {
        let medicationsByID = latestValuesByID(
            medications.filter { !$0.isArchived },
            id: \.id,
            updatedAt: \.updatedAt
        )
        let phasesByRegimenID = Dictionary(grouping: phases, by: \.regimenID)
        let phasesByID = latestValuesByID(
            phases,
            id: \.id,
            updatedAt: \.updatedAt
        )
        var recordsByRegimenID = [UUID: [MedicationDoseRecord]]()
        for record in records {
            guard let regimenID = record.regimenID else { continue }
            recordsByRegimenID[regimenID, default: []].append(record)
        }
        let snoozedOccurrenceKeys = MedicationSnoozeStateStore.activeOccurrenceKeys(now: now)
        let rangeStart = now.addingTimeInterval(-24 * 60 * 60)
        let rangeEnd = now.addingTimeInterval(2 * 60 * 60)
        return regimens.filter { $0.isActive }.flatMap { regimen -> [TodayHomeSummaryItem] in
            guard let profileID = regimen.profileID,
                  let profile = profilesByID[profileID],
                  let medication = medicationsByID[regimen.medicationID] else { return [] }
            let occurrences = MedicationScheduleEngine.unloggedOccurrences(
                MedicationScheduleEngine.occurrences(
                    regimen: regimen,
                    phases: phasesByRegimenID[regimen.id] ?? [],
                    from: rangeStart,
                    through: rangeEnd
                ),
                records: recordsByRegimenID[regimen.id] ?? []
            ).filter {
                !snoozedOccurrenceKeys.contains($0.occurrenceKey)
            }
            return occurrences.map { occurrence in
                let overdueSeconds = now.timeIntervalSince(occurrence.scheduledAt)
                let urgency: TodayHomeSummaryUrgency = overdueSeconds > 30 * 60
                    ? .urgent
                    : (overdueSeconds >= 0 ? .attention : .normal)
                let sourceUpdatedAt = max(
                    max(medication.updatedAt, regimen.updatedAt),
                    occurrence.phaseID.flatMap { phasesByID[$0]?.updatedAt } ?? .distantPast
                )
                return TodayHomeSummaryItem(
                    id: "attention-medication-\(occurrence.occurrenceKey)",
                    category: .medications,
                    title: medication.name,
                    detail: "\(dueText(occurrence.scheduledAt, now: now, calendar: .current)) · \(profile.name)",
                    badge: overdueSeconds > 0 ? "Overdue" : "Due soon",
                    systemImage: "pills.fill",
                    urgency: urgency,
                    route: .medications(profileID: profileID),
                    sortDate: occurrence.scheduledAt,
                    sourceKey: "\(HouseholdAttentionSourceKind.medicationDose.rawValue):\(occurrence.occurrenceKey)",
                    sourceUpdatedAt: sourceUpdatedAt,
                    profileID: profileID,
                    profileName: profile.name,
                    sourceLabel: "Medication",
                    dueLabel: dueText(occurrence.scheduledAt, now: now, calendar: .current),
                    medicationAttention: TodayMedicationAttention(
                        profileID: profileID,
                        medicationID: medication.id,
                        regimenID: regimen.id,
                        phaseID: occurrence.phaseID,
                        occurrenceKey: occurrence.occurrenceKey,
                        scheduledAt: occurrence.scheduledAt,
                        doseAmount: occurrence.doseAmount,
                        doseUnit: occurrence.doseUnit
                    )
                )
            }
        }
    }

    private static func routineAttentionItems(
        householdID: UUID,
        profilesByID: [UUID: CareProfile],
        routines: [CareRoutine],
        runs: [CareRoutineRun],
        now: Date,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [TodayHomeSummaryItem] {
        routines.compactMap { routine in
            guard !routine.isArchived,
                  (routine.householdID == householdID || routine.profileID.map({ profilesByID[$0] != nil }) == true) else {
                return nil
            }
            let routineRuns = runs.filter { $0.routineID == routine.id }
            let activeRun = routineRuns.first { $0.state == .active }
            let completedToday = routineRuns.contains {
                $0.state == .completed && $0.completedAt.map { $0 >= dayStart && $0 < dayEnd } == true
            }
            let dueDate = routine.reminderTimeMinutesAfterMidnight.flatMap {
                calendar.date(byAdding: .minute, value: $0, to: dayStart)
            }
            let isDue = routine.reminderEnabled && dueDate.map { $0 <= now } == true && !completedToday
            guard activeRun != nil || isDue else { return nil }
            let profile = routine.profileID.flatMap { profilesByID[$0] }
            let sourceDate = activeRun?.startedAt ?? dueDate ?? routine.updatedAt
            let sourceKey = activeRun.map {
                "\(HouseholdAttentionSourceKind.routine.rawValue):run:\($0.id.uuidString.lowercased())"
            } ?? "\(HouseholdAttentionSourceKind.routine.rawValue):\(routine.id.uuidString.lowercased()):\(Int(dayStart.timeIntervalSince1970))"
            return TodayHomeSummaryItem(
                id: "attention-routine-\(routine.id.uuidString)",
                category: .routines,
                title: routine.title,
                detail: [activeRun == nil ? "Routine is due" : "Routine is in progress", profile?.name ?? "Household"]
                    .joined(separator: " · "),
                badge: activeRun == nil ? "Due" : "In progress",
                systemImage: routine.iconName,
                urgency: activeRun == nil && dueDate.map { now.timeIntervalSince($0) > 60 * 60 } == true
                    ? .urgent
                    : .attention,
                route: .routines(profileID: routine.profileID),
                sortDate: sourceDate,
                sourceKey: sourceKey,
                sourceUpdatedAt: max(routine.updatedAt, activeRun?.updatedAt ?? .distantPast),
                profileID: routine.profileID,
                profileName: profile?.name,
                sourceLabel: "Routine",
                dueLabel: activeRun == nil
                    ? dueDate.map { dueText($0, now: now, calendar: calendar) } ?? "Due now"
                    : "In progress"
            )
        }
    }

    private static func applyCollaboration(
        to items: [TodayHomeSummaryItem],
        profiles: [CareProfile],
        acknowledgements: [HouseholdAttentionAcknowledgement],
        claims: [HouseholdAttentionClaim],
        familyCaregiverIdentities: [FamilyCaregiverIdentity],
        currentCaregiverIdentifier: String,
        familySyncEnabled: Bool
    ) -> [TodayHomeSummaryItem] {
        let profilesByID = latestValuesByID(
            profiles,
            id: \.id,
            updatedAt: \.updatedAt
        )
        let acknowledgementsBySource = Dictionary(grouping: acknowledgements, by: \.sourceKey)
        let caregiverNamesByIdentifier = Dictionary(
            familyCaregiverIdentities.map { ($0.caregiverIdentifier, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        let claimsBySource = Dictionary(grouping: claims, by: \.sourceKey).compactMapValues {
            $0.max { $0.updatedAt < $1.updatedAt }
        }
        return items.map { item in
            var result = item
            guard familySyncEnabled, let sourceKey = item.sourceKey else { return result }
            let isShared = item.profileID.map {
                profilesByID[$0]?.sharingScope == .family
            } ?? (item.category != .appointments)
            guard isShared else { return result }
            result.isFamilyShared = true
            let sourceUpdatedAt = item.sourceUpdatedAt ?? .distantPast
            let validAcknowledgements = (acknowledgementsBySource[sourceKey] ?? []).filter {
                $0.sourceUpdatedAt >= sourceUpdatedAt
            }
            let latestAcknowledgementByCaregiver = Dictionary(
                grouping: validAcknowledgements,
                by: \.caregiverIdentifier
            ).compactMapValues { values in
                values.max { $0.updatedAt < $1.updatedAt }
            }
            result.acknowledgedByNames = latestAcknowledgementByCaregiver.values.map {
                caregiverNamesByIdentifier[$0.caregiverIdentifier] ?? $0.caregiverName
            }.sorted()
            result.currentCaregiverHasAcknowledged = validAcknowledgements.contains {
                $0.caregiverIdentifier == currentCaregiverIdentifier
            }
            if let claim = claimsBySource[sourceKey],
               let identifier = claim.caregiverIdentifier,
               !identifier.isEmpty {
                result.claimedCaregiverIdentifier = identifier
                result.claimedCaregiverName = caregiverNamesByIdentifier[identifier] ?? claim.caregiverName
            }
            return result
        }
    }

    private static func handoffSummary(
        items: [TodayHomeSummaryItem],
        followUps: [AppointmentFollowUp],
        acknowledgements: [HouseholdAttentionAcknowledgement],
        claims: [HouseholdAttentionClaim],
        notes: [CaregiverHandoffNote],
        sharedProfileIDs: Set<UUID>,
        caregiverNamesByIdentifier: [String: String],
        currentCaregiverIdentifier: String,
        checkpoint: Date,
        sourceRoutesByKey: [String: TodayHomeSummaryRoute]
    ) -> TodayCaregiverHandoffSummary {
        let appointmentFollowUpPrefix = "\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):"
        let sharedFollowUpSourceKeys: Set<String> = Set(followUps.compactMap { followUp in
            guard followUp.profileID.map(sharedProfileIDs.contains) == true else { return nil }
            return followUp.attentionSourceKey
        })
        let isSharedInteraction: (UUID?, String?) -> Bool = { profileID, sourceKey in
            if let sourceKey, sourceKey.hasPrefix(appointmentFollowUpPrefix) {
                return sharedFollowUpSourceKeys.contains(sourceKey)
            }
            return profileID.map(sharedProfileIDs.contains) ?? true
        }
        let sharedNotes = notes.filter {
            isSharedInteraction($0.profileID, $0.sourceKey)
        }
        let sharedOtherNotes = sharedNotes.filter {
            $0.authorCaregiverIdentifier != currentCaregiverIdentifier
        }
        let sharedOtherAcknowledgements = acknowledgements.filter {
            isSharedInteraction($0.profileID, $0.sourceKey)
                && $0.caregiverIdentifier != currentCaregiverIdentifier
        }
        let sharedOtherClaims = claims.filter {
            isSharedInteraction($0.profileID, $0.sourceKey)
                && $0.updatedByCaregiverIdentifier != currentCaregiverIdentifier
        }
        let sharedOtherCompletions = followUps.filter {
            $0.profileID.map(sharedProfileIDs.contains) == true
                && $0.completedByCaregiverIdentifier.map {
                    !$0.isEmpty && $0 != currentCaregiverIdentifier
                } == true
                && $0.completedAt != nil
        }
        let newNotes = sharedOtherNotes.filter { $0.updatedAt > checkpoint }
            .sorted { $0.updatedAt > $1.updatedAt }
        let recentNotes = sharedNotes.sorted { $0.updatedAt > $1.updatedAt }
        let acknowledgementUpdates = sharedOtherAcknowledgements.filter { $0.updatedAt > checkpoint }
        let claimUpdates = sharedOtherClaims.filter { $0.updatedAt > checkpoint }
        let completedFollowUps = sharedOtherCompletions.filter {
            $0.completedAt.map { $0 > checkpoint } == true
        }
        let activeItemTitlesBySource = Dictionary(
            items.compactMap { item in
                item.sourceKey.map { ($0, item.title) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let recentActivities = (
            acknowledgementUpdates.map { acknowledgement in
                let caregiverName = caregiverNamesByIdentifier[acknowledgement.caregiverIdentifier]
                    ?? acknowledgement.caregiverName
                return TodayHandoffActivitySummary(
                    id: "ack-\(acknowledgement.id.uuidString)",
                    text: "\(caregiverName) saw \(activeItemTitlesBySource[acknowledgement.sourceKey] ?? "a shared item")",
                    occurredAt: acknowledgement.updatedAt
                )
            }
            + claimUpdates.map { claim in
                let title = activeItemTitlesBySource[claim.sourceKey] ?? "a shared follow-up"
                let updaterName = caregiverNamesByIdentifier[claim.updatedByCaregiverIdentifier]
                    ?? claim.updatedByCaregiverName
                let assignment = claim.caregiverIdentifier.flatMap {
                    caregiverNamesByIdentifier[$0]
                } ?? claim.caregiverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = assignment.isEmpty
                    ? "\(updaterName) cleared responsibility for \(title)"
                    : "\(updaterName) assigned \(title) to \(assignment)"
                return TodayHandoffActivitySummary(
                    id: "claim-\(claim.id.uuidString)",
                    text: text,
                    occurredAt: claim.updatedAt
                )
            }
            + completedFollowUps.compactMap { followUp in
                guard let completedAt = followUp.completedAt else { return nil }
                let caregiverName = followUp.completedByCaregiverIdentifier.flatMap {
                    caregiverNamesByIdentifier[$0]
                } ?? followUp.completedByCaregiverName ?? "A caregiver"
                return TodayHandoffActivitySummary(
                    id: "completed-\(followUp.id.uuidString)",
                    text: "\(caregiverName) completed \(followUp.title)",
                    occurredAt: completedAt
                )
            }
        ).sorted { $0.occurredAt > $1.occurredAt }
        let latestObservedActivityAt = (
            sharedOtherNotes.map(\.updatedAt)
                + sharedOtherAcknowledgements.map(\.updatedAt)
                + sharedOtherClaims.map(\.updatedAt)
                + sharedOtherCompletions.compactMap(\.completedAt)
        ).max()
        let needsAcknowledgement = items.first {
            $0.isFamilyShared && !$0.currentCaregiverHasAcknowledged
        }
        let nextUp = items.first {
            $0.isFamilyShared
                && $0.supportsClaim
                && $0.claimedCaregiverIdentifier == currentCaregiverIdentifier
        }
        return TodayCaregiverHandoffSummary(
            activityCount: newNotes.count
                + acknowledgementUpdates.count
                + claimUpdates.count
                + completedFollowUps.count,
            newNoteCount: newNotes.count,
            recentActivities: Array(recentActivities.prefix(4)),
            notes: recentNotes.map {
                TodayHandoffNoteSummary(
                    id: $0.id,
                    authorCaregiverIdentifier: $0.authorCaregiverIdentifier,
                    authorName: caregiverNamesByIdentifier[$0.authorCaregiverIdentifier]
                        ?? $0.authorCaregiverName,
                    body: $0.body,
                    sourceTitle: $0.sourceTitleSnapshot,
                    sourceRoute: $0.sourceKey.flatMap { sourceRoutesByKey[$0] },
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            needsAcknowledgementItemID: needsAcknowledgement?.id,
            nextUpItemID: nextUp?.id,
            latestObservedActivityAt: latestObservedActivityAt
        )
    }

    private static func handoffSourceRoutes(
        householdID: UUID,
        items: [TodayHomeSummaryItem],
        notes: [CaregiverHandoffNote],
        sharedProfileIDs: Set<UUID>,
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        packingTrips: [PackingTrip],
        returnRequests: [ReturnRequest],
        reminders: [FoodReminder],
        medicationRegimens: [MedicationRegimen],
        medicationRefillTasks: [MedicationRefillTask],
        appointmentFollowUps: [AppointmentFollowUp],
        careRoutines: [CareRoutine],
        careRoutineRuns: [CareRoutineRun],
        plannedSolidMeals: [PlannedSolidMeal],
        solidAllergenProgress: [SolidAllergenProgress]
    ) -> [String: TodayHomeSummaryRoute] {
        var routes = Dictionary(
            items.compactMap { item in
                item.sourceKey.map { ($0, item.route) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let sourceKeys = Set(notes.compactMap { note in
            note.householdID == householdID ? note.sourceKey : nil
        })
        let routinesByID = latestValuesByID(
            careRoutines,
            id: \.id,
            updatedAt: \.updatedAt
        )
        let routineRunsByID = latestValuesByID(
            careRoutineRuns,
            id: \.id,
            updatedAt: \.updatedAt
        )

        for sourceKey in sourceKeys where routes[sourceKey] == nil {
            guard let separator = sourceKey.firstIndex(of: ":"),
                  let kind = HouseholdAttentionSourceKind(
                    rawValue: String(sourceKey[..<separator])
                  ) else { continue }
            let value = String(sourceKey[sourceKey.index(after: separator)...])

            switch kind {
            case .appointmentFollowUp:
                guard let id = UUID(uuidString: value),
                      let followUp = appointmentFollowUps.first(where: {
                          $0.id == id
                              && $0.householdID == householdID
                              && $0.profileID.map(sharedProfileIDs.contains) == true
                      }) else { continue }
                routes[sourceKey] = .appointment(
                    followUp.appointmentID,
                    profileID: followUp.profileID
                )

            case .medicationDose:
                guard let regimenIDText = value.split(separator: "|", maxSplits: 1).first,
                      let regimenID = UUID(uuidString: String(regimenIDText)),
                      let profileID = medicationRegimens.first(where: { $0.id == regimenID })?.profileID,
                      sharedProfileIDs.contains(profileID) else { continue }
                routes[sourceKey] = .medications(profileID: profileID)

            case .medicationRefill:
                guard let refillID = UUID(uuidString: value),
                      let refillTask = medicationRefillTasks.first(where: {
                          $0.id == refillID && $0.householdID == householdID
                      }),
                      let profileID = refillTask.profileID,
                      sharedProfileIDs.contains(profileID) else { continue }
                routes[sourceKey] = .medication(
                    refillTask.medicationID,
                    profileID: profileID
                )

            case .routine:
                let components = value.split(separator: ":")
                let routineID: UUID?
                if components.first == "run",
                   components.count > 1,
                   let runID = UUID(uuidString: String(components[1])) {
                    routineID = routineRunsByID[runID]?.routineID
                } else {
                    routineID = components.first.flatMap { UUID(uuidString: String($0)) }
                }
                guard let routineID,
                      let routine = routinesByID[routineID],
                      routine.profileID.map(sharedProfileIDs.contains)
                        ?? (routine.householdID == householdID) else { continue }
                routes[sourceKey] = .routines(profileID: routine.profileID)

            case .inventory:
                guard let id = UUID(uuidString: value),
                      inventoryItems.contains(where: {
                          $0.id == id && $0.householdID == householdID
                      }) else { continue }
                routes[sourceKey] = .food(.inventoryItem(id))

            case .mealPrep:
                guard let id = UUID(uuidString: value),
                      mealPrepItems.contains(where: {
                          $0.id == id && $0.householdID == householdID
                      }) else { continue }
                routes[sourceKey] = .food(.mealPrepItem(id))

            case .returnRequest:
                guard let id = UUID(uuidString: value),
                      returnRequests.contains(where: {
                          $0.id == id && $0.householdID == householdID
                      }) else { continue }
                routes[sourceKey] = .food(.returnRequest(id))

            case .trip:
                guard let id = UUID(uuidString: value),
                      packingTrips.contains(where: {
                          $0.id == id && $0.householdID == householdID
                      }) else { continue }
                routes[sourceKey] = .food(.packingList(id))

            case .plannedSolidMeal:
                guard let id = UUID(uuidString: value),
                      let plan = plannedSolidMeals.first(where: {
                          $0.id == id && sharedProfileIDs.contains($0.profileID)
                      }) else { continue }
                routes[sourceKey] = .plannedSolidMeal(id, profileID: plan.profileID)

            case .solidAllergen:
                guard let id = UUID(uuidString: value),
                      let progress = solidAllergenProgress.first(where: {
                          $0.id == id && sharedProfileIDs.contains($0.profileID)
                      }) else { continue }
                routes[sourceKey] = .solidAllergen(
                    progress.allergenID,
                    profileID: progress.profileID
                )

            case .homeReminder:
                guard let id = UUID(uuidString: value),
                      let reminder = reminders.first(where: {
                          $0.id == id && $0.householdID == householdID
                      }) else { continue }
                routes[sourceKey] = .food(route(for: reminder))
            }
        }

        return routes
    }

    private static func dueUrgency(
        _ dueDate: Date?,
        now: Date,
        dayEnd: Date
    ) -> TodayHomeSummaryUrgency {
        guard let dueDate else { return .normal }
        if dueDate < now { return .urgent }
        return dueDate < dayEnd ? .attention : .normal
    }

    private static func dueText(_ date: Date, now: Date, calendar: Calendar) -> String {
        if date < now {
            return "Overdue · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        if calendar.isDateInToday(date) {
            return "Due today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Due tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Due \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func todoSummary(
        householdID: UUID,
        caregiverName: String,
        lists: [HomeTodoList],
        items: [HomeTodoItem],
        dayStart: Date,
        dayEnd: Date
    ) -> TodayHomeSummarySection {
        let listsByID = latestValuesByID(
            lists,
            id: \.id,
            updatedAt: \.updatedAt
        ).filter { _, list in
            list.householdID == householdID && !list.isArchived
        }
        let activeLists = Array(listsByID.values)
        let scopedItems = latestValuesByID(
            items,
            id: \.id,
            updatedAt: \.updatedAt
        ).values.filter {
            $0.householdID == householdID && listsByID[$0.todoListID] != nil
        }
        let completedToday = scopedItems.filter {
            $0.isCompleted && isInDay($0.completedAt, start: dayStart, end: dayEnd)
        }
        let normalizedCaregiver = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let openItems = scopedItems.filter { !$0.isCompleted }.sorted { lhs, rhs in
            let lhsIsCurrent = !normalizedCaregiver.isEmpty && lhs.assignedCaregiverName == normalizedCaregiver
            let rhsIsCurrent = !normalizedCaregiver.isEmpty && rhs.assignedCaregiverName == normalizedCaregiver
            if lhsIsCurrent != rhsIsCurrent { return lhsIsCurrent }
            let lhsOrder = lhs.sortOrder ?? Int.max
            let rhsOrder = rhs.sortOrder ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.updatedAt > rhs.updatedAt
        }
        let visible = openItems.prefix(visibleItemLimit).map { item in
            let listName = listsByID[item.todoListID]?.name ?? "To-Do"
            let assignee = item.assignedCaregiverName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = [listName, assignee.flatMap { $0.isEmpty ? nil : "Assigned to \($0)" }]
                .compactMap { $0 }
                .joined(separator: " · ")
            return TodayHomeSummaryItem(
                id: "todo-\(item.id.uuidString)",
                category: .todos,
                title: item.title,
                detail: detail,
                systemImage: "circle",
                route: .food(.todoList(item.todoListID)),
                sortDate: item.updatedAt
            )
        }

        return TodayHomeSummarySection(
            category: .todos,
            countLabel: countText(openItems.count, singular: "open", plural: "open"),
            summary: "\(countText(activeLists.count, singular: "active list", plural: "active lists")) · \(completedToday.count) completed today",
            items: Array(visible),
            remainderText: remainderText(openItems.count - visible.count, noun: "task"),
            emptyMessage: "No open household to-dos."
        )
    }

    private static func shoppingSummary(
        householdID: UUID,
        lists: [ShoppingList],
        items: [ShoppingListItem],
        dayStart: Date,
        dayEnd: Date
    ) -> TodayHomeSummarySection {
        let activeLists = latestValuesByID(
            lists,
            id: \.id,
            updatedAt: \.updatedAt
        ).values.filter { $0.householdID == householdID && !$0.isArchived }
        let listIDs = Set(activeLists.map(\.id))
        let scopedItems = latestValuesByID(
            items,
            id: \.id,
            updatedAt: \.updatedAt
        ).values.filter {
            $0.householdID == householdID && listIDs.contains($0.shoppingListID)
        }
        let openItems = scopedItems.filter { !$0.isChecked }
        let checkedToday = scopedItems.filter {
            $0.isChecked && isInDay($0.checkedAt, start: dayStart, end: dayEnd)
        }
        let openByList = Dictionary(grouping: openItems, by: \.shoppingListID)
        let listsWithItems = activeLists.filter { !(openByList[$0.id] ?? []).isEmpty }.sorted { lhs, rhs in
            let lhsItems = openByList[lhs.id] ?? []
            let rhsItems = openByList[rhs.id] ?? []
            let lhsHigh = lhsItems.filter { $0.priority == .high }.count
            let rhsHigh = rhsItems.filter { $0.priority == .high }.count
            if lhsHigh != rhsHigh { return lhsHigh > rhsHigh }
            if lhsItems.count != rhsItems.count { return lhsItems.count > rhsItems.count }
            return lhs.updatedAt > rhs.updatedAt
        }
        let visible = listsWithItems.prefix(visibleItemLimit).map { list in
            let listItems = (openByList[list.id] ?? []).sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority == .high }
                return (lhs.sortOrder ?? Int.max) < (rhs.sortOrder ?? Int.max)
            }
            let names = listItems.prefix(2).map(\.name).joined(separator: ", ")
            let extra = max(0, listItems.count - 2)
            let detail = extra > 0 ? "\(names) + \(extra) more" : names
            let highCount = listItems.filter { $0.priority == .high }.count
            return TodayHomeSummaryItem(
                id: "shopping-\(list.id.uuidString)",
                category: .shopping,
                title: list.name,
                detail: detail,
                badge: highCount > 0 ? countText(highCount, singular: "high priority", plural: "high priority") : nil,
                systemImage: "cart",
                urgency: highCount > 0 ? .attention : .normal,
                route: .food(.shoppingList(list.id)),
                sortDate: list.updatedAt
            )
        }

        return TodayHomeSummarySection(
            category: .shopping,
            countLabel: countText(openItems.count, singular: "item", plural: "items"),
            summary: "\(countText(listsWithItems.count, singular: "active list", plural: "active lists")) · \(checkedToday.count) checked today",
            items: Array(visible),
            remainderText: remainderText(listsWithItems.count - visible.count, noun: "list"),
            emptyMessage: "Shopping lists are clear."
        )
    }

    private static func latestValuesByID<Value>(
        _ values: [Value],
        id: KeyPath<Value, UUID>,
        updatedAt: KeyPath<Value, Date>
    ) -> [UUID: Value] {
        Dictionary(
            values.map { ($0[keyPath: id], $0) },
            uniquingKeysWith: { current, candidate in
                candidate[keyPath: updatedAt] > current[keyPath: updatedAt]
                    ? candidate
                    : current
            }
        )
    }

    private static func kitchenSummary(
        householdID: UUID,
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        usages: [MealPrepUsage],
        dayStart: Date,
        dayEnd: Date
    ) -> (section: TodayHomeSummarySection, attention: [TodayHomeSummaryItem]) {
        let activePrep = mealPrepItems.filter { $0.householdID == householdID && !$0.isArchived }
        let todayUsages = usages.filter {
            $0.householdID == householdID && isInDay($0.dateTime, start: dayStart, end: dayEnd)
        }
        let usageByItem = Dictionary(grouping: todayUsages, by: \.mealPrepItemID)
        let usedUpInventory = inventoryItems.filter {
            $0.householdID == householdID && $0.status == .usedUp
        }.sorted { $0.updatedAt > $1.updatedAt }
        let sortedPrep = activePrep.sorted { lhs, rhs in
            if lhs.servingsRemaining != rhs.servingsRemaining {
                return lhs.servingsRemaining < rhs.servingsRemaining
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        var representativeItems = sortedPrep.map { item in
            let usedToday = (usageByItem[item.id] ?? []).reduce(0) { $0 + $1.servingsUsed }
            let usageDetail = usedToday > 0 ? " · \(formatted(usedToday)) used today" : ""
            return TodayHomeSummaryItem(
                id: "meal-prep-\(item.id.uuidString)",
                category: .kitchen,
                title: item.name,
                detail: "\(item.servingsText)\(usageDetail)",
                badge: item.servingsRemaining <= 2 ? "Low" : nil,
                systemImage: "takeoutbag.and.cup.and.straw",
                urgency: item.servingsRemaining <= 0 ? .urgent : (item.servingsRemaining <= 2 ? .attention : .normal),
                route: .food(.mealPrepItem(item.id)),
                sortDate: item.updatedAt
            )
        }
        if representativeItems.count < visibleItemLimit {
            representativeItems.append(contentsOf: usedUpInventory.prefix(visibleItemLimit - representativeItems.count).map { item in
                TodayHomeSummaryItem(
                    id: "inventory-\(item.id.uuidString)",
                    category: .kitchen,
                    title: item.name,
                    detail: "Marked used up",
                    badge: "Inventory",
                    systemImage: "cabinet",
                    urgency: .attention,
                    route: .food(.inventoryItem(item.id)),
                    sortDate: item.updatedAt
                )
            })
        }
        let visible = Array(representativeItems.prefix(visibleItemLimit))
        let totalServings = activePrep.reduce(0) { $0 + $1.servingsRemaining }
        let usedToday = todayUsages.reduce(0) { $0 + $1.servingsUsed }
        let lowPrepAttention = sortedPrep.filter { $0.servingsRemaining <= 2 }.prefix(2).map { item in
            TodayHomeSummaryItem(
                id: "attention-meal-prep-\(item.id.uuidString)",
                category: .kitchen,
                title: item.servingsRemaining <= 0 ? "\(item.name) is finished" : "\(item.name) is running low",
                detail: item.servingsText,
                badge: "Meal Prep",
                systemImage: "exclamationmark.triangle.fill",
                urgency: item.servingsRemaining <= 0 ? .urgent : .attention,
                route: .food(.mealPrepItem(item.id)),
                sortDate: item.updatedAt,
                sourceKey: "\(HouseholdAttentionSourceKind.mealPrep.rawValue):\(item.id.uuidString.lowercased())",
                sourceUpdatedAt: item.updatedAt,
                sourceLabel: "Meal Prep",
                dueLabel: "Needs attention now"
            )
        }
        let usedUpAttention = usedUpInventory.prefix(2).map { item in
            TodayHomeSummaryItem(
                id: "attention-inventory-\(item.id.uuidString)",
                category: .kitchen,
                title: "\(item.name) is used up",
                detail: "Inventory needs review",
                badge: "Inventory",
                systemImage: "cabinet.fill",
                urgency: .attention,
                route: .food(.inventoryItem(item.id)),
                sortDate: item.updatedAt,
                sourceKey: "\(HouseholdAttentionSourceKind.inventory.rawValue):\(item.id.uuidString.lowercased())",
                sourceUpdatedAt: item.updatedAt,
                sourceLabel: "Inventory",
                dueLabel: "Needs attention now"
            )
        }

        return (
            TodayHomeSummarySection(
                category: .kitchen,
                countLabel: countText(activePrep.count, singular: "prepared item", plural: "prepared items"),
                summary: "\(formatted(totalServings)) servings ready · \(formatted(usedToday)) used today · \(usedUpInventory.count) used up",
                items: visible,
                remainderText: remainderText(max(0, activePrep.count + usedUpInventory.count - visible.count), noun: "item"),
                emptyMessage: "No meal prep or inventory items need attention."
            ),
            Array(lowPrepAttention + usedUpAttention)
        )
    }

    private static func tripSummary(
        householdID: UUID,
        trips: [PackingTrip],
        packingItems: [PackingItem],
        itineraryItems: [TripItineraryItem],
        now: Date,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> (section: TodayHomeSummarySection, attention: [TodayHomeSummaryItem]) {
        let activeTrips = trips.filter {
            $0.householdID == householdID && !$0.isArchived && $0.status == .upcoming && $0.completedAt == nil
        }.sorted { lhs, rhs in
            let lhsCurrent = lhs.startDate < dayEnd && lhs.endDate >= dayStart
            let rhsCurrent = rhs.startDate < dayEnd && rhs.endDate >= dayStart
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            return lhs.startDate < rhs.startDate
        }
        let activeTripIDs = Set(activeTrips.map(\.id))
        let packingByTrip = Dictionary(
            grouping: packingItems.filter { $0.householdID == householdID && activeTripIDs.contains($0.tripID) },
            by: \.tripID
        )
        let todayItinerary = itineraryItems.filter {
            guard $0.householdID == householdID, activeTripIDs.contains($0.tripID), !$0.isCompleted else {
                return false
            }
            return isInDay($0.scheduledDay, start: dayStart, end: dayEnd)
                || isInDay($0.startDate, start: dayStart, end: dayEnd)
        }.sorted {
            ($0.startDate ?? $0.scheduledDay ?? .distantFuture)
                < ($1.startDate ?? $1.scheduledDay ?? .distantFuture)
        }
        var representative = todayItinerary.prefix(2).map { item in
            TodayHomeSummaryItem(
                id: "itinerary-\(item.id.uuidString)",
                category: .trips,
                title: item.title,
                detail: "Today · \(activeTrips.first(where: { $0.id == item.tripID })?.title ?? "Trip itinerary")",
                badge: item.kind.displayName,
                systemImage: item.kind.systemImage,
                route: .food(.itineraryItem(item.tripID, item.id)),
                sortDate: item.startDate ?? item.scheduledDay
            )
        }
        for trip in activeTrips where representative.count < visibleItemLimit {
            let tripItems = packingByTrip[trip.id] ?? []
            let relevantItems = tripItems.filter { $0.state != .notNeeded }
            let packedCount = relevantItems.filter { $0.state == .packed }.count
            let isCurrent = trip.startDate < dayEnd && trip.endDate >= dayStart
            let daysUntil = calendar.dateComponents(
                [.day],
                from: dayStart,
                to: calendar.startOfDay(for: trip.startDate)
            ).day ?? 0
            let timing: String
            if isCurrent {
                timing = "Happening now"
            } else if daysUntil == 1 {
                timing = "Starts tomorrow"
            } else if daysUntil > 1 {
                timing = "Starts in \(daysUntil) days"
            } else {
                timing = "Starts today"
            }
            representative.append(TodayHomeSummaryItem(
                id: "trip-\(trip.id.uuidString)",
                category: .trips,
                title: trip.title,
                detail: "\(timing) · \(packedCount) of \(relevantItems.count) packed",
                badge: isCurrent ? "Today" : nil,
                systemImage: "suitcase.rolling",
                urgency: isCurrent ? .attention : .normal,
                route: .food(.packingTrip(trip.id)),
                sortDate: trip.startDate
            ))
        }
        let attention = activeTrips.compactMap { trip -> TodayHomeSummaryItem? in
            let tripItems = packingByTrip[trip.id] ?? []
            let sourceUpdatedAt = tripItems.map(\.updatedAt).max()
                .map { max(trip.updatedAt, $0) } ?? trip.updatedAt
            let neededEssentials = tripItems.filter { $0.state == .needed && $0.priority == .essential }.count
            let checkDate = [trip.finalCheckDate, trip.reminderDate].compactMap { $0 }.min()
            let startsSoon = trip.startDate < (calendar.date(byAdding: .day, value: 3, to: dayStart) ?? dayEnd)
            guard isBeforeEndOfDay(checkDate, dayEnd: dayEnd) || (startsSoon && neededEssentials > 0) else {
                return nil
            }
            let isOverdue = checkDate.map { $0 < now } == true
            let detail = neededEssentials > 0
                ? countText(neededEssentials, singular: "essential item still needed", plural: "essential items still needed")
                : "Trip check is due"
            return TodayHomeSummaryItem(
                id: "attention-trip-\(trip.id.uuidString)",
                category: .trips,
                title: "Review \(trip.title)",
                detail: detail,
                badge: "Trip",
                systemImage: "suitcase.rolling.fill",
                urgency: isOverdue ? .urgent : .attention,
                route: .food(.packingList(trip.id)),
                sortDate: checkDate ?? trip.startDate,
                sourceKey: "\(HouseholdAttentionSourceKind.trip.rawValue):\(trip.id.uuidString.lowercased())",
                sourceUpdatedAt: sourceUpdatedAt,
                sourceLabel: "Trip",
                dueLabel: dueText(checkDate ?? trip.startDate, now: now, calendar: calendar)
            )
        }
        let todayCount = activeTrips.filter { $0.startDate < dayEnd && $0.endDate >= dayStart }.count

        return (
            TodayHomeSummarySection(
                category: .trips,
                countLabel: countText(activeTrips.count, singular: "active trip", plural: "active trips"),
                summary: "\(todayCount) happening today · \(countText(todayItinerary.count, singular: "itinerary item today", plural: "itinerary items today"))",
                items: Array(representative.prefix(visibleItemLimit)),
                remainderText: remainderText(max(0, activeTrips.count + todayItinerary.count - representative.count), noun: "trip item"),
                emptyMessage: "No active or upcoming trips."
            ),
            attention
        )
    }

    private static func returnsSummary(
        householdID: UUID,
        requests: [ReturnRequest],
        items: [ReturnItem],
        packages: [ReturnPackage],
        dayStart: Date,
        dayEnd: Date
    ) -> (section: TodayHomeSummarySection, attention: [TodayHomeSummaryItem]) {
        let scopedRequests = requests.filter { $0.householdID == householdID && !$0.isArchived }
        let scopedItems = items.filter { $0.householdID == householdID }
        let scopedPackages = packages.filter { $0.householdID == householdID }
        let itemsByRequest = Dictionary(grouping: scopedItems, by: \.returnRequestID)
        let packagesByRequest = Dictionary(grouping: scopedPackages, by: \.returnRequestID)
        let active = scopedRequests.compactMap { request -> (ReturnRequest, ReturnRequestStatus, Date?)? in
            let requestPackages = packagesByRequest[request.id] ?? []
            let status = ReturnTrackingService.status(for: request, packages: requestPackages)
            guard status != .completed && status != .archived else { return nil }
            return (request, status, requestPackages.compactMap(\.returnByDate).min())
        }.sorted { lhs, rhs in
            let lhsUrgent = lhs.2.map { $0 < dayEnd } ?? false
            let rhsUrgent = rhs.2.map { $0 < dayEnd } ?? false
            if lhsUrgent != rhsUrgent { return lhsUrgent }
            return (lhs.2 ?? .distantFuture) < (rhs.2 ?? .distantFuture)
        }
        let visible = active.prefix(visibleItemLimit).map { request, status, returnByDate in
            let title = returnTitle(
                items: itemsByRequest[request.id] ?? [],
                packages: packagesByRequest[request.id] ?? []
            )
            let deadline = returnByDate.map { " · Return by \(DateFormatting.day.string(from: $0))" } ?? ""
            let urgency: TodayHomeSummaryUrgency = returnByDate.map {
                $0 < dayStart ? .urgent : ($0 < dayEnd ? .attention : .normal)
            } ?? .normal
            return TodayHomeSummaryItem(
                id: "return-\(request.id.uuidString)",
                category: .returns,
                title: title,
                detail: "\(status.displayName)\(deadline)",
                badge: urgency == .urgent ? "Overdue" : (urgency == .attention ? "Due today" : nil),
                systemImage: "shippingbox",
                urgency: urgency,
                route: .food(.returnRequest(request.id)),
                sortDate: returnByDate ?? request.updatedAt
            )
        }
        let attention = active.compactMap { request, status, returnByDate -> TodayHomeSummaryItem? in
            guard let returnByDate, returnByDate < dayEnd else { return nil }
            let overdue = returnByDate < dayStart
            let relatedUpdatedAt = (
                (itemsByRequest[request.id] ?? []).map(\.updatedAt)
                    + (packagesByRequest[request.id] ?? []).map(\.updatedAt)
            ).max()
            let sourceUpdatedAt = relatedUpdatedAt.map { max(request.updatedAt, $0) }
                ?? request.updatedAt
            return TodayHomeSummaryItem(
                id: "attention-return-\(request.id.uuidString)",
                category: .returns,
                title: returnTitle(
                    items: itemsByRequest[request.id] ?? [],
                    packages: packagesByRequest[request.id] ?? []
                ),
                detail: overdue ? "Return deadline has passed" : "Return is due today · \(status.displayName)",
                badge: overdue ? "Overdue" : "Due today",
                systemImage: "shippingbox.fill",
                urgency: overdue ? .urgent : .attention,
                route: .food(.returnRequest(request.id)),
                sortDate: returnByDate,
                sourceKey: "\(HouseholdAttentionSourceKind.returnRequest.rawValue):\(request.id.uuidString.lowercased())",
                sourceUpdatedAt: sourceUpdatedAt,
                sourceLabel: "Return",
                dueLabel: overdue
                    ? "Overdue · \(returnByDate.formatted(date: .abbreviated, time: .shortened))"
                    : "Due today at \(returnByDate.formatted(date: .omitted, time: .shortened))"
            )
        }
        let dueSoonCount = active.filter { $0.2.map { $0 < dayEnd } ?? false }.count

        return (
            TodayHomeSummarySection(
                category: .returns,
                countLabel: countText(active.count, singular: "active return", plural: "active returns"),
                summary: "\(dueSoonCount) due or overdue · \(active.filter { $0.1 == .readyToDropOff }.count) ready to drop off",
                items: Array(visible),
                remainderText: remainderText(active.count - visible.count, noun: "return"),
                emptyMessage: "No active returns."
            ),
            attention
        )
    }

    private static func reminderItems(
        householdID: UUID,
        reminders: [FoodReminder],
        now: Date,
        dayEnd: Date
    ) -> [TodayHomeSummaryItem] {
        reminders.filter {
            $0.householdID == householdID && $0.isEnabled && $0.dateTime < dayEnd
        }.map { reminder in
            let overdue = reminder.dateTime < now
            let category = category(for: reminder)
            return TodayHomeSummaryItem(
                id: "reminder-\(reminder.id.uuidString)",
                category: category,
                title: reminder.title,
                detail: overdue
                    ? "Home reminder is overdue"
                    : "Home reminder at \(DateFormatting.time.string(from: reminder.dateTime))",
                badge: overdue ? "Overdue" : "Today",
                systemImage: "bell.badge.fill",
                urgency: overdue ? .urgent : .attention,
                route: .food(route(for: reminder)),
                sortDate: reminder.dateTime,
                sourceKey: "\(HouseholdAttentionSourceKind.homeReminder.rawValue):\(reminder.id.uuidString.lowercased())",
                sourceUpdatedAt: reminder.updatedAt,
                sourceLabel: "Home Reminder",
                dueLabel: overdue
                    ? "Overdue · \(reminder.dateTime.formatted(date: .abbreviated, time: .shortened))"
                    : "Due today at \(DateFormatting.time.string(from: reminder.dateTime))"
            )
        }
    }

    private static func category(for reminder: FoodReminder) -> TodayHomeSummaryCategory {
        switch reminder.type {
        case .todos: .todos
        case .shopping: .shopping
        case .mealPrep: .kitchen
        case .returns: .returns
        case .custom: .todos
        }
    }

    private static func route(for reminder: FoodReminder) -> FoodRouteCommand {
        if let id = reminder.relatedTodoListID { return .todoList(id) }
        if let id = reminder.relatedShoppingListID { return .shoppingList(id) }
        if let id = reminder.relatedMealPrepItemID { return .mealPrepItem(id) }
        if let id = reminder.relatedReturnRequestID { return .returnRequest(id) }
        switch reminder.type {
        case .todos, .custom: return .todos
        case .shopping: return .shopping
        case .mealPrep: return .mealPrep
        case .returns: return .returns
        }
    }

    private static func returnTitle(items: [ReturnItem], packages: [ReturnPackage]) -> String {
        if let first = items.sorted(by: { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }).first {
            return items.count == 1 ? first.name : "\(first.name) + \(items.count - 1)"
        }
        if let package = packages.sorted(by: { ($0.sortOrder ?? 0, $0.displayName) < ($1.sortOrder ?? 0, $1.displayName) }).first {
            return "Return at \(package.displayName)"
        }
        return "Return"
    }

    private static func isInDay(_ date: Date?, start: Date, end: Date) -> Bool {
        guard let date else { return false }
        return date >= start && date < end
    }

    private static func isBeforeEndOfDay(_ date: Date?, dayEnd: Date) -> Bool {
        date.map { $0 < dayEnd } ?? false
    }

    private static func countText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private static func remainderText(_ count: Int, noun: String) -> String? {
        guard count > 0 else { return nil }
        return "+ \(count) more \(noun)\(count == 1 ? "" : "s")"
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

@MainActor
enum FoodInsightsService {
    static func metrics(
        householdID: UUID,
        locations: [InventoryLocation],
        inventoryItems: [InventoryItem],
        mealPrepItems: [MealPrepItem],
        packingTrips: [PackingTrip],
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
        let usedShoppingLists = shoppingLists.filter {
            $0.householdID == householdID && $0.lastUsedAt != nil
        }.count
        let completedPackingTrips = packingTrips.filter {
            $0.householdID == householdID && ($0.status == .completed || $0.completedAt != nil)
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
                title: "Lists Used",
                value: "\(usedShoppingLists)",
                detail: "Reusable shopping lists completed at least once.",
                systemImage: "checkmark.circle.fill"
            ),
            FoodInsightMetric(
                title: "Trips",
                value: "\(completedPackingTrips)",
                detail: "Packing trips marked complete.",
                systemImage: "suitcase.rolling.fill"
            ),
            FoodInsightMetric(
                title: "Frequent Buy",
                value: busiestStore?.name ?? "None yet",
                detail: purchaseText.map { "\($0) recorded." } ?? "Complete a shopping list to build history.",
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
    WidgetSnapshotService.scheduleFoodRefresh(context: context)
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
