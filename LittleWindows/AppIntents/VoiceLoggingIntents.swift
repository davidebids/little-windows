import AppIntents
import Foundation
import SwiftData

extension VoiceCareKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Care entry"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .bottle: "Bottle", .diaper: "Diaper", .sleep: "Completed sleep", .nursing: "Nursing",
        .pumping: "Pumping", .temperature: "Temperature", .bloodPressure: "Blood pressure",
        .heartRate: "Pulse", .oxygenSaturation: "Oxygen saturation", .respiratoryRate: "Breathing rate",
        .glucose: "Blood glucose", .weight: "Weight", .pain: "Pain", .symptom: "Symptom",
        .activity: "Activity", .note: "Note",
        .wetDiaper: DisplayRepresentation(title: "Wet diaper", synonyms: ["Pee", "Pee diaper"]),
        .dirtyDiaper: DisplayRepresentation(title: "Dirty diaper", synonyms: ["Poo", "Poop", "Poo diaper", "Poop diaper", "Poopy diaper"]),
        .mixedDiaper: DisplayRepresentation(title: "Mixed diaper", synonyms: ["Pee and poo", "Pee and poop", "Pee and poo diaper", "Pee and poop diaper", "Wet and dirty diaper"]),
        .potty: DisplayRepresentation(title: "Potty", synonyms: ["Potty visit"]),
        .pottyPee: "Potty pee", .pottyPoop: DisplayRepresentation(title: "Potty poo", synonyms: ["Potty poop"]),
        .pottyBoth: DisplayRepresentation(title: "Potty pee and poo", synonyms: ["Potty pee and poop"]),
        .solidMeal: DisplayRepresentation(title: "Solid meal", synonyms: ["Solids"]), .otherFeed: "Other feed",
        .height: DisplayRepresentation(title: "Height", synonyms: ["Length"]), .headCircumference: "Head circumference",
        .tummyTime: "Tummy time", .storyTime: DisplayRepresentation(title: "Story time", synonyms: ["Reading"]),
        .brushTeeth: DisplayRepresentation(title: "Tooth brushing", synonyms: ["Brushing teeth"]),
        .indoorPlay: "Indoor play", .outdoorPlay: "Outdoor play", .screenTime: "Screen time", .bath: "Bath",
        .exercise: "Exercise", .physicalTherapy: "Physical therapy", .socialActivity: "Social activity",
        .littlePee: DisplayRepresentation(title: "Little pee", synonyms: ["Small pee", "Little wet diaper", "Small wet diaper", "Little P", "Small P"]),
        .mediumPee: DisplayRepresentation(title: "Medium pee", synonyms: ["Medium wet diaper", "Medium P"]),
        .bigPee: DisplayRepresentation(title: "Big pee", synonyms: ["Large pee", "Big wet diaper", "Large wet diaper", "Big P", "Large P"]),
        .littlePoo: DisplayRepresentation(title: "Little poo", synonyms: ["Small poo", "Little poop", "Small poop", "Little dirty diaper", "Small dirty diaper"]),
        .mediumPoo: DisplayRepresentation(title: "Medium poo", synonyms: ["Medium poop", "Medium dirty diaper"]),
        .bigPoo: DisplayRepresentation(title: "Big poo", synonyms: ["Large poo", "Big poop", "Large poop", "Big dirty diaper", "Large dirty diaper"]),
        .littleMixedDiaper: DisplayRepresentation(title: "Little mixed diaper", synonyms: ["Small mixed diaper"]),
        .mediumMixedDiaper: "Medium mixed diaper",
        .bigMixedDiaper: DisplayRepresentation(title: "Big mixed diaper", synonyms: ["Large mixed diaper"])
    ]
}

extension VoiceCareUnit: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Measurement unit"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .ounces: "Fluid ounces", .milliliters: "Milliliters", .celsius: "Celsius", .fahrenheit: "Fahrenheit",
        .kilograms: "Kilograms", .pounds: "Pounds", .milligramsPerDeciliter: "Milligrams per deciliter",
        .millimolesPerLiter: "Millimoles per liter",
        .grams: "Grams", .weightOunces: "Ounces by weight", .centimeters: "Centimeters", .inches: "Inches"
    ]
}

extension DiaperKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper type"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .wet: DisplayRepresentation(title: "Wet", synonyms: ["Pee"]),
        .dirty: DisplayRepresentation(title: "Dirty", synonyms: ["Poo", "Poop"]),
        .both: DisplayRepresentation(title: "Both", synonyms: ["Mixed", "Pee and poo", "Pee and poop"])
    ]
}

/// One spoken answer can carry both the diaper type and its amount.
enum VoiceDiaperEntry: String, CaseIterable, AppEnum {
    case wetDiaper, dirtyDiaper, mixedDiaper
    case littlePee, mediumPee, bigPee, littlePoo, mediumPoo, bigPoo
    case littleMixedDiaper, mediumMixedDiaper, bigMixedDiaper
    var kind: VoiceCareKind { VoiceCareKind(rawValue: rawValue)! }
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper details"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .wetDiaper: DisplayRepresentation(title: "Wet diaper", synonyms: ["Pee", "Pee diaper"]),
        .dirtyDiaper: DisplayRepresentation(title: "Dirty diaper", synonyms: ["Poo", "Poop", "Poo diaper", "Poop diaper", "Poopy diaper"]),
        .mixedDiaper: DisplayRepresentation(title: "Mixed diaper", synonyms: ["Pee and poo", "Pee and poop", "Pee and poo diaper", "Pee and poop diaper", "Wet and dirty diaper"]),
        .littlePee: DisplayRepresentation(title: "Little pee", synonyms: ["Small pee", "Little wet diaper", "Small wet diaper", "Little P", "Small P"]),
        .mediumPee: DisplayRepresentation(title: "Medium pee", synonyms: ["Medium wet diaper", "Medium P"]),
        .bigPee: DisplayRepresentation(title: "Big pee", synonyms: ["Large pee", "Big wet diaper", "Large wet diaper", "Big P", "Large P"]),
        .littlePoo: DisplayRepresentation(title: "Little poo", synonyms: ["Small poo", "Little poop", "Small poop", "Little dirty diaper", "Small dirty diaper"]),
        .mediumPoo: DisplayRepresentation(title: "Medium poo", synonyms: ["Medium poop", "Medium dirty diaper"]),
        .bigPoo: DisplayRepresentation(title: "Big poo", synonyms: ["Large poo", "Big poop", "Large poop", "Big dirty diaper", "Large dirty diaper"]),
        .littleMixedDiaper: DisplayRepresentation(title: "Little mixed diaper", synonyms: ["Small mixed diaper"]),
        .mediumMixedDiaper: "Medium mixed diaper",
        .bigMixedDiaper: DisplayRepresentation(title: "Big mixed diaper", synonyms: ["Large mixed diaper"]),
    ]
}

