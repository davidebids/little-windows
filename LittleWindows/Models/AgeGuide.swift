import Foundation
import SwiftData

enum AgeGuideTopicCategory: String, Codable, CaseIterable, Identifiable {
    case socialEmotional
    case communication
    case cognitive
    case movementPhysical
    case sleep
    case feeding
    case play
    case safety
    case care
    case health
    case memoryPrompts
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .socialEmotional: "Social & emotional"
        case .communication: "Communication"
        case .cognitive: "Cognitive"
        case .movementPhysical: "Movement & physical"
        case .sleep: "Sleep"
        case .feeding: "Feeding"
        case .play: "Play"
        case .safety: "Safety"
        case .care: "Care"
        case .health: "Health"
        case .memoryPrompts: "Memory prompts"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .socialEmotional: "face.smiling.fill"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .cognitive: "brain.head.profile"
        case .movementPhysical: "figure.child"
        case .sleep: "moon.stars.fill"
        case .feeding: "fork.knife"
        case .play: "sparkles"
        case .safety: "shield.lefthalf.filled"
        case .care: "heart.text.square.fill"
        case .health: "cross.case.fill"
        case .memoryPrompts: "heart.text.clipboard.fill"
        case .custom: "star.fill"
        }
    }
}

enum MonthlyAgeGuideNotificationTiming: String, Codable, CaseIterable, Identifiable {
    case monthlyBirthday
    case oneDayAfter
    case firstWeekendAfter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlyBirthday: "On monthly birthday"
        case .oneDayAfter: "1 day after"
        case .firstWeekendAfter: "First weekend after"
        }
    }
}

struct ContentSourceReference: Codable, Identifiable, Hashable {
    var id: String
    var sourceName: String
    var sourceURL: URL?
    var retrievedOrReviewedDate: Date?
    var notes: String?
}

struct AgeGuideTopic: Codable, Identifiable, Hashable {
    var id: String
    var category: AgeGuideTopicCategory
    var title: String
    var body: String
    var sourceReferenceIDs: [String]?
}

struct MilestonePrompt: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var suggestedCategory: MilestoneCategory
    var promptText: String
    var ageMonth: Int
    var sourceReferenceIDs: [String]?

    var milestoneTemplate: MilestoneTemplate {
        MilestoneTemplate(title: title, category: suggestedCategory)
    }
}

struct AgeGuide: Codable, Identifiable, Hashable {
    var id: String
    var ageMonth: Int
    var title: String
    var subtitle: String
    var overview: String
    var developmentalTopics: [AgeGuideTopic]
    var milestonePrompts: [MilestonePrompt]
    var playIdeas: [String]
    var careNotes: [String]
    var sleepNotes: [String]
    var feedingNotes: [String]
    var safetyNotes: [String]
    var sourceReferences: [ContentSourceReference]
    var isCheckpointAge: Bool
    var disclaimer: String
    var createdAt: Date
    var updatedAt: Date

    var ageLabel: String {
        switch ageMonth {
        case 0: "Newborn"
        case 1: "1 Month"
        default: "\(ageMonth) Months"
        }
    }
}

@Model
final class AgeGuideReadState {
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
