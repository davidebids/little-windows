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

enum SolidPortionUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case gram
    case ounce
    case teaspoon
    case tablespoon
    case cup
    case piece
    case serving

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gram: "Grams"
        case .ounce: "Ounces"
        case .teaspoon: "Teaspoons"
        case .tablespoon: "Tablespoons"
        case .cup: "Cups"
        case .piece: "Pieces"
        case .serving: "Servings"
        }
    }

    var abbreviatedName: String {
        switch self {
        case .gram: "g"
        case .ounce: "oz"
        case .teaspoon: "tsp"
        case .tablespoon: "tbsp"
        case .cup: "cup"
        case .piece: "piece"
        case .serving: "serving"
        }
    }

    var gramsPerUnit: Double? {
        switch self {
        case .gram: 1
        case .ounce: 28.349523125
        case .teaspoon, .tablespoon, .cup, .piece, .serving: nil
        }
    }
}

enum SolidConsumptionEstimate: String, Codable, CaseIterable, Identifiable, Sendable {
    case exact
    case taste
    case quarter
    case half
    case most
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exact: "Exact"
        case .taste: "Taste"
        case .quarter: "¼"
        case .half: "½"
        case .most: "Most"
        case .all: "All"
        }
    }

    var offeredFraction: Double? {
        switch self {
        case .exact: nil
        case .taste: 0.05
        case .quarter: 0.25
        case .half: 0.5
        case .most: 0.75
        case .all: 1
        }
    }
}

enum SolidNutritionSourceKind: String, Codable, Sendable {
    case usdaFoodDataCentral
    case manualLabel
    case customRecipe

    var displayName: String {
        switch self {
        case .usdaFoodDataCentral: "USDA FoodData Central"
        case .manualLabel: "Manual nutrition label"
        case .customRecipe: "Custom recipe"
        }
    }
}

struct SolidNutritionValues: Codable, Hashable, Sendable {
    var energyKilocalories: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?
    var ironMilligrams: Double?
    var zincMilligrams: Double?
    var calciumMilligrams: Double?
    var vitaminCMilligrams: Double?

    init(
        energyKilocalories: Double? = nil,
        proteinGrams: Double? = nil,
        fatGrams: Double? = nil,
        fiberGrams: Double? = nil,
        ironMilligrams: Double? = nil,
        zincMilligrams: Double? = nil,
        calciumMilligrams: Double? = nil,
        vitaminCMilligrams: Double? = nil
    ) {
        self.energyKilocalories = energyKilocalories
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.ironMilligrams = ironMilligrams
        self.zincMilligrams = zincMilligrams
        self.calciumMilligrams = calciumMilligrams
        self.vitaminCMilligrams = vitaminCMilligrams
    }

    var hasValues: Bool {
        [
            energyKilocalories,
            proteinGrams,
            fatGrams,
            fiberGrams,
            ironMilligrams,
            zincMilligrams,
            calciumMilligrams,
            vitaminCMilligrams
        ].contains { $0 != nil }
    }

    var hasNegativeValue: Bool {
        [
            energyKilocalories,
            proteinGrams,
            fatGrams,
            fiberGrams,
            ironMilligrams,
            zincMilligrams,
            calciumMilligrams,
            vitaminCMilligrams
        ].compactMap { $0 }.contains { $0 < 0 || !$0.isFinite }
    }

    var isComplete: Bool {
        [
            energyKilocalories,
            proteinGrams,
            fatGrams,
            fiberGrams,
            ironMilligrams,
            zincMilligrams,
            calciumMilligrams,
            vitaminCMilligrams
        ].allSatisfy { $0 != nil }
    }

    func scaled(by factor: Double) -> SolidNutritionValues {
        guard factor.isFinite, factor >= 0 else { return SolidNutritionValues() }
        func scaledValue(_ value: Double?) -> Double? {
            guard let value else { return nil }
            let result = value * factor
            return result.isFinite ? result : nil
        }
        return SolidNutritionValues(
            energyKilocalories: scaledValue(energyKilocalories),
            proteinGrams: scaledValue(proteinGrams),
            fatGrams: scaledValue(fatGrams),
            fiberGrams: scaledValue(fiberGrams),
            ironMilligrams: scaledValue(ironMilligrams),
            zincMilligrams: scaledValue(zincMilligrams),
            calciumMilligrams: scaledValue(calciumMilligrams),
            vitaminCMilligrams: scaledValue(vitaminCMilligrams)
        )
    }

