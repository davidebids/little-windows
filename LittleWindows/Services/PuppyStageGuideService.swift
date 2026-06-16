import Foundation
import SwiftData

@MainActor
final class PuppyStageGuideService {
    static let shared = PuppyStageGuideService()

    private init() {}

    func allGuides() -> [PuppyStageGuide] {
        Self.guides
    }

    func guide(forStageKey key: String) -> PuppyStageGuide? {
        allGuides().first { $0.stageKey == key }
    }

    func currentGuide(for profile: CareProfile, now: Date = Date()) -> PuppyStageGuide? {
        guard profile.profileType == .dog else { return nil }
        let weeks = ageWeeks(for: profile, now: now)
        return allGuides().first { guide in
            let min = guide.minAgeWeeks ?? -Double.infinity
            let max = guide.maxAgeWeeks ?? .infinity
            return weeks >= min && weeks < max
        } ?? allGuides().last
    }

    func shouldShowStageCard(
        profile: CareProfile,
        readState: PuppyStageGuideReadState?,
        now: Date = Date()
    ) -> Bool {
        guard profile.profileType == .dog,
              currentGuide(for: profile, now: now) != nil else {
            return false
        }
        return readState?.isDismissedFromToday != true
    }

    func markGuideRead(
        _ guide: PuppyStageGuide,
        in context: ModelContext,
        readStates: [PuppyStageGuideReadState],
        profileID: UUID?
    ) {
        let now = Date()
        let state = readStates.first {
            $0.guideID == guide.id && $0.matchesProfile(profileID)
        } ?? PuppyStageGuideReadState(profileID: profileID, guideID: guide.id)
        if state.modelContext == nil {
            context.insert(state)
        }
        state.profileID = state.profileID ?? profileID
        if state.firstOpenedAt == nil {
            state.firstOpenedAt = now
        }
        state.lastOpenedAt = now
        state.updatedAt = now
        try? context.save()
    }

    func markStageCardDismissed(
        _ guide: PuppyStageGuide,
        in context: ModelContext,
        readStates: [PuppyStageGuideReadState],
        profileID: UUID?
    ) {
        let now = Date()
        let state = readStates.first {
            $0.guideID == guide.id && $0.matchesProfile(profileID)
        } ?? PuppyStageGuideReadState(profileID: profileID, guideID: guide.id)
        if state.modelContext == nil {
            context.insert(state)
        }
        state.profileID = state.profileID ?? profileID
        state.isDismissedFromToday = true
        state.updatedAt = now
        try? context.save()
    }

    func ageWeeks(for profile: CareProfile, now: Date = Date(), calendar: Calendar = .current) -> Double {
        let days = calendar.dateComponents([.day], from: profile.birthDate, to: now).day ?? 0
        return max(0, Double(days) / 7)
    }

