import Foundation
import SwiftData

struct TripDestinationSelection: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var detail: String?
    var latitude: Double?
    var longitude: Double?
    var timeZoneIdentifier: String?

    var id: String {
        if let latitude, let longitude {
            return "\(latitude),\(longitude)"
        }
        return "manual:\(name.lowercased())"
    }

    var supportsWeather: Bool {
        latitude != nil && longitude != nil
    }
}

struct TripDestinationStop: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var destination: TripDestinationSelection
    var startDate: Date

    init(
        id: UUID = UUID(),
        destination: TripDestinationSelection,
        startDate: Date
    ) {
        self.id = id
        self.destination = destination
        self.startDate = startDate
    }
}

struct TripDestinationWeatherWindow: Equatable, Identifiable, Sendable {
    var stop: TripDestinationStop
    var startDate: Date
    var endDate: Date

    var id: UUID { stop.id }
    var destination: TripDestinationSelection { stop.destination }
}

private enum TripDestinationStopCodec {
    static func decode(_ value: String) -> [TripDestinationStop] {
        guard let data = value.data(using: .utf8),
              let stops = try? JSONDecoder().decode([TripDestinationStop].self, from: data) else {
            return []
        }
        return stops
    }

    static func encode(_ stops: [TripDestinationStop]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stops),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }
}

enum PackingTripStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming
    case completed
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }
}

enum PackingTravelMode: String, Codable, CaseIterable, Identifiable {
    case car
    case plane
    case train
    case cruise
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .car: "Car"
        case .plane: "Plane"
        case .train: "Train"
        case .cruise: "Cruise"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .car: "car.fill"
        case .plane: "airplane"
        case .train: "train.side.front.car"
        case .cruise: "ferry.fill"
        case .other: "suitcase.rolling.fill"
        }
    }
}

enum PackingLodgingType: String, Codable, CaseIterable, Identifiable {
    case hotel
    case home
    case camping
    case mixed
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotel: "Hotel"
        case .home: "Home or Rental"
        case .camping: "Camping"
        case .mixed: "Mixed"
        case .other: "Other"
        }
    }
}

enum PackingTripActivity: String, Codable, CaseIterable, Identifiable {
    case beach
    case outdoors
    case swimming
    case sightseeing
    case hiking
    case camping
    case boating
    case waterSports
    case cycling
    case fitness
    case snowSports
    case themeParks
    case business
    case formal
    case coldWeather

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beach: "Beach"
        case .outdoors: "Outdoors"
        case .swimming: "Swimming"
        case .sightseeing: "Sightseeing"
        case .hiking: "Hiking"
        case .camping: "Camping"
        case .boating: "Boating"
        case .waterSports: "Water sports"
        case .cycling: "Cycling"
        case .fitness: "Fitness or workouts"
        case .snowSports: "Snow sports"
        case .themeParks: "Theme parks"
        case .business: "Business or work"
        case .formal: "Dress-up"
        case .coldWeather: "Cold weather"
        }
    }

    var systemImage: String {
        switch self {
        case .beach: "beach.umbrella.fill"
        case .outdoors: "tree.fill"
        case .swimming: "figure.pool.swim"
        case .sightseeing: "binoculars.fill"
        case .hiking: "figure.hiking"
        case .camping: "tent.fill"
        case .boating: "sailboat.fill"
        case .waterSports: "figure.water.fitness"
        case .cycling: "figure.outdoor.cycle"
        case .fitness: "figure.run"
        case .snowSports: "figure.skiing.downhill"
        case .themeParks: "ticket.fill"
        case .business: "briefcase.fill"
        case .formal: "sparkles"
        case .coldWeather: "snowflake"
        }
    }
}

enum TripTravelerKind: String, Codable, CaseIterable, Identifiable {
    case adult
    case child
    case dog

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adult: "Adult"
        case .child: "Child"
        case .dog: "Dog"
        }
    }

    var systemImage: String {
        switch self {
        case .adult: "person.fill"
        case .child: "figure.child"
        case .dog: "pawprint.fill"
        }
    }
}

enum PackingItemCategory: String, Codable, CaseIterable, Identifiable {
    case essentials
    case clothing
    case toiletries
    case feeding
    case diapering
    case sleep
    case health
    case documents
    case electronics
    case activities
    case dogCare
    case gear
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .essentials: "Essentials"
        case .clothing: "Clothing"
        case .toiletries: "Toiletries"
        case .feeding: "Feeding"
        case .diapering: "Diapering"
        case .sleep: "Sleep"
        case .health: "Health"
        case .documents: "Documents"
        case .electronics: "Electronics"
        case .activities: "Activities"
        case .dogCare: "Dog Care"
        case .gear: "Gear"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .essentials: "star.fill"
        case .clothing: "tshirt.fill"
        case .toiletries: "shower.fill"
        case .feeding: "fork.knife"
        case .diapering: "drop.fill"
        case .sleep: "moon.fill"
        case .health: "cross.case.fill"
        case .documents: "doc.text.fill"
        case .electronics: "cable.connector"
        case .activities: "figure.run"
        case .dogCare: "pawprint.fill"
        case .gear: "backpack.fill"
        case .other: "shippingbox.fill"
        }
    }
}