    func adding(_ other: SolidNutritionValues) -> SolidNutritionValues {
        func sum(_ lhs: Double?, _ rhs: Double?) -> Double? {
            switch (lhs, rhs) {
            case let (.some(left), .some(right)):
                let result = left + right
                return result.isFinite ? result : nil
            case let (.some(left), .none): return left
            case let (.none, .some(right)): return right
            case (.none, .none): return nil
            }
        }
        return SolidNutritionValues(
            energyKilocalories: sum(energyKilocalories, other.energyKilocalories),
            proteinGrams: sum(proteinGrams, other.proteinGrams),
            fatGrams: sum(fatGrams, other.fatGrams),
            fiberGrams: sum(fiberGrams, other.fiberGrams),
            ironMilligrams: sum(ironMilligrams, other.ironMilligrams),
            zincMilligrams: sum(zincMilligrams, other.zincMilligrams),
            calciumMilligrams: sum(calciumMilligrams, other.calciumMilligrams),
            vitaminCMilligrams: sum(vitaminCMilligrams, other.vitaminCMilligrams)
        )
    }

    static let zero = SolidNutritionValues(
        energyKilocalories: 0,
        proteinGrams: 0,
        fatGrams: 0,
        fiberGrams: 0,
        ironMilligrams: 0,
        zincMilligrams: 0,
        calciumMilligrams: 0,
        vitaminCMilligrams: 0
    )
}

struct SolidNutritionReference: Codable, Hashable, Sendable {
    var sourceKind: SolidNutritionSourceKind
    var sourceID: String
    var sourceDescription: String
    var sourceVersion: String
    var basisQuantity: Double
    var basisUnit: SolidPortionUnit
    var basisGrams: Double?
    var nutrients: SolidNutritionValues
    var portions: [SolidNutritionPortion]
}

struct SolidNutritionPortion: Codable, Hashable, Identifiable, Sendable {
    var unit: SolidPortionUnit
    var gramsPerUnit: Double
    var description: String

    var id: SolidPortionUnit { unit }
}

struct SolidNutritionSnapshot: Codable, Hashable, Sendable {
    var sourceKind: SolidNutritionSourceKind
    var sourceID: String
    var sourceDescription: String
    var sourceVersion: String
    var amountDescription: String
    var eatenAmount: Double?
    var portionUnit: SolidPortionUnit?
    var estimatedEatenGrams: Double?
    var nutrients: SolidNutritionValues
    var isComplete: Bool
    var capturedAt: Date
}

struct SolidManualNutritionLabel: Codable, Hashable, Sendable {
    var servingQuantity: Double
    var servingUnit: SolidPortionUnit
    var servingGrams: Double?
    var sourceDescription: String
    var nutrients: SolidNutritionValues

    var sourceDisplayName: String {
        let cleaned = sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Manual nutrition label" : cleaned
    }

    var isValid: Bool {
        servingQuantity.isFinite
            && servingQuantity > 0
            && (servingGrams.map { $0.isFinite && $0 > 0 } ?? true)
            && nutrients.hasValues
            && !nutrients.hasNegativeValue
    }

    var nutritionReference: SolidNutritionReference? {
        guard isValid else { return nil }
        let grams = servingGrams ?? servingUnit.gramsPerUnit.map { $0 * servingQuantity }
        return SolidNutritionReference(
            sourceKind: .manualLabel,
            sourceID: "manual-label",
            sourceDescription: sourceDisplayName,
            sourceVersion: "1",
            basisQuantity: servingQuantity,
            basisUnit: servingUnit,
            basisGrams: grams,
            nutrients: nutrients,
            portions: grams.map {
                [SolidNutritionPortion(unit: servingUnit, gramsPerUnit: $0 / servingQuantity, description: "Label serving")]
            } ?? []
        )
    }
}

