import SwiftData
import SwiftUI
import UIKit

struct FoodHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var router = DeepLinkRouter.shared
    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \ShoppingList.sortOrder) private var shoppingLists: [ShoppingList]
    @Query(sort: \ShoppingListItem.sortOrder) private var shoppingItems: [ShoppingListItem]
    @Query(sort: \FoodStore.sortOrder) private var stores: [FoodStore]
    @Query(sort: \FoodStoreSection.sortOrder) private var storeSections: [FoodStoreSection]
    @Query(sort: \InventoryLocation.sortOrder) private var locations: [InventoryLocation]
    @Query(sort: \InventoryItem.updatedAt, order: .reverse) private var inventoryItems: [InventoryItem]
    @Query(sort: \MealPrepItem.updatedAt, order: .reverse) private var mealPrepItems: [MealPrepItem]
    @Query(sort: \MealPrepUsage.dateTime, order: .reverse) private var mealPrepUsages: [MealPrepUsage]
    @Query(sort: \FoodReminder.dateTime) private var reminders: [FoodReminder]

    @State private var selectedSection: FoodHomeSection = .shopping
    @State private var path = NavigationPath()
    @State private var showingQuickAdd = false

    private var household: Household? { households.first }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let household {
                    content(household: household)
                } else {
                    ProgressView("Preparing Food & Home")
                        .task {
                            FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
                        }
                }
            }
            .navigationTitle("Food & Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: FoodRoute.reminders) {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("Food reminders")
                }
            }
            .navigationDestination(for: FoodRoute.self) { route in
                destination(for: route)
            }
            .task {
                FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
            }
            .onReceive(router.$pendingFoodCommand.compactMap { $0 }) { command in
                handle(command)
                router.pendingFoodCommand = nil
            }
            .sheet(isPresented: $showingQuickAdd) {
                if let household {
                    QuickAddShoppingItemView(
                        household: household,
                        shoppingLists: householdShoppingLists,
                        shoppingItems: householdShoppingItems
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func content(household: Household) -> some View {
        VStack(spacing: 0) {
            Picker("Food section", selection: $selectedSection) {
                ForEach(FoodHomeSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)

            switch selectedSection {
            case .shopping:
                ShoppingListsView(
                    household: household,
                    shoppingLists: householdShoppingLists,
                    shoppingItems: householdShoppingItems,
                    stores: householdStores,
                    openList: { path.append(FoodRoute.shoppingList($0.id)) }
                )
            case .inventory:
                InventoryHomeView(
                    household: household,
                    locations: householdLocations,
                    inventoryItems: householdInventoryItems,
                    mealPrepItems: householdMealPrepItems,
                    shoppingLists: householdShoppingLists,
                    shoppingItems: householdShoppingItems,
                    openItem: { path.append(FoodRoute.inventoryItem($0.id)) }
                )
            case .mealPrep:
                MealPrepView(
                    household: household,
                    locations: householdLocations,
                    mealPrepItems: householdMealPrepItems,
                    openItem: { path.append(FoodRoute.mealPrepItem($0.id)) }
                )
            case .stores:
                StoresView(
                    household: household,
                    stores: householdStores,
                    sections: householdStoreSections,
                    openStore: { path.append(FoodRoute.store($0.id)) }
                )
            case .insights:
                FoodInsightsView(
                    household: household,
                    locations: householdLocations,
                    inventoryItems: householdInventoryItems,
                    mealPrepItems: householdMealPrepItems,
                    shoppingLists: householdShoppingLists,
                    shoppingItems: householdShoppingItems,
                    mealPrepUsages: householdMealPrepUsages
                )
            }
        }
        .background(AppTheme.background)
    }

    @ViewBuilder
    private func destination(for route: FoodRoute) -> some View {
        switch route {
        case .shoppingList(let id):
            if let list = householdShoppingLists.first(where: { $0.id == id }) {
                ShoppingListDetailView(
                    list: list,
                    items: householdShoppingItems.filter { $0.shoppingListID == list.id },
                    store: householdStores.first { $0.id == list.storeID },
                    sections: householdStoreSections.filter { $0.storeID == list.storeID },
                    inventoryItems: householdInventoryItems,
                    mealPrepItems: householdMealPrepItems,
                    openShoppingMode: { path.append(FoodRoute.shoppingMode(list.id)) }
                )
            } else {
                MissingFoodRouteView()
            }
        case .shoppingMode(let id):
            if let list = householdShoppingLists.first(where: { $0.id == id }) {
                ShoppingModeView(
                    list: list,
                    items: householdShoppingItems.filter { $0.shoppingListID == list.id },
                    sections: householdStoreSections.filter { $0.storeID == list.storeID },
                    locations: householdLocations
                )
            } else {
                MissingFoodRouteView()
            }
        case .inventoryItem(let id):
            if let item = householdInventoryItems.first(where: { $0.id == id }) {
                InventoryItemDetailView(
                    item: item,
                    locations: householdLocations,
                    shoppingLists: householdShoppingLists,
                    shoppingItems: householdShoppingItems
                )
            } else {
                MissingFoodRouteView()
            }
        case .mealPrepItem(let id):
            if let item = householdMealPrepItems.first(where: { $0.id == id }) {
                MealPrepDetailView(
                    item: item,
                    locations: householdLocations,
                    usages: householdMealPrepUsages.filter { $0.mealPrepItemID == item.id }
                )
            } else {
                MissingFoodRouteView()
            }
        case .store(let id):
            if let store = householdStores.first(where: { $0.id == id }) {
                StoreEditorView(
                    store: store,
                    sections: householdStoreSections.filter { $0.storeID == store.id }
                )
            } else {
                MissingFoodRouteView()
            }
        case .reminders:
            if let household {
                FoodReminderSettingsView(
                    household: household,
                    reminders: householdReminders,
                    shoppingLists: householdShoppingLists,
                    mealPrepItems: householdMealPrepItems
                )
            }
        }
    }

    private func handle(_ command: FoodRouteCommand) {
        switch command {
        case .food:
            selectedSection = .shopping
            path.removeLast(path.count)
        case .shopping:
            selectedSection = .shopping
            path.removeLast(path.count)
        case .shoppingList(let id):
            selectedSection = .shopping
            path.append(FoodRoute.shoppingList(id))
        case .shoppingMode(let id):
            selectedSection = .shopping
            path.append(FoodRoute.shoppingMode(id))
        case .inventory:
            selectedSection = .inventory
            path.removeLast(path.count)
        case .inventoryItem(let id):
            selectedSection = .inventory
            path.append(FoodRoute.inventoryItem(id))
        case .mealPrep:
            selectedSection = .mealPrep
            path.removeLast(path.count)
        case .mealPrepItem(let id):
            selectedSection = .mealPrep
            path.append(FoodRoute.mealPrepItem(id))
        case .store(let id):
            selectedSection = .stores
            path.append(FoodRoute.store(id))
        case .quickAdd:
            selectedSection = .shopping
            showingQuickAdd = true
        }
    }

    private var householdShoppingLists: [ShoppingList] {
        guard let household else { return [] }
        return shoppingLists
            .filter { $0.householdID == household.id && !$0.isArchived }
            .sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }
    }

    private var householdShoppingItems: [ShoppingListItem] {
        guard let household else { return [] }
        return shoppingItems.filter { $0.householdID == household.id }
    }

    private var householdStores: [FoodStore] {
        guard let household else { return [] }
        return stores
            .filter { $0.householdID == household.id && !$0.isArchived }
            .sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }
    }

    private var householdStoreSections: [FoodStoreSection] {
        guard let household else { return [] }
        return storeSections
            .filter { $0.householdID == household.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var householdLocations: [InventoryLocation] {
        guard let household else { return [] }
        return locations
            .filter { $0.householdID == household.id && !$0.isArchived }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var householdInventoryItems: [InventoryItem] {
        guard let household else { return [] }
        return inventoryItems.filter { $0.householdID == household.id }
    }

    private var householdMealPrepItems: [MealPrepItem] {
        guard let household else { return [] }
        return mealPrepItems.filter { $0.householdID == household.id }
    }

    private var householdMealPrepUsages: [MealPrepUsage] {
        guard let household else { return [] }
        return mealPrepUsages.filter { $0.householdID == household.id }
    }

    private var householdReminders: [FoodReminder] {
        guard let household else { return [] }
        return reminders.filter { $0.householdID == household.id }
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
    @State private var newListName = ""
    @State private var selectedStoreID: UUID?

    var body: some View {
        List {
            Section {
                ForEach(shoppingLists) { list in
                    Button {
                        openList(list)
                    } label: {
                        ShoppingListSummaryRow(
                            list: list,
                            store: stores.first { $0.id == list.storeID },
                            items: shoppingItems.filter { $0.shoppingListID == list.id }
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                AppSectionHeader(title: "Reusable Lists", subtitle: "\(shoppingLists.count)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedStoreID = nil
                    showingNewList = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create shopping list")
            }
        }
        .sheet(isPresented: $showingNewList) {
            NavigationStack {
                Form {
                    TextField("List name", text: $newListName)
                    Picker("Store", selection: $selectedStoreID) {
                        Text("General").tag(UUID?.none)
                        ForEach(stores) { store in
                            Text(store.name).tag(UUID?.some(store.id))
                        }
                    }
                }
                .navigationTitle("New List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingNewList = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            _ = ShoppingListService.createList(
                                name: newListName,
                                householdID: household.id,
                                storeID: selectedStoreID,
                                context: modelContext
                            )
                            newListName = ""
                            showingNewList = false
                        }
                    }
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
    @Bindable var list: ShoppingList
    let items: [ShoppingListItem]
    let store: FoodStore?
    let sections: [FoodStoreSection]
    let inventoryItems: [InventoryItem]
    let mealPrepItems: [MealPrepItem]
    let openShoppingMode: () -> Void

    @State private var fastAddText = ""
    @State private var selectedSectionID: UUID?
    @State private var showingChecked = true
    @State private var searchText = ""
    @State private var editingItem: ShoppingListItem?
    @State private var showingActions = false

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
        List {
            Section {
                HStack {
                    TextField("Add item", text: $fastAddText)
                        .submitLabel(.done)
                        .onSubmit(addFastItem)
                    Menu {
                        Button("No Section") { selectedSectionID = nil }
                        ForEach(sections) { section in
                            Button(section.name) { selectedSectionID = section.id }
                        }
                    } label: {
                        Label(selectedSectionName, systemImage: "square.grid.2x2")
                            .labelStyle(.iconOnly)
                    }
                    Button(action: addFastItem) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(fastAddText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            suggestionsSection

            ForEach(sections) { section in
                let sectionItems = activeItems(sectionID: section.id)
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
                            }
                        }
                    }
                }
            }

            let otherItems = activeItems(sectionID: nil)
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
                        }
                    }
                }
            }

            if showingChecked {
                let checked = visibleItems.filter(\.isChecked)
                if !checked.isEmpty {
                    Section("In Cart") {
                        ForEach(checked) { item in
                            ShoppingListItemRow(item: item, large: false) {
                                ShoppingListService.setChecked(
                                    item,
                                    isChecked: false,
                                    context: modelContext
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Edit") { editingItem = item }
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
        .searchable(text: $searchText, prompt: "Search this list")
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
            }
        }
        .sheet(item: $editingItem) { item in
            ShoppingListItemEditorView(item: item, sections: sections)
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
                }
            }
        }
    }

    private var selectedSectionName: String {
        selectedSectionID.flatMap { id in sections.first { $0.id == id }?.name } ?? "Section"
    }

    private func activeItems(sectionID: UUID?) -> [ShoppingListItem] {
        visibleItems
            .filter { !$0.isChecked && $0.storeSectionID == sectionID }
            .sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }
    }

    private func addFastItem() {
        ShoppingListService.addItem(
            named: fastAddText,
            to: list,
            sectionID: selectedSectionID,
            existingItems: items,
            context: modelContext
        )
        fastAddText = ""
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
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
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
                let sectionItems = modeItems(sectionID: section.id)
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

            let otherItems = modeItems(sectionID: nil)
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

    private func modeItems(sectionID: UUID?) -> [ShoppingListItem] {
        items
            .filter { item in
                item.storeSectionID == sectionID
                    && (filter == .all
                        || (filter == .active && !item.isChecked)
                        || (filter == .checked && item.isChecked))
            }
            .sorted { ($0.sortOrder ?? 0, $0.name) < ($1.sortOrder ?? 0, $1.name) }
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

private struct ShoppingListItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: ShoppingListItem
    let sections: [FoodStoreSection]

    @State private var name = ""
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var notes = ""
    @State private var sectionID: UUID?
    @State private var isStaple = false
    @State private var priority: ShoppingItemPriority = .normal
    @State private var inventoryBehavior: InventoryLinkBehavior = .askWhenChecked

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Quantity", value: $quantity, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Unit", text: $unit)
                Picker("Section", selection: $sectionID) {
                    Text("Other").tag(UUID?.none)
                    ForEach(sections) { section in
                        Text(section.name).tag(UUID?.some(section.id))
                    }
                }
                Toggle("Staple", isOn: $isStaple)
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
                TextField("Notes", text: $notes, axis: .vertical)
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
                            priority: priority,
                            inventoryLinkBehavior: inventoryBehavior,
                            context: modelContext
                        )
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
                priority = item.priority
                inventoryBehavior = item.inventoryLinkBehavior
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

    var body: some View {
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
                ForEach(filteredItems) { item in
                    Button { openItem(item) } label: {
                        InventoryItemRow(
                            item: item,
                            location: locations.first { $0.id == item.locationID }
                        )
                    }
                    .buttonStyle(.plain)
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

    var body: some View {
        NavigationStack {
            List {
                Section("Locations") {
                    ForEach(locations) { location in
                        Button {
                            editingLocation = location
                            showingEditor = true
                        } label: {
                            locationRow(location)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Archive", role: .destructive) {
                                archive(location)
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
        }
    }

    private func locationRow(_ location: InventoryLocation) -> some View {
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
            let count = usageCount(for: location)
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

    private func usageCount(for location: InventoryLocation) -> Int {
        inventoryItems.filter { $0.locationID == location.id }.count
            + mealPrepItems.filter { $0.locationID == location.id && !$0.isArchived }.count
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
    @Bindable var item: InventoryItem
    let locations: [InventoryLocation]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]

    @State private var showingEditor = false
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

    var body: some View {
        List {
            ForEach(groupedLocations, id: \.id) { location in
                let items = filteredItems.filter { $0.locationID == location.id }
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
                        }
                    }
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
    @Bindable var item: MealPrepItem
    let locations: [InventoryLocation]
    let usages: [MealPrepUsage]

    @State private var showingEditor = false
    @State private var showingUseSheet = false
    @State private var showingFinishPrompt = false

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
                    item.isArchived = true
                    item.updatedAt = Date()
                    save(modelContext)
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
            }
            Button("Keep Visible", role: .cancel) {}
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Total", value: $servingsTotal, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Remaining", value: $servingsRemaining, format: .number)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $servingUnit) {
                    ForEach(MealPrepServingUnit.allCases) { unit in
                        Text(unit.singularName.capitalized).tag(unit)
                    }
                }
                Picker("Location", selection: $locationID) {
                    ForEach(locations) { location in
                        Text(location.name).tag(UUID?.some(location.id))
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
    @State private var storeName = ""

    var body: some View {
        List {
            Section("Stores") {
                ForEach(stores) { store in
                    Button {
                        openStore(store)
                    } label: {
                        LabeledContent {
                            Text("\(sections.filter { $0.storeID == store.id }.count) sections")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label(store.name, systemImage: "map.fill")
                        }
                    }
                    .buttonStyle(.plain)
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
            NavigationStack {
                Form {
                    TextField("Store name", text: $storeName)
                }
                .navigationTitle("New Store")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingNewStore = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            _ = StoreLayoutService.createStore(
                                name: storeName,
                                householdID: household.id,
                                context: modelContext
                            )
                            storeName = ""
                            showingNewStore = false
                        }
                    }
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
    @State private var newSectionName = ""

    var body: some View {
        Form {
            Section("Store") {
                TextField("Name", text: $store.name)
                    .onChange(of: store.name) { _, _ in
                        store.updatedAt = Date()
                        save(modelContext)
                    }
                TextField("Notes", text: Binding(
                    get: { store.notes ?? "" },
                    set: { store.notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ), axis: .vertical)
            }
            Section("Sections") {
                ForEach(sections) { section in
                    StoreSectionEditorView(section: section)
                }
                HStack {
                    TextField("New section", text: $newSectionName)
                    Button("Add") {
                        StoreLayoutService.createSection(
                            name: newSectionName,
                            store: store,
                            existingSections: sections,
                            context: modelContext
                        )
                        newSectionName = ""
                    }
                }
            }
            Section {
                Button("Archive Store", role: .destructive) {
                    StoreLayoutService.archiveStore(store, context: modelContext)
                    dismiss()
                }
            }
        }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StoreSectionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: FoodStoreSection

    var body: some View {
        HStack {
            TextField("Section", text: $section.name)
            TextField("Order", value: $section.sortOrder, format: .number)
                .keyboardType(.numberPad)
                .frame(width: 70)
        }
        .onChange(of: section.name) { _, _ in persist() }
        .onChange(of: section.sortOrder) { _, _ in persist() }
    }

    private func persist() {
        section.updatedAt = Date()
        save(modelContext)
    }
}

private struct FoodInsightsView: View {
    let household: Household
    let locations: [InventoryLocation]
    let inventoryItems: [InventoryItem]
    let mealPrepItems: [MealPrepItem]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let mealPrepUsages: [MealPrepUsage]

    var body: some View {
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
            Section("Inventory by Location") {
                ForEach(locations) { location in
                    LabeledContent(location.name) {
                        Text("\(inventoryItems.filter { $0.locationID == location.id && $0.status == .available }.count)")
                    }
                }
            }
            Section("Meal Prep Servings") {
                ForEach(mealPrepItems.filter { !$0.isArchived }) { item in
                    LabeledContent(item.name) {
                        Text(item.servingsText)
                    }
                }
            }
            Section("Shopping Trips by Store") {
                ForEach(shoppingLists) { list in
                    LabeledContent(list.name) {
                        Text(list.lastUsedAt == nil ? "No trips" : "Used")
                    }
                }
            }
            Section("Meal Prep Usage") {
                ForEach(mealPrepUsages.prefix(12)) { usage in
                    LabeledContent(DateFormatting.day.string(from: usage.dateTime)) {
                        Text("\(formatted(usage.servingsUsed)) servings")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }

    private var metrics: [FoodInsightMetric] {
        FoodInsightsService.metrics(
            householdID: household.id,
            locations: locations,
            inventoryItems: inventoryItems,
            mealPrepItems: mealPrepItems,
            shoppingLists: shoppingLists,
            shoppingItems: shoppingItems
        )
    }
}

struct FoodReminderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let household: Household
    let reminders: [FoodReminder]
    let shoppingLists: [ShoppingList]
    let mealPrepItems: [MealPrepItem]

    @State private var title = ""
    @State private var type: FoodReminderType = .shopping
    @State private var dateTime = Date().addingTimeInterval(3600)
    @State private var selectedListID: UUID?
    @State private var selectedMealPrepID: UUID?

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
                Button("Schedule", systemImage: "bell.badge") {
                    Task {
                        await FoodReminderService.createReminder(
                            householdID: household.id,
                            type: type,
                            title: title.isEmpty ? defaultTitle : title,
                            dateTime: dateTime,
                            relatedShoppingListID: selectedListID,
                            relatedMealPrepItemID: selectedMealPrepID,
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
                        Text(DateFormatting.day.string(from: reminder.dateTime))
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
        .navigationTitle("Food Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeReminders: [FoodReminder] {
        reminders
            .filter { $0.isEnabled && $0.dateTime > Date() }
            .sorted { $0.dateTime < $1.dateTime }
    }

    private var defaultTitle: String {
        switch type {
        case .shopping: "Check shopping list"
        case .mealPrep: "Check meal prep"
        case .custom: "Food & Home reminder"
        }
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
