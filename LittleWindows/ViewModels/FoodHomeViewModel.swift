import Foundation

enum FoodHomeSection: String, CaseIterable, Identifiable, Codable {
    case todos
    case solids
    case shopping
    case trips
    case returns
    case inventory
    case mealPrep
    case stores
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todos: "To-Do"
        case .solids: "Solids"
        case .shopping: "Shopping"
        case .trips: "Trips"
        case .inventory: "Kitchen Inventory"
        case .mealPrep: "Meal Prep"
        case .returns: "Returns"
        case .stores: "Grocery Stores"
        case .insights: "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .todos: "checklist"
        case .solids: "carrot.fill"
        case .shopping: "cart.fill"
        case .trips: "suitcase.rolling.fill"
        case .inventory: "cabinet.fill"
        case .mealPrep: "takeoutbag.and.cup.and.straw.fill"
        case .returns: "shippingbox.fill"
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

enum FoodRoute: Hashable, Codable {
    case solidsHome
    case solidsDatabase
    case solidsGuided
    case solidFood(String)
    case customSolidFood(UUID)
    case solidsPlan
    case plannedSolidMeal(UUID)
    case solidsTracker
    case solidFoodHistory(String, String)
    case solidMeal(UUID)
    case solidsAllergens
    case solidAllergen(String)
    case solidsRecipes
    case solidsRecipe(String)
    case todoList(UUID)
    case shoppingList(UUID)
    case shoppingMode(UUID)
    case packingTrip(UUID)
    case inventoryItem(UUID)
    case mealPrepItem(UUID)
    case returnRequest(UUID)
    case store(UUID)
    case reminders

    var isSolidsWorkspaceRoute: Bool {
        switch self {
        case .solidsHome, .solidsDatabase, .solidsGuided, .solidFood, .customSolidFood,
             .solidsPlan, .plannedSolidMeal, .solidsTracker, .solidFoodHistory, .solidMeal,
             .solidsAllergens, .solidAllergen, .solidsRecipes, .solidsRecipe:
            true
        case .todoList, .shoppingList, .shoppingMode, .packingTrip, .inventoryItem,
             .mealPrepItem, .returnRequest, .store, .reminders:
            false
        }
    }
}

struct FoodNavigationRestorationState: Codable, Equatable {
    static let defaultsKey = "navigation.foodHome"

    var selectedSection: FoodHomeSection
    var path: [FoodRoute]

    static let initial = FoodNavigationRestorationState(
        selectedSection: .todos,
        path: []
    )

    static func load(defaults: UserDefaults = .standard) -> FoodNavigationRestorationState {
        guard let data = defaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(Self.self, from: data) else {
            return .initial
        }
        return state
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

enum FoodRouteCommand: Equatable {
    case food
    case solids
    case solidsDatabase
    case solidsGuided
    case solidFood(String)
    case customSolidFood(UUID)
    case solidsPlan
    case plannedSolidMeal(UUID)
    case solidsTracker
    case solidMeal(UUID)
    case solidsAllergens
    case solidAllergen(String)
    case solidsRecipes
    case solidsRecipe(String)
    case todos
    case todoList(UUID)
    case shopping
    case shoppingList(UUID)
    case shoppingMode(UUID)
    case trips
    case packingTrip(UUID)
    case inventory
    case inventoryItem(UUID)
    case mealPrep
    case mealPrepItem(UUID)
    case returns
    case returnRequest(UUID)
    case store(UUID)
    case quickAdd
}
