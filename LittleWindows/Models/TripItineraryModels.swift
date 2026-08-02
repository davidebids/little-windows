import Foundation
import SwiftData

enum TripItineraryItemKind: String, Codable, CaseIterable, Identifiable {
    case activity
    case transportation
    case flight
    case lodging
    case meal
    case task
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .activity: "Activity"
        case .transportation: "Transportation"
        case .flight: "Flight"
        case .lodging: "Lodging"
        case .meal: "Meal"
        case .task: "Task"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: "figure.walk"
        case .transportation: "car.fill"
        case .flight: "airplane"
        case .lodging: "bed.double.fill"
        case .meal: "fork.knife"
        case .task: "checkmark.circle"
        case .note: "note.text"
        }
    }

    var supportsCompletion: Bool { self == .task }
    var supportsOrigin: Bool { self == .transportation || self == .flight }
}

enum TripItineraryScheduleKind: String, Codable, CaseIterable, Identifiable {
    case timed
    case morning
    case afternoon
    case evening
    case anytime
    case unscheduled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .timed: "Specific Time"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .anytime: "Anytime"
        case .unscheduled: "Idea — No Day Yet"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .timed: "Timed"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .anytime: "Anytime"
        case .unscheduled: "Idea"
        }
    }

    var sortRank: Int {
        switch self {
        case .morning: 100
        case .timed: 200
        case .afternoon: 300
        case .evening: 400
        case .anytime: 500
        case .unscheduled: 600
        }
    }
}

enum TripItineraryBookingStatus: String, Codable, CaseIterable, Identifiable {
    case idea
    case planned
    case booked
    case cancelled

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .idea: "lightbulb"
        case .planned: "calendar"
        case .booked: "checkmark.seal.fill"
        case .cancelled: "xmark.circle"
        }
    }
}

@Model
final class TripItineraryChoiceGroup {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var tripID: UUID = UUID()
    var title: String = ""
    var notes: String?
    var scheduledDay: Date?
    var selectedItemID: UUID?
    var createdBy: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        householdID: UUID,
        tripID: UUID,
        title: String,
        notes: String? = nil,
        scheduledDay: Date? = nil,
        selectedItemID: UUID? = nil,
        createdBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.tripID = tripID
        self.title = title
        self.notes = notes
        self.scheduledDay = scheduledDay
        self.selectedItemID = selectedItemID
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}

@Model
final class TripItineraryItem {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var tripID: UUID = UUID()
    var choiceGroupID: UUID?
    var title: String = ""
    var kindRawValue: String = TripItineraryItemKind.activity.rawValue
    var scheduleKindRawValue: String = TripItineraryScheduleKind.anytime.rawValue
    var scheduledDay: Date?
    var startDate: Date?
    var endDate: Date?
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var locationName: String?
    var locationDetail: String?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationTimeZoneIdentifier: String?
    var originName: String?
    var originDetail: String?
    var originLatitude: Double?
    var originLongitude: Double?
    var originTimeZoneIdentifier: String?
    var notes: String?
    var bookingStatusRawValue: String = TripItineraryBookingStatus.planned.rawValue
    var providerName: String?
    var confirmationNumber: String?
    var isCompleted: Bool = false
    var assignedCaregiverName: String?
    var reminderEnabled: Bool = false
    var reminderOffsetMinutes: Int = 60
    var createdBy: String?
    var completedBy: String?
    var completedAt: Date?
    var lastReopenedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        householdID: UUID,
        tripID: UUID,
        choiceGroupID: UUID? = nil,
        title: String,
        kind: TripItineraryItemKind = .activity,
        scheduleKind: TripItineraryScheduleKind = .anytime,
        scheduledDay: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        startTimeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        location: TripDestinationSelection? = nil,
        origin: TripDestinationSelection? = nil,
        notes: String? = nil,
        bookingStatus: TripItineraryBookingStatus = .planned,
        providerName: String? = nil,
        confirmationNumber: String? = nil,
        isCompleted: Bool = false,
        assignedCaregiverName: String? = nil,
        reminderEnabled: Bool = false,
        reminderOffsetMinutes: Int = 60,
        createdBy: String? = nil,
        completedBy: String? = nil,
        completedAt: Date? = nil,
        lastReopenedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.tripID = tripID
        self.choiceGroupID = choiceGroupID
        self.title = title
        self.kindRawValue = kind.rawValue
        self.scheduleKindRawValue = scheduleKind.rawValue
        self.scheduledDay = scheduledDay
        self.startDate = startDate
        self.endDate = endDate
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
        self.notes = notes
        self.bookingStatusRawValue = bookingStatus.rawValue
        self.providerName = providerName
        self.confirmationNumber = confirmationNumber
        self.isCompleted = isCompleted
        self.assignedCaregiverName = assignedCaregiverName
        self.reminderEnabled = reminderEnabled
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.createdBy = createdBy
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.lastReopenedAt = lastReopenedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.location = location
        self.origin = origin
    }

    var kind: TripItineraryItemKind {
        get { TripItineraryItemKind(rawValue: kindRawValue) ?? .activity }
        set { kindRawValue = newValue.rawValue }
    }

    var scheduleKind: TripItineraryScheduleKind {
        get { TripItineraryScheduleKind(rawValue: scheduleKindRawValue) ?? .anytime }
        set { scheduleKindRawValue = newValue.rawValue }
    }

    var bookingStatus: TripItineraryBookingStatus {
        get { TripItineraryBookingStatus(rawValue: bookingStatusRawValue) ?? .planned }
        set { bookingStatusRawValue = newValue.rawValue }
    }

    var location: TripDestinationSelection? {
        get {
            guard let locationName else { return nil }
            return TripDestinationSelection(
                name: locationName,
                detail: locationDetail,
                latitude: locationLatitude,
                longitude: locationLongitude,
                timeZoneIdentifier: locationTimeZoneIdentifier
            )
        }
        set {
            locationName = newValue?.name
            locationDetail = newValue?.detail
            locationLatitude = newValue?.latitude
            locationLongitude = newValue?.longitude
            locationTimeZoneIdentifier = newValue?.timeZoneIdentifier
        }
    }

    var origin: TripDestinationSelection? {
        get {
            guard let originName else { return nil }
            return TripDestinationSelection(
                name: originName,
                detail: originDetail,
                latitude: originLatitude,
                longitude: originLongitude,
                timeZoneIdentifier: originTimeZoneIdentifier
            )
        }
        set {
            originName = newValue?.name
            originDetail = newValue?.detail
            originLatitude = newValue?.latitude
            originLongitude = newValue?.longitude
            originTimeZoneIdentifier = newValue?.timeZoneIdentifier
        }
    }

    var reminderDate: Date? {
        guard reminderEnabled, scheduleKind == .timed, let startDate else { return nil }
        return startDate.addingTimeInterval(TimeInterval(-reminderOffsetMinutes * 60))
    }
}

@Model
final class TripItineraryLink {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var tripID: UUID = UUID()
    var itineraryItemID: UUID?
    var title: String = ""
    var urlString: String = ""
    var createdBy: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        householdID: UUID,
        tripID: UUID,
        itineraryItemID: UUID? = nil,
        title: String,
        urlString: String,
        createdBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdID = householdID
        self.tripID = tripID
        self.itineraryItemID = itineraryItemID
        self.title = title
        self.urlString = urlString
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var url: URL? {
        guard let value = URL(string: urlString),
              let scheme = value.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              value.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return value
    }
}