/// Canonical phrase values keep the whole entry (including an article and
/// amount) together. The follow-up menu remains the concise VoiceDiaperEntry.
enum VoiceDiaperPhrase: String, CaseIterable, AppEnum {
    case diaper, aDiaper
    case wetDiaper, aWetDiaper, pee, aPee, peeDiaper, aPeeDiaper
    case dirtyDiaper, aDirtyDiaper, poo, aPoo, poop, aPoop, pooDiaper, aPooDiaper, poopDiaper, aPoopDiaper, poopyDiaper, aPoopyDiaper
    case mixedDiaper, aMixedDiaper, peeAndPoo, aPeeAndPoo, peeAndPoop, aPeeAndPoop, peeAndPooDiaper, aPeeAndPooDiaper, peeAndPoopDiaper, aPeeAndPoopDiaper, wetAndDirtyDiaper, aWetAndDirtyDiaper
    case littlePee, aLittlePee, smallPee, aSmallPee, littleWetDiaper, aLittleWetDiaper, smallWetDiaper, aSmallWetDiaper, littleP, aLittleP, smallP, aSmallP
    case mediumPee, aMediumPee, mediumWetDiaper, aMediumWetDiaper, mediumP, aMediumP
    case bigPee, aBigPee, largePee, aLargePee, bigWetDiaper, aBigWetDiaper, largeWetDiaper, aLargeWetDiaper, bigP, aBigP, largeP, aLargeP
    case littlePoo, aLittlePoo, smallPoo, aSmallPoo, littlePoop, aLittlePoop, smallPoop, aSmallPoop, littleDirtyDiaper, aLittleDirtyDiaper, smallDirtyDiaper, aSmallDirtyDiaper
    case mediumPoo, aMediumPoo, mediumPoop, aMediumPoop, mediumDirtyDiaper, aMediumDirtyDiaper
    case bigPoo, aBigPoo, largePoo, aLargePoo, bigPoop, aBigPoop, largePoop, aLargePoop, bigDirtyDiaper, aBigDirtyDiaper, largeDirtyDiaper, aLargeDirtyDiaper
    case littleMixedDiaper, aLittleMixedDiaper, smallMixedDiaper, aSmallMixedDiaper
    case mediumMixedDiaper, aMediumMixedDiaper
    case bigMixedDiaper, aBigMixedDiaper, largeMixedDiaper, aLargeMixedDiaper

    var kind: VoiceCareKind {
        switch self {
        case .diaper, .aDiaper: .diaper
        case .wetDiaper, .aWetDiaper, .pee, .aPee, .peeDiaper, .aPeeDiaper: .wetDiaper
        case .dirtyDiaper, .aDirtyDiaper, .poo, .aPoo, .poop, .aPoop, .pooDiaper, .aPooDiaper, .poopDiaper, .aPoopDiaper, .poopyDiaper, .aPoopyDiaper: .dirtyDiaper
        case .mixedDiaper, .aMixedDiaper, .peeAndPoo, .aPeeAndPoo, .peeAndPoop, .aPeeAndPoop, .peeAndPooDiaper, .aPeeAndPooDiaper, .peeAndPoopDiaper, .aPeeAndPoopDiaper, .wetAndDirtyDiaper, .aWetAndDirtyDiaper: .mixedDiaper
        case .littlePee, .aLittlePee, .smallPee, .aSmallPee, .littleWetDiaper, .aLittleWetDiaper, .smallWetDiaper, .aSmallWetDiaper, .littleP, .aLittleP, .smallP, .aSmallP: .littlePee
        case .mediumPee, .aMediumPee, .mediumWetDiaper, .aMediumWetDiaper, .mediumP, .aMediumP: .mediumPee
        case .bigPee, .aBigPee, .largePee, .aLargePee, .bigWetDiaper, .aBigWetDiaper, .largeWetDiaper, .aLargeWetDiaper, .bigP, .aBigP, .largeP, .aLargeP: .bigPee
        case .littlePoo, .aLittlePoo, .smallPoo, .aSmallPoo, .littlePoop, .aLittlePoop, .smallPoop, .aSmallPoop, .littleDirtyDiaper, .aLittleDirtyDiaper, .smallDirtyDiaper, .aSmallDirtyDiaper: .littlePoo
        case .mediumPoo, .aMediumPoo, .mediumPoop, .aMediumPoop, .mediumDirtyDiaper, .aMediumDirtyDiaper: .mediumPoo
        case .bigPoo, .aBigPoo, .largePoo, .aLargePoo, .bigPoop, .aBigPoop, .largePoop, .aLargePoop, .bigDirtyDiaper, .aBigDirtyDiaper, .largeDirtyDiaper, .aLargeDirtyDiaper: .bigPoo
        case .littleMixedDiaper, .aLittleMixedDiaper, .smallMixedDiaper, .aSmallMixedDiaper: .littleMixedDiaper
        case .mediumMixedDiaper, .aMediumMixedDiaper: .mediumMixedDiaper
        case .bigMixedDiaper, .aBigMixedDiaper, .largeMixedDiaper, .aLargeMixedDiaper: .bigMixedDiaper
        }
    }
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper entry"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .diaper: "Diaper",
        .aDiaper: "A diaper",
        .wetDiaper: "Wet diaper",
        .aWetDiaper: "A wet diaper",
        .pee: "Pee",
        .aPee: "A pee",
        .peeDiaper: "Pee diaper",
        .aPeeDiaper: "A pee diaper",
        .dirtyDiaper: "Dirty diaper",
        .aDirtyDiaper: "A dirty diaper",
        .poo: "Poo",
        .aPoo: "A poo",
        .poop: "Poop",
        .aPoop: "A poop",
        .pooDiaper: "Poo diaper",
        .aPooDiaper: "A poo diaper",
        .poopDiaper: "Poop diaper",
        .aPoopDiaper: "A poop diaper",
        .poopyDiaper: "Poopy diaper",
        .aPoopyDiaper: "A poopy diaper",
        .mixedDiaper: "Mixed diaper",
        .aMixedDiaper: "A mixed diaper",
        .peeAndPoo: "Pee and poo",
        .aPeeAndPoo: "A pee and poo",
        .peeAndPoop: "Pee and poop",
        .aPeeAndPoop: "A pee and poop",
        .peeAndPooDiaper: "Pee and poo diaper",
        .aPeeAndPooDiaper: "A pee and poo diaper",
        .peeAndPoopDiaper: "Pee and poop diaper",
        .aPeeAndPoopDiaper: "A pee and poop diaper",
        .wetAndDirtyDiaper: "Wet and dirty diaper",
        .aWetAndDirtyDiaper: "A wet and dirty diaper",
        .littlePee: "Little pee",
        .aLittlePee: "A little pee",
        .smallPee: "Small pee",
        .aSmallPee: "A small pee",
        .littleWetDiaper: "Little wet diaper",
        .aLittleWetDiaper: "A little wet diaper",
        .smallWetDiaper: "Small wet diaper",
        .aSmallWetDiaper: "A small wet diaper",
        .littleP: "Little P",
        .aLittleP: "A little p",
        .smallP: "Small P",
        .aSmallP: "A small p",
        .mediumPee: "Medium pee",
        .aMediumPee: "A medium pee",
        .mediumWetDiaper: "Medium wet diaper",
        .aMediumWetDiaper: "A medium wet diaper",
        .mediumP: "Medium P",
        .aMediumP: "A medium p",
        .bigPee: "Big pee",
        .aBigPee: "A big pee",
        .largePee: "Large pee",
        .aLargePee: "A large pee",
        .bigWetDiaper: "Big wet diaper",
        .aBigWetDiaper: "A big wet diaper",
        .largeWetDiaper: "Large wet diaper",
        .aLargeWetDiaper: "A large wet diaper",
        .bigP: "Big P",
        .aBigP: "A big p",
        .largeP: "Large P",
        .aLargeP: "A large p",
        .littlePoo: "Little poo",
        .aLittlePoo: "A little poo",
        .smallPoo: "Small poo",
        .aSmallPoo: "A small poo",
        .littlePoop: "Little poop",
        .aLittlePoop: "A little poop",
        .smallPoop: "Small poop",
        .aSmallPoop: "A small poop",
        .littleDirtyDiaper: "Little dirty diaper",
        .aLittleDirtyDiaper: "A little dirty diaper",
        .smallDirtyDiaper: "Small dirty diaper",
        .aSmallDirtyDiaper: "A small dirty diaper",
        .mediumPoo: "Medium poo",
        .aMediumPoo: "A medium poo",
        .mediumPoop: "Medium poop",
        .aMediumPoop: "A medium poop",
        .mediumDirtyDiaper: "Medium dirty diaper",
        .aMediumDirtyDiaper: "A medium dirty diaper",
        .bigPoo: "Big poo",
        .aBigPoo: "A big poo",
        .largePoo: "Large poo",
        .aLargePoo: "A large poo",
        .bigPoop: "Big poop",
        .aBigPoop: "A big poop",
        .largePoop: "Large poop",
        .aLargePoop: "A large poop",
        .bigDirtyDiaper: "Big dirty diaper",
        .aBigDirtyDiaper: "A big dirty diaper",
        .largeDirtyDiaper: "Large dirty diaper",
        .aLargeDirtyDiaper: "A large dirty diaper",
        .littleMixedDiaper: "Little mixed diaper",
        .aLittleMixedDiaper: "A little mixed diaper",
        .smallMixedDiaper: "Small mixed diaper",
        .aSmallMixedDiaper: "A small mixed diaper",
        .mediumMixedDiaper: "Medium mixed diaper",
        .aMediumMixedDiaper: "A medium mixed diaper",
        .bigMixedDiaper: "Big mixed diaper",
        .aBigMixedDiaper: "A big mixed diaper",
        .largeMixedDiaper: "Large mixed diaper",
        .aLargeMixedDiaper: "A large mixed diaper",
    ]
}

