import Foundation
import SwiftData

struct AgeGuideService {
    static let shared = AgeGuideService()

    private let guides: [AgeGuide]
    private let calendar: Calendar

    init(bundle: Bundle = .main, calendar: Calendar = .current) {
        self.calendar = calendar
        guides = (
            try? Self.loadGuides(bundle: bundle)
        )?.sorted { $0.ageMonth < $1.ageMonth } ?? Self.fallbackGuides()
    }

    static func loadGuides(bundle: Bundle = .main) throws -> [AgeGuide] {
        guard let url = bundle.url(
            forResource: "guides",
            withExtension: "json",
            subdirectory: "AgeGuides"
        ) ?? bundle.url(forResource: "guides", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AgeGuide].self, from: Data(contentsOf: url))
    }

    func allAgeGuides() -> [AgeGuide] {
        guides
    }

    func ageGuide(for month: Int) -> AgeGuide? {
        guides.first { $0.ageMonth == month }
    }

    func currentAgeGuide(for profile: BabyProfile, now: Date = Date()) -> AgeGuide? {
        ageGuide(for: ageMonth(for: profile, now: now))
    }

    func milestonePrompts(for month: Int) -> [MilestonePrompt] {
        ageGuide(for: month)?.milestonePrompts ?? []
    }

    func ageMonth(for profile: BabyProfile, now: Date = Date()) -> Int {
        max(0, calendar.dateComponents([.month], from: profile.birthDate, to: now).month ?? 0)
    }

    func monthlyBirthdayDate(
        for profile: BabyProfile,
        ageMonth: Int
    ) -> Date? {
        calendar.date(byAdding: .month, value: ageMonth, to: profile.birthDate)
    }

    func shouldShowMonthlyCard(
        profile: BabyProfile,
        readState: AgeGuideReadState?,
        now: Date = Date()
    ) -> Bool {
        guard let guide = currentAgeGuide(for: profile, now: now),
              let reachedDate = monthlyBirthdayDate(for: profile, ageMonth: guide.ageMonth),
              reachedDate <= now,
              !calendar.isDate(reachedDate, inSameDayAs: profile.birthDate) || guide.ageMonth == 0 else {
            return false
        }
        guard readState?.isDismissedFromToday != true else { return false }
        let showUntil = calendar.date(byAdding: .day, value: 7, to: reachedDate) ?? reachedDate
        return now <= showUntil
    }

    @MainActor
    func markGuideRead(
        _ guide: AgeGuide,
        in context: ModelContext,
        readStates: [AgeGuideReadState],
        profileID: UUID? = nil,
        now: Date = Date()
    ) {
        let state = readStates.first {
            $0.guideID == guide.id && $0.matchesProfile(profileID)
        } ?? AgeGuideReadState(
            profileID: profileID,
            guideID: guide.id,
            createdAt: now,
            updatedAt: now
        )
        state.profileID = state.profileID ?? profileID
        if state.modelContext == nil {
            context.insert(state)
        }
        if state.firstOpenedAt == nil {
            state.firstOpenedAt = now
        }
        state.lastOpenedAt = now
        state.updatedAt = now
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    @MainActor
    func markMonthlyCardDismissed(
        _ guide: AgeGuide,
        in context: ModelContext,
        readStates: [AgeGuideReadState],
        profileID: UUID? = nil,
        now: Date = Date()
    ) {
        let state = readStates.first {
            $0.guideID == guide.id && $0.matchesProfile(profileID)
        } ?? AgeGuideReadState(
            profileID: profileID,
            guideID: guide.id,
            createdAt: now,
            updatedAt: now
        )
        state.profileID = state.profileID ?? profileID
        if state.modelContext == nil {
            context.insert(state)
        }
        state.isDismissedFromToday = true
        state.updatedAt = now
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    private static func fallbackGuides() -> [AgeGuide] {
        let sourceDate = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")
        let sources = [
            ContentSourceReference(
                id: "cdc-act-early",
                sourceName: "CDC Learn the Signs. Act Early.",
                sourceURL: URL(string: "https://www.cdc.gov/act-early/milestones/index.html"),
                retrievedOrReviewedDate: sourceDate,
                notes: "Used as the preferred basis for checkpoint-age milestone themes."
            ),
            ContentSourceReference(
                id: "healthychildren",
                sourceName: "HealthyChildren.org by the American Academy of Pediatrics",
                sourceURL: URL(string: "https://www.healthychildren.org/English/ages-stages/baby/Pages/default.aspx"),
                retrievedOrReviewedDate: sourceDate,
                notes: "Used for parent-facing development, care, play, feeding, and safety framing."
            )
        ]
        let disclaimer = "Monthly guides are based on general developmental information and your logged data. They are not medical advice. Ask your pediatrician if you have concerns about development."
        return Array(2...12).map { month in
            guide(
                month: month,
                sources: sources,
                disclaimer: disclaimer
            )
        }
    }

    private static func guide(
        month: Int,
        sources: [ContentSourceReference],
        disclaimer: String
    ) -> AgeGuide {
        let title = month == 1 ? "Baby at 1 Month" : "Baby at \(month) Months"
        let checkpoint = [2, 4, 6, 9, 12].contains(month)
        let reviewed = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z") ?? Date()
        return AgeGuide(
            id: "age-\(String(format: "%02d", month))",
            ageMonth: month,
            title: title,
            subtitle: checkpoint
                ? "A checkpoint-style guide with gentle milestone prompts."
                : "A between-checkpoint guide for memories, play, and routines.",
            overview: overview(month),
            developmentalTopics: topics(month),
            milestonePrompts: prompts(month),
            playIdeas: playIdeas(month),
            careNotes: [
                "Keep using your logs as a parent memory aid, not as a scorecard.",
                "Bring questions or patterns that concern you to Ethan's pediatrician."
            ],
            sleepNotes: [
                "Sleep can shift quickly during growth, travel, illness, and new skills.",
                "Look for patterns over several days rather than one difficult nap or night."
            ],
            feedingNotes: feeding(month),
            safetyNotes: [
                "As movement increases, re-check floor spaces, changing surfaces, cords, and small objects.",
                "Use this guide as a prompt for discussion, not as a medical checklist."
            ],
            sourceReferences: sources,
            isCheckpointAge: checkpoint,
            disclaimer: disclaimer,
            createdAt: reviewed,
            updatedAt: reviewed
        )
    }

    private static func overview(_ month: Int) -> String {
        switch month {
        case 2:
            return "Around 2 months, many babies become more alert, more responsive to faces and voices, and more expressive in small ways. Every baby develops on their own timeline."
        case 3:
            return "Around 3 months, you may notice more social interaction, stronger head control, and new interest in hands, sounds, and nearby toys."
        case 4:
            return "Around 4 months, many babies become more expressive, more interested in faces and voices, and more active with their hands and body. Every baby develops on their own timeline."
        case 5:
            return "Around 5 months, this can be a playful in-between stage: more reaching, more sound-making, and more curiosity about routines and people."
        case 6:
            return "Around 6 months, many babies are increasingly interactive and physical. This is often a helpful month to capture new sounds, movement, feeding changes, and favorite games."
        default:
            return "This month can bring new rhythms, small surprises, and memory-worthy little changes."
        }
    }

    private static func topics(_ month: Int) -> [AgeGuideTopic] {
        [
            AgeGuideTopic(
                id: "social-\(month)",
                category: .socialEmotional,
                title: "Faces, voices, and connection",
                body: "You may notice new ways Ethan responds to familiar people, expressions, songs, or daily routines.",
                sourceReferenceIDs: ["cdc-act-early", "healthychildren"]
            ),
            AgeGuideTopic(
                id: "communication-\(month)",
                category: .communication,
                title: "Sounds and back-and-forth",
                body: "Listen for new coos, squeals, laughs, pauses, or favorite sounds. These can make sweet milestone memories without turning them into a checklist.",
                sourceReferenceIDs: ["cdc-act-early"]
            ),
            AgeGuideTopic(
                id: "movement-\(month)",
                category: .movementPhysical,
                title: "Hands, head, and body",
                body: "Many babies around this age show changing control of their head, hands, arms, or legs. Capture new attempts as memories, not pass/fail moments.",
                sourceReferenceIDs: ["cdc-act-early"]
            ),
            AgeGuideTopic(
                id: "play-\(month)",
                category: .play,
                title: "Simple play matters",
                body: "Short, gentle play windows with talking, reading, singing, tummy time, and reaching games can support development and create memories.",
                sourceReferenceIDs: ["healthychildren"]
            )
        ]
    }

    private static func prompts(_ month: Int) -> [MilestonePrompt] {
        let base: [(String, MilestoneCategory, String)] = [
            ("New favorite sound", .communication, "What sound, squeal, laugh, or coo stood out this month?"),
            ("Reached for a toy", .motor, "Did Ethan reach, swipe, grab, or show a new favorite toy?"),
            ("New funny habit", .funny, "What tiny habit made you laugh this month?"),
            ("New favorite book", .firsts, "Was there a book, song, or story that got a reaction?"),
            ("Sized up diapers or clothes", .growth, "Did Ethan move into a new diaper or clothing size?")
        ]
        let monthSpecific: [(String, MilestoneCategory, String)]
        switch month {
        case 2:
            monthSpecific = [
                ("First social smile", .social, "Did Ethan give a smile that felt especially connected?"),
                ("First coo conversation", .communication, "Did Ethan start a little back-and-forth with coos or sounds?")
            ]
        case 4:
            monthSpecific = [
                ("First big laugh", .social, "Did Ethan laugh, squeal, or light up in a new way?"),
                ("Held hands together at center", .motor, "Did Ethan bring hands together or to the mouth?")
            ]
        case 6:
            monthSpecific = [
                ("Tried a new food", .feeding, "Did Ethan explore a new taste, texture, or feeding routine?"),
                ("Sat with support", .motor, "Was there a new sitting, rolling, or reaching moment?")
            ]
        default:
            monthSpecific = []
        }
        return (monthSpecific + base).enumerated().map { index, value in
            MilestonePrompt(
                id: "prompt-\(month)-\(index)",
                title: value.0,
                suggestedCategory: value.1,
                promptText: value.2,
                ageMonth: month,
                sourceReferenceIDs: ["cdc-act-early", "healthychildren"]
            )
        }
    }

    private static func playIdeas(_ month: Int) -> [String] {
        [
            "Talk or sing during diaper changes and wait for Ethan's response.",
            "Offer a safe toy slightly to the side and watch for looking, reaching, or batting.",
            "Read one short book and log any new reaction as a memory.",
            "Try a few minutes of supervised tummy time when Ethan is calm and alert."
        ]
    }

    private static func feeding(_ month: Int) -> [String] {
        if month >= 6 {
            return [
                "If solids are part of Ethan's care plan, this can be a good place to capture first tastes and reactions.",
                "Use feeding notes for memories and questions to bring to the pediatrician."
            ]
        }
        return [
            "Feeding patterns can change during growth and routine shifts.",
            "If you have concerns about intake, comfort, or growth, ask Ethan's pediatrician."
        ]
    }
}
