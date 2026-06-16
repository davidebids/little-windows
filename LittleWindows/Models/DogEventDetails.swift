import Foundation

enum DogAmountUnit: String, Codable, CaseIterable, Identifiable {
    case cup
    case ounces = "oz"
    case grams
    case can
    case scoop
    case treatCount
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cup: "Cup"
        case .ounces: "Oz"
        case .grams: "Grams"
        case .can: "Can"
        case .scoop: "Scoop"
        case .treatCount: "Treat count"
        case .other: "Other"
        }
    }
}

enum DogMealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DogEatenAmount: String, Codable, CaseIterable, Identifiable {
    case all
    case most
    case some
    case none
    case unknown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DogWaterUnit: String, Codable, CaseIterable, Identifiable {
    case ounces = "oz"
    case milliliters = "mL"
    case bowl
    case other
    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum DogPottyType: String, Codable, CaseIterable, Identifiable {
    case pee
    case poop
    case both
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var hasPee: Bool { self == .pee || self == .both }
    var hasPoop: Bool { self == .poop || self == .both }
}

enum DogPottyLocation: String, Codable, CaseIterable, Identifiable {
    case outside
    case yard
    case walk
    case pad
    case indoorAccident
    case crateAccident
    case other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .indoorAccident: "Indoor accident"
        case .crateAccident: "Crate accident"
        default: rawValue.capitalized
        }
    }
}

enum DogPeeColor: String, Codable, CaseIterable, Identifiable {
    case clear
    case paleYellow
    case yellow
    case darkYellow
    case orange
    case red
    case unknown
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .paleYellow: "Pale yellow"
        case .darkYellow: "Dark yellow"
        default: rawValue.capitalized
        }
    }
}

enum DogPoopColor: String, Codable, CaseIterable, Identifiable {
    case brown
    case darkBrown
    case yellow
    case green
    case black
    case red
    case unknown
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .darkBrown: "Dark brown"
        default: rawValue.capitalized
        }
    }
}

enum DogStoolQuality: String, Codable, CaseIterable, Identifiable {
    case veryHard
    case firm
    case normal
    case soft
    case loose
    case diarrhea
    case mucus
    case unknown
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .veryHard: "Very hard"
        default: rawValue.capitalized
        }
    }
}

enum DogDistanceUnit: String, Codable, CaseIterable, Identifiable {
    case miles = "mi"
    case kilometers = "km"
    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum DogLeashBehavior: String, Codable, CaseIterable, Identifiable {
    case great
    case okay
    case pulled
    case reactive
    case unknown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DogRestType: String, Codable, CaseIterable, Identifiable {
    case nap
    case overnight
    case crate
    case calmRest
    case other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .calmRest: "Calm rest"
        default: rawValue.capitalized
        }
    }
}

enum DogTrainingType: String, Codable, CaseIterable, Identifiable {
    case pottyTraining
    case crateTraining
    case obedience
    case leash
    case socialization
    case recall
    case trick
    case behavior
    case other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pottyTraining: "Potty training"
        case .crateTraining: "Crate training"
        default: rawValue.capitalized
        }
    }
}

enum DogTrainingOutcome: String, Codable, CaseIterable, Identifiable {
    case great
    case good
    case mixed
    case difficult
    case notApplicable
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .notApplicable: "Not applicable"
        default: rawValue.capitalized
        }
    }
}

enum DogGroomingType: String, Codable, CaseIterable, Identifiable {
    case brush
    case bath
    case nailTrim
    case earCleaning
    case teethBrushing
    case haircut
    case professionalGroomer
    case other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .nailTrim: "Nail trim"
        case .earCleaning: "Ear cleaning"
        case .teethBrushing: "Teeth brushing"
        case .professionalGroomer: "Professional groomer"
        default: rawValue.capitalized
        }
    }
}

enum DogMedicineUnit: String, Codable, CaseIterable, Identifiable {
    case tablet
    case halfTablet
    case capsule
    case milliliters = "mL"
    case drops
    case teaspoons = "tsp"
    case topical
    case injection
    case other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .halfTablet: "Half tablet"
        case .milliliters: "mL"
        case .teaspoons: "tsp"
        default: rawValue.capitalized
        }
    }
}