/// The promoted care vocabulary excludes diapers, which have their own action.
/// Keep VoiceCareKind unchanged for existing saved Shortcuts and history queries.
enum VoiceGeneralCareEntry: String, CaseIterable, AppEnum {
    case bottle, sleep, nursing, pumping, temperature, bloodPressure, heartRate, oxygenSaturation, respiratoryRate, glucose, weight, pain, symptom, activity, note, potty, pottyPee, pottyPoop, pottyBoth, solidMeal, otherFeed, height, headCircumference, tummyTime, storyTime, brushTeeth, indoorPlay, outdoorPlay, screenTime, bath, exercise, physicalTherapy, socialActivity
    var kind: VoiceCareKind { VoiceCareKind(rawValue: rawValue)! }
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Care entry"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .bottle: "Bottle",
        .sleep: DisplayRepresentation(title: "Sleep", synonyms: ["Completed sleep"]),
        .nursing: "Nursing",
        .pumping: "Pumping",
        .temperature: "Temperature",
        .bloodPressure: "Blood pressure",
        .heartRate: "Pulse",
        .oxygenSaturation: "Oxygen saturation",
        .respiratoryRate: "Breathing rate",
        .glucose: "Blood glucose",
        .weight: "Weight",
        .pain: "Pain",
        .symptom: "Symptom",
        .activity: "Activity",
        .note: "Note",
        .potty: DisplayRepresentation(title: "Potty", synonyms: ["Potty visit"]),
        .pottyPee: "Potty pee",
        .pottyPoop: DisplayRepresentation(title: "Potty poo", synonyms: ["Potty poop"]),
        .pottyBoth: DisplayRepresentation(title: "Potty pee and poo", synonyms: ["Potty pee and poop"]),
        .solidMeal: DisplayRepresentation(title: "Solid meal", synonyms: ["Solids"]),
        .otherFeed: "Other feed",
        .height: DisplayRepresentation(title: "Height", synonyms: ["Length"]),
        .headCircumference: "Head circumference",
        .tummyTime: "Tummy time",
        .storyTime: DisplayRepresentation(title: "Story time", synonyms: ["Reading"]),
        .brushTeeth: DisplayRepresentation(title: "Tooth brushing", synonyms: ["Brushing teeth"]),
        .indoorPlay: "Indoor play",
        .outdoorPlay: "Outdoor play",
        .screenTime: "Screen time",
        .bath: "Bath",
        .exercise: "Exercise",
        .physicalTherapy: "Physical therapy",
        .socialActivity: "Social activity",
    ]
}

extension ChildPottyKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Potty type"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .pee: "Pee", .poo: DisplayRepresentation(title: "Poo", synonyms: ["Poop"]),
        .both: DisplayRepresentation(title: "Both", synonyms: ["Pee and poo", "Pee and poop"])
    ]
}

extension ChildPottyLocation: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Potty location"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .toilet: "Toilet", .pottyChair: "Potty chair", .trainingPants: "Training pants",
        .diaper: "Diaper", .accident: "Accident", .other: "Other"
    ]
}

extension DiaperAmount: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pee or poo amount"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .little: DisplayRepresentation(title: "Small", synonyms: ["Little"]), .medium: "Medium",
        .big: DisplayRepresentation(title: "Big", synonyms: ["Large"]), .unknown: "Unknown"
    ]
}

extension PooColor: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Poo color"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .yellow: "Yellow", .green: "Green", .brown: "Brown", .black: "Black", .red: "Red", .other: "Other", .unknown: "Unknown"
    ]
}

extension PooTexture: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Poo consistency"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .seedy: "Seedy", .runny: "Runny", .soft: "Soft", .formed: "Formed", .hard: "Hard", .mucus: "Mucus", .unknown: "Unknown"
    ]
}

extension NursingSide: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Nursing side"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.left: "Left", .right: "Right"]
}

extension SleepKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep type"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.nap: "Nap", .nightSleep: "Night sleep", .nightWaking: "Night waking"]
}

extension VoiceTimerAction: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Timer action"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .start: "Start",
        .pause: DisplayRepresentation(title: "Pause", synonyms: ["Stop"]),
        .resume: "Resume", .switchSide: "Switch nursing side",
        .finish: DisplayRepresentation(title: "Finish", synonyms: ["Save", "Finish and save", "Stop and save"]),
        .reset: "Reset", .discard: "Discard", .adjustStart: "Adjust start"
    ]
}

extension VoiceTimerKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Care timer"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .sleep: "Sleep", .nap: "Nap", .nightSleep: "Night sleep", .nightWaking: "Night waking",
        .nursing: DisplayRepresentation(title: "Nursing", synonyms: ["Breastfeeding"]),
        // The literal nursing-left/right shortcuts own their established phrases.
        .nursingLeft: "Left-side breastfeeding", .nursingRight: "Right-side breastfeeding",
        .pumping: "Pumping", .bottle: DisplayRepresentation(title: "Bottle", synonyms: ["Bottle feed"]),
        .solidMeal: "Solid meal", .otherFeed: "Other feed",
        .tummyTime: "Tummy time", .storyTime: DisplayRepresentation(title: "Story time", synonyms: ["Reading"]),
        .brushTeeth: DisplayRepresentation(title: "Tooth brushing", synonyms: ["Brushing teeth"]),
        .indoorPlay: "Indoor play", .outdoorPlay: "Outdoor play", .screenTime: "Screen time", .bath: "Bath",
        .exercise: "Exercise", .physicalTherapy: "Physical therapy", .socialActivity: "Social activity",
        .customActivity: "Custom activity", .customTimer: "Custom timer"
    ]
}

struct VoiceActiveTimerEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Open care timer"
    static var defaultQuery = VoiceActiveTimerQuery()
    var id: UUID
    var profileID: UUID
    var profileName: String
    var kind: VoiceTimerKind
    var title: String
    var isRunning: Bool
    var updatedAt: Date
    var amountOz: Double?
    var profileSubtitle: String
    var startDate: Date
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title) · \(profileName)", subtitle: "\(profileSubtitle) · \(isRunning ? "Running" : "Paused") · \(startDate.formatted(date: .abbreviated, time: .shortened))")
    }
    init(_ option: VoiceTimerOption) {
        id = option.id
        profileID = option.profileID
        profileName = option.profileName
        kind = option.kind
        title = option.title
        isRunning = option.isRunning
        updatedAt = option.updatedAt
        amountOz = option.amountOz
        profileSubtitle = option.profileSubtitle
        startDate = option.startDate
    }
}

