import Foundation
import SwiftData

enum HouseholdAttentionSourceKind: String, Codable, CaseIterable {
    case medicationDose
    case medicationRefill
    case appointmentFollowUp
    case routine
    case inventory
    case mealPrep
    case returnRequest
    case trip
    case plannedSolidMeal
    case solidAllergen
    case homeReminder
}

@Model
final class AppointmentFollowUp {
    var id: UUID = UUID()
    var appointmentID: UUID = UUID()
    var householdID: UUID = UUID()
    var profileID: UUID?
    var title: String = ""
    var details: String?
    var dueDate: Date?
    var completedAt: Date?
    var completedByCaregiverIdentifier: String?
    var completedByCaregiverName: String?
    var createdByCaregiverIdentifier: String?
    var createdByCaregiverName: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        appointmentID: UUID,
        householdID: UUID,
        profileID: UUID?,
        title: String,
        details: String? = nil,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        completedByCaregiverIdentifier: String? = nil,
        completedByCaregiverName: String? = nil,
        createdByCaregiverIdentifier: String? = nil,
        createdByCaregiverName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.appointmentID = appointmentID
        self.householdID = householdID
        self.profileID = profileID
        self.title = title
        self.details = details
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.completedByCaregiverIdentifier = completedByCaregiverIdentifier
        self.completedByCaregiverName = completedByCaregiverName
        self.createdByCaregiverIdentifier = createdByCaregiverIdentifier
        self.createdByCaregiverName = createdByCaregiverName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isCompleted: Bool { completedAt != nil }

    var attentionSourceKey: String {
        "\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):\(id.uuidString.lowercased())"
    }
}

@Model
final class HouseholdAttentionAcknowledgement {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var profileID: UUID?
    var sourceKey: String = ""
    var sourceUpdatedAt: Date = Date.distantPast
    var caregiverIdentifier: String = ""
    var caregiverName: String = ""
    var acknowledgedAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID,
        householdID: UUID,
        profileID: UUID?,
        sourceKey: String,
        sourceUpdatedAt: Date,
        caregiverIdentifier: String,
        caregiverName: String,
        acknowledgedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.sourceKey = sourceKey
        self.sourceUpdatedAt = sourceUpdatedAt
        self.caregiverIdentifier = caregiverIdentifier
        self.caregiverName = caregiverName
        self.acknowledgedAt = acknowledgedAt
        self.updatedAt = updatedAt
    }
}

@Model
final class HouseholdAttentionClaim {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var profileID: UUID?
    var sourceKey: String = ""
    var caregiverIdentifier: String?
    var caregiverName: String?
    var updatedByCaregiverIdentifier: String = ""
    var updatedByCaregiverName: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID,
        householdID: UUID,
        profileID: UUID?,
        sourceKey: String,
        caregiverIdentifier: String?,
        caregiverName: String?,
        updatedByCaregiverIdentifier: String,
        updatedByCaregiverName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.sourceKey = sourceKey
        self.caregiverIdentifier = caregiverIdentifier
        self.caregiverName = caregiverName
        self.updatedByCaregiverIdentifier = updatedByCaregiverIdentifier
        self.updatedByCaregiverName = updatedByCaregiverName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CaregiverHandoffNote {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var profileID: UUID?
    var sourceKey: String?
    var sourceTitleSnapshot: String?
    var body: String = ""
    var authorCaregiverIdentifier: String = ""
    var authorCaregiverName: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        householdID: UUID,
        profileID: UUID?,
        sourceKey: String?,
        sourceTitleSnapshot: String?,
        body: String,
        authorCaregiverIdentifier: String,
        authorCaregiverName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.profileID = profileID
        self.sourceKey = sourceKey
        self.sourceTitleSnapshot = sourceTitleSnapshot
        self.body = body
        self.authorCaregiverIdentifier = authorCaregiverIdentifier
        self.authorCaregiverName = authorCaregiverName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class FamilyCaregiverIdentity {
    var id: UUID = UUID()
    var householdID: UUID = UUID()
    var caregiverIdentifier: String = ""
    var displayName: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastSeenAt: Date = Date()

    init(
        id: UUID,
        householdID: UUID,
        caregiverIdentifier: String,
        displayName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.caregiverIdentifier = caregiverIdentifier
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
    }
}