enum PackingItemPriority: String, Codable, CaseIterable, Identifiable {
    case normal
    case essential

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PackingItemState: String, Codable, CaseIterable, Identifiable {
    case needed
    case packed
    case notNeeded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .needed: "Needed"
        case .packed: "Packed"
        case .notNeeded: "Not Needed"
        }
    }
}

@Model
final class PackingTrip {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var title: String = ""
    var destinationName: String?
    var destinationDetail: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var destinationTimeZoneIdentifier: String?
    var destinationStopsRawValue: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var timeZoneIdentifier: String?
    var travelModeRawValue: String = PackingTravelMode.car.rawValue
    var lodgingTypeRawValue: String = PackingLodgingType.home.rawValue
    var laundryAvailable: Bool = false
    var activitiesRawValue: String = ""
    var notes: String?
    var statusRawValue: String = PackingTripStatus.upcoming.rawValue
    var weatherSuggestionsEnabled: Bool = true
    var reminderDate: Date?
    var finalCheckDate: Date?
    var createdBy: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var isArchived: Bool = false
    var sortOrder: Int?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        title: String,
        destinationName: String? = nil,
        destinationDetail: String? = nil,
        destinationLatitude: Double? = nil,
        destinationLongitude: Double? = nil,
        destinationTimeZoneIdentifier: String? = nil,
        destinationStops: [TripDestinationStop] = [],
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String? = nil,
        travelMode: PackingTravelMode = .car,
        lodgingType: PackingLodgingType = .home,
        laundryAvailable: Bool = false,
        activities: Set<PackingTripActivity> = [],
        notes: String? = nil,
        status: PackingTripStatus = .upcoming,
        weatherSuggestionsEnabled: Bool = true,
        reminderDate: Date? = nil,
        finalCheckDate: Date? = nil,
        createdBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        isArchived: Bool = false,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.title = title
        self.destinationName = destinationName
        self.destinationDetail = destinationDetail
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.destinationTimeZoneIdentifier = destinationTimeZoneIdentifier
        self.destinationStopsRawValue = ""
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.travelModeRawValue = travelMode.rawValue
        self.lodgingTypeRawValue = lodgingType.rawValue
        self.laundryAvailable = laundryAvailable
        self.activitiesRawValue = activities.map(\.rawValue).sorted().joined(separator: ",")
        self.notes = notes
        self.statusRawValue = status.rawValue
        self.weatherSuggestionsEnabled = weatherSuggestionsEnabled
        self.reminderDate = reminderDate
        self.finalCheckDate = finalCheckDate
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        if !destinationStops.isEmpty {
            self.destinationStops = destinationStops
        }
    }

    var status: PackingTripStatus {
        get { PackingTripStatus(rawValue: statusRawValue) ?? .upcoming }
        set { statusRawValue = newValue.rawValue }
    }

    var travelMode: PackingTravelMode {
        get { PackingTravelMode(rawValue: travelModeRawValue) ?? .other }
        set { travelModeRawValue = newValue.rawValue }
    }

    var lodgingType: PackingLodgingType {
        get { PackingLodgingType(rawValue: lodgingTypeRawValue) ?? .other }
        set { lodgingTypeRawValue = newValue.rawValue }
    }

    var activities: Set<PackingTripActivity> {
        get {
            Set(activitiesRawValue.split(separator: ",").compactMap {
                PackingTripActivity(rawValue: String($0))
            })
        }
        set { activitiesRawValue = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    var tripTimeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    var destinationTimeZone: TimeZone {
        destinationTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? tripTimeZone
    }

    var destinationStops: [TripDestinationStop] {
        get {
            let decoded = TripDestinationStopCodec.decode(destinationStopsRawValue)
            if !decoded.isEmpty {
                return decoded.sorted { ($0.startDate, $0.id.uuidString) < ($1.startDate, $1.id.uuidString) }
            }
            guard let destinationName else { return [] }
            return [TripDestinationStop(
                id: id,
                destination: TripDestinationSelection(
                    name: destinationName,
                    detail: destinationDetail,
                    latitude: destinationLatitude,
                    longitude: destinationLongitude,
                    timeZoneIdentifier: destinationTimeZoneIdentifier
                ),
                startDate: startDate
            )]
        }
        set {
            let sorted = newValue.sorted {
                ($0.startDate, $0.id.uuidString) < ($1.startDate, $1.id.uuidString)
            }
            destinationStopsRawValue = TripDestinationStopCodec.encode(sorted)
            let primary = sorted.first?.destination
            destinationName = primary?.name
            destinationDetail = primary?.detail
            destinationLatitude = primary?.latitude
            destinationLongitude = primary?.longitude
            destinationTimeZoneIdentifier = primary?.timeZoneIdentifier
        }
    }

    var destinationWeatherWindows: [TripDestinationWeatherWindow] {
        let stops = destinationStops
        guard !stops.isEmpty else { return [] }
        let tripStart = tripCalendar.startOfDay(for: startDate)
        let tripEnd = tripCalendar.startOfDay(for: endDate)
        return stops.enumerated().compactMap { index, stop in
            let windowStart = max(tripStart, tripCalendar.startOfDay(for: stop.startDate))
            let nextStart = stops.indices.contains(index + 1)
                ? tripCalendar.startOfDay(for: stops[index + 1].startDate)
                : nil
            let windowEnd = nextStart.flatMap {
                tripCalendar.date(byAdding: .day, value: -1, to: $0)
            } ?? tripEnd
            guard windowStart <= windowEnd, windowStart <= tripEnd else { return nil }
            return TripDestinationWeatherWindow(
                stop: stop,
                startDate: windowStart,
                endDate: min(windowEnd, tripEnd)
            )
        }
    }

    var destinationSummary: String? {
        let names = destinationStops.map(\.destination.name)
        guard let first = names.first else { return nil }
        return names.count == 1 ? first : "\(first) + \(names.count - 1) more"
    }

    var tripCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tripTimeZone
        return calendar
    }

    var isSingleDay: Bool {
        tripCalendar.isDate(startDate, inSameDayAs: endDate)
    }

    func formattedDate(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = tripCalendar
        formatter.timeZone = tripTimeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var dayCount: Int {
        max(1, (tripCalendar.dateComponents(
            [.day],
            from: tripCalendar.startOfDay(for: startDate),
            to: tripCalendar.startOfDay(for: endDate)
        ).day ?? 0) + 1)
    }
}

@Model
final class TripTraveler {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var tripID: UUID = UUID()
    var kindRawValue: String = TripTravelerKind.adult.rawValue
    var profileID: UUID?
    var displayName: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        householdID: UUID,
        tripID: UUID,
        kind: TripTravelerKind,
        profileID: UUID? = nil,
        displayName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.tripID = tripID
        self.kindRawValue = kind.rawValue
        self.profileID = profileID
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var kind: TripTravelerKind {
        get { TripTravelerKind(rawValue: kindRawValue) ?? .adult }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class PackingBag {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var tripID: UUID = UUID()
    var travelerID: UUID?
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        householdID: UUID,
        tripID: UUID,
        travelerID: UUID? = nil,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.tripID = tripID
        self.travelerID = travelerID
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}

@Model
final class PackingItem {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var tripID: UUID = UUID()
    var travelerID: UUID?
    var bagID: UUID?
    var templateKey: String?
    var title: String = ""
    var categoryRawValue: String = PackingItemCategory.other.rawValue
    var quantity: Double?
    var unit: String?
    var notes: String?
    var priorityRawValue: String = PackingItemPriority.normal.rawValue
    var stateRawValue: String = PackingItemState.needed.rawValue
    var needsPurchase: Bool = false
    var relatedShoppingItemID: UUID?
    var addedBy: String?
    var assignedCaregiverName: String?
    var caregiverReminderEnabled: Bool = true
    var packedBy: String?
    var packedAt: Date?
    var lastUnpackedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        householdID: UUID,
        tripID: UUID,
        travelerID: UUID? = nil,
        bagID: UUID? = nil,
        templateKey: String? = nil,
        title: String,
        category: PackingItemCategory = .other,
        quantity: Double? = nil,
        unit: String? = nil,
        notes: String? = nil,
        priority: PackingItemPriority = .normal,
        state: PackingItemState = .needed,
        needsPurchase: Bool = false,
        relatedShoppingItemID: UUID? = nil,
        addedBy: String? = nil,
        assignedCaregiverName: String? = nil,
        caregiverReminderEnabled: Bool = true,
        packedBy: String? = nil,
        packedAt: Date? = nil,
        lastUnpackedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.tripID = tripID
        self.travelerID = travelerID
        self.bagID = bagID
        self.templateKey = templateKey
        self.title = title
        self.categoryRawValue = category.rawValue
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
        self.priorityRawValue = priority.rawValue
        self.stateRawValue = state.rawValue
        self.needsPurchase = needsPurchase
        self.relatedShoppingItemID = relatedShoppingItemID
        self.addedBy = addedBy
        self.assignedCaregiverName = assignedCaregiverName
        self.caregiverReminderEnabled = caregiverReminderEnabled
        self.packedBy = packedBy
        self.packedAt = packedAt
        self.lastUnpackedAt = lastUnpackedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var category: PackingItemCategory {
        get { PackingItemCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var priority: PackingItemPriority {
        get { PackingItemPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    var state: PackingItemState {
        get { PackingItemState(rawValue: stateRawValue) ?? .needed }
        set { stateRawValue = newValue.rawValue }
    }

    var quantityText: String {
        guard let quantity else { return "" }
        let number = quantity == quantity.rounded()
            ? String(Int(quantity))
            : String(format: "%.1f", quantity)
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }
}
