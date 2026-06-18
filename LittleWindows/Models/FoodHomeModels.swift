import Foundation
import SwiftData

enum ShoppingListType: String, Codable, CaseIterable, Identifiable {
    case store
    case general
    case costcoRun
    case mealPrep
    case household
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .store: "Store"
        case .general: "General"
        case .costcoRun: "Costco Run"
        case .mealPrep: "Meal Prep"
        case .household: "Household"
        case .custom: "Custom"
        }
    }
}

enum ShoppingItemPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum InventoryLinkBehavior: String, Codable, CaseIterable, Identifiable {
    case none
    case addToInventoryWhenChecked
    case increaseInventoryWhenChecked
    case askWhenChecked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Do Nothing"
        case .addToInventoryWhenChecked: "Add to Inventory"
        case .increaseInventoryWhenChecked: "Increase Inventory"
        case .askWhenChecked: "Ask at Finish"
        }
    }
}

enum InventoryLocationType: String, Codable, CaseIterable, Identifiable {
    case fridge
    case freezer
    case pantry
    case counter
    case garageFreezer
    case household
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        case .counter: "Counter"
        case .garageFreezer: "Garage Freezer"
        case .household: "Household"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .fridge: "refrigerator.fill"
        case .freezer, .garageFreezer: "snowflake"
        case .pantry: "cabinet.fill"
        case .counter: "table.furniture.fill"
        case .household: "house.fill"
        case .custom: "square.grid.2x2.fill"
        }
    }
}

enum InventoryItemStatus: String, Codable, CaseIterable, Identifiable {
    case available
    case usedUp
    case discarded
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .available: "Available"
        case .usedUp: "Used Up"
        case .discarded: "Discarded"
        case .archived: "Archived"
        }
    }
}

enum MealPrepServingUnit: String, Codable, CaseIterable, Identifiable {
    case serving
    case portion
    case container
    case bag
    case tray
    case meal
    case burrito
    case jar
    case other

    var id: String { rawValue }

    var singularName: String {
        switch self {
        case .serving: "serving"
        case .portion: "portion"
        case .container: "container"
        case .bag: "bag"
        case .tray: "tray"
        case .meal: "meal"
        case .burrito: "burrito"
        case .jar: "jar"
        case .other: "item"
        }
    }

    func displayName(count: Double) -> String {
        count == 1 ? singularName : "\(singularName)s"
    }
}

enum FoodReminderType: String, Codable, CaseIterable, Identifiable {
    case shopping
    case mealPrep
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shopping: "Shopping"
        case .mealPrep: "Meal Prep"
        case .custom: "Custom"
        }
    }
}

@Model
final class Household {
    var id: UUID = UUID()
    var name: String = "Home"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "Home",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class FoodStore {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var name: String = ""
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var sortOrder: Int?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        name: String,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }
}

@Model
final class FoodStoreSection {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var storeID: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        householdID: UUID,
        storeID: UUID,
        name: String,
        sortOrder: Int = 0,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.storeID = storeID
        self.name = name
        self.sortOrder = sortOrder
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ShoppingList {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var name: String = ""
    var storeID: UUID?
    var listTypeRawValue: String = ShoppingListType.general.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var sortOrder: Int?
    var notes: String?
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        name: String,
        storeID: UUID? = nil,
        listType: ShoppingListType = .general,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        sortOrder: Int? = nil,
        notes: String? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.storeID = storeID
        self.listTypeRawValue = listType.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.notes = notes
        self.lastUsedAt = lastUsedAt
    }

    var listType: ShoppingListType {
        get { ShoppingListType(rawValue: listTypeRawValue) ?? .general }
        set { listTypeRawValue = newValue.rawValue }
    }
}

