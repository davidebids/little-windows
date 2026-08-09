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

    func currentAgeGuide(for profile: CareProfile, now: Date = Date()) -> AgeGuide? {
        guard profile.profileType.capabilities.supportsAgeGuide else { return nil }
        return ageGuide(for: ageMonth(for: profile, now: now))
    }

    func milestonePrompts(for month: Int) -> [MilestonePrompt] {
        ageGuide(for: month)?.milestonePrompts ?? []
    }

    func ageMonth(for profile: CareProfile, now: Date = Date()) -> Int {
        guard let birthDate = profile.birthDate else { return 0 }
        return max(0, calendar.dateComponents([.month], from: birthDate, to: now).month ?? 0)
    }

    func monthlyBirthdayDate(
        for profile: CareProfile,
        ageMonth: Int
    ) -> Date? {
        guard profile.profileType.capabilities.supportsAgeGuide,
              let birthDate = profile.birthDate else {
            return nil
        }
        return calendar.date(byAdding: .month, value: ageMonth, to: birthDate)
    }

    func shouldShowMonthlyCard(
        profile: CareProfile,
        readState: AgeGuideReadState?,
        now: Date = Date()
    ) -> Bool {
        guard let birthDate = profile.birthDate,
              let guide = currentAgeGuide(for: profile, now: now),
              let reachedDate = monthlyBirthdayDate(for: profile, ageMonth: guide.ageMonth),
              reachedDate <= now,
              !calendar.isDate(reachedDate, inSameDayAs: birthDate) || guide.ageMonth == 0 else {
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
        guard PersistenceService.save(context: context) else { return }
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
        guard PersistenceService.save(context: context) else { return }
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
        let reviewed = ISO8601DateFormatter().date(from: "2026-07-07T00:00:00Z")
        let sources = Self.sources(reviewed: reviewed)
        lessons = [
            SleepGuideLesson(
                id: "safe-sleep",
                title: "Safe sleep comes first",
                subtitle: "Set up each sleep before optimizing schedules.",
                body: "The first sleep skill is not stretching a nap or improving a night. It is building the same safe setup every time a baby sleeps. Once the basics are reliable, the rest of the routine is easier to reason about.",
                sections: [
                    SleepGuideLessonSection(
                        id: "sleep-surface",
                        title: "Start with the sleep space",
                        body: "Use a firm, flat surface made for infant sleep, such as a crib, bassinet, portable crib, or play yard that meets current safety standards. The surface should not indent under the baby, and it should not be inclined. A fitted sheet is enough; pillows, loose blankets, bumpers, stuffed toys, sleep positioners, nests, and similar soft items do not belong in the sleep space."
                    ),
                    SleepGuideLessonSection(
                        id: "sleep-position",
                        title: "Place baby on their back",
                        body: "For naps and night sleep, place babies on their back unless a pediatric clinician gives different guidance for a specific medical reason. If a baby later rolls both directions on their own, the key is still to begin each sleep on the back and keep the sleep space clear."
                    ),
                    SleepGuideLessonSection(
                        id: "sleep-away-from-products",
                        title: "Move sleep out of sitting devices",
                        body: "Car seats, swings, carriers, strollers, and similar products are useful for travel or soothing, but they are not the planned sleep setup. If a baby falls asleep there, move them to a firm, flat sleep surface as soon as practical. This is especially important when adults are tired and may be tempted to let an unplanned sleep continue."
                    )
                ],
                bullets: [
                    "Before every sleep, check back, flat surface, and clear space.",
                    "Treat safety setup as the baseline, not as a schedule preference.",
                    "If a sleep begins in a sitting or carrying product, plan the transfer before the caregiver gets too tired."
                ],
                sourceReferences: sources.filter { ["healthychildren-safe-sleep", "nichd-safe-to-sleep"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "normal-sleep",
                title: "Normal sleep is variable",
                subtitle: "Night waking is common, especially early on.",
                body: "Baby sleep is not a straight climb toward longer nights. It changes with age, feeding, growth, illness, daily rhythm, and new skills. A difficult night can be real and exhausting without meaning that anything is wrong.",
                sections: [
                    SleepGuideLessonSection(
                        id: "early-fragmented-sleep",
                        title: "Early sleep is fragmented",
                        body: "HealthyChildren notes that newborn sleep often comes in short stretches, and regular sleep cycles are not expected until around 6 months. That means a young baby's day can look scattered: frequent wakes, short naps, and nights that do not yet feel predictable."
                    ),
                    SleepGuideLessonSection(
                        id: "ranges-not-targets",
                        title: "Ranges are not a daily score",
                        body: "The American Academy of Sleep Medicine gives broad 24-hour sleep ranges beginning at 4 months because normal sleep needs differ. Those ranges are helpful context, but they are not a grade for a single day. Look for the overall pattern, the baby's alertness and comfort, and whether concerns keep repeating."
                    ),
                    SleepGuideLessonSection(
                        id: "patterns-need-days",
                        title: "Patterns need more than one night",
                        body: "One short nap, one long wake, or one unusually broken night is usually less informative than several days together. Logs become useful when they show repeated timing, total sleep, feeding-to-sleep patterns, or changes that line up with travel, illness, or a new routine."
                    )
                ],
                bullets: [
                    "Compare today with several recent days, not with an ideal day.",
                    "Use duration ranges as context after 4 months, not as a diagnosis.",
                    "Add notes for illness, travel, new skills, or unusually disrupted care."
                ],
                sourceReferences: sources.filter { ["healthychildren-sleep", "aasm-duration"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "routines",
                title: "Routines make patterns easier to read",
                subtitle: "Consistent cues can help the whole household.",
                body: "A routine is a set of cues, not a promise that sleep will happen on command. The goal is to make transitions calmer and easier to repeat, especially when more than one caregiver is sharing the day.",
                sections: [
                    SleepGuideLessonSection(
                        id: "short-repeatable-routine",
                        title: "Make it short enough to repeat",
                        body: "The best routine is one the household can actually do on ordinary days. A few predictable steps, such as feeding, diaper, sleep sack, book or song, and lights down, can be more durable than a long routine that only works when everything is perfect."
                    ),
                    SleepGuideLessonSection(
                        id: "day-night-signals",
                        title: "Separate day and night signals",
                        body: "During the day, normal light, interaction, and movement can help make daytime feel distinct. Overnight, lower light and calmer care can help keep wakes from turning into full playtime. These signals are gentle supports; they do not need to be rigid."
                    ),
                    SleepGuideLessonSection(
                        id: "routine-changes",
                        title: "Expect routines to bend",
                        body: "Growth, illness, travel, feeding changes, and developmental practice can all interrupt a routine that was working. When that happens, keep the safest and most repeatable pieces, then rebuild from there. Notes in Little Windows can explain why a week looks different instead of making the data feel confusing."
                    )
                ],
                bullets: [
                    "Choose a bedtime routine that can survive a tired weekday.",
                    "Use calmer light and interaction for overnight care when possible.",
                    "Log disruptions so later sleep patterns have context."
                ],
                sourceReferences: sources.filter { ["medlineplus-bedtime", "healthychildren-sleep"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "use-logs",
                title: "Use logs as planning cues",
                subtitle: "Predictions are aids, not instructions.",
                body: "Logs are strongest when they help caregivers prepare. They are weakest when they make a hard day feel like a failure. Little Windows can estimate likely windows, but the app is reading patterns from past entries, not telling the baby what must happen next.",
                sections: [
                    SleepGuideLessonSection(
                        id: "complete-start-end",
                        title: "Start and end times matter",
                        body: "Completed sleep entries help the app estimate wake windows, day totals, and night patterns. If a timer was left running or a nap was entered later from memory, correct it when you can. Approximate data is still useful, but accurate start and end times make the planning cues steadier."
                    ),
                    SleepGuideLessonSection(
                        id: "confidence-is-context",
                        title: "Read confidence as context",
                        body: "A higher-confidence prediction means the recent pattern is more consistent. A lower-confidence prediction should feel wider and softer: a reminder to prepare, not a reason to force sleep. Real tired cues, feeding needs, illness, and household constraints still matter."
                    ),
                    SleepGuideLessonSection(
                        id: "look-for-questions",
                        title: "Use logs to find better questions",
                        body: "Good logs can reveal questions to test: Is the last wake window often long? Are naps short after a disrupted morning? Did overnight awake time change this week? Those questions are more helpful than trying to prove that one exact schedule is correct."
                    )
                ],
                bullets: [
                    "Fix obvious timer mistakes when you notice them.",
                    "Treat low confidence as a broad heads-up, not a command.",
                    "Use notes to connect sleep changes with feeding, illness, travel, or schedule shifts."
                ],
                sourceReferences: sources.filter { ["aasm-duration", "healthychildren-sleep"].contains($0.id) }
            ),
            SleepGuideLesson(
                id: "when-to-ask",
                title: "Know when to ask for help",
                subtitle: "Bring concerns and patterns to a clinician.",
                body: "Sleep education can reduce guesswork, but it cannot replace medical guidance. When sleep feels connected to safety, breathing, feeding, illness, development, or caregiver exhaustion, the right next step is support from a pediatric clinician or another trusted care resource.",
                sections: [
                    SleepGuideLessonSection(
                        id: "bring-patterns",
                        title: "Bring patterns, not pressure",
                        body: "Logs can make a pediatric conversation easier because they show timing, duration, wakes, feeding notes, and changes over several days. They are context, not proof of a diagnosis. Share what you are seeing and what worries you most."
                    ),
                    SleepGuideLessonSection(
                        id: "concern-categories",
                        title: "Do not wait on safety concerns",
                        body: "Ask for help with persistent sleep concerns, breathing worries, feeding or growth concerns, extreme fussiness, illness, or anything that feels unusual for the baby. If something seems urgent, use urgent or emergency care instead of waiting to collect more data."
                    ),
                    SleepGuideLessonSection(
                        id: "caregiver-safety",
                        title: "Caregiver safety counts too",
                        body: "Severe sleep deprivation can make safe care harder. If a caregiver is too tired to safely stay awake while holding or feeding the baby, prioritize a safe handoff, put the baby in a safe sleep space, and ask for practical help. A safe setup is more important than completing a perfect routine."
                    )
                ],
                bullets: [
                    "Share several days of logs when asking about recurring patterns.",
                    "Escalate breathing, feeding, illness, or urgent safety worries promptly.",
                    "When caregiver exhaustion is high, choose safe handoff and safe sleep setup first."
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
