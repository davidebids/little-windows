import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct FoodHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var router = DeepLinkRouter.shared
    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]

    @StateObject private var profileService = ProfileService.shared

    @State private var selectedSection: FoodHomeSection
    @State private var path: [FoodRoute]
    @State private var showingQuickAdd = false
    @State private var deferredFoodCommand: FoodRouteCommand?

    private var household: Household? { households.first }
    private var selectedProfile: CareProfile? { profileService.selectedProfile(in: profiles) }
    // Solids routes are handed to Care before Food's navigation stack is used.
    // Keep the unreachable destination switch source-compatible without
    // installing CloudKit observers for solids history on every Home screen.
    private var careEvents: [CareEvent] { [] }
    private var solidFoodProgress: [SolidFoodProgress] { [] }
    private var solidFoodEventItems: [SolidFoodEventItem] { [] }
    private var solidAllergenProgress: [SolidAllergenProgress] { [] }
    private var customSolidFoods: [SolidFoodCatalogItem] { [] }
    private var solidFoodPhotos: [PhotoAttachment] { [] }
    private var plannedSolidMeals: [PlannedSolidMeal] { [] }
    private var selectedSolidsState: SolidsProfileState? { nil }
    private var solidsAccessLevel: SolidsAccessLevel { .hidden }
    private var availableSections: [FoodHomeSection] {
        FoodHomeSection.allCases.filter { $0 != .solids }
    }
    init() {
        let restoredNavigation = FoodNavigationRestorationState.load()
        let restoredSection: FoodHomeSection = restoredNavigation.selectedSection == .solids
            ? .todos
            : restoredNavigation.selectedSection
        let restoredPath = restoredNavigation.path.contains { $0.isSolidsWorkspaceRoute }
            ? []
            : restoredNavigation.path
        _selectedSection = State(initialValue: restoredSection)
        _path = State(initialValue: restoredPath)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let household {
                    FoodHomeDataLoader(
                        householdID: household.id,
                        selectedSection: selectedSection,
                        activeRoute: path.last
                    ) { data in
                        navigationContent(household: household, data: data)
                    }
                } else {
                    ProgressView("Preparing Food & Home")
                        .task {
                            FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
                        }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: FoodRoute.reminders) {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("Food reminders")

                    Button {
                        router.presentSettings()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
                _ = profileService.ensureSelection(in: profiles)
                handlePendingProfileSwitch()
            }
            .onChange(of: router.pendingProfileID) { _, _ in
                handlePendingProfileSwitch()
            }
            .onChange(of: selectedSection) { _, _ in
                saveNavigationState()
            }
            .onChange(of: path) { _, _ in
                saveNavigationState()
            }
        }
    }

    private func navigationContent(
        household: Household,
        data: FoodHomeRouteData
    ) -> some View {
        content(household: household, data: data)
            .navigationDestination(for: FoodRoute.self) { route in
                destination(for: route, data: data)
            }
            .task(id: router.pendingFoodCommand) {
                guard let command = router.pendingFoodCommand else { return }
                await Task.yield()
                consumePendingFoodCommand(command, data: data)
            }
            .task(id: data.version) {
                await Task.yield()
                retryDeferredFoodCommandIfPossible(data: data)
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddShoppingItemView(
                    household: household,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems
                )
            }
    }

    private func saveNavigationState() {
        FoodNavigationRestorationState(
            selectedSection: selectedSection,
            path: path
        ).save()
    }

    @ViewBuilder
    private func content(household: Household, data: FoodHomeRouteData) -> some View {
        VStack(spacing: 0) {
            FoodHomeSectionPicker(sections: availableSections, selectedSection: selectedSection) { section in
                guard selectedSection != section else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    replaceNavigation(with: section)
                }
            }

            switch selectedSection {
            case .todos:
                HomeTodoListsView(
                    household: household,
                    lists: data.todoLists,
                    items: data.todoItems,
                    openList: { path.append(FoodRoute.todoList($0.id)) }
                )
            case .solids:
                EmptyView()
            case .shopping:
                ShoppingListsView(
                    household: household,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    stores: data.stores,
                    openList: { path.append(FoodRoute.shoppingList($0.id)) }
                )
            case .trips:
                TripsHomeView(
                    household: household,
                    trips: data.packingTrips,
                    travelers: data.tripTravelers,
                    items: data.packingItems,
                    profiles: profiles,
                    openTrip: { path.append(FoodRoute.packingTrip($0)) }
                )
            case .inventory:
                InventoryHomeView(
                    household: household,
                    locations: data.locations,
                    inventoryItems: data.inventoryItems,
                    mealPrepItems: data.mealPrepItems,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    openItem: { path.append(FoodRoute.inventoryItem($0.id)) }
                )
            case .mealPrep:
                MealPrepView(
                    household: household,
                    locations: data.locations,
                    mealPrepItems: data.mealPrepItems,
                    openItem: { path.append(FoodRoute.mealPrepItem($0.id)) }
                )
            case .returns:
                ReturnsHomeView(
                    household: household,
                    requests: data.sortedReturnRequests,
                    items: data.returnItems,
                    packages: data.returnPackages,
                    photoAttachments: data.returnPhotos,
                    openReturn: { path.append(FoodRoute.returnRequest($0.id)) }
                )
            case .stores:
                StoresView(
                    household: household,
                    stores: data.stores,
                    sections: data.storeSections,
                    openStore: { path.append(FoodRoute.store($0.id)) }
                )
            case .insights:
                FoodInsightsView(
                    household: household,
                    todoLists: data.todoLists,
                    todoItems: data.todoItems,
                    returnRequests: data.sortedReturnRequests,
                    returnItems: data.returnItems,
                    returnPackages: data.returnPackages,
                    locations: data.locations,
                    inventoryItems: data.inventoryItems,
                    mealPrepItems: data.mealPrepItems,
                    packingTrips: data.packingTrips,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    mealPrepUsages: data.mealPrepUsages
                )
            }
        }
        .background(AppTheme.background)
    }

    @ViewBuilder
    private func destination(for route: FoodRoute, data: FoodHomeRouteData) -> some View {
        switch route {
        case .solidsHome:
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel != .hidden {
                SolidsHomeView(
                    profile: selectedProfile,
                    accessLevel: solidsAccessLevel,
                    events: careEvents,
                    eventItems: solidFoodEventItems,
                    progress: solidFoodProgress,
                    plans: plannedSolidMeals,
                    profileState: selectedSolidsState,
                    open: { path.append($0) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsGuided:
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidsGuidedPathView(
                    profile: selectedProfile,
                    progress: solidFoodProgress,
                    eventItems: solidFoodEventItems,
                    allergenProgress: solidAllergenProgress,
                    plans: plannedSolidMeals,
                    profileState: selectedSolidsState,
                    openFood: { path.append(.solidFood($0)) },
                    openRecipe: { path.append(.solidsRecipe($0)) },
                    openPlan: { path.append(.plannedSolidMeal($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsDatabase:
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidsFoodDatabaseView(
                    profile: selectedProfile,
                    progress: solidFoodProgress,
                    customFoods: customSolidFoods,
                    photoAttachments: solidFoodPhotos,
                    openFood: { path.append(.solidFood($0)) },
                    openCustomFood: { path.append(.customSolidFood($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidFood(let id):
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel == .full,
               let food = SolidsReferenceCatalog.food(id: id) {
                SolidsFoodDetailView(
                    food: food,
                    profile: selectedProfile,
                    progress: solidFoodProgress,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    inventoryItems: data.inventoryItems,
                    foodItems: data.foodItems,
                    openHistory: { path.append(.solidFoodHistory($0, $1)) },
                    openRecipe: { path.append(.solidsRecipe($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .customSolidFood(let id):
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel == .full,
               let food = customSolidFoods.first(where: { $0.id == id }) {
                CustomSolidFoodDetailView(
                    food: food,
                    profile: selectedProfile,
                    photo: food.photoAttachmentID.flatMap { photoID in
                        solidFoodPhotos.first { $0.id == photoID }
                    },
                    allFoods: customSolidFoods,
                    progress: solidFoodProgress,
                    plannedMeals: plannedSolidMeals,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    inventoryItems: data.inventoryItems,
                    foodItems: data.foodItems,
                    openPlan: { path.append(.plannedSolidMeal($0)) },
                    openHistory: { path.append(.solidFoodHistory($0, $1)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsPlan:
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidsPlannerView(
                    profile: selectedProfile,
                    plans: plannedSolidMeals,
                    openPlan: { path.append(.plannedSolidMeal($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .plannedSolidMeal(let id):
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel == .full,
               let plan = plannedSolidMeals.first(where: {
                   $0.id == id && $0.profileID == selectedProfile.id
               }) {
                PlannedSolidMealDetailView(
                    plan: plan,
                    profile: selectedProfile,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    inventoryItems: data.inventoryItems,
                    foodItems: data.foodItems,
                    openFood: { foodID, foodName in
                        if SolidsReferenceCatalog.food(id: foodID) != nil {
                            path.append(.solidFood(foodID))
                        } else if foodID.hasPrefix("custom-"),
                                  let customID = UUID(uuidString: String(foodID.dropFirst("custom-".count))),
                                  customSolidFoods.contains(where: { $0.id == customID }) {
                            path.append(.customSolidFood(customID))
                        } else {
                            path.append(.solidFoodHistory(foodID, foodName))
                        }
                    },
                    openRecipe: { path.append(.solidsRecipe($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsTracker(let initialFilter):
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidsTrackerView(
                    profile: selectedProfile,
                    initialFilter: initialFilter,
                    events: careEvents,
                    progress: solidFoodProgress,
                    eventItems: solidFoodEventItems,
                    openFoodHistory: { path.append(.solidFoodHistory($0, $1)) },
                    openMeal: { path.append(.solidMeal($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidFoodHistory(let foodID, let foodName):
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidFoodHistoryView(
                    profile: selectedProfile,
                    foodID: foodID,
                    foodName: foodName,
                    events: careEvents,
                    eventItems: solidFoodEventItems,
                    openMeal: { path.append(.solidMeal($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidMeal(let id):
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel == .full,
               let event = careEvents.first(where: { $0.id == id && $0.profileID == selectedProfile.id }) {
                SolidMealDetailView(
                    event: event,
                    items: solidFoodEventItems,
                    editEvent: {
                        router.openToday(
                            action: .showEvent(event.id),
                            profileID: selectedProfile.id
                        )
                    }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsAllergens:
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidsAllergensView(
                    profile: selectedProfile,
                    eventItems: solidFoodEventItems,
                    progress: solidAllergenProgress,
                    openAllergen: { path.append(.solidAllergen($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidAllergen(let id):
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel == .full,
               let allergen = SolidsAllergen(rawValue: id) {
                SolidsAllergenDetailView(
                    allergen: allergen,
                    profile: selectedProfile,
                    eventItems: solidFoodEventItems,
                    progress: solidAllergenProgress.first {
                        $0.profileID == selectedProfile.id && $0.allergenID == id
                    },
                    allProgress: solidAllergenProgress,
                    plans: plannedSolidMeals,
                    openRecipe: { path.append(.solidsRecipe($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsRecipes:
            if let selectedProfile, selectedProfile.profileType == .child, solidsAccessLevel == .full {
                SolidsRecipesView(
                    profile: selectedProfile,
                    profileState: selectedSolidsState,
                    openRecipe: { path.append(.solidsRecipe($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .solidsRecipe(let id):
            if let selectedProfile,
               selectedProfile.profileType == .child,
               solidsAccessLevel == .full,
               let recipe = SolidsReferenceCatalog.recipe(id: id) {
                SolidsRecipeDetailView(
                    recipe: recipe,
                    profile: selectedProfile,
                    profileState: selectedSolidsState,
                    plannedMeals: plannedSolidMeals,
                    household: household,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    inventoryItems: data.inventoryItems,
                    foodItems: data.foodItems,
                    locations: data.locations,
                    openPlan: { path.append(.plannedSolidMeal($0)) },
                    openFood: { path.append(.solidFood($0)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .todoList(let id):
            if let list = data.todoLists.first(where: { $0.id == id }) {
                HomeTodoListDetailView(
                    list: list,
                    items: data.todoItems.filter { $0.todoListID == list.id }
                )
            } else {
                MissingFoodRouteView()
            }
        case .shoppingList(let id):
            if let list = data.shoppingLists.first(where: { $0.id == id }) {
                ShoppingListDetailView(
                    list: list,
                    items: data.shoppingItems.filter { $0.shoppingListID == list.id },
                    shoppingLists: data.shoppingLists,
                    store: data.stores.first { $0.id == list.storeID },
                    sections: data.storeSections.filter { $0.storeID == list.storeID },
                    inventoryItems: data.inventoryItems,
                    mealPrepItems: data.mealPrepItems,
                    openShoppingMode: { path.append(FoodRoute.shoppingMode(list.id)) },
                    openMealPrep: {
                        replaceNavigation(with: .mealPrep)
                    }
                )
            } else {
                MissingFoodRouteView()
            }
        case .shoppingMode(let id):
            if let list = data.shoppingLists.first(where: { $0.id == id }) {
                ShoppingModeView(
                    list: list,
                    items: data.shoppingItems.filter { $0.shoppingListID == list.id },
                    sections: data.storeSections.filter { $0.storeID == list.storeID },
                    locations: data.locations
                )
            } else {
                MissingFoodRouteView()
            }
        case .packingTrip(let id):
            if let trip = data.packingTrips.first(where: { $0.id == id }) {
                PackingTripDetailView(
                    trip: trip,
                    allTrips: data.packingTrips,
                    allTravelers: data.tripTravelers,
                    allBags: data.packingBags,
                    allItems: data.packingItems,
                    itineraryChoiceGroups: data.itineraryChoiceGroups,
                    itineraryItems: data.itineraryItems,
                    itineraryLinks: data.itineraryLinks,
                    profiles: profiles.filter { !$0.isArchived },
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems
                )
            } else {
                MissingFoodRouteView()
            }
        case .packingList(let id):
            if let trip = data.packingTrips.first(where: { $0.id == id }) {
                PackingTripDetailView(
                    trip: trip,
                    allTrips: data.packingTrips,
                    allTravelers: data.tripTravelers,
                    allBags: data.packingBags,
                    allItems: data.packingItems,
                    itineraryChoiceGroups: data.itineraryChoiceGroups,
                    itineraryItems: data.itineraryItems,
                    itineraryLinks: data.itineraryLinks,
                    profiles: profiles.filter { !$0.isArchived },
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    startsInPacking: true
                )
            } else {
                MissingFoodRouteView()
            }
        case .itineraryItem(let tripID, let itemID):
            if let trip = data.packingTrips.first(where: { $0.id == tripID }),
               data.itineraryItems.contains(where: { $0.id == itemID && $0.tripID == tripID }) {
                PackingTripDetailView(
                    trip: trip,
                    allTrips: data.packingTrips,
                    allTravelers: data.tripTravelers,
                    allBags: data.packingBags,
                    allItems: data.packingItems,
                    itineraryChoiceGroups: data.itineraryChoiceGroups,
                    itineraryItems: data.itineraryItems,
                    itineraryLinks: data.itineraryLinks,
                    profiles: profiles.filter { !$0.isArchived },
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems,
                    initialItineraryItemID: itemID
                )
            } else {
                MissingFoodRouteView()
            }
        case .inventoryItem(let id):
            if let item = data.inventoryItems.first(where: { $0.id == id }) {
                InventoryItemDetailView(
                    item: item,
                    locations: data.locations,
                    shoppingLists: data.shoppingLists,
                    shoppingItems: data.shoppingItems
                )
            } else {
                MissingFoodRouteView()
            }
        case .mealPrepItem(let id):
            if let item = data.mealPrepItems.first(where: { $0.id == id }) {
                MealPrepDetailView(
                    item: item,
                    locations: data.locations,
                    usages: data.mealPrepUsages.filter { $0.mealPrepItemID == item.id }
                )
            } else {
                MissingFoodRouteView()
            }
        case .returnRequest(let id):
            if let request = data.sortedReturnRequests.first(where: { $0.id == id }) {
                ReturnDetailView(
                    request: request,
                    items: data.returnItems.filter { $0.returnRequestID == request.id },
                    packages: data.returnPackages.filter { $0.returnRequestID == request.id },
                    photoAttachments: data.returnPhotos
                )
            } else {
                MissingFoodRouteView()
            }
        case .store(let id):
            if let store = data.stores.first(where: { $0.id == id }) {
                let storeSections = data.storeSections.filter { $0.storeID == store.id }
                let storeSectionIDs = Set(storeSections.map(\.id))
                StoreEditorView(
                    store: store,
                    sections: storeSections,
                    shoppingItems: data.shoppingItems.filter { item in
                        item.storeSectionID.map(storeSectionIDs.contains) == true
                    }
                )
            } else {
                MissingFoodRouteView()
            }
        case .reminders:
            if let household {
                FoodReminderSettingsView(
                    household: household,
                    reminders: data.reminders,
                    todoLists: data.todoLists,
                    shoppingLists: data.shoppingLists,
                    mealPrepItems: data.mealPrepItems,
                    returnRequests: data.sortedReturnRequests
                )
            }
        }
    }

    private func handle(
        _ command: FoodRouteCommand,
        data: FoodHomeRouteData,
        allowDeferral: Bool = true
    ) {
        if section(for: command) == .solids {
            deferredFoodCommand = nil
            replaceNavigation(with: .todos)
            router.openSolids(
                command,
                profileID: selectedProfile?.id,
                returningTo: .food
            )
            return
        }

        if section(for: command) == .solids,
           selectedProfile?.profileType != .child {
            deferredFoodCommand = nil
            correctUnavailableSolidsRoute()
            return
        }

        if section(for: command) == .solids,
           selectedProfile != nil,
           solidsAccessLevel == .hidden {
            deferredFoodCommand = nil
            correctUnavailableSolidsRoute()
            return
        }

        if section(for: command) == .solids,
           solidsAccessLevel == .readinessPreview,
           command != .solids {
            deferredFoodCommand = nil
            replaceNavigation(with: .solids)
            return
        }

        if allowDeferral && shouldDefer(command, data: data) {
            deferFoodCommand(command)
            return
        }

        switch command {
        case .food:
            deferredFoodCommand = nil
            replaceNavigation(with: .todos)
        case .solids:
            deferredFoodCommand = nil
            replaceNavigation(with: .solids)
        case .solidsDatabase:
            openSolidsRoute(.solidsDatabase)
        case .solidsGuided:
            openSolidsRoute(.solidsGuided)
        case .solidFood(let id):
            openSolidsRoute(.solidFood(id))
        case .customSolidFood(let id):
            openSolidsRoute(.customSolidFood(id))
        case .solidsPlan:
            openSolidsRoute(.solidsPlan)
        case .plannedSolidMeal(let id):
            openSolidsRoute(.plannedSolidMeal(id))
        case .solidsTracker(let initialFilter):
            openSolidsRoute(.solidsTracker(initialFilter))
        case .solidMeal(let id):
            openSolidsRoute(.solidMeal(id))
        case .solidsAllergens:
            openSolidsRoute(.solidsAllergens)
        case .solidAllergen(let id):
            openSolidsRoute(.solidAllergen(id))
        case .solidsRecipes:
            openSolidsRoute(.solidsRecipes)
        case .solidsRecipe(let id):
            openSolidsRoute(.solidsRecipe(id))
        case .todos:
            deferredFoodCommand = nil
            replaceNavigation(with: .todos)
        case .todoList(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .todos, route: .todoList(id))
        case .shopping:
            deferredFoodCommand = nil
            replaceNavigation(with: .shopping)
        case .shoppingList(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .shopping, route: .shoppingList(id))
        case .shoppingMode(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .shopping, route: .shoppingMode(id))
        case .trips:
            deferredFoodCommand = nil
            replaceNavigation(with: .trips)
        case .packingTrip(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .trips, route: .packingTrip(id))
        case .packingList(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .trips, route: .packingList(id))
        case .itineraryItem(let tripID, let itemID):
            deferredFoodCommand = nil
            replaceNavigation(with: .trips, route: .itineraryItem(tripID, itemID))
        case .inventory:
            deferredFoodCommand = nil
            replaceNavigation(with: .inventory)
        case .inventoryItem(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .inventory, route: .inventoryItem(id))
        case .mealPrep:
            deferredFoodCommand = nil
            replaceNavigation(with: .mealPrep)
        case .mealPrepItem(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .mealPrep, route: .mealPrepItem(id))
        case .returns:
            deferredFoodCommand = nil
            replaceNavigation(with: .returns)
        case .returnRequest(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .returns, route: .returnRequest(id))
        case .store(let id):
            deferredFoodCommand = nil
            replaceNavigation(with: .stores, route: .store(id))
        case .quickAdd:
            deferredFoodCommand = nil
            selectedSection = .shopping
            showingQuickAdd = true
        }
    }

    private func consumePendingFoodCommand(
        _ expectedCommand: FoodRouteCommand,
        data: FoodHomeRouteData
    ) {
        guard router.pendingFoodCommand == expectedCommand else { return }

        // Clear first so rebuilding the task cannot replay the same command if
        // handling it causes the view hierarchy to refresh.
        router.pendingFoodCommand = nil
        handle(expectedCommand, data: data)
    }

    private func replaceNavigation(
        with section: FoodHomeSection,
        route: FoodRoute? = nil
    ) {
        if selectedSection != section {
            selectedSection = section
        }

        let replacementPath = route.map { [$0] } ?? []
        if path != replacementPath {
            path = replacementPath
        }
    }

    private func shouldDefer(_ command: FoodRouteCommand, data: FoodHomeRouteData) -> Bool {
        guard household != nil else { return true }
        switch command {
        case .food, .todos, .shopping, .trips, .inventory, .mealPrep, .returns, .quickAdd:
            return false
        case .solids, .solidsDatabase, .solidsGuided, .solidsPlan, .solidsTracker, .solidsAllergens, .solidsRecipes:
            return solidsAccessLevel == .hidden
        case .solidFood(let id):
            return solidsAccessLevel == .hidden || SolidsReferenceCatalog.food(id: id) == nil
        case .customSolidFood(let id):
            return solidsAccessLevel == .hidden || !customSolidFoods.contains { $0.id == id }
        case .plannedSolidMeal(let id):
            return solidsAccessLevel == .hidden || !plannedSolidMeals.contains {
                $0.id == id && $0.profileID == selectedProfile?.id
            }
        case .solidMeal(let id):
            return solidsAccessLevel == .hidden || !careEvents.contains {
                $0.id == id && $0.profileID == selectedProfile?.id && $0.feedKind == .solid
            }
        case .solidAllergen(let id):
            return solidsAccessLevel == .hidden || SolidsAllergen(rawValue: id) == nil
        case .solidsRecipe(let id):
            return solidsAccessLevel == .hidden || !SolidsReferenceCatalog.recipes.contains { $0.id == id }
        case .todoList(let id):
            return !data.todoLists.contains { $0.id == id }
        case .shoppingList(let id), .shoppingMode(let id):
            return !data.shoppingLists.contains { $0.id == id }
        case .packingTrip(let id), .packingList(let id):
            return !data.packingTrips.contains { $0.id == id }
        case .itineraryItem(let tripID, _):
            return !data.packingTrips.contains { $0.id == tripID }
        case .inventoryItem(let id):
            return !data.inventoryItems.contains { $0.id == id }
        case .mealPrepItem(let id):
            return !data.mealPrepItems.contains { $0.id == id }
        case .returnRequest(let id):
            return !data.sortedReturnRequests.contains { $0.id == id }
        case .store(let id):
            return !data.stores.contains { $0.id == id }
        }
    }

    private func deferFoodCommand(_ command: FoodRouteCommand) {
        replaceNavigation(with: section(for: command))
        deferredFoodCommand = command
    }

    private func retryDeferredFoodCommandIfPossible(
        data: FoodHomeRouteData,
        force: Bool = false
    ) {
        guard let command = deferredFoodCommand else { return }
        if force, shouldDefer(command, data: data), section(for: command) == .solids {
            deferredFoodCommand = nil
            correctUnavailableSolidsRoute()
            return
        }
        if force || !shouldDefer(command, data: data) {
            handle(command, data: data, allowDeferral: !force)
        }
    }

    private func section(for command: FoodRouteCommand) -> FoodHomeSection {
        switch command {
        case .food, .todos, .todoList:
            return .todos
        case .solids, .solidsDatabase, .solidsGuided, .solidFood, .customSolidFood,
             .solidsPlan, .plannedSolidMeal, .solidsTracker, .solidMeal,
             .solidsAllergens, .solidAllergen, .solidsRecipes, .solidsRecipe:
            return .solids
        case .shopping, .shoppingList, .shoppingMode, .quickAdd:
            return .shopping
        case .trips, .packingTrip, .packingList, .itineraryItem:
            return .trips
        case .inventory, .inventoryItem:
            return .inventory
        case .mealPrep, .mealPrepItem:
            return .mealPrep
        case .returns, .returnRequest:
            return .returns
        case .store:
            return .stores
        }
    }

    private func openSolidsRoute(_ route: FoodRoute) {
        deferredFoodCommand = nil
        replaceNavigation(with: .solids, route: route)
    }

    private func handlePendingProfileSwitch() {
        guard let id = router.pendingProfileID else { return }
        profileService.switchProfile(id: id, profiles: profiles)
        router.pendingProfileID = nil
        correctUnavailableSolidsRoute()
    }

    private func correctUnavailableSolidsRoute() {
        if selectedSection == .solids || path.contains(where: { $0.isSolidsWorkspaceRoute }) {
            replaceNavigation(with: .todos)
        }
    }
}

private struct FoodHomeRouteData {
    let scopeKey: String
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let stores: [FoodStore]
    let storeSections: [FoodStoreSection]
    let todoLists: [HomeTodoList]
    let todoItems: [HomeTodoItem]
    let locations: [InventoryLocation]
    let inventoryItems: [InventoryItem]
    let foodItems: [FoodItem]
    let mealPrepItems: [MealPrepItem]
    let mealPrepUsages: [MealPrepUsage]
    let sortedReturnRequests: [ReturnRequest]
    let returnItems: [ReturnItem]
    let returnPackages: [ReturnPackage]
    let returnPhotos: [PhotoAttachment]
    let reminders: [FoodReminder]
    let packingTrips: [PackingTrip]
    let tripTravelers: [TripTraveler]
    let packingBags: [PackingBag]
    let packingItems: [PackingItem]
    let itineraryChoiceGroups: [TripItineraryChoiceGroup]
    let itineraryItems: [TripItineraryItem]
    let itineraryLinks: [TripItineraryLink]

    var version: String {
        let shopping = "\(shoppingLists.count):\(shoppingItems.count):\(stores.count):\(storeSections.count)"
        let home = "\(todoLists.count):\(todoItems.count):\(locations.count):\(inventoryItems.count)"
        let food = "\(mealPrepItems.count):\(mealPrepUsages.count):\(reminders.count)"
        let returns = "\(sortedReturnRequests.count):\(returnItems.count):\(returnPackages.count):\(returnPhotos.count)"
        let trips = "\(packingTrips.count):\(tripTravelers.count):\(packingBags.count):\(packingItems.count):\(itineraryChoiceGroups.count):\(itineraryItems.count):\(itineraryLinks.count)"
        return "\(scopeKey):\(shopping):\(home):\(food):\(returns):\(trips)"
    }
}

private struct FoodHomeDataScope {
    let section: FoodHomeSection
    let activeRoute: FoodRoute?

    var key: String {
        "\(section.rawValue):\(String(describing: activeRoute))"
    }

    private var isReminders: Bool {
        activeRoute == .reminders
    }

    var packingTripID: UUID? {
        switch activeRoute {
        case .packingTrip(let id), .packingList(let id), .itineraryItem(let id, _): id
        default: nil
        }
    }

    var todoListID: UUID? {
        guard case .todoList(let id) = activeRoute else { return nil }
        return id
    }

    var shoppingListID: UUID? {
        switch activeRoute {
        case .shoppingList(let id), .shoppingMode(let id):
            return id
        default:
            return nil
        }
    }

    var inventoryItemID: UUID? {
        guard case .inventoryItem(let id) = activeRoute else { return nil }
        return id
    }

    var mealPrepItemID: UUID? {
        guard case .mealPrepItem(let id) = activeRoute else { return nil }
        return id
    }

    var returnRequestID: UUID? {
        guard case .returnRequest(let id) = activeRoute else { return nil }
        return id
    }

    var storeID: UUID? {
        guard case .store(let id) = activeRoute else { return nil }
        return id
    }

    var loadsTodos: Bool { section == .todos || section == .insights || isReminders }
    var loadsShoppingLists: Bool {
        section == .shopping || packingTripID != nil || section == .inventory
            || section == .insights || isReminders
    }
    var loadsShoppingItems: Bool {
        section == .shopping || packingTripID != nil || section == .inventory
            || section == .stores || section == .insights
    }
    var loadsStores: Bool { section == .shopping || section == .stores }
    var loadsLocations: Bool {
        section == .shopping || section == .inventory || section == .mealPrep
            || section == .insights
    }
    var loadsInventory: Bool {
        section == .shopping || section == .inventory || section == .insights
    }
    var loadsMealPrep: Bool {
        section == .shopping || section == .inventory || section == .mealPrep
            || section == .insights || isReminders
    }
    var loadsMealPrepUsage: Bool { section == .mealPrep || section == .insights }
    var loadsReturns: Bool { section == .returns || section == .insights || isReminders }
    var loadsReturnDetails: Bool { section == .returns || section == .insights }
    var loadsReturnPhotos: Bool { section == .returns }
    var loadsReminders: Bool { isReminders }
    var loadsTrips: Bool { section == .trips || section == .insights }
}

/// Each Home area observes only its own records. This prevents a CloudKit
/// import or a packing-list edit from invalidating every other Home workflow.
private struct FoodHomeDataLoader<Content: View>: View {
    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingItems: [ShoppingListItem]
    @Query private var stores: [FoodStore]
    @Query private var storeSections: [FoodStoreSection]
    @Query private var todoLists: [HomeTodoList]
    @Query private var todoItems: [HomeTodoItem]
    @Query private var locations: [InventoryLocation]
    @Query private var inventoryItems: [InventoryItem]
    @Query private var mealPrepItems: [MealPrepItem]
    @Query private var mealPrepUsages: [MealPrepUsage]
    @Query private var returnRequests: [ReturnRequest]
    @Query private var returnItems: [ReturnItem]
    @Query private var returnPackages: [ReturnPackage]
    @Query private var returnPhotos: [PhotoAttachment]
    @Query private var reminders: [FoodReminder]
    @Query private var packingTrips: [PackingTrip]
    @Query private var tripTravelers: [TripTraveler]
    @Query private var packingBags: [PackingBag]
    @Query private var packingItems: [PackingItem]
    @Query private var itineraryChoiceGroups: [TripItineraryChoiceGroup]
    @Query private var itineraryItems: [TripItineraryItem]
    @Query private var itineraryLinks: [TripItineraryLink]

    private let scope: FoodHomeDataScope
    private let content: (FoodHomeRouteData) -> Content

    init(
        householdID: UUID,
        selectedSection: FoodHomeSection,
        activeRoute: FoodRoute?,
        @ViewBuilder content: @escaping (FoodHomeRouteData) -> Content
    ) {
        let scope = FoodHomeDataScope(section: selectedSection, activeRoute: activeRoute)
        self.scope = scope
        self.content = content
        let unloadedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let todoID = scope.loadsTodos ? householdID : unloadedID
        let shoppingListID = scope.loadsShoppingLists ? householdID : unloadedID
        let shoppingItemID = scope.loadsShoppingItems ? householdID : unloadedID
        let storeID = scope.loadsStores ? householdID : unloadedID
        let locationID = scope.loadsLocations ? householdID : unloadedID
        let inventoryID = scope.loadsInventory ? householdID : unloadedID
        let mealPrepID = scope.loadsMealPrep ? householdID : unloadedID
        let mealPrepUsageID = scope.loadsMealPrepUsage ? householdID : unloadedID
        let returnID = scope.loadsReturns ? householdID : unloadedID
        let returnDetailID = scope.loadsReturnDetails ? householdID : unloadedID
        let reminderID = scope.loadsReminders ? householdID : unloadedID
        let tripID = scope.loadsTrips ? householdID : unloadedID

        _shoppingLists = Query(FetchDescriptor<ShoppingList>(
            predicate: #Predicate { $0.householdID == shoppingListID && !$0.isArchived },
            sortBy: [SortDescriptor(\ShoppingList.sortOrder), SortDescriptor(\ShoppingList.name)]
        ))
        if let shoppingListID = scope.shoppingListID {
            _shoppingItems = Query(FetchDescriptor<ShoppingListItem>(
                predicate: #Predicate { $0.shoppingListID == shoppingListID },
                sortBy: [SortDescriptor(\ShoppingListItem.sortOrder)]
            ))
        } else {
            _shoppingItems = Query(FetchDescriptor<ShoppingListItem>(
                predicate: #Predicate { $0.householdID == shoppingItemID },
                sortBy: [SortDescriptor(\ShoppingListItem.sortOrder)]
            ))
        }
        if let activeStoreID = scope.storeID {
            _stores = Query(FetchDescriptor<FoodStore>(
                predicate: #Predicate { $0.id == activeStoreID && !$0.isArchived },
                sortBy: [SortDescriptor(\FoodStore.sortOrder), SortDescriptor(\FoodStore.name)]
            ))
            _storeSections = Query(FetchDescriptor<FoodStoreSection>(
                predicate: #Predicate { $0.storeID == activeStoreID },
                sortBy: [SortDescriptor(\FoodStoreSection.sortOrder), SortDescriptor(\FoodStoreSection.name)]
            ))
        } else {
            _stores = Query(FetchDescriptor<FoodStore>(
                predicate: #Predicate { $0.householdID == storeID && !$0.isArchived },
                sortBy: [SortDescriptor(\FoodStore.sortOrder), SortDescriptor(\FoodStore.name)]
            ))
            _storeSections = Query(FetchDescriptor<FoodStoreSection>(
                predicate: #Predicate { $0.householdID == storeID },
                sortBy: [SortDescriptor(\FoodStoreSection.sortOrder), SortDescriptor(\FoodStoreSection.name)]
            ))
        }
        _todoLists = Query(FetchDescriptor<HomeTodoList>(
            predicate: #Predicate { $0.householdID == todoID && !$0.isArchived },
            sortBy: [SortDescriptor(\HomeTodoList.sortOrder), SortDescriptor(\HomeTodoList.name)]
        ))
        if let todoListID = scope.todoListID {
            _todoItems = Query(FetchDescriptor<HomeTodoItem>(
                predicate: #Predicate { $0.todoListID == todoListID },
                sortBy: [SortDescriptor(\HomeTodoItem.sortOrder)]
            ))
        } else {
            _todoItems = Query(FetchDescriptor<HomeTodoItem>(
                predicate: #Predicate { $0.householdID == todoID },
                sortBy: [SortDescriptor(\HomeTodoItem.sortOrder)]
            ))
        }
        _locations = Query(FetchDescriptor<InventoryLocation>(
            predicate: #Predicate { $0.householdID == locationID && !$0.isArchived },
            sortBy: [SortDescriptor(\InventoryLocation.sortOrder), SortDescriptor(\InventoryLocation.name)]
        ))
        if let inventoryItemID = scope.inventoryItemID {
            _inventoryItems = Query(FetchDescriptor<InventoryItem>(
                predicate: #Predicate { $0.id == inventoryItemID },
                sortBy: [SortDescriptor(\InventoryItem.updatedAt, order: .reverse)]
            ))
        } else {
            _inventoryItems = Query(FetchDescriptor<InventoryItem>(
                predicate: #Predicate { $0.householdID == inventoryID },
                sortBy: [SortDescriptor(\InventoryItem.updatedAt, order: .reverse)]
            ))
        }
        if let mealPrepItemID = scope.mealPrepItemID {
            _mealPrepItems = Query(FetchDescriptor<MealPrepItem>(
                predicate: #Predicate { $0.id == mealPrepItemID },
                sortBy: [SortDescriptor(\MealPrepItem.updatedAt, order: .reverse)]
            ))
            _mealPrepUsages = Query(FetchDescriptor<MealPrepUsage>(
                predicate: #Predicate { $0.mealPrepItemID == mealPrepItemID },
                sortBy: [SortDescriptor(\MealPrepUsage.dateTime, order: .reverse)]
            ))
        } else {
            _mealPrepItems = Query(FetchDescriptor<MealPrepItem>(
                predicate: #Predicate { $0.householdID == mealPrepID },
                sortBy: [SortDescriptor(\MealPrepItem.updatedAt, order: .reverse)]
            ))
            _mealPrepUsages = Query(FetchDescriptor<MealPrepUsage>(
                predicate: #Predicate { $0.householdID == mealPrepUsageID },
                sortBy: [SortDescriptor(\MealPrepUsage.dateTime, order: .reverse)]
            ))
        }
        if let returnRequestID = scope.returnRequestID {
            _returnRequests = Query(FetchDescriptor<ReturnRequest>(
                predicate: #Predicate { $0.id == returnRequestID && !$0.isArchived },
                sortBy: [SortDescriptor(\ReturnRequest.updatedAt, order: .reverse)]
            ))
            _returnItems = Query(FetchDescriptor<ReturnItem>(
                predicate: #Predicate { $0.returnRequestID == returnRequestID },
                sortBy: [SortDescriptor(\ReturnItem.sortOrder)]
            ))
            _returnPackages = Query(FetchDescriptor<ReturnPackage>(
                predicate: #Predicate { $0.returnRequestID == returnRequestID },
                sortBy: [SortDescriptor(\ReturnPackage.sortOrder)]
            ))
        } else {
            _returnRequests = Query(FetchDescriptor<ReturnRequest>(
                predicate: #Predicate { $0.householdID == returnID && !$0.isArchived },
                sortBy: [SortDescriptor(\ReturnRequest.updatedAt, order: .reverse)]
            ))
            _returnItems = Query(FetchDescriptor<ReturnItem>(
                predicate: #Predicate { $0.householdID == returnDetailID },
                sortBy: [SortDescriptor(\ReturnItem.sortOrder)]
            ))
            _returnPackages = Query(FetchDescriptor<ReturnPackage>(
                predicate: #Predicate { $0.householdID == returnDetailID },
                sortBy: [SortDescriptor(\ReturnPackage.sortOrder)]
            ))
        }
        let returnPhotoKind = scope.loadsReturnPhotos
            ? PhotoAttachmentOwnerKind.returnPhoto.rawValue
            : "__unloaded_return_photo__"
        _returnPhotos = Query(FetchDescriptor<PhotoAttachment>(
            predicate: #Predicate { $0.ownerKindRawValue == returnPhotoKind },
            sortBy: [SortDescriptor(\PhotoAttachment.createdAt)]
        ))
        _reminders = Query(FetchDescriptor<FoodReminder>(
            predicate: #Predicate { $0.householdID == reminderID },
            sortBy: [SortDescriptor(\FoodReminder.dateTime)]
        ))
        _packingTrips = Query(FetchDescriptor<PackingTrip>(
            predicate: #Predicate { $0.householdID == tripID },
            sortBy: [SortDescriptor(\PackingTrip.startDate)]
        ))
        if let packingTripID = scope.packingTripID {
            _tripTravelers = Query(FetchDescriptor<TripTraveler>(
                predicate: #Predicate { $0.tripID == packingTripID },
                sortBy: [SortDescriptor(\TripTraveler.sortOrder)]
            ))
            _packingBags = Query(FetchDescriptor<PackingBag>(
                predicate: #Predicate { $0.tripID == packingTripID },
                sortBy: [SortDescriptor(\PackingBag.sortOrder)]
            ))
            _packingItems = Query(FetchDescriptor<PackingItem>(
                predicate: #Predicate { $0.tripID == packingTripID },
                sortBy: [SortDescriptor(\PackingItem.sortOrder)]
            ))
            _itineraryChoiceGroups = Query(FetchDescriptor<TripItineraryChoiceGroup>(
                predicate: #Predicate { $0.tripID == packingTripID },
                sortBy: [SortDescriptor(\TripItineraryChoiceGroup.sortOrder)]
            ))
            _itineraryItems = Query(FetchDescriptor<TripItineraryItem>(
                predicate: #Predicate { $0.tripID == packingTripID },
                sortBy: [SortDescriptor(\TripItineraryItem.sortOrder)]
            ))
            _itineraryLinks = Query(FetchDescriptor<TripItineraryLink>(
                predicate: #Predicate { $0.tripID == packingTripID },
                sortBy: [SortDescriptor(\TripItineraryLink.sortOrder)]
            ))
        } else {
            _tripTravelers = Query(FetchDescriptor<TripTraveler>(
                predicate: #Predicate { $0.householdID == tripID },
                sortBy: [SortDescriptor(\TripTraveler.sortOrder)]
            ))
            _packingBags = Query(FetchDescriptor<PackingBag>(
                predicate: #Predicate { $0.householdID == unloadedID },
                sortBy: [SortDescriptor(\PackingBag.sortOrder)]
            ))
            _packingItems = Query(FetchDescriptor<PackingItem>(
                predicate: #Predicate { $0.householdID == tripID },
                sortBy: [SortDescriptor(\PackingItem.sortOrder)]
            ))
            _itineraryChoiceGroups = Query(FetchDescriptor<TripItineraryChoiceGroup>(
                predicate: #Predicate { $0.householdID == unloadedID },
                sortBy: [SortDescriptor(\TripItineraryChoiceGroup.sortOrder)]
            ))
            _itineraryItems = Query(FetchDescriptor<TripItineraryItem>(
                predicate: #Predicate { $0.householdID == unloadedID },
                sortBy: [SortDescriptor(\TripItineraryItem.sortOrder)]
            ))
            _itineraryLinks = Query(FetchDescriptor<TripItineraryLink>(
                predicate: #Predicate { $0.householdID == unloadedID },
                sortBy: [SortDescriptor(\TripItineraryLink.sortOrder)]
            ))
        }
    }

    var body: some View {
        content(FoodHomeRouteData(
            scopeKey: scope.key,
            shoppingLists: shoppingLists,
            shoppingItems: shoppingItems,
            stores: stores,
            storeSections: storeSections,
            todoLists: todoLists,
            todoItems: todoItems,
            locations: locations,
            inventoryItems: inventoryItems,
            foodItems: [],
            mealPrepItems: mealPrepItems,
            mealPrepUsages: mealPrepUsages,
            sortedReturnRequests: sortedRequests(),
            returnItems: returnItems,
            returnPackages: returnPackages,
            returnPhotos: returnPhotos,
            reminders: reminders,
            packingTrips: packingTrips,
            tripTravelers: tripTravelers,
            packingBags: packingBags,
            packingItems: packingItems,
            itineraryChoiceGroups: itineraryChoiceGroups,
            itineraryItems: itineraryItems,
            itineraryLinks: itineraryLinks
        ))
    }

    private func sortedRequests() -> [ReturnRequest] {
        let packagesByReturnID = Dictionary(grouping: returnPackages, by: \.returnRequestID)
        let itemsByReturnID = Dictionary(grouping: returnItems, by: \.returnRequestID)
        let statusesByReturnID = Dictionary(uniqueKeysWithValues: returnRequests.map { request in
            (request.id, ReturnTrackingService.status(
                for: request,
                packages: packagesByReturnID[request.id] ?? []
            ))
        })
        return returnRequests.sorted { lhs, rhs in
            let lhsPackages = packagesByReturnID[lhs.id] ?? []
            let rhsPackages = packagesByReturnID[rhs.id] ?? []
            return (
                statusSortOrder(statusesByReturnID[lhs.id] ?? .needsAction),
                lhsPackages.compactMap(\.returnByDate).min() ?? .distantFuture,
                returnDisplayTitle(items: itemsByReturnID[lhs.id] ?? [], packages: lhsPackages)
            ) < (
                statusSortOrder(statusesByReturnID[rhs.id] ?? .needsAction),
                rhsPackages.compactMap(\.returnByDate).min() ?? .distantFuture,
                returnDisplayTitle(items: itemsByReturnID[rhs.id] ?? [], packages: rhsPackages)
            )
        }
    }

    private func statusSortOrder(_ status: ReturnRequestStatus) -> Int {
        switch status {
        case .needsAction: 0
        case .readyToDropOff: 1
        case .partiallyDroppedOff: 2
        case .droppedOff: 3
        case .completed: 4
        case .archived: 5
        }
    }

    private func returnDisplayTitle(items: [ReturnItem], packages: [ReturnPackage]) -> String {
        if let firstItem = items.min(by: {
            ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name)
        }) {
            return items.count == 1 ? firstItem.name : "\(firstItem.name) + \(items.count - 1)"
        }
        if let firstPackage = packages.min(by: {
            ($0.sortOrder ?? 0, $0.displayName) < ($1.sortOrder ?? 0, $1.displayName)
        }) {
            return "Return at \(firstPackage.displayName)"
        }
        return "Return"
    }
}

private struct FoodHomeSectionPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sections: [FoodHomeSection]
    let selectedSection: FoodHomeSection
    let select: (FoodHomeSection) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Home areas")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("home.areas.title")
                Spacer()
                Text(selectedSection.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(sections) { section in
                    FoodHomeSectionButton(
                        section: section,
                        isSelected: selectedSection == section
                    ) {
                        select(section)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.background)
    }
}

private struct FoodHomeSectionButton: View {
    let section: FoodHomeSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : section.tint)
                    .frame(width: 34, height: 30)
                    .background(
                        isSelected ? Color.white.opacity(0.16) : section.tint.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                Text(section.selectorTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .padding(.horizontal, 4)
            .background(
                isSelected ? section.tint.gradient : AppTheme.surface.gradient,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? section.tint.opacity(0.7) : AppTheme.line,
                        lineWidth: isSelected ? 1.2 : 0.6
                    )
            }
            .shadow(
                color: isSelected ? section.tint.opacity(0.2) : .clear,
                radius: 8,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(section.title)
        .accessibilityIdentifier("home-area.\(section.rawValue)")
    }
}

private extension FoodHomeSection {
    var selectorTitle: String {
        switch self {
        case .todos: "To-Do"
        case .solids: "Solids"
        case .shopping: "Shopping"
        case .trips: "Trips"
        case .returns: "Returns"
        case .inventory: "Inventory"
        case .mealPrep: "Meal Prep"
        case .stores: "Stores"
        case .insights: "Insights"
        }
    }

    var tint: Color {
        switch self {
        case .todos: .indigo
        case .solids: .orange
        case .shopping: .blue
        case .trips: .cyan
        case .returns: .orange
        case .inventory: .brown
        case .mealPrep: .green
        case .stores: .purple
        case .insights: .teal
        }
    }
}

private struct HomeTodoListsView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let lists: [HomeTodoList]
    let items: [HomeTodoItem]
    let openList: (HomeTodoList) -> Void

    @State private var showingNewList = false
    @State private var editingList: HomeTodoList?
    @State private var showingRemoveListConfirmation = false
    @State private var listPendingRemoval: HomeTodoList?

    var body: some View {
        let itemsByListID = Dictionary(grouping: items, by: \.todoListID)

        List {
            if lists.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No to-do lists",
                        systemImage: "checklist",
                        description: Text("Create named lists for home tasks, errands, reminders, and shared follow-ups.")
                    )
                }
            } else {
                Section {
                    ForEach(lists) { list in
                        Button {
                            openList(list)
                        } label: {
                            HomeTodoListRow(
                                list: list,
                                items: itemsByListID[list.id] ?? []
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("Edit", systemImage: "pencil") {
                                editingList = list
                            }
                            .tint(.blue)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                listPendingRemoval = list
                                showingRemoveListConfirmation = true
                            }
                        }
                    }
                    .onMove { source, destination in
                        HomeTodoService.reorderLists(
                            lists,
                            from: source,
                            to: destination,
                            context: modelContext
                        )
                    }
                } header: {
                    AppSectionHeader(title: "To-Do Lists", subtitle: "\(lists.count)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if lists.count > 1 {
                    EditButton()
                }

                Button {
                    showingNewList = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to-do list")
            }
        }
        .sheet(isPresented: $showingNewList) {
            NavigationStack {
                HomeTodoListEditorView(
                    household: household,
                    list: nil,
                    existingLists: lists
                )
            }
        }
        .sheet(item: $editingList) { list in
            NavigationStack {
                HomeTodoListEditorView(
                    household: household,
                    list: list,
                    existingLists: lists
                )
            }
        }
        .appActionSheet(
            isPresented: $showingRemoveListConfirmation,
            title: "Remove to-do list?",
            message: "This removes the list from active Home tracking. Items in the list will no longer appear.",
            systemImage: "archivebox.fill",
            tint: .red,
            options: removeListOptions
        )
    }

    private var removeListOptions: [AppActionSheetOption] {
        [
            AppActionSheetOption(
                title: "Remove List",
                subtitle: listPendingRemoval?.name,
                systemImage: "archivebox.fill",
                tint: .red,
                role: .destructive
            ) {
                if let listPendingRemoval {
                    _ = HomeTodoService.archiveList(listPendingRemoval, context: modelContext)
                }
                listPendingRemoval = nil
            }
        ]
    }
}

private struct HomeTodoListRow: View {
    let list: HomeTodoList
    let items: [HomeTodoItem]

    private var activeCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    private var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activeCount == 0 && completedCount > 0 ? "checkmark.circle.fill" : "checklist")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background((activeCount == 0 && completedCount > 0 ? Color.green : AppTheme.accent).gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text("\(activeCount) to do")
                    Text("\(completedCount) done")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = list.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct HomeTodoListEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let list: HomeTodoList?
    let existingLists: [HomeTodoList]

    @State private var name: String
    @State private var notes: String

    init(household: Household, list: HomeTodoList?, existingLists: [HomeTodoList]) {
        self.household = household
        self.list = list
        self.existingLists = existingLists
        _name = State(initialValue: list?.name ?? "")
        _notes = State(initialValue: list?.notes ?? "")
    }

    var body: some View {
        Form {
            Section("List") {
                TextField("Name", text: $name)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle(list == nil ? "New To-Do List" : "Edit To-Do List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        if let list {
            HomeTodoService.updateList(list, name: name, notes: notes, context: modelContext)
        } else {
            _ = HomeTodoService.createList(
                name: name,
                householdID: household.id,
                existingLists: existingLists,
                context: modelContext
            )
        }
        dismiss()
    }
}

private struct HomeTodoListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CaregiverIdentityService.currentCaregiverNameKey) private var currentCaregiverName = ""
    @AppStorage(CaregiverIdentityService.primaryCaregiverNameKey) private var primaryCaregiverName = "Caregiver 1"

    @Bindable var list: HomeTodoList
    let items: [HomeTodoItem]

    @State private var editingItem: HomeTodoItem?
    @State private var showingCompleted = false
    @State private var showingDeleteItemConfirmation = false
    @State private var itemPendingDelete: HomeTodoItem?

    private var actorName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: primaryCaregiverName
        )
    }

    private var sortedActiveItems: [HomeTodoItem] {
        items
            .filter { !$0.isCompleted }
            .sorted { ($0.sortOrder ?? 0, $0.createdAt) < ($1.sortOrder ?? 0, $1.createdAt) }
    }

    private var sortedCompletedItems: [HomeTodoItem] {
        items
            .filter(\.isCompleted)
            .sorted { ($0.sortOrder ?? 0, $0.completedAt ?? $0.updatedAt) < ($1.sortOrder ?? 0, $1.completedAt ?? $1.updatedAt) }
    }

    var body: some View {
        let activeItems = sortedActiveItems
        let completedItems = sortedCompletedItems
        let canReorderVisibleItems = activeItems.count > 1
            || (showingCompleted && completedItems.count > 1)

        List {
            Section {
                if activeItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing active",
                        systemImage: "checkmark.circle",
                        description: Text("Add an item or reopen one from Completed.")
                    )
                } else {
                    ForEach(activeItems) { item in
                        HomeTodoItemRow(
                            item: item,
                            isCompleted: false,
                            toggle: { setCompleted(item, true) },
                            edit: { editingItem = item },
                            delete: { confirmDelete(item) }
                        )
                    }
                    .onMove { source, destination in
                        reorder(activeItems, from: source, to: destination)
                    }
                }
            } header: {
                AppSectionHeader(title: "To Do", subtitle: "\(activeItems.count)")
            }

            Section {
                if showingCompleted {
                    if completedItems.isEmpty {
                        ContentUnavailableView(
                            "No completed items",
                            systemImage: "circle",
                            description: Text("Checked-off items will appear here.")
                        )
                    } else {
                        ForEach(completedItems) { item in
                            HomeTodoItemRow(
                                item: item,
                                isCompleted: true,
                                toggle: { setCompleted(item, false) },
                                edit: { editingItem = item },
                                delete: { confirmDelete(item) }
                            )
                        }
                        .onMove { source, destination in
                            reorder(completedItems, from: source, to: destination)
                        }
                    }
                }
            } header: {
                Button {
                    showingCompleted.toggle()
                } label: {
                    HStack {
                        AppSectionHeader(title: "Completed", subtitle: "\(completedItems.count)")
                        Spacer()
                        Image(systemName: showingCompleted ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canReorderVisibleItems {
                    EditButton()
                }

                HomeTodoAddItemButton(
                    list: list,
                    existingItems: items,
                    defaultActorName: actorName
                )
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                HomeTodoItemEditorView(
                    list: list,
                    item: item,
                    existingItems: items,
                    defaultActorName: actorName
                )
            }
        }
        .appActionSheet(
            isPresented: $showingDeleteItemConfirmation,
            title: "Delete to-do item?",
            message: "This permanently removes the item from this list.",
            systemImage: "trash.fill",
            tint: .red,
            options: deleteItemOptions
        )
    }

    private func setCompleted(_ item: HomeTodoItem, _ isCompleted: Bool) {
        HomeTodoService.setCompleted(
            item,
            isCompleted: isCompleted,
            completedBy: actorName,
            siblingItems: items,
            context: modelContext
        )
    }

    private func reorder(_ visibleItems: [HomeTodoItem], from source: IndexSet, to destination: Int) {
        HomeTodoService.reorderItems(
            visibleItems,
            from: source,
            to: destination,
            context: modelContext
        )
    }

    private func confirmDelete(_ item: HomeTodoItem) {
        itemPendingDelete = item
        showingDeleteItemConfirmation = true
    }

    private var deleteItemOptions: [AppActionSheetOption] {
        [
            AppActionSheetOption(
                title: "Delete Item",
                subtitle: itemPendingDelete?.title,
                systemImage: "trash.fill",
                tint: .red,
                role: .destructive
            ) {
                if let itemPendingDelete {
                    HomeTodoService.deleteItem(itemPendingDelete, context: modelContext)
                }
                itemPendingDelete = nil
            }
        ]
    }
}

/// Owns add-editor presentation independently from the detail list. Opening
/// the editor should not force every visible to-do row to sort and diff before
/// the title field can receive focus.
private struct HomeTodoAddItemButton: View {
    let list: HomeTodoList
    let existingItems: [HomeTodoItem]
    let defaultActorName: String

    @State private var showingEditor = false

    var body: some View {
        Button {
            showingEditor = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add to-do item")
        .accessibilityIdentifier("home.todo.add-item")
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HomeTodoItemEditorView(
                    list: list,
                    item: nil,
                    existingItems: existingItems,
                    defaultActorName: defaultActorName
                )
            }
        }
    }
}

private struct HomeTodoItemRow: View {
    let item: HomeTodoItem
    let isCompleted: Bool
    let toggle: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? .green : .secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isCompleted ? "Mark active" : "Mark complete")

            Button(action: edit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted)
                    if let notes = item.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let assignmentText {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.fill")
                            Text(assignmentText)
                                .lineLimit(1)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.11), in: Capsule())
                        .accessibilityElement(children: .combine)
                    }
                    Text(metadata)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .swipeActions {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var metadata: String {
        if isCompleted {
            let actor = item.completedBy?.nilIfBlank ?? "Someone"
            if let completedAt = item.completedAt {
                return "Completed by \(actor) \(DateFormatting.day.string(from: completedAt))"
            }
            return "Completed by \(actor)"
        }
        let actor = item.addedBy?.nilIfBlank ?? "Someone"
        return "Added by \(actor) \(DateFormatting.day.string(from: item.createdAt))"
    }

    private var assignmentText: String? {
        item.assignedCaregiverName?.nilIfBlank.map { "Assigned to \($0)" }
    }
}

private enum HomeTodoCaregiverAssignment: Hashable {
    case unassigned
    case me
    case caregiver(String)
}

private struct HomeTodoItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let list: HomeTodoList
    let item: HomeTodoItem?
    let existingItems: [HomeTodoItem]
    let defaultActorName: String
    private let isUsingFamilySync: Bool
    private let familyCaregiverNames: [String]

    @State private var title: String
    @State private var notes: String
    @State private var addedBy: String
    @State private var caregiverAssignment: HomeTodoCaregiverAssignment
    @FocusState private var isTitleFocused: Bool

    init(
        list: HomeTodoList,
        item: HomeTodoItem?,
        existingItems: [HomeTodoItem],
        defaultActorName: String
    ) {
        self.list = list
        self.item = item
        self.existingItems = existingItems
        self.defaultActorName = defaultActorName
        let defaults = UserDefaults.standard
        isUsingFamilySync = PersistenceService.familySyncMode(defaults: defaults)
            == .sharedFamilySync
        familyCaregiverNames = CaregiverIdentityService.familySyncCaregiverNames(
            defaults: defaults
        ).filter {
            !CaregiverIdentityService.namesMatch($0, defaultActorName)
        }
        _title = State(initialValue: item?.title ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _addedBy = State(initialValue: item?.addedBy ?? defaultActorName)
        if let assignedName = item?.assignedCaregiverName?.nilIfBlank {
            _caregiverAssignment = State(
                initialValue: CaregiverIdentityService.namesMatch(
                    assignedName,
                    defaultActorName
                ) ? .me : .caregiver(assignedName)
            )
        } else {
            _caregiverAssignment = State(initialValue: .unassigned)
        }
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Title", text: $title)
                    .focused($isTitleFocused)
                    .accessibilityIdentifier("home.todo.title")
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section("Added By") {
                TextField("Name", text: $addedBy)
            }
            Section {
                Picker("Assigned to", selection: $caregiverAssignment) {
                    Text("Me — \(defaultActorName)")
                        .tag(HomeTodoCaregiverAssignment.me)
                    if isUsingFamilySync {
                        ForEach(familyCaregiverNames, id: \.self) { name in
                            Text(name).tag(HomeTodoCaregiverAssignment.caregiver(name))
                        }
                    }
                    Text("Unassigned").tag(HomeTodoCaregiverAssignment.unassigned)
                    if let currentAssignedName {
                        Text("\(currentAssignedName) — current assignment")
                            .tag(HomeTodoCaregiverAssignment.caregiver(currentAssignedName))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("home.todo.assignee")
            } header: {
                Text("Assignment")
            } footer: {
                Text(assignmentFooterText)
            }
        }
        .navigationTitle(item == nil ? "Add To-Do" : "Edit To-Do")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard item == nil else { return }
            isTitleFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        if let item {
            HomeTodoService.updateItem(
                item,
                title: title,
                notes: notes,
                addedBy: addedBy,
                assignedCaregiverName: resolvedAssignedCaregiverName,
                context: modelContext
            )
        } else {
            _ = HomeTodoService.addItem(
                title: title,
                notes: notes,
                addedBy: addedBy,
                assignedCaregiverName: resolvedAssignedCaregiverName,
                to: list,
                existingItems: existingItems,
                context: modelContext
            )
        }
        dismiss()
    }

    private var currentAssignedName: String? {
        guard case .caregiver(let name) = caregiverAssignment,
              !familyCaregiverNames.contains(name) else {
            return nil
        }
        return name
    }

    private var resolvedAssignedCaregiverName: String? {
        switch caregiverAssignment {
        case .unassigned:
            return nil
        case .me:
            return defaultActorName
        case .caregiver(let name):
            return name
        }
    }

    private var assignmentFooterText: String {
        isUsingFamilySync
            ? "Choose yourself, an accepted Family Sync caregiver, or leave this task unassigned."
            : "Family Sync is not active, so this task can be assigned only to you or left unassigned."
    }
}

private struct QuickAddShoppingItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]

    @State private var itemName = ""
    @State private var selectedListID: UUID?

    private var selectedList: ShoppingList? {
        if let selectedListID,
           let list = shoppingLists.first(where: { $0.id == selectedListID }) {
            return list
        }
        return shoppingLists.first { $0.name.localizedCaseInsensitiveContains("Trader") }
            ?? shoppingLists.first
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $itemName)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                Picker("List", selection: $selectedListID) {
                    ForEach(shoppingLists) { list in
                        Text(list.name).tag(UUID?.some(list.id))
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addItem)
                        .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                selectedListID = selectedList?.id
            }
        }
    }

    private func addItem() {
        guard let selectedList else { return }
        ShoppingListService.addItem(
            named: itemName,
            to: selectedList,
            sectionID: nil,
            existingItems: shoppingItems.filter { $0.shoppingListID == selectedList.id },
            context: modelContext
        )
        dismiss()
    }
}

private struct ShoppingListsView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let stores: [FoodStore]
    let openList: (ShoppingList) -> Void

    @State private var showingNewList = false
    @State private var listPendingDelete: ShoppingList?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        let itemsByListID = Dictionary(grouping: shoppingItems, by: \.shoppingListID)
        List {
            Section {
                if shoppingLists.isEmpty {
                    ContentUnavailableView(
                        "No shopping lists",
                        systemImage: "cart",
                        description: Text("Create a reusable list for a store, pantry run, or household trip.")
                    )
                } else {
                    ForEach(shoppingLists) { list in
                        Button {
                            openList(list)
                        } label: {
                            ShoppingListSummaryRow(
                                list: list,
                                store: stores.first { $0.id == list.storeID },
                                items: itemsByListID[list.id] ?? []
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                listPendingDelete = list
                                showingDeleteConfirmation = true
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Duplicate") {
                                duplicate(list)
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove(perform: moveLists)
                }
            } header: {
                AppSectionHeader(title: "Reusable Lists", subtitle: "\(shoppingLists.count)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button {
                    showingNewList = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create shopping list")
            }
        }
        .sheet(isPresented: $showingNewList) {
            ShoppingListCreateView(household: household, stores: stores)
        }
        .confirmationDialog(
            "Delete shopping list?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                if let listPendingDelete {
                    ShoppingListService.archiveList(listPendingDelete, context: modelContext)
                }
                listPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                listPendingDelete = nil
            }
        } message: {
            Text("This removes the list from active shopping lists.")
        }
    }

    private func duplicate(_ list: ShoppingList) {
        ShoppingListService.duplicateList(
            list,
            items: shoppingItems,
            existingLists: shoppingLists,
            context: modelContext
        )
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
        var ordered = shoppingLists
        ordered.move(fromOffsets: source, toOffset: destination)
        ShoppingListService.reorderLists(ordered, context: modelContext)
    }
}

private struct ShoppingListCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let stores: [FoodStore]

    @State private var name = ""
    @State private var selectedStoreID: UUID?
    @State private var newlyCreatedStore: FoodStore?
    @State private var showingNewStore = false

    private var availableStores: [FoodStore] {
        guard let newlyCreatedStore,
              !stores.contains(where: { $0.id == newlyCreatedStore.id })
        else { return stores }
        return stores + [newlyCreatedStore]
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("List") {
                    TextField("List name", text: $name)
                        .accessibilityIdentifier("shopping-list.name")
                }

                Section {
                    Picker("Use store", selection: $selectedStoreID) {
                        Text("General").tag(UUID?.none)
                        ForEach(availableStores) { store in
                            Text(store.name).tag(UUID?.some(store.id))
                        }
                    }
                    .accessibilityIdentifier("shopping-list.store")

                    Button {
                        showingNewStore = true
                    } label: {
                        Label(
                            stores.isEmpty ? "Add Your First Store" : "Add a New Store",
                            systemImage: "plus.circle.fill"
                        )
                    }
                    .accessibilityIdentifier("shopping-list.add-store")
                } header: {
                    Text("Store (Optional)")
                } footer: {
                    Text("General lists work anywhere. Add a store to organize this list using that store's aisles and sections.")
                }
            }
            .navigationTitle("New Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard ShoppingListService.createList(
                            name: name,
                            householdID: household.id,
                            storeID: selectedStoreID,
                            context: modelContext
                        ) != nil else { return }
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("shopping-list.save")
                }
            }
            .sheet(isPresented: $showingNewStore) {
                StoreCreateView(household: household) { store in
                    newlyCreatedStore = store
                    selectedStoreID = store.id
                }
            }
        }
    }
}

private struct ShoppingListSummaryRow: View {
    let list: ShoppingList
    let store: FoodStore?
    let items: [ShoppingListItem]

    private var activeCount: Int { items.filter { !$0.isChecked }.count }
    private var checkedCount: Int { items.filter(\.isChecked).count }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cart.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text("\(activeCount) active")
                    Text("\(checkedCount) checked")
                    if let lastUsed = list.lastUsedAt {
                        Text("Last \(DateFormatting.day.string(from: lastUsed))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = list.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if store != nil {
                Image(systemName: "map")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct ShoppingListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var list: ShoppingList
    let items: [ShoppingListItem]
    let shoppingLists: [ShoppingList]
    let store: FoodStore?
    let sections: [FoodStoreSection]
    let inventoryItems: [InventoryItem]
    let mealPrepItems: [MealPrepItem]
    let openShoppingMode: () -> Void
    let openMealPrep: () -> Void

    @State private var selectedSectionID: UUID?
    @State private var showingChecked = true
    @State private var searchText = ""
    @State private var editingItem: ShoppingListItem?
    @State private var showingDeleteConfirmation = false
    @State private var itemPendingDelete: ShoppingListItem?
    @State private var showingDeleteItemConfirmation = false
    @State private var showingListEditor = false
    @State private var showingBulkAdd = false
    @State private var showingDuplicatedConfirmation = false

    private var visibleItems: [ShoppingListItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return items
        }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        let visibleItems = self.visibleItems
        let activeItemsBySectionID = Dictionary(
            grouping: visibleItems.filter { !$0.isChecked },
            by: \.storeSectionID
        )
        let checkedItems = visibleItems.filter(\.isChecked)
        List {
            ShoppingListFastAddSection(
                list: list,
                items: items,
                sections: sections,
                selectedSectionID: $selectedSectionID
            )

            suggestionsSection

            ForEach(sections) { section in
                let sectionItems = sortedItems(activeItemsBySectionID[section.id] ?? [])
                if !sectionItems.isEmpty {
                    Section(section.name) {
                        ForEach(sectionItems) { item in
                            ShoppingListItemRow(item: item, large: false) {
                                ShoppingListService.setChecked(
                                    item,
                                    isChecked: !item.isChecked,
                                    context: modelContext
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Edit") { editingItem = item }
                                Button("Delete", role: .destructive) {
                                    itemPendingDelete = item
                                    showingDeleteItemConfirmation = true
                                }
                            }
                            .swipeActions(edge: .leading) {
                                favoriteButton(for: item)
                            }
                        }
                    }
                }
            }

            let otherItems = sortedItems(activeItemsBySectionID[nil] ?? [])
            if !otherItems.isEmpty {
                Section("Other") {
                    ForEach(otherItems) { item in
                        ShoppingListItemRow(item: item, large: false) {
                            ShoppingListService.setChecked(
                                item,
                                isChecked: !item.isChecked,
                                context: modelContext
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Edit") { editingItem = item }
                            Button("Delete", role: .destructive) {
                                itemPendingDelete = item
                                showingDeleteItemConfirmation = true
                            }
                        }
                        .swipeActions(edge: .leading) {
                            favoriteButton(for: item)
                        }
                    }
                }
            }

            if showingChecked {
                if !checkedItems.isEmpty {
                    Section("In Cart") {
                        ForEach(checkedItems) { item in
                            ShoppingListItemRow(item: item, large: false) {
                                ShoppingListService.setChecked(
                                    item,
                                    isChecked: false,
                                    context: modelContext
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Edit") { editingItem = item }
                                Button("Delete", role: .destructive) {
                                    itemPendingDelete = item
                                    showingDeleteItemConfirmation = true
                                }
                            }
                            .swipeActions(edge: .leading) {
                                favoriteButton(for: item)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(list.name)
        .debouncedSearch(text: $searchText, prompt: "Search this list")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    openShoppingMode()
                } label: {
                    Image(systemName: "figure.walk.motion")
                }
                .accessibilityLabel("Shopping mode")
                Menu {
                    Button(showingChecked ? "Hide checked items" : "Show checked items") {
                        showingChecked.toggle()
                    }
                    Button("Reactivate all checked") {
                        ShoppingListService.reactivateAllChecked(
                            in: list,
                            items: items,
                            context: modelContext
                        )
                    }
                    Button("Reactivate staples") {
                        ShoppingListService.reactivateStaples(
                            in: list,
                            items: items,
                            context: modelContext
                        )
                    }
                    Button("Reactivate last trip") {
                        ShoppingListService.reactivateLastTrip(
                            in: list,
                            items: items,
                            context: modelContext
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reactivate items")
                Menu {
                    Button("Edit List") {
                        showingListEditor = true
                    }
                    Button("Add Multiple Items") {
                        showingBulkAdd = true
                    }
                    Button("Duplicate List") {
                        ShoppingListService.duplicateList(
                            list,
                            items: items,
                            existingLists: shoppingLists,
                            context: modelContext
                        )
                        showingDuplicatedConfirmation = true
                    }
                    Divider()
                    Button("Delete List", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More list actions")
            }
        }
        .sheet(item: $editingItem) { item in
            ShoppingListItemEditorView(
                item: item,
                sourceList: list,
                shoppingLists: shoppingLists,
                sections: sections
            )
        }
        .sheet(isPresented: $showingListEditor) {
            ShoppingListEditorView(list: list)
        }
        .sheet(isPresented: $showingBulkAdd) {
            BulkShoppingItemAddView(
                list: list,
                items: items,
                sections: sections,
                initialSectionID: selectedSectionID
            )
        }
        .confirmationDialog(
            "Delete \(list.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                ShoppingListService.archiveList(list, context: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the list from active shopping lists.")
        }
        .confirmationDialog(
            "Delete item?",
            isPresented: $showingDeleteItemConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Item", role: .destructive) {
                if let itemPendingDelete {
                    ShoppingListService.deleteItem(itemPendingDelete, context: modelContext)
                }
                itemPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text("This permanently removes the item from this shopping list.")
        }
        .alert("List duplicated", isPresented: $showingDuplicatedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A reusable copy was added with every item reset for a new trip.")
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let suggestions = FoodSuggestionService.suggestions(
            for: list,
            items: items,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems
        )
        if !suggestions.isEmpty {
            Section("Suggestions") {
                ForEach(suggestions) { suggestion in
                    Button {
                        apply(suggestion)
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                    Text(suggestion.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: suggestion.systemImage)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sortedItems(_ values: [ShoppingListItem]) -> [ShoppingListItem] {
        values
            .sorted {
                ($0.isFavorite ? 0 : 1, $0.sortOrder ?? 0, $0.name)
                    < ($1.isFavorite ? 0 : 1, $1.sortOrder ?? 0, $1.name)
            }
    }

    private func favoriteButton(for item: ShoppingListItem) -> some View {
        Button(item.isFavorite ? "Unfavorite" : "Favorite") {
            ShoppingListService.setFavorite(
                item,
                isFavorite: !item.isFavorite,
                context: modelContext
            )
        }
        .tint(.pink)
    }

    private func apply(_ suggestion: FoodSuggestion) {
        switch suggestion.action {
        case .reactivateStaples:
            ShoppingListService.reactivateStaples(
                in: list,
                items: items,
                context: modelContext
            )
        case .reactivateFrequent:
            ShoppingListService.reactivateFrequentItems(
                in: list,
                items: items,
                context: modelContext
            )
        case .addUsedUpInventory:
            ShoppingListService.addUsedUpInventoryItems(
                inventoryItems,
                to: list,
                existingItems: items,
                context: modelContext
            )
        case .reviewMealPrep:
            openMealPrep()
        }
    }
}

private struct ShoppingListFastAddSection: View {
    @Environment(\.modelContext) private var modelContext
    let list: ShoppingList
    let items: [ShoppingListItem]
    let sections: [FoodStoreSection]
    @Binding var selectedSectionID: UUID?
    @State private var text = ""

    private var suggestions: [ShoppingListItem] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return items
            .filter {
                $0.isChecked
                    && ($0.name.localizedCaseInsensitiveContains(query)
                        || ($0.notes?.localizedCaseInsensitiveContains(query) ?? false))
            }
            .sorted {
                ($0.isFavorite ? 0 : 1, $0.isRecurringStaple ? 0 : 1, -$0.purchaseCount, $0.name)
                    < ($1.isFavorite ? 0 : 1, $1.isRecurringStaple ? 0 : 1, -$1.purchaseCount, $1.name)
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Section {
            HStack {
                TextField("Add item", text: $text)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                Menu {
                    Button("No Section") { selectedSectionID = nil }
                    ForEach(sections) { section in
                        Button(section.name) { selectedSectionID = section.id }
                    }
                } label: {
                    Label(selectedSectionName, systemImage: "square.grid.2x2")
                        .labelStyle(.iconOnly)
                }
                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let notes = list.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(suggestions) { item in
                Button {
                    reactivate(item)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text("Previously purchased\(item.quantityText.isEmpty ? "" : " · \(item.quantityText)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedSectionName: String {
        selectedSectionID.flatMap { id in sections.first { $0.id == id }?.name } ?? "Section"
    }

    private func addItem() {
        ShoppingListService.addItem(
            named: text,
            to: list,
            sectionID: selectedSectionID,
            existingItems: items,
            context: modelContext
        )
        text = ""
    }

    private func reactivate(_ item: ShoppingListItem) {
        ShoppingListService.addItem(
            named: item.name,
            to: list,
            sectionID: item.storeSectionID,
            existingItems: items,
            context: modelContext
        )
        text = ""
    }
}

private struct ShoppingListItemRow: View {
    @Bindable var item: ShoppingListItem
    var large: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(large ? .title2 : .title3)
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .frame(width: large ? 42 : 30, height: large ? 42 : 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.name)
                            .font(large ? .headline : .body)
                            .strikethrough(item.isChecked)
                            .foregroundStyle(.primary)
                        if item.isRecurringStaple {
                            Image(systemName: "repeat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if item.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                        }
                    }
                    HStack(spacing: 8) {
                        if !item.quantityText.isEmpty {
                            Text(item.quantityText)
                        }
                        if item.priority == .high {
                            Text("High")
                                .foregroundStyle(.red)
                        }
                        if let notes = item.notes, !notes.isEmpty {
                            Text(notes)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, large ? 7 : 2)
        }
        .buttonStyle(.plain)
    }
}

private struct ShoppingModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var list: ShoppingList
    let items: [ShoppingListItem]
    let sections: [FoodStoreSection]
    let locations: [InventoryLocation]

    @State private var filter: ShoppingModeFilter = .active
    @State private var showingInventoryPrompt = false

    private var activeItems: [ShoppingListItem] { items.filter { !$0.isChecked } }
    private var checkedItems: [ShoppingListItem] { items.filter(\.isChecked) }

    var body: some View {
        let modeItemsBySectionID = Dictionary(
            grouping: items.filter { item in
                filter == .all ||
                    (filter == .active && !item.isChecked) ||
                    (filter == .checked && item.isChecked)
            },
            by: \.storeSectionID
        ).mapValues { values in
            values.sorted {
                ($0.isFavorite ? 0 : 1, $0.sortOrder ?? 0, $0.name)
                    < ($1.isFavorite ? 0 : 1, $1.sortOrder ?? 0, $1.name)
            }
        }

        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(checkedItems.count) of \(items.count) items")
                        .font(.title3.weight(.semibold))
                    ProgressView(
                        value: items.isEmpty ? 0 : Double(checkedItems.count),
                        total: Double(max(items.count, 1))
                    )
                    Picker("Filter", selection: $filter) {
                        ForEach(ShoppingModeFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 6)
            }

            ForEach(sections) { section in
                let sectionItems = modeItemsBySectionID[section.id] ?? []
                if !sectionItems.isEmpty {
                    Section(section.name) {
                        ForEach(sectionItems) { item in
                            ShoppingListItemRow(item: item, large: true) {
                                ShoppingListService.setChecked(
                                    item,
                                    isChecked: !item.isChecked,
                                    context: modelContext
                                )
                            }
                        }
                    }
                }
            }

            let otherItems = modeItemsBySectionID[nil] ?? []
            if !otherItems.isEmpty {
                Section("Other") {
                    ForEach(otherItems) { item in
                        ShoppingListItemRow(item: item, large: true) {
                            ShoppingListService.setChecked(
                                item,
                                isChecked: !item.isChecked,
                                context: modelContext
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Shopping Mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish Trip") {
                    showingInventoryPrompt = true
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .confirmationDialog("Add purchased items to inventory?", isPresented: $showingInventoryPrompt) {
            Button("Add Purchased Items") {
                finish(addToInventory: true)
            }
            Button("Skip Inventory") {
                finish(addToInventory: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Purchased items can be added to Pantry by default. You can edit locations later.")
        }
    }

    private func finish(addToInventory: Bool) {
        ShoppingListService.finishTrip(
            list: list,
            items: items,
            addToInventory: addToInventory,
            locations: locations,
            context: modelContext
        )
        dismiss()
    }
}

private struct ShoppingListEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var list: ShoppingList

    @State private var name = ""
    @State private var notes = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("List") {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Edit Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ShoppingListService.updateList(
                            list,
                            name: name,
                            notes: notes,
                            context: modelContext
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                name = list.name
                notes = list.notes ?? ""
            }
        }
    }
}

private struct BulkShoppingItemAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let list: ShoppingList
    let items: [ShoppingListItem]
    let sections: [FoodStoreSection]
    let initialSectionID: UUID?

    @State private var text = ""
    @State private var sectionID: UUID?

    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Items to add")
                } header: {
                    Text("Items")
                } footer: {
                    Text("Enter one item per line. Comma-separated items also work. Existing checked items are reactivated instead of duplicated.")
                }

                if !sections.isEmpty {
                    Picker("Section", selection: $sectionID) {
                        Text("Other").tag(UUID?.none)
                        ForEach(sections) { section in
                            Text(section.name).tag(UUID?.some(section.id))
                        }
                    }
                }
            }
            .navigationTitle("Add Multiple Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        ShoppingListService.addItems(
                            from: text,
                            to: list,
                            sectionID: sectionID,
                            existingItems: items,
                            context: modelContext
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear {
                sectionID = initialSectionID
            }
        }
    }
}

private struct ShoppingListItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: ShoppingListItem
    let sourceList: ShoppingList
    let shoppingLists: [ShoppingList]
    let sections: [FoodStoreSection]

    @State private var name = ""
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var notes = ""
    @State private var sectionID: UUID?
    @State private var isStaple = false
    @State private var isFavorite = false
    @State private var priority: ShoppingItemPriority = .normal
    @State private var inventoryBehavior: InventoryLinkBehavior = .askWhenChecked
    @State private var destinationListID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                LabeledContent("Quantity") {
                    TextField("Optional", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Unit") {
                    TextField("Optional", text: $unit)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Section", selection: $sectionID) {
                    Text("Other").tag(UUID?.none)
                    ForEach(sections) { section in
                        Text(section.name).tag(UUID?.some(section.id))
                    }
                }
                Toggle("Staple", isOn: $isStaple)
                Toggle("Favorite", isOn: $isFavorite)
                Picker("Priority", selection: $priority) {
                    ForEach(ShoppingItemPriority.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Inventory", selection: $inventoryBehavior) {
                    ForEach(InventoryLinkBehavior.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                TextField("Notes (what you liked or disliked)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)

                if shoppingLists.count > 1 {
                    Picker("List", selection: $destinationListID) {
                        ForEach(shoppingLists) { list in
                            Text(list.name).tag(UUID?.some(list.id))
                        }
                    }
                }
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ShoppingListService.updateItem(
                            item,
                            name: name,
                            quantity: quantity,
                            unit: unit,
                            notes: notes,
                            sectionID: sectionID,
                            isRecurringStaple: isStaple,
                            isFavorite: isFavorite,
                            priority: priority,
                            inventoryLinkBehavior: inventoryBehavior,
                            context: modelContext
                        )
                        if let destinationListID,
                           destinationListID != sourceList.id,
                           let destination = shoppingLists.first(where: { $0.id == destinationListID }) {
                            let descriptor = FetchDescriptor<ShoppingListItem>(
                                predicate: #Predicate { $0.shoppingListID == destinationListID },
                                sortBy: [SortDescriptor(\ShoppingListItem.sortOrder)]
                            )
                            let destinationItems = (try? modelContext.fetch(descriptor)) ?? []
                            ShoppingListService.moveItem(
                                item,
                                from: sourceList,
                                to: destination,
                                existingDestinationItems: destinationItems,
                                context: modelContext
                            )
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = item.name
                quantity = item.quantity
                unit = item.unit ?? ""
                notes = item.notes ?? ""
                sectionID = item.storeSectionID
                isStaple = item.isRecurringStaple
                isFavorite = item.isFavorite
                priority = item.priority
                inventoryBehavior = item.inventoryLinkBehavior
                destinationListID = sourceList.id
            }
        }
    }
}

private struct InventoryHomeView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let locations: [InventoryLocation]
    let inventoryItems: [InventoryItem]
    let mealPrepItems: [MealPrepItem]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let openItem: (InventoryItem) -> Void

    @State private var selectedLocationType: InventoryLocationType?
    @State private var filter: InventoryFilter = .available
    @State private var sort: InventorySort = .recentlyAdded
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var showingLocationManager = false
    @State private var itemPendingDelete: InventoryItem?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })

        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        locationChip(title: "All", type: nil)
                        ForEach(InventoryLocationType.allCases) { type in
                            locationChip(title: type.displayName, type: type)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Picker("Filter", selection: $filter) {
                    ForEach(InventoryFilter.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Sort", selection: $sort) {
                    ForEach(InventorySort.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
            Section("Inventory") {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No inventory items",
                        systemImage: "cabinet",
                        description: Text("Add pantry, fridge, freezer, or household items so they are easy to find later.")
                    )
                } else {
                    ForEach(filteredItems) { item in
                        Button { openItem(item) } label: {
                            InventoryItemRow(
                                item: item,
                                location: locationsByID[item.locationID]
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                itemPendingDelete = item
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .searchable(text: $searchText, prompt: "Search inventory")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingLocationManager = true } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityLabel("Manage inventory locations")
                Button { showingEditor = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add inventory item")
            }
        }
        .sheet(isPresented: $showingEditor) {
            InventoryItemEditorView(
                household: household,
                item: nil,
                locations: locations
            )
        }
        .sheet(isPresented: $showingLocationManager) {
            InventoryLocationManagerView(
                household: household,
                locations: locations,
                inventoryItems: inventoryItems,
                mealPrepItems: mealPrepItems
            )
        }
        .confirmationDialog(
            "Delete inventory item?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Item", role: .destructive) {
                if let itemPendingDelete {
                    FoodInventoryService.deleteInventoryItem(itemPendingDelete, context: modelContext)
                }
                itemPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text("This permanently removes the item from inventory.")
        }
    }

    @ViewBuilder
    private func locationChip(title: String, type: InventoryLocationType?) -> some View {
        Button {
            selectedLocationType = type
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    selectedLocationType == type ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var filteredItems: [InventoryItem] {
        let locationIDs = Set(locations
            .filter { selectedLocationType == nil || $0.locationType == selectedLocationType }
            .map(\.id))
        var result = inventoryItems.filter { item in
            (selectedLocationType == nil || locationIDs.contains(item.locationID))
                && (filter == .all
                    || (filter == .available && item.status == .available)
                    || (filter == .usedUp && item.status == .usedUp)
                    || filter == .mealPrep)
                && (searchText.isEmpty
                    || item.name.localizedCaseInsensitiveContains(searchText)
                    || (item.notes?.localizedCaseInsensitiveContains(searchText) ?? false))
        }
        if filter == .mealPrep {
            result = []
        }
        switch sort {
        case .recentlyAdded:
            return result.sorted { $0.createdAt > $1.createdAt }
        case .recentlyUsed:
            return result.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
        case .name:
            return result.sorted { $0.name < $1.name }
        case .location:
            return result.sorted { $0.locationID.uuidString < $1.locationID.uuidString }
        case .quantity:
            return result.sorted { $0.quantity > $1.quantity }
        }
    }
}

private struct InventoryItemRow: View {
    let item: InventoryItem
    let location: InventoryLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(item.quantityText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.status == .available ? .primary : .secondary)
            }
            HStack(spacing: 8) {
                if let location {
                    Label(location.name, systemImage: location.locationType.systemImage)
                }
                if let detail = item.storageDetail {
                    Text(detail)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct InventoryLocationManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let locations: [InventoryLocation]
    let inventoryItems: [InventoryItem]
    let mealPrepItems: [MealPrepItem]

    @State private var showingEditor = false
    @State private var editingLocation: InventoryLocation?
    @State private var showingArchiveBlocked = false
    @State private var locationPendingArchive: InventoryLocation?
    @State private var showingArchiveConfirmation = false

    var body: some View {
        let inventoryCountByLocationID = inventoryItems.reduce(into: [UUID: Int]()) { counts, item in
            counts[item.locationID, default: 0] += 1
        }
        let mealPrepCountByLocationID = mealPrepItems.reduce(into: [UUID: Int]()) { counts, item in
            if !item.isArchived {
                counts[item.locationID, default: 0] += 1
            }
        }

        NavigationStack {
            List {
                Section("Locations") {
                    ForEach(locations) { location in
                        Button {
                            editingLocation = location
                            showingEditor = true
                        } label: {
                            locationRow(
                                location,
                                count: inventoryCountByLocationID[location.id, default: 0]
                                    + mealPrepCountByLocationID[location.id, default: 0]
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Archive", role: .destructive) {
                                locationPendingArchive = location
                                showingArchiveConfirmation = true
                            }
                        }
                    }
                }
            }
            .navigationTitle("Inventory Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingLocation = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add inventory location")
                }
            }
            .sheet(isPresented: $showingEditor) {
                InventoryLocationEditorView(
                    householdID: household.id,
                    location: editingLocation,
                    locations: locations
                )
            }
            .alert("Location is in use", isPresented: $showingArchiveBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Move or remove items from this location before archiving it.")
            }
            .confirmationDialog(
                "Archive location?",
                isPresented: $showingArchiveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Archive Location", role: .destructive) {
                    if let locationPendingArchive {
                        archive(locationPendingArchive)
                    }
                    locationPendingArchive = nil
                }
                Button("Cancel", role: .cancel) {
                    locationPendingArchive = nil
                }
            } message: {
                Text("Archived locations are removed from active inventory pickers.")
            }
        }
    }

    private func locationRow(_ location: InventoryLocation, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: location.locationType.systemImage)
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(location.locationType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = location.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if count > 0 {
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func archive(_ location: InventoryLocation) {
        let didArchive = InventoryLocationService.archiveLocation(
            location,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems,
            context: modelContext
        )
        showingArchiveBlocked = !didArchive
    }
}

private struct InventoryLocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let householdID: UUID
    let location: InventoryLocation?
    let locations: [InventoryLocation]
    var onSave: ((UUID) -> Void)?

    @State private var name = ""
    @State private var locationType: InventoryLocationType = .custom
    @State private var notes = ""
    @State private var showingDuplicateName = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $locationType) {
                    ForEach(InventoryLocationType.allCases) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle(location == nil ? "Add Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLocation() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                name = location?.name ?? ""
                locationType = location?.locationType ?? .custom
                notes = location?.notes ?? ""
            }
            .alert("Name already exists", isPresented: $showingDuplicateName) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Use a different location name.")
            }
        }
    }

    private func saveLocation() {
        if let location {
            let didSave = InventoryLocationService.updateLocation(
                location,
                name: name,
                locationType: locationType,
                notes: notes,
                existingLocations: locations,
                context: modelContext
            )
            if didSave {
                onSave?(location.id)
                dismiss()
            } else {
                showingDuplicateName = true
            }
        } else if let location = InventoryLocationService.addLocation(
            name: name,
            locationType: locationType,
            householdID: householdID,
            notes: notes,
            existingLocations: locations,
            context: modelContext
        ) {
            onSave?(location.id)
            dismiss()
        } else {
            showingDuplicateName = true
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct InventoryItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: InventoryItem
    let locations: [InventoryLocation]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedListID: UUID?

    var body: some View {
        List {
            Section {
                InventoryItemRow(
                    item: item,
                    location: locations.first { $0.id == item.locationID }
                )
            }
            Section("Actions") {
                Button("Use One", systemImage: "minus.circle") {
                    FoodInventoryService.useOne(item, context: modelContext)
                }
                Button("Mark Used Up", systemImage: "checkmark.circle") {
                    FoodInventoryService.markUsedUp(item, context: modelContext)
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    FoodInventoryService.duplicate(item, context: modelContext)
                }
                Button("Delete Item", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                Picker("Add to List", selection: $selectedListID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(shoppingLists) { list in
                        Text(list.name).tag(UUID?.some(list.id))
                    }
                }
                .onChange(of: selectedListID) { _, id in
                    guard let id,
                          let list = shoppingLists.first(where: { $0.id == id }) else { return }
                    FoodInventoryService.addToShoppingList(
                        item: item,
                        list: list,
                        existingItems: shoppingItems,
                        context: modelContext
                    )
                    selectedListID = nil
                }
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            InventoryItemEditorView(
                household: nil,
                item: item,
                locations: locations
            )
        }
        .confirmationDialog(
            "Delete \(item.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Item", role: .destructive) {
                FoodInventoryService.deleteInventoryItem(item, context: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the item from inventory.")
        }
    }
}

private struct InventoryItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household?
    let item: InventoryItem?
    let locations: [InventoryLocation]

    @State private var name = ""
    @State private var quantityText = ""
    @State private var unit = ""
    @State private var locationID: UUID?
    @State private var storageDetail = ""
    @State private var notes = ""
    @State private var showingLocationEditor = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Quantity", text: $quantityText)
                    .keyboardType(.decimalPad)
                TextField("Unit", text: $unit)
                Picker("Location", selection: $locationID) {
                    Text("Select Location").tag(UUID?.none)
                    ForEach(locations) { location in
                        Text(location.name).tag(UUID?.some(location.id))
                    }
                }
                if locationHouseholdID != nil {
                    Button("Add Location", systemImage: "plus") {
                        showingLocationEditor = true
                    }
                }
                TextField("Storage detail", text: $storageDetail)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle(item == nil ? "Add Inventory" : "Edit Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveItem() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                name = item?.name ?? ""
                quantityText = item.map { formatted($0.quantity) } ?? ""
                unit = item?.unit ?? ""
                locationID = item?.locationID
                storageDetail = item?.storageDetail ?? ""
                notes = item?.notes ?? ""
            }
            .sheet(isPresented: $showingLocationEditor) {
                if let householdID = locationHouseholdID {
                    InventoryLocationEditorView(
                        householdID: householdID,
                        location: nil,
                        locations: locations,
                        onSave: { locationID = $0 }
                    )
                }
            }
        }
    }

    private func saveItem() {
        guard let locationID, let quantity = parsedQuantity else { return }
        if let item {
            FoodInventoryService.updateInventoryItem(
                item,
                name: name,
                quantity: quantity,
                unit: unit,
                locationID: locationID,
                storageDetail: storageDetail,
                notes: notes,
                context: modelContext
            )
        } else if let household {
            FoodInventoryService.addInventoryItem(
                name: name,
                quantity: quantity,
                unit: unit,
                locationID: locationID,
                householdID: household.id,
                context: modelContext,
                storageDetail: storageDetail,
                notes: notes
            )
        }
        dismiss()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedQuantity != nil
            && locationID != nil
    }

    private var locationHouseholdID: UUID? {
        household?.id ?? item?.householdID
    }

    private var parsedQuantity: Double? {
        let trimmed = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value > 0 else { return nil }
        return value
    }
}

private struct MealPrepView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let locations: [InventoryLocation]
    let mealPrepItems: [MealPrepItem]
    let openItem: (MealPrepItem) -> Void

    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var itemPendingArchive: MealPrepItem?
    @State private var showingArchiveConfirmation = false

    var body: some View {
        let visibleItems = filteredItems
        let groupedLocations = self.groupedLocations
        let groupedLocationIDs = Set(groupedLocations.map(\.id))
        let itemsByLocationID = Dictionary(grouping: visibleItems, by: \.locationID)

        List {
            if visibleItems.isEmpty {
                ContentUnavailableView(
                    "No meal prep yet",
                    systemImage: "takeoutbag.and.cup.and.straw",
                    description: Text("Add prepared portions, freezer meals, or leftovers to track what is ready.")
                )
            } else {
                ForEach(groupedLocations, id: \.id) { location in
                    let items = itemsByLocationID[location.id] ?? []
                    if !items.isEmpty {
                        Section(location.name) {
                            ForEach(items) { item in
                                Button { openItem(item) } label: {
                                    MealPrepCard(
                                        item: item,
                                        location: location,
                                        useOne: {
                                            MealPrepService.use(
                                                item,
                                                servings: 1,
                                                notes: "",
                                                context: modelContext
                                            )
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Archive", role: .destructive) {
                                        itemPendingArchive = item
                                        showingArchiveConfirmation = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if !visibleItems.isEmpty && visibleItems.allSatisfy({ item in
                !groupedLocationIDs.contains(item.locationID)
            }) {
                Section {
                    ContentUnavailableView(
                        "Meal prep location unavailable",
                        systemImage: "archivebox",
                        description: Text("Move these items to an active fridge, freezer, pantry, or garage freezer location.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .searchable(text: $searchText, prompt: "Search meal prep")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditor = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add meal prep")
            }
        }
        .sheet(isPresented: $showingEditor) {
            MealPrepEditorView(
                household: household,
                item: nil,
                locations: locations
            )
        }
        .confirmationDialog(
            "Archive meal prep?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Item", role: .destructive) {
                if let itemPendingArchive {
                    MealPrepService.archive(itemPendingArchive, context: modelContext)
                }
                itemPendingArchive = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingArchive = nil
            }
        } message: {
            Text("Archived meal prep is hidden from active food planning.")
        }
    }

    private var groupedLocations: [InventoryLocation] {
        locations.filter { [.freezer, .fridge, .garageFreezer, .pantry].contains($0.locationType) }
    }

    private var filteredItems: [MealPrepItem] {
        mealPrepItems
            .filter { !$0.isArchived }
            .filter {
                searchText.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(searchText)
                    || ($0.tagsJSON?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            .sorted { $0.servingsRemaining > $1.servingsRemaining }
    }
}

private struct MealPrepCard: View {
    @Bindable var item: MealPrepItem
    let location: InventoryLocation?
    let useOne: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(item.servingsText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.servingsRemaining <= 2 ? .orange : .primary)
                HStack(spacing: 8) {
                    if let location {
                        Label(location.name, systemImage: location.locationType.systemImage)
                    }
                    if let prepared = item.preparedDate {
                        Text(DateFormatting.day.string(from: prepared))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let tags = item.tagsJSON, !tags.isEmpty {
                    Text(tags)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Use 1", action: useOne)
                .buttonStyle(.borderedProminent)
                .disabled(item.servingsRemaining <= 0)
        }
        .padding(.vertical, 5)
    }
}

private struct MealPrepDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: MealPrepItem
    let locations: [InventoryLocation]
    let usages: [MealPrepUsage]

    @State private var showingEditor = false
    @State private var showingUseSheet = false
    @State private var showingFinishPrompt = false
    @State private var showingArchiveConfirmation = false

    var body: some View {
        List {
            Section {
                MealPrepCard(
                    item: item,
                    location: locations.first { $0.id == item.locationID },
                    useOne: { use(servings: 1, notes: "") }
                )
            }
            Section("Actions") {
                Button("Use Servings", systemImage: "minus.circle") {
                    showingUseSheet = true
                }
                Button("Archive", systemImage: "archivebox", role: .destructive) {
                    showingArchiveConfirmation = true
                }
            }
            if !usages.isEmpty {
                Section("Usage History") {
                    ForEach(usages) { usage in
                        LabeledContent(DateFormatting.day.string(from: usage.dateTime)) {
                            Text("\(formatted(usage.servingsUsed)) used")
                        }
                    }
                }
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            MealPrepEditorView(
                household: nil,
                item: item,
                locations: locations
            )
        }
        .sheet(isPresented: $showingUseSheet) {
            UseMealPrepView(item: item) { servings, notes in
                use(servings: servings, notes: notes)
            }
        }
        .confirmationDialog("Mark finished?", isPresented: $showingFinishPrompt) {
            Button("Archive Finished Item") {
                MealPrepService.archiveIfFinished(item, context: modelContext)
                dismiss()
            }
            Button("Keep Visible", role: .cancel) {}
        }
        .confirmationDialog(
            "Archive \(item.name)?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Item", role: .destructive) {
                MealPrepService.archive(item, context: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived meal prep is hidden from active food planning.")
        }
    }

    private func use(servings: Double, notes: String) {
        MealPrepService.use(item, servings: servings, notes: notes, context: modelContext)
        if item.servingsRemaining <= 0 {
            showingFinishPrompt = true
        }
    }
}

private struct MealPrepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household?
    let item: MealPrepItem?
    let locations: [InventoryLocation]

    @State private var name = ""
    @State private var servingsTotal: Double?
    @State private var servingsRemaining = 1.0
    @State private var servingUnit: MealPrepServingUnit = .serving
    @State private var locationID: UUID?
    @State private var preparedDate = Date()
    @State private var hasPreparedDate = false
    @State private var notes = ""
    @State private var tags = ""
    @State private var showingLocationEditor = false

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Name") {
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Total quantity") {
                    TextField("Optional", value: $servingsTotal, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Quantity remaining") {
                    TextField("Required", value: $servingsRemaining, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Unit", selection: $servingUnit) {
                    ForEach(MealPrepServingUnit.allCases) { unit in
                        Text(unit.singularName.capitalized).tag(unit)
                    }
                }
                Picker("Location", selection: $locationID) {
                    Text("Select Location").tag(UUID?.none)
                    ForEach(locations) { location in
                        Text(location.name).tag(UUID?.some(location.id))
                    }
                }
                if locationHouseholdID != nil {
                    Button("Add Location", systemImage: "plus") {
                        showingLocationEditor = true
                    }
                }
                Toggle("Prepared date", isOn: $hasPreparedDate)
                if hasPreparedDate {
                    DatePicker("Prepared", selection: $preparedDate, displayedComponents: .date)
                }
                TextField("Tags", text: $tags)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle(item == nil ? "Add Meal Prep" : "Edit Meal Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveItem() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                name = item?.name ?? ""
                servingsTotal = item?.servingsTotal
                servingsRemaining = item?.servingsRemaining ?? 1
                servingUnit = item?.servingUnit ?? .serving
                locationID = item?.locationID ?? locations.first?.id
                preparedDate = item?.preparedDate ?? Date()
                hasPreparedDate = item?.preparedDate != nil
                notes = item?.notes ?? ""
                tags = item?.tagsJSON ?? ""
            }
            .sheet(isPresented: $showingLocationEditor) {
                if let householdID = locationHouseholdID {
                    InventoryLocationEditorView(
                        householdID: householdID,
                        location: nil,
                        locations: locations,
                        onSave: { locationID = $0 }
                    )
                }
            }
        }
    }

    private func saveItem() {
        guard let locationID else { return }
        if let item {
            MealPrepService.updateMealPrepItem(
                item,
                name: name,
                servingsTotal: servingsTotal,
                servingsRemaining: servingsRemaining,
                servingUnit: servingUnit,
                locationID: locationID,
                preparedDate: hasPreparedDate ? preparedDate : nil,
                notes: notes,
                tags: tags,
                context: modelContext
            )
        } else if let household {
            MealPrepService.createMealPrepItem(
                name: name,
                servingsTotal: servingsTotal,
                servingsRemaining: servingsRemaining,
                servingUnit: servingUnit,
                locationID: locationID,
                householdID: household.id,
                preparedDate: hasPreparedDate ? preparedDate : nil,
                notes: notes,
                tags: tags,
                context: modelContext
            )
        }
        dismiss()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && servingsRemaining >= 0
            && (servingsTotal == nil || (servingsTotal ?? 0) >= 0)
            && locationID != nil
    }

    private var locationHouseholdID: UUID? {
        household?.id ?? item?.householdID
    }
}

private struct UseMealPrepView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: MealPrepItem
    let onUse: (Double, String) -> Void
    @State private var servings = 1.0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $servings, in: 0.5...max(0.5, item.servingsRemaining), step: 0.5) {
                    Text("\(formatted(servings)) \(item.servingUnit.displayName(count: servings))")
                }
                TextField("Note", text: $notes, axis: .vertical)
            }
            .navigationTitle("Use \(item.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse(servings, notes)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StoresView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let stores: [FoodStore]
    let sections: [FoodStoreSection]
    let openStore: (FoodStore) -> Void

    @State private var showingNewStore = false
    @State private var storePendingArchive: FoodStore?
    @State private var showingArchiveConfirmation = false

    var body: some View {
        let sectionCountByStoreID = Dictionary(grouping: sections, by: \.storeID).mapValues(\.count)

        List {
            Section("Stores") {
                if stores.isEmpty {
                    ContentUnavailableView(
                        "No stores",
                        systemImage: "map",
                        description: Text("Add a store to organize aisles, sections, and store-specific shopping lists.")
                    )
                } else {
                    ForEach(stores) { store in
                        Button {
                            openStore(store)
                        } label: {
                            LabeledContent {
                                Text("\(sectionCountByStoreID[store.id, default: 0]) sections")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(store.name, systemImage: "map.fill")
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Archive", role: .destructive) {
                                storePendingArchive = store
                                showingArchiveConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewStore = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add store")
            }
        }
        .sheet(isPresented: $showingNewStore) {
            StoreCreateView(household: household) { _ in }
        }
        .confirmationDialog(
            "Archive store?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Store", role: .destructive) {
                if let storePendingArchive {
                    StoreLayoutService.archiveStore(storePendingArchive, context: modelContext)
                }
                storePendingArchive = nil
            }
            Button("Cancel", role: .cancel) {
                storePendingArchive = nil
            }
        } message: {
            Text("Archived stores are removed from active store lists and section pickers.")
        }
    }
}

private struct StoreCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let onCreated: (FoodStore) -> Void

    @State private var name = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Store name", text: $name)
                        .accessibilityIdentifier("store.name")
                } footer: {
                    Text("Common sections are added automatically. You can rename or reorder them from Stores later.")
                }
            }
            .navigationTitle("New Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let store = StoreLayoutService.createStore(
                            name: name,
                            householdID: household.id,
                            context: modelContext
                        ) else { return }
                        onCreated(store)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("store.save")
                }
            }
        }
    }
}

private struct StoreEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FoodStore
    let sections: [FoodStoreSection]
    let shoppingItems: [ShoppingListItem]
    private let itemCountBySectionID: [UUID: Int]
    @State private var nameDraft: String
    @State private var notesDraft: String
    @State private var newSectionName = ""
    @State private var sectionPendingRemoval: FoodStoreSection?
    @State private var showingArchiveConfirmation = false
    @State private var pendingSave: Task<Void, Never>?

    init(store: FoodStore, sections: [FoodStoreSection], shoppingItems: [ShoppingListItem]) {
        self.store = store
        self.sections = sections
        self.shoppingItems = shoppingItems
        itemCountBySectionID = shoppingItems.reduce(into: [UUID: Int]()) { counts, item in
            if let sectionID = item.storeSectionID {
                counts[sectionID, default: 0] += 1
            }
        }
        _nameDraft = State(initialValue: store.name)
        _notesDraft = State(initialValue: store.notes ?? "")
    }

    var body: some View {
        let orderedSections = sections.sorted {
            ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name)
        }

        Form {
            Section("Store") {
                TextField("Name", text: $nameDraft)
                    .onChange(of: nameDraft) { _, _ in scheduleSave() }
                TextField("Notes", text: $notesDraft, axis: .vertical)
                    .onChange(of: notesDraft) { _, _ in scheduleSave() }
            }

            Section {
                HStack {
                    TextField("Section name", text: $newSectionName)
                        .submitLabel(.done)
                        .onSubmit(addSection)
                        .accessibilityIdentifier("store.add-section.name")
                    Button("Add") {
                        addSection()
                    }
                    .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("store.add-section")
                }
            } header: {
                Text("Add Section")
            }

            Section {
                if orderedSections.isEmpty {
                    ContentUnavailableView(
                        "No sections",
                        systemImage: "square.grid.2x2",
                        description: Text("Add the first aisle or area for this store.")
                    )
                } else {
                    ForEach(orderedSections) { section in
                        StoreSectionEditorView(
                            section: section,
                            itemCount: itemCountBySectionID[section.id, default: 0],
                            remove: { sectionPendingRemoval = section }
                        )
                    }
                    .onMove(perform: moveSections)
                }
            } header: {
                Text("Aisle Order")
            } footer: {
                Text("Tap a name to rename it. Tap Edit to drag sections into order. Any section, including a default, can be removed; its items move to Other.")
            }

            Section {
                Button("Archive Store", role: .destructive) {
                    showingArchiveConfirmation = true
                }
            }
        }
        .navigationTitle(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Store" : nameDraft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if sections.count > 1 {
                    EditButton()
                }
            }
        }
        .onDisappear(perform: saveNow)
        .onChange(of: store.id) { _, _ in syncDraftsFromStore() }
        .alert(
            sectionPendingRemoval.map { "Remove \($0.name)?" } ?? "Remove section?",
            isPresented: Binding(
                get: { sectionPendingRemoval != nil },
                set: { if !$0 { sectionPendingRemoval = nil } }
            )
        ) {
            Button("Remove Section", role: .destructive) {
                if let sectionPendingRemoval {
                    StoreLayoutService.deleteSection(
                        sectionPendingRemoval,
                        from: store,
                        shoppingItems: shoppingItems,
                        remainingSections: sections,
                        context: modelContext
                    )
                }
                sectionPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                sectionPendingRemoval = nil
            }
        } message: {
            Text(sectionRemovalMessage)
        }
        .confirmationDialog(
            "Archive \(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? store.name : nameDraft)?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Store", role: .destructive) {
                StoreLayoutService.archiveStore(store, context: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived stores are removed from active store lists and section pickers.")
        }
    }

    private var orderedSections: [FoodStoreSection] {
        sections.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var sectionRemovalMessage: String {
        guard let sectionPendingRemoval else { return "" }
        let itemCount = itemCountBySectionID[sectionPendingRemoval.id, default: 0]
        guard itemCount > 0 else {
            return "This removes the section from this store."
        }
        return "\(itemCount) item\(itemCount == 1 ? "" : "s") currently use this section. They will move to Other."
    }

    private func addSection() {
        guard StoreLayoutService.createSection(
            name: newSectionName,
            store: store,
            existingSections: sections,
            context: modelContext
        ) != nil else { return }
        newSectionName = ""
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        var reordered = orderedSections
        reordered.move(fromOffsets: source, toOffset: destination)
        StoreLayoutService.reorderSections(
            reordered,
            in: store,
            context: modelContext
        )
    }

    private func syncDraftsFromStore() {
        pendingSave?.cancel()
        nameDraft = store.name
        notesDraft = store.notes ?? ""
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            persistDrafts()
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        persistDrafts()
    }

    private func persistDrafts() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        guard !name.isEmpty else { return }
        guard store.name != name || store.notes != notes else { return }
        store.name = name
        store.notes = notes
        store.updatedAt = Date()
        save(modelContext)
    }
}

private struct StoreSectionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: FoodStoreSection
    let itemCount: Int
    let remove: () -> Void
    @State private var nameDraft: String
    @State private var pendingSave: Task<Void, Never>?

    init(section: FoodStoreSection, itemCount: Int, remove: @escaping () -> Void) {
        self.section = section
        self.itemCount = itemCount
        self.remove = remove
        _nameDraft = State(initialValue: section.name)
    }

    var body: some View {
        HStack {
            TextField("Section", text: $nameDraft)
            Spacer()
            Text(itemCount == 1 ? "1 item" : "\(itemCount) items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(section.name)")
        }
        .onChange(of: nameDraft) { _, _ in schedulePersist() }
        .onChange(of: section.id) { _, _ in syncDraftFromSection() }
        .onDisappear(perform: persistNow)
    }

    private func syncDraftFromSection() {
        pendingSave?.cancel()
        nameDraft = section.name
    }

    private func schedulePersist() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            persistDraft()
        }
    }

    private func persistNow() {
        pendingSave?.cancel()
        persistDraft()
    }

    private func persistDraft() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, section.name != name else { return }
        section.name = name
        section.updatedAt = Date()
        save(modelContext)
    }
}

private struct FoodInsightsView: View {
    let household: Household
    let todoLists: [HomeTodoList]
    let todoItems: [HomeTodoItem]
    let returnRequests: [ReturnRequest]
    let returnItems: [ReturnItem]
    let returnPackages: [ReturnPackage]
    let locations: [InventoryLocation]
    let inventoryItems: [InventoryItem]
    let mealPrepItems: [MealPrepItem]
    let packingTrips: [PackingTrip]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let mealPrepUsages: [MealPrepUsage]

    var body: some View {
        let availableInventoryCountByLocationID = inventoryItems.reduce(into: [UUID: Int]()) { counts, item in
            if item.status == .available {
                counts[item.locationID, default: 0] += 1
            }
        }
        let activeMealPrepItems = mealPrepItems.filter { !$0.isArchived }
        let todoItemsByListID = Dictionary(grouping: todoItems, by: \.todoListID)
        let returnItemsByRequestID = Dictionary(grouping: returnItems, by: \.returnRequestID)
        let returnPackagesByRequestID = Dictionary(grouping: returnPackages, by: \.returnRequestID)
        let returnStatusesByRequestID = Dictionary(uniqueKeysWithValues: returnRequests.map { request in
            (
                request.id,
                ReturnTrackingService.status(for: request, packages: returnPackagesByRequestID[request.id] ?? [])
            )
        })
        let activeReturnRequests = returnRequests.filter {
            returnStatusesByRequestID[$0.id] != .completed
        }
        let visibleTodoLists = Array(todoLists.prefix(12))
        let hiddenTodoListCount = max(0, todoLists.count - visibleTodoLists.count)
        let visibleReturnRequests = Array(activeReturnRequests.prefix(12))
        let hiddenReturnCount = max(0, activeReturnRequests.count - visibleReturnRequests.count)
        let metrics = FoodInsightsService.metrics(
            householdID: household.id,
            locations: locations,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems,
            packingTrips: packingTrips,
            shoppingLists: shoppingLists,
            shoppingItems: shoppingItems,
            todoLists: todoLists,
            todoItems: todoItems,
            returnRequests: returnRequests,
            returnPackages: returnPackages,
            returnStatusesByRequestID: returnStatusesByRequestID
        )

        List {
            Section("Overview") {
                ForEach(metrics) { metric in
                    Label {
                        LabeledContent {
                            Text(metric.value)
                                .font(.headline)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.title)
                                Text(metric.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: metric.systemImage)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("To-Do Lists") {
                if todoLists.isEmpty {
                    Text("No lists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleTodoLists) { list in
                        let listItems = todoItemsByListID[list.id] ?? []
                        let openCount = listItems.filter { !$0.isCompleted }.count
                        let completedCount = listItems.filter(\.isCompleted).count
                        LabeledContent(list.name) {
                            Text(todoListSummary(openCount: openCount, completedCount: completedCount))
                        }
                    }
                    if hiddenTodoListCount > 0 {
                        Text(itemCountText(hiddenTodoListCount, singular: "more list", plural: "more lists"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Returns") {
                if returnRequests.isEmpty {
                    Text("No returns yet")
                        .foregroundStyle(.secondary)
                } else if activeReturnRequests.isEmpty {
                    Text("No active returns")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleReturnRequests) { request in
                        let items = returnItemsByRequestID[request.id] ?? []
                        let packages = returnPackagesByRequestID[request.id] ?? []
                        LabeledContent(returnInsightsTitle(for: request, items: items, packages: packages)) {
                            Text((returnStatusesByRequestID[request.id] ?? .needsAction).displayName)
                        }
                    }
                    if hiddenReturnCount > 0 {
                        Text(itemCountText(hiddenReturnCount, singular: "more active return", plural: "more active returns"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Kitchen Inventory by Location") {
                if locations.isEmpty {
                    Text("No inventory locations yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locations) { location in
                        LabeledContent(location.name) {
                            Text("\(availableInventoryCountByLocationID[location.id, default: 0])")
                        }
                    }
                }
            }
            Section("Meal Prep Servings") {
                if activeMealPrepItems.isEmpty {
                    Text("No active meal prep items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMealPrepItems) { item in
                        LabeledContent(item.name) {
                            Text(item.servingsText)
                        }
                    }
                }
            }
            Section("Shopping List Usage") {
                if shoppingLists.isEmpty {
                    Text("No shopping lists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shoppingLists) { list in
                        LabeledContent(list.name) {
                            Text(list.lastUsedAt == nil ? "No trips" : "Used")
                        }
                    }
                }
            }
            Section("Meal Prep Usage") {
                if mealPrepUsages.isEmpty {
                    Text("No usage yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mealPrepUsages.prefix(12)) { usage in
                        LabeledContent(DateFormatting.day.string(from: usage.dateTime)) {
                            Text("\(formatted(usage.servingsUsed)) servings")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }

    private func todoListSummary(openCount: Int, completedCount: Int) -> String {
        "\(itemCountText(openCount, singular: "open item", plural: "open items")), \(itemCountText(completedCount, singular: "done", plural: "done"))"
    }

    private func itemCountText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func returnInsightsTitle(for request: ReturnRequest, items: [ReturnItem], packages: [ReturnPackage]) -> String {
        if let item = items.first {
            return item.name
        }
        if let package = packages.first {
            return package.displayName
        }
        return DateFormatting.day.string(from: request.createdAt)
    }
}

private struct ReturnsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let requests: [ReturnRequest]
    let items: [ReturnItem]
    let packages: [ReturnPackage]
    let photoAttachments: [PhotoAttachment]
    let openReturn: (ReturnRequest) -> Void

    @State private var showingNewReturn = false
    @State private var returnPendingRemove: ReturnRequest?

    var body: some View {
        let itemsByReturnID = Dictionary(grouping: items, by: \.returnRequestID)
        let packagesByReturnID = Dictionary(grouping: packages, by: \.returnRequestID)
        let statusByReturnID = Dictionary(uniqueKeysWithValues: requests.map { request in
            (
                request.id,
                ReturnTrackingService.status(for: request, packages: packagesByReturnID[request.id] ?? [])
            )
        })
        let activeRequests = requests.filter {
            statusByReturnID[$0.id] != .completed
        }
        let completedRequests = requests.filter {
            statusByReturnID[$0.id] == .completed
        }
        let activeGroups = groupedRequests(
            activeRequests,
            itemsByReturnID: itemsByReturnID,
            packagesByReturnID: packagesByReturnID
        )

        List {
            if requests.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No returns",
                        systemImage: "shippingbox",
                        description: Text("Create a return request with its items, send-back details, photos, and drop-offs.")
                    )
                }
            } else {
                ForEach(activeGroups) { group in
                    Section {
                        ForEach(group.requests) { request in
                            Button {
                                openReturn(request)
                            } label: {
                                ReturnSummaryRow(
                                    status: statusByReturnID[request.id] ?? .needsAction,
                                    items: itemsByReturnID[request.id] ?? [],
                                    packages: packagesByReturnID[request.id] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    returnPendingRemove = request
                                }
                            }
                        }
                    } header: {
                        AppSectionHeader(title: group.title, subtitle: "\(group.requests.count)")
                    }
                }

                if !completedRequests.isEmpty {
                    Section {
                        ForEach(completedRequests) { request in
                            Button {
                                openReturn(request)
                            } label: {
                                ReturnSummaryRow(
                                    status: statusByReturnID[request.id] ?? .completed,
                                    items: itemsByReturnID[request.id] ?? [],
                                    packages: packagesByReturnID[request.id] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    returnPendingRemove = request
                                }
                            }
                        }
                    } header: {
                        AppSectionHeader(title: "Completed", subtitle: "\(completedRequests.count)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewReturn = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add return")
            }
        }
        .sheet(isPresented: $showingNewReturn) {
            NavigationStack {
                ReturnCreateView(
                    household: household,
                    sortOrder: nextReturnSortOrder
                )
            }
        }
        .appActionSheet(
            isPresented: Binding(
                get: { returnPendingRemove != nil },
                set: { if !$0 { returnPendingRemove = nil } }
            ),
            title: "Remove return?",
            message: returnPendingRemove.map { removeMessage(for: $0, itemsByReturnID: itemsByReturnID, packagesByReturnID: packagesByReturnID) },
            systemImage: "archivebox.fill",
            tint: .red,
            options: removeOptions
        )
    }

    private var nextReturnSortOrder: Int {
        (requests.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
    }

    private var removeOptions: [AppActionSheetOption] {
        guard let request = returnPendingRemove else { return [] }
        return [
            AppActionSheetOption(
                title: "Remove Return",
                subtitle: "Remove its items, send-back details, and attached photos.",
                systemImage: "archivebox.fill",
                tint: .red,
                role: .destructive
            ) {
                remove(request)
                returnPendingRemove = nil
            }
        ]
    }

    private func remove(_ request: ReturnRequest) {
        ReturnTrackingService.archive(
            request,
            items: items,
            packages: packages,
            attachments: photoAttachments,
            context: modelContext
        )
    }

    private func removeMessage(
        for request: ReturnRequest,
        itemsByReturnID: [UUID: [ReturnItem]],
        packagesByReturnID: [UUID: [ReturnPackage]]
    ) -> String {
        let itemCount = itemsByReturnID[request.id]?.count ?? 0
        let packageCount = packagesByReturnID[request.id]?.count ?? 0
        return "This removes \(itemCount) item\(itemCount == 1 ? "" : "s"), \(packageCount) send-back detail\(packageCount == 1 ? "" : "s"), and any attached return label photos from active tracking."
    }

    private func groupedRequests(
        _ requests: [ReturnRequest],
        itemsByReturnID: [UUID: [ReturnItem]],
        packagesByReturnID: [UUID: [ReturnPackage]]
    ) -> [ReturnDropOffGroup] {
        let grouped = Dictionary(grouping: requests) { request in
            dropOffGroupKey(for: request, packagesByReturnID: packagesByReturnID)
        }
        return grouped.map { key, requests in
            ReturnDropOffGroup(
                key: key,
                title: key.title,
                requests: requests.sorted {
                    sortRequests(
                        $0,
                        $1,
                        itemsByReturnID: itemsByReturnID,
                        packagesByReturnID: packagesByReturnID
                    )
                }
            )
        }
        .sorted { lhs, rhs in
            (lhs.key.sortOrder, lhs.title) < (rhs.key.sortOrder, rhs.title)
        }
    }

    private func dropOffGroupKey(
        for request: ReturnRequest,
        packagesByReturnID: [UUID: [ReturnPackage]]
    ) -> ReturnDropOffGroupKey {
        let requestPackages = packagesByReturnID[request.id] ?? []
        guard !requestPackages.isEmpty else { return .needsLabel }
        let carriers = Set(requestPackages.map(\.carrier))
        guard carriers.count == 1, let carrier = carriers.first else { return .multiple }
        return .carrier(carrier)
    }

    private func sortRequests(
        _ lhs: ReturnRequest,
        _ rhs: ReturnRequest,
        itemsByReturnID: [UUID: [ReturnItem]],
        packagesByReturnID: [UUID: [ReturnPackage]]
    ) -> Bool {
        let lhsItems = itemsByReturnID[lhs.id] ?? []
        let rhsItems = itemsByReturnID[rhs.id] ?? []
        let lhsPackages = packagesByReturnID[lhs.id] ?? []
        let rhsPackages = packagesByReturnID[rhs.id] ?? []
        return (
            earliestReturnByDate(in: lhsPackages) ?? .distantFuture,
            returnDisplayTitle(items: lhsItems, packages: lhsPackages)
        ) < (
            earliestReturnByDate(in: rhsPackages) ?? .distantFuture,
            returnDisplayTitle(items: rhsItems, packages: rhsPackages)
        )
    }

    private func earliestReturnByDate(in packages: [ReturnPackage]) -> Date? {
        packages.compactMap(\.returnByDate).min()
    }

    private func returnDisplayTitle(items: [ReturnItem], packages: [ReturnPackage]) -> String {
        if let firstItem = items.sorted(by: { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }).first {
            return items.count == 1 ? firstItem.name : "\(firstItem.name) + \(items.count - 1)"
        }
        if let firstPackage = packages.sorted(by: { ($0.sortOrder ?? 0, $0.displayName) < ($1.sortOrder ?? 0, $1.displayName) }).first {
            return "Return at \(firstPackage.displayName)"
        }
        return "Return"
    }
}

private struct ReturnDropOffGroup: Identifiable {
    let key: ReturnDropOffGroupKey
    let title: String
    let requests: [ReturnRequest]

    var id: String { key.id }
}

private enum ReturnDropOffGroupKey: Hashable {
    case needsLabel
    case carrier(ReturnPackageCarrier)
    case multiple

    var id: String {
        switch self {
        case .needsLabel: "needs-label"
        case .carrier(let carrier): carrier.rawValue
        case .multiple: "multiple"
        }
    }

    var title: String {
        switch self {
        case .needsLabel: "Needs Details"
        case .carrier(let carrier): carrier.displayName
        case .multiple: "Multiple Drop-offs"
        }
    }

    var sortOrder: Int {
        switch self {
        case .needsLabel:
            0
        case .carrier(let carrier):
            (ReturnPackageCarrier.allCases.firstIndex(of: carrier) ?? 99) + 1
        case .multiple:
            100
        }
    }
}

private struct ReturnSummaryRow: View {
    let status: ReturnRequestStatus
    let items: [ReturnItem]
    let packages: [ReturnPackage]

    private var title: String {
        if let firstItem = items.sorted(by: { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }).first {
            return items.count == 1 ? firstItem.name : "\(firstItem.name) + \(items.count - 1)"
        }
        if let firstPackage = packages.sorted(by: { ($0.sortOrder ?? 0, $0.displayName) < ($1.sortOrder ?? 0, $1.displayName) }).first {
            return "Return at \(firstPackage.displayName)"
        }
        return "Return"
    }

    private var earliestReturnByDate: Date? {
        packages.compactMap(\.returnByDate).min()
    }

    private var dropOffSummary: String {
        guard !packages.isEmpty else { return "No drop-off set" }
        let carriers = Array(Set(packages.map(\.carrier)))
            .sorted { lhs, rhs in
                (ReturnPackageCarrier.allCases.firstIndex(of: lhs) ?? 99)
                    < (ReturnPackageCarrier.allCases.firstIndex(of: rhs) ?? 99)
            }
        if carriers.count == 1, let carrier = carriers.first {
            return carrier.displayName
        }
        return carriers.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSystemImage(status))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(statusColor(status).gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(status.displayName)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    Text("\(packages.count) send-back detail\(packages.count == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Label(dropOffSummary, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let returnByDate = earliestReturnByDate {
                    Text("Return by \(DateFormatting.day.string(from: returnByDate))")
                        .font(.caption)
                        .foregroundStyle(returnByDate < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct ReturnDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var request: ReturnRequest
    let items: [ReturnItem]
    let packages: [ReturnPackage]
    let photoAttachments: [PhotoAttachment]

    @State private var showingAddItem = false
    @State private var editingItem: ReturnItem?
    @State private var itemPendingDelete: ReturnItem?
    @State private var showingAddPackage = false
    @State private var editingPackage: ReturnPackage?
    @State private var packagePendingDelete: ReturnPackage?
    @State private var showingRemoveReturnConfirmation = false
    @State private var showingDeleteItemConfirmation = false
    @State private var showingDeletePackageConfirmation = false

    private var status: ReturnRequestStatus {
        ReturnTrackingService.status(for: request, packages: packages)
    }

    private var title: String {
        if let firstItem = items.sorted(by: { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }).first {
            return items.count == 1 ? firstItem.name : "\(firstItem.name) + \(items.count - 1)"
        }
        if let firstPackage = packages.sorted(by: { ($0.sortOrder ?? 0, $0.displayName) < ($1.sortOrder ?? 0, $1.displayName) }).first {
            return "Return at \(firstPackage.displayName)"
        }
        return "Return"
    }

    var body: some View {
        List {
            Section {
                Label {
                    LabeledContent("Status") {
                        Text(status.displayName)
                            .foregroundStyle(statusColor(status))
                    }
                } icon: {
                    Image(systemName: statusSystemImage(status))
                        .foregroundStyle(statusColor(status))
                }
            } header: {
                AppSectionHeader(title: "Progress")
            }

            Section {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No items",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add each item that belongs to this return.")
                    )
                } else {
                    ForEach(items.sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                editingItem = item
                            } label: {
                                ReturnItemRow(
                                    item: item,
                                    package: packages.first { $0.id == item.packageID }
                                )
                            }
                            .buttonStyle(.plain)
                            if let urlString = item.returnURLString,
                               let url = URL(string: urlString) {
                                Link(destination: url) {
                                    Label("Open return link", systemImage: "link")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                itemPendingDelete = item
                                showingDeleteItemConfirmation = true
                            }
                        }
                    }
                }
            } header: {
                AppSectionHeader(title: "Items", subtitle: "\(items.count)")
            }

            Section {
                if packages.isEmpty {
                    ContentUnavailableView(
                        "No send-back details",
                        systemImage: "shippingbox",
                        description: Text("Add the drop-off partner, barcode, return label, or tracking details.")
                    )
                } else {
                    ForEach(packages.sorted { ($0.sortOrder ?? 0, $0.displayName) < ($1.sortOrder ?? 0, $1.displayName) }) { package in
                        ReturnPackageCard(
                            package: package,
                            items: items.filter { $0.packageID == package.id },
                            photoAttachments: photoAttachments,
                            edit: { editingPackage = package }
                        )
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                packagePendingDelete = package
                                showingDeletePackageConfirmation = true
                            }
                        }
                    }
                }
            } header: {
                AppSectionHeader(title: "Send-Back Details", subtitle: "\(packages.count)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Add Item", systemImage: "list.bullet.rectangle") {
                        showingAddItem = true
                    }
                    Button("Add Send-Back Details", systemImage: "shippingbox") {
                        showingAddPackage = true
                    }
                    Button("Remove Return", systemImage: "archivebox", role: .destructive) {
                        showingRemoveReturnConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            NavigationStack {
                ReturnItemEditorView(
                    request: request,
                    item: nil,
                    packages: packages,
                    existingItems: items
                )
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                ReturnItemEditorView(
                    request: request,
                    item: item,
                    packages: packages,
                    existingItems: items
                )
            }
        }
        .sheet(isPresented: $showingAddPackage) {
            NavigationStack {
                ReturnPackageEditorView(
                    request: request,
                    package: nil,
                    existingPackages: packages,
                    photoAttachments: photoAttachments
                )
            }
        }
        .sheet(item: $editingPackage) { package in
            NavigationStack {
                ReturnPackageEditorView(
                    request: request,
                    package: package,
                    existingPackages: packages,
                    photoAttachments: photoAttachments
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if status != .completed {
                ReturnDetailActionBar(
                    canMarkDroppedOff: canMarkDroppedOff,
                    canMarkInProgress: canMarkInProgress,
                    markDroppedOff: {
                        ReturnTrackingService.markDroppedOff(
                            request,
                            packages: packages,
                            context: modelContext
                        )
                    },
                    markInProgress: {
                        ReturnTrackingService.markInProgress(
                            request,
                            packages: packages,
                            context: modelContext
                        )
                    },
                    markComplete: {
                        ReturnTrackingService.markComplete(
                            request,
                            packages: packages,
                            context: modelContext
                        )
                    }
                )
            }
        }
        .appActionSheet(
            isPresented: $showingRemoveReturnConfirmation,
            title: "Remove return?",
            message: "This removes the return, its items, send-back details, and attached return label photos from active tracking.",
            systemImage: "archivebox.fill",
            tint: .red,
            options: removeReturnOptions
        )
        .confirmationDialog(
            "Delete return item?",
            isPresented: $showingDeleteItemConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Item", role: .destructive) {
                if let itemPendingDelete {
                    ReturnTrackingService.deleteItem(
                        itemPendingDelete,
                        from: request,
                        items: items,
                        packages: packages,
                        attachments: photoAttachments,
                        context: modelContext
                    )
                    if items.filter({ $0.returnRequestID == request.id && $0.id != itemPendingDelete.id }).isEmpty {
                        dismiss()
                    }
                }
                itemPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text("This removes the item from this return.")
        }
        .confirmationDialog(
            "Delete send-back details?",
            isPresented: $showingDeletePackageConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Details", role: .destructive) {
                if let packagePendingDelete {
                    ReturnTrackingService.deletePackage(
                        packagePendingDelete,
                        items: items,
                        attachments: photoAttachments,
                        context: modelContext
                    )
                }
                packagePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                packagePendingDelete = nil
            }
        } message: {
            Text("Items assigned to these send-back details will become unassigned, and attached photos will be removed.")
        }
    }

    private var removeReturnOptions: [AppActionSheetOption] {
        [
            AppActionSheetOption(
                title: "Remove Return",
                subtitle: "Remove its items, send-back details, and attached photos.",
                systemImage: "archivebox.fill",
                tint: .red,
                role: .destructive
            ) {
                ReturnTrackingService.archive(
                    request,
                    items: items,
                    packages: packages,
                    attachments: photoAttachments,
                    context: modelContext
                )
                dismiss()
            }
        ]
    }

    private var canMarkDroppedOff: Bool {
        packages.contains { $0.completedAt == nil && $0.droppedOffAt == nil }
    }

    private var canMarkInProgress: Bool {
        packages.contains { $0.completedAt == nil && $0.droppedOffAt != nil }
    }
}

private struct ReturnItemRow: View {
    let item: ReturnItem
    let package: ReturnPackage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !item.quantityText.isEmpty {
                    Text("Qty \(item.quantityText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let reason = item.reason {
                    Text(reason)
                }
                if let package {
                    Label(package.displayName, systemImage: "shippingbox")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ReturnDetailActionBar: View {
    let canMarkDroppedOff: Bool
    let canMarkInProgress: Bool
    let markDroppedOff: () -> Void
    let markInProgress: () -> Void
    let markComplete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if canMarkDroppedOff || canMarkInProgress {
                HStack(spacing: 10) {
                    if canMarkInProgress {
                        Button(action: markInProgress) {
                            Label("In Progress", systemImage: "arrow.uturn.backward.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if canMarkDroppedOff {
                        Button(action: markDroppedOff) {
                            Label("Dropped Off", systemImage: "tray.and.arrow.up.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Button(action: markComplete) {
                Label("Complete Return", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .foregroundStyle(.white)
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

private struct ReturnPackageCard: View {
    let package: ReturnPackage
    let items: [ReturnItem]
    let photoAttachments: [PhotoAttachment]
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: package.completedAt == nil ? "shippingbox.fill" : "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(package.completedAt == nil ? Color.orange.gradient : Color.green.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(package.displayName)
                        .font(.headline)
                    Text(packageSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: edit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit package")
            }

            if let trackingNumber = package.trackingNumber {
                LabeledContent("Tracking") { Text(trackingNumber) }
                    .font(.caption)
            }
            if let returnByDate = package.returnByDate {
                LabeledContent("Return by") { Text(DateFormatting.day.string(from: returnByDate)) }
                    .font(.caption)
                    .foregroundStyle(returnByDate < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
            }
            if !items.isEmpty {
                Text(items.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let photos = package.photoAttachmentIDs.compactMap { id -> (UUID, Data)? in
                guard let data = photoAttachments.first(where: { $0.id == id })?.previewData else {
                    return nil
                }
                return (id, data)
            }
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(photos, id: \.0) { attachmentID, data in
                            if let image = ThumbnailImageCache.image(
                                attachmentID: attachmentID,
                                data: data
                            ) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 74, height: 74)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 4)
    }

    private var packageSubtitle: String {
        if let completedAt = package.completedAt {
            return "Completed \(DateFormatting.day.string(from: completedAt))"
        }
        if let droppedOffAt = package.droppedOffAt {
            return "Dropped off \(DateFormatting.day.string(from: droppedOffAt))"
        }
        return "\(package.method.displayName) via \(package.carrier.displayName)"
    }
}

private struct ReturnCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let sortOrder: Int

    @State private var returnURLString = ""
    @State private var hasReturnByDate = false
    @State private var returnByDate = Date()
    @State private var itemName = ""
    @State private var itemQuantity: Double = 1
    @State private var hasItemQuantity = false
    @State private var itemReason = ""
    @State private var packageName = ""
    @State private var carrier: ReturnPackageCarrier = .wholeFoods
    @State private var method: ReturnPackageMethod = .dropOff
    @State private var trackingNumber = ""
    @State private var selectedPhotoItems = [PhotosPickerItem]()
    @State private var photoDrafts = [PhotoAttachmentDraft]()
    @State private var showingPhotoControls = false
    @State private var isImportingPhotos = false

    var body: some View {
        Form {
            Section("What You're Returning") {
                TextField("Item name", text: $itemName)
                Toggle("Quantity", isOn: $hasItemQuantity)
                if hasItemQuantity {
                    Stepper(value: $itemQuantity, in: 1...99, step: 1) {
                        Text("\(Int(itemQuantity))")
                    }
                }
                TextField("Reason", text: $itemReason)
                TextField("Return link", text: $returnURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            Section("How You'll Send It Back") {
                Toggle("Return-by date", isOn: $hasReturnByDate)
                if hasReturnByDate {
                    DatePicker("Date", selection: $returnByDate, displayedComponents: .date)
                }
                Picker("Method", selection: $method) {
                    ForEach(ReturnPackageMethod.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Drop-off partner", selection: $carrier) {
                    ForEach(ReturnPackageCarrier.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                TextField("Reference name", text: $packageName)
                TextField("Tracking number", text: $trackingNumber)
                    .textInputAutocapitalization(.never)
            }

            Section("Barcode or Return Label Photos") {
                if photoDrafts.isEmpty && !showingPhotoControls {
                    Button {
                        showingPhotoControls = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                }
                if !photoDrafts.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(photoDrafts) { draft in
                            ZStack(alignment: .topTrailing) {
                                if let image = ThumbnailImageCache.image(
                                    attachmentID: draft.id,
                                    data: draft.thumbnailData ?? draft.imageData
                                ) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Button {
                                    photoDrafts.removeAll { $0.id == draft.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                            }
                        }
                    }
                }
                if showingPhotoControls || !photoDrafts.isEmpty {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 6,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(isImportingPhotos ? "Importing" : "Add Photos", systemImage: "photo.badge.plus")
                    }
                    .disabled(isImportingPhotos)
                }
            }
        }
        .navigationTitle("New Return")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            importPhotoItems(newItems)
        }
    }

    private var hasExplicitPackageDetails: Bool {
        !packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || carrier != .wholeFoods
            || method != .dropOff
            || !trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasReturnByDate
            || !photoDrafts.isEmpty
    }

    private var canSave: Bool {
        !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasExplicitPackageDetails
    }

    private func importPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            isImportingPhotos = true
            defer {
                isImportingPhotos = false
                selectedPhotoItems = []
            }
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let draft = PhotoAttachmentImageProcessor.draft(from: data)
                else { continue }
                photoDrafts.append(draft)
            }
        }
    }

    private func save() {
        guard canSave else { return }

        for draft in photoDrafts {
            insertReturnPhoto(draft, in: modelContext)
        }

        guard ReturnTrackingService.createReturn(
            householdID: household.id,
            sortOrder: sortOrder,
            itemName: itemName,
            itemQuantity: hasItemQuantity ? itemQuantity : nil,
            itemReason: itemReason,
            returnURLString: returnURLString,
            packageName: packageName,
            carrier: carrier,
            method: method,
            trackingNumber: trackingNumber,
            returnByDate: hasReturnByDate ? returnByDate : nil,
            photoAttachmentIDs: photoDrafts.map(\.id),
            context: modelContext
        ) != nil else { return }

        dismiss()
    }
}

private struct ReturnItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let request: ReturnRequest
    let item: ReturnItem?
    let packages: [ReturnPackage]
    let existingItems: [ReturnItem]

    @State private var name: String
    @State private var quantity: Double
    @State private var hasQuantity: Bool
    @State private var reason: String
    @State private var returnURLString: String
    @State private var packageID: UUID?

    init(request: ReturnRequest, item: ReturnItem?, packages: [ReturnPackage], existingItems: [ReturnItem]) {
        self.request = request
        self.item = item
        self.packages = packages
        self.existingItems = existingItems
        _name = State(initialValue: item?.name ?? "")
        _quantity = State(initialValue: item?.quantity ?? 1)
        _hasQuantity = State(initialValue: item?.quantity != nil)
        _reason = State(initialValue: item?.reason ?? "")
        _returnURLString = State(initialValue: item?.returnURLString ?? "")
        _packageID = State(initialValue: item?.packageID)
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $name)
                Toggle("Quantity", isOn: $hasQuantity)
                if hasQuantity {
                    Stepper(value: $quantity, in: 1...99, step: 1) {
                        Text("\(Int(quantity))")
                    }
                }
                TextField("Reason", text: $reason)
                TextField("Return link", text: $returnURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            Section("Send-Back Details") {
                Picker("Assign to", selection: $packageID) {
                    Text("Unassigned").tag(UUID?.none)
                    ForEach(packages) { package in
                        Text(package.displayName).tag(UUID?.some(package.id))
                    }
                }
            }
        }
        .navigationTitle(item == nil ? "Add Item" : "Edit Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        if let item {
            ReturnTrackingService.updateItem(
                item,
                name: name,
                quantity: hasQuantity ? quantity : nil,
                reason: reason,
                returnURLString: returnURLString,
                packageID: packageID,
                context: modelContext
            )
        } else {
            _ = ReturnTrackingService.addItem(
                name: name,
                quantity: hasQuantity ? quantity : nil,
                reason: reason,
                returnURLString: returnURLString,
                packageID: packageID,
                to: request,
                existingItems: existingItems,
                context: modelContext
            )
        }
        dismiss()
    }
}

private struct ReturnPackageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let request: ReturnRequest
    let package: ReturnPackage?
    let existingPackages: [ReturnPackage]
    let photoAttachments: [PhotoAttachment]

    @State private var name: String
    @State private var carrier: ReturnPackageCarrier
    @State private var method: ReturnPackageMethod
    @State private var trackingNumber: String
    @State private var hasReturnByDate: Bool
    @State private var returnByDate: Date
    @State private var selectedPhotoItems = [PhotosPickerItem]()
    @State private var photoDrafts = [PhotoAttachmentDraft]()
    @State private var keptAttachmentIDs: [UUID]
    @State private var removedAttachmentIDs = Set<UUID>()
    @State private var isImportingPhotos = false

    init(
        request: ReturnRequest,
        package: ReturnPackage?,
        existingPackages: [ReturnPackage],
        photoAttachments: [PhotoAttachment]
    ) {
        self.request = request
        self.package = package
        self.existingPackages = existingPackages
        self.photoAttachments = photoAttachments
        _name = State(initialValue: package?.name ?? "")
        _carrier = State(initialValue: package?.carrier ?? .wholeFoods)
        _method = State(initialValue: package?.method ?? .dropOff)
        _trackingNumber = State(initialValue: package?.trackingNumber ?? "")
        _hasReturnByDate = State(initialValue: package?.returnByDate != nil)
        _returnByDate = State(initialValue: package?.returnByDate ?? Date())
        _keptAttachmentIDs = State(initialValue: package?.photoAttachmentIDs ?? [])
    }

    var body: some View {
        Form {
            Section("How You'll Send It Back") {
                Picker("Method", selection: $method) {
                    ForEach(ReturnPackageMethod.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Drop-off partner", selection: $carrier) {
                    ForEach(ReturnPackageCarrier.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Toggle("Return-by date", isOn: $hasReturnByDate)
                if hasReturnByDate {
                    DatePicker("Date", selection: $returnByDate, displayedComponents: .date)
                }
                TextField("Reference name", text: $name)
                TextField("Tracking number", text: $trackingNumber)
                    .textInputAutocapitalization(.never)
            }

            Section("Barcode or Return Label Photos") {
                if photoPreviewItems.isEmpty {
                    ContentUnavailableView(
                        "No photos",
                        systemImage: "barcode.viewfinder",
                        description: Text("Add a QR code, barcode, label, or receipt photo.")
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(photoPreviewItems) { item in
                            ZStack(alignment: .topTrailing) {
                                if let image = ThumbnailImageCache.image(
                                    attachmentID: item.id,
                                    data: item.data
                                ) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Button {
                                    removePhoto(id: item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                            }
                        }
                    }
                }
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 6,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(isImportingPhotos ? "Importing" : "Add Photos", systemImage: "photo.badge.plus")
                }
                .disabled(isImportingPhotos)
            }
        }
        .navigationTitle(package == nil ? "Add Send-Back Details" : "Edit Send-Back Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            importPhotoItems(newItems)
        }
    }

    private var photoPreviewItems: [ReturnPhotoPreviewItem] {
        let existing = keptAttachmentIDs.compactMap { id -> ReturnPhotoPreviewItem? in
            guard let attachment = photoAttachments.first(where: { $0.id == id }),
                  let data = attachment.previewData else { return nil }
            return ReturnPhotoPreviewItem(id: id, data: data)
        }
        let drafts = photoDrafts.map {
            ReturnPhotoPreviewItem(id: $0.id, data: $0.thumbnailData ?? $0.imageData)
        }
        return existing + drafts
    }

    private func importPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            isImportingPhotos = true
            defer {
                isImportingPhotos = false
                selectedPhotoItems = []
            }
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let draft = PhotoAttachmentImageProcessor.draft(from: data)
                else { continue }
                photoDrafts.append(draft)
            }
        }
    }

    private func removePhoto(id: UUID) {
        if photoDrafts.contains(where: { $0.id == id }) {
            photoDrafts.removeAll { $0.id == id }
        } else {
            keptAttachmentIDs.removeAll { $0 == id }
            removedAttachmentIDs.insert(id)
        }
    }

    private func save() {
        let newAttachmentIDs = photoDrafts.map(\.id)
        for draft in photoDrafts {
            contextInsertPhoto(draft)
        }
        PhotoAttachmentStore.deleteAttachments(
            with: Array(removedAttachmentIDs),
            in: photoAttachments,
            context: modelContext
        )
        let attachmentIDs = keptAttachmentIDs + newAttachmentIDs
        if let package {
            ReturnTrackingService.updatePackage(
                package,
                name: name,
                carrier: carrier,
                method: method,
                trackingNumber: trackingNumber,
                returnByDate: hasReturnByDate ? returnByDate : nil,
                photoAttachmentIDs: attachmentIDs,
                context: modelContext
            )
        } else {
            _ = ReturnTrackingService.addPackage(
                name: name,
                carrier: carrier,
                method: method,
                trackingNumber: trackingNumber,
                returnByDate: hasReturnByDate ? returnByDate : nil,
                photoAttachmentIDs: attachmentIDs,
                to: request,
                existingPackages: existingPackages,
                context: modelContext
            )
        }
        dismiss()
    }

    private func contextInsertPhoto(_ draft: PhotoAttachmentDraft) {
        insertReturnPhoto(draft, in: modelContext)
    }
}

private struct ReturnPhotoPreviewItem: Identifiable {
    var id: UUID
    var data: Data
}

private func insertReturnPhoto(_ draft: PhotoAttachmentDraft, in modelContext: ModelContext) {
    modelContext.insert(PhotoAttachment(
        id: draft.id,
        profileID: nil,
        ownerKind: .returnPhoto,
        contentType: draft.contentType,
        filename: draft.filename,
        imageData: draft.imageData,
        thumbnailData: draft.thumbnailData,
        createdAt: draft.createdAt,
        updatedAt: draft.createdAt
    ))
}

private func statusColor(_ status: ReturnRequestStatus) -> Color {
    switch status {
    case .needsAction: .red
    case .readyToDropOff: .orange
    case .partiallyDroppedOff: .yellow
    case .droppedOff: .blue
    case .completed: .green
    case .archived: .secondary
    }
}

private func statusSystemImage(_ status: ReturnRequestStatus) -> String {
    switch status {
    case .needsAction: "exclamationmark.triangle.fill"
    case .readyToDropOff: "barcode.viewfinder"
    case .partiallyDroppedOff: "shippingbox.and.arrow.backward.fill"
    case .droppedOff: "tray.and.arrow.up.fill"
    case .completed: "checkmark.circle.fill"
    case .archived: "archivebox.fill"
    }
}

struct FoodReminderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let reminders: [FoodReminder]
    let todoLists: [HomeTodoList]
    let shoppingLists: [ShoppingList]
    let mealPrepItems: [MealPrepItem]
    let returnRequests: [ReturnRequest]

    @State private var title = ""
    @State private var type: FoodReminderType = .todos
    @State private var dateTime = Date().addingTimeInterval(3600)
    @State private var timeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
    @State private var selectedTodoListID: UUID?
    @State private var selectedListID: UUID?
    @State private var selectedMealPrepID: UUID?
    @State private var selectedReturnRequestID: UUID?

    var body: some View {
        Form {
            Section("New Reminder") {
                Picker("Type", selection: $type) {
                    ForEach(FoodReminderType.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                TextField("Title", text: $title)
                DatePicker("Time", selection: $dateTime)
                    .environment(\.timeZone, reminderTimeZone)
                NavigationLink {
                    TimeZonePickerView(selection: $timeZoneIdentifier)
                } label: {
                    LabeledContent(
                        "Time zone",
                        value: CareTimeZoneSettings.displayName(
                            for: reminderTimeZone,
                            on: dateTime
                        )
                    )
                }
                if type == .todos {
                    Picker("To-do list", selection: $selectedTodoListID) {
                        Text("None").tag(UUID?.none)
                        ForEach(todoLists) { list in
                            Text(list.name).tag(UUID?.some(list.id))
                        }
                    }
                }
                if type == .shopping {
                    Picker("List", selection: $selectedListID) {
                        Text("None").tag(UUID?.none)
                        ForEach(shoppingLists) { list in
                            Text(list.name).tag(UUID?.some(list.id))
                        }
                    }
                }
                if type == .mealPrep {
                    Picker("Meal prep", selection: $selectedMealPrepID) {
                        Text("None").tag(UUID?.none)
                        ForEach(mealPrepItems) { item in
                            Text(item.name).tag(UUID?.some(item.id))
                        }
                    }
                }
                if type == .returns {
                    Picker("Return", selection: $selectedReturnRequestID) {
                        Text("None").tag(UUID?.none)
                        ForEach(returnRequests) { request in
                            Text("Return").tag(UUID?.some(request.id))
                        }
                    }
                }
                Button("Schedule", systemImage: "bell.badge") {
                    Task {
                        await FoodReminderService.createReminder(
                            householdID: household.id,
                            type: type,
                            title: title.isEmpty ? defaultTitle : title,
                            dateTime: dateTime,
                            timeZoneIdentifier: reminderTimeZone.identifier,
                            relatedTodoListID: selectedTodoListID,
                            relatedShoppingListID: selectedListID,
                            relatedMealPrepItemID: selectedMealPrepID,
                            relatedReturnRequestID: selectedReturnRequestID,
                            context: modelContext
                        )
                        title = ""
                    }
                }
            }
            Section("Scheduled") {
                if activeReminders.isEmpty {
                    ContentUnavailableView(
                        "No scheduled reminders",
                        systemImage: "bell.slash",
                        description: Text("Food & Home reminders you schedule will appear here.")
                    )
                }
                ForEach(activeReminders) { reminder in
                    LabeledContent {
                        Text(
                            "\(DateFormatting.dayString(from: reminder.dateTime, timeZone: TimeZone(identifier: reminder.timeZoneIdentifier ?? "") ?? .autoupdatingCurrent)) · \(DateFormatting.timeString(from: reminder.dateTime, timeZone: TimeZone(identifier: reminder.timeZoneIdentifier ?? "") ?? .autoupdatingCurrent, includesTimeZone: true))"
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                            Text(reminder.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Cancel", role: .destructive) {
                            Task {
                                await FoodReminderService.cancel(reminder, context: modelContext)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Food & Home Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: type) { _, newType in
            if newType != .todos { selectedTodoListID = nil }
            if newType != .shopping { selectedListID = nil }
            if newType != .mealPrep { selectedMealPrepID = nil }
            if newType != .returns { selectedReturnRequestID = nil }
        }
    }

    private var activeReminders: [FoodReminder] {
        reminders
            .filter { $0.isEnabled && $0.dateTime > Date() }
            .sorted { $0.dateTime < $1.dateTime }
    }

    private var defaultTitle: String {
        switch type {
        case .todos: "Check to-do list"
        case .shopping: "Check shopping list"
        case .mealPrep: "Check meal prep"
        case .returns: "Check return"
        case .custom: "Food & Home reminder"
        }
    }

    private var reminderTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier)
            ?? CareTimeZoneSettings.effectiveTimeZone()
    }
}

private struct MissingFoodRouteView: View {
    var body: some View {
        ContentUnavailableView(
            "Item Not Found",
            systemImage: "questionmark.folder",
            description: Text("This Food & Home item may have been archived or deleted.")
        )
    }
}
