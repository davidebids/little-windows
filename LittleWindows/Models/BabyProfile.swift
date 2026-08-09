import Foundation
import SwiftData

enum CareProfileType: String, Codable, CaseIterable, Identifiable {
    case child
    case adult
    case dog

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .child: "Child"
        case .adult: "Adult"
        case .dog: "Dog"
        }
    }

    var systemImage: String {
        switch self {
        case .child: "figure.and.child.holdinghands"
        case .adult: "person.crop.circle.fill"
        case .dog: "pawprint.fill"
        }
    }

    var capabilities: CareProfileCapabilities {
        switch self {
        case .child:
            CareProfileCapabilities(
                supportsSleepPrediction: true,
                supportsSolids: true,
                supportsAgeGuide: true,
                supportsPuppyGuide: false,
                supportsPediatricGrowthReferences: true,
                supportsMedications: true,
                supportsHealthObservations: true
            )
        case .adult:
            CareProfileCapabilities(
                supportsSleepPrediction: false,
                supportsSolids: false,
                supportsAgeGuide: false,
                supportsPuppyGuide: false,
                supportsPediatricGrowthReferences: false,
                supportsMedications: true,
                supportsHealthObservations: true
            )
        case .dog:
            CareProfileCapabilities(
                supportsSleepPrediction: false,
                supportsSolids: false,
                supportsAgeGuide: false,
                supportsPuppyGuide: true,
                supportsPediatricGrowthReferences: false,
                supportsMedications: true,
                supportsHealthObservations: false
            )
        }
    }
}

struct CareProfileCapabilities: Equatable {
    let supportsSleepPrediction: Bool
    let supportsSolids: Bool
    let supportsAgeGuide: Bool
    let supportsPuppyGuide: Bool
    let supportsPediatricGrowthReferences: Bool
    let supportsMedications: Bool
    let supportsHealthObservations: Bool
}

enum AdultCareRelationship: String, Codable, CaseIterable, Identifiable {
    case myself
    case parent
    case grandparent
    case partner
    case sibling
    case relative
    case friend
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .myself: "Myself"
        case .parent: "Parent"
        case .grandparent: "Grandparent"
        case .partner: "Partner"
        case .sibling: "Sibling"
        case .relative: "Other relative"
        case .friend: "Friend"
        case .other: "Someone else"
        }
    }
}

enum CareProfileSharingScope: String, Codable, CaseIterable, Identifiable {
    case privateOnly
    case family

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .privateOnly: "Private"
        case .family: "Family Sync"
        }
    }
}

@Model
final class CareProfile {
    var id: UUID = UUID()
    var profileTypeRawValue: String = CareProfileType.child.rawValue
    var name: String = ""
    var birthDate: Date?
    var sexRawValue: String = ProfileSex.unknown.rawValue
    var adultRelationshipRawValue: String?
    var sharingScopeRawValue: String = CareProfileSharingScope.privateOnly.rawValue
    var ownerIdentifier: String = ""
    var birthWeightKilograms: Double?
    var birthLengthCentimeters: Double?
    var birthHeadCircumferenceCentimeters: Double?
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var displayColor: String?
    var adoptionDate: Date?
    var species: String?
    var breed: String?
    var coatColor: String?
    var microchipNumber: String?
    var vetName: String?
    var vetClinic: String?
    var vetPhone: String?
    var emergencyVet: String?
    var profilePhotoAttachmentID: UUID?

    init(
        id: UUID = UUID(),
        profileType: CareProfileType = .child,
        name: String,
        birthDate: Date? = nil,
        sex: ProfileSex = .unknown,
        adultRelationship: AdultCareRelationship? = nil,
        sharingScope: CareProfileSharingScope = .privateOnly,
        ownerIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier(),
        birthWeightKilograms: Double? = nil,
        birthLengthCentimeters: Double? = nil,
        birthHeadCircumferenceCentimeters: Double? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        displayColor: String? = nil,
        adoptionDate: Date? = nil,
        species: String? = nil,
        breed: String? = nil,
        coatColor: String? = nil,
        microchipNumber: String? = nil,
        vetName: String? = nil,
        vetClinic: String? = nil,
        vetPhone: String? = nil,
        emergencyVet: String? = nil,
        profilePhotoAttachmentID: UUID? = nil
    ) {
        self.id = id
        self.profileTypeRawValue = profileType.rawValue
        self.name = name
        self.birthDate = birthDate
        self.sexRawValue = sex.rawValue
        self.adultRelationshipRawValue = adultRelationship?.rawValue
        self.sharingScopeRawValue = sharingScope.rawValue
        self.ownerIdentifier = ownerIdentifier
        self.birthWeightKilograms = birthWeightKilograms
        self.birthLengthCentimeters = birthLengthCentimeters
        self.birthHeadCircumferenceCentimeters = birthHeadCircumferenceCentimeters
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.displayColor = displayColor
        self.adoptionDate = adoptionDate
        self.species = species
        self.breed = breed
        self.coatColor = coatColor
        self.microchipNumber = microchipNumber
        self.vetName = vetName
        self.vetClinic = vetClinic
        self.vetPhone = vetPhone
        self.emergencyVet = emergencyVet
        self.profilePhotoAttachmentID = profilePhotoAttachmentID
    }

    var profileType: CareProfileType {
        get { CareProfileType(rawValue: profileTypeRawValue)! }
        set { profileTypeRawValue = newValue.rawValue }
    }

    var sex: ProfileSex {
        get { ProfileSex(rawValue: sexRawValue) ?? .unknown }
        set { sexRawValue = newValue.rawValue }
    }

    var adultRelationship: AdultCareRelationship? {
        get { adultRelationshipRawValue.flatMap(AdultCareRelationship.init(rawValue:)) }
        set { adultRelationshipRawValue = newValue?.rawValue }
    }

    var sharingScope: CareProfileSharingScope {
        get { CareProfileSharingScope(rawValue: sharingScopeRawValue)! }
        set { sharingScopeRawValue = newValue.rawValue }
    }

    var isSharedWithFamily: Bool {
        sharingScope == .family
    }

    func isOwned(by caregiverIdentifier: String) -> Bool {
        ownerIdentifier == caregiverIdentifier
    }

    var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }

    var ageDescription: String {
        switch profileType {
        case .child:
            return birthDate.map { DateFormatting.age(from: $0) } ?? "Birthdate not set"
        case .adult:
            return birthDate.map { DateFormatting.age(from: $0) } ?? "Age not set"
        case .dog:
            if let birthDate {
                return DateFormatting.age(from: birthDate)
            }
            if let adoptionDate {
                return "Adopted \(DateFormatting.timeSince(adoptionDate))"
            }
            return "Age not set"
        }
    }

    var profileSubtitle: String {
        switch profileType {
        case .child:
            return ageDescription
        case .adult:
            if let birthDate {
                return DateFormatting.age(from: birthDate)
            }
            if adultRelationship == .myself {
                return "My care"
            }
            return adultRelationship?.displayName ?? ageDescription
        case .dog:
            let breedText = breed?.trimmingCharacters(in: .whitespacesAndNewlines)
            return breedText?.isEmpty == false ? breedText! : "Dog"
        }
    }
}