struct VoiceActiveTimerQuery: EntityStringQuery {
    @MainActor
    func suggestedEntities() async throws -> [VoiceActiveTimerEntity] {
        let container = try await VoiceLoggingService.container()
        return try VoiceLoggingService.timerOptions(in: container).map(VoiceActiveTimerEntity.init)
    }
    func entities(for identifiers: [UUID]) async throws -> [VoiceActiveTimerEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [VoiceActiveTimerEntity] {
        try await suggestedEntities().filter {
            $0.title.localizedStandardContains(string) || $0.profileName.localizedStandardContains(string)
        }
    }
}

struct VoiceCareProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Care profile"
    static var defaultQuery = VoiceCareProfileQuery()
    var id: UUID
    var name: String
    var profileType: String
    var subtitle: String
    var isMyself: Bool
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    @MainActor
    init(_ profile: CareProfile) {
        id = profile.id
        name = profile.name
        profileType = profile.profileType.rawValue
        subtitle = [profile.profileType.displayName, profile.birthDate?.formatted(date: .abbreviated, time: .omitted)]
            .compactMap { $0 }.joined(separator: " · ")
        isMyself = profile.profileType == .adult && profile.adultRelationship == .myself
    }
}

struct VoiceCareProfileQuery: EntityStringQuery {
    @MainActor
    func suggestedEntities() async throws -> [VoiceCareProfileEntity] {
        let container = try await VoiceLoggingService.container()
        return try VoiceLoggingService.profiles(in: container).map(VoiceCareProfileEntity.init)
    }
    func entities(for identifiers: [UUID]) async throws -> [VoiceCareProfileEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [VoiceCareProfileEntity] {
        let profiles = try await suggestedEntities()
        let name = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["me", "myself", "my"].contains(name.lowercased()) { return profiles.filter(\.isMyself) }
        let exact = profiles.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        return exact.isEmpty ? profiles.filter { $0.name.localizedStandardContains(name) } : exact
    }
}

private enum VoiceIntentProfiles {
    static func choices(kind: VoiceCareKind? = nil) async throws -> [VoiceCareProfileEntity] {
        let profiles = try await VoiceCareProfileQuery().suggestedEntities()
        let eligible = profiles.filter { entity in
            guard let kind, let type = CareProfileType(rawValue: entity.profileType) else { return true }
            return kind.supports(type)
        }
        guard !eligible.isEmpty else {
            throw VoiceLoggingError("Add an eligible child or adult profile in Little Windows first.")
        }
        return eligible
    }

