import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct TripsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let household: Household
    let trips: [PackingTrip]
    let travelers: [TripTraveler]
    let items: [PackingItem]
    let profiles: [CareProfile]
    let openTrip: (UUID) -> Void

    @State private var showingNewTrip = false

    private var activeTrips: [PackingTrip] {
        trips
            .filter { $0.householdID == household.id && !$0.isArchived && $0.status == .upcoming }
            .sorted { ($0.startDate, $0.title) < ($1.startDate, $1.title) }
    }

    private var completedTrips: [PackingTrip] {
        trips
            .filter { $0.householdID == household.id && !$0.isArchived && $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.endDate) > ($1.completedAt ?? $1.endDate) }
    }

    private var archivedTrips: [PackingTrip] {
        trips
            .filter { $0.householdID == household.id && $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        let travelersByTripID = Dictionary(grouping: travelers, by: \.tripID)
        let itemsByTripID = Dictionary(grouping: items, by: \.tripID)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                if activeTrips.isEmpty {
                    ContentUnavailableView {
                        Label("No Upcoming Trips", systemImage: "suitcase.rolling")
                    } description: {
                        Text("Create a trip to generate an editable packing list for adults, children, and dogs.")
                    } actions: {
                        Button("Plan a Trip") { showingNewTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upcoming")
                            .font(.headline)
                        ForEach(activeTrips) { trip in
                            Button {
                                openTrip(trip.id)
                            } label: {
                                PackingTripRow(
                                    trip: trip,
                                    travelers: travelersByTripID[trip.id] ?? [],
                                    items: itemsByTripID[trip.id] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("trips.row.\(trip.id.uuidString)")
                        }
                    }
                }

                if !completedTrips.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Completed")
                            .font(.headline)
                        ForEach(completedTrips.prefix(5)) { trip in
                            Button {
                                openTrip(trip.id)
                            } label: {
                                PackingTripRow(
                                    trip: trip,
                                    travelers: travelersByTripID[trip.id] ?? [],
                                    items: itemsByTripID[trip.id] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !archivedTrips.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Archived")
                            .font(.headline)
                        ForEach(archivedTrips) { trip in
                            Button {
                                openTrip(trip.id)
                            } label: {
                                PackingTripRow(
                                    trip: trip,
                                    travelers: travelersByTripID[trip.id] ?? [],
                                    items: itemsByTripID[trip.id] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("trips.home")
        .sheet(isPresented: $showingNewTrip) {
            NavigationStack {
                PackingTripCreationView(
                    household: household,
                    profiles: profiles.filter { !$0.isArchived },
                    existingTrips: trips,
                    onCreated: { trip in
                        showingNewTrip = false
                        openTrip(trip.id)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                headerCopy
                newTripButton
            }
        } else {
            HStack {
                headerCopy
                Spacer()
                newTripButton
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trips")
                .font(.title2.bold())
            Text("Pack together without losing track of who needs what.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var newTripButton: some View {
        Button {
            showingNewTrip = true
        } label: {
            Label("New Trip", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("trips.new")
    }
}

private struct PackingTripRow: View {
    let trip: PackingTrip
    let travelers: [TripTraveler]
    let items: [PackingItem]

    private var relevantItems: [PackingItem] { items.filter { $0.state != .notNeeded } }
    private var packedCount: Int { relevantItems.filter { $0.state == .packed }.count }
    private var progress: Double {
        guard !relevantItems.isEmpty else { return 0 }
        return Double(packedCount) / Double(relevantItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: trip.travelMode.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 38, height: 38)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let destination = trip.destinationSummary {
                        Label(destination, systemImage: "mappin.and.ellipse")
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

            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : .blue)
            HStack {
                Text("\(packedCount) of \(relevantItems.count) packed")
                Spacer()
                Text(travelerText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.line, lineWidth: 0.6)
        }
    }

    private var dateText: String {
        if trip.isSingleDay {
            return trip.formattedDate(trip.startDate)
        }
        return "\(trip.formattedDate(trip.startDate)) – \(trip.formattedDate(trip.endDate))"
    }

    private var travelerText: String {
        "\(travelers.count) \(travelers.count == 1 ? "traveler" : "travelers")"
    }
}

private struct AdultTravelerDraft: Identifiable {
    var id = UUID()
    var name: String
}

private struct TripDestinationDraft: Identifiable {
    var id: UUID
    var destination: TripDestinationSelection?
    var startDate: Date

    init(
        id: UUID = UUID(),
        destination: TripDestinationSelection? = nil,
        startDate: Date
    ) {
        self.id = id
        self.destination = destination
        self.startDate = startDate
    }

    init(stop: TripDestinationStop) {
        self.id = stop.id
        self.destination = stop.destination
        self.startDate = stop.startDate
    }
}

private struct PackingTripActivitiesSection: View {
    @Binding var activities: Set<PackingTripActivity>

    var body: some View {
        Section {
            NavigationLink {
                PackingTripActivitiesSelectionView(activities: $activities)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose activities")
                        Text(selectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .accessibilityLabel("Activities")
            .accessibilityValue(accessibilitySummary)
            .accessibilityIdentifier("trip.activities.open")
        } header: {
            Text("Activities")
        } footer: {
            Text("Selections tailor clothing and gear suggestions for this trip.")
        }
    }

    private var selectedActivities: [PackingTripActivity] {
        PackingTripActivity.allCases.filter(activities.contains)
    }

    private var selectionSummary: String {
        guard !selectedActivities.isEmpty else { return "None selected" }
        let visibleNames = selectedActivities.prefix(3).map(\.displayName)
        let remainingCount = selectedActivities.count - visibleNames.count
        if remainingCount == 0 {
            return visibleNames.joined(separator: ", ")
        }
        return "\(visibleNames.joined(separator: ", ")) +\(remainingCount) more"
    }

    private var accessibilitySummary: String {
        guard !selectedActivities.isEmpty else { return "None selected" }
        return "\(selectedActivities.count) selected: \(selectedActivities.map(\.displayName).joined(separator: ", "))"
    }
}

private struct PackingTripActivitiesSelectionView: View {
    @Binding var activities: Set<PackingTripActivity>

    private let columns = [
        GridItem(.adaptive(minimum: 138), spacing: 10)
    ]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(PackingTripActivity.allCases) { activity in
                        activityButton(activity)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(selectionCountText)
            } footer: {
                Text("Choose all that apply. You can change these at any time.")
            }
        }
        .navigationTitle("Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    activities.removeAll()
                }
                .disabled(activities.isEmpty)
            }
        }
    }

    private var selectionCountText: String {
        activities.count == 1 ? "1 selected" : "\(activities.count) selected"
    }

    private func activityButton(_ activity: PackingTripActivity) -> some View {
        let isSelected = activities.contains(activity)
        return Button {
            if isSelected {
                activities.remove(activity)
            } else {
                activities.insert(activity)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: activity.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
                }

                Text(activity.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activity.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("trip.activity.\(activity.rawValue)")
    }
}

struct PackingTripCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationManager = NotificationManager.shared
    let household: Household
    let profiles: [CareProfile]
    let existingTrips: [PackingTrip]
    let onCreated: (PackingTrip) -> Void

    @State private var title = ""
    @State private var destinationDrafts = [TripDestinationDraft]()
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var travelMode = PackingTravelMode.car
    @State private var lodgingType = PackingLodgingType.home
    @State private var laundryAvailable = false
    @State private var activities = Set<PackingTripActivity>()
    @State private var adults = [AdultTravelerDraft(name: CaregiverIdentityService.currentCaregiverName())]
    @State private var selectedProfileIDs = Set<UUID>()
    @State private var includeStarterList = true
    @State private var weatherSuggestionsEnabled = true
    @State private var reminderEnabled = true
    @State private var finalCheckEnabled = true
    @State private var reminderDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
    @State private var finalCheckDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var saveAttempted = false
    @State private var creationErrorMessage: String?
    private let tripTimeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()

    private var tripTimeZone: TimeZone {
        TimeZone(identifier: tripTimeZoneIdentifier) ?? .current
    }

    private var tripCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tripTimeZone
        return calendar
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate >= startDate
            && (!adults.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                || !selectedProfileIDs.isEmpty)
            && TripPackingService.reminderDatesAreValid(
                reminderDate: reminderEnabled ? reminderDate : nil,
                finalCheckDate: finalCheckEnabled ? finalCheckDate : nil
            )
            && destinationsAreValid
    }

    private var destinationStops: [TripDestinationStop] {
        destinationDrafts.compactMap { draft in
            draft.destination.map {
                TripDestinationStop(id: draft.id, destination: $0, startDate: draft.startDate)
            }
        }
        .sorted { ($0.startDate, $0.id.uuidString) < ($1.startDate, $1.id.uuidString) }
    }

    private var destinationsAreValid: Bool {
        destinationStops.count == destinationDrafts.count
            && TripPackingService.destinationStopsAreValid(
                destinationStops,
                tripStartDate: startDate,
                tripEndDate: endDate,
                timeZoneIdentifier: tripTimeZoneIdentifier
            )
    }

    var body: some View {
        Form {
            Section("Trip") {
                LabeledContent("Trip name") {
                    TextField("Required", text: $title)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("trip.create.name")
                }
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    .environment(\.timeZone, tripTimeZone)
                DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .environment(\.timeZone, tripTimeZone)
                Picker("Travel", selection: $travelMode) {
                    ForEach(PackingTravelMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                    }
                }
                Picker("Stay", selection: $lodgingType) {
                    ForEach(PackingLodgingType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Toggle("Laundry available", isOn: $laundryAvailable)
            }

            TripDestinationsEditor(
                destinations: destinationDrafts,
                tripStartDate: startDate,
                tripEndDate: endDate,
                timeZone: tripTimeZone,
                onChange: { destinationDrafts = $0 }
            )

            Section("Travelers") {
                ForEach($adults) { $adult in
                    LabeledContent {
                        HStack {
                            TextField("Required", text: $adult.name)
                                .multilineTextAlignment(.trailing)
                            if adults.count > 1 {
                                Button(role: .destructive) {
                                    adults.removeAll { $0.id == adult.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove adult")
                            }
                        }
                    } label: {
                        Label("Adult name", systemImage: "person.fill")
                    }
                }
                Button("Add Adult", systemImage: "person.badge.plus") {
                    adults.append(AdultTravelerDraft(name: ""))
                }
                ForEach(profiles) { profile in
                    Toggle(isOn: Binding(
                        get: { selectedProfileIDs.contains(profile.id) },
                        set: { selected in
                            if selected { selectedProfileIDs.insert(profile.id) }
                            else { selectedProfileIDs.remove(profile.id) }
                        }
                    )) {
                        Label(
                            profile.name,
                            systemImage: profile.profileType == .dog
                                ? "pawprint.fill"
                                : profile.profileType == .adult ? "person.fill" : "figure.child"
                        )
                    }
                }
            }

            PackingTripActivitiesSection(activities: $activities)

            Section("Starter list") {
                Toggle("Generate a starter packing list", isOn: $includeStarterList)
                if includeStarterList {
                    Text("Suggestions use trip length, laundry, travel mode, activities, and traveler type. Everything remains editable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Weather suggestions", isOn: $weatherSuggestionsEnabled)
                if weatherSuggestionsEnabled {
                    Text(destinationStops.contains(where: { $0.destination.supportsWeather })
                         ? "Each destination gets its own forecast as its dates enter WeatherKit's forecast window."
                         : "Choose destination search results with map pins to enable forecasts. Manual destinations remain available offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Reminders") {
                Toggle("Start packing reminder", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("Packing reminder", selection: $reminderDate)
                }
                Toggle("Final check reminder", isOn: $finalCheckEnabled)
                if finalCheckEnabled {
                    DatePicker("Final check", selection: $finalCheckDate)
                }
                PackingReminderPermissionView(
                    status: notificationManager.authorizationStatus,
                    hasEnabledReminders: reminderEnabled || finalCheckEnabled,
                    hasFutureReminder: (reminderEnabled && reminderDate > Date())
                        || (finalCheckEnabled && finalCheckDate > Date()),
                    requestPermission: {
                        Task { _ = await notificationManager.requestAuthorization() }
                    }
                )
            }

            Section("Notes") {
                PackingNotesField(
                    text: $notes,
                    lineLimit: 3...6,
                    accessibilityIdentifier: "trip.create.notes"
                )
            }

            if saveAttempted && !canSave {
                Section {
                    Text("Add a trip name and at least one traveler, review destination starting dates, keep the end date on or after the start, and schedule the start-packing reminder before the final check.")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if let creationErrorMessage {
                Section {
                    Text(creationErrorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("New Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { createTrip() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("trip.create.save")
            }
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
            if !destinationDrafts.isEmpty {
                destinationDrafts[0].startDate = newValue
            }
            reminderDate = tripCalendar.date(byAdding: .day, value: -3, to: newValue) ?? newValue
            finalCheckDate = tripCalendar.date(byAdding: .day, value: -1, to: newValue) ?? newValue
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    private func createTrip() {
        saveAttempted = true
        creationErrorMessage = nil
        guard canSave else { return }
        var travelerInputs = adults.compactMap { adult -> TripTravelerInput? in
            let name = adult.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return TripTravelerInput(kind: .adult, profileID: nil, displayName: name)
        }
        travelerInputs.append(contentsOf: profiles.filter { selectedProfileIDs.contains($0.id) }.map {
            TripTravelerInput(
                kind: $0.profileType.tripTravelerKind,
                profileID: $0.id,
                displayName: $0.name
            )
        })
        let input = PackingTripInput(
            title: title,
            destination: destinationStops.first?.destination,
            startDate: startDate,
            endDate: endDate,
            travelMode: travelMode,
            lodgingType: lodgingType,
            laundryAvailable: laundryAvailable,
            activities: activities,
            travelers: travelerInputs,
            includeStarterList: includeStarterList,
            weatherSuggestionsEnabled: weatherSuggestionsEnabled,
            reminderDate: reminderEnabled ? reminderDate : nil,
            finalCheckDate: finalCheckEnabled ? finalCheckDate : nil,
            notes: notes,
            timeZoneIdentifier: tripTimeZoneIdentifier,
            destinationStops: destinationStops
        )
        guard let trip = TripPackingService.createTrip(
            input: input,
            householdID: household.id,
            existingTrips: existingTrips,
            context: modelContext
        ) else {
            creationErrorMessage = "The trip could not be saved. Please review the details and try again."
            return
        }
        onCreated(trip)
    }
}

private enum PackingListFilter: String, CaseIterable, Identifiable {
    case remaining
    case all
    case packed
    case toBuy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .remaining: "Remaining"
        case .all: "All"
        case .packed: "Packed"
        case .toBuy: "To Buy"
        }
    }
}

struct PackingListDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CaregiverIdentityService.currentCaregiverNameKey) private var currentCaregiverName = ""
    @AppStorage(CaregiverIdentityService.primaryCaregiverNameKey) private var primaryCaregiverName = ""
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

    @State private var filter = PackingListFilter.remaining
    @State private var showingNewItem = false
    @State private var editingItem: PackingItem?
    @State private var shoppingItem: PackingItem?
    @State private var showingBags = false
    @State private var showingTravelers = false
    @State private var showingTripEditor = false
    @State private var weatherForecasts = [TripDestinationWeatherForecast]()
    @State private var weatherIsLoading = false
    @State private var weatherRefreshToken = 0
    @State private var forceWeatherRefresh = false
    @State private var weatherSuggestionMessage: String?
    @State private var showingWeatherDetails = false
    @State private var showingWeatherAttribution = false
    @State private var showingArchiveConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var itemPendingDelete: PackingItem?
    @State private var actionFailureMessage: String?
    @State private var itemEditMode = EditMode.inactive

    private var travelers: [TripTraveler] {
        allTravelers.filter { $0.tripID == trip.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var bags: [PackingBag] {
        allBags.filter { $0.tripID == trip.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var items: [PackingItem] {
        allItems.filter { $0.tripID == trip.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var relevantItems: [PackingItem] { items.filter { $0.state != .notNeeded } }
    private var packedCount: Int { relevantItems.filter { $0.state == .packed }.count }
    private var progress: Double {
        guard !relevantItems.isEmpty else { return 0 }
        return Double(packedCount) / Double(relevantItems.count)
    }
    private var activeCaregiverName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: primaryCaregiverName,
            fallback: ""
        )
    }
    private var myRemainingItems: [PackingItem] {
        guard !activeCaregiverName.isEmpty else { return [] }
        return items.filter {
            $0.state == .needed
                && CaregiverIdentityService.namesMatch(
                    $0.assignedCaregiverName,
                    activeCaregiverName
                )
        }
    }

    private var visibleItems: [PackingItem] {
        switch filter {
        case .remaining: items.filter { $0.state == .needed }
        case .all: items
        case .packed: items.filter { $0.state == .packed }
        case .toBuy: items.filter { $0.needsPurchase && $0.state != .notNeeded }
        }
    }

    private var emptyListDescription: String {
        if trip.isArchived {
            return filter == .remaining
                ? "Review the full archived list."
                : "Choose another filter to review this archived list."
        }
        return filter == .remaining
            ? "Review the full list or mark the trip complete."
            : "Choose another filter or add an item."
    }

    private var canReorderVisibleItems: Bool {
        !trip.isArchived && travelerSections.contains { $0.items.count > 1 }
    }

    private var combinedWeatherSuggestions: [PackingSuggestion] {
        let snapshots = weatherForecasts.compactMap(\.snapshot)
        return TripPackingSuggestionEngine.weatherSuggestions(
            rainLikely: snapshots.contains(where: \.rainLikely),
            coldWeather: snapshots.contains(where: \.coldWeather),
            hotOrHighUV: snapshots.contains(where: \.hotOrHighUV)
        )
    }

    private var weatherAttribution: TripWeatherSnapshot? {
        weatherForecasts.compactMap(\.snapshot).first
    }

    private var weatherLastUpdatedAt: Date? {
        weatherForecasts.compactMap { $0.snapshot?.fetchedAt }.min()
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if trip.isArchived {
                        Label("Archived · Read only", systemImage: "archivebox.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("trip.archived.read-only")
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dateText)
                                .font(.subheadline.weight(.semibold))
                            ForEach(trip.destinationWeatherWindows) { window in
                                Label(
                                    "\(window.destination.name) · \(destinationDateText(window))",
                                    systemImage: "mappin.and.ellipse"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.title2.bold())
                            .foregroundStyle(progress >= 1 ? .green : .blue)
                    }
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? .green : .blue)
                    HStack {
                        Text("\(packedCount) packed")
                        Spacer()
                        Text("\(items.filter { $0.state == .needed }.count) remaining")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !myRemainingItems.isEmpty {
                        Label(
                            "\(myRemainingItems.count) assigned to you",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityIdentifier("trip.assignments.mine")
                    }
                }
                .padding(.vertical, 4)
            }

            if trip.weatherSuggestionsEnabled,
               !trip.destinationStops.isEmpty {
                Section("Weather") {
                    weatherContent
                }
            }

            Section {
                Picker("Show", selection: $filter) {
                    ForEach(PackingListFilter.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    filter == .remaining ? "Everything Is Packed" : "No Matching Items",
                    systemImage: filter == .remaining ? "checkmark.seal.fill" : "line.3.horizontal.decrease.circle",
                    description: Text(emptyListDescription)
                )
            } else {
                ForEach(travelerSections, id: \.key) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            PackingItemRow(
                                item: item,
                                bag: item.bagID.flatMap { id in bags.first { $0.id == id } },
                                isReadOnly: trip.isArchived,
                                toggle: {
                                    guard !trip.isArchived else { return }
                                    TripPackingService.setState(
                                        item,
                                        state: item.state == .packed ? .needed : .packed,
                                        trip: trip,
                                        context: modelContext
                                    )
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !trip.isArchived else { return }
                                editingItem = item
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !trip.isArchived {
                                    Button(role: .destructive) {
                                        itemPendingDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        TripPackingService.setState(item, state: .notNeeded, trip: trip, context: modelContext)
                                    } label: {
                                        Label("Not Needed", systemImage: "minus.circle")
                                    }
                                    .tint(.gray)
                                }
                            }
                            .contextMenu {
                                if !trip.isArchived {
                                    Button("Edit", systemImage: "pencil") { editingItem = item }
                                    if item.relatedShoppingItemID.map({ relatedID in
                                        shoppingItems.contains { $0.id == relatedID }
                                    }) != true {
                                        Button("Add to Shopping", systemImage: "cart.badge.plus") {
                                            shoppingItem = item
                                        }
                                    }
                                    Button("Mark Not Needed", systemImage: "minus.circle") {
                                        TripPackingService.setState(item, state: .notNeeded, trip: trip, context: modelContext)
                                    }
                                }
                            }
                        }
                        .onMove { source, destination in
                            guard !trip.isArchived else { return }
                            TripPackingService.reorderItems(
                                section.items,
                                from: source,
                                to: destination,
                                trip: trip,
                                allItems: items,
                                context: modelContext
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $itemEditMode)
        .accessibilityIdentifier("trip.detail")
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if canReorderVisibleItems {
                        Button {
                            withAnimation {
                                itemEditMode = itemEditMode.isEditing ? .inactive : .active
                            }
                        } label: {
                            Image(systemName: itemEditMode.isEditing ? "checkmark" : "arrow.up.arrow.down")
                                .frame(width: 44, height: 36)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(itemEditMode.isEditing ? "Done" : "Reorder")
                        .accessibilityIdentifier("trip.items.reorder-mode")
                    }
                    if !trip.isArchived {
                        Button {
                            guard !showingNewItem else { return }
                            showingNewItem = true
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 44, height: 36)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Add Packing Item")
                        .accessibilityIdentifier("trip.item.add")
                    }
                    Menu {
                        if !trip.isArchived {
                            Button("Edit Trip", systemImage: "pencil") { showingTripEditor = true }
                            Button("Manage Travelers", systemImage: "person.2") { showingTravelers = true }
                            Button("Manage Bags", systemImage: "bag") { showingBags = true }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            if TripPackingService.duplicateTrip(
                                trip,
                                travelers: allTravelers,
                                bags: allBags,
                                items: allItems,
                                itineraryChoiceGroups: itineraryChoiceGroups,
                                itineraryItems: itineraryItems,
                                itineraryLinks: itineraryLinks,
                                existingTrips: allTrips,
                                context: modelContext
                            ) != nil {
                                dismiss()
                            } else {
                                actionFailureMessage = "The trip couldn’t be duplicated. Please try again."
                            }
                        }
                        if trip.isArchived {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                TripPackingService.restore(trip, context: modelContext)
                            }
                        } else if trip.status == .completed {
                            Button("Reopen Trip", systemImage: "arrow.uturn.backward") {
                                TripPackingService.setCompleted(trip, completed: false, context: modelContext)
                            }
                        } else {
                            Button("Mark Complete", systemImage: "checkmark.circle") {
                                TripPackingService.setCompleted(trip, completed: true, context: modelContext)
                            }
                        }
                        if !trip.isArchived {
                            Divider()
                            Button("Archive", systemImage: "archivebox", role: .destructive) {
                                showingArchiveConfirmation = true
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
        .onChange(of: canReorderVisibleItems) { _, canReorder in
            if !canReorder {
                itemEditMode = .inactive
            }
        }
        .sheet(isPresented: $showingNewItem) {
            NavigationStack {
                PackingItemEditorView(
                    trip: trip,
                    item: nil,
                    travelers: travelers,
                    bags: bags,
                    existingItems: items
                )
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                PackingItemEditorView(
                    trip: trip,
                    item: item,
                    travelers: travelers,
                    bags: bags,
                    existingItems: items
                )
            }
        }
        .sheet(item: $shoppingItem) { item in
            NavigationStack {
                PackingShoppingListPicker(
                    item: item,
                    trip: trip,
                    lists: shoppingLists.filter { $0.householdID == trip.householdID && !$0.isArchived },
                    shoppingItems: shoppingItems
                )
            }
        }
        .sheet(isPresented: $showingBags) {
            NavigationStack {
                PackingBagsEditorView(
                    trip: trip,
                    travelers: travelers,
                    bags: bags,
                    items: items
                )
            }
        }
        .sheet(isPresented: $showingTravelers) {
            NavigationStack {
                PackingTravelersEditorView(
                    trip: trip,
                    travelers: travelers,
                    bags: bags,
                    items: items,
                    profiles: profiles
                )
            }
        }
        .sheet(isPresented: $showingTripEditor) {
            NavigationStack {
                PackingTripEditorView(trip: trip)
            }
        }
        .sheet(isPresented: $showingWeatherDetails) {
            TripWeatherDetailSheet(
                trip: trip,
                forecasts: weatherForecasts,
                isRefreshing: weatherIsLoading,
                refresh: refreshWeather
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingWeatherAttribution) {
            if let weatherAttribution {
                TripWeatherAttributionSheet(snapshot: weatherAttribution)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task(id: weatherRequestID) {
            await loadWeather()
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(6 * 60 * 60))
                } catch {
                    return
                }
                weatherRefreshToken += 1
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, trip.weatherSuggestionsEnabled {
                weatherRefreshToken += 1
            }
        }
        .alert("Weather suggestions", isPresented: Binding(
            get: { weatherSuggestionMessage != nil },
            set: { if !$0 { weatherSuggestionMessage = nil } }
        )) {
            Button("OK") { weatherSuggestionMessage = nil }
        } message: {
            Text(weatherSuggestionMessage ?? "")
        }
        .modifier(
            PackingListActionConfirmationModifier(
                showingArchiveConfirmation: $showingArchiveConfirmation,
                itemPendingDelete: $itemPendingDelete,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                tripTitle: trip.title,
                archiveTrip: {
                    if TripPackingService.archive(trip, context: modelContext) {
                        dismiss()
                    } else {
                        actionFailureMessage = "The trip couldn’t be archived. Please try again."
                    }
                },
                deleteItem: { item in
                    TripPackingService.deleteItem(item, trip: trip, context: modelContext)
                },
                deleteTrip: {
                    if TripPackingService.deleteTrip(trip, context: modelContext) {
                        dismiss()
                    } else {
                        actionFailureMessage = "The trip couldn’t be deleted. Please try again."
                    }
                }
            )
        )
        .alert("Couldn’t Update Trip", isPresented: Binding(
            get: { actionFailureMessage != nil },
            set: { if !$0 { actionFailureMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionFailureMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var weatherContent: some View {
        if weatherIsLoading && weatherForecasts.isEmpty {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checking trip weather")
                        .font(.subheadline.weight(.semibold))
                    Text("Looking at each destination and its travel dates…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Forecast-based packing")
                            .font(.subheadline.weight(.semibold))
                        Text("Open a destination for the daily forecast.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let weatherLastUpdatedAt {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                Text(TripWeatherFormatting.lastUpdated(weatherLastUpdatedAt))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("trip.weather.summary-last-updated")
                        }
                    }
                    Spacer()
                    Button(action: refreshWeather) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(weatherIsLoading)
                    .accessibilityLabel("Refresh trip weather")
                }

                ForEach(weatherForecasts) { forecast in
                    destinationWeatherContent(forecast)
                }

                if !combinedWeatherSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Suggested for this trip", systemImage: "suitcase.fill")
                            .font(.subheadline.weight(.semibold))
                        ForEach(combinedWeatherSuggestions) { suggestion in
                            Label(suggestion.title, systemImage: suggestion.category.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !trip.isArchived {
                            Button {
                                let added = TripPackingService.addSuggestions(
                                    combinedWeatherSuggestions,
                                    to: trip,
                                    existingItems: items,
                                    context: modelContext
                                )
                                weatherSuggestionMessage = added == 0
                                    ? "Those weather items are already on this trip."
                                    : "Added \(added) weather \(added == 1 ? "item" : "items") to the shared list."
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(.white)
                                    Text("Add \(combinedWeatherSuggestions.count) to Packing List")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                } else if weatherForecasts.contains(where: { $0.snapshot != nil }) {
                    Label("No weather-specific additions suggested", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if let weatherAttribution {
                    Divider()
                    HStack(spacing: 12) {
                        TripWeatherAttributionMark(snapshot: weatherAttribution)
                        Spacer()
                        Button {
                            showingWeatherAttribution = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                Text("About weather data")
                            }
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if weatherIsLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Refreshing…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationWeatherContent(_ forecast: TripDestinationWeatherForecast) -> some View {
        if let snapshot = forecast.snapshot {
            Button {
                showingWeatherDetails = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.dailyForecast.first?.symbolName ?? "cloud.sun.fill")
                        .font(.title2)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 46, height: 46)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(forecast.window.destination.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if snapshot.hasPartialCoverage {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Partial forecast")
                            }
                        }
                        Text(destinationDateText(forecast.window))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(snapshot.summary)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the daily trip forecast")
            .accessibilityIdentifier("trip.weather.destination.\(forecast.id.uuidString)")
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(forecast.window.destination.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(destinationDateText(forecast.window))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TripWeatherAvailabilityMessage(availability: forecast.availability)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func destinationDateText(_ window: TripDestinationWeatherWindow) -> String {
        if trip.tripCalendar.isDate(window.startDate, inSameDayAs: window.endDate) {
            return trip.formattedDate(window.startDate)
        }
        return "\(trip.formattedDate(window.startDate)) – \(trip.formattedDate(window.endDate))"
    }

    private var travelerSections: [(key: String, title: String, items: [PackingItem])] {
        var sections = [(key: String, title: String, items: [PackingItem])]()
        let shared = visibleItems.filter { $0.travelerID == nil }
        if !shared.isEmpty { sections.append(("shared", "Shared", shared)) }
        for traveler in travelers {
            let scoped = visibleItems.filter { $0.travelerID == traveler.id }
            if !scoped.isEmpty { sections.append((traveler.id.uuidString, traveler.displayName, scoped)) }
        }
        let missing = visibleItems.filter { item in
            guard let travelerID = item.travelerID else { return false }
            return !travelers.contains { $0.id == travelerID }
        }
        if !missing.isEmpty { sections.append(("missing", "Former Traveler", missing)) }
        return sections
    }

    private var dateText: String {
        if trip.isSingleDay {
            return trip.formattedDate(trip.startDate)
        }
        return "\(trip.formattedDate(trip.startDate)) – \(trip.formattedDate(trip.endDate))"
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
            String(trip.endDate.timeIntervalSinceReferenceDate),
            String(weatherRefreshToken)
        ].joined(separator: "|")
    }

    @MainActor
    private func loadWeather() async {
        guard trip.weatherSuggestionsEnabled,
              !trip.destinationStops.isEmpty else {
            weatherForecasts = []
            return
        }
        let requestedID = weatherRequestID
        let shouldForceRefresh = forceWeatherRefresh
        weatherIsLoading = true
        defer {
            if requestedID == weatherRequestID {
                weatherIsLoading = false
                forceWeatherRefresh = false
            }
        }
        let values = await TripWeatherService.forecasts(
            for: trip,
            forceRefresh: shouldForceRefresh
        )
        guard !Task.isCancelled, requestedID == weatherRequestID else { return }
        weatherForecasts = values
    }

    private func refreshWeather() {
        forceWeatherRefresh = true
        weatherRefreshToken += 1
    }
}

private struct PackingListActionConfirmationModifier: ViewModifier {
    @Binding var showingArchiveConfirmation: Bool
    @Binding var itemPendingDelete: PackingItem?
    @Binding var showingDeleteConfirmation: Bool
    let tripTitle: String
    let archiveTrip: () -> Void
    let deleteItem: (PackingItem) -> Void
    let deleteTrip: () -> Void

    func body(content: Content) -> some View {
        content
            .appActionSheet(
                isPresented: $showingArchiveConfirmation,
                title: "Archive Trip?",
                message: "This hides the trip from active planning. You can restore it later.",
                systemImage: "archivebox.fill",
                tint: .orange,
                options: [
                    AppActionSheetOption(
                        title: "Archive Trip",
                        subtitle: tripTitle,
                        systemImage: "archivebox.fill",
                        tint: .orange,
                        action: archiveTrip
                    )
                ]
            )
            .appActionSheet(
                isPresented: Binding(
                    get: { itemPendingDelete != nil },
                    set: { if !$0 { itemPendingDelete = nil } }
                ),
                title: "Delete Packing Item?",
                message: itemPendingDelete.map { "This permanently removes \($0.title) from the packing list." },
                systemImage: "trash.fill",
                tint: .red,
                options: itemPendingDelete.map { item in
                    [AppActionSheetOption(
                        title: "Delete Item",
                        subtitle: item.title,
                        systemImage: "trash.fill",
                        tint: .red,
                        role: .destructive
                    ) {
                        deleteItem(item)
                        itemPendingDelete = nil
                    }]
                } ?? [],
                cancelAction: { itemPendingDelete = nil }
            )
            .appActionSheet(
                isPresented: $showingDeleteConfirmation,
                title: "Delete Trip?",
                message: "This permanently removes the trip, itinerary, packing list, bags, and traveler assignments. Items already added to Shopping will remain.",
                systemImage: "trash.fill",
                tint: .red,
                options: [
                    AppActionSheetOption(
                        title: "Delete Trip",
                        subtitle: tripTitle,
                        systemImage: "trash.fill",
                        tint: .red,
                        role: .destructive,
                        action: deleteTrip
                    )
                ]
            )
    }
}

private struct TripWeatherDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trip: PackingTrip
    let forecasts: [TripDestinationWeatherForecast]
    let isRefreshing: Bool
    let refresh: () -> Void

    @State private var showingAttribution = false

    private var attribution: TripWeatherSnapshot? {
        forecasts.compactMap(\.snapshot).first
    }

    private var lastUpdatedAt: Date? {
        forecasts.compactMap { $0.snapshot?.fetchedAt }.min()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weather along your trip")
                            .font(.title2.bold())
                        Text("Forecasts are matched to each destination’s dates and update as the trip gets closer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let lastUpdatedAt {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                Text(TripWeatherFormatting.lastUpdated(lastUpdatedAt))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("trip.weather.last-updated")
                        }
                    }

                    ForEach(forecasts) { forecast in
                        destinationCard(forecast)
                    }

                    if let attribution {
                        HStack(spacing: 12) {
                            TripWeatherAttributionMark(snapshot: attribution)
                            Spacer()
                            Button {
                                showingAttribution = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                    Text("About weather data")
                                }
                                .font(.caption.weight(.semibold))
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("Trip Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refresh) {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh trip weather")
                }
            }
            .sheet(isPresented: $showingAttribution) {
                if let attribution {
                    TripWeatherAttributionSheet(snapshot: attribution)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationCard(_ forecast: TripDestinationWeatherForecast) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(forecast.window.destination.name, systemImage: "mappin.and.ellipse")
                        .font(.headline)
                    Text(destinationDateText(forecast.window))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let snapshot = forecast.snapshot,
                   let symbolName = snapshot.dailyForecast.first?.symbolName {
                    Image(systemName: symbolName)
                        .font(.title2)
                        .symbolRenderingMode(.multicolor)
                }
            }

            if let snapshot = forecast.snapshot {
                Text(snapshot.summary)
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    TripWeatherMetric(
                        title: "Low",
                        value: TripWeatherFormatting.temperature(snapshot.lowTemperatureCelsius),
                        systemImage: "thermometer.low",
                        tint: .cyan
                    )
                    TripWeatherMetric(
                        title: "High",
                        value: TripWeatherFormatting.temperature(snapshot.highTemperatureCelsius),
                        systemImage: "thermometer.high",
                        tint: .orange
                    )
                    TripWeatherMetric(
                        title: "Rain",
                        value: TripWeatherFormatting.percentage(
                            snapshot.dailyForecast.map(\.precipitationChance).max() ?? 0
                        ),
                        systemImage: "drop.fill",
                        tint: .blue
                    )
                    TripWeatherMetric(
                        title: "Peak UV",
                        value: String(snapshot.dailyForecast.map(\.uvIndex).max() ?? 0),
                        systemImage: "sun.max.fill",
                        tint: .yellow
                    )
                }

                if !snapshot.dailyForecast.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(snapshot.dailyForecast, id: \.date) { day in
                                TripWeatherDayCard(
                                    day: day,
                                    timeZoneIdentifier: forecast.window.destination.timeZoneIdentifier
                                        ?? trip.tripTimeZone.identifier
                                )
                            }
                        }
                    }
                }

                Label(
                    snapshot.coverageSummary,
                    systemImage: snapshot.hasPartialCoverage
                        ? "exclamationmark.triangle.fill"
                        : "calendar.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(snapshot.hasPartialCoverage ? .orange : .secondary)
                .accessibilityIdentifier("trip.weather.coverage.\(forecast.id.uuidString)")

                let suggestions = TripPackingSuggestionEngine.weatherSuggestions(
                    rainLikely: snapshot.rainLikely,
                    coldWeather: snapshot.coldWeather,
                    hotOrHighUV: snapshot.hotOrHighUV
                )
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Packing considerations")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(suggestions) { suggestion in
                            Label(suggestion.title, systemImage: suggestion.category.systemImage)
                                .font(.subheadline)
                        }
                    }
                }
            } else {
                TripWeatherAvailabilityMessage(availability: forecast.availability)
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }

    private func destinationDateText(_ window: TripDestinationWeatherWindow) -> String {
        if trip.tripCalendar.isDate(window.startDate, inSameDayAs: window.endDate) {
            return trip.formattedDate(window.startDate)
        }
        return "\(trip.formattedDate(window.startDate)) – \(trip.formattedDate(window.endDate))"
    }
}

private struct TripWeatherMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TripWeatherDayCard: View {
    let day: TripDailyWeather
    let timeZoneIdentifier: String

    var body: some View {
        VStack(spacing: 8) {
            Text(TripWeatherFormatting.day(day.date, timeZoneIdentifier: timeZoneIdentifier))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: day.symbolName)
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .frame(height: 28)
            HStack(spacing: 5) {
                Text(TripWeatherFormatting.temperature(day.highTemperatureCelsius, includesUnit: false))
                    .font(.subheadline.bold())
                Text(TripWeatherFormatting.temperature(day.lowTemperatureCelsius, includesUnit: false))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Label(
                TripWeatherFormatting.percentage(day.precipitationChance),
                systemImage: "drop.fill"
            )
            .font(.caption2)
            .foregroundStyle(.blue)
            Text("UV \(day.uvIndex)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 108)
        .padding(.vertical, 12)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct TripWeatherAvailabilityMessage: View {
    let availability: TripWeatherAvailability

    var body: some View {
        Group {
            switch availability {
            case .notYetAvailable:
                Label(
                    "Forecast isn’t available yet. It will appear automatically as these dates enter the forecast window.",
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(.secondary)
            case .past:
                Label("Forecast is no longer available for these dates.", systemImage: "calendar.badge.minus")
                    .foregroundStyle(.secondary)
            case .locationRequired:
                Label(
                    "Choose a destination search result with a map pin to enable weather.",
                    systemImage: "mappin.slash"
                )
                .foregroundStyle(.orange)
            case .failed(let reason):
                switch reason {
                case .appConfiguration:
                    Label(
                        "Weather isn’t available in this app build. Update the app and try again.",
                        systemImage: "exclamationmark.shield"
                    )
                    .foregroundStyle(.orange)
                case .connection:
                    Label(
                        "Weather couldn’t connect. Check your connection and try again.",
                        systemImage: "wifi.exclamationmark"
                    )
                    .foregroundStyle(.orange)
                case .serviceUnavailable:
                    Label(
                        "Weather couldn’t refresh right now. Try again shortly.",
                        systemImage: "exclamationmark.icloud"
                    )
                    .foregroundStyle(.orange)
                }
            case .available:
                EmptyView()
            }
        }
        .font(.caption)
    }
}

struct TripWeatherAttributionMark: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: TripWeatherSnapshot

    var body: some View {
        AsyncImage(url: colorScheme == .dark ? snapshot.darkMarkURL : snapshot.lightMarkURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Label("Apple Weather", systemImage: "cloud.sun.fill")
                .font(.system(size: 8, weight: .semibold))
                .minimumScaleFactor(0.6)
        }
        .frame(width: 58, height: 12, alignment: .leading)
        .clipped()
        .accessibilityLabel("Apple Weather")
    }
}

struct TripWeatherAttributionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: TripWeatherSnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TripWeatherAttributionMark(snapshot: snapshot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Weather data provided by Apple Weather")
                        .font(.title3.bold())
                    Text("Forecasts are used only to provide trip-planning context and tailor packing suggestions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("Data sources and legal attribution")
                        .font(.headline)
                    Text(snapshot.legalAttributionText.isEmpty
                         ? "Apple Weather provides the forecast and required data-source attribution."
                         : snapshot.legalAttributionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(20)
            }
            .navigationTitle("About Weather Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum TripWeatherFormatting {
    static func temperature(
        _ celsius: Double,
        locale: Locale = .current,
        includesUnit: Bool = true
    ) -> String {
        let unit: UnitTemperature = locale.measurementSystem == .us ? .fahrenheit : .celsius
        let value = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: unit)
            .value
        return includesUnit
            ? "\(Int(value.rounded()))\(unit.symbol)"
            : "\(Int(value.rounded()))°"
    }

    static func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func lastUpdated(_ date: Date) -> String {
        "Last updated \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func day(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }
}

private struct PackingNotesField: View {
    @Binding var text: String
    let lineLimit: ClosedRange<Int>
    let accessibilityIdentifier: String

    var body: some View {
        TextField("Optional notes", text: $text, axis: .vertical)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .textInputAutocapitalization(.sentences)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct PackingItemRow: View {
    let item: PackingItem
    let bag: PackingBag?
    let isReadOnly: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isReadOnly {
                Image(systemName: stateImage)
                    .font(.title3)
                    .foregroundStyle(stateColor)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else {
                Button(action: toggle) {
                    Image(systemName: stateImage)
                        .font(.title3)
                        .foregroundStyle(stateColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.state == .packed ? "Mark unpacked" : "Mark packed")
                .accessibilityIdentifier("trip.item.\(item.id.uuidString).toggle")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .strikethrough(item.state == .packed)
                        .foregroundStyle(item.state == .notNeeded ? .secondary : .primary)
                    if item.priority == .essential {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Essential")
                    }
                }

                PackingItemFlowLayout(spacing: 6) {
                    PackingItemMetadataBadge(
                        title: item.category.displayName,
                        systemImage: item.category.systemImage,
                        tint: .secondary
                    )
                    if !item.quantityText.isEmpty {
                        PackingItemMetadataBadge(
                            title: item.quantityText,
                            systemImage: "number",
                            tint: .secondary
                        )
                    }
                    if let bag {
                        PackingItemMetadataBadge(
                            title: bag.name,
                            systemImage: "bag.fill",
                            tint: .secondary
                        )
                    }
                    if item.needsPurchase {
                        PackingItemMetadataBadge(
                            title: "Buy",
                            systemImage: "cart.fill",
                            tint: .orange
                        )
                    }
                }

                if item.assignedCaregiverName != nil
                    || (item.packedBy != nil && item.state == .packed) {
                    PackingItemFlowLayout(spacing: 6) {
                        if let assignedCaregiverName = item.assignedCaregiverName {
                            PackingItemMetadataBadge(
                                title: "Assigned to \(assignedCaregiverName)",
                                systemImage: "person.crop.circle.fill",
                                tint: .blue,
                                trailingSystemImage: item.caregiverReminderEnabled ? "bell.fill" : nil
                            )
                        }
                        if let packedBy = item.packedBy, item.state == .packed {
                            PackingItemMetadataBadge(
                                title: packedByMatchesAssignee(packedBy) ? "Packed" : "Packed by \(packedBy)",
                                systemImage: "checkmark.circle.fill",
                                tint: .green
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var stateImage: String {
        switch item.state {
        case .needed: "circle"
        case .packed: "checkmark.circle.fill"
        case .notNeeded: "minus.circle.fill"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .needed: .secondary
        case .packed: .green
        case .notNeeded: .gray
        }
    }

    private func packedByMatchesAssignee(_ packedBy: String) -> Bool {
        guard let assignedCaregiverName = item.assignedCaregiverName else { return false }
        return CaregiverIdentityService.namesMatch(assignedCaregiverName, packedBy)
    }
}

private struct PackingItemMetadataBadge: View {
    let title: String
    let systemImage: String
    let tint: Color
    var trailingSystemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .accessibilityLabel("Reminder enabled")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.11), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct PackingItemFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var usedHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if rowWidth > 0, proposedWidth > availableWidth {
                usedWidth = max(usedWidth, rowWidth)
                usedHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = proposedWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        usedWidth = max(usedWidth, rowWidth)
        usedHeight += rowHeight
        return CGSize(
            width: proposal.width ?? usedWidth,
            height: usedHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x > bounds.minX, point.x + size.width > bounds.maxX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: point,
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            point.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct PackingTravelersEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: PackingTrip
    let profiles: [CareProfile]

    @State private var currentTravelers: [TripTraveler]
    @State private var currentBags: [PackingBag]
    @State private var currentItems: [PackingItem]
    @State private var adultNames: [UUID: String]
    @State private var newAdultName = ""
    @State private var includeStarterItems = true
    @State private var travelerToRemove: TripTraveler?

    init(
        trip: PackingTrip,
        travelers: [TripTraveler],
        bags: [PackingBag],
        items: [PackingItem],
        profiles: [CareProfile]
    ) {
        self.trip = trip
        self.profiles = profiles
        let sortedTravelers = travelers.sorted { $0.sortOrder < $1.sortOrder }
        _currentTravelers = State(initialValue: sortedTravelers)
        _currentBags = State(initialValue: bags)
        _currentItems = State(initialValue: items)
        _adultNames = State(initialValue: Dictionary(
            sortedTravelers
                .filter { $0.kind == .adult }
                .map { ($0.id, $0.displayName) },
            uniquingKeysWith: { current, _ in current }
        ))
    }

    private var availableProfiles: [CareProfile] {
        let linkedIDs = Set(currentTravelers.compactMap(\.profileID))
        return profiles.filter { !linkedIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(currentTravelers) { traveler in
                    HStack(spacing: 10) {
                        Image(systemName: traveler.kind.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        if traveler.kind == .adult {
                            LabeledContent("Adult name") {
                                TextField("Required", text: Binding(
                                    get: { adultNames[traveler.id] ?? traveler.displayName },
                                    set: { adultNames[traveler.id] = $0 }
                                ))
                                .multilineTextAlignment(.trailing)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(traveler.displayName)
                                Text("Linked \(traveler.kind.displayName.lowercased()) profile")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            travelerToRemove = traveler
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .disabled(currentTravelers.count == 1)
                        .accessibilityLabel("Remove \(traveler.displayName)")
                    }
                }
                if currentTravelers.contains(where: { $0.kind == .adult }) {
                    Button("Save Adult Names") { saveAdultNames() }
                }
            } header: {
                Text("Travelers")
            } footer: {
                Text("A trip needs at least one traveler. Removing someone keeps their packing items and bags on the shared list.")
            }

            Section {
                Toggle("Add starter items for new travelers", isOn: $includeStarterItems)
            } footer: {
                Text("New suggestions use the trip's duration, laundry, and activities and remain fully editable.")
            }

            Section("Add Adult") {
                LabeledContent("Adult name") {
                    HStack {
                        TextField("Required", text: $newAdultName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit(addAdult)
                        Button("Add", action: addAdult)
                            .disabled(newAdultName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if !availableProfiles.isEmpty {
                Section("Add Care Profile") {
                    ForEach(availableProfiles) { profile in
                        Button {
                            addProfile(profile)
                        } label: {
                            Label(
                                profile.name,
                                systemImage: profile.profileType == .dog
                                    ? "pawprint.fill"
                                    : profile.profileType == .adult ? "person.fill" : "figure.child"
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Travelers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveAdultNames()
                    dismiss()
                }
            }
        }
        .appActionSheet(
            isPresented: Binding(
                get: { travelerToRemove != nil },
                set: { if !$0 { travelerToRemove = nil } }
            ),
            title: "Remove traveler?",
            message: travelerToRemove.map {
                "\($0.displayName)'s items and bags will move to Shared."
            },
            systemImage: "person.crop.circle.badge.minus",
            tint: .red,
            options: travelerToRemove.map { traveler in
                [AppActionSheetOption(
                    title: "Remove \(traveler.displayName)",
                    subtitle: "Keep their items and bags on the shared list.",
                    systemImage: "person.crop.circle.badge.minus",
                    tint: .red,
                    role: .destructive
                ) {
                    remove(traveler)
                }]
            } ?? [],
            cancelAction: { travelerToRemove = nil }
        )
    }

    private func saveAdultNames() {
        for traveler in currentTravelers where traveler.kind == .adult {
            guard let name = adultNames[traveler.id] else { continue }
            if TripPackingService.updateTravelerName(
                traveler,
                displayName: name,
                trip: trip,
                context: modelContext
            ) {
                adultNames[traveler.id] = traveler.displayName
            }
        }
    }

    private func addAdult() {
        guard let traveler = TripPackingService.addTraveler(
            to: trip,
            kind: .adult,
            profileID: nil,
            displayName: newAdultName,
            includeStarterItems: includeStarterItems,
            existingTravelers: currentTravelers,
            existingItems: currentItems,
            context: modelContext
        ) else { return }
        currentTravelers.append(traveler)
        currentTravelers.sort { $0.sortOrder < $1.sortOrder }
        adultNames[traveler.id] = traveler.displayName
        newAdultName = ""
        refreshRelatedData()
    }

    private func addProfile(_ profile: CareProfile) {
        guard let traveler = TripPackingService.addTraveler(
            to: trip,
            kind: profile.profileType.tripTravelerKind,
            profileID: profile.id,
            displayName: profile.name,
            includeStarterItems: includeStarterItems,
            existingTravelers: currentTravelers,
            existingItems: currentItems,
            context: modelContext
        ) else { return }
        currentTravelers.append(traveler)
        currentTravelers.sort { $0.sortOrder < $1.sortOrder }
        refreshRelatedData()
    }

    private func remove(_ traveler: TripTraveler) {
        guard TripPackingService.removeTraveler(
            traveler,
            from: trip,
            travelers: currentTravelers,
            bags: currentBags,
            items: currentItems,
            context: modelContext
        ) else { return }
        currentTravelers.removeAll { $0.id == traveler.id }
        adultNames.removeValue(forKey: traveler.id)
        travelerToRemove = nil
        refreshRelatedData()
    }

    private func refreshRelatedData() {
        let tripID = trip.id
        currentBags = (try? modelContext.fetch(FetchDescriptor<PackingBag>(
            predicate: #Predicate { $0.tripID == tripID },
            sortBy: [SortDescriptor(\PackingBag.sortOrder)]
        ))) ?? []
        currentItems = (try? modelContext.fetch(FetchDescriptor<PackingItem>(
            predicate: #Predicate { $0.tripID == tripID },
            sortBy: [SortDescriptor(\PackingItem.sortOrder)]
        ))) ?? []
    }
}

private extension CareProfileType {
    var tripTravelerKind: TripTravelerKind {
        switch self {
        case .child: .child
        case .adult: .adult
        case .dog: .dog
        }
    }
}

private struct PackingItemEditorOption: Identifiable {
    let id: UUID
    let title: String
}

private enum PackingItemCaregiverAssignment: Hashable {
    case shared
    case known(String)
    case custom
}

private struct PackingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: PackingTrip
    let item: PackingItem?
    let existingItems: [PackingItem]
    private let travelerOptions: [PackingItemEditorOption]
    private let bagOptions: [PackingItemEditorOption]
    private let knownCaregiverNames: [String]

    @State private var title: String
    @State private var category: PackingItemCategory
    @State private var travelerID: UUID?
    @State private var bagID: UUID?
    @State private var quantity: Double?
    @State private var unit: String
    @State private var notes: String
    @State private var priority: PackingItemPriority
    @State private var needsPurchase: Bool
    @State private var caregiverAssignment: PackingItemCaregiverAssignment
    @State private var customCaregiverName: String
    @State private var caregiverReminderEnabled: Bool
    @State private var validationMessage: String?
    @FocusState private var isCustomCaregiverNameFocused: Bool

    init(
        trip: PackingTrip,
        item: PackingItem?,
        travelers: [TripTraveler],
        bags: [PackingBag],
        existingItems: [PackingItem]
    ) {
        self.trip = trip
        self.item = item
        self.existingItems = existingItems
        travelerOptions = travelers.map {
            PackingItemEditorOption(id: $0.id, title: $0.displayName)
        }
        bagOptions = bags.map {
            PackingItemEditorOption(id: $0.id, title: $0.name)
        }
        let defaults = UserDefaults.standard
        let caregiverCandidates: [String?] = [
            defaults.string(forKey: CaregiverIdentityService.currentCaregiverNameKey),
            defaults.string(forKey: CaregiverIdentityService.primaryCaregiverNameKey),
            trip.createdBy
        ]
        + travelers.filter { $0.kind == .adult }.map { Optional($0.displayName) }
        + existingItems.flatMap {
            [$0.assignedCaregiverName, $0.addedBy, $0.packedBy]
        }
        let caregiverNames = TripPackingService.uniqueCaregiverNames(
            from: caregiverCandidates
        )
        knownCaregiverNames = caregiverNames
        let existingCaregiverName = item?.assignedCaregiverName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let initialCaregiverAssignment: PackingItemCaregiverAssignment
        let initialCustomCaregiverName: String
        if let existingCaregiverName, !existingCaregiverName.isEmpty {
            if let knownName = caregiverNames.first(where: {
                $0.caseInsensitiveCompare(existingCaregiverName) == .orderedSame
            }) {
                initialCaregiverAssignment = .known(knownName)
                initialCustomCaregiverName = ""
            } else {
                initialCaregiverAssignment = .custom
                initialCustomCaregiverName = existingCaregiverName
            }
        } else {
            initialCaregiverAssignment = .shared
            initialCustomCaregiverName = ""
        }
        _title = State(initialValue: item?.title ?? "")
        _category = State(initialValue: item?.category ?? .other)
        _travelerID = State(initialValue: item?.travelerID)
        _bagID = State(initialValue: item?.bagID)
        _quantity = State(initialValue: item?.quantity)
        _unit = State(initialValue: item?.unit ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _priority = State(initialValue: item?.priority ?? .normal)
        _needsPurchase = State(initialValue: item?.needsPurchase ?? false)
        _caregiverAssignment = State(initialValue: initialCaregiverAssignment)
        _customCaregiverName = State(initialValue: initialCustomCaregiverName)
        _caregiverReminderEnabled = State(initialValue: item?.caregiverReminderEnabled ?? true)
        _validationMessage = State(initialValue: nil)
    }

    var body: some View {
        Form {
            Section("Item") {
                LabeledContent("Name") {
                    TextField("Required", text: $title)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("trip.item.name")
                }
                Picker("Category", selection: $category) {
                    ForEach(PackingItemCategory.allCases) { value in
                        Label(value.displayName, systemImage: value.systemImage).tag(value)
                    }
                }
                Picker("Traveler", selection: $travelerID) {
                    Text("Shared").tag(UUID?.none)
                    ForEach(travelerOptions) { option in
                        Text(option.title).tag(Optional(option.id))
                    }
                }
                Picker("Bag", selection: $bagID) {
                    Text("Not assigned").tag(UUID?.none)
                    ForEach(bagOptions) { option in
                        Text(option.title).tag(Optional(option.id))
                    }
                }
            }
            Section("Details") {
                LabeledContent("Quantity") {
                    TextField("Optional", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                if !TripPackingService.isValidQuantity(quantity) {
                    Text("Quantity must be greater than zero.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                LabeledContent("Unit") {
                    TextField("Optional", text: $unit)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Priority", selection: $priority) {
                    ForEach(PackingItemPriority.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Toggle("Need to buy", isOn: $needsPurchase)
            }
            Section("Notes") {
                PackingNotesField(
                    text: $notes,
                    lineLimit: 2...5,
                    accessibilityIdentifier: "trip.item.notes"
                )
            }
            Section {
                Text("Choose who is responsible for this item, or leave it shared. Select a name or enter a new one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Assigned to", selection: $caregiverAssignment) {
                    Text("Shared — anyone").tag(PackingItemCaregiverAssignment.shared)
                    ForEach(knownCaregiverNames, id: \.self) { name in
                        Text(name).tag(PackingItemCaregiverAssignment.known(name))
                    }
                    Text("Enter a new name").tag(PackingItemCaregiverAssignment.custom)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("trip.item.caregiver-choice")

                if caregiverAssignment == .custom {
                    LabeledContent("Name") {
                        TextField("Required", text: $customCaregiverName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .focused($isCustomCaregiverNameFocused)
                            .accessibilityIdentifier("trip.item.caregiver")
                    }
                }

                if caregiverAssignment != .shared {
                    Toggle("Only remind this person", isOn: $caregiverReminderEnabled)
                        .disabled(resolvedCaregiverName == nil)
                        .accessibilityIdentifier("trip.item.caregiver-reminder")
                }
            } header: {
                Text("Responsibility")
            } footer: {
                Text(responsibilityFooterText)
            }
            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("trip.item.editor")
        .navigationTitle(item == nil ? "Add Packing Item" : "Edit Packing Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    validationMessage = nil
                    let saved: Bool
                    if let item {
                        saved = TripPackingService.updateItem(
                            item,
                            title: title,
                            category: category,
                            travelerID: travelerID,
                            bagID: bagID,
                            quantity: quantity,
                            unit: unit,
                            notes: notes,
                            priority: priority,
                            needsPurchase: needsPurchase,
                            assignedCaregiverName: resolvedCaregiverName,
                            caregiverReminderEnabled: caregiverReminderEnabled,
                            trip: trip,
                            context: modelContext
                        )
                    } else {
                        saved = TripPackingService.addItem(
                            to: trip,
                            title: title,
                            category: category,
                            travelerID: travelerID,
                            bagID: bagID,
                            quantity: quantity,
                            unit: unit,
                            notes: notes,
                            priority: priority,
                            needsPurchase: needsPurchase,
                            assignedCaregiverName: resolvedCaregiverName,
                            caregiverReminderEnabled: caregiverReminderEnabled,
                            existingItems: existingItems,
                            context: modelContext
                        ) != nil
                    }
                    if saved {
                        dismiss()
                    } else {
                        validationMessage = "The item could not be saved. Review its name and quantity, then try again."
                    }
                }
                .accessibilityIdentifier("trip.item.save")
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !TripPackingService.isValidQuantity(quantity)
                        || !caregiverAssignmentIsValid
                )
            }
        }
        .onChange(of: caregiverAssignment) { _, assignment in
            if assignment == .custom {
                isCustomCaregiverNameFocused = true
            }
        }
    }

    private var resolvedCaregiverName: String? {
        switch caregiverAssignment {
        case .shared:
            return nil
        case .known(let name):
            return name
        case .custom:
            let trimmed = customCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private var caregiverAssignmentIsValid: Bool {
        caregiverAssignment != .custom || resolvedCaregiverName != nil
    }

    private var responsibilityFooterText: String {
        switch caregiverAssignment {
        case .shared:
            return "Shared items can be packed by anyone. No one person receives a reminder."
        case .known, .custom:
            return "When enabled, reminders go only to devices where the name in Settings matches this assignment."
        }
    }

}

private struct PackingShoppingListPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: PackingItem
    let trip: PackingTrip
    let lists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    @State private var errorMessage: String?

    var body: some View {
        List {
            if lists.isEmpty {
                ContentUnavailableView(
                    "No Shopping Lists",
                    systemImage: "cart",
                    description: Text("Create a shopping list in Home, then add this packing item to it.")
                )
            } else {
                ForEach(lists) { list in
                    Button {
                        guard TripPackingService.addToShoppingList(
                            item,
                            trip: trip,
                            shoppingList: list,
                            existingShoppingItems: shoppingItems,
                            context: modelContext
                        ) != nil else {
                            errorMessage = "The item could not be added. Please try again."
                            return
                        }
                        dismiss()
                    } label: {
                        Label(list.name, systemImage: "cart.fill")
                    }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add to Shopping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

private struct PackingBagDraft: Identifiable {
    let bag: PackingBag
    var name: String
    var travelerID: UUID?

    var id: UUID { bag.id }
}

private struct PackingBagsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: PackingTrip
    let travelers: [TripTraveler]
    let items: [PackingItem]
    private let assignedItemCountByBagID: [UUID: Int]

    @State private var drafts: [PackingBagDraft]
    @State private var newName = ""
    @State private var newTravelerID: UUID?
    @State private var bagToDelete: PackingBag?
    @State private var validationMessage: String?
    @State private var addedBagName: String?
    @State private var pendingSaveTasks = [UUID: Task<Void, Never>]()
    @FocusState private var isNewBagNameFocused: Bool

    init(
        trip: PackingTrip,
        travelers: [TripTraveler],
        bags: [PackingBag],
        items: [PackingItem]
    ) {
        self.trip = trip
        self.travelers = travelers
        self.items = items
        assignedItemCountByBagID = items.reduce(into: [UUID: Int]()) { counts, item in
            if let bagID = item.bagID {
                counts[bagID, default: 0] += 1
            }
        }
        _drafts = State(initialValue: bags.sorted { $0.sortOrder < $1.sortOrder }.map {
            PackingBagDraft(bag: $0, name: $0.name, travelerID: $0.travelerID)
        })
    }

    var body: some View {
        Form {
            Section {
                Text("Create one bag at a time. Give it a name, optionally choose a traveler, then add it to the trip.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LabeledContent("Bag name") {
                    TextField("Required", text: $newName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.go)
                        .focused($isNewBagNameFocused)
                        .onSubmit {
                            if canAddBag {
                                addBag()
                            }
                        }
                        .accessibilityIdentifier("trip.bag.new.name")
                }
                Picker("Traveler", selection: $newTravelerID) {
                    Text("Shared").tag(UUID?.none)
                    ForEach(travelers) { traveler in
                        Text(traveler.displayName).tag(Optional(traveler.id))
                    }
                }

                Button(action: addBag) {
                    Label("Add This Bag", systemImage: "bag.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAddBag)
                .accessibilityIdentifier("trip.bag.add")

                if let addedBagName {
                    Label("\(addedBagName) added. Ready for another bag.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(addedBagName) added. Ready for another bag.")
                        .accessibilityIdentifier("trip.bag.added")
                }
            } header: {
                Text("Add a Bag")
            } footer: {
                Text("Each time you tap Add This Bag, it appears below and these fields reset for the next bag.")
            }

            if drafts.isEmpty {
                Section("Added Bags") {
                    Label("No bags added yet", systemImage: "bag")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach($drafts) { $draft in
                    Section {
                        LabeledContent("Bag name") {
                            TextField("Required", text: $draft.name)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                                .onChange(of: draft.name) { _, _ in
                                    scheduleSave(for: draft.id)
                                }
                                .accessibilityIdentifier("trip.bag.existing.name")
                        }
                        Picker("Traveler", selection: $draft.travelerID) {
                            Text("Shared").tag(UUID?.none)
                            ForEach(travelers) { traveler in
                                Text(traveler.displayName).tag(Optional(traveler.id))
                            }
                        }
                        .onChange(of: draft.travelerID) { _, _ in
                            saveNow(draft.id)
                        }
                        Button("Delete Bag", role: .destructive) {
                            bagToDelete = draft.bag
                        }
                    } header: {
                        Text(draft.bag.name)
                    } footer: {
                        let assignedCount = assignedItemCountByBagID[draft.id, default: 0]
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Changes save automatically.")
                            if assignedCount > 0 {
                                Text("\(assignedCount) assigned \(assignedCount == 1 ? "item" : "items"). Deleting this bag leaves them unassigned.")
                            }
                        }
                    }
                }
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Bags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish() }
            }
        }
        .onDisappear {
            if !pendingSaveTasks.isEmpty {
                _ = flushPendingSaves()
            }
        }
        .appActionSheet(
            isPresented: Binding(
                get: { bagToDelete != nil },
                set: { if !$0 { bagToDelete = nil } }
            ),
            title: "Delete bag?",
            message: bagToDelete.map { bag in
                let count = items.filter { $0.bagID == bag.id }.count
                return count == 0
                    ? "This removes \(bag.name)."
                    : "This removes \(bag.name) and leaves \(count) assigned \(count == 1 ? "item" : "items") unassigned."
            },
            systemImage: "trash.fill",
            tint: .red,
            options: bagToDelete.map { bag in
                [AppActionSheetOption(
                    title: "Delete \(bag.name)",
                    subtitle: "Assigned items will remain on the trip without a bag.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    delete(bag)
                }]
            } ?? [],
            cancelAction: { bagToDelete = nil }
        )
    }

    private var currentBags: [PackingBag] {
        drafts.map(\.bag)
    }

    private var canAddBag: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleSave(for bagID: UUID) {
        pendingSaveTasks[bagID]?.cancel()
        pendingSaveTasks[bagID] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let draft = drafts.first(where: { $0.id == bagID }) else { return }
            _ = save(draft)
            pendingSaveTasks[bagID] = nil
        }
    }

    private func saveNow(_ bagID: UUID) {
        pendingSaveTasks[bagID]?.cancel()
        pendingSaveTasks[bagID] = nil
        guard let draft = drafts.first(where: { $0.id == bagID }) else { return }
        _ = save(draft)
    }

    @discardableResult
    private func save(_ draft: PackingBagDraft) -> Bool {
        validationMessage = nil
        guard TripPackingService.updateBag(
            draft.bag,
            name: draft.name,
            travelerID: draft.travelerID,
            trip: trip,
            existingBags: currentBags,
            context: modelContext
        ) else {
            validationMessage = "Use a unique, non-empty bag name and try again."
            return false
        }
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index].name = draft.bag.name
            drafts[index].travelerID = draft.bag.travelerID
        }
        return true
    }

    private func finish() {
        guard flushPendingSaves() else { return }
        dismiss()
    }

    @discardableResult
    private func flushPendingSaves() -> Bool {
        pendingSaveTasks.values.forEach { $0.cancel() }
        pendingSaveTasks.removeAll()
        for draft in drafts where !save(draft) {
            return false
        }
        return true
    }

    private func addBag() {
        validationMessage = nil
        addedBagName = nil
        guard let bag = TripPackingService.addBag(
            to: trip,
            name: newName,
            travelerID: newTravelerID,
            existingBags: currentBags,
            context: modelContext
        ) else {
            validationMessage = "Use a unique, non-empty bag name and try again."
            return
        }
        drafts.append(PackingBagDraft(bag: bag, name: bag.name, travelerID: bag.travelerID))
        drafts.sort { $0.bag.sortOrder < $1.bag.sortOrder }
        newName = ""
        newTravelerID = nil
        addedBagName = bag.name
        isNewBagNameFocused = true
    }

    private func delete(_ bag: PackingBag) {
        validationMessage = nil
        pendingSaveTasks[bag.id]?.cancel()
        pendingSaveTasks[bag.id] = nil
        guard TripPackingService.deleteBag(
            bag,
            trip: trip,
            items: items,
            context: modelContext
        ) else {
            validationMessage = "The bag could not be deleted. Please try again."
            return
        }
        drafts.removeAll { $0.id == bag.id }
        bagToDelete = nil
    }
}

struct PackingTripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationManager = NotificationManager.shared
    let trip: PackingTrip

    @State private var title: String
    @State private var destinationDrafts: [TripDestinationDraft]
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var travelMode: PackingTravelMode
    @State private var lodgingType: PackingLodgingType
    @State private var laundryAvailable: Bool
    @State private var activities: Set<PackingTripActivity>
    @State private var weatherEnabled: Bool
    @State private var reminderDate: Date?
    @State private var finalCheckDate: Date?
    @State private var notes: String

    init(trip: PackingTrip) {
        self.trip = trip
        _title = State(initialValue: trip.title)
        _destinationDrafts = State(initialValue: trip.destinationStops.map(TripDestinationDraft.init))
        _startDate = State(initialValue: trip.startDate)
        _endDate = State(initialValue: trip.endDate)
        _travelMode = State(initialValue: trip.travelMode)
        _lodgingType = State(initialValue: trip.lodgingType)
        _laundryAvailable = State(initialValue: trip.laundryAvailable)
        _activities = State(initialValue: trip.activities)
        _weatherEnabled = State(initialValue: trip.weatherSuggestionsEnabled)
        _reminderDate = State(initialValue: trip.reminderDate)
        _finalCheckDate = State(initialValue: trip.finalCheckDate)
        _notes = State(initialValue: trip.notes ?? "")
    }

    private var destinationStops: [TripDestinationStop] {
        destinationDrafts.compactMap { draft in
            draft.destination.map {
                TripDestinationStop(id: draft.id, destination: $0, startDate: draft.startDate)
            }
        }
        .sorted { ($0.startDate, $0.id.uuidString) < ($1.startDate, $1.id.uuidString) }
    }

    private var destinationsAreValid: Bool {
        destinationStops.count == destinationDrafts.count
            && TripPackingService.destinationStopsAreValid(
                destinationStops,
                tripStartDate: startDate,
                tripEndDate: endDate,
                timeZoneIdentifier: trip.timeZoneIdentifier
            )
    }

    var body: some View {
        Form {
            Section("Trip") {
                LabeledContent("Trip name") {
                    TextField("Required", text: $title)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    .environment(\.timeZone, trip.tripTimeZone)
                DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .environment(\.timeZone, trip.tripTimeZone)
                Picker("Travel", selection: $travelMode) {
                    ForEach(PackingTravelMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Stay", selection: $lodgingType) {
                    ForEach(PackingLodgingType.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Laundry available", isOn: $laundryAvailable)
            }
            TripDestinationsEditor(
                destinations: destinationDrafts,
                tripStartDate: startDate,
                tripEndDate: endDate,
                timeZone: trip.tripTimeZone,
                onChange: { destinationDrafts = $0 }
            )
            PackingTripActivitiesSection(activities: $activities)
            Section("Planning") {
                Toggle("Weather suggestions", isOn: $weatherEnabled)
                Toggle("Start packing reminder", isOn: Binding(
                    get: { reminderDate != nil },
                    set: { reminderDate = $0 ? (trip.tripCalendar.date(byAdding: .day, value: -3, to: startDate) ?? startDate) : nil }
                ))
                if let reminder = Binding($reminderDate) {
                    DatePicker("Packing reminder", selection: reminder)
                }
                Toggle("Final check reminder", isOn: Binding(
                    get: { finalCheckDate != nil },
                    set: { finalCheckDate = $0 ? (trip.tripCalendar.date(byAdding: .day, value: -1, to: startDate) ?? startDate) : nil }
                ))
                if let finalCheck = Binding($finalCheckDate) {
                    DatePicker("Final check", selection: finalCheck)
                }
                if !TripPackingService.reminderDatesAreValid(
                    reminderDate: reminderDate,
                    finalCheckDate: finalCheckDate
                ) {
                    Text("The start-packing reminder must be before the final check.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                PackingReminderPermissionView(
                    status: notificationManager.authorizationStatus,
                    hasEnabledReminders: reminderDate != nil || finalCheckDate != nil,
                    hasFutureReminder: reminderDate.map { $0 > Date() } == true
                        || finalCheckDate.map { $0 > Date() } == true,
                    requestPermission: {
                        Task { _ = await notificationManager.requestAuthorization() }
                    }
                )
            }
            Section("Notes") {
                PackingNotesField(
                    text: $notes,
                    lineLimit: 3...6,
                    accessibilityIdentifier: "trip.edit.notes"
                )
            }
        }
        .navigationTitle("Edit Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard TripPackingService.updateTrip(
                        trip,
                        title: title,
                        destination: destinationStops.first?.destination,
                        destinationStops: destinationStops,
                        startDate: startDate,
                        endDate: endDate,
                        travelMode: travelMode,
                        lodgingType: lodgingType,
                        laundryAvailable: laundryAvailable,
                        activities: activities,
                        weatherSuggestionsEnabled: weatherEnabled,
                        reminderDate: reminderDate,
                        finalCheckDate: finalCheckDate,
                        notes: notes,
                        context: modelContext
                    ) else { return }
                    dismiss()
                }
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || endDate < startDate
                        || !destinationsAreValid
                        || !TripPackingService.reminderDatesAreValid(
                            reminderDate: reminderDate,
                            finalCheckDate: finalCheckDate
                        )
                )
            }
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
            if !destinationDrafts.isEmpty {
                destinationDrafts[0].startDate = newValue
            }
        }
    }

}

private struct PackingReminderPermissionView: View {
    let status: UNAuthorizationStatus
    let hasEnabledReminders: Bool
    let hasFutureReminder: Bool
    let requestPermission: () -> Void

    var body: some View {
        if hasEnabledReminders {
            if status == .notDetermined {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow notifications so Little Windows can alert the family at these times.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Allow Notifications", action: requestPermission)
                }
            } else if status == .denied {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Reminder dates will be saved, but notifications are off.", systemImage: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Notification Settings", destination: settingsURL)
                    }
                }
            }
            if !hasFutureReminder {
                Label("Choose a future time to schedule an alert.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct TripDestinationsEditor: View {
    let destinations: [TripDestinationDraft]
    let tripStartDate: Date
    let tripEndDate: Date
    let timeZone: TimeZone
    let onChange: ([TripDestinationDraft]) -> Void

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    private var additionalStartRange: ClosedRange<Date> {
        let preferredStart = calendar.date(byAdding: .day, value: 1, to: tripStartDate)
            ?? tripStartDate
        let lowerBound = min(preferredStart, tripEndDate)
        return lowerBound...tripEndDate
    }

    private var nextDestinationDate: Date? {
        guard let latest = destinations.map(\.startDate).max() else { return tripStartDate }
        guard tripEndDate > tripStartDate else { return nil }
        let next = calendar.date(byAdding: .day, value: 1, to: latest) ?? tripEndDate
        return next <= tripEndDate ? next : nil
    }

    var body: some View {
        Section {
            ForEach(destinations) { destination in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink {
                        TripDestinationPickerView(selection: destination.destination) { selection in
                            updateDestination(destination.id, selection: selection)
                        }
                    } label: {
                        LabeledContent(destinationLabel(for: destination.id)) {
                            Text(destination.destination?.name ?? "Choose")
                                .foregroundStyle(destination.destination == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .accessibilityIdentifier(
                        "trip.destination.select.\((destinations.firstIndex(where: { $0.id == destination.id }) ?? 0) + 1)"
                    )

                    if let detail = destination.destination?.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if destination.id == destinations.first?.id {
                        Label("Starts with the trip", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        DatePicker(
                            "Starting",
                            selection: startDateBinding(for: destination.id),
                            in: additionalStartRange,
                            displayedComponents: .date
                        )
                        .environment(\.timeZone, timeZone)
                    }

                    Button("Remove Destination", systemImage: "minus.circle", role: .destructive) {
                        remove(destination.id)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Button("Add Destination", systemImage: "mappin.and.ellipse") {
                addDestination()
            }
            .disabled(nextDestinationDate == nil)
            .accessibilityIdentifier("trip.destination.add")
        } header: {
            Text("Destinations")
        } footer: {
            Text("Each destination begins on its selected date and continues until the next destination starts. Add destinations in travel order.")
        }
    }

    private func destinationLabel(for id: UUID) -> String {
        guard let index = destinations.firstIndex(where: { $0.id == id }) else {
            return "Destination"
        }
        return "Destination \(index + 1)"
    }

    private func updateDestination(_ id: UUID, selection: TripDestinationSelection?) {
        var updated = destinations
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].destination = selection
        onChange(updated)
    }

    private func startDateBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: {
                destinations.first(where: { $0.id == id })?.startDate ?? tripStartDate
            },
            set: { newValue in
                var updated = destinations
                guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
                updated[index].startDate = newValue
                onChange(updated)
            }
        )
    }

    private func addDestination() {
        guard let date = nextDestinationDate else { return }
        var updated = destinations
        updated.append(TripDestinationDraft(startDate: date))
        onChange(updated)
    }

    private func remove(_ id: UUID) {
        var updated = destinations
        updated.removeAll { $0.id == id }
        if !updated.isEmpty {
            updated[0].startDate = tripStartDate
        }
        onChange(updated)
    }
}

struct TripDestinationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    private let currentSelection: TripDestinationSelection?
    let onSelect: (TripDestinationSelection?) -> Void

    @State private var query: String
    @State private var results = [TripDestinationSelection]()
    @State private var cachedResults = [String: [TripDestinationSelection]]()
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var retryToken = 0

    init(
        selection: TripDestinationSelection?,
        onSelect: @escaping (TripDestinationSelection?) -> Void
    ) {
        currentSelection = selection
        _query = State(initialValue: "")
        self.onSelect = onSelect
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if let currentSelection {
                Section("Selected") {
                    destinationButton(currentSelection, selected: true)
                    Button("Clear Destination", systemImage: "xmark.circle", role: .destructive) {
                        commit(nil)
                    }
                }
            }

            if isSearching {
                Section {
                    HStack {
                        ProgressView()
                        Text("Finding destinations…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let searchError {
                Section {
                    ContentUnavailableView(
                        "Search Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(searchError)
                    )
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        retryToken += 1
                    }
                }
            } else if !results.isEmpty {
                Section("Search Results") {
                    ForEach(results) { value in
                        destinationButton(value, selected: value.id == currentSelection?.id)
                    }
                }
            } else if !trimmedQuery.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Map Results",
                        systemImage: "mappin.slash",
                        description: Text("Try a city, region, or full place name. You can also keep the text as an offline destination.")
                    )
                }
            }

            if !trimmedQuery.isEmpty {
                Section {
                    Button {
                        let destination = TripDestinationSelection(name: trimmedQuery)
                        commit(destination)
                    } label: {
                        Label("Use “\(trimmedQuery)” Without Weather", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("trip.destination.offline")
                    .accessibilityHint("Saves the destination text without a forecast location")
                } footer: {
                    Text("A destination saved without a map result remains available offline but cannot provide WeatherKit suggestions.")
                }
            }
        }
        .navigationTitle("Destination")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "City, region, or place")
        .task(id: "\(query)|\(retryToken)") {
            await search()
        }
    }

    private func destinationButton(
        _ value: TripDestinationSelection,
        selected: Bool
    ) -> some View {
        Button {
            commit(value)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: value.supportsWeather ? "mappin.and.ellipse" : "square.and.pencil")
                    .foregroundStyle(value.supportsWeather ? .blue : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.name)
                        .foregroundStyle(.primary)
                    if let detail = value.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .accessibilityLabel([value.name, value.detail].compactMap { $0 }.joined(separator: ", "))
    }

    private func commit(_ value: TripDestinationSelection?) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            onSelect(value)
        }
    }

    @MainActor
    private func search() async {
        let requestedQuery = trimmedQuery
        guard requestedQuery.count >= 2 else {
            results = []
            searchError = nil
            isSearching = false
            return
        }
        let cacheKey = requestedQuery.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        if let cached = cachedResults[cacheKey] {
            results = cached
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        searchError = nil
        do {
            try await Task.sleep(for: .milliseconds(200))
            let values = try await TripWeatherService.searchDestinations(matching: requestedQuery)
            guard !Task.isCancelled, requestedQuery == trimmedQuery else { return }
            cachedResults[cacheKey] = values
            results = values
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestedQuery == trimmedQuery else { return }
            results = []
            searchError = "Check your connection and try again, or save the typed destination without weather."
        }
        if requestedQuery == trimmedQuery {
            isSearching = false
        }
    }
}