struct CustomSolidRecipeIngredient: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var foodID: String
    var foodName: String
    var amount: Double
    var unit: SolidPortionUnit

    init(
        id: UUID = UUID(),
        foodID: String,
        foodName: String,
        amount: Double,
        unit: SolidPortionUnit
    ) {
        self.id = id
        self.foodID = foodID
        self.foodName = foodName
        self.amount = amount
        self.unit = unit
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
    var amountOffered: Double?
    var amountEaten: Double?
    var portionUnit: SolidPortionUnit?
    var consumptionEstimate: SolidConsumptionEstimate?
    var nutritionSnapshot: SolidNutritionSnapshot?
    var recipeID: String?
    var recipeName: String?
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

struct SolidFeedEditorPreset: Equatable, @unchecked Sendable {
    var foodIDs: [String] = []
    var foodNames: [String] = []
    var allergenIDsByFoodID: [String: [String]] = [:]
    var confirmedAllergenPortionIDs: [String] = []
    var plannedMealID: UUID?
    var recipeID: String?
    var recipeName: String?
    var foodDetails: [SolidFoodLogDetail] = []

    static let empty = SolidFeedEditorPreset()
}

private final class SolidNutritionSnapshotCacheEntry {
    let snapshot: SolidNutritionSnapshot

    init(_ snapshot: SolidNutritionSnapshot) {
        self.snapshot = snapshot
    }
}

private enum SolidNutritionSnapshotDecodeCache {
    static let shared: NSCache<NSString, SolidNutritionSnapshotCacheEntry> = {
        let cache = NSCache<NSString, SolidNutritionSnapshotCacheEntry>()
        cache.countLimit = 6_000
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()
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
    var amountOffered: Double?
    var amountEaten: Double?
    var portionUnitRawValue: String?
    var consumptionEstimateRawValue: String?
    var nutritionSnapshotJSON: String?
    var recipeID: String?
    var recipeNameSnapshot: String?
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
        amountOffered: Double? = nil,
        amountEaten: Double? = nil,
        portionUnit: SolidPortionUnit? = nil,
        consumptionEstimate: SolidConsumptionEstimate? = nil,
        nutritionSnapshot: SolidNutritionSnapshot? = nil,
        recipeID: String? = nil,
        recipeNameSnapshot: String? = nil,
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
        self.amountOffered = amountOffered
        self.amountEaten = amountEaten
        self.portionUnitRawValue = portionUnit?.rawValue
        self.consumptionEstimateRawValue = consumptionEstimate?.rawValue
        self.nutritionSnapshotJSON = Self.encode(nutritionSnapshot)
        self.recipeID = recipeID
        self.recipeNameSnapshot = recipeNameSnapshot
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

    var portionUnit: SolidPortionUnit? {
        get { portionUnitRawValue.flatMap(SolidPortionUnit.init(rawValue:)) }
        set { portionUnitRawValue = newValue?.rawValue }
    }

    var consumptionEstimate: SolidConsumptionEstimate? {
        get { consumptionEstimateRawValue.flatMap(SolidConsumptionEstimate.init(rawValue:)) }
        set { consumptionEstimateRawValue = newValue?.rawValue }
    }

    var nutritionSnapshot: SolidNutritionSnapshot? {
        get {
            guard let nutritionSnapshotJSON else { return nil }
            let key = nutritionSnapshotJSON as NSString
            if let cached = SolidNutritionSnapshotDecodeCache.shared.object(forKey: key) {
                return cached.snapshot
            }
            guard let decoded: SolidNutritionSnapshot = Self.decode(nutritionSnapshotJSON) else {
                return nil
            }
            SolidNutritionSnapshotDecodeCache.shared.setObject(
                SolidNutritionSnapshotCacheEntry(decoded),
                forKey: key,
                cost: nutritionSnapshotJSON.utf8.count
            )
            return decoded
        }
        set {
            nutritionSnapshotJSON = Self.encode(newValue)
            guard let newValue, let nutritionSnapshotJSON else { return }
            SolidNutritionSnapshotDecodeCache.shared.setObject(
                SolidNutritionSnapshotCacheEntry(newValue),
                forKey: nutritionSnapshotJSON as NSString,
                cost: nutritionSnapshotJSON.utf8.count
            )
        }
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

    private static func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func decode<T: Decodable>(_ value: String?) -> T? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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

@Model
final class CustomSolidRecipe {
    var id: UUID = UUID()
    var name: String = ""
    var ingredientsJSON: String = "[]"
    var servings: Double = 1
    var minimumAgeMonths: Int = 6
    var instructions: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        ingredients: [CustomSolidRecipeIngredient],
        servings: Double = 1,
        minimumAgeMonths: Int = 6,
        instructions: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ingredientsJSON = Self.encode(ingredients)
        self.servings = servings
        self.minimumAgeMonths = minimumAgeMonths
        self.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var trackingID: String { "custom-recipe-\(id.uuidString.lowercased())" }

    var ingredients: [CustomSolidRecipeIngredient] {
        get { Self.decode(ingredientsJSON) }
        set { ingredientsJSON = Self.encode(newValue) }
    }

    private static func encode(_ values: [CustomSolidRecipeIngredient]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decode(_ value: String) -> [CustomSolidRecipeIngredient] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CustomSolidRecipeIngredient].self, from: data)) ?? []
    }
}

extension CareEvent {
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