    @MainActor
    static func nursingProfile(
        _ explicit: VoiceCareProfileEntity?,
        parameter: IntentParameter<VoiceCareProfileEntity?>,
        runningOnly: Bool = false
    ) async throws -> VoiceCareProfileEntity {
        var candidates = try await choices(kind: .nursing)
        if runningOnly {
            let container = try await VoiceLoggingService.container()
            let ids = try VoiceLoggingService.runningNursingProfileIDs(in: container)
            candidates = candidates.filter { ids.contains($0.id) }
            guard !candidates.isEmpty else {
                throw VoiceLoggingError("There is no running nursing timer. Start or resume nursing first.")
            }
        }
        if let explicit {
            guard candidates.contains(where: { $0.id == explicit.id }) else {
                throw VoiceLoggingError("Choose a child with an available nursing timer.")
            }
            return explicit
        }
        if candidates.count == 1 { return candidates[0] }
        return try await parameter.requestDisambiguation(among: candidates, dialog: "Whose nursing session?")
    }
}

struct StartNursingLeftByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Nurse on the Left by Voice"
    static let description = IntentDescription("Starts left-side nursing or continues the existing nursing timer on the left, keeping time on both sides.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    static var parameterSummary: some ParameterSummary { Summary("Nurse on the left for \(\.$profile)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = Date()
        let target = try await VoiceIntentProfiles.nursingProfile(profile, parameter: $profile)
        self.profile = target
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.manageTimer(
            action: .start, kind: .nursing, profileID: target.id, side: .left,
            continueExistingNursing: true, at: requestedAt, in: container
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StartNursingRightByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Nurse on the Right by Voice"
    static let description = IntentDescription("Starts right-side nursing or continues the existing nursing timer on the right, keeping time on both sides.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    static var parameterSummary: some ParameterSummary { Summary("Nurse on the right for \(\.$profile)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = Date()
        let target = try await VoiceIntentProfiles.nursingProfile(profile, parameter: $profile)
        self.profile = target
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.manageTimer(
            action: .start, kind: .nursing, profileID: target.id, side: .right,
            continueExistingNursing: true, at: requestedAt, in: container
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct SwitchActiveNursingSideByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Active Nursing Side"
    static let description = IntentDescription("Switches the running nursing timer to the other side, or a specified side, without stopping the session. Uses the sole running session or asks which child.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    @Parameter(title: "Switch to") var side: NursingSide?
    static var parameterSummary: some ParameterSummary { Summary("Switch nursing side for \(\.$profile)") { \.$side } }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = Date()
        let target = try await VoiceIntentProfiles.nursingProfile(profile, parameter: $profile, runningOnly: true)
        self.profile = target
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.manageTimer(
            action: .switchSide, kind: .nursing, profileID: target.id, side: side,
            at: requestedAt, in: container
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// The required category is resolved first. Only details needed by that
/// category are requested; supplied parameters are never replaced by defaults.
struct LogCareByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Care by Voice"
    static let description = IntentDescription("Saves a baby or adult care entry and confirms what was recorded. Asks only for missing details.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Entry", requestValueDialog: "What would you like to log?") var kind: VoiceCareKind?
    @Parameter(title: "Care entry") var entry: VoiceGeneralCareEntry?
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    @Parameter(title: "Amount or reading") var value: Double?
    @Parameter(title: "Unit") var unit: VoiceCareUnit?
    @Parameter(title: "Bottom blood pressure number") var secondValue: Double?
    @Parameter(title: "Pulse with blood pressure") var pulse: Double?
    @Parameter(title: "Minutes") var durationMinutes: Double?
    @Parameter(title: "When", description: "When it happened. For an entry with a duration, this is when it ended. Defaults to now.") var date: Date?
    @Parameter(title: "Description or body location") var text: String?
    @Parameter(title: "Notes") var notes: String?
    @Parameter(title: "Diaper type") var diaperKind: DiaperKind?
    @Parameter(title: "Diaper details", description: "Pee, poo, mixed, or an amount such as big pee or medium poop.") var diaperEntry: VoiceDiaperEntry?
    @Parameter(title: "Nursing side") var nursingSide: NursingSide?
    @Parameter(title: "Sleep type") var sleepKind: SleepKind?

    @Parameter(title: "Potty type") var pottyKind: ChildPottyKind?
    @Parameter(title: "Potty location") var pottyLocation: ChildPottyLocation?
    @Parameter(title: "Potty accident") var pottyAccident: Bool?
    @Parameter(title: "Pee amount") var peeAmount: DiaperAmount?
    @Parameter(title: "Poo amount") var pooAmount: DiaperAmount?
    @Parameter(title: "Poo color") var pooColor: PooColor?
    @Parameter(title: "Poo consistency") var pooTexture: PooTexture?
    @Parameter(title: "Diaper rash") var diaperRash: Bool?

    static var parameterSummary: some ParameterSummary {
        When(\.$entry, .hasAnyValue) {
            Switch(\.$entry) {
                Case([.potty, .pottyPee, .pottyPoop, .pottyBoth]) {
                    Summary("Log \(\.$entry) for \(\.$profile)") { \.$pottyKind; \.$pottyLocation; \.$pottyAccident; \.$peeAmount; \.$pooAmount; \.$pooColor; \.$pooTexture; \.$date; \.$notes }
                }
                Case(.sleep) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$durationMinutes; \.$sleepKind; \.$date; \.$notes } }
                Case(.nursing) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$nursingSide; \.$durationMinutes; \.$date; \.$notes } }
                Case(.bloodPressure) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$value; \.$secondValue; \.$pulse; \.$date; \.$notes } }
                Case(.symptom) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$text; \.$value; \.$date; \.$notes } }
                Case(.pain) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$value; \.$text; \.$date; \.$notes } }
                Case(.note) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$text; \.$date } }
                Case([.activity, .tummyTime, .storyTime, .brushTeeth, .indoorPlay, .outdoorPlay, .screenTime, .bath,
                      .exercise, .physicalTherapy, .socialActivity]) {
                    Summary("Log \(\.$entry) for \(\.$profile)") { \.$text; \.$durationMinutes; \.$date; \.$notes }
                }
                Case([.solidMeal, .otherFeed]) { Summary("Log \(\.$entry) for \(\.$profile)") { \.$text; \.$durationMinutes; \.$date; \.$notes } }
                DefaultCase { Summary("Log \(\.$entry) for \(\.$profile)") { \.$value; \.$unit; \.$durationMinutes; \.$date; \.$notes } }
            }
        } otherwise: {
            Switch(\.$kind) {
                Case([.diaper, .wetDiaper, .dirtyDiaper, .mixedDiaper,
                      .littlePee, .mediumPee, .bigPee, .littlePoo, .mediumPoo, .bigPoo,
                      .littleMixedDiaper, .mediumMixedDiaper, .bigMixedDiaper]) {
                    Summary("Log \(\.$kind) for \(\.$profile)") {
                        \.$diaperEntry; \.$diaperKind; \.$peeAmount; \.$pooAmount; \.$pooColor; \.$pooTexture; \.$diaperRash; \.$date; \.$notes
                    }
                }
                Case([.potty, .pottyPee, .pottyPoop, .pottyBoth]) {
                    Summary("Log \(\.$kind) for \(\.$profile)") { \.$pottyKind; \.$pottyLocation; \.$pottyAccident; \.$peeAmount; \.$pooAmount; \.$pooColor; \.$pooTexture; \.$date; \.$notes }
                }
                Case(.sleep) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$durationMinutes; \.$sleepKind; \.$date; \.$notes } }
                Case(.nursing) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$nursingSide; \.$durationMinutes; \.$date; \.$notes } }
                Case(.bloodPressure) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$value; \.$secondValue; \.$pulse; \.$date; \.$notes } }
                Case(.symptom) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$text; \.$value; \.$date; \.$notes } }
                Case(.pain) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$value; \.$text; \.$date; \.$notes } }
                Case(.note) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$text; \.$date } }
                Case([.activity, .tummyTime, .storyTime, .brushTeeth, .indoorPlay, .outdoorPlay, .screenTime, .bath,
                      .exercise, .physicalTherapy, .socialActivity]) {
                    Summary("Log \(\.$kind) for \(\.$profile)") { \.$text; \.$durationMinutes; \.$date; \.$notes }
                }
                Case([.solidMeal, .otherFeed]) { Summary("Log \(\.$kind) for \(\.$profile)") { \.$text; \.$durationMinutes; \.$date; \.$notes } }
                DefaultCase { Summary("Log \(\.$kind) for \(\.$profile)") { \.$value; \.$unit; \.$durationMinutes; \.$date; \.$notes } }
            }
        }
    }

    func resolvedEntryKind() throws -> VoiceCareKind {
        guard let kind = kind ?? entry?.kind else {
            throw $kind.needsValueError("What would you like to log?")
        }
        if let entry, kind != entry.kind {
            throw VoiceLoggingError("The care entry and saved category conflict. Choose one entry.")
        }
        if let diaperEntry, kind != .diaper && kind != diaperEntry.kind {
            throw VoiceLoggingError("The diaper entry and spoken details conflict. Choose one diaper entry.")
        }
        return kind == .diaper ? (diaperEntry?.kind ?? kind) : kind
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = date ?? Date()
        self.date = requestedAt
        let kind = try resolvedEntryKind()
        self.kind = kind
        let choices = try await VoiceIntentProfiles.choices(kind: kind)
        let target: VoiceCareProfileEntity
        if let profile {
            guard choices.contains(where: { $0.id == profile.id }) else {
                throw VoiceLoggingError("Choose a profile that supports this entry.")
            }
            target = profile
        } else if choices.count == 1 {
            target = choices[0]
        } else {
            target = try await $profile.requestDisambiguation(among: choices, dialog: "Who is this entry for?")
        }
        self.profile = target
        switch kind {
        case .bottle, .pumping:
            if value == nil { throw $value.needsValueError("How much milk?") }
            if unit == nil { throw $unit.needsValueError("Fluid ounces or milliliters?") }
        case .temperature:
            if value == nil { throw $value.needsValueError("What was the temperature?") }
            if unit == nil { throw $unit.needsValueError("Celsius or Fahrenheit?") }
        case .bloodPressure:
            if value == nil { throw $value.needsValueError("What was the top blood pressure number?") }
            if secondValue == nil { throw $secondValue.needsValueError("What was the bottom blood pressure number?") }
        case .heartRate:
            if value == nil { throw $value.needsValueError("What was the pulse in beats per minute?") }
        case .oxygenSaturation:
            if value == nil { throw $value.needsValueError("What was the oxygen saturation percentage?") }
        case .respiratoryRate:
            if value == nil { throw $value.needsValueError("How many breaths per minute?") }
        case .glucose:
            if value == nil { throw $value.needsValueError("What was the blood glucose reading?") }
            if unit == nil { throw $unit.needsValueError("Milligrams per deciliter or millimoles per liter?") }
        case .weight:
            if value == nil { throw $value.needsValueError("What was the weight?") }
            if unit == nil { throw $unit.needsValueError("Pounds, kilograms, grams, or ounces by weight?") }
        case .height, .headCircumference:
            if value == nil { throw $value.needsValueError("What was the measurement?") }
            if unit == nil { throw $unit.needsValueError("Centimeters or inches?") }
        case .pain:
            if value == nil { throw $value.needsValueError("What was the pain score from zero to ten?") }
        case .symptom, .activity, .note, .solidMeal, .otherFeed:
            if text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw $text.needsValueError("What would you like to record?")
            }
        case .diaper:
            if diaperKind == nil && diaperEntry == nil {
                throw $diaperEntry.needsValueError("Pee, poo, or mixed? You can include an amount, like big pee or medium poop.")
            }
        case .potty:
            if pottyKind == nil { throw $pottyKind.needsValueError("Was this potty pee, poo, or both?") }
        case .sleep:
            if sleepKind == nil { throw $sleepKind.needsValueError("Was this a nap or night sleep?") }
        case .nursing:
            if nursingSide == nil { throw $nursingSide.needsValueError("Left or right side?") }
        case .wetDiaper, .dirtyDiaper, .mixedDiaper, .pottyPee, .pottyPoop, .pottyBoth,
             .littlePee, .mediumPee, .bigPee, .littlePoo, .mediumPoo, .bigPoo,
             .littleMixedDiaper, .mediumMixedDiaper, .bigMixedDiaper,
             .tummyTime, .storyTime, .brushTeeth, .indoorPlay, .outdoorPlay, .screenTime, .bath,
             .exercise, .physicalTherapy, .socialActivity:
            break
        }
        if [.sleep, .nursing].contains(kind), durationMinutes == nil {
            throw $durationMinutes.needsValueError("How many minutes did it last?")
        }
        let container = try await VoiceLoggingService.container()
        let resolvedKind = try resolvedEntryKind()
        let message = try await VoiceLoggingService.log(VoiceCareLog(
            profileID: target.id, kind: resolvedKind, date: requestedAt,
            durationMinutes: durationMinutes, value: value, unit: unit,
            secondValue: secondValue, pulse: pulse, text: text, notes: notes,
            diaperKind: diaperKind, nursingSide: nursingSide, sleepKind: sleepKind,
            pottyKind: pottyKind, pottyLocation: pottyLocation, pottyAccident: pottyAccident,
            peeAmount: peeAmount, pooAmount: pooAmount, pooColor: pooColor, pooTexture: pooTexture, diaperRash: diaperRash
        ), in: container)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// A focused action gives flexible matching a diaper-specific route. Its
