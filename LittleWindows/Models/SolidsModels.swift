import Foundation
import SwiftData

enum SolidsFoodStatus: String, Codable, CaseIterable, Identifiable {
    case notTried
    case wantToTry
    case tried

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notTried: "Not tried"
        case .wantToTry: "Want to try"
        case .tried: "Tried"
        }
    }
}

enum SolidReactionSeverity: String, Codable, CaseIterable, Identifiable {
    case unknown
    case mild
    case moderate
    case severe

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum SolidReactionFollowUp: String, Codable, CaseIterable, Identifiable {
    case none
    case monitoring
    case resolved
    case discussWithClinician
    case avoidPendingAdvice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .monitoring: "Monitoring"
        case .resolved: "Resolved"
        case .discussWithClinician: "Discuss with clinician"
        case .avoidPendingAdvice: "Avoid pending advice"
        }
    }
}

enum SolidReactionSymptom: String, Codable, CaseIterable, Identifiable {
    case hivesOrRash
    case swelling
    case vomiting
    case diarrhea
    case coughingOrWheezing
    case breathingDifficulty
    case unusualSleepiness
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hivesOrRash: "Hives or rash"
        case .swelling: "Swelling"
        case .vomiting: "Vomiting"
        case .diarrhea: "Diarrhea"
        case .coughingOrWheezing: "Coughing or wheezing"
        case .breathingDifficulty: "Trouble breathing"
        case .unusualSleepiness: "Unusual sleepiness"
        case .other: "Other"
        }
    }
}

enum SolidAllergenStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case introducing
    case tolerated
    case suspectedReaction
    case avoidPendingAdvice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: "Not started"
        case .introducing: "Introducing"
        case .tolerated: "Tolerated"
        case .suspectedReaction: "Reaction noted"
        case .avoidPendingAdvice: "Avoid pending advice"
        }
    }
}

enum SolidsFeedingSkill: String, Codable, CaseIterable, Identifiable {
    case bringsFoodToMouth
    case managesSmoothMash
    case holdsLargeSoftPiece
    case usesPreloadedSpoon
    case managesLumpyTexture
    case picksUpBiteSizeFood
    case drinksFromOpenCup
    case usesPincerGrasp
    case takesBitesFromLargerFood
    case scoopsWithUtensil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bringsFoodToMouth: "Brings food to mouth"
        case .managesSmoothMash: "Manages a smooth mash"
        case .holdsLargeSoftPiece: "Holds a large soft piece"
        case .usesPreloadedSpoon: "Uses a preloaded spoon"
        case .managesLumpyTexture: "Manages a lumpy texture"
        case .picksUpBiteSizeFood: "Picks up bite-size food"
        case .drinksFromOpenCup: "Practices with an open cup"
        case .usesPincerGrasp: "Uses a pincer grasp"
        case .takesBitesFromLargerFood: "Takes bites from larger food"
        case .scoopsWithUtensil: "Scoops with a utensil"
        }
    }

    var detail: String {
        switch self {
        case .bringsFoodToMouth: "Intentionally brings a grasped food toward the mouth."
        case .managesSmoothMash: "Moves and swallows a smooth mashed texture."
        case .holdsLargeSoftPiece: "Grasps and explores a large, soft, resistive piece."
        case .usesPreloadedSpoon: "Brings a caregiver-loaded spoon to the mouth."
        case .managesLumpyTexture: "Handles soft lumps mixed into a familiar texture."
        case .picksUpBiteSizeFood: "Picks up and eats soft, small pieces."
        case .drinksFromOpenCup: "Takes supported sips from a small open cup."
        case .usesPincerGrasp: "Uses thumb and fingertip to pick up small pieces."
        case .takesBitesFromLargerFood: "Bites off a manageable amount from a soft larger piece."
        case .scoopsWithUtensil: "Begins loading and bringing a spoon or fork independently."
        }
    }
}

