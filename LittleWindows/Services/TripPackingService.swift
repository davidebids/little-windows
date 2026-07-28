import Foundation
import SwiftData

struct TripTravelerInput: Equatable {
    var kind: TripTravelerKind
    var profileID: UUID?
    var displayName: String
}

struct PackingTripInput {
    var title: String
    var destination: TripDestinationSelection?
    var startDate: Date
    var endDate: Date
    var travelMode: PackingTravelMode
    var lodgingType: PackingLodgingType
    var laundryAvailable: Bool
    var activities: Set<PackingTripActivity>
    var travelers: [TripTravelerInput]
    var includeStarterList: Bool
    var weatherSuggestionsEnabled: Bool
    var reminderDate: Date?
    var finalCheckDate: Date?
    var notes: String
    var timeZoneIdentifier: String? = nil
    var destinationStops: [TripDestinationStop] = []
}

struct PackingSuggestion: Identifiable, Equatable {
    var templateKey: String
    var title: String
    var category: PackingItemCategory
    var quantity: Double?
    var unit: String?
    var travelerID: UUID?
    var priority: PackingItemPriority = .normal
    var notes: String?

    var id: String { "\(travelerID?.uuidString ?? "shared").\(templateKey)" }
}

enum TripPackingSuggestionEngine {
    static func suggestions(
        for trip: PackingTrip,
        travelers: [TripTraveler]
    ) -> [PackingSuggestion] {
        var values = sharedSuggestions(for: trip)
        for traveler in travelers {
            switch traveler.kind {
            case .adult:
                values.append(contentsOf: adultSuggestions(for: trip, travelerID: traveler.id))
            case .child:
                values.append(contentsOf: childSuggestions(for: trip, travelerID: traveler.id))
            case .dog:
                values.append(contentsOf: dogSuggestions(for: trip, travelerID: traveler.id))
            }
        }
        return values
    }

    static func weatherSuggestions(
        rainLikely: Bool,
        coldWeather: Bool,
        hotOrHighUV: Bool
    ) -> [PackingSuggestion] {
        var values = [PackingSuggestion]()
        if rainLikely {
            values.append(PackingSuggestion(
                templateKey: "weather.rain-jacket",
                title: "Rain jacket or umbrella",
                category: .clothing,
                quantity: 1,
                unit: nil,
                travelerID: nil
            ))
        }
        if coldWeather {
            values.append(PackingSuggestion(
                templateKey: "weather.warm-layer",
                title: "Warm layers",
                category: .clothing,
                quantity: nil,
                unit: nil,
                travelerID: nil
            ))
        }
        if hotOrHighUV {
            values.append(PackingSuggestion(
                templateKey: "weather.sun-protection",
                title: "Sun protection",
                category: .health,
                quantity: nil,
                unit: nil,
                travelerID: nil,
                notes: "Choose products appropriate for each traveler."
            ))
        }
        return values
    }

    private static func sharedSuggestions(for trip: PackingTrip) -> [PackingSuggestion] {
        var values = [
            PackingSuggestion(templateKey: "shared.identification", title: "Identification and travel documents", category: .documents, quantity: nil, unit: nil, travelerID: nil, priority: .essential),
            PackingSuggestion(templateKey: "shared.chargers", title: "Device chargers", category: .electronics, quantity: nil, unit: nil, travelerID: nil),
            PackingSuggestion(templateKey: "shared.medicines", title: "Usual medicines", category: .health, quantity: nil, unit: nil, travelerID: nil, priority: .essential, notes: "Pack only medicines already chosen for your household."),
            PackingSuggestion(templateKey: "shared.snacks", title: "Travel snacks", category: .feeding, quantity: nil, unit: nil, travelerID: nil),
            PackingSuggestion(templateKey: "shared.water", title: "Water bottles", category: .essentials, quantity: nil, unit: nil, travelerID: nil)
        ]
        if trip.travelMode == .plane {
            values.append(PackingSuggestion(templateKey: "plane.carry-on-change", title: "Carry-on change of clothes", category: .clothing, quantity: 1, unit: "set", travelerID: nil))
        }
        if trip.lodgingType == .camping {
            values.append(PackingSuggestion(templateKey: "camping.light", title: "Flashlight or headlamp", category: .gear, quantity: 1, unit: nil, travelerID: nil))
        }
        if trip.activities.contains(.beach) || trip.activities.contains(.swimming) {
            values.append(PackingSuggestion(templateKey: "activity.towels", title: "Swim towels", category: .activities, quantity: nil, unit: nil, travelerID: nil))
        }
        return values
    }