/// parameters use the same structured writer and validation as general care.
struct LogDiaperByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Diaper, Pee or Poop"
    static let description = IntentDescription("Records a wet, dirty or mixed diaper, including pee and poop amounts, color, consistency and rash. Big pee and medium poop describe diapers.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Diaper entry") var spokenEntry: VoiceDiaperPhrase?
    @Parameter(title: "Diaper details") var diaperEntry: VoiceDiaperEntry?
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    @Parameter(title: "Diaper type") var diaperKind: DiaperKind?
    @Parameter(title: "Pee amount") var peeAmount: DiaperAmount?
    @Parameter(title: "Poo amount") var pooAmount: DiaperAmount?
    @Parameter(title: "Poo color") var pooColor: PooColor?
    @Parameter(title: "Poo consistency") var pooTexture: PooTexture?
    @Parameter(title: "Diaper rash") var diaperRash: Bool?
    @Parameter(title: "When") var date: Date?
    @Parameter(title: "Notes") var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$spokenEntry) for \(\.$profile)") {
            \.$diaperEntry; \.$diaperKind; \.$peeAmount; \.$pooAmount; \.$pooColor; \.$pooTexture; \.$diaperRash; \.$date; \.$notes
        }
    }

    func resolvedEntryKind() throws -> VoiceCareKind {
        if let spokenEntry, spokenEntry.kind != .diaper {
            if let diaperEntry, spokenEntry.kind != diaperEntry.kind {
                throw VoiceLoggingError("The spoken entry and diaper details conflict. Choose one diaper entry.")
            }
            return spokenEntry.kind
        }
        guard diaperEntry != nil || diaperKind != nil else {
            throw $diaperEntry.needsValueError("Pee, poo, or mixed? You can include an amount, like big pee or medium poop.")
        }
        return diaperEntry?.kind ?? .diaper
    }

    func careLog(profileID: UUID, at date: Date) throws -> VoiceCareLog {
        VoiceCareLog(profileID: profileID, kind: try resolvedEntryKind(), date: date,
            notes: notes, diaperKind: diaperKind, peeAmount: peeAmount, pooAmount: pooAmount,
            pooColor: pooColor, pooTexture: pooTexture, diaperRash: diaperRash)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = date ?? Date()
        self.date = requestedAt
        // Resolve diaper details before asking for a person; a missing entry
        // must never turn into an unrelated category's follow-up.
        _ = try resolvedEntryKind()
        let choices = try await VoiceIntentProfiles.choices(kind: .diaper)
        let target: VoiceCareProfileEntity
        if let profile {
            guard choices.contains(where: { $0.id == profile.id }) else {
                throw VoiceLoggingError("Choose an available child profile.")
            }
            target = profile
        } else if choices.count == 1 {
            target = choices[0]
        } else {
            target = try await $profile.requestDisambiguation(among: choices, dialog: "Whose diaper would you like to record?")
        }
        self.profile = target
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.log(try careLog(profileID: target.id, at: requestedAt), in: container)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Retained for saved Shortcuts; promoted sleep phrases use general care.
struct LogSleepByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Sleep"
    static let description = IntentDescription("Records completed sleep for a child or adult. Asks who, nap or night sleep, and how many minutes; an omitted end time means now.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    @Parameter(title: "Sleep type") var sleepKind: SleepKind?
    @Parameter(title: "Minutes") var durationMinutes: Double?
    @Parameter(title: "Ended at") var date: Date?
    @Parameter(title: "Notes") var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log sleep for \(\.$profile)") { \.$sleepKind; \.$durationMinutes; \.$date; \.$notes }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choices = try await VoiceIntentProfiles.choices(kind: .sleep)
        let target: VoiceCareProfileEntity
        if let profile {
            guard choices.contains(where: { $0.id == profile.id }) else {
                throw VoiceLoggingError("Choose an available child or adult profile.")
            }
            target = profile
        } else if choices.count == 1 {
            target = choices[0]
        } else {
            target = try await $profile.requestDisambiguation(among: choices, dialog: "Whose sleep would you like to record?")
        }
        self.profile = target
        guard sleepKind != nil else {
            throw $sleepKind.needsValueError("Was this a nap or night sleep?")
        }
        guard let durationMinutes, durationMinutes.isFinite, durationMinutes > 0 else {
            throw $durationMinutes.needsValueError("How many minutes did the sleep last?")
        }
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.log(VoiceCareLog(
            profileID: target.id, kind: .sleep, date: date ?? Date(),
            durationMinutes: durationMinutes, notes: notes, sleepKind: sleepKind
        ), in: container)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ActiveCareTimersByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Open Care Timers"
    static let description = IntentDescription("Reads running and paused care timers, who they belong to, and their elapsed times.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    static var parameterSummary: some ParameterSummary { Summary("Get open timers for \(\.$profile)") }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let container = try await VoiceLoggingService.container()
        let options = try VoiceLoggingService.timerOptions(profileID: profile?.id, in: container)
        let message = options.isEmpty ? "There are no open care timers." : options.map {
            "\($0.profileName): \($0.title), \($0.isRunning ? "running" : "paused"), \(($0.elapsedSeconds / 60).formatted(.number.precision(.fractionLength(0...1)))) minutes"
        }.joined(separator: ". ")
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct StartCareTimerByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Care Timer by Voice"
    static let description = IntentDescription("Starts a sleep, feeding, nursing, pumping, activity, or custom timer for a chosen person.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Timer type") var timerKind: VoiceTimerKind
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    @Parameter(title: "Nursing side") var nursingSide: NursingSide?
    @Parameter(title: "Sleep type") var sleepKind: SleepKind?
    @Parameter(title: "Name or food description") var name: String?
    @Parameter(title: "Started at") var date: Date?
    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$timerKind) for \(\.$profile)") { \.$nursingSide; \.$sleepKind; \.$name; \.$date }
    }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = date ?? Date()
        self.date = requestedAt
        let choices = try await VoiceCareProfileQuery().suggestedEntities().filter {
            CareProfileType(rawValue: $0.profileType).map(timerKind.supports) == true
        }
        guard !choices.isEmpty else { throw VoiceLoggingError("Add a profile that supports this timer first.") }
        let target: VoiceCareProfileEntity
        if let profile {
            guard choices.contains(where: { $0.id == profile.id }) else { throw VoiceLoggingError("That timer is unavailable for this profile.") }
            target = profile
        } else if choices.count == 1 { target = choices[0] }
        else { target = try await $profile.requestDisambiguation(among: choices, dialog: "Whose timer should start?") }
        self.profile = target
        if timerKind == .nursing, nursingSide == nil { throw $nursingSide.needsValueError("Left or right side?") }
        if timerKind == .sleep, sleepKind == nil { throw $sleepKind.needsValueError("Nap, night sleep, or night waking?") }
        if timerKind.needsName, name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw $name.needsValueError("What is this activity, timer, or meal called?")
        }
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.manageTimer(
            action: .start, timerKind: timerKind, profileID: target.id,
            side: nursingSide, sleepKind: sleepKind, name: name,
            continueExistingNursing: timerKind.eventType == .nursing,
            at: requestedAt, in: container
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ManageCareTimerByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Manage Care Timer by Voice"
    static let description = IntentDescription("Pauses, resumes, finishes/saves, resets, discards, or corrects the start of an exact open care timer. Stop means pause; finish means save.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    // Preserve the original parameter names/types for existing saved shortcuts.
    @Parameter(title: "Action") var action: VoiceTimerAction?
    @Parameter(title: "Legacy category") var kind: VoiceCareKind?
    @Parameter(title: "Timer type") var timerKind: VoiceTimerKind?
    @Parameter(title: "Timer") var timer: VoiceActiveTimerEntity?
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    @Parameter(title: "Nursing side") var nursingSide: NursingSide?
    @Parameter(title: "Sleep type") var sleepKind: SleepKind?
    @Parameter(title: "Milk amount") var amount: Double?
    @Parameter(title: "Add milk amount") var includeMilkAmount: Bool?
    @Parameter(title: "Unit") var unit: VoiceCareUnit?
    @Parameter(title: "When") var date: Date?
    @Parameter(title: "Name or food description") var name: String?
    @Parameter(title: "Corrected start time") var adjustedStart: Date?
    // Each phrase carries one typed timer selector and therefore one verb.
    @Parameter(title: "Timer to pause") var pauseTimer: VoiceTimerKind?
    @Parameter(title: "Timer to resume") var resumeTimer: VoiceTimerKind?
    @Parameter(title: "Timer to finish") var finishTimer: VoiceTimerKind?
    @Parameter(title: "Timer to reset") var resetTimer: VoiceTimerKind?
    @Parameter(title: "Timer to discard") var discardTimer: VoiceTimerKind?
    @Parameter(title: "Timer to correct") var correctTimer: VoiceTimerKind?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) \(\.$timer)") {
            \.$timerKind; \.$profile; \.$amount; \.$includeMilkAmount; \.$unit; \.$adjustedStart; \.$nursingSide; \.$sleepKind; \.$name; \.$date
        }
    }

    func selection() throws -> (VoiceTimerAction, VoiceTimerKind?) {
        let phraseSelections: [(VoiceTimerAction, VoiceTimerKind)] = [
            pauseTimer.map { (.pause, $0) }, resumeTimer.map { (.resume, $0) },
            finishTimer.map { (.finish, $0) }, resetTimer.map { (.reset, $0) },
            discardTimer.map { (.discard, $0) }, correctTimer.map { (.adjustStart, $0) }
        ].compactMap { $0 }
        guard phraseSelections.count <= 1 else { throw VoiceLoggingError("Choose one timer action at a time.") }
        if let phrase = phraseSelections.first {
            guard action == nil || action == phrase.0, timerKind == nil || timerKind == phrase.1,
                  kind == nil || kind!.eventType == phrase.1.eventType else {
                throw VoiceLoggingError("The timer action and type conflict. Choose one action and timer.")
            }
            return phrase
        }
        guard let action else { throw $action.needsValueError("Pause, resume, finish, reset, discard, or adjust the start?") }
        let selectedKind: VoiceTimerKind?
        if let timerKind { selectedKind = timerKind }
        else {
            switch kind {
            case .sleep: selectedKind = .sleep
            case .nursing: selectedKind = .nursing
            case .pumping: selectedKind = .pumping
            case .bottle: selectedKind = .bottle
            case .activity: selectedKind = .customActivity
            case .note: selectedKind = .customTimer
            case .none: selectedKind = nil
            default: throw VoiceLoggingError("Choose a timer rather than a measurement.")
            }
        }
        return (action, selectedKind)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requestedAt = date ?? Date()
        self.date = requestedAt
        let (selectedAction, selectedKind) = try selection()
        let container = try await VoiceLoggingService.container()
        if selectedAction == .start {
            guard let selectedKind else { throw $timerKind.needsValueError("Which type of timer?") }
            let choices = try await VoiceCareProfileQuery().suggestedEntities().filter {
                CareProfileType(rawValue: $0.profileType).map(selectedKind.supports) == true
            }
            guard !choices.isEmpty else { throw VoiceLoggingError("No eligible profile is available.") }
            let target: VoiceCareProfileEntity
            if let profile { target = profile }
            else if choices.count == 1 { target = choices[0] }
            else { target = try await $profile.requestDisambiguation(among: choices, dialog: "Whose timer?") }
            self.profile = target
            if selectedKind == .nursing, nursingSide == nil { throw $nursingSide.needsValueError("Left or right side?") }
            if selectedKind == .sleep, sleepKind == nil { throw $sleepKind.needsValueError("Nap, night sleep, or night waking?") }
            if selectedKind.needsName, name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw $name.needsValueError("What is this timer or activity called?")
            }
            let reply = try await VoiceLoggingService.manageTimer(
                action: .start, timerKind: selectedKind, profileID: target.id,
                side: nursingSide, sleepKind: sleepKind, amount: amount, unit: unit, name: name,
                continueExistingNursing: selectedKind.eventType == .nursing,
                at: requestedAt, in: container
            )
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }
        let choices = try VoiceLoggingService.timerOptions(
            profileID: profile?.id, kind: selectedKind, action: selectedAction, in: container
        ).map(VoiceActiveTimerEntity.init)
        guard !choices.isEmpty else { throw VoiceLoggingError("No matching open timer is available for that action.") }
        let target: VoiceActiveTimerEntity
        if let timer {
            guard choices.contains(where: { $0.id == timer.id }) else { throw VoiceLoggingError("That exact timer is no longer available for this action.") }
            target = timer
        } else if choices.count == 1 { target = choices[0] }
        else { target = try await $timer.requestDisambiguation(among: choices, dialog: "Which timer should change?") }
        self.timer = target
        if selectedAction == .finish, target.kind.eventType == .pumping || target.kind == .bottle {
            if amount == nil && target.amountOz == nil {
                if includeMilkAmount == nil { throw $includeMilkAmount.needsValueError("Would you like to add the milk amount?") }
                if includeMilkAmount == true { throw $amount.needsValueError("How much milk?") }
            }
            if amount != nil && unit == nil { throw $unit.needsValueError("Fluid ounces or milliliters?") }
        }
        if selectedAction == .adjustStart, adjustedStart == nil { throw $adjustedStart.needsValueError("When did this timer actually start?") }
        if [.reset, .discard, .adjustStart].contains(selectedAction) {
            let verb: String = switch selectedAction {
            case .reset: "Reset the elapsed time for"
            case .discard: "Discard without saving"
            default: "Correct the start time for"
            }
            let correction = adjustedStart.map { " to \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
            let prompt = IntentDialog(stringLiteral: "\(verb) \(target.title) for \(target.profileName)\(correction)?")
            if #available(iOS 18.0, *) { try await requestConfirmation(dialog: prompt) }
            else {
                guard try await $timer.requestConfirmation(for: target, dialog: prompt) else { throw CancellationError() }
            }
        }
        let message = try await VoiceLoggingService.manageTimer(
            action: selectedAction, timerKind: target.kind, profileID: target.profileID,
            eventID: target.id, expectedUpdatedAt: target.updatedAt,
            side: nursingSide, amount: amount, unit: unit, adjustedStart: adjustedStart,
            at: requestedAt, in: container
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct LastCareEntryByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Care Entry"
    static let description = IntentDescription("Reads the last saved entry for a chosen person and category.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Entry") var kind: VoiceCareKind
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    static var parameterSummary: some ParameterSummary { Summary("Get last \(\.$kind) for \(\.$profile)") }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let choices = try await VoiceIntentProfiles.choices(kind: kind)
        let target: VoiceCareProfileEntity
        if let profile { target = profile }
        else if choices.count == 1 { target = choices[0] }
        else { target = try await $profile.requestDisambiguation(among: choices, dialog: "Whose last entry?") }
        let container = try await VoiceLoggingService.container()
        let message = try VoiceLoggingService.last(kind: kind, profileID: target.id, in: container)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct UndoVoiceCareEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Voice Care Entry"
    static let description = IntentDescription("Removes the last unchanged entry created by voice for this person within ten minutes. Timer and medication changes are reviewed in the app.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Profile") var profile: VoiceCareProfileEntity?
    static var parameterSummary: some ParameterSummary { Summary("Undo last voice entry for \(\.$profile)") }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choices = try await VoiceIntentProfiles.choices()
        let target: VoiceCareProfileEntity
        if let profile { target = profile }
        else if choices.count == 1 { target = choices[0] }
        else { target = try await $profile.requestDisambiguation(among: choices, dialog: "Whose voice entry should be undone?") }
        let prompt = IntentDialog(stringLiteral: "Remove the last unchanged voice entry for \(target.name)?")
        if #available(iOS 18.0, *) { try await requestConfirmation(dialog: prompt) }
        else {
            guard try await $profile.requestConfirmation(for: target, dialog: prompt) else {
                throw CancellationError()
            }
        }
        let container = try await VoiceLoggingService.container()
        let message = try await VoiceLoggingService.undo(profileID: target.id, in: container)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

enum VoiceMedicationOutcome: String, AppEnum {
    case taken, skipped
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dose outcome"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.taken: "Taken", .skipped: "Skipped"]
}

struct VoiceMedicationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Medication"
    static var defaultQuery = VoiceMedicationQuery()
    var id: UUID
    var profileID: UUID
    var name: String
    var detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(detail)") }
}

struct VoiceMedicationQuery: EntityStringQuery {
    @MainActor
    func suggestedEntities() async throws -> [VoiceMedicationEntity] {
        let container = try await VoiceLoggingService.container()
        let profiles = try VoiceLoggingService.profiles(in: container)
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { !$0.isArchived })).compactMap { med in
            guard let profileID = med.profileID, let profileName = byID[profileID] else { return nil }
            return VoiceMedicationEntity(id: med.id, profileID: profileID, name: med.name,
                detail: [profileName, med.strengthDescription].compactMap { $0 }.joined(separator: " · "))
        }
    }
    func entities(for identifiers: [UUID]) async throws -> [VoiceMedicationEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [VoiceMedicationEntity] {
        try await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }
}