struct SolidFoodLogDetail: Codable, Hashable, Identifiable {
    var foodID: String
    var foodName: String
    var allergenIDs: [String] = []
    /// `nil` denotes a legacy log made before introduction portions were tracked.
    var confirmedAllergenPortionIDs: [String]?
    var preference: SolidReaction = .unknown
    var servingAmount: String?
    var notes: String?
    var suspectedReaction: Bool = false
    var symptoms: [SolidReactionSymptom] = []
    var severity: SolidReactionSeverity = .unknown
    var onsetMinutes: Int?
    var durationMinutes: Int?
    var responseNotes: String = ""
    var followUp: SolidReactionFollowUp = .none

    var id: String { foodID }
}

struct SolidRecipeCollection: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var recipeIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        recipeIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recipeIDs = Array(Set(recipeIDs)).sorted()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SolidFeedEditorPreset: Equatable {
    var foodIDs: [String] = []
    var foodNames: [String] = []
    var allergenIDsByFoodID: [String: [String]] = [:]
    var confirmedAllergenPortionIDs: [String] = []
    var plannedMealID: UUID?
    var recipeID: String?

    static let empty = SolidFeedEditorPreset()
}

@Model
final class SolidsProfileState {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var isActivated: Bool = false
    var startedAt: Date?
    var readinessNotes: String = ""
    var guidedStartDate: Date?
    var favoriteRecipeIDsJSON: String = "[]"
    var wantToTryRecipeIDsJSON: String = "[]"
    var recipeCollectionsJSON: String = "[]"
    var completedFeedingSkillIDsJSON: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        isActivated: Bool = false,
        startedAt: Date? = nil,
        readinessNotes: String = "",
        guidedStartDate: Date? = nil,
        favoriteRecipeIDs: [String] = [],
        wantToTryRecipeIDs: [String] = [],
        recipeCollections: [SolidRecipeCollection] = [],
        completedFeedingSkillIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.isActivated = isActivated
        self.startedAt = startedAt
        self.readinessNotes = readinessNotes
        self.guidedStartDate = guidedStartDate
        self.favoriteRecipeIDsJSON = Self.encode(favoriteRecipeIDs)
        self.wantToTryRecipeIDsJSON = Self.encode(wantToTryRecipeIDs)
        self.recipeCollectionsJSON = Self.encode(recipeCollections)
        self.completedFeedingSkillIDsJSON = Self.encode(completedFeedingSkillIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var favoriteRecipeIDs: [String] {
        get { Self.decode(favoriteRecipeIDsJSON) }
        set { favoriteRecipeIDsJSON = Self.encode(newValue) }
    }

    var wantToTryRecipeIDs: [String] {
        get { Self.decode(wantToTryRecipeIDsJSON) }
        set { wantToTryRecipeIDsJSON = Self.encode(newValue) }
    }

    var recipeCollections: [SolidRecipeCollection] {
        get { Self.decodeCollections(recipeCollectionsJSON) }
        set { recipeCollectionsJSON = Self.encode(newValue) }
    }

    var completedFeedingSkillIDs: [String] {
        get { Self.decode(completedFeedingSkillIDsJSON) }
        set { completedFeedingSkillIDsJSON = Self.encode(newValue) }
    }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func encode(_ values: [SolidRecipeCollection]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func decodeCollections(_ value: String) -> [SolidRecipeCollection] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SolidRecipeCollection].self, from: data)) ?? []
    }
}