    private static func adultSuggestions(
        for trip: PackingTrip,
        travelerID: UUID
    ) -> [PackingSuggestion] {
        let clothingDays = trip.laundryAvailable ? min(4, trip.dayCount) : trip.dayCount
        var values = [
            PackingSuggestion(templateKey: "adult.underwear", title: "Underwear", category: .clothing, quantity: Double(clothingDays + 1), unit: "pairs", travelerID: travelerID),
            PackingSuggestion(templateKey: "adult.socks", title: "Socks", category: .clothing, quantity: Double(clothingDays), unit: "pairs", travelerID: travelerID),
            PackingSuggestion(templateKey: "adult.tops", title: "Tops", category: .clothing, quantity: Double(clothingDays), unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "adult.bottoms", title: "Bottoms", category: .clothing, quantity: Double(max(2, (clothingDays + 1) / 2)), unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "adult.sleepwear", title: "Sleepwear", category: .sleep, quantity: 1, unit: "set", travelerID: travelerID),
            PackingSuggestion(templateKey: "adult.toiletries", title: "Toiletries", category: .toiletries, quantity: nil, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "adult.shoes", title: "Everyday shoes", category: .clothing, quantity: 1, unit: "pair", travelerID: travelerID)
        ]
        if trip.activities.contains(.formal) {
            values.append(PackingSuggestion(templateKey: "adult.dress-outfit", title: "Dress-up outfit", category: .clothing, quantity: 1, unit: "set", travelerID: travelerID))
        }
        if trip.activities.contains(.beach) || trip.activities.contains(.swimming) {
            values.append(PackingSuggestion(templateKey: "adult.swimwear", title: "Swimwear", category: .activities, quantity: 1, unit: nil, travelerID: travelerID))
        }
        if trip.activities.contains(.coldWeather) {
            values.append(PackingSuggestion(templateKey: "adult.warm-layer", title: "Warm outer layer", category: .clothing, quantity: 1, unit: nil, travelerID: travelerID))
        }
        return values
    }

    private static func childSuggestions(
        for trip: PackingTrip,
        travelerID: UUID
    ) -> [PackingSuggestion] {
        let clothingDays = trip.laundryAvailable ? min(4, trip.dayCount) : trip.dayCount
        var values = [
            PackingSuggestion(templateKey: "child.outfits", title: "Outfits", category: .clothing, quantity: Double(clothingDays + 2), unit: "sets", travelerID: travelerID),
            PackingSuggestion(templateKey: "child.pajamas", title: "Pajamas", category: .sleep, quantity: Double(max(2, (clothingDays + 1) / 2)), unit: "sets", travelerID: travelerID),
            PackingSuggestion(templateKey: "child.diapers", title: "Diapers or training supplies", category: .diapering, quantity: Double(trip.dayCount * 7), unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "child.wipes", title: "Wipes", category: .diapering, quantity: Double(max(1, (trip.dayCount + 2) / 3)), unit: "packs", travelerID: travelerID),
            PackingSuggestion(templateKey: "child.feeding", title: "Usual feeding supplies", category: .feeding, quantity: nil, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "child.sleep", title: "Familiar sleep items", category: .sleep, quantity: nil, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "child.comfort", title: "Comfort items and toys", category: .activities, quantity: nil, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "child.car-seat", title: "Car seat", category: .gear, quantity: 1, unit: nil, travelerID: travelerID, priority: .essential),
            PackingSuggestion(templateKey: "child.stroller-carrier", title: "Stroller or carrier", category: .gear, quantity: 1, unit: nil, travelerID: travelerID)
        ]
        if trip.activities.contains(.beach) || trip.activities.contains(.swimming) {
            values.append(PackingSuggestion(templateKey: "child.swim", title: "Swimwear and swim diaper", category: .activities, quantity: 1, unit: "set", travelerID: travelerID))
        }
        return values
    }