struct LogMedicationDoseByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Medication Dose by Voice"
    static let description = IntentDescription("Confirms and records a taken or skipped dose from an existing medication plan. Does not create or change prescriptions.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Medication") var medication: VoiceMedicationEntity
    @Parameter(title: "Outcome") var outcome: VoiceMedicationOutcome
    @Parameter(title: "When") var date: Date?
    @Parameter(title: "Scheduled dose") var scheduledDose: String?
    static var parameterSummary: some ParameterSummary {
        Summary("Record \(\.$medication) as \(\.$outcome)") { \.$date; \.$scheduledDose }
    }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try await VoiceLoggingService.container()
        let recordedDate = date ?? Date()
        let plan = try VoiceLoggingService.medicationPlan(
            medicationID: medication.id, profileID: medication.profileID, at: recordedDate, in: container
        )
        let occurrence: MedicationOccurrence?
        if plan.isAsNeeded { occurrence = nil }
        else if let scheduledDose {
            guard let selected = plan.occurrences.first(where: { plan.doseLabel($0) == scheduledDose }) else {
                throw $scheduledDose.needsValueError("Choose a scheduled dose from the current plan.")
            }
            occurrence = selected
        } else if plan.occurrences.count == 1 { occurrence = plan.occurrences[0] }
        else {
            let selected = try await $scheduledDose.requestDisambiguation(
                among: plan.occurrences.map { plan.doseLabel($0) }, dialog: "Which scheduled dose?"
            )
            occurrence = plan.occurrences.first { plan.doseLabel($0) == selected }
        }
        let amount = occurrence?.doseAmount ?? plan.doseAmount
        let unit = occurrence?.doseUnit ?? plan.doseUnit
        let schedule = occurrence.map { " scheduled \($0.scheduledAt.formatted(date: .abbreviated, time: .shortened))" } ?? " as needed"
        let prompt = IntentDialog(stringLiteral:
            "Record \(plan.label), \(amount.formatted()) \(unit)\(schedule), as \(outcome.rawValue) at \(recordedDate.formatted(date: .abbreviated, time: .shortened))?"
        )
        if #available(iOS 18.0, *) { try await requestConfirmation(dialog: prompt) }
        else {
            guard try await $medication.requestConfirmation(for: medication, dialog: prompt) else {
                throw CancellationError()
            }
        }
        let message = try VoiceLoggingService.recordMedication(
            plan: plan, occurrenceKey: occurrence?.occurrenceKey,
            status: outcome == .taken ? .taken : .skipped, at: recordedDate, in: container
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct LittleWindowsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogCareByVoiceIntent(),
            phrases: ["Log care in \(.applicationName)", "Log \(\.$entry) in \(.applicationName)", "Log a \(\.$entry) in \(.applicationName)", "Record \(\.$entry) in \(.applicationName)"],
            shortTitle: "Log Care", systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: ManageCareTimerByVoiceIntent(),
            phrases: [
                "Manage a care timer in \(.applicationName)",
                "\(\.$action) timer in \(.applicationName)",
                "\(\.$action) the timer in \(.applicationName)",
                "Pause \(\.$pauseTimer) in \(.applicationName)",
                "Stop \(\.$pauseTimer) in \(.applicationName)",
                "Resume \(\.$resumeTimer) in \(.applicationName)",
                "Finish \(\.$finishTimer) in \(.applicationName)",
                "Finish and save \(\.$finishTimer) in \(.applicationName)",
                "Stop and save \(\.$finishTimer) in \(.applicationName)",
                "Save \(\.$finishTimer) in \(.applicationName)",
                "Reset \(\.$resetTimer) in \(.applicationName)",
                "Discard \(\.$discardTimer) in \(.applicationName)",
                "Correct \(\.$correctTimer) start time in \(.applicationName)"
            ],
            shortTitle: "Care Timer", systemImageName: "timer"
        )
        AppShortcut(
            intent: StartCareTimerByVoiceIntent(),
            phrases: ["Start \(\.$timerKind) in \(.applicationName)", "Start \(\.$timerKind) timer in \(.applicationName)", "Start a care timer in \(.applicationName)"],
            shortTitle: "Start Care Timer",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: StartNursingLeftByVoiceIntent(),
            phrases: ["Start nursing left in \(.applicationName)", "Start nursing on the left in \(.applicationName)"],
            shortTitle: "Nurse Left",
            systemImageName: "l.circle.fill"
        )
        AppShortcut(
            intent: StartNursingRightByVoiceIntent(),
            phrases: ["Start nursing right in \(.applicationName)", "Start nursing on the right in \(.applicationName)"],
            shortTitle: "Nurse Right",
            systemImageName: "r.circle.fill"
        )
        AppShortcut(
            intent: ActiveCareTimersByVoiceIntent(),
            phrases: ["Show active timers in \(.applicationName)", "What timers are running in \(.applicationName)"],
            shortTitle: "Open Timers", systemImageName: "timer"
        )
        AppShortcut(
            intent: LastCareEntryByVoiceIntent(),
            phrases: ["Get last care entry in \(.applicationName)", "Get last \(\.$kind) in \(.applicationName)"],
            shortTitle: "Last Entry",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: LogDiaperByVoiceIntent(),
            phrases: ["Log \(\.$spokenEntry) in \(.applicationName)", "Record \(\.$spokenEntry) in \(.applicationName)"],
            shortTitle: "Log Diaper",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogMedicationDoseByVoiceIntent(),
            phrases: ["Log medicine in \(.applicationName)"],
            shortTitle: "Medicine",
            systemImageName: "cross.case.fill"
        )
        AppShortcut(
            intent: SwitchActiveNursingSideByVoiceIntent(),
            phrases: ["Switch nursing sides in \(.applicationName)", "Switch nursing side in \(.applicationName)", "Switch sides in \(.applicationName)", "Switch nursing to \(\.$side) in \(.applicationName)"],
            shortTitle: "Switch Sides",
            systemImageName: "arrow.left.arrow.right"
        )


    }
}