@Model
final class SolidFoodProgress {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var foodID: String = ""
    var foodNameSnapshot: String = ""
    var statusRawValue: String = SolidsFoodStatus.notTried.rawValue
    var isFavorite: Bool = false
    var firstTriedAt: Date?
    var lastTriedAt: Date?
    var exposureCount: Int = 0
    var lastReactionRawValue: String?
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        foodID: String,
        foodNameSnapshot: String,
        status: SolidsFoodStatus = .notTried,
        isFavorite: Bool = false,
        firstTriedAt: Date? = nil,
        lastTriedAt: Date? = nil,
        exposureCount: Int = 0,
        lastReactionRawValue: String? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.foodID = foodID
        self.foodNameSnapshot = foodNameSnapshot
        self.statusRawValue = status.rawValue
        self.isFavorite = isFavorite
        self.firstTriedAt = firstTriedAt
        self.lastTriedAt = lastTriedAt
        self.exposureCount = exposureCount
        self.lastReactionRawValue = lastReactionRawValue
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: SolidsFoodStatus {
        get { SolidsFoodStatus(rawValue: statusRawValue) ?? .notTried }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class SolidFoodEventItem {
    var id: UUID = UUID()
    var eventID: UUID = UUID()
    var profileID: UUID = UUID()
    var foodID: String = ""
    var foodNameSnapshot: String = ""
    var allergenIDsJSON: String = "[]"
    /// `nil` denotes a legacy record whose listed allergens count as confirmed portions.
    var confirmedAllergenPortionIDsJSON: String?
    var reactionRawValue: String?
    var servingAmount: String = ""
    var notes: String = ""
    var suspectedReaction: Bool = false
    var symptomIDsJSON: String = "[]"
    var severityRawValue: String = SolidReactionSeverity.unknown.rawValue
    var onsetMinutes: Int?
    var durationMinutes: Int?
    var responseNotes: String = ""
    var followUpRawValue: String = SolidReactionFollowUp.none.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        eventID: UUID,
        profileID: UUID,
        foodID: String,
        foodNameSnapshot: String,
        allergenIDs: [String] = [],
        confirmedAllergenPortionIDs: [String]? = nil,
        reactionRawValue: String? = nil,
        servingAmount: String = "",
        notes: String = "",
        suspectedReaction: Bool = false,
        symptoms: [SolidReactionSymptom] = [],
        severity: SolidReactionSeverity = .unknown,
        onsetMinutes: Int? = nil,
        durationMinutes: Int? = nil,
        responseNotes: String = "",
        followUp: SolidReactionFollowUp = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.eventID = eventID
        self.profileID = profileID
        self.foodID = foodID
        self.foodNameSnapshot = foodNameSnapshot
        self.allergenIDsJSON = Self.encode(allergenIDs)
        self.confirmedAllergenPortionIDsJSON = confirmedAllergenPortionIDs.map(Self.encode)
        self.reactionRawValue = reactionRawValue
        self.servingAmount = servingAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.suspectedReaction = suspectedReaction
        self.symptomIDsJSON = Self.encode(symptoms.map(\.rawValue))
        self.severityRawValue = severity.rawValue
        self.onsetMinutes = onsetMinutes
        self.durationMinutes = durationMinutes
        self.responseNotes = responseNotes
        self.followUpRawValue = followUp.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var allergenIDs: [String] {
        get { Self.decode(allergenIDsJSON) }
        set { allergenIDsJSON = Self.encode(newValue) }
    }

    var confirmedAllergenPortionIDs: [String]? {
        get { confirmedAllergenPortionIDsJSON.map(Self.decode) }
        set { confirmedAllergenPortionIDsJSON = newValue.map(Self.encode) }
    }

    func confirmsIntroductionPortion(for allergenID: String) -> Bool {
        guard allergenIDs.contains(allergenID) else { return false }
        guard let confirmedAllergenPortionIDs else { return true }
        return confirmedAllergenPortionIDs.contains(allergenID)
    }

    var reaction: SolidReaction {
        get { reactionRawValue.flatMap(SolidReaction.init(rawValue:)) ?? .unknown }
        set { reactionRawValue = newValue.rawValue }
    }

    var symptoms: [SolidReactionSymptom] {
        get { Self.decode(symptomIDsJSON).compactMap(SolidReactionSymptom.init(rawValue:)) }
        set { symptomIDsJSON = Self.encode(newValue.map(\.rawValue)) }
    }

    var severity: SolidReactionSeverity {
        get { SolidReactionSeverity(rawValue: severityRawValue) ?? .unknown }
        set { severityRawValue = newValue.rawValue }
    }

    var followUp: SolidReactionFollowUp {
        get { SolidReactionFollowUp(rawValue: followUpRawValue) ?? .none }
        set { followUpRawValue = newValue.rawValue }
    }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

@Model
final class SolidAllergenProgress {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var allergenID: String = ""
    var statusRawValue: String = SolidAllergenStatus.notStarted.rawValue
    var statusOverrideRawValue: String?
    var introductionStep: Int = 0
    var exposureMealCount: Int = 0
    var firstIntroducedAt: Date?
    var lastExposureAt: Date?
    var nextExposureDueAt: Date?
    var reminderEnabled: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        allergenID: String,
        status: SolidAllergenStatus = .notStarted,
        statusOverride: SolidAllergenStatus? = nil,
        introductionStep: Int = 0,
        exposureMealCount: Int = 0,
        firstIntroducedAt: Date? = nil,
        lastExposureAt: Date? = nil,
        nextExposureDueAt: Date? = nil,
        reminderEnabled: Bool = false,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.allergenID = allergenID
        self.statusRawValue = status.rawValue
        self.statusOverrideRawValue = statusOverride?.rawValue
        self.introductionStep = introductionStep
        self.exposureMealCount = exposureMealCount
        self.firstIntroducedAt = firstIntroducedAt
        self.lastExposureAt = lastExposureAt
        self.nextExposureDueAt = nextExposureDueAt
        self.reminderEnabled = reminderEnabled
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: SolidAllergenStatus {
        get { SolidAllergenStatus(rawValue: statusRawValue) ?? .notStarted }
        set { statusRawValue = newValue.rawValue }
    }

    var statusOverride: SolidAllergenStatus? {
        get { statusOverrideRawValue.flatMap(SolidAllergenStatus.init(rawValue:)) }
        set { statusOverrideRawValue = newValue?.rawValue }
    }
}

@Model
final class PlannedSolidMeal {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var scheduledAt: Date = Date()
    var title: String = "Solids meal"
    var foodIDsJSON: String = "[]"
    var foodNamesJSON: String = "[]"
    var notes: String = ""
    var completedEventID: UUID?
    var recipeID: String?
    var isGuided: Bool = false
    var guidedPosition: Int?
    var allergenID: String?
    var allergenIntroductionStep: Int?
    var allergenServingGuidance: String?
    var allergenObservationMinutes: Int?
    var reminderEnabled: Bool = false
    var reminderOffsetMinutes: Int = 30
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        scheduledAt: Date,
        title: String = "Solids meal",
        foodIDs: [String],
        foodNames: [String],
        notes: String = "",
        completedEventID: UUID? = nil,
        recipeID: String? = nil,
        isGuided: Bool = false,
        guidedPosition: Int? = nil,
        allergenID: String? = nil,
        allergenIntroductionStep: Int? = nil,
        allergenServingGuidance: String? = nil,
        allergenObservationMinutes: Int? = nil,
        reminderEnabled: Bool = false,
        reminderOffsetMinutes: Int = 30,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.scheduledAt = scheduledAt
        self.title = title
        self.foodIDsJSON = Self.encode(foodIDs)
        self.foodNamesJSON = Self.encode(foodNames)
        self.notes = notes
        self.completedEventID = completedEventID
        self.recipeID = recipeID
        self.isGuided = isGuided
        self.guidedPosition = guidedPosition
        self.allergenID = allergenID
        self.allergenIntroductionStep = allergenIntroductionStep
        self.allergenServingGuidance = allergenServingGuidance
        self.allergenObservationMinutes = allergenObservationMinutes
        self.reminderEnabled = reminderEnabled
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var foodIDs: [String] {
        get { Self.decode(foodIDsJSON) }
        set { foodIDsJSON = Self.encode(newValue) }
    }

    var foodNames: [String] {
        get { Self.decode(foodNamesJSON) }
        set { foodNamesJSON = Self.encode(newValue) }
    }

    var isCompleted: Bool { completedEventID != nil }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

extension BabyEvent {
    var solidFoodDetails: [SolidFoodLogDetail] {
        get {
            guard let solidFoodDetailsJSON,
                  let data = solidFoodDetailsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([SolidFoodLogDetail].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty,
                  let data = try? JSONEncoder().encode(newValue),
                  let string = String(data: data, encoding: .utf8) else {
                solidFoodDetailsJSON = nil
                return
            }
            solidFoodDetailsJSON = string
        }
    }
}
