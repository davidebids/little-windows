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
                "Bring questions or patterns that concern you to your baby's pediatrician."
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
                body: "You may notice new ways your baby responds to familiar people, expressions, songs, or daily routines.",
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
            ("Reached for a toy", .motor, "Did your baby reach, swipe, grab, or show a new favorite toy?"),
            ("New funny habit", .funny, "What tiny habit made you laugh this month?"),
            ("New favorite book", .firsts, "Was there a book, song, or story that got a reaction?"),
            ("Sized up diapers or clothes", .growth, "Did your baby move into a new diaper or clothing size?")
        ]
        let monthSpecific: [(String, MilestoneCategory, String)]
        switch month {
        case 2:
            monthSpecific = [
                ("First social smile", .social, "Did your baby give a smile that felt especially connected?"),
                ("First coo conversation", .communication, "Did your baby start a little back-and-forth with coos or sounds?")
            ]
        case 4:
            monthSpecific = [
                ("First big laugh", .social, "Did your baby laugh, squeal, or light up in a new way?"),
                ("Held hands together at center", .motor, "Did your baby bring hands together or to the mouth?")
            ]
        case 6:
            monthSpecific = [
                ("Tried a new food", .feeding, "Did your baby explore a new taste, texture, or feeding routine?"),
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
            "Talk or sing during diaper changes and wait for your baby's response.",
            "Offer a safe toy slightly to the side and watch for looking, reaching, or batting.",
            "Read one short book and log any new reaction as a memory.",
            "Try a few minutes of supervised tummy time when your baby is calm and alert."
        ]
    }

    private static func feeding(_ month: Int) -> [String] {
        if month >= 6 {
            return [
                "If solids are part of your baby's care plan, this can be a good place to capture first tastes and reactions.",
                "Use feeding notes for memories and questions to bring to the pediatrician."
            ]
        }
        return [
            "Feeding patterns can change during growth and routine shifts.",
            "If you have concerns about intake, comfort, or growth, ask your baby's pediatrician."
        ]
    }
}

struct SleepGuideService {
    static let shared = SleepGuideService()

    let lessons: [SleepGuideLesson]