@Model
final class ShoppingListItem {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var shoppingListID: UUID = UUID()
    var foodItemID: UUID?
    var name: String = ""
    var quantity: Double?
    var unit: String?
    var notes: String?
    var storeSectionID: UUID?
    var categoryName: String?
    var isChecked: Bool = false
    var checkedAt: Date?
    var lastUncheckedAt: Date?
    var isRecurringStaple: Bool = false
    var priorityRawValue: String = ShoppingItemPriority.normal.rawValue
    var addedBy: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int?
    var lastPurchasedAt: Date?
    var purchaseCount: Int = 0
    var inventoryLinkBehaviorRawValue: String = InventoryLinkBehavior.askWhenChecked.rawValue

    init(
        id: UUID = UUID(),
        householdID: UUID,
        shoppingListID: UUID,
        foodItemID: UUID? = nil,
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        notes: String? = nil,
        storeSectionID: UUID? = nil,
        categoryName: String? = nil,
        isChecked: Bool = false,
        checkedAt: Date? = nil,
        lastUncheckedAt: Date? = nil,
        isRecurringStaple: Bool = false,
        priority: ShoppingItemPriority = .normal,
        addedBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int? = nil,
        lastPurchasedAt: Date? = nil,
        purchaseCount: Int = 0,
        inventoryLinkBehavior: InventoryLinkBehavior = .askWhenChecked
    ) {
        self.id = id
        self.householdID = householdID
        self.shoppingListID = shoppingListID
        self.foodItemID = foodItemID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
        self.storeSectionID = storeSectionID
        self.categoryName = categoryName
        self.isChecked = isChecked
        self.checkedAt = checkedAt
        self.lastUncheckedAt = lastUncheckedAt
        self.isRecurringStaple = isRecurringStaple
        self.priorityRawValue = priority.rawValue
        self.addedBy = addedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.lastPurchasedAt = lastPurchasedAt
        self.purchaseCount = purchaseCount
        self.inventoryLinkBehaviorRawValue = inventoryLinkBehavior.rawValue
    }

