import Foundation
import SwiftData

enum CareProfileType: String, Codable, CaseIterable, Identifiable {
    case child
    case dog

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .child: "Child"
        case .dog: "Dog"
        }
    }

    var systemImage: String {
        switch self {
        case .child: "figure.and.child.holdinghands"
        case .dog: "pawprint.fill"
        }
    }
}

@Model
final class CareProfile {
    var id: UUID = UUID()
    var profileTypeRawValue: String = CareProfileType.child.rawValue
    var name: String = "Child"
    var birthDate: Date = Date()
    var sexRawValue: String = BabySex.unknown.rawValue
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

    init(
        id: UUID = UUID(),
        profileType: CareProfileType = .child,
        name: String,
        birthDate: Date,
        sex: BabySex = .male,
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
        emergencyVet: String? = nil
    ) {
        self.id = id
        self.profileTypeRawValue = profileType.rawValue
        self.name = name
        self.birthDate = birthDate
        self.sexRawValue = sex.rawValue
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
    }

    var profileType: CareProfileType {
        get { CareProfileType(rawValue: profileTypeRawValue) ?? .child }
        set { profileTypeRawValue = newValue.rawValue }
    }

    var sex: BabySex {
        get { BabySex(rawValue: sexRawValue) ?? .unknown }
        set { sexRawValue = newValue.rawValue }
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
            return DateFormatting.age(from: birthDate)
        case .dog:
            if let adoptionDate {
                return "home \(DateFormatting.age(from: adoptionDate))"
            }
            return DateFormatting.age(from: birthDate)
        }
    }

    var profileSubtitle: String {
        switch profileType {
        case .child:
            return ageDescription
        case .dog:
            let breedText = breed?.trimmingCharacters(in: .whitespacesAndNewlines)
            return breedText?.isEmpty == false ? breedText! : "Dog"
        }
    }
}

typealias BabyProfile = CareProfile