    private init() {
        let reviewed = ISO8601DateFormatter().date(from: "2026-07-05T00:00:00Z")
        let sources = Self.sources(reviewed: reviewed)
        lessons = [
            SleepGuideLesson(
                id: "safe-sleep",
                title: "Safe sleep comes first",
                subtitle: "Set up each sleep before optimizing schedules.",
                body: "Before comparing wake windows or night patterns, keep the sleep setup simple and safe. Little Windows should support routines, but it should never override safe-sleep guidance or a pediatrician's advice.",
                bullets: [
                    "Use a firm, flat sleep surface designed for infant sleep.",
                    "Place babies on their back for naps and night sleep unless your pediatrician gives different guidance.",
                    "Keep pillows, loose blankets, bumpers, and soft objects out of the sleep space.",
                    "Move a baby who falls asleep in a car seat, swing, carrier, or stroller to a firm sleep surface as soon as practical."
                ],
                sourceReferences: sources.filter { ["healthychildren-safe-sleep", "nichd-safe-to-sleep"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "normal-sleep",
                title: "Normal sleep is variable",
                subtitle: "Night waking is common, especially early on.",
                body: "Baby sleep changes quickly. Newborn sleep is often fragmented, and many babies still wake at night as their day-night rhythm develops. Use logs to spot patterns across several days, not to judge one hard night.",
                bullets: [
                    "HealthyChildren notes that regular sleep cycles are not expected until around 6 months.",
                    "AASM gives broad sleep-duration ranges starting at 4 months because younger infant sleep varies widely.",
                    "A single short nap or difficult night is less useful than a pattern across several days."
                ],
                sourceReferences: sources.filter { ["healthychildren-sleep", "aasm-duration"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "routines",
                title: "Routines make patterns easier to read",
                subtitle: "Consistent cues can help the whole household.",
                body: "A calm, repeatable routine can make sleep transitions more predictable. The goal is not perfection; it is giving caregivers and the baby familiar signals around naps, bedtime, and overnight care.",
                bullets: [
                    "Keep the routine short enough to repeat on ordinary nights.",
                    "Use low light and quiet care during overnight wakings when possible.",
                    "Log meaningful changes such as travel, illness, new skills, or schedule disruptions in notes."
                ],
                sourceReferences: sources.filter { ["medlineplus-bedtime", "healthychildren-sleep"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "use-logs",
                title: "Use logs as planning cues",
                subtitle: "Predictions are aids, not instructions.",
                body: "Little Windows can estimate windows from completed sleep logs, but babies are not clocks. Treat predictions, sleep pressure, and the day-ahead plan as a way to prepare, then adjust for real tired cues and family constraints.",
                bullets: [
                    "Night-waking logs help separate awake time from actual night sleep.",
                    "Complete start and end times improve wake-window and sleep-score calculations.",
                    "Prediction confidence matters; lower confidence should feel like a wider planning cue."
                ],
                sourceReferences: sources.filter { ["aasm-duration", "healthychildren-sleep"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "when-to-ask",
                title: "Know when to ask for help",
                subtitle: "Bring concerns and patterns to a clinician.",
                body: "This course is general education. If sleep changes feel unusual, intense, or connected with breathing, feeding, illness, development, or caregiver safety, check with your pediatrician.",
                bullets: [
                    "Ask about persistent concerns, breathing worries, feeding concerns, or extreme fussiness.",
                    "Share logs as context, not as proof of a diagnosis.",
                    "If a caregiver is too tired to safely stay awake, prioritize safe handoff and safe sleep setup."
                ],
                sourceReferences: sources.filter { ["healthychildren-safe-sleep", "medlineplus-bedtime"].contains($0.id) }
            )
        ]
    }

    private static func sources(reviewed: Date?) -> [ContentSourceReference] {
        [
            ContentSourceReference(
                id: "healthychildren-sleep",
                sourceName: "HealthyChildren.org by the American Academy of Pediatrics - Sleep",
                sourceURL: URL(string: "https://www.healthychildren.org/English/ages-stages/baby/sleep/Pages/default.aspx"),
                retrievedOrReviewedDate: reviewed,
                notes: "Used for normal infant sleep variability and parent-facing sleep framing."
            ),
            ContentSourceReference(
                id: "healthychildren-safe-sleep",
                sourceName: "HealthyChildren.org by the American Academy of Pediatrics - Safe Sleep",
                sourceURL: URL(string: "https://www.healthychildren.org/English/ages-stages/baby/sleep/Pages/A-Parents-Guide-to-Safe-Sleep.aspx"),
                retrievedOrReviewedDate: reviewed,
                notes: "Used for safe sleep setup and caregiver safety reminders."
            ),
            ContentSourceReference(
                id: "nichd-safe-to-sleep",
                sourceName: "NIH/NICHD Safe to Sleep",
                sourceURL: URL(string: "https://safetosleep.nichd.nih.gov/reduce-risk/reduce"),
                retrievedOrReviewedDate: reviewed,
                notes: "Used for sleep-related infant death risk-reduction framing."
            ),
            ContentSourceReference(
                id: "aasm-duration",
                sourceName: "American Academy of Sleep Medicine pediatric sleep duration consensus",
                sourceURL: URL(string: "https://aasm.org/resources/pdf/pediatricsleepdurationconsensus.pdf"),
                retrievedOrReviewedDate: reviewed,
                notes: "Used for broad sleep-duration ranges and variability cautions."
            ),
            ContentSourceReference(
                id: "medlineplus-bedtime",
                sourceName: "MedlinePlus Medical Encyclopedia - Bedtime habits for infants and children",
                sourceURL: URL(string: "https://medlineplus.gov/ency/article/002392.htm"),
                retrievedOrReviewedDate: reviewed,
                notes: "Used for routine and bedtime-habit framing."
            )
        ]
    }
}
