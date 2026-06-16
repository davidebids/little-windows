import Foundation
import SwiftData

enum PuppyStageTopicCategory: String, Codable, CaseIterable, Identifiable {
    case socialization
    case pottyTraining
    case crateTraining
    case training
    case leashSkills
    case feeding
    case sleepRest
    case chewingTeething
    case grooming
    case healthVet
    case safety
    case enrichment
    case adolescence
    case memoryPrompts
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pottyTraining: "Potty Training"
        case .crateTraining: "Crate Training"
        case .leashSkills: "Leash Skills"
        case .sleepRest: "Sleep & Rest"
        case .chewingTeething: "Chewing & Teething"
        case .healthVet: "Vet Care"
        case .memoryPrompts: "Memory Prompts"
        default: rawValue.capitalized
        }
    }
}

struct PuppyStageGuideTopic: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var category: PuppyStageTopicCategory
    var title: String
    var body: String
}

struct DogMilestonePrompt: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var suggestedCategoryRawValue: String
    var promptText: String
    var stageKey: String

    var suggestedCategory: MilestoneCategory {
        MilestoneCategory(rawValue: suggestedCategoryRawValue) ?? .custom
    }
}

struct DogTrainingPrompt: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var trainingTypeRawValue: String
    var promptText: String
    var stageKey: String

    var trainingType: DogTrainingType {
        DogTrainingType(rawValue: trainingTypeRawValue) ?? .other
    }
}

struct PuppyStageGuide: Codable, Identifiable, Equatable {
    var id: String { stageKey }
    var stageKey: String
    var title: String
    var subtitle: String
    var minAgeWeeks: Double?
    var maxAgeWeeks: Double?
    var overview: String
    var topics: [PuppyStageGuideTopic]
    var milestonePrompts: [DogMilestonePrompt]
    var trainingPrompts: [DogTrainingPrompt]
    var careNotes: [String]
    var vetCareNotes: [String]
    var sourceReferences: [ContentSourceReference]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@Model
final class PuppyStageGuideReadState {
    var id: UUID = UUID()
    var profileID: UUID?
    var guideID: String = ""
    var firstOpenedAt: Date?
    var lastOpenedAt: Date?
    var isDismissedFromToday: Bool = false
    var notificationSentAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID? = nil,
        guideID: String,
        firstOpenedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        isDismissedFromToday: Bool = false,
        notificationSentAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.guideID = guideID
        self.firstOpenedAt = firstOpenedAt
        self.lastOpenedAt = lastOpenedAt
        self.isDismissedFromToday = isDismissedFromToday
        self.notificationSentAt = notificationSentAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