    var priority: ShoppingItemPriority {
        get { ShoppingItemPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    var inventoryLinkBehavior: InventoryLinkBehavior {
        get { InventoryLinkBehavior(rawValue: inventoryLinkBehaviorRawValue) ?? .askWhenChecked }
        set { inventoryLinkBehaviorRawValue = newValue.rawValue }
    }

    var quantityText: String {
        guard let quantity else { return "" }
        let number = quantity == quantity.rounded()
            ? String(Int(quantity))
            : String(format: "%.1f", quantity)
        if let unit, !unit.isEmpty {
            return "\(number) \(unit)"
        }
        return number
    }
}

@Model
final class FoodItem {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var canonicalName: String = ""
    var aliasesJSON: String?
    var defaultUnit: String?
    var defaultStoreSectionByStoreJSON: String?
    var defaultInventoryLocationID: UUID?
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false

    init(
        id: UUID = UUID(),
        householdID: UUID,
        canonicalName: String,
        aliasesJSON: String? = nil,
        defaultUnit: String? = nil,
        defaultStoreSectionByStoreJSON: String? = nil,
        defaultInventoryLocationID: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.householdID = householdID
        self.canonicalName = canonicalName
        self.aliasesJSON = aliasesJSON
        self.defaultUnit = defaultUnit
        self.defaultStoreSectionByStoreJSON = defaultStoreSectionByStoreJSON
        self.defaultInventoryLocationID = defaultInventoryLocationID
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

@Model
final class InventoryLocation {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var name: String = ""
    var locationTypeRawValue: String = InventoryLocationType.custom.rawValue
    var sortOrder: Int = 0
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false

    init(
        id: UUID = UUID(),
        householdID: UUID,
        name: String,
        locationType: InventoryLocationType,
        sortOrder: Int = 0,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.locationTypeRawValue = locationType.rawValue
        self.sortOrder = sortOrder
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    var locationType: InventoryLocationType {
        get { InventoryLocationType(rawValue: locationTypeRawValue) ?? .custom }
        set { locationTypeRawValue = newValue.rawValue }
    }
}

@Model
final class InventoryItem {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var foodItemID: UUID?
    var name: String = ""
    var quantity: Double = 0
    var unit: String = ""
    var locationID: UUID = UUID()
    var storageDetail: String?
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date?
    var statusRawValue: String = InventoryItemStatus.available.rawValue

    init(
        id: UUID = UUID(),
        householdID: UUID,
        foodItemID: UUID? = nil,
        name: String,
        quantity: Double,
        unit: String = "",
        locationID: UUID,
        storageDetail: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        status: InventoryItemStatus = .available
    ) {
        self.id = id
        self.householdID = householdID
        self.foodItemID = foodItemID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.locationID = locationID
        self.storageDetail = storageDetail
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.statusRawValue = status.rawValue
    }

    var status: InventoryItemStatus {
        get { InventoryItemStatus(rawValue: statusRawValue) ?? .available }
        set { statusRawValue = newValue.rawValue }
    }

    var quantityText: String {
        let number = quantity == quantity.rounded()
            ? String(Int(quantity))
            : String(format: "%.1f", quantity)
        return unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? number
            : "\(number) \(unit)"
    }
}

@Model
final class MealPrepItem {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var name: String = ""
    var locationID: UUID = UUID()
    var servingsTotal: Double?
    var servingsRemaining: Double = 0
    var servingUnitRawValue: String = MealPrepServingUnit.serving.rawValue
    var preparedDate: Date?
    var notes: String?
    var tagsJSON: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date?
    var isArchived: Bool = false

    init(
        id: UUID = UUID(),
        householdID: UUID,
        name: String,
        locationID: UUID,
        servingsTotal: Double? = nil,
        servingsRemaining: Double,
        servingUnit: MealPrepServingUnit = .serving,
        preparedDate: Date? = nil,
        notes: String? = nil,
        tagsJSON: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.locationID = locationID
        self.servingsTotal = servingsTotal
        self.servingsRemaining = servingsRemaining
        self.servingUnitRawValue = servingUnit.rawValue
        self.preparedDate = preparedDate
        self.notes = notes
        self.tagsJSON = tagsJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.isArchived = isArchived
    }

    var servingUnit: MealPrepServingUnit {
        get { MealPrepServingUnit(rawValue: servingUnitRawValue) ?? .serving }
        set { servingUnitRawValue = newValue.rawValue }
    }

    var servingsText: String {
        let number = servingsRemaining == servingsRemaining.rounded()
            ? String(Int(servingsRemaining))
            : String(format: "%.1f", servingsRemaining)
        return "\(number) \(servingUnit.displayName(count: servingsRemaining)) left"
    }
}

@Model
final class MealPrepUsage {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var mealPrepItemID: UUID = UUID()
    var dateTime: Date = Date()
    var servingsUsed: Double = 1
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        householdID: UUID,
        mealPrepItemID: UUID,
        dateTime: Date = Date(),
        servingsUsed: Double = 1,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.mealPrepItemID = mealPrepItemID
        self.dateTime = dateTime
        self.servingsUsed = servingsUsed
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class FoodReminder {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var typeRawValue: String = FoodReminderType.custom.rawValue
    var title: String = ""
    var relatedShoppingListID: UUID?
    var relatedMealPrepItemID: UUID?
    var dateTime: Date = Date()
    var isEnabled: Bool = true
    var recurrence: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        householdID: UUID,
        type: FoodReminderType = .custom,
        title: String,
        relatedShoppingListID: UUID? = nil,
        relatedMealPrepItemID: UUID? = nil,
        dateTime: Date,
        isEnabled: Bool = true,
        recurrence: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.typeRawValue = type.rawValue
        self.title = title
        self.relatedShoppingListID = relatedShoppingListID
        self.relatedMealPrepItemID = relatedMealPrepItemID
        self.dateTime = dateTime
        self.isEnabled = isEnabled
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: FoodReminderType {
        get { FoodReminderType(rawValue: typeRawValue) ?? .custom }
        set { typeRawValue = newValue.rawValue }
    }
}