    private static func dogSuggestions(
        for trip: PackingTrip,
        travelerID: UUID
    ) -> [PackingSuggestion] {
        [
            PackingSuggestion(templateKey: "dog.food", title: "Usual food", category: .dogCare, quantity: Double(trip.dayCount), unit: "day supply", travelerID: travelerID, priority: .essential),
            PackingSuggestion(templateKey: "dog.bowls", title: "Food and water bowls", category: .dogCare, quantity: 2, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "dog.leash", title: "Leash and harness or collar", category: .dogCare, quantity: 1, unit: "set", travelerID: travelerID, priority: .essential),
            PackingSuggestion(templateKey: "dog.waste", title: "Waste bags", category: .dogCare, quantity: nil, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "dog.bedding", title: "Bed or familiar blanket", category: .sleep, quantity: 1, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "dog.treats", title: "Treats and toys", category: .dogCare, quantity: nil, unit: nil, travelerID: travelerID),
            PackingSuggestion(templateKey: "dog.medicines", title: "Usual medicines", category: .health, quantity: nil, unit: nil, travelerID: travelerID, priority: .essential, notes: "Pack only medicines already chosen with your veterinarian."),
            PackingSuggestion(templateKey: "dog.records", title: "Identification and required travel records", category: .documents, quantity: nil, unit: nil, travelerID: travelerID, priority: .essential, notes: "Verify current destination and carrier requirements.")
        ]
    }
}

@MainActor
enum TripPackingService {
    static func validationMessage(for input: PackingTripInput) -> String? {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Add a trip name."
        }
        guard input.endDate >= input.startDate else {
            return "The trip end date cannot be before its start date."
        }
        let destinationStops = resolvedDestinationStops(
            destination: input.destination,
            destinationStops: input.destinationStops,
            startDate: input.startDate
        )
        guard destinationStopsAreValid(
            destinationStops,
            tripStartDate: input.startDate,
            tripEndDate: input.endDate,
            timeZoneIdentifier: input.timeZoneIdentifier
        ) else {
            return "Each destination needs a valid location and a unique starting day within the trip."
        }
        guard input.travelers.contains(where: {
            !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return "Add at least one traveler."
        }
        if !reminderDatesAreValid(
            reminderDate: input.reminderDate,
            finalCheckDate: input.finalCheckDate
        ) {
            return "The start-packing reminder must be before the final check."
        }
        return nil
    }

    nonisolated static func reminderDatesAreValid(
        reminderDate: Date?,
        finalCheckDate: Date?
    ) -> Bool {
        guard let reminderDate, let finalCheckDate else { return true }
        return reminderDate <= finalCheckDate
    }

    nonisolated static func isValidQuantity(_ quantity: Double?) -> Bool {
        guard let quantity else { return true }
        return quantity.isFinite && quantity > 0
    }

    nonisolated static func uniqueCaregiverNames(
        from candidates: [String?]
    ) -> [String] {
        var values = [String]()
        var seen = Set<String>()
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = CaregiverIdentityService.normalizedName(trimmed),
                  seen.insert(normalized).inserted else { continue }
            values.append(trimmed)
        }
        return values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    nonisolated static func destinationStopsAreValid(
        _ stops: [TripDestinationStop],
        tripStartDate: Date,
        tripEndDate: Date,
        timeZoneIdentifier: String?
    ) -> Bool {
        guard tripEndDate >= tripStartDate else { return false }
        guard !stops.isEmpty else { return true }
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let startKey = TripDayKey(date: tripStartDate, timeZone: timeZone)
        let endKey = TripDayKey(date: tripEndDate, timeZone: timeZone)
        let keys = stops.map { TripDayKey(date: $0.startDate, timeZone: timeZone) }
        guard keys.min() == startKey,
              Set(keys).count == keys.count,
              keys.allSatisfy({ $0 >= startKey && $0 <= endKey }) else {
            return false
        }
        return stops.allSatisfy { stop in
            let name = stop.destination.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let coordinatesAreValid: Bool
            switch (stop.destination.latitude, stop.destination.longitude) {
            case (nil, nil):
                coordinatesAreValid = true
            case (let latitude?, let longitude?):
                coordinatesAreValid = latitude.isFinite
                    && longitude.isFinite
                    && (-90...90).contains(latitude)
                    && (-180...180).contains(longitude)
            default:
                coordinatesAreValid = false
            }
            let timeZoneIsValid = stop.destination.timeZoneIdentifier.map {
                TimeZone(identifier: $0) != nil
            } ?? true
            return !name.isEmpty && coordinatesAreValid && timeZoneIsValid
        }
    }

    nonisolated static func resolvedDestinationStops(
        destination: TripDestinationSelection?,
        destinationStops: [TripDestinationStop],
        startDate: Date
    ) -> [TripDestinationStop] {
        if !destinationStops.isEmpty { return destinationStops }
        guard let destination else { return [] }
        return [TripDestinationStop(destination: destination, startDate: startDate)]
    }