enum DogMedicineRoute: String, Codable, CaseIterable, Identifiable {
    case oral
    case topical
    case ear
    case eye
    case injection
    case other
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DogVaccineType: String, Codable, CaseIterable, Identifiable {
    case rabies
    case dhpp
    case bordetella
    case leptospirosis
    case influenza
    case lyme
    case other
    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() == rawValue ? rawValue : rawValue.capitalized }
}

enum DogSymptomType: String, Codable, CaseIterable, Identifiable {
    case vomiting
    case diarrhea
    case coughing
    case sneezing
    case itching
    case limping
    case lethargy
    case appetiteChange
    case waterIntakeChange
    case eyeIssue
    case earIssue
    case skinIssue
    case regurgitation
    case other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .appetiteChange: "Appetite change"
        case .waterIntakeChange: "Water intake change"
        case .eyeIssue: "Eye issue"
        case .earIssue: "Ear issue"
        case .skinIssue: "Skin issue"
        default: rawValue.capitalized
        }
    }
}

enum DogSymptomSeverity: String, Codable, CaseIterable, Identifiable {
    case mild
    case moderate
    case severe
    case unknown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DogGlucoseUnit: String, Codable, CaseIterable, Identifiable {
    case mgdl = "mg/dL"
    case mmolL = "mmol/L"
    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum DogMealRelation: String, Codable, CaseIterable, Identifiable {
    case beforeMeal
    case afterMeal
    case fasting
    case unknown
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .beforeMeal: "Before meal"
        case .afterMeal: "After meal"
        default: rawValue.capitalized
        }
    }
}

struct DogEventDetails: Codable, Equatable {
    var foodName: String?
    var foodAmount: Double?
    var foodUnitRawValue: String?
    var mealTypeRawValue: String?
    var eatenAmountRawValue: String?
    var waterAmount: Double?
    var waterUnitRawValue: String?
    var treatName: String?
    var treatQuantity: Double?
    var pottyTypeRawValue: String?
    var pottyLocationRawValue: String?
    var accident: Bool?
    var peeAmountRawValue: String?
    var peeColorRawValue: String?
    var poopAmountRawValue: String?
    var stoolQualityRawValue: String?
    var poopColorRawValue: String?
    var distance: Double?
    var distanceUnitRawValue: String?
    var peeCount: Int?
    var poopCount: Int?
    var leashBehaviorRawValue: String?
    var weather: String?
    var restTypeRawValue: String?
    var trainingTypeRawValue: String?
    var trainingSkill: String?
    var trainingOutcomeRawValue: String?
    var groomingTypeRawValue: String?
    var medicineUnitRawValue: String?
    var medicineRouteRawValue: String?
    var vaccineTypeRawValue: String?
    var vaccineDueDate: Date?
    var vaccineLotNumber: String?
    var vaccineClinic: String?
    var symptomTypeRawValue: String?
    var symptomSeverityRawValue: String?
    var symptomResolved: Bool?
    var glucoseValue: Double?
    var glucoseUnitRawValue: String?
    var glucoseMealRelationRawValue: String?

