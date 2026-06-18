import Foundation

enum FoodHomeSection: String, CaseIterable, Identifiable {
    case shopping
    case inventory
    case mealPrep
    case stores
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shopping: "Shopping"
        case .inventory: "Inventory"
        case .mealPrep: "Meal Prep"
        case .stores: "Stores"
        case .insights: "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .shopping: "cart.fill"
        case .inventory: "cabinet.fill"
        case .mealPrep: "takeoutbag.and.cup.and.straw.fill"
        case .stores: "map.fill"
        case .insights: "chart.bar.xaxis"
        }
    }
}

enum ShoppingModeFilter: String, CaseIterable, Identifiable {
    case active
    case checked
    case all

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum InventoryFilter: String, CaseIterable, Identifiable {
    case available
    case usedUp
    case mealPrep
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: "Available"
        case .usedUp: "Used Up"
        case .mealPrep: "Meal Prep"
        case .all: "All"
        }
    }
}

enum InventorySort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case recentlyUsed
    case name
    case location
    case quantity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .recentlyUsed: "Recently Used"
        case .name: "Name"
        case .location: "Location"
        case .quantity: "Quantity"
        }
    }
}

enum FoodRoute: Hashable {
    case shoppingList(UUID)
    case shoppingMode(UUID)
    case inventoryItem(UUID)
    case mealPrepItem(UUID)
    case store(UUID)
    case reminders
}

enum FoodRouteCommand: Equatable {
    case food
    case shopping
    case shoppingList(UUID)
    case shoppingMode(UUID)
    case inventory
    case inventoryItem(UUID)
    case mealPrep
    case mealPrepItem(UUID)
    case store(UUID)
    case quickAdd
}
