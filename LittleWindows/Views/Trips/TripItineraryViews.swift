import Observation
import SwiftData
import SwiftUI
import UIKit

private enum TripDetailWorkspace: String, CaseIterable, Identifiable {
    case itinerary
    case packing

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PackingTripDetailView: View {
    let trip: PackingTrip
    let allTrips: [PackingTrip]
    let allTravelers: [TripTraveler]
    let allBags: [PackingBag]
    let allItems: [PackingItem]
    let itineraryChoiceGroups: [TripItineraryChoiceGroup]
    let itineraryItems: [TripItineraryItem]
    let itineraryLinks: [TripItineraryLink]
    let profiles: [CareProfile]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    var initialItineraryItemID: UUID? = nil
    var startsInPacking = false

    @State private var workspaceOverride: TripDetailWorkspace?

    private var workspace: TripDetailWorkspace {
        workspaceOverride ?? (startsInPacking ? .packing : .itinerary)
    }

    private var workspaceSelection: Binding<TripDetailWorkspace> {
        Binding(
            get: { workspace },
            set: { workspaceOverride = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Trip workspace", selection: workspaceSelection) {
                ForEach(TripDetailWorkspace.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityIdentifier("trip.workspace")

            switch workspace {
            case .itinerary:
                TripItineraryView(
                    trip: trip,
                    allTrips: allTrips,
                    allTravelers: allTravelers,
                    allBags: allBags,
                    allPackingItems: allItems,
                    travelers: allTravelers.filter { $0.tripID == trip.id },
                    choiceGroups: itineraryChoiceGroups.filter { $0.tripID == trip.id },
                    items: itineraryItems.filter { $0.tripID == trip.id },
                    links: itineraryLinks.filter { $0.tripID == trip.id },
                    initialItemID: initialItineraryItemID
                )
            case .packing:
                PackingListDetailView(
                    trip: trip,
                    allTrips: allTrips,
                    allTravelers: allTravelers,
                    allBags: allBags,
                    allItems: allItems,
                    itineraryChoiceGroups: itineraryChoiceGroups,
                    itineraryItems: itineraryItems,
                    itineraryLinks: itineraryLinks,
                    profiles: profiles,
                    shoppingLists: shoppingLists,
                    shoppingItems: shoppingItems
                )
            }
        }
    }
}

private struct TripItineraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: PackingTrip
    let allTrips: [PackingTrip]
    let allTravelers: [TripTraveler]
    let allBags: [PackingBag]
    let allPackingItems: [PackingItem]
    let travelers: [TripTraveler]
    let choiceGroups: [TripItineraryChoiceGroup]
    let items: [TripItineraryItem]
    let links: [TripItineraryLink]
    let initialItemID: UUID?

    @State private var showingNewItem = false
    @State private var newItemDay: Date?
    @State private var newItemGroup: TripItineraryChoiceGroup?
    @State private var editingItem: TripItineraryItem?
    @State private var showingNewGroup = false
    @State private var editingGroup: TripItineraryChoiceGroup?
    @State private var weatherForecasts = [TripDestinationWeatherForecast]()
    @State private var failureMessage: String?
    @State private var appliedInitialItem = false
    @State private var showingWeatherAttribution = false
    @State private var showingTripEditor = false
    @State private var showingDeleteConfirmation = false

    private var itineraryDays: [Date] {
        let calendar = trip.tripCalendar
        let first = calendar.startOfDay(for: trip.startDate)
        let last = calendar.startOfDay(for: trip.endDate)
        var result = [Date]()
        var day = first
        while day <= last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    var body: some View {
        itineraryPresentations
    }

    private var itineraryPresentations: some View {
        itineraryEditors
            .sheet(isPresented: $showingNewGroup) {
                NavigationStack {
                    TripItineraryChoiceGroupEditorView(
                        trip: trip,
                        group: nil,
                        existingGroups: choiceGroups,
                        items: items
                    )
                }
            }
            .sheet(item: $editingGroup) { group in
                NavigationStack {
                    TripItineraryChoiceGroupEditorView(
                        trip: trip,
                        group: group,
                        existingGroups: choiceGroups,
                        items: items
                    )
                }
            }
            .sheet(isPresented: $showingWeatherAttribution) {
                if let weatherAttribution {
                    TripWeatherAttributionSheet(snapshot: weatherAttribution)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showingTripEditor) {
                NavigationStack {
                    PackingTripEditorView(trip: trip)
                }
            }
            .task(id: weatherRequestID) {
                weatherForecasts = await TripWeatherService.forecasts(for: trip)
            }
            .task(id: "\(initialItemID?.uuidString ?? "none")|\(items.count)") {
                guard !appliedInitialItem else { return }
                if let initialItemID,
                   let item = items.first(where: { $0.id == initialItemID }),
                   !trip.isArchived {
                    appliedInitialItem = true
                    editingItem = item
                }
            }
            .alert("Couldn’t Update Itinerary", isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failureMessage ?? "Please try again.")
            }
            .appActionSheet(
                isPresented: $showingDeleteConfirmation,
                title: "Delete Trip?",
                message: "This permanently removes the trip, itinerary, packing list, bags, and traveler assignments. Items already added to Shopping will remain.",
                systemImage: "trash.fill",
                tint: .red,
                options: [
                    AppActionSheetOption(
                        title: "Delete Trip",
                        subtitle: trip.title,
                        systemImage: "trash.fill",
                        tint: .red,
                        role: .destructive
                    ) {
                        if TripPackingService.deleteTrip(trip, context: modelContext) {
                            dismiss()
                        } else {
                            failureMessage = "The trip couldn’t be deleted."
                        }
                    }
                ]
            )
    }

    private var itineraryEditors: some View {
        itineraryList
            .sheet(isPresented: $showingNewItem) {
                NavigationStack {
                    TripItineraryItemEditorView(
                        trip: trip,
                        item: nil,
                        initialDay: newItemDay,
                        initialGroup: newItemGroup,
                        travelers: travelers,
                        choiceGroups: choiceGroups,
                        existingItems: items,
                        links: links
                    )
                }
            }
            .sheet(item: $editingItem) { item in
                NavigationStack {
                    TripItineraryItemEditorView(
                        trip: trip,
                        item: item,
                        initialDay: item.scheduledDay,
                        initialGroup: item.choiceGroupID.flatMap { id in
                            choiceGroups.first { $0.id == id }
                        },
                        travelers: travelers,
                        choiceGroups: choiceGroups,
                        existingItems: items,
                        links: links
                    )
                }
            }
    }

    private var itineraryList: some View {
        let presentation = TripItineraryPresentationIndex(
            trip: trip,
            choiceGroups: choiceGroups,
            items: items,
            links: links,
            weatherForecasts: weatherForecasts
        )
        return List {
            if trip.isArchived {
                Section {
                    Label("Archived · Read only", systemImage: "archivebox.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(presentation.itineraryDays, id: \.self) { day in
                Section {
                    let dayItems = presentation.ungroupedItemsByDay[day] ?? []
                    let dayGroups = presentation.groupsByDay[day] ?? []
                    if dayItems.isEmpty && dayGroups.isEmpty {
                        Button {
                            beginAddingItem(on: day)
                        } label: {
                            Label("Nothing planned — add an item", systemImage: "plus.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(trip.isArchived ? Color.secondary : Color.itineraryAction)
                        }
                        .disabled(trip.isArchived)
                    } else {
                        ForEach(dayItems) { item in
                            itineraryRow(item, linkValues: presentation.linksByItemID[item.id] ?? [])
                        }
                        ForEach(dayGroups) { group in
                            choiceGroupCard(
                                group,
                                options: presentation.optionsByGroupID[group.id] ?? [],
                                linksByItemID: presentation.linksByItemID
                            )
                        }
                    }
                } header: {
                    ItineraryDayHeader(
                        day: day,
                        trip: trip,
                        destination: presentation.destinationsByDay[day],
                        weather: presentation.weatherByDay[day]
                    )
                }
            }

            if !presentation.unscheduledItems.isEmpty || !presentation.unscheduledGroups.isEmpty || !trip.isArchived {
                Section {
                    ForEach(presentation.unscheduledItems) { item in
                        itineraryRow(item, linkValues: presentation.linksByItemID[item.id] ?? [])
                    }
                    ForEach(presentation.unscheduledGroups) { group in
                        choiceGroupCard(
                            group,
                            options: presentation.optionsByGroupID[group.id] ?? [],
                            linksByItemID: presentation.linksByItemID
                        )
                    }
                    if !trip.isArchived {
                        Button {
                            beginAddingItem(on: nil)
                        } label: {
                            Label("Add an idea", systemImage: "lightbulb")
                        }
                        .buttonStyle(.borderless)
                        .tint(.itineraryAction)
                    }
                } header: {
                    Label("Ideas · No Day Yet", systemImage: "lightbulb.fill")
                        .foregroundStyle(Color(uiColor: .label))
                }
            }
            if let weatherAttribution {
                Section {
                    Button {
                        showingWeatherAttribution = true
                    } label: {
                        HStack {
                            TripWeatherAttributionMark(snapshot: weatherAttribution)
                            Spacer()
                            Text("About weather data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .accessibilityIdentifier("trip.itinerary")
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if !trip.isArchived {
                        Menu {
                            Button("Add Itinerary Item", systemImage: "calendar.badge.plus") {
                                beginAddingItem(on: nextUsefulDay)
                            }
                            Button("Add Option Group", systemImage: "arrow.triangle.branch") {
                                showingNewGroup = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 44, height: 36)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("trip.itinerary.add")
                    }
                    Menu {
                        if !trip.isArchived {
                            Button("Edit Trip", systemImage: "pencil") { showingTripEditor = true }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            if TripPackingService.duplicateTrip(
                                trip,
                                travelers: allTravelers,
                                bags: allBags,
                                items: allPackingItems,
                                itineraryChoiceGroups: choiceGroups,
                                itineraryItems: items,
                                itineraryLinks: links,
                                existingTrips: allTrips,
                                context: modelContext
                            ) != nil {
                                dismiss()
                            } else {
                                failureMessage = "The trip couldn’t be duplicated."
                            }
                        }
                        if trip.isArchived {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                if !TripPackingService.restore(trip, context: modelContext) {
                                    failureMessage = "The trip couldn’t be restored."
                                }
                            }
                        } else if trip.status == .completed {
                            Button("Reopen Trip", systemImage: "arrow.uturn.backward") {
                                if !TripPackingService.setCompleted(trip, completed: false, context: modelContext) {
                                    failureMessage = "The trip couldn’t be reopened."
                                }
                            }
                        } else {
                            Button("Mark Complete", systemImage: "checkmark.circle") {
                                if !TripPackingService.setCompleted(trip, completed: true, context: modelContext) {
                                    failureMessage = "The trip couldn’t be completed."
                                }
                            }
                        }
                        if !trip.isArchived {
                            Divider()
                            Button("Archive", systemImage: "archivebox", role: .destructive) {
                                if TripPackingService.archive(trip, context: modelContext) {
                                    dismiss()
                                } else {
                                    failureMessage = "The trip couldn’t be archived."
                                }
                            }
                        }
                        Divider()
                        Button("Delete Trip", systemImage: "trash", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .accessibilityIdentifier("trip.delete")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("trip.actions")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var nextUsefulDay: Date? {
        let today = trip.tripCalendar.startOfDay(for: Date())
        return itineraryDays.first { $0 >= today } ?? itineraryDays.first
    }

    private var weatherRequestID: String {
        [
            trip.weatherSuggestionsEnabled ? "on" : "off",
            trip.destinationName ?? "",
            trip.destinationLatitude.map { String($0) } ?? "",
            trip.destinationLongitude.map { String($0) } ?? "",
            trip.destinationTimeZoneIdentifier ?? "",
            trip.destinationStopsRawValue,
            String(trip.startDate.timeIntervalSinceReferenceDate),
            String(trip.endDate.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private var weatherAttribution: TripWeatherSnapshot? {
        weatherForecasts.compactMap(\.snapshot).first
    }

    private func beginAddingItem(on day: Date?, group: TripItineraryChoiceGroup? = nil) {
        newItemDay = day
        newItemGroup = group
        showingNewItem = true
    }

    private func itineraryRow(
        _ item: TripItineraryItem,
        linkValues: [TripItineraryLink]
    ) -> some View {
        TripItineraryInteractiveItemRow(
            item: item,
            links: linkValues,
            trip: trip,
            selectedInChoiceGroup: item.choiceGroupID.flatMap { groupID in
                choiceGroups.first { $0.id == groupID }?.selectedItemID == item.id
            } ?? false,
            toggleTask: {
                guard !trip.isArchived else { return }
                if !TripItineraryService.setCompleted(
                    item,
                    completed: !item.isCompleted,
                    trip: trip,
                    context: modelContext
                ) {
                    failureMessage = "The task couldn’t be updated."
                }
            },
            edit: {
                guard !trip.isArchived else { return }
                editingItem = item
            },
            delete: {
                guard !trip.isArchived else { return }
                if !TripItineraryService.deleteItem(
                    item,
                    trip: trip,
                    choiceGroups: choiceGroups,
                    links: links,
                    context: modelContext
                ) {
                    failureMessage = "The itinerary item couldn’t be deleted."
                }
            }
        )
        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 6, trailing: 20))
    }

    private func choiceGroupCard(
        _ group: TripItineraryChoiceGroup,
        options: [TripItineraryItem],
        linksByItemID: [UUID: [TripItineraryLink]]
    ) -> TripItineraryChoiceGroupCard {
        TripItineraryChoiceGroupCard(
            group: group,
            options: options,
            linksByItemID: linksByItemID,
            trip: trip,
            editGroup: { editingGroup = group },
            select: { option in
                guard !trip.isArchived else { return }
                if !TripItineraryService.selectChoice(
                    option,
                    in: group,
                    trip: trip,
                    context: modelContext
                ) {
                    failureMessage = "The selected option couldn’t be saved."
                }
            },
            editItem: { editingItem = $0 },
            deleteItem: { item in
                if !TripItineraryService.deleteItem(
                    item,
                    trip: trip,
                    choiceGroups: choiceGroups,
                    links: links,
                    context: modelContext
                ) {
                    failureMessage = "The itinerary item couldn’t be deleted."
                }
            },
            toggleTask: { item in
                if !TripItineraryService.setCompleted(
                    item,
                    completed: !item.isCompleted,
                    trip: trip,
                    context: modelContext
                ) {
                    failureMessage = "The task couldn’t be updated."
                }
            },
            addOption: { beginAddingItem(on: group.scheduledDay, group: group) }
        )
    }
}

private struct TripItineraryInteractiveItemRow: View {
    let item: TripItineraryItem
    let links: [TripItineraryLink]
    let trip: PackingTrip
    let selectedInChoiceGroup: Bool
    let toggleTask: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        TripItineraryItemRow(
            item: item,
            links: links,
            trip: trip,
            selectedInChoiceGroup: selectedInChoiceGroup,
            toggleTask: toggleTask,
            edit: edit
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !trip.isArchived {
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if !trip.isArchived {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        }
    }
}

private struct TripItineraryChoiceGroupCard: View {
    let group: TripItineraryChoiceGroup
    let options: [TripItineraryItem]
    let linksByItemID: [UUID: [TripItineraryLink]]
    let trip: PackingTrip
    let editGroup: () -> Void
    let select: (TripItineraryItem?) -> Void
    let editItem: (TripItineraryItem) -> Void
    let deleteItem: (TripItineraryItem) -> Void
    let toggleTask: (TripItineraryItem) -> Void
    let addOption: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .accessibilityHidden(true)
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .foregroundStyle(Color(uiColor: .label))
                    .layoutPriority(1)
                Spacer()
                if !trip.isArchived {
                    Button(action: editGroup) {
                        Text("Edit")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(uiColor: .label))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 12)
                            .frame(minWidth: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("trip.itinerary.group.edit.\(group.id.uuidString)")
                }
            }
            if let notes = group.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            if options.isEmpty {
                Text("No options yet")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            ForEach(options) { option in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        select(group.selectedItemID == option.id ? nil : option)
                    } label: {
                        Image(systemName: group.selectedItemID == option.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(group.selectedItemID == option.id ? .green : .secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(trip.isArchived)
                    .accessibilityLabel(group.selectedItemID == option.id ? "Clear selected option" : "Select this option")
                    TripItineraryInteractiveItemRow(
                        item: option,
                        links: linksByItemID[option.id] ?? [],
                        trip: trip,
                        selectedInChoiceGroup: group.selectedItemID == option.id,
                        toggleTask: { toggleTask(option) },
                        edit: { editItem(option) },
                        delete: { deleteItem(option) }
                    )
                }
            }
            if !trip.isArchived {
                Button(action: addOption) {
                    Label("Add option", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .tint(.itineraryAction)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("trip.itinerary.group.\(group.id.uuidString)")
    }
}

private struct ItineraryDayHeader: View {
    let day: Date
    let trip: PackingTrip
    let destination: TripDestinationSelection?
    let weather: TripDailyWeather?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                if let destination {
                    Label(destination.name, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .label))
                }
            }
            Spacer()
            if let weather {
                Label(temperatureText(weather), systemImage: weather.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
            }
        }
        .textCase(nil)
    }

    private func temperatureText(_ weather: TripDailyWeather) -> String {
        let unit: UnitTemperature = Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        let low = Measurement(value: weather.lowTemperatureCelsius, unit: UnitTemperature.celsius)
            .converted(to: unit).value
        let high = Measurement(value: weather.highTemperatureCelsius, unit: UnitTemperature.celsius)
            .converted(to: unit).value
        return "\(Int(high.rounded()))° / \(Int(low.rounded()))°"
    }

    private var dayText: String {
        day.formatted(Date.FormatStyle(
            date: .complete,
            time: .omitted,
            calendar: trip.tripCalendar,
            timeZone: trip.tripTimeZone
        ))
    }
}

private struct TripItineraryItemRow: View {
    @Environment(\.openURL) private var openURL

    let item: TripItineraryItem
    let links: [TripItineraryLink]
    let trip: PackingTrip
    let selectedInChoiceGroup: Bool
    let toggleTask: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.kind.supportsCompletion {
                Button(action: toggleTask) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")
            } else {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if trip.isArchived {
                    summary
                } else {
                    summary
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: edit)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(item.title)
                    .accessibilityHint("Edit itinerary item")
                }

                if hasActions {
                    HStack(spacing: 8) {
                        if let mapURL {
                            Button {
                                openURL(mapURL)
                            } label: {
                                TripItineraryActionLabel(
                                    title: "Directions",
                                    systemImage: "arrow.triangle.turn.up.right.diamond"
                                )
                            }
                            .accessibilityIdentifier("trip.itinerary.item.\(item.id.uuidString).directions")
                        }
                        if actionableLinks.count == 1,
                           let link = actionableLinks.first,
                           let url = link.url {
                            Button {
                                openURL(url)
                            } label: {
                                TripItineraryActionLabel(title: link.title, systemImage: "link")
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(link.title)
                        } else if actionableLinks.count > 1 {
                            Menu {
                                ForEach(actionableLinks) { link in
                                    if let url = link.url {
                                        Link(link.title, destination: url)
                                    }
                                }
                            } label: {
                                TripItineraryActionLabel(title: "Links", systemImage: "link")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.itinerary.item.\(item.id.uuidString)")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .strikethrough(item.bookingStatus == .cancelled || item.isCompleted)
                if selectedInChoiceGroup {
                    Text("SELECTED")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 4)
                if !trip.isArchived {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                    Text(scheduleText)
                        .fontWeight(.semibold)
                }
                .fixedSize(horizontal: true, vertical: false)
                if let routeText {
                    HStack(spacing: 5) {
                        Image(systemName: item.kind.supportsOrigin ? "arrow.left.arrow.right" : "mappin")
                            .accessibilityHidden(true)
                        Text(routeText)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if item.bookingStatus != .planned || item.confirmationNumber != nil || item.providerName != nil {
                Label(bookingText, systemImage: item.bookingStatus.systemImage)
                    .font(.caption.weight(item.bookingStatus == .booked ? .semibold : .regular))
                    .foregroundStyle(item.bookingStatus == .booked ? .green : .secondary)
                    .textSelection(.enabled)
            }
            if let notes = item.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let assignee = item.assignedCaregiverName {
                Label(assignee, systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasActions: Bool {
        mapURL != nil || !actionableLinks.isEmpty
    }

    private var actionableLinks: [TripItineraryLink] {
        links.filter { $0.url != nil }
    }

    private var iconColor: Color {
        switch item.bookingStatus {
        case .booked: .green
        case .cancelled: .secondary
        case .idea: .orange
        case .planned: .itineraryAction
        }
    }

    private var scheduleText: String {
        guard item.scheduleKind == .timed, let start = item.startDate else {
            return item.scheduleKind.shortDisplayName
        }
        let startText = timeText(start, timeZoneIdentifier: item.startTimeZoneIdentifier)
        guard let end = item.endDate else { return startText }
        let endText = timeText(end, timeZoneIdentifier: item.endTimeZoneIdentifier)
        return "\(startText)–\(endText)"
    }

    private func timeText(_ date: Date, timeZoneIdentifier: String?) -> String {
        date.formatted(Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            timeZone: timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? trip.tripTimeZone
        ))
    }

    private var routeText: String? {
        if let origin = item.originName, let destination = item.locationName {
            return "\(origin) → \(destination)"
        }
        return item.locationName
    }

    private var bookingText: String {
        [item.bookingStatus.displayName, item.providerName, item.confirmationNumber]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " · ")
    }

    private var mapURL: URL? {
        guard let location = item.location else { return nil }
        var components = URLComponents(string: "maps://")
        if let latitude = location.latitude, let longitude = location.longitude {
            components?.queryItems = [URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)")]
        } else {
            components?.queryItems = [URLQueryItem(name: "daddr", value: location.name)]
        }
        return components?.url
    }
}

private struct TripItineraryActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

@Observable
private final class ItineraryLinkDraft: Identifiable {
    let id: UUID
    var title: String
    var urlString: String

    init(id: UUID = UUID(), title: String = "", urlString: String = "") {
        self.id = id
        self.title = title
        self.urlString = urlString
    }
}

private struct ItineraryLinkDraftRow: View {
    private enum Field: Hashable {
        case label
        case url
    }

    @Bindable var draft: ItineraryLinkDraft
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Label") {
                TextField("Open Link", text: $draft.title)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .label)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .url }
                    .accessibilityIdentifier("trip.itinerary.link.\(draft.id.uuidString).label")
            }
            LabeledContent("URL") {
                TextField("Paste or type web address", text: $draft.urlString)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .url)
                    .submitLabel(.done)
                    .accessibilityIdentifier("trip.itinerary.link.\(draft.id.uuidString).url")
            }
        }
    }
}

private struct TripItineraryItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CaregiverIdentityService.currentCaregiverNameKey) private var currentCaregiverName = ""
    @AppStorage(CaregiverIdentityService.primaryCaregiverNameKey) private var primaryCaregiverName = ""

    let trip: PackingTrip
    let item: TripItineraryItem?
    let travelers: [TripTraveler]
    let choiceGroups: [TripItineraryChoiceGroup]
    let existingItems: [TripItineraryItem]
    let links: [TripItineraryLink]

    @State private var title: String
    @State private var kind: TripItineraryItemKind
    @State private var scheduleKind: TripItineraryScheduleKind
    @State private var scheduledDay: Date
    @State private var startDate: Date
    @State private var includesEndTime: Bool
    @State private var endDate: Date
    @State private var startTimeZoneIdentifier: String
    @State private var endTimeZoneIdentifier: String
    @State private var location: TripDestinationSelection?
    @State private var origin: TripDestinationSelection?
    @State private var notes: String
    @State private var bookingStatus: TripItineraryBookingStatus
    @State private var providerName: String
    @State private var confirmationNumber: String
    @State private var choiceGroupID: UUID?
    @State private var assignedCaregiverName: String
    @State private var reminderEnabled: Bool
    @State private var reminderOffsetMinutes: Int
    @State private var linkDrafts: [ItineraryLinkDraft]
    @State private var validationMessage: String?

    init(
        trip: PackingTrip,
        item: TripItineraryItem?,
        initialDay: Date?,
        initialGroup: TripItineraryChoiceGroup?,
        travelers: [TripTraveler],
        choiceGroups: [TripItineraryChoiceGroup],
        existingItems: [TripItineraryItem],
        links: [TripItineraryLink]
    ) {
        self.trip = trip
        self.item = item
        self.travelers = travelers
        self.choiceGroups = choiceGroups
        self.existingItems = existingItems
        self.links = links
        let resolvedGroup = item?.choiceGroupID.flatMap { id in choiceGroups.first { $0.id == id } } ?? initialGroup
        let day = resolvedGroup?.scheduledDay ?? item?.scheduledDay ?? initialDay ?? trip.tripCalendar.startOfDay(for: trip.startDate)
        let initialScheduleKind: TripItineraryScheduleKind
        if let resolvedGroup {
            initialScheduleKind = resolvedGroup.scheduledDay == nil
                ? .unscheduled
                : (item?.scheduleKind == .unscheduled ? .anytime : item?.scheduleKind ?? .timed)
        } else {
            initialScheduleKind = item?.scheduleKind ?? (initialDay == nil ? .unscheduled : .timed)
        }
        let initialKind = item?.kind ?? .activity
        let fallbackTimeZoneIdentifier = trip.timeZoneIdentifier.flatMap { identifier in
            TimeZone(identifier: identifier) == nil ? nil : identifier
        } ?? trip.tripTimeZone.identifier
        let initialStartTimeZoneIdentifier = item?.startTimeZoneIdentifier.flatMap { identifier in
            TimeZone(identifier: identifier) == nil ? nil : identifier
        } ?? (initialKind.supportsOrigin ? item?.origin?.timeZoneIdentifier : item?.location?.timeZoneIdentifier)
            ?? fallbackTimeZoneIdentifier
        let initialEndTimeZoneIdentifier = item?.endTimeZoneIdentifier.flatMap { identifier in
            TimeZone(identifier: identifier) == nil ? nil : identifier
        } ?? item?.location?.timeZoneIdentifier
            ?? fallbackTimeZoneIdentifier
        var startCalendar = Calendar(identifier: .gregorian)
        startCalendar.timeZone = TimeZone(identifier: initialStartTimeZoneIdentifier) ?? trip.tripTimeZone
        let defaultStart = startCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: initialKind)
        _scheduleKind = State(initialValue: initialScheduleKind)
        _scheduledDay = State(initialValue: day)
        _startDate = State(initialValue: item?.startDate ?? defaultStart)
        _includesEndTime = State(initialValue: item?.endDate != nil)
        _endDate = State(initialValue: item?.endDate ?? defaultStart.addingTimeInterval(60 * 60))
        _startTimeZoneIdentifier = State(initialValue: initialStartTimeZoneIdentifier)
        _endTimeZoneIdentifier = State(initialValue: initialEndTimeZoneIdentifier)
        _location = State(initialValue: item?.location)
        _origin = State(initialValue: item?.origin)
        _notes = State(initialValue: item?.notes ?? "")
        _bookingStatus = State(initialValue: item?.bookingStatus ?? .planned)
        _providerName = State(initialValue: item?.providerName ?? "")
        _confirmationNumber = State(initialValue: item?.confirmationNumber ?? "")
        _choiceGroupID = State(initialValue: resolvedGroup?.id)
        _assignedCaregiverName = State(initialValue: item?.assignedCaregiverName ?? "")
        _reminderEnabled = State(initialValue: item?.reminderEnabled ?? false)
        _reminderOffsetMinutes = State(initialValue: item?.reminderOffsetMinutes ?? 60)
        let itemLinks = item.map { currentItem in
            links.filter { $0.itineraryItemID == currentItem.id }
        } ?? []
        _linkDrafts = State(initialValue: itemLinks
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ItineraryLinkDraft(title: $0.title, urlString: $0.urlString) })
    }

    var body: some View {
        Form {
            Section("What") {
                LabeledContent("Title") {
                    TextField("Required", text: $title)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("trip.itinerary.editor.title")
                }
                Picker("Type", selection: $kind) {
                    ForEach(TripItineraryItemKind.allCases) { value in
                        Label(value.displayName, systemImage: value.systemImage).tag(value)
                    }
                }
                Picker("Status", selection: $bookingStatus) {
                    ForEach(TripItineraryBookingStatus.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }

            Section("When") {
                Picker("Schedule", selection: $scheduleKind) {
                    ForEach(availableScheduleKinds) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .accessibilityIdentifier("trip.itinerary.editor.schedule")
                if scheduleKind != .unscheduled {
                    DatePicker("Day", selection: $scheduledDay, in: trip.startDate...trip.endDate, displayedComponents: .date)
                        .environment(\.timeZone, trip.tripTimeZone)
                        .disabled(selectedChoiceGroup != nil)
                        .accessibilityIdentifier("trip.itinerary.editor.day")
                }
                if scheduleKind == .timed {
                    DatePicker("Start", selection: $startDate, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, startTimeZone)
                        .accessibilityIdentifier("trip.itinerary.editor.start")
                    Toggle("Add end time", isOn: $includesEndTime)
                    if includesEndTime {
                        DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, endTimeZone)
                            .accessibilityIdentifier("trip.itinerary.editor.end")
                    }
                    LabeledContent(kind.supportsOrigin ? "Departure time zone" : "Time zone", value: timeZoneName(startTimeZone))
                    if kind.supportsOrigin, endTimeZone.identifier != startTimeZone.identifier {
                        LabeledContent("Arrival time zone", value: timeZoneName(endTimeZone))
                    }
                }
                if selectedChoiceGroup != nil {
                    Text("The option group controls whether this item belongs to a specific day or Ideas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if kind.supportsOrigin {
                Section("Route") {
                    destinationLink(
                        title: "From",
                        selection: origin,
                        accessibilityIdentifier: "trip.itinerary.editor.origin"
                    ) { origin = $0 }
                    destinationLink(
                        title: "To",
                        selection: location,
                        accessibilityIdentifier: "trip.itinerary.editor.location"
                    ) { location = $0 }
                }
            } else {
                Section("Place") {
                    destinationLink(
                        title: "Location",
                        selection: location,
                        accessibilityIdentifier: "trip.itinerary.editor.location"
                    ) { location = $0 }
                }
            }

            Section("Booking Details") {
                LabeledContent("Provider or property") {
                    TextField("Optional", text: $providerName)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("trip.itinerary.editor.provider")
                }
                LabeledContent("Confirmation number") {
                    TextField("Optional", text: $confirmationNumber)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("trip.itinerary.editor.confirmation")
                }
            }

            Section("Notes") {
                TextField("Add details, instructions, or backup context", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("trip.itinerary.editor.notes")
            }

            Section("Planning") {
                Picker("Option group", selection: $choiceGroupID) {
                    Text("None").tag(UUID?.none)
                    ForEach(choiceGroups) { group in
                        Text(group.title).tag(Optional(group.id))
                    }
                }
                .accessibilityIdentifier("trip.itinerary.editor.option-group")
                Picker("Assigned to", selection: $assignedCaregiverName) {
                    Text("Anyone").tag("")
                    ForEach(assignmentNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                if scheduleKind == .timed {
                    Toggle("Reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Picker("Notify", selection: $reminderOffsetMinutes) {
                            Text("At start time").tag(0)
                            Text("15 minutes before").tag(15)
                            Text("30 minutes before").tag(30)
                            Text("1 hour before").tag(60)
                            Text("2 hours before").tag(120)
                            Text("1 day before").tag(1_440)
                        }
                    }
                }
            }

            Section("Links") {
                ForEach(linkDrafts) { draft in
                    ItineraryLinkDraftRow(draft: draft)
                }
                .onDelete { linkDrafts.remove(atOffsets: $0) }
                Button("Add Link", systemImage: "link.badge.plus") {
                    linkDrafts.append(ItineraryLinkDraft())
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("trip.itinerary.editor")
        .navigationTitle(item == nil ? "Add Itinerary Item" : "Edit Itinerary Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("trip.itinerary.editor.save")
            }
        }
        .onChange(of: scheduledDay) { oldDay, newDay in
            startDate = moving(startDate, from: oldDay, to: newDay, timeZone: startTimeZone)
            endDate = moving(endDate, from: oldDay, to: newDay, timeZone: endTimeZone)
        }
        .onChange(of: scheduleKind) { _, value in
            if value != .timed { reminderEnabled = false }
        }
        .onChange(of: kind) { _, value in
            if value.supportsOrigin {
                setStartTimeZone(origin?.timeZoneIdentifier)
                setEndTimeZone(location?.timeZoneIdentifier)
            } else {
                setStartTimeZone(location?.timeZoneIdentifier)
                setEndTimeZone(location?.timeZoneIdentifier)
            }
        }
        .onChange(of: origin) { _, value in
            guard kind.supportsOrigin else { return }
            setStartTimeZone(value?.timeZoneIdentifier)
        }
        .onChange(of: location) { _, value in
            if kind.supportsOrigin {
                setEndTimeZone(value?.timeZoneIdentifier)
            } else {
                setStartTimeZone(value?.timeZoneIdentifier)
                setEndTimeZone(value?.timeZoneIdentifier)
            }
        }
        .onChange(of: choiceGroupID) { _, _ in
            alignWithSelectedChoiceGroup()
        }
        .onChange(of: reminderEnabled) { _, enabled in
            if enabled {
                Task { _ = await NotificationManager.shared.requestAuthorization() }
            }
        }
        .alert("Check Itinerary Item", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var assignmentNames: [String] {
        var values = travelers.filter { $0.kind == .adult }.map(\.displayName).filter { !$0.isEmpty }
        values.append(contentsOf: CaregiverIdentityService.familySyncCaregiverNames())
        values.append(contentsOf: existingItems.compactMap(\.assignedCaregiverName))
        if let createdBy = trip.createdBy { values.append(createdBy) }
        let caregiver = CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: primaryCaregiverName,
            fallback: ""
        )
        if !caregiver.isEmpty { values.append(caregiver) }
        return Array(Set(values)).sorted()
    }

    private var selectedChoiceGroup: TripItineraryChoiceGroup? {
        choiceGroupID.flatMap { id in choiceGroups.first { $0.id == id } }
    }

    private var availableScheduleKinds: [TripItineraryScheduleKind] {
        guard let selectedChoiceGroup else { return TripItineraryScheduleKind.allCases }
        return selectedChoiceGroup.scheduledDay == nil
            ? [.unscheduled]
            : TripItineraryScheduleKind.allCases.filter { $0 != .unscheduled }
    }

    private var startTimeZone: TimeZone {
        TimeZone(identifier: startTimeZoneIdentifier) ?? trip.tripTimeZone
    }

    private var endTimeZone: TimeZone {
        TimeZone(identifier: endTimeZoneIdentifier) ?? trip.tripTimeZone
    }

    private func timeZoneName(_ timeZone: TimeZone) -> String {
        timeZone.localizedName(for: .shortStandard, locale: .current) ?? timeZone.identifier
    }

    private func alignWithSelectedChoiceGroup() {
        guard let selectedChoiceGroup else { return }
        guard let groupDay = selectedChoiceGroup.scheduledDay else {
            scheduleKind = .unscheduled
            reminderEnabled = false
            return
        }
        scheduledDay = groupDay
        if scheduleKind == .unscheduled {
            scheduleKind = .anytime
        }
    }

    @ViewBuilder
    private func destinationLink(
        title: String,
        selection: TripDestinationSelection?,
        accessibilityIdentifier: String,
        onSelect: @escaping (TripDestinationSelection?) -> Void
    ) -> some View {
        NavigationLink {
            TripDestinationPickerView(selection: selection, onSelect: onSelect)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(selection?.name ?? "Choose")
                    .foregroundStyle(selection == nil ? .secondary : .primary)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func moving(_ value: Date, from oldDay: Date, to newDay: Date, timeZone: TimeZone) -> Date {
        TripItineraryService.movingScheduledDate(
            value,
            from: oldDay,
            to: newDay,
            sourceScheduleCalendar: trip.tripCalendar,
            destinationScheduleCalendar: trip.tripCalendar,
            valueTimeZoneIdentifier: timeZone.identifier
        )
    }

    private func setStartTimeZone(_ identifier: String?) {
        let newTimeZone = identifier.flatMap(TimeZone.init(identifier:)) ?? trip.tripTimeZone
        guard newTimeZone.identifier != startTimeZone.identifier else { return }
        startDate = TripItineraryService.date(
            startDate,
            preservingWallClockFrom: startTimeZone,
            to: newTimeZone
        )
        startTimeZoneIdentifier = newTimeZone.identifier
    }

    private func setEndTimeZone(_ identifier: String?) {
        let newTimeZone = identifier.flatMap(TimeZone.init(identifier:)) ?? trip.tripTimeZone
        guard newTimeZone.identifier != endTimeZone.identifier else { return }
        endDate = TripItineraryService.date(
            endDate,
            preservingWallClockFrom: endTimeZone,
            to: newTimeZone
        )
        endTimeZoneIdentifier = newTimeZone.identifier
    }

    private func save() {
        let preparedStart = scheduleKind == .timed ? startDate : nil
        let preparedEnd = scheduleKind == .timed && includesEndTime ? endDate : nil
        let input = TripItineraryItemInput(
            title: title,
            kind: kind,
            scheduleKind: scheduleKind,
            scheduledDay: scheduleKind == .unscheduled ? nil : scheduledDay,
            startDate: preparedStart,
            endDate: preparedEnd,
            startTimeZoneIdentifier: startTimeZoneIdentifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            location: location,
            origin: origin,
            notes: notes,
            bookingStatus: bookingStatus,
            providerName: providerName,
            confirmationNumber: confirmationNumber,
            choiceGroupID: choiceGroupID,
            assignedCaregiverName: assignedCaregiverName.nilIfEmpty,
            reminderEnabled: reminderEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes,
            links: linkDrafts.filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.map { TripItineraryLinkInput(title: $0.title, urlString: $0.urlString) }
        )
        if let message = TripItineraryService.validationMessage(for: input, trip: trip, choiceGroups: choiceGroups) {
            validationMessage = message
            return
        }
        let succeeded: Bool
        if let item {
            succeeded = TripItineraryService.updateItem(
                item,
                input: input,
                trip: trip,
                choiceGroups: choiceGroups,
                existingLinks: links,
                context: modelContext
            )
        } else {
            succeeded = TripItineraryService.createItem(
                input: input,
                trip: trip,
                choiceGroups: choiceGroups,
                existingItems: existingItems,
                context: modelContext
            ) != nil
        }
        if succeeded {
            dismiss()
        } else {
            validationMessage = "The item couldn’t be saved. Please try again."
        }
    }
}

private struct TripItineraryChoiceGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: PackingTrip
    let group: TripItineraryChoiceGroup?
    let existingGroups: [TripItineraryChoiceGroup]
    let items: [TripItineraryItem]

    @State private var title: String
    @State private var notes: String
    @State private var hasDay: Bool
    @State private var scheduledDay: Date
    @State private var failureMessage: String?
    @State private var showingDeleteConfirmation = false

    init(
        trip: PackingTrip,
        group: TripItineraryChoiceGroup?,
        existingGroups: [TripItineraryChoiceGroup],
        items: [TripItineraryItem]
    ) {
        self.trip = trip
        self.group = group
        self.existingGroups = existingGroups
        self.items = items
        _title = State(initialValue: group?.title ?? "")
        _notes = State(initialValue: group?.notes ?? "")
        _hasDay = State(initialValue: group?.scheduledDay != nil)
        _scheduledDay = State(initialValue: group?.scheduledDay ?? trip.startDate)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Title") {
                    TextField("Required", text: $title)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("trip.itinerary.group-editor.title")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Decision notes")
                        .font(.subheadline)
                    TextField("For example, choose after checking the weather", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("trip.itinerary.group-editor.notes")
                }
            } header: {
                Text("Group Details")
            } footer: {
                Text("Use groups for mutually exclusive plans, such as boat day or a rainy-day movie. Select the final choice from the itinerary.")
            }
            Section("Day") {
                Toggle("Assign to a day", isOn: $hasDay)
                if hasDay {
                    DatePicker("Day", selection: $scheduledDay, in: trip.startDate...trip.endDate, displayedComponents: .date)
                        .environment(\.timeZone, trip.tripTimeZone)
                        .accessibilityIdentifier("trip.itinerary.group-editor.day")
                }
            }
            if group != nil {
                Section {
                    Button("Delete Option Group", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } footer: {
                    Text("Its itinerary items will remain and move out of the group.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("trip.itinerary.group-editor")
        .navigationTitle(group == nil ? "New Option Group" : "Edit Option Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("trip.itinerary.group-editor.save")
            }
        }
        .alert("Couldn’t Save Group", isPresented: Binding(
            get: { failureMessage != nil },
            set: { if !$0 { failureMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "Please try again.")
        }
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete Option Group?",
            message: "The itinerary items will remain and move out of this group.",
            systemImage: "trash.fill",
            tint: .red,
            options: group.map { group in
                [AppActionSheetOption(
                    title: "Delete Option Group",
                    subtitle: group.title,
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    if TripItineraryService.deleteChoiceGroup(
                        group,
                        trip: trip,
                        items: items,
                        context: modelContext
                    ) {
                        dismiss()
                    } else {
                        failureMessage = "The option group couldn’t be deleted."
                    }
                }]
            } ?? []
        )
    }

    private func save() {
        let day = hasDay ? scheduledDay : nil
        let succeeded: Bool
        if let group {
            succeeded = TripItineraryService.updateChoiceGroup(
                group,
                title: title,
                notes: notes,
                scheduledDay: day,
                trip: trip,
                items: items,
                context: modelContext
            )
        } else {
            succeeded = TripItineraryService.createChoiceGroup(
                title: title,
                notes: notes,
                scheduledDay: day,
                trip: trip,
                existingGroups: existingGroups,
                context: modelContext
            ) != nil
        }
        if succeeded {
            dismiss()
        } else {
            failureMessage = "The option group couldn’t be saved."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Color {
    static let itineraryAction = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.38, green: 0.72, blue: 1, alpha: 1)
        }
        return UIColor(red: 0, green: 0.31, blue: 0.68, alpha: 1)
    })
}