    var foodUnit: DogAmountUnit? {
        get { foodUnitRawValue.flatMap(DogAmountUnit.init(rawValue:)) }
        set { foodUnitRawValue = newValue?.rawValue }
    }
    var mealType: DogMealType? {
        get { mealTypeRawValue.flatMap(DogMealType.init(rawValue:)) }
        set { mealTypeRawValue = newValue?.rawValue }
    }
    var eatenAmount: DogEatenAmount? {
        get { eatenAmountRawValue.flatMap(DogEatenAmount.init(rawValue:)) }
        set { eatenAmountRawValue = newValue?.rawValue }
    }
    var waterUnit: DogWaterUnit? {
        get { waterUnitRawValue.flatMap(DogWaterUnit.init(rawValue:)) }
        set { waterUnitRawValue = newValue?.rawValue }
    }
    var pottyType: DogPottyType? {
        get { pottyTypeRawValue.flatMap(DogPottyType.init(rawValue:)) }
        set { pottyTypeRawValue = newValue?.rawValue }
    }
    var pottyLocation: DogPottyLocation? {
        get { pottyLocationRawValue.flatMap(DogPottyLocation.init(rawValue:)) }
        set { pottyLocationRawValue = newValue?.rawValue }
    }
    var peeAmount: DiaperAmount? {
        get { peeAmountRawValue.flatMap(DiaperAmount.init(rawValue:)) }
        set { peeAmountRawValue = newValue?.rawValue }
    }
    var poopAmount: DiaperAmount? {
        get { poopAmountRawValue.flatMap(DiaperAmount.init(rawValue:)) }
        set { poopAmountRawValue = newValue?.rawValue }
    }
    var peeColor: DogPeeColor? {
        get { peeColorRawValue.flatMap(DogPeeColor.init(rawValue:)) }
        set { peeColorRawValue = newValue?.rawValue }
    }
    var stoolQuality: DogStoolQuality? {
        get { stoolQualityRawValue.flatMap(DogStoolQuality.init(rawValue:)) }
        set { stoolQualityRawValue = newValue?.rawValue }
    }
    var poopColor: DogPoopColor? {
        get { poopColorRawValue.flatMap(DogPoopColor.init(rawValue:)) }
        set { poopColorRawValue = newValue?.rawValue }
    }
    var distanceUnit: DogDistanceUnit? {
        get { distanceUnitRawValue.flatMap(DogDistanceUnit.init(rawValue:)) }
        set { distanceUnitRawValue = newValue?.rawValue }
    }
    var leashBehavior: DogLeashBehavior? {
        get { leashBehaviorRawValue.flatMap(DogLeashBehavior.init(rawValue:)) }
        set { leashBehaviorRawValue = newValue?.rawValue }
    }
    var restType: DogRestType? {
        get { restTypeRawValue.flatMap(DogRestType.init(rawValue:)) }
        set { restTypeRawValue = newValue?.rawValue }
    }
    var trainingType: DogTrainingType? {
        get { trainingTypeRawValue.flatMap(DogTrainingType.init(rawValue:)) }
        set { trainingTypeRawValue = newValue?.rawValue }
    }
    var trainingOutcome: DogTrainingOutcome? {
        get { trainingOutcomeRawValue.flatMap(DogTrainingOutcome.init(rawValue:)) }
        set { trainingOutcomeRawValue = newValue?.rawValue }
    }
    var groomingType: DogGroomingType? {
        get { groomingTypeRawValue.flatMap(DogGroomingType.init(rawValue:)) }
        set { groomingTypeRawValue = newValue?.rawValue }
    }
    var medicineUnit: DogMedicineUnit? {
        get { medicineUnitRawValue.flatMap(DogMedicineUnit.init(rawValue:)) }
        set { medicineUnitRawValue = newValue?.rawValue }
    }
    var medicineRoute: DogMedicineRoute? {
        get { medicineRouteRawValue.flatMap(DogMedicineRoute.init(rawValue:)) }
        set { medicineRouteRawValue = newValue?.rawValue }
    }
    var vaccineType: DogVaccineType? {
        get { vaccineTypeRawValue.flatMap(DogVaccineType.init(rawValue:)) }
        set { vaccineTypeRawValue = newValue?.rawValue }
    }
    var symptomType: DogSymptomType? {
        get { symptomTypeRawValue.flatMap(DogSymptomType.init(rawValue:)) }
        set { symptomTypeRawValue = newValue?.rawValue }
    }
    var symptomSeverity: DogSymptomSeverity? {
        get { symptomSeverityRawValue.flatMap(DogSymptomSeverity.init(rawValue:)) }
        set { symptomSeverityRawValue = newValue?.rawValue }
    }
    var glucoseUnit: DogGlucoseUnit? {
        get { glucoseUnitRawValue.flatMap(DogGlucoseUnit.init(rawValue:)) }
        set { glucoseUnitRawValue = newValue?.rawValue }
    }
    var glucoseMealRelation: DogMealRelation? {
        get { glucoseMealRelationRawValue.flatMap(DogMealRelation.init(rawValue:)) }
        set { glucoseMealRelationRawValue = newValue?.rawValue }
    }
}