    private static let guides: [PuppyStageGuide] = [
        PuppyStageGuide(
            stageKey: "stage_08_weeks",
            title: "8 Weeks",
            subtitle: "Settling in, gentle routines, and first confidence wins",
            minAgeWeeks: 0,
            maxAgeWeeks: 10,
            overview: "Many puppies around this stage are learning home routines, short potty rhythms, crate comfort, and gentle handling. Keep notes practical and ask your veterinarian or trainer if you have concerns.",
            topics: [
                PuppyStageGuideTopic(category: .pottyTraining, title: "Potty rhythm", body: "Consider logging pee, poop, and accidents so patterns are easier to spot."),
                PuppyStageGuideTopic(category: .crateTraining, title: "Crate comfort", body: "Short, calm crate rests can be logged as rest or training wins."),
                PuppyStageGuideTopic(category: .healthVet, title: "Vet records", body: "Use vaccine and vet appointment logs to keep records together.")
            ],
            milestonePrompts: [
                DogMilestonePrompt(title: "First night home", suggestedCategoryRawValue: MilestoneCategory.adoption.rawValue, promptText: "Capture the first cozy night in the family timeline.", stageKey: "stage_08_weeks"),
                DogMilestonePrompt(title: "First successful potty outside", suggestedCategoryRawValue: MilestoneCategory.pottyTraining.rawValue, promptText: "Mark the little win without judging the pace.", stageKey: "stage_08_weeks")
            ],
            trainingPrompts: [
                DogTrainingPrompt(title: "Practice name recognition", trainingTypeRawValue: DogTrainingType.obedience.rawValue, promptText: "Short, upbeat repetitions are enough to log.", stageKey: "stage_08_weeks"),
                DogTrainingPrompt(title: "Practice crate comfort", trainingTypeRawValue: DogTrainingType.crateTraining.rawValue, promptText: "Log a calm crate moment or short rest.", stageKey: "stage_08_weeks")
            ],
            careNotes: ["Keep notes simple: food, water, potty, rest, and short training sessions.", "Avoid comparing one puppy's pace against another."],
            vetCareNotes: ["Record vaccines, symptoms, and questions for your vet without interpreting them medically."],
            sourceReferences: []
        ),
        PuppyStageGuide(
            stageKey: "stage_12_weeks",
            title: "12 Weeks",
            subtitle: "Socialization, leash foundations, potty patterns, and early skills",
            minAgeWeeks: 10,
            maxAgeWeeks: 16,
            overview: "Around this stage, many puppies benefit from gentle exposure, short training sessions, and continued potty pattern tracking. Keep it flexible and contact your vet or trainer for individualized guidance.",
            topics: [
                PuppyStageGuideTopic(category: .socialization, title: "Gentle exposure", body: "Log calm outings and new experiences as activities or memories."),
                PuppyStageGuideTopic(category: .leashSkills, title: "Leash practice", body: "Walk logs can include duration, distance, potty counts, and leash behavior without GPS."),
                PuppyStageGuideTopic(category: .training, title: "Simple commands", body: "Track sit, down, recall, settle, or whatever your trainer recommends.")
            ],
            milestonePrompts: [
                DogMilestonePrompt(title: "First walk", suggestedCategoryRawValue: MilestoneCategory.travel.rawValue, promptText: "Capture the first walk as a memory.", stageKey: "stage_12_weeks"),
                DogMilestonePrompt(title: "Learned sit", suggestedCategoryRawValue: MilestoneCategory.training.rawValue, promptText: "Save the training win in the timeline.", stageKey: "stage_12_weeks")
            ],
            trainingPrompts: [
                DogTrainingPrompt(title: "Practice sit", trainingTypeRawValue: DogTrainingType.obedience.rawValue, promptText: "Log a short session and outcome.", stageKey: "stage_12_weeks"),
                DogTrainingPrompt(title: "Practice leash walking", trainingTypeRawValue: DogTrainingType.leash.rawValue, promptText: "Track duration and leash behavior.", stageKey: "stage_12_weeks")
            ],
            careNotes: ["Walks can be timer-based or manually entered.", "Potty accidents are tracking data, not a judgment."],
            vetCareNotes: ["Keep vaccine due dates and visit notes in the medical history."],
            sourceReferences: []
        ),
        PuppyStageGuide(
            stageKey: "stage_06_months",
            title: "6 Months",
            subtitle: "Adolescent energy, training refreshers, grooming comfort, and routines",
            minAgeWeeks: 16,
            maxAgeWeeks: 52,
            overview: "Many dogs change rhythms through adolescence. Use logs to spot your own routine trends and keep concerns for your veterinarian or trainer.",
            topics: [
                PuppyStageGuideTopic(category: .adolescence, title: "Changing routines", body: "Track walks, training, rest, and symptoms neutrally."),
                PuppyStageGuideTopic(category: .grooming, title: "Grooming comfort", body: "Log brushing, baths, nail trims, teeth brushing, and professional grooming."),
                PuppyStageGuideTopic(category: .enrichment, title: "Training and play", body: "Short training sessions and enrichment can be logged without making comparisons.")
            ],
            milestonePrompts: [
                DogMilestonePrompt(title: "First groom", suggestedCategoryRawValue: MilestoneCategory.grooming.rawValue, promptText: "Capture the first full groom or haircut.", stageKey: "stage_06_months"),
                DogMilestonePrompt(title: "Favorite toy discovered", suggestedCategoryRawValue: MilestoneCategory.favoriteThings.rawValue, promptText: "Save the funny little favorite.", stageKey: "stage_06_months")
            ],
            trainingPrompts: [
                DogTrainingPrompt(title: "Practice recall", trainingTypeRawValue: DogTrainingType.recall.rawValue, promptText: "Log the session and outcome.", stageKey: "stage_06_months"),
                DogTrainingPrompt(title: "Practice settle/place", trainingTypeRawValue: DogTrainingType.behavior.rawValue, promptText: "Capture calm wins too.", stageKey: "stage_06_months")
            ],
            careNotes: ["Use trends as household context, not diagnosis.", "Structured notes make vet and trainer conversations easier."],
            vetCareNotes: ["Record medicine, vaccines, symptoms, weight, temperature, glucose, and vet visits for export later."],
            sourceReferences: []
        )
    ]
}