    static func createTrip(
        input: PackingTripInput,
        householdID: UUID,
        existingTrips: [PackingTrip],
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> PackingTrip? {
        guard validationMessage(for: input) == nil else { return nil }
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let travelerInputs = input.travelers.compactMap { value -> TripTravelerInput? in
            let name = value.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return TripTravelerInput(kind: value.kind, profileID: value.profileID, displayName: name)
        }
        guard !travelerInputs.isEmpty else { return nil }

        let destinationStops = resolvedDestinationStops(
            destination: input.destination,
            destinationStops: input.destinationStops,
            startDate: input.startDate
        )
        let primaryDestination = destinationStops.first?.destination ?? input.destination

        let trip = PackingTrip(
            householdID: householdID,
            title: title,
            destinationName: primaryDestination?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            destinationDetail: primaryDestination?.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            destinationLatitude: primaryDestination?.latitude,
            destinationLongitude: primaryDestination?.longitude,
            destinationTimeZoneIdentifier: primaryDestination?.timeZoneIdentifier,
            destinationStops: destinationStops,
            startDate: input.startDate,
            endDate: input.endDate,
            timeZoneIdentifier: input.timeZoneIdentifier ?? CareTimeZoneSettings.effectiveIdentifier(),
            travelMode: input.travelMode,
            lodgingType: input.lodgingType,
            laundryAvailable: input.laundryAvailable,
            activities: input.activities,
            notes: input.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            weatherSuggestionsEnabled: input.weatherSuggestionsEnabled,
            reminderDate: input.reminderDate,
            finalCheckDate: input.finalCheckDate,
            createdBy: caregiverName,
            createdAt: now,
            updatedAt: now,
            sortOrder: (existingTrips.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        )
        context.insert(trip)

        var travelers = [TripTraveler]()
        for (index, value) in travelerInputs.enumerated() {
            let traveler = TripTraveler(
                householdID: householdID,
                tripID: trip.id,
                kind: value.kind,
                profileID: value.profileID,
                displayName: value.displayName,
                createdAt: now,
                updatedAt: now,
                sortOrder: index
            )
            travelers.append(traveler)
            context.insert(traveler)
        }

        let sharedBag = PackingBag(
            householdID: householdID,
            tripID: trip.id,
            name: "Shared Bag",
            createdAt: now,
            updatedAt: now
        )
        context.insert(sharedBag)

        if input.includeStarterList {
            for (index, suggestion) in TripPackingSuggestionEngine.suggestions(
                for: trip,
                travelers: travelers
            ).enumerated() {
                context.insert(PackingItem(
                    householdID: householdID,
                    tripID: trip.id,
                    travelerID: suggestion.travelerID,
                    templateKey: suggestion.templateKey,
                    title: suggestion.title,
                    category: suggestion.category,
                    quantity: suggestion.quantity,
                    unit: suggestion.unit,
                    notes: suggestion.notes,
                    priority: suggestion.priority,
                    addedBy: caregiverName,
                    createdAt: now,
                    updatedAt: now,
                    sortOrder: index
                ))
            }
        }
        guard PersistenceService.save(context: context) else { return nil }
        scheduleReminders(for: trip, context: context)
        return trip
    }

    static func addItem(
        to trip: PackingTrip,
        title: String,
        category: PackingItemCategory,
        travelerID: UUID?,
        bagID: UUID? = nil,
        quantity: Double? = nil,
        unit: String = "",
        notes: String = "",
        priority: PackingItemPriority = .normal,
        needsPurchase: Bool = false,
        assignedCaregiverName: String? = nil,
        caregiverReminderEnabled: Bool = true,
        existingItems: [PackingItem],
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> PackingItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidQuantity(quantity) else { return nil }
        let nextOrder = (existingItems.filter { $0.tripID == trip.id }.map(\.sortOrder).max() ?? -1) + 1
        let item = PackingItem(
            householdID: trip.householdID,
            tripID: trip.id,
            travelerID: travelerID,
            bagID: bagID,
            title: trimmed,
            category: category,
            quantity: quantity,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            priority: priority,
            needsPurchase: needsPurchase,
            addedBy: caregiverName,
            assignedCaregiverName: assignedCaregiverName?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            caregiverReminderEnabled: caregiverReminderEnabled,
            createdAt: now,
            updatedAt: now,
            sortOrder: nextOrder
        )
        context.insert(item)
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return nil }
        scheduleReminders(for: trip, context: context)
        return item
    }

    static func addSuggestions(
        _ suggestions: [PackingSuggestion],
        to trip: PackingTrip,
        existingItems: [PackingItem],
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> Int {
        let existingKeys = Set(existingItems.filter { $0.tripID == trip.id }.compactMap { item -> String? in
            guard let templateKey = item.templateKey else { return nil }
            return "\(item.travelerID?.uuidString ?? "shared").\(templateKey)"
        })
        var nextOrder = (existingItems.filter { $0.tripID == trip.id }.map(\.sortOrder).max() ?? -1) + 1
        var added = 0
        for suggestion in suggestions where !existingKeys.contains(suggestion.id) {
            context.insert(PackingItem(
                householdID: trip.householdID,
                tripID: trip.id,
                travelerID: suggestion.travelerID,
                templateKey: suggestion.templateKey,
                title: suggestion.title,
                category: suggestion.category,
                quantity: suggestion.quantity,
                unit: suggestion.unit,
                notes: suggestion.notes,
                priority: suggestion.priority,
                addedBy: caregiverName,
                createdAt: now,
                updatedAt: now,
                sortOrder: nextOrder
            ))
            nextOrder += 1
            added += 1
        }
        guard added > 0 else { return 0 }
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return 0 }
        scheduleReminders(for: trip, context: context)
        return added
    }

    static func addTraveler(
        to trip: PackingTrip,
        kind: TripTravelerKind,
        profileID: UUID?,
        displayName: String,
        includeStarterItems: Bool,
        existingTravelers: [TripTraveler],
        existingItems: [PackingItem],
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> TripTraveler? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let tripTravelers = existingTravelers.filter { $0.tripID == trip.id }
        if let profileID,
           tripTravelers.contains(where: { $0.profileID == profileID }) {
            return nil
        }
        let traveler = TripTraveler(
            householdID: trip.householdID,
            tripID: trip.id,
            kind: kind,
            profileID: profileID,
            displayName: name,
            createdAt: now,
            updatedAt: now,
            sortOrder: (tripTravelers.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(traveler)
        if includeStarterItems {
            let suggestions = TripPackingSuggestionEngine.suggestions(
                for: trip,
                travelers: [traveler]
            ).filter { $0.travelerID == traveler.id }
            var nextOrder = (existingItems.filter { $0.tripID == trip.id }.map(\.sortOrder).max() ?? -1) + 1
            for suggestion in suggestions {
                context.insert(PackingItem(
                    householdID: trip.householdID,
                    tripID: trip.id,
                    travelerID: traveler.id,
                    templateKey: suggestion.templateKey,
                    title: suggestion.title,
                    category: suggestion.category,
                    quantity: suggestion.quantity,
                    unit: suggestion.unit,
                    notes: suggestion.notes,
                    priority: suggestion.priority,
                    addedBy: caregiverName,
                    createdAt: now,
                    updatedAt: now,
                    sortOrder: nextOrder
                ))
                nextOrder += 1
            }
        }
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return nil }
        return traveler
    }

    static func updateTravelerName(
        _ traveler: TripTraveler,
        displayName: String,
        trip: PackingTrip,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard traveler.kind == .adult, !name.isEmpty else { return false }
        traveler.displayName = name
        traveler.updatedAt = now
        trip.updatedAt = now
        return PersistenceService.save(context: context)
    }

    static func removeTraveler(
        _ traveler: TripTraveler,
        from trip: PackingTrip,
        travelers: [TripTraveler],
        bags: [PackingBag],
        items: [PackingItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let tripTravelers = travelers.filter { $0.tripID == trip.id }
        guard traveler.tripID == trip.id, tripTravelers.count > 1 else { return false }
        for item in items where item.tripID == trip.id && item.travelerID == traveler.id {
            item.travelerID = nil
            item.updatedAt = now
        }
        for bag in bags where bag.tripID == trip.id && bag.travelerID == traveler.id {
            bag.travelerID = nil
            bag.updatedAt = now
        }
        context.delete(traveler)
        trip.updatedAt = now
        return PersistenceService.save(context: context)
    }

    @discardableResult
    static func setState(
        _ item: PackingItem,
        state: PackingItemState,
        trip: PackingTrip,
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> Bool {
        guard item.state != state else { return true }
        let previousState = item.state
        item.state = state
        item.updatedAt = now
        if state == .packed {
            item.packedAt = now
            item.packedBy = caregiverName
        } else {
            if previousState == .packed { item.lastUnpackedAt = now }
            item.packedAt = nil
            item.packedBy = nil
        }
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    static func updateItem(
        _ item: PackingItem,
        title: String,
        category: PackingItemCategory,
        travelerID: UUID?,
        bagID: UUID?,
        quantity: Double?,
        unit: String,
        notes: String,
        priority: PackingItemPriority,
        needsPurchase: Bool,
        assignedCaregiverName: String?,
        caregiverReminderEnabled: Bool,
        trip: PackingTrip,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidQuantity(quantity) else { return false }
        item.title = trimmed
        item.category = category
        item.travelerID = travelerID
        item.bagID = bagID
        item.quantity = quantity
        item.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.priority = priority
        item.needsPurchase = needsPurchase
        item.assignedCaregiverName = assignedCaregiverName?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.caregiverReminderEnabled = caregiverReminderEnabled
        item.updatedAt = now
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    @discardableResult
    static func reorderItems(
        _ sectionItems: [PackingItem],
        from source: IndexSet,
        to destination: Int,
        trip: PackingTrip,
        allItems: [PackingItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard sectionItems.count > 1,
              let firstItem = sectionItems.first else {
            return false
        }
        let travelerID = firstItem.travelerID
        guard sectionItems.allSatisfy({
                  $0.tripID == trip.id && $0.travelerID == travelerID
              }),
              let reorderedSection = reorderedValues(
                  sectionItems,
                  from: source,
                  to: destination
              ),
              reorderedSection.map(\.id) != sectionItems.map(\.id) else {
            return false
        }

        let tripItems = allItems
            .filter { $0.tripID == trip.id }
            .sorted {
                ($0.sortOrder, $0.createdAt, $0.id.uuidString)
                    < ($1.sortOrder, $1.createdAt, $1.id.uuidString)
            }
        let sectionItemIDs = Set(sectionItems.map(\.id))
        guard sectionItemIDs.count == sectionItems.count,
              sectionItemIDs.isSubset(of: Set(tripItems.map(\.id))) else {
            return false
        }

        var reorderedSectionIterator = reorderedSection.makeIterator()
        let reorderedTripItems = tripItems.map { item in
            sectionItemIDs.contains(item.id) ? (reorderedSectionIterator.next() ?? item) : item
        }
        for (index, item) in reorderedTripItems.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.updatedAt = now
        }
        trip.updatedAt = now
        return PersistenceService.save(context: context)
    }

    static func updateTrip(
        _ trip: PackingTrip,
        title: String,
        destination: TripDestinationSelection?,
        destinationStops: [TripDestinationStop]? = nil,
        startDate: Date,
        endDate: Date,
        travelMode: PackingTravelMode,
        lodgingType: PackingLodgingType,
        laundryAvailable: Bool,
        activities: Set<PackingTripActivity>,
        weatherSuggestionsEnabled: Bool,
        reminderDate: Date?,
        finalCheckDate: Date?,
        notes: String,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStops = resolvedDestinationStops(
            destination: destination,
            destinationStops: destinationStops ?? [],
            startDate: startDate
        )
        guard !trimmedTitle.isEmpty,
              endDate >= startDate,
              destinationStopsAreValid(
                  resolvedStops,
                  tripStartDate: startDate,
                  tripEndDate: endDate,
                  timeZoneIdentifier: trip.timeZoneIdentifier
              ),
              reminderDatesAreValid(
                  reminderDate: reminderDate,
                  finalCheckDate: finalCheckDate
              ) else { return false }
        trip.title = trimmedTitle
        trip.destinationName = destination?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.destinationDetail = destination?.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.destinationLatitude = destination?.latitude
        trip.destinationLongitude = destination?.longitude
        trip.destinationTimeZoneIdentifier = destination?.timeZoneIdentifier
        trip.startDate = startDate
        trip.endDate = endDate
        trip.destinationStops = resolvedStops
        trip.travelMode = travelMode
        trip.lodgingType = lodgingType
        trip.laundryAvailable = laundryAvailable
        trip.activities = activities
        trip.weatherSuggestionsEnabled = weatherSuggestionsEnabled
        trip.reminderDate = reminderDate
        trip.finalCheckDate = finalCheckDate
        trip.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    @discardableResult
    static func deleteItem(
        _ item: PackingItem,
        trip: PackingTrip,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        context.delete(item)
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    static func addBag(
        to trip: PackingTrip,
        name: String,
        travelerID: UUID?,
        existingBags: [PackingBag],
        context: ModelContext,
        now: Date = Date()
    ) -> PackingBag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !existingBags.contains(where: {
                  $0.tripID == trip.id
                      && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return nil }
        let bag = PackingBag(
            householdID: trip.householdID,
            tripID: trip.id,
            travelerID: travelerID,
            name: trimmed,
            createdAt: now,
            updatedAt: now,
            sortOrder: (existingBags.filter { $0.tripID == trip.id }.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(bag)
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return nil }
        return bag
    }

    static func updateBag(
        _ bag: PackingBag,
        name: String,
        travelerID: UUID?,
        trip: PackingTrip,
        existingBags: [PackingBag],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bag.tripID == trip.id,
              !trimmed.isEmpty,
              !existingBags.contains(where: {
                  $0.tripID == trip.id
                      && $0.id != bag.id
                      && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return false }
        bag.name = trimmed
        bag.travelerID = travelerID
        bag.updatedAt = now
        trip.updatedAt = now
        return PersistenceService.save(context: context)
    }

    static func deleteBag(
        _ bag: PackingBag,
        trip: PackingTrip,
        items: [PackingItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard bag.tripID == trip.id else { return false }
        for item in items where item.tripID == trip.id && item.bagID == bag.id {
            item.bagID = nil
            item.updatedAt = now
        }
        context.delete(bag)
        trip.updatedAt = now
        return PersistenceService.save(context: context)
    }

    static func addToShoppingList(
        _ item: PackingItem,
        trip: PackingTrip,
        shoppingList: ShoppingList,
        existingShoppingItems: [ShoppingListItem],
        context: ModelContext,
        now: Date = Date()
    ) -> ShoppingListItem? {
        guard item.householdID == shoppingList.householdID else { return nil }
        if let relatedID = item.relatedShoppingItemID,
           let existing = existingShoppingItems.first(where: { $0.id == relatedID }) {
            return existing
        }
        item.relatedShoppingItemID = nil
        guard let shoppingItem = ShoppingListService.addItem(
            named: item.title,
            to: shoppingList,
            sectionID: nil,
            existingItems: existingShoppingItems,
            context: context,
            now: now,
            saveImmediately: false
        ) else { return nil }
        if shoppingItem.quantity == nil { shoppingItem.quantity = item.quantity }
        if shoppingItem.unit == nil { shoppingItem.unit = item.unit }
        shoppingItem.addedBy = CaregiverIdentityService.currentCaregiverName()
        shoppingItem.updatedAt = now
        item.needsPurchase = true
        item.relatedShoppingItemID = shoppingItem.id
        item.updatedAt = now
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return nil }
        return shoppingItem
    }

    static func duplicateTrip(
        _ source: PackingTrip,
        travelers: [TripTraveler],
        bags: [PackingBag],
        items: [PackingItem],
        existingTrips: [PackingTrip],
        context: ModelContext,
        now: Date = Date()
    ) -> PackingTrip? {
        let copiedTimeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        var copiedCalendar = Calendar(identifier: .gregorian)
        copiedCalendar.timeZone = TimeZone(identifier: copiedTimeZoneIdentifier) ?? .current
        let copiedStartDate = copiedCalendar.startOfDay(for: now)
        let copiedDestinationStops = source.destinationStops.map { stop in
            let offset = source.tripCalendar.dateComponents(
                [.day],
                from: source.tripCalendar.startOfDay(for: source.startDate),
                to: source.tripCalendar.startOfDay(for: stop.startDate)
            ).day ?? 0
            return TripDestinationStop(
                destination: stop.destination,
                startDate: copiedCalendar.date(
                    byAdding: .day,
                    value: offset,
                    to: copiedStartDate
                ) ?? copiedStartDate
            )
        }
        let copy = PackingTrip(
            householdID: source.householdID,
            title: uniqueCopyName(source.title, existingTrips: existingTrips),
            destinationName: source.destinationName,
            destinationDetail: source.destinationDetail,
            destinationLatitude: source.destinationLatitude,
            destinationLongitude: source.destinationLongitude,
            destinationTimeZoneIdentifier: source.destinationTimeZoneIdentifier,
            destinationStops: copiedDestinationStops,
            startDate: copiedStartDate,
            endDate: copiedCalendar.date(byAdding: .day, value: max(0, source.dayCount - 1), to: copiedStartDate) ?? copiedStartDate,
            timeZoneIdentifier: copiedTimeZoneIdentifier,
            travelMode: source.travelMode,
            lodgingType: source.lodgingType,
            laundryAvailable: source.laundryAvailable,
            activities: source.activities,
            notes: source.notes,
            weatherSuggestionsEnabled: source.weatherSuggestionsEnabled,
            createdBy: CaregiverIdentityService.currentCaregiverName(),
            createdAt: now,
            updatedAt: now,
            sortOrder: (existingTrips.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        )
        context.insert(copy)

        var travelerMap = [UUID: UUID]()
        for sourceTraveler in travelers.filter({ $0.tripID == source.id }).sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let traveler = TripTraveler(
                householdID: copy.householdID,
                tripID: copy.id,
                kind: sourceTraveler.kind,
                profileID: sourceTraveler.profileID,
                displayName: sourceTraveler.displayName,
                createdAt: now,
                updatedAt: now,
                sortOrder: sourceTraveler.sortOrder
            )
            travelerMap[sourceTraveler.id] = traveler.id
            context.insert(traveler)
        }
        var bagMap = [UUID: UUID]()
        for sourceBag in bags.filter({ $0.tripID == source.id }).sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let bag = PackingBag(
                householdID: copy.householdID,
                tripID: copy.id,
                travelerID: sourceBag.travelerID.flatMap { travelerMap[$0] },
                name: sourceBag.name,
                createdAt: now,
                updatedAt: now,
                sortOrder: sourceBag.sortOrder
            )
            bagMap[sourceBag.id] = bag.id
            context.insert(bag)
        }
        for sourceItem in items.filter({ $0.tripID == source.id }).sorted(by: { $0.sortOrder < $1.sortOrder }) {
            context.insert(PackingItem(
                householdID: copy.householdID,
                tripID: copy.id,
                travelerID: sourceItem.travelerID.flatMap { travelerMap[$0] },
                bagID: sourceItem.bagID.flatMap { bagMap[$0] },
                templateKey: sourceItem.templateKey,
                title: sourceItem.title,
                category: sourceItem.category,
                quantity: sourceItem.quantity,
                unit: sourceItem.unit,
                notes: sourceItem.notes,
                priority: sourceItem.priority,
                needsPurchase: sourceItem.needsPurchase,
                addedBy: CaregiverIdentityService.currentCaregiverName(),
                assignedCaregiverName: sourceItem.assignedCaregiverName,
                caregiverReminderEnabled: sourceItem.caregiverReminderEnabled,
                createdAt: now,
                updatedAt: now,
                sortOrder: sourceItem.sortOrder
            ))
        }
        guard PersistenceService.save(context: context) else { return nil }
        return copy
    }

    @discardableResult
    static func setCompleted(
        _ trip: PackingTrip,
        completed: Bool,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        trip.status = completed ? .completed : .upcoming
        trip.completedAt = completed ? now : nil
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    @discardableResult
    static func archive(
        _ trip: PackingTrip,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !trip.isArchived else { return true }
        trip.isArchived = true
        trip.status = .archived
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    @discardableResult
    static func restore(
        _ trip: PackingTrip,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard trip.isArchived else { return true }
        trip.isArchived = false
        trip.status = trip.completedAt == nil ? .upcoming : .completed
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        scheduleReminders(for: trip, context: context)
        return true
    }

    private static func scheduleReminders(for trip: PackingTrip, context: ModelContext) {
        let tripID = trip.id
        let descriptor = FetchDescriptor<PackingItem>(
            predicate: #Predicate { $0.tripID == tripID }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        let snapshot = PackingTripReminderSnapshot(
            trip: trip,
            items: items,
            currentCaregiverName: CaregiverIdentityService.currentCaregiverName()
        )
        Task { _ = await NotificationManager.shared.reschedulePackingTripReminders(snapshot: snapshot) }
    }

    private static func uniqueCopyName(
        _ sourceName: String,
        existingTrips: [PackingTrip]
    ) -> String {
        let existing = Set(existingTrips.map { $0.title.lowercased() })
        let base = "\(sourceName) Copy"
        guard existing.contains(base.lowercased()) else { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private static func reorderedValues<T>(
        _ values: [T],
        from source: IndexSet,
        to destination: Int
    ) -> [T]? {
        guard !source.isEmpty else { return nil }
        let sourceIndexes = source.sorted()
        guard let lastIndex = sourceIndexes.last,
              lastIndex < values.count,
              destination >= 0,
              destination <= values.count else {
            return nil
        }
        var reordered = values
        let movedValues = sourceIndexes.map { reordered[$0] }
        for index in sourceIndexes.reversed() {
            reordered.remove(at: index)
        }
        let adjustedDestination = destination - sourceIndexes.filter { $0 < destination }.count
        reordered.insert(
            contentsOf: movedValues,
            at: max(0, min(adjustedDestination, reordered.count))
        )
        return reordered
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
