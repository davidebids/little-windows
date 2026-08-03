import SwiftData
import SwiftUI
import UIKit

struct EventEditorRoute: Identifiable {
    let id = UUID()
    var type: EventType
    var event: BabyEvent?
    var solidPreset: SolidFeedEditorPreset? = nil
}

private enum TodayScrollAnchor {
    case timeline
}

private struct DogPottySubtitleKey: Hashable {
    var pottyType: DogPottyType
    var accident: Bool?
}

enum TodayFeedQuickActionDetail {
    static func solidFoodSummary(for event: BabyEvent) -> String? {
        guard event.type == .feed, event.feedKind == .solid else { return nil }

        let detailNames = SolidFoodSelection.deduplicatedNames(
            event.solidFoodDetails.map(\.foodName)
        )
        let names = detailNames.isEmpty
            ? SolidFoodSelection.names(from: event.foodDescription)
            : detailNames

        guard let first = names.first else { return nil }
        switch names.count {
        case 1:
            return first
        case 2:
            return names.joined(separator: " + ")
        default:
            return "\(first) + \(names.count - 1) more"
        }
    }
}

private struct TodayRenderState {
    var profile: BabyProfile?
    var profileID: UUID?
    var scopedEvents: [BabyEvent]
    var scopedRecords: [SleepPredictionRecord]
    var scopedAppointments: [DoctorAppointment]
    var scopedAgeGuideReadStates: [AgeGuideReadState]
    var scopedPuppyGuideReadStates: [PuppyStageGuideReadState]
    var todayEvents: [BabyEvent]
    var activeEvents: [BabyEvent]
    var prediction: SleepPrediction?
    var sleepPressure: SleepPressure?
    var isDogProfile: Bool
    var currentHouseholdID: UUID?
    var visibleCareRoutines: [CareRoutine]
    var careRoutineTodayItems: [CareRoutineTodayItem]
    var suggestedRoutineTemplates: [CareRoutineTemplate]
    var currentAgeGuide: AgeGuide?
    var shouldShowAgeGuideCard: Bool
    var currentPuppyGuide: PuppyStageGuide?
    var shouldShowPuppyGuideCard: Bool
    var relevantAppointments: [DoctorAppointment]
    var runningSleepTimer: BabyEvent?
    var awakeSinceDate: Date?
    var isSleeping: Bool
    var sleepMiniPlan: SleepMiniPlan?
    var dogLastEventTitles: [EventType: String]
    var dogPottyTitles: [DogPottyType: String]
    var lastLoggedDates: [EventType: Date]
    var latestSolidFoodSummary: String?
    var dogPottyLastLoggedDates: [DogPottySubtitleKey: Date]
    var smartQuickActions: [QuickLogActionSnapshot]
    var visibleCareTypes: Set<EventType>
    var solidsProfileState: SolidsProfileState?
    var solidsAccessLevel: SolidsAccessLevel
    var nextPlannedSolidMeal: PlannedSolidMeal?
    var dueSolidAllergenProgress: SolidAllergenProgress?
    var hasSolidHistory: Bool

    func shows(_ type: EventType) -> Bool {
        visibleCareTypes.contains(type)
    }

    func hasActiveTimer(of type: EventType) -> Bool {
        activeEvents.contains { $0.type == type && $0.isTimerDraft }
    }

    func activeTimer(of type: EventType) -> BabyEvent? {
        activeEvents.first { $0.type == type && $0.isTimerDraft }
    }

    static let empty = TodayRenderState(
        profile: nil,
        profileID: nil,
        scopedEvents: [],
        scopedRecords: [],
        scopedAppointments: [],
        scopedAgeGuideReadStates: [],
        scopedPuppyGuideReadStates: [],
        todayEvents: [],
        activeEvents: [],
        prediction: nil,
        sleepPressure: nil,
        isDogProfile: false,
        currentHouseholdID: nil,
        visibleCareRoutines: [],
        careRoutineTodayItems: [],
        suggestedRoutineTemplates: [],
        currentAgeGuide: nil,
        shouldShowAgeGuideCard: false,
        currentPuppyGuide: nil,
        shouldShowPuppyGuideCard: false,
        relevantAppointments: [],
        runningSleepTimer: nil,
        awakeSinceDate: nil,
        isSleeping: false,
        sleepMiniPlan: nil,
        dogLastEventTitles: [:],
        dogPottyTitles: [:],
        lastLoggedDates: [:],
        latestSolidFoodSummary: nil,
        dogPottyLastLoggedDates: [:],
        smartQuickActions: [],
        visibleCareTypes: [],
        solidsProfileState: nil,
        solidsAccessLevel: .hidden,
        nextPlannedSolidMeal: nil,
        dueSolidAllergenProgress: nil,
        hasSolidHistory: false
    )
}

private struct TodayPreferenceRevision: Equatable {
    var selectedProfileID: UUID?
    var caregiverOne: String
    var currentCaregiverName: String
    var feedAdjustmentEnabled: Bool
    var nursingAdjustmentEnabled: Bool
    var bedtimePredictionEnabled: Bool
    var customWakeMinimum: Double
    var customWakeMaximum: Double
    var pinnedQuickActionRevision: Int
    var categoryPreferenceRevision: Int
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query private var allEvents: [BabyEvent]
    @Query(sort: \DoctorAppointment.startDate) private var appointments: [DoctorAppointment]
    @Query private var records: [SleepPredictionRecord]
    @Query(sort: \AgeGuideReadState.updatedAt) private var ageGuideReadStates: [AgeGuideReadState]
    @Query(sort: \PuppyStageGuideReadState.updatedAt) private var puppyStageGuideReadStates: [PuppyStageGuideReadState]
    @Query(sort: \CareRoutine.sortOrder) private var careRoutines: [CareRoutine]
    @Query(sort: \CareRoutineStep.sortOrder) private var careRoutineSteps: [CareRoutineStep]
    @Query(sort: \CareRoutineRun.startedAt, order: .reverse) private var careRoutineRuns: [CareRoutineRun]
    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \PlannedSolidMeal.scheduledAt) private var plannedSolidMeals: [PlannedSolidMeal]
    @Query(sort: \SolidsProfileState.updatedAt, order: .reverse) private var solidsProfileStates: [SolidsProfileState]
    @Query(sort: \SolidAllergenProgress.updatedAt, order: .reverse) private var solidAllergenProgress: [SolidAllergenProgress]

    @AppStorage("caregiverOne") private var caregiverOne = "Caregiver 1"
    @AppStorage("currentCaregiverName") private var currentCaregiverName = ""
    @AppStorage("feedAdjustmentEnabled") private var feedAdjustmentEnabled = true
    @AppStorage("nursingAdjustmentEnabled") private var nursingAdjustmentEnabled = true
    @AppStorage("bedtimePredictionEnabled") private var bedtimePredictionEnabled = true
    @AppStorage("predictionNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 10
    @AppStorage("customWakeMinimum") private var customWakeMinimum = 0.0
    @AppStorage("customWakeMaximum") private var customWakeMaximum = 0.0

    @State private var editorRoute: EventEditorRoute?
    @State private var activeTimerToEdit: BabyEvent?
    @State private var showingExplanation = false
    @State private var showingBackwardsPlanner = false
    @State private var duplicateTimerMessage: String?
    @State private var showingAlertPermissionPrompt = false
    @State private var showingPermissionDenied = false
    @State private var showingSleepChooser = false
    @State private var showingNursingChooser = false
    @State private var showingActivityChooser = false
    @State private var showingAppointments = false
    @State private var appointmentToOpen: DoctorAppointment?
    @State private var selectedMilestoneTemplate: MilestoneTemplate?
    @State private var puppyGuideToOpen: PuppyStageGuide?
    @State private var puppyGuideProfileToOpen: BabyProfile?
    @State private var showingProfileEditor = false
    @State private var showingRoutineManager = false
    @State private var routineRunRoute: CareRoutineRunRoute?
    @State private var pendingRoutineStepCompletion: PendingRoutineStepCompletion?
    @State private var eventPendingDelete: BabyEvent?
    @State private var activeSleepPlan: ActiveSleepPlan?
    @State private var pinnedQuickActionRevision = 0
    @State private var categoryPreferenceRevision = 0
    @State private var repeatFeedback: RepeatFeedback?
    @State private var showingCareCustomization = false
    @State private var cachedRenderState = TodayRenderState.empty
    @State private var hasCompletedInitialSetup = false
    @State private var renderStateRefreshTask: Task<Void, Never>?
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var profileService = ProfileService.shared

    init(profileID: UUID? = nil) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let recentCutoff = calendar.date(byAdding: .day, value: -45, to: todayStart) ?? todayStart
        let selectedProfileID = profileID ?? ProfileService.shared.selectedProfileID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        var eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { event in
                event.profileID == selectedProfileID && event.startDate >= recentCutoff
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        _allEvents = Query(eventDescriptor)

        let appointmentEnd = calendar.date(byAdding: .day, value: 3, to: todayStart)
            ?? todayStart.addingTimeInterval(3 * 24 * 60 * 60)
        let appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate<DoctorAppointment> { appointment in
                appointment.profileID == selectedProfileID &&
                    appointment.isCompleted == false &&
                    appointment.startDate >= todayStart &&
                    appointment.startDate <= appointmentEnd
            },
            sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
        )
        _appointments = Query(appointmentDescriptor)

        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.profileID == selectedProfileID &&
                    (record.actualSleepEventID == nil || record.generatedAt >= recentCutoff)
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        _records = Query(recordDescriptor)

        let routineRunCutoff = calendar.date(byAdding: .day, value: -14, to: todayStart) ?? todayStart
        let activeRoutineRunState = CareRoutineRunState.active.rawValue
        _careRoutines = Query(FetchDescriptor<CareRoutine>(
            predicate: #Predicate { routine in
                !routine.isArchived
                    && (routine.profileID == selectedProfileID || routine.profileID == nil)
            },
            sortBy: [SortDescriptor(\CareRoutine.sortOrder)]
        ))
        var scopedRoutineRunDescriptor = FetchDescriptor<CareRoutineRun>(
            predicate: #Predicate { run in
                (run.profileID == selectedProfileID || run.profileID == nil)
                    && (run.stateRawValue == activeRoutineRunState || run.startedAt >= routineRunCutoff)
            },
            sortBy: [SortDescriptor(\CareRoutineRun.startedAt, order: .reverse)]
        )
        scopedRoutineRunDescriptor.fetchLimit = 120
        _careRoutineRuns = Query(scopedRoutineRunDescriptor)

        _ageGuideReadStates = Query(FetchDescriptor<AgeGuideReadState>(
            predicate: #Predicate { $0.profileID == selectedProfileID },
            sortBy: [SortDescriptor(\AgeGuideReadState.updatedAt)]
        ))
        _puppyStageGuideReadStates = Query(FetchDescriptor<PuppyStageGuideReadState>(
            predicate: #Predicate { $0.profileID == selectedProfileID },
            sortBy: [SortDescriptor(\PuppyStageGuideReadState.updatedAt)]
        ))
        _plannedSolidMeals = Query(FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate {
                $0.profileID == selectedProfileID && $0.completedEventID == nil
            },
            sortBy: [SortDescriptor(\PlannedSolidMeal.scheduledAt)]
        ))
        _solidsProfileStates = Query(FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == selectedProfileID },
            sortBy: [SortDescriptor(\SolidsProfileState.updatedAt, order: .reverse)]
        ))
        _solidAllergenProgress = Query(FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == selectedProfileID },
            sortBy: [SortDescriptor(\SolidAllergenProgress.updatedAt, order: .reverse)]
        ))
    }
    private var profile: BabyProfile? {
        cachedRenderState.profile
    }
    private var selectedProfileID: UUID? { cachedRenderState.profileID }
    private var scopedEvents: [BabyEvent] {
        cachedRenderState.scopedEvents
    }
    private var scopedRecords: [SleepPredictionRecord] {
        cachedRenderState.scopedRecords
    }
    private var scopedAppointments: [DoctorAppointment] {
        cachedRenderState.scopedAppointments
    }
    private var currentHouseholdID: UUID? {
        cachedRenderState.currentHouseholdID
    }
    private var visibleCareRoutines: [CareRoutine] {
        cachedRenderState.visibleCareRoutines
    }
    private var activeEvents: [BabyEvent] {
        cachedRenderState.activeEvents
    }
    private var prediction: SleepPrediction? {
        cachedRenderState.prediction
    }
    private var activeCaregiverName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: caregiverOne
        )
    }
    private var predictionSettings: PredictionSettings {
        PredictionSettings(
            feedAdjustmentEnabled: feedAdjustmentEnabled,
            nursingAdjustmentEnabled: nursingAdjustmentEnabled,
            bedtimePredictionEnabled: bedtimePredictionEnabled,
            customBaselineMinimum: customWakeMinimum > 0 ? customWakeMinimum : nil,
            customBaselineMaximum: customWakeMaximum > 0 ? customWakeMaximum : nil
        )
    }
    private var runningSleepTimer: BabyEvent? {
        cachedRenderState.runningSleepTimer
    }
    private var preferenceRevision: TodayPreferenceRevision {
        TodayPreferenceRevision(
            selectedProfileID: profileService.selectedProfileID,
            caregiverOne: caregiverOne,
            currentCaregiverName: currentCaregiverName,
            feedAdjustmentEnabled: feedAdjustmentEnabled,
            nursingAdjustmentEnabled: nursingAdjustmentEnabled,
            bedtimePredictionEnabled: bedtimePredictionEnabled,
            customWakeMinimum: customWakeMinimum,
            customWakeMaximum: customWakeMaximum,
            pinnedQuickActionRevision: pinnedQuickActionRevision,
            categoryPreferenceRevision: categoryPreferenceRevision
        )
    }

    private func refreshCachedRenderState() {
        cachedRenderState = makeRenderState()
    }

    private func makeRenderState() -> TodayRenderState {
        let profile = profileService.selectedProfile(in: profiles)
        let profileID = profile?.id
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        // Every query owned by TodayView is already scoped to the selected profile.
        // Do not re-read every SwiftData property just to apply the same filter.
        let scopedEvents = allEvents
        let scopedRecords = records
        let scopedAppointments = appointments
        let scopedAgeGuideReadStates = ageGuideReadStates
        let scopedPuppyGuideReadStates = puppyStageGuideReadStates
        let currentHouseholdID = households.first?.id
        let visibleCareRoutines = CareRoutineService.visibleRoutines(
            routines: careRoutines,
            profileID: profileID,
            profileType: profile?.profileType,
            householdID: currentHouseholdID
        )
        let careRoutineTodayItems = visibleCareRoutines.prefix(3).map { routine in
            CareRoutineTodayItem(
                routine: routine,
                steps: CareRoutineService.steps(for: routine, steps: careRoutineSteps),
                activeRun: CareRoutineService.activeRun(for: routine, runs: careRoutineRuns),
                latestRun: CareRoutineService.latestRun(for: routine, runs: careRoutineRuns)
            )
        }
        let existingRoutineKinds = Set(visibleCareRoutines.compactMap(\.templateKind))
        let suggestedRoutineTemplates = CareRoutineService.templates(for: profile?.profileType).filter {
            !existingRoutineKinds.contains($0.kind)
        }
        let currentAgeGuide = profile.flatMap { AgeGuideService.shared.currentAgeGuide(for: $0) }
        let shouldShowAgeGuideCard: Bool
        if let profile, let currentAgeGuide {
            let state = scopedAgeGuideReadStates.first { $0.guideID == currentAgeGuide.id }
            shouldShowAgeGuideCard = AgeGuideService.shared.shouldShowMonthlyCard(
                profile: profile,
                readState: state
            )
        } else {
            shouldShowAgeGuideCard = false
        }
        let currentPuppyGuide = profile.flatMap { PuppyStageGuideService.shared.currentGuide(for: $0) }
        let shouldShowPuppyGuideCard: Bool
        if let profile, let currentPuppyGuide {
            let state = scopedPuppyGuideReadStates.first { $0.guideID == currentPuppyGuide.id }
            shouldShowPuppyGuideCard = PuppyStageGuideService.shared.shouldShowStageCard(
                profile: profile,
                readState: state
            )
        } else {
            shouldShowPuppyGuideCard = false
        }
        var todayEvents: [BabyEvent] = []
        var activeEvents: [BabyEvent] = []
        var sleepPressureEvents: [BabyEvent] = []
        var latestCompletedSleepEnd: Date?
        var latestStoppedDraftSleepEnd: Date?
        var dogLatestEvents: [EventType: BabyEvent] = [:]
        var latestPeeEvent: BabyEvent?
        var latestPoopEvent: BabyEvent?
        var lastLoggedDates: [EventType: Date] = [:]
        var latestSolidFoodSummary: String?
        var dogPottyLastLoggedDates: [DogPottySubtitleKey: Date] = [:]
        var hasSolidHistory = false

        for event in scopedEvents {
            if event.isTimerDraft {
                activeEvents.append(event)
                if event.isSleepBlock {
                    sleepPressureEvents.append(event)
                }
                if !event.isTimerRunning, event.updatedAt <= now, latestStoppedDraftSleepEnd.map({ event.updatedAt > $0 }) ?? true {
                    latestStoppedDraftSleepEnd = event.updatedAt
                }
                continue
            }

            let logDate = event.endDate ?? event.startDate
            if event.type == .feed, event.feedKind == .solid {
                hasSolidHistory = true
            }
            if logDate <= now, lastLoggedDates[event.type].map({ logDate > $0 }) ?? true {
                lastLoggedDates[event.type] = logDate
                if event.type == .feed {
                    latestSolidFoodSummary = TodayFeedQuickActionDetail.solidFoodSummary(for: event)
                }
            }

            if event.occursOnLocalDay(now, calendar: calendar) {
                todayEvents.append(event)
            }

            if event.isSleepBlock,
               let endDate = event.endDate,
               endDate <= now,
               latestCompletedSleepEnd.map({ endDate > $0 }) ?? true {
                latestCompletedSleepEnd = endDate
            }
            if event.isSleepBlock, event.endDate != nil {
                sleepPressureEvents.append(event)
            }

            if profile?.profileType == .dog {
                switch event.type {
                case .food, .water, .walk, .medicine:
                    if dogLatestEvents[event.type].map({ event.startDate > $0.startDate }) ?? true {
                        dogLatestEvents[event.type] = event
                    }
                case .potty:
                    let details = event.dogDetails
                    if details.pottyType == .pee || details.pottyType == .both,
                       latestPeeEvent.map({ event.startDate > $0.startDate }) ?? true {
                        latestPeeEvent = event
                    }
                    if details.pottyType == .poop || details.pottyType == .both,
                       latestPoopEvent.map({ event.startDate > $0.startDate }) ?? true {
                        latestPoopEvent = event
                    }
                    if logDate <= now {
                        if details.pottyType == .pee || details.pottyType == .both {
                            updateDogPottyLastLoggedDate(
                                logDate,
                                pottyType: .pee,
                                accident: nil,
                                values: &dogPottyLastLoggedDates
                            )
                            updateDogPottyLastLoggedDate(
                                logDate,
                                pottyType: .pee,
                                accident: details.accident,
                                values: &dogPottyLastLoggedDates
                            )
                        }
                        if details.pottyType == .poop || details.pottyType == .both {
                            updateDogPottyLastLoggedDate(
                                logDate,
                                pottyType: .poop,
                                accident: nil,
                                values: &dogPottyLastLoggedDates
                            )
                            updateDogPottyLastLoggedDate(
                                logDate,
                                pottyType: .poop,
                                accident: details.accident,
                                values: &dogPottyLastLoggedDates
                            )
                        }
                    }
                default:
                    break
                }
            }
        }
        activeEvents.sort { $0.startDate < $1.startDate }
        sleepPressureEvents.sort { $0.startDate < $1.startDate }
        let prediction = PredictionTuningService.currentPrediction(
            profile: profile,
            events: scopedEvents,
            records: scopedRecords,
            settings: predictionSettings
        )
        let sleepPressure = SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: sleepPressureEvents,
            records: scopedRecords,
            now: now,
            settings: predictionSettings
        )
        let soon = now.addingTimeInterval(3 * 24 * 60 * 60)
        let relevantAppointments = scopedAppointments
            .filter { !$0.isCompleted && $0.startDate >= todayStart && $0.startDate <= soon }
            .sorted { $0.startDate < $1.startDate }
        let runningSleepTimer = activeEvents.first {
            $0.isSleepBlock && $0.isTimerRunning
        }
        let awakeSinceDate = runningSleepTimer == nil
            ? [latestCompletedSleepEnd, latestStoppedDraftSleepEnd].compactMap { $0 }.max()
            : nil
        let sleepMiniPlan = profile.flatMap {
            SleepMiniPlanService.plan(
                profile: $0,
                events: scopedEvents,
                records: scopedRecords,
                prediction: prediction,
                now: now,
                calendar: calendar
            )
        }
        var dogLastEventTitles: [EventType: String] = [:]
        var dogPottyTitles: [DogPottyType: String] = [:]
        if profile?.profileType == .dog {
            for type in [EventType.food, .water, .walk, .medicine] {
                dogLastEventTitles[type] = dogLatestEvents[type]?.displayTitle ?? "Not logged"
            }
            dogPottyTitles[.pee] = latestPeeEvent?.displayTitle ?? "Not logged"
            dogPottyTitles[.poop] = latestPoopEvent?.displayTitle ?? "Not logged"
        }
        _ = pinnedQuickActionRevision
        _ = categoryPreferenceRevision
        let visibleCareTypes = Set(CareCategoryPreferenceStore.visibleTypes(
            for: profile?.profileType ?? .child,
            profileID: profileID
        ))
        let pinnedQuickActionIDs = QuickLogActionPreferenceStore.pinnedActionIDs(profileID: profileID)
        let smartQuickActions = WidgetSnapshotService.makeQuickActions(
            profileID: profileID,
            profileType: profile?.profileType ?? .child,
            events: scopedEvents,
            pinnedActionIDs: pinnedQuickActionIDs,
            now: now
        )
        let solidsProfileState = profileID.flatMap { targetProfileID in
            solidsProfileStates.first { $0.profileID == targetProfileID }
        }
        let solidsAccessLevel = profile.map {
            SolidsTrackingService.accessLevel(
                for: $0,
                events: scopedEvents,
                state: solidsProfileState
            )
        } ?? .hidden
        let endOfToday = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: todayStart
        ) ?? now
        let nextPlannedSolidMeal = profileID.flatMap { targetProfileID in
            plannedSolidMeals.first {
                $0.profileID == targetProfileID && !$0.isCompleted && $0.scheduledAt <= endOfToday
            }
        }
        let dueSolidAllergenProgress = profileID.flatMap { targetProfileID in
            solidAllergenProgress
                .lazy
                .filter {
                    $0.profileID == targetProfileID &&
                        $0.nextExposureDueAt.map { $0 <= endOfToday } == true &&
                        $0.status != .suspectedReaction &&
                        $0.status != .avoidPendingAdvice
                }
                .min {
                    ($0.nextExposureDueAt ?? .distantFuture) < ($1.nextExposureDueAt ?? .distantFuture)
                }
        }
        return TodayRenderState(
            profile: profile,
            profileID: profileID,
            scopedEvents: scopedEvents,
            scopedRecords: scopedRecords,
            scopedAppointments: scopedAppointments,
            scopedAgeGuideReadStates: scopedAgeGuideReadStates,
            scopedPuppyGuideReadStates: scopedPuppyGuideReadStates,
            todayEvents: todayEvents,
            activeEvents: activeEvents,
            prediction: prediction,
            sleepPressure: sleepPressure,
            isDogProfile: profile?.profileType == .dog,
            currentHouseholdID: currentHouseholdID,
            visibleCareRoutines: visibleCareRoutines,
            careRoutineTodayItems: careRoutineTodayItems,
            suggestedRoutineTemplates: suggestedRoutineTemplates,
            currentAgeGuide: currentAgeGuide,
            shouldShowAgeGuideCard: shouldShowAgeGuideCard,
            currentPuppyGuide: currentPuppyGuide,
            shouldShowPuppyGuideCard: shouldShowPuppyGuideCard,
            relevantAppointments: relevantAppointments,
            runningSleepTimer: runningSleepTimer,
            awakeSinceDate: awakeSinceDate,
            isSleeping: runningSleepTimer != nil,
            sleepMiniPlan: profile?.profileType == .child ? sleepMiniPlan : nil,
            dogLastEventTitles: dogLastEventTitles,
            dogPottyTitles: dogPottyTitles,
            lastLoggedDates: lastLoggedDates,
            latestSolidFoodSummary: latestSolidFoodSummary,
            dogPottyLastLoggedDates: dogPottyLastLoggedDates,
            smartQuickActions: smartQuickActions,
            visibleCareTypes: visibleCareTypes,
            solidsProfileState: solidsProfileState,
            solidsAccessLevel: solidsAccessLevel,
            nextPlannedSolidMeal: nextPlannedSolidMeal,
            dueSolidAllergenProgress: dueSolidAllergenProgress,
            hasSolidHistory: hasSolidHistory
        )
    }

    private func updateDogPottyLastLoggedDate(
        _ date: Date,
        pottyType: DogPottyType,
        accident: Bool?,
        values: inout [DogPottySubtitleKey: Date]
    ) {
        let key = DogPottySubtitleKey(pottyType: pottyType, accident: accident)
        if values[key].map({ date > $0 }) ?? true {
            values[key] = date
        }
    }

    var body: some View {
        let state = cachedRenderState
        let todayEvents = state.todayEvents
        let activeEvents = state.activeEvents
        let prediction = state.prediction
        let profile = state.profile

        let listContent = ScrollViewReader { scrollProxy in
            List {
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Good \(greeting), \(activeCaregiverName)")
                                .font(.title2.bold())
                            if let profile {
                                Text(profile.profileType == .dog
                                    ? "\(profile.name) · \(profile.profileSubtitle)"
                                    : "\(profile.name) is \(DateFormatting.age(from: profile.birthDate))"
                                )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let profile {
                            Button {
                                withAnimation(.snappy) {
                                    scrollProxy.scrollTo(TodayScrollAnchor.timeline, anchor: .top)
                                }
                            } label: {
                                VStack(spacing: 3) {
                                    Text("\(todayEvents.count)")
                                        .font(.title3.bold())
                                        .monospacedDigit()
                                    Text("logs today")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(todayEvents.count) logs today for \(profile.name)")
                            .accessibilityHint("Jumps to today's timeline")
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                }

                if profile == nil {
                    noProfileSection
                } else {
                    activeTimersSection(activeEvents)

                    solidsTodaySection(state)

                    if state.isDogProfile {
                        dogTodaySummarySection(state)
                        puppyStageGuideSection(state)
                    }

                    if !state.isDogProfile {
                        Section {
                            PredictionCard(
                                prediction: prediction,
                                babyName: profile?.name ?? "Baby",
                                awakeSinceDate: state.awakeSinceDate,
                                sleepPressure: state.sleepPressure,
                                alertStatusText: notificationManager.statusText(
                                    prediction: prediction,
                                    settings: .current,
                                    isSleeping: state.isSleeping
                                ),
                                alertsEnabled: notificationsEnabled,
                                toggleAlerts: toggleLittleWindowAlerts,
                                showBackwardsPlanner: { showingBackwardsPlanner = true },
                                showExplanation: { showingExplanation = true }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    if state.isDogProfile {
                        dogQuickActionsSection(state)
                    } else {
                        childQuickActionsSection(state)
                    }

                    sleepMiniPlanSection(state)

                    careRoutinesSection(state)

                    Section {
                        if todayEvents.isEmpty {
                            ContentUnavailableView(
                                "No events yet",
                                systemImage: "clock",
                                description: Text("Use a quick action to start \(profile?.name ?? "the profile")'s day.")
                            )
                        } else {
                            ForEach(todayEvents) { event in
                                Button {
                                    if event.isTimerDraft {
                                        activeTimerToEdit = event
                                    } else {
                                        editorRoute = EventEditorRoute(type: event.type, event: event)
                                    }
                                } label: {
                                    EventRow(event: event)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        eventPendingDelete = event
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        AppSectionHeader(
                            title: "Today's timeline",
                            subtitle: todayEvents.isEmpty ? nil : "\(todayEvents.count) events"
                        )
                    }
                    .id(TodayScrollAnchor.timeline)

                    if !state.isDogProfile {
                        monthlyAgeGuideSection(state)
                    }

                    appointmentsSection(state)
                }
            }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
        }

        listContent
        .navigationTitle("Today")
        .navigationDestination(for: FoodRoute.self) { route in
            todaySolidsDestination(route, state: state)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    deepLinkRouter.presentSettings()
                } label: {
                    if let profile {
                        ProfileAvatarView(profile: profile, size: 32)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(profile?.name ?? "Profile") settings")
                .accessibilityHint("Opens settings where you can switch profiles")
            }
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                EventEditorView(
                    type: route.type,
                    event: route.event,
                    solidPreset: route.solidPreset
                ) { savedEvent in
                    Task {
                        await eventChanged(savedEvent, solidPreset: route.solidPreset)
                        completePendingRoutineStepIfNeeded()
                    }
                }
            }
        }
        .sheet(isPresented: $showingRoutineManager) {
            NavigationStack {
                CareRoutineManagerView(
                    profileType: profile?.profileType,
                    routines: state.visibleCareRoutines,
                    steps: careRoutineSteps,
                    runs: careRoutineRuns,
                    templates: state.suggestedRoutineTemplates,
                    addTemplate: addRoutineTemplate,
                    createRoutine: createCustomRoutine,
                    updateRoutine: updateCustomRoutine,
                    duplicateRoutine: duplicateRoutine,
                    moveRoutines: moveRoutines,
                    startRoutine: startRoutine,
                    archiveRoutine: archiveRoutine,
                    toggleReminder: toggleRoutineReminder,
                    openRun: openRoutineRun
                )
            }
        }
        .sheet(item: $routineRunRoute) { route in
            if let routine = careRoutines.first(where: { $0.id == route.routineID }),
               let run = careRoutineRuns.first(where: { $0.id == route.runID }) {
                NavigationStack {
                    CareRoutineRunView(
                        routine: routine,
                        steps: CareRoutineService.steps(for: routine, steps: careRoutineSteps),
                        run: run,
                        perform: { performRoutineStep($0, routine: routine, run: run) },
                        skip: { skipRoutineStep($0, routine: routine, run: run) },
                        finish: { finishRoutineRun(run, routine: routine) },
                        cancel: { cancelRoutineRun(run) },
                        canPerform: { step in
                            step.action != .startTimer
                                || state.activeTimer(of: step.eventType ?? .custom) == nil
                        }
                    )
                }
            }
        }
        .sheet(item: $activeTimerToEdit) { event in
            NavigationStack {
                activeTimerEditor(for: event)
            }
        }
        .sheet(isPresented: $showingAppointments) {
            NavigationStack {
                AppointmentsListView()
            }
        }
        .sheet(item: $appointmentToOpen) { appointment in
            NavigationStack {
                AppointmentDetailView(appointment: appointment)
            }
        }
        .sheet(item: $selectedMilestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template)
            }
        }
        .sheet(item: $puppyGuideToOpen) { guide in
            NavigationStack {
                PuppyStageGuideDetailView(guide: guide, profile: puppyGuideProfileToOpen ?? profile)
            }
        }
        .sheet(isPresented: $showingProfileEditor) {
            NavigationStack {
                ProfileEditorView()
            }
        }
        .sheet(isPresented: $showingCareCustomization) {
            NavigationStack {
                CareCategoryCustomizationView(
                    profileID: state.profileID,
                    profileType: profile?.profileType ?? .child
                ) {
                    categoryPreferenceRevision += 1
                    refreshWidgetSnapshot()
                }
            }
        }
        .sheet(isPresented: $showingExplanation) {
            NavigationStack {
                PredictionExplanationView(
                    prediction: prediction,
                    sleepPressure: state.sleepPressure
                )
            }
        }
        .sheet(isPresented: $showingBackwardsPlanner) {
            if let profile = state.profile {
                NavigationStack {
                    BackwardsSleepPlanView(
                        profile: profile,
                        events: state.scopedEvents,
                        settings: predictionSettings,
                        activePlan: activeSleepPlan,
                        activatePlan: activateSleepPlan,
                        deactivatePlan: deactivateSleepPlan
                    )
                }
            }
        }
        .appActionSheet(
            isPresented: Binding(
                get: { eventPendingDelete != nil },
                set: { if !$0 { eventPendingDelete = nil } }
            ),
            title: "Delete event?",
            message: eventPendingDelete.map {
                "This permanently removes the \($0.type.displayName.lowercased()) event from Today and History."
            },
            systemImage: "trash.fill",
            tint: .red,
            options: deleteEventOptions
        )
        .modifier(
            SleepKindChooser(
                isPresented: $showingSleepChooser,
                timerIsActive: state.hasActiveTimer(of: .sleep),
                startSleep: { kind in
                    startTimer(.sleep, sleepKind: kind)
                }
            )
        )
        .alert(
            "Timer already running",
            isPresented: Binding(
                get: { duplicateTimerMessage != nil },
                set: { if !$0 { duplicateTimerMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateTimerMessage ?? "")
        }
        .appActionSheet(
            isPresented: $showingNursingChooser,
            title: "Start Nursing",
            message: "Choose the starting side. You can switch sides while the timer runs.",
            systemImage: "figure.and.child.holdinghands",
            tint: .pink,
            options: [
                AppActionSheetOption(
                    title: "Left Side",
                    subtitle: state.hasActiveTimer(of: .nursing)
                        ? "A nursing timer is already active."
                        : "Begin tracking time on the left side.",
                    systemImage: "l.circle.fill",
                    tint: .pink,
                    isEnabled: !state.hasActiveTimer(of: .nursing)
                ) {
                    startNursing(.left)
                },
                AppActionSheetOption(
                    title: "Right Side",
                    subtitle: state.hasActiveTimer(of: .nursing)
                        ? "A nursing timer is already active."
                        : "Begin tracking time on the right side.",
                    systemImage: "r.circle.fill",
                    tint: .pink,
                    isEnabled: !state.hasActiveTimer(of: .nursing)
                ) {
                    startNursing(.right)
                }
            ]
        )
        .appActionSheet(
            isPresented: $showingActivityChooser,
            title: "Start Activity",
            message: "Pick a common activity timer or open a custom activity entry.",
            systemImage: "figure.play",
            tint: .green,
            options: showingActivityChooser ? activityOptions(state: state) : []
        )
        .confirmationDialog(
            "Turn on Little Window Alerts?",
            isPresented: $showingAlertPermissionPrompt,
            titleVisibility: .visible
        ) {
            Button("Allow Notifications") {
                Task { await enableLittleWindowAlerts() }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Little Windows can remind you before \(profile?.name ?? "your baby")'s next likely nap or bedtime window.")
        }
        .alert("Notifications are turned off", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can allow Little Window Alerts in iOS Settings whenever you're ready.")
        }
        .overlay(alignment: .bottom) {
            if let repeatFeedback {
                RepeatFeedbackBanner(feedback: repeatFeedback)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: deepLinkRouter.pendingAction) { _, _ in
            handlePendingDeepLink()
        }
        .onChange(of: preferenceRevision) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: deepLinkRouter.pendingProfileID) { _, _ in
            handlePendingProfileSwitch()
            refreshActiveSleepPlan()
        }
        .onChange(of: deepLinkRouter.pendingAppointmentCommand) { _, _ in
            handlePendingAppointmentDeepLink()
        }
        .onChange(of: deepLinkRouter.pendingPuppyGuideCommand) { _, _ in
            handlePendingPuppyGuideDeepLink()
        }
        .onChange(of: deepLinkRouter.pendingRoutineCommand) { _, _ in
            handlePendingRoutineDeepLink()
        }
        .onChange(of: deepLinkRouter.isDataReady) { _, ready in
            if ready {
                handlePendingProfileSwitch()
                handlePendingDeepLink()
                handlePendingAppointmentDeepLink()
                handlePendingPuppyGuideDeepLink()
                handlePendingRoutineDeepLink()
            }
        }
        .task {
            guard !hasCompletedInitialSetup else { return }
            hasCompletedInitialSetup = true
            _ = HouseholdService.ensureDefaultHousehold(context: modelContext)
            _ = profileService.ensureSelection(in: profiles)
            refreshCachedRenderState()
            refreshActiveSleepPlan()
            handlePendingProfileSwitch()
            handlePendingDeepLink()
            handlePendingAppointmentDeepLink()
            handlePendingPuppyGuideDeepLink()
            handlePendingRoutineDeepLink()
            await AppInteractionMonitor.waitUntilIdle()
            guard !Task.isCancelled else {
                hasCompletedInitialSetup = false
                return
            }
            await syncActiveSleepPlanWakeAlert()
        }
        .task(id: state.profileID) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                await AppInteractionMonitor.waitUntilIdle()
                guard !Task.isCancelled else { return }
                refreshCachedRenderState()
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        default: "evening"
        }
    }

    private var noProfileSection: some View {
        Section {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("Create a profile")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)

                    Text("Add a child or dog profile to start logging care, or import an existing backup from Settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingProfileEditor = true
                } label: {
                    Label("Add Profile", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func sleepMiniPlanSection(_ state: TodayRenderState) -> some View {
        if !state.isDogProfile, let plan = state.sleepMiniPlan {
            Section {
                SleepMiniPlanCard(plan: plan) {
                    showingBackwardsPlanner = true
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "Sleep day ahead", subtitle: plan.horizon)
            }
        }
    }

    @ViewBuilder
    private func monthlyAgeGuideSection(_ state: TodayRenderState) -> some View {
        if state.shouldShowAgeGuideCard, let profile = state.profile, let guide = state.currentAgeGuide {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    AgeGuideFeatureCard(
                        guide: guide,
                        babyName: profile.name,
                        isCurrent: true,
                        isUnread: !state.scopedAgeGuideReadStates.contains {
                            $0.guideID == guide.id && $0.firstOpenedAt != nil
                        },
                        reachedDate: AgeGuideService.shared.monthlyBirthdayDate(
                            for: profile,
                            ageMonth: guide.ageMonth
                        ),
                        onDismiss: {
                            AgeGuideService.shared.markMonthlyCardDismissed(
                                guide,
                                in: modelContext,
                                readStates: state.scopedAgeGuideReadStates,
                                profileID: state.profileID
                            )
                        },
                        onAddMilestone: {
                            selectedMilestoneTemplate = guide.milestonePrompts.first?.milestoneTemplate
                        }
                    )
                    NavigationLink {
                        AgeGuideDetailView(guide: guide)
                    } label: {
                        Label("Read development guide", systemImage: "book.pages.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MilestonePalette.accent)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "This Month", subtitle: guide.ageLabel)
            }
        }
    }

    @ViewBuilder
    private func puppyStageGuideSection(_ state: TodayRenderState) -> some View {
        if state.shouldShowPuppyGuideCard, let profile = state.profile, let guide = state.currentPuppyGuide {
            Section {
                PuppyStageGuideCard(
                    profile: profile,
                    guide: guide,
                    onDismiss: {
                        PuppyStageGuideService.shared.markStageCardDismissed(
                            guide,
                            in: modelContext,
                            readStates: state.scopedPuppyGuideReadStates,
                            profileID: state.profileID
                        )
                    },
                    onRead: {
                        puppyGuideToOpen = guide
                    },
                    onAddMilestone: {
                        selectedMilestoneTemplate = guide.milestonePrompts.first.map {
                            MilestoneTemplate(title: $0.title, category: $0.suggestedCategory)
                        }
                    },
                    onLogTraining: {
                        startTimer(.training)
                    },
                    isTrainingTimerActive: state.hasActiveTimer(of: .training)
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "Puppy Stage Guides", subtitle: guide.title)
            }
        }
    }

    @ViewBuilder
    private func solidsTodaySection(_ state: TodayRenderState) -> some View {
        if let profile = state.profile, profile.profileType == .child {
            let calendar = Calendar.current
            let accessLevel = state.solidsAccessLevel
            let nextPlan = state.nextPlannedSolidMeal
            let dueAllergen = state.dueSolidAllergenProgress
            let hasSolidHistory = state.hasSolidHistory

            if accessLevel == .readinessPreview {
                Section {
                    NavigationLink(value: FoodRoute.solidsHome) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Starting solids soon")
                                    .font(.headline)
                                Text("Review readiness signs and age-appropriate preparation before the first meal.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "carrot.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.solids-readiness")
                }
            } else if accessLevel == .full,
                      nextPlan != nil || dueAllergen != nil || !hasSolidHistory {
                Section {
                    if let nextPlan {
                        Button {
                            deepLinkRouter.openSolids(
                                .plannedSolidMeal(nextPlan.id),
                                profileID: profile.id,
                                returningTo: .today
                            )
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(nextPlan.title)
                                        .font(.headline)
                                    Text(nextPlan.scheduledAt < calendar.startOfDay(for: Date())
                                        ? "Planned meal is overdue"
                                        : "Planned for \(nextPlan.scheduledAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.solids.next-plan")
                    }

                    if let dueAllergen,
                       let allergen = SolidsAllergen(rawValue: dueAllergen.allergenID) {
                        Button {
                            deepLinkRouter.openSolids(
                                .solidAllergen(allergen.rawValue),
                                profileID: profile.id,
                                returningTo: .today
                            )
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Continue \(allergen.displayName)")
                                        .font(.headline)
                                    Text("A follow-up exposure is due. Review the introduction steps before serving.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "checklist")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.solids.due-allergen")
                    }

                    if nextPlan == nil, dueAllergen == nil, !hasSolidHistory {
                        Button {
                            deepLinkRouter.openSolids(
                                .solidsGuided,
                                profileID: profile.id,
                                returningTo: .today
                            )
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Plan the first solids meal")
                                        .font(.headline)
                                    Text("Build a paced first-100-food path with an age-aware first week.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "fork.knife.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.solids.guided")
                    }
                } header: {
                    AppSectionHeader(title: "Solids")
                }
            }
        }
    }

    @ViewBuilder
    private func todaySolidsDestination(
        _ route: FoodRoute,
        state: TodayRenderState
    ) -> some View {
        if route == .solidsHome,
           let profile = state.profile,
           profile.profileType == .child {
            let profileState = state.solidsProfileState
            let accessLevel = state.solidsAccessLevel
            if accessLevel != .hidden {
                SolidsHomeView(
                    profile: profile,
                    accessLevel: accessLevel,
                    events: state.scopedEvents,
                    eventItems: [],
                    progress: [],
                    plans: plannedSolidMeals,
                    profileState: profileState,
                    open: openSolidsInCare
                )
            } else {
                todaySolidsUnavailable
            }
        } else {
            todaySolidsUnavailable
        }
    }

    private var todaySolidsUnavailable: some View {
        ContentUnavailableView(
            "Unavailable",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Solids is not available for the selected profile.")
        )
    }

    private func openSolidsInCare(_ route: FoodRoute) {
        guard let command = solidsCommand(for: route) else { return }
        deepLinkRouter.openSolids(
            command,
            profileID: cachedRenderState.profileID,
            returningTo: .today
        )
    }

    private func solidsCommand(for route: FoodRoute) -> FoodRouteCommand? {
        switch route {
        case .solidsHome: .solids
        case .solidsDatabase: .solidsDatabase
        case .solidsGuided: .solidsGuided
        case .solidFood(let id): .solidFood(id)
        case .customSolidFood(let id): .customSolidFood(id)
        case .solidsPlan: .solidsPlan
        case .plannedSolidMeal(let id): .plannedSolidMeal(id)
        case .solidsTracker: .solidsTracker
        case .solidMeal(let id): .solidMeal(id)
        case .solidsAllergens: .solidsAllergens
        case .solidAllergen(let id): .solidAllergen(id)
        case .solidsRecipes: .solidsRecipes
        case .solidsRecipe(let id): .solidsRecipe(id)
        case .solidFoodHistory, .todoList, .shoppingList, .shoppingMode,
             .packingTrip, .itineraryItem, .inventoryItem, .mealPrepItem, .returnRequest,
             .store, .reminders:
            nil
        }
    }

    private func childQuickActionsSection(_ state: TodayRenderState) -> some View {
        Section {
            VStack(spacing: 14) {
                smartQuickActionsRow(state.smartQuickActions.filter { $0.id != "sleep" })

                if state.shows(.sleep) {
                    Button {
                        if let activeSleep = state.activeTimer(of: .sleep) {
                            activeTimerToEdit = activeSleep
                        } else {
                            showingSleepChooser = true
                        }
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "moon.stars.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.hasActiveTimer(of: .sleep) ? "Sleep timer active" : "Start sleep")
                                    .font(.headline)
                                Text(
                                    state.hasActiveTimer(of: .sleep)
                                        ? "Tap to manage the running timer"
                                        : lastEventSubtitle(.sleep, state: state)
                                )
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            Spacer()
                            Image(systemName: state.hasActiveTimer(of: .sleep) ? "timer" : "play.fill")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.14), in: Circle())
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(
                            LinearGradient(
                                colors: [.indigo, Color(red: 0.43, green: 0.34, blue: 0.84)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 19)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.start-sleep")
                    .accessibilityHint(
                        state.hasActiveTimer(of: .sleep)
                            ? "Open the active sleep timer"
                            : "Choose a sleep type and start the timer"
                    )
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 14
                ) {
                    if state.shows(.feed) {
                        QuickActionButton(
                            title: "Feed",
                            detail: state.latestSolidFoodSummary.map { "Solid · \($0)" },
                            subtitle: lastEventSubtitle(.feed, state: state),
                            icon: "waterbottle.fill",
                            color: .orange
                        ) {
                            editorRoute = EventEditorRoute(type: .feed)
                        }
                    }
                    if state.shows(.nursing) {
                        QuickActionButton(
                            title: "Nursing",
                            subtitle: state.hasActiveTimer(of: .nursing)
                                ? "Timer active"
                                : lastEventSubtitle(.nursing, state: state),
                            icon: "figure.and.child.holdinghands",
                            color: .pink,
                            isEnabled: !state.hasActiveTimer(of: .nursing)
                        ) {
                            showingNursingChooser = true
                        }
                    }
                    if state.shows(.pumping) {
                        QuickActionButton(
                            title: "Pumping",
                            subtitle: state.hasActiveTimer(of: .pumping)
                                ? "Timer active"
                                : lastEventSubtitle(.pumping, state: state),
                            icon: "drop.circle.fill",
                            color: .cyan,
                            isEnabled: !state.hasActiveTimer(of: .pumping)
                        ) {
                            startTimer(.pumping)
                        }
                    }
                    if state.shows(.diaper) {
                        QuickActionButton(
                            title: "Diaper",
                            subtitle: lastEventSubtitle(.diaper, state: state),
                            icon: "drop.fill",
                            color: .teal
                        ) {
                            editorRoute = EventEditorRoute(type: .diaper)
                        }
                    }
                    if state.shows(.potty) {
                        QuickActionButton(
                            title: "Potty",
                            subtitle: lastEventSubtitle(.potty, state: state),
                            icon: "figure.child",
                            color: .teal
                        ) {
                            editorRoute = EventEditorRoute(type: .potty)
                        }
                    }
                    if state.shows(.activity) {
                        QuickActionButton(
                            title: "Activity",
                            subtitle: state.hasActiveTimer(of: .activity)
                                ? "Timer active"
                                : lastEventSubtitle(.activity, state: state),
                            icon: "figure.play",
                            color: .green,
                            isEnabled: !state.hasActiveTimer(of: .activity)
                        ) {
                            showingActivityChooser = true
                        }
                    }
                    if state.shows(.medicine) {
                        QuickActionButton(
                            title: "Medicine",
                            subtitle: lastEventSubtitle(.medicine, state: state),
                            icon: "cross.case.fill",
                            color: .red
                        ) {
                            editorRoute = EventEditorRoute(type: .medicine)
                        }
                    }
                    if state.shows(.temperature) {
                        QuickActionButton(
                            title: "Temperature",
                            subtitle: lastEventSubtitle(.temperature, state: state),
                            icon: "thermometer.medium",
                            color: .red
                        ) {
                            editorRoute = EventEditorRoute(type: .temperature)
                        }
                    }
                    if state.shows(.growth) {
                        QuickActionButton(
                            title: "Growth",
                            subtitle: lastEventSubtitle(.growth, state: state),
                            icon: "ruler.fill",
                            color: .mint
                        ) {
                            editorRoute = EventEditorRoute(type: .growth)
                        }
                    }
                    QuickActionButton(title: "Visits", icon: "stethoscope", color: .indigo) {
                        showingAppointments = true
                    }
                    if state.shows(.custom) {
                        QuickActionButton(
                            title: "Custom",
                            subtitle: lastEventSubtitle(.custom, state: state),
                            icon: "sparkles",
                            color: .purple
                        ) {
                            editorRoute = EventEditorRoute(type: .custom)
                        }
                    }
                }
                Button {
                    showingCareCustomization = true
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Log something")
        } footer: {
            Text("Choose the sleep or activity kind, or use another action to log quickly.")
                .font(.caption)
        }
    }

    private func dogQuickActionsSection(_ state: TodayRenderState) -> some View {
        Section {
            VStack(spacing: 14) {
                smartQuickActionsRow(state.smartQuickActions)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 14
                ) {
                    if state.shows(.food) {
                        QuickActionButton(
                            title: "Food",
                            subtitle: lastEventSubtitle(.food, state: state),
                            icon: "fork.knife",
                            color: .orange
                        ) {
                            editorRoute = EventEditorRoute(type: .food)
                        }
                    }
                    if state.shows(.water) {
                        QuickActionButton(
                            title: "Water",
                            subtitle: lastEventSubtitle(.water, state: state),
                            icon: "drop.fill",
                            color: .cyan
                        ) {
                            editorRoute = EventEditorRoute(type: .water)
                        }
                    }
                    if state.shows(.walk) {
                        QuickActionButton(
                            title: "Start Walk",
                            subtitle: state.hasActiveTimer(of: .walk)
                                ? "Timer active"
                                : lastEventSubtitle(.walk, state: state),
                            icon: "figure.walk",
                            color: .green,
                            isEnabled: !state.hasActiveTimer(of: .walk)
                        ) {
                            startTimer(.walk)
                        }
                    }
                    if state.shows(.potty) {
                        QuickActionButton(
                            title: "Pee",
                            subtitle: dogPottySubtitle(.pee, state: state),
                            icon: "pawprint.fill",
                            color: .teal
                        ) {
                            logDogPotty(.pee, accident: false)
                        }
                    }
                    if state.shows(.potty) {
                        QuickActionButton(
                            title: "Poop",
                            subtitle: dogPottySubtitle(.poop, state: state),
                            icon: "pawprint.circle.fill",
                            color: .teal
                        ) {
                            logDogPotty(.poop, accident: false)
                        }
                    }
                    if state.shows(.potty) {
                        QuickActionButton(
                            title: "Accident",
                            subtitle: dogPottySubtitle(.pee, state: state, accident: true),
                            icon: "exclamationmark.triangle.fill",
                            color: .orange
                        ) {
                            logDogPotty(.pee, accident: true)
                        }
                    }
                    if state.shows(.rest) {
                        QuickActionButton(
                            title: "Rest",
                            subtitle: state.hasActiveTimer(of: .rest)
                                ? "Timer active"
                                : lastEventSubtitle(.rest, state: state),
                            icon: "bed.double.fill",
                            color: .indigo,
                            isEnabled: !state.hasActiveTimer(of: .rest)
                        ) {
                            startTimer(.rest)
                        }
                    }
                    if state.shows(.training) {
                        QuickActionButton(
                            title: "Training",
                            subtitle: state.hasActiveTimer(of: .training)
                                ? "Timer active"
                                : lastEventSubtitle(.training, state: state),
                            icon: "graduationcap.fill",
                            color: .purple,
                            isEnabled: !state.hasActiveTimer(of: .training)
                        ) {
                            startTimer(.training)
                        }
                    }
                    if state.shows(.medicine) {
                        QuickActionButton(
                            title: "Medicine",
                            subtitle: lastEventSubtitle(.medicine, state: state),
                            icon: "cross.case.fill",
                            color: .red
                        ) {
                            editorRoute = EventEditorRoute(type: .medicine)
                        }
                    }
                }
                Button {
                    showingCareCustomization = true
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Log something")
        } footer: {
            Text("Walk, training, and rest timers use the same Live Activity and widget controls. No GPS route tracking or location permission is used.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func smartQuickActionsRow(_ actions: [QuickLogActionSnapshot]) -> some View {
        let visibleActions = Array(actions.prefix(4))
        if !visibleActions.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Smart picks")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleActions) { action in
                            let tint = smartQuickActionColor(action.tintName)
                            ZStack(alignment: .topTrailing) {
                                HStack(spacing: 8) {
                                    Image(systemName: action.systemImage)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(tint, in: Circle())
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(action.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.82)
                                        if let subtitle = action.subtitle {
                                            Text(subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.82)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.trailing, 12)
                                .frame(width: 136, height: 48)
                                .background(
                                    Color.primary.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                                .onTapGesture {
                                    performSmartQuickAction(action)
                                }

                                Button {
                                    togglePinnedQuickAction(action)
                                } label: {
                                    Image(systemName: action.resolvedIsPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(action.resolvedIsPinned ? tint : .secondary)
                                        .frame(width: 28, height: 28)
                                        .background(.thinMaterial, in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    Text(action.resolvedIsPinned ? "Unpin \(action.title)" : "Pin \(action.title)")
                                )
                                .zIndex(1)
                            }
                            .frame(width: 136, height: 48)
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
            }
        }
    }

    private func dogTodaySummarySection(_ state: TodayRenderState) -> some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                DogSummaryCard(title: "Last food", value: dogLastEventTitle(.food, state: state), icon: "fork.knife", color: .orange)
                DogSummaryCard(title: "Last water", value: dogLastEventTitle(.water, state: state), icon: "drop.fill", color: .cyan)
                DogSummaryCard(title: "Last pee", value: dogPottyTitle(.pee, state: state), icon: "pawprint.fill", color: .teal)
                DogSummaryCard(title: "Last poop", value: dogPottyTitle(.poop, state: state), icon: "pawprint.circle.fill", color: .teal)
                DogSummaryCard(title: "Last walk", value: dogLastEventTitle(.walk, state: state), icon: "figure.walk", color: .green)
                DogSummaryCard(title: "Medicine", value: dogLastEventTitle(.medicine, state: state), icon: "cross.case.fill", color: .red)
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "\(state.profile?.name ?? "Dog") today", subtitle: "Quick snapshot")
        }
    }

    @ViewBuilder
    private func activeTimersSection(_ events: [BabyEvent]) -> some View {
        if !events.isEmpty {
            Section {
                ForEach(events) { event in
                    activeTimerCard(for: event)
                }
            } header: {
                AppSectionHeader(
                    title: "Timers",
                    subtitle: "\(events.count) draft\(events.count == 1 ? "" : "s")"
                )
            }
        }
    }

    private func careRoutinesSection(_ state: TodayRenderState) -> some View {
        CareRoutinesTodayCard(
            items: state.careRoutineTodayItems,
            routineCount: state.visibleCareRoutines.count,
            templates: state.suggestedRoutineTemplates,
            addTemplate: addRoutineTemplate,
            startRoutine: startRoutine,
            archiveRoutine: archiveRoutine,
            cancelRun: cancelRoutineRun,
            openRun: openRoutineRun,
            manage: { showingRoutineManager = true }
        )
    }

    @ViewBuilder
    private func appointmentsSection(_ state: TodayRenderState) -> some View {
        if !state.relevantAppointments.isEmpty {
            Section {
                ForEach(state.relevantAppointments.prefix(2)) { appointment in
                    Button {
                        appointmentToOpen = appointment
                    } label: {
                        AppointmentCard(appointment: appointment)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        Button {
                            markCompleted(appointment)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Appointments")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        showingAppointments = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("View all")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all appointments")
                }
                .textCase(nil)
                .padding(.horizontal, 4)
            }
        }
    }

    private func activeTimerCard(for event: BabyEvent) -> some View {
        ActiveTimerCard(
            event: event,
            planWakeAlert: wakeAlert(for: event),
            edit: { activeTimerToEdit = event },
            toggleRunning: {
                event.isTimerRunning ? stop(event) : resume(event)
            },
            save: { save(event) },
            switchNursingSide: nursingSideSwitcher(for: event),
            setNursingSide: nursingSideSetter(for: event)
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func activeTimerEditor(for event: BabyEvent) -> some View {
        ActiveTimerEditorView(
            event: event,
            adjustStart: { date in adjustStart(of: event, to: date) },
            stop: { stop(event) },
            resume: { resume(event) },
            reset: { reset(event) },
            save: { endDate in save(event, endDate: endDate) },
            discard: { delete(event) },
            setStartTimeZone: { setStartTimeZone($0, for: event) },
            setEndTimeZone: { setEndTimeZone($0, for: event) },
            switchNursingSide: nursingSideSwitcher(for: event),
            setNursingSide: nursingSideSetter(for: event)
        )
    }

    private func nursingSideSwitcher(for event: BabyEvent) -> (() -> Void)? {
        guard event.type == .nursing else { return nil }
        return { switchNursingSide(event) }
    }

    private func nursingSideSetter(for event: BabyEvent) -> ((NursingSide) -> Void)? {
        guard event.type == .nursing else { return nil }
        return { side in setNursingSide(side, for: event) }
    }

    @discardableResult
    private func startTimer(
        _ type: EventType,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        activityType: ActivityType? = nil,
        presentsEditor: Bool = true
    ) -> BabyEvent? {
        if let existingTimer = activeTimer(of: type) {
            if presentsEditor {
                activeTimerToEdit = existingTimer
            }
            return nil
        }
        let created = EventMutationService.startTimer(
            type: type,
            nursingSide: nursingSide,
            sleepKind: sleepKind,
            activityType: activityType,
            caregiverName: activeCaregiverName,
            events: scopedEvents,
            profileID: selectedProfileID,
            profileType: profile?.profileType,
            context: modelContext
        )
        if let created {
            if presentsEditor {
                activeTimerToEdit = created
            }
            Task {
                await eventChanged(
                    created,
                    refreshPrediction: false,
                    waitForSystemIntegrations: true
                )
                await syncActiveSleepPlanWakeAlert(
                    for: created.isSleepBlock ? created : nil
                )
            }
            return created
        } else {
            duplicateTimerMessage = "A \(type.displayName.lowercased()) timer is already running."
            return nil
        }
    }

    private func activeTimer(of type: EventType) -> BabyEvent? {
        cachedRenderState.activeTimer(of: type)
    }

    private func logDogPotty(_ pottyType: DogPottyType, accident: Bool) {
        var details = DogEventDetails()
        details.pottyType = pottyType
        details.pottyLocation = accident ? .indoorAccident : .outside
        details.accident = accident
        let now = Date()
        let timeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        let event = BabyEvent(
            profileID: selectedProfileID,
            type: .potty,
            startDate: now,
            endDate: now,
            startTimeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: timeZoneIdentifier,
            caregiverName: activeCaregiverName
        )
        event.profileTypeSnapshot = .dog
        event.dogDetails = details
        modelContext.insert(event)
        Task {
            await eventChanged(event, refreshPrediction: false, waitForSystemIntegrations: true)
        }
    }

    private func addRoutineTemplate(_ template: CareRoutineTemplate) {
        let householdID = template.scope == .household
            ? HouseholdService.ensureDefaultHousehold(context: modelContext).id
            : currentHouseholdID
        let routine = CareRoutineService.createRoutine(
            from: template,
            profileID: selectedProfileID,
            profileType: profile?.profileType,
            householdID: householdID,
            existingRoutines: careRoutines,
            context: modelContext
        )
        showingRoutineManager = false
        startRoutine(routine)
    }

    private func createCustomRoutine(_ input: CareRoutineInput) {
        let householdID = input.scope == .household
            ? HouseholdService.ensureDefaultHousehold(context: modelContext).id
            : currentHouseholdID
        guard let routine = CareRoutineService.createRoutine(
            title: input.title,
            notes: input.notes,
            scope: input.scope,
            iconName: input.iconName,
            tintName: input.tintName,
            reminderEnabled: input.reminderEnabled,
            reminderTimeMinutesAfterMidnight: input.reminderTimeMinutesAfterMidnight,
            steps: input.steps,
            profileID: selectedProfileID,
            profileType: profile?.profileType,
            householdID: householdID,
            existingRoutines: careRoutines,
            context: modelContext
        ) else {
            return
        }
        showingRoutineManager = false
        Task {
            await syncRoutineReminderPreference(for: routine)
        }
        startRoutine(routine)
    }

    private func updateCustomRoutine(_ routine: CareRoutine, input: CareRoutineInput) {
        let householdID = input.scope == .household
            ? HouseholdService.ensureDefaultHousehold(context: modelContext).id
            : currentHouseholdID
        let updated = CareRoutineService.updateRoutine(
            routine,
            input: input,
            profileID: selectedProfileID,
            profileType: profile?.profileType,
            householdID: householdID,
            existingSteps: careRoutineSteps,
            context: modelContext
        )
        guard updated else { return }
        Task {
            await syncRoutineReminderPreference(for: routine)
        }
    }

    private func duplicateRoutine(_ routine: CareRoutine) {
        let copy = CareRoutineService.duplicateRoutine(
            routine,
            steps: careRoutineSteps,
            existingRoutines: careRoutines,
            context: modelContext
        )
        Task {
            await notificationManager.cancelRoutineReminder(routineID: copy.id)
        }
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        CareRoutineService.reorderRoutines(
            visibleCareRoutines,
            from: source,
            to: destination,
            context: modelContext
        )
    }

    private func startRoutine(_ routine: CareRoutine) {
        let run = CareRoutineService.startRun(
            routine: routine,
            activeRuns: careRoutineRuns,
            context: modelContext,
            caregiverName: activeCaregiverName
        )
        openRoutineRun(routine, run)
    }

    private func openRoutineRun(_ routine: CareRoutine, _ run: CareRoutineRun) {
        routineRunRoute = CareRoutineRunRoute(routineID: routine.id, runID: run.id)
    }

    private func archiveRoutine(_ routine: CareRoutine) {
        if let activeRun = CareRoutineService.activeRun(for: routine, runs: careRoutineRuns) {
            CareRoutineService.cancelRun(activeRun, context: modelContext, caregiverName: activeCaregiverName)
        }
        CareRoutineService.archive(routine, context: modelContext)
        if routineRunRoute?.routineID == routine.id {
            routineRunRoute = nil
        }
        Task {
            await notificationManager.cancelRoutineReminder(routineID: routine.id)
        }
    }

    private func toggleRoutineReminder(_ routine: CareRoutine) {
        if routine.reminderEnabled {
            routine.reminderEnabled = false
            routine.updatedAt = Date()
            guard PersistenceService.save(context: modelContext) else { return }
            Task {
                await notificationManager.cancelRoutineReminder(routineID: routine.id)
            }
            return
        }

        Task {
            let status = await notificationManager.getAuthorizationStatus()
            let granted: Bool
            if status == .notDetermined {
                granted = await notificationManager.requestAuthorization()
            } else {
                granted = status == .authorized || status == .provisional || status == .ephemeral
            }
            guard granted else {
                showingPermissionDenied = true
                return
            }
            routine.reminderEnabled = true
            routine.reminderTimeMinutesAfterMidnight = routine.reminderTimeMinutesAfterMidnight
                ?? CareRoutineService.defaultReminderMinutes
            routine.updatedAt = Date()
            guard PersistenceService.save(context: modelContext) else { return }
            await notificationManager.scheduleRoutineReminder(routine: routine)
        }
    }

    private func syncRoutineReminderPreference(for routine: CareRoutine) async {
        guard routine.reminderEnabled else {
            await notificationManager.cancelRoutineReminder(routineID: routine.id)
            return
        }

        let status = await notificationManager.getAuthorizationStatus()
        let granted: Bool
        if status == .notDetermined {
            granted = await notificationManager.requestAuthorization()
        } else {
            granted = status == .authorized || status == .provisional || status == .ephemeral
        }
        guard granted else {
            routine.reminderEnabled = false
            routine.updatedAt = Date()
            guard PersistenceService.save(context: modelContext) else { return }
            showingPermissionDenied = true
            await notificationManager.cancelRoutineReminder(routineID: routine.id)
            return
        }

        routine.reminderTimeMinutesAfterMidnight = routine.reminderTimeMinutesAfterMidnight
            ?? CareRoutineService.defaultReminderMinutes
        routine.updatedAt = Date()
        guard PersistenceService.save(context: modelContext) else { return }
        await notificationManager.scheduleRoutineReminder(routine: routine)
    }

    private func performRoutineStep(
        _ step: CareRoutineStep,
        routine: CareRoutine,
        run: CareRoutineRun
    ) {
        switch step.action {
        case .checklist, .note:
            completeRoutineStep(step, routine: routine, run: run)
        case .logEvent:
            pendingRoutineStepCompletion = PendingRoutineStepCompletion(
                routineID: routine.id,
                runID: run.id,
                stepID: step.id
            )
            routineRunRoute = nil
            editorRoute = EventEditorRoute(type: step.eventType ?? .custom)
        case .startTimer:
            let created = startTimer(
                step.eventType ?? .custom,
                nursingSide: step.nursingSide,
                sleepKind: step.sleepKind,
                activityType: step.activityType,
                presentsEditor: false
            )
            if created != nil {
                completeRoutineStep(step, routine: routine, run: run)
            }
        case .openFoodHome:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.openFood(.food)
            routineRunRoute = nil
        case .openFoodQuickAdd:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.openFood(.quickAdd)
            routineRunRoute = nil
        case .openShoppingList:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.openFood(.shopping)
            routineRunRoute = nil
        case .openInventory:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.openFood(.inventory)
            routineRunRoute = nil
        case .openMealPrep:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.openFood(.mealPrep)
            routineRunRoute = nil
        case .openReports:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.selectedReportsMode = .day
            deepLinkRouter.selectedTab = .reports
            routineRunRoute = nil
        case .openMilestones:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.selectedTab = .milestones
            routineRunRoute = nil
        case .openAppointments:
            completeRoutineStep(step, routine: routine, run: run)
            routineRunRoute = nil
            showingAppointments = true
        case .openAgeGuide:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.pendingAgeGuideCommand = .list
            deepLinkRouter.selectedTab = .milestones
            routineRunRoute = nil
        case .openPuppyGuide:
            completeRoutineStep(step, routine: routine, run: run)
            routineRunRoute = nil
            deepLinkRouter.pendingPuppyGuideCommand = .current
            handlePendingPuppyGuideDeepLink()
        case .openSettings:
            completeRoutineStep(step, routine: routine, run: run)
            routineRunRoute = nil
            deepLinkRouter.presentSettings()
        case .openNightLight:
            completeRoutineStep(step, routine: routine, run: run)
            deepLinkRouter.selectedTab = .nightLight
            routineRunRoute = nil
        }
    }

    private func skipRoutineStep(
        _ step: CareRoutineStep,
        routine: CareRoutine,
        run: CareRoutineRun
    ) {
        CareRoutineService.skipStep(
            step,
            in: run,
            routine: routine,
            allSteps: careRoutineSteps,
            context: modelContext,
            caregiverName: activeCaregiverName
        )
        closeFinishedRoutineRunIfNeeded(run)
    }

    private func completeRoutineStep(
        _ step: CareRoutineStep,
        routine: CareRoutine,
        run: CareRoutineRun
    ) {
        CareRoutineService.completeStep(
            step,
            in: run,
            routine: routine,
            allSteps: careRoutineSteps,
            context: modelContext,
            caregiverName: activeCaregiverName
        )
        closeFinishedRoutineRunIfNeeded(run)
    }

    private func completePendingRoutineStepIfNeeded() {
        guard let pending = pendingRoutineStepCompletion,
              let routine = careRoutines.first(where: { $0.id == pending.routineID }),
              let run = careRoutineRuns.first(where: { $0.id == pending.runID }),
              let step = careRoutineSteps.first(where: { $0.id == pending.stepID }) else {
            pendingRoutineStepCompletion = nil
            return
        }
        pendingRoutineStepCompletion = nil
        completeRoutineStep(step, routine: routine, run: run)
    }

    private func finishRoutineRun(_ run: CareRoutineRun, routine: CareRoutine) {
        CareRoutineService.finishRun(run, routine: routine, context: modelContext, caregiverName: activeCaregiverName)
        routineRunRoute = nil
    }

    private func cancelRoutineRun(_ run: CareRoutineRun) {
        CareRoutineService.cancelRun(run, context: modelContext, caregiverName: activeCaregiverName)
        routineRunRoute = nil
    }

    private func closeFinishedRoutineRunIfNeeded(_ run: CareRoutineRun) {
        if run.state != .active {
            routineRunRoute = nil
        }
    }

    private func lastEventSubtitle(_ type: EventType, state: TodayRenderState) -> String {
        lastLoggedSubtitle(date: state.lastLoggedDates[type])
    }

    private func dogPottySubtitle(
        _ pottyType: DogPottyType,
        state: TodayRenderState,
        accident: Bool? = nil
    ) -> String {
        lastLoggedSubtitle(
            date: state.dogPottyLastLoggedDates[
                DogPottySubtitleKey(pottyType: pottyType, accident: accident)
            ]
        )
    }

    private func lastLoggedSubtitle(date: Date?) -> String {
        let now = Date()
        guard let date, date <= now else {
            return "Not logged"
        }
        return "Last \(DurationFormatting.string(seconds: now.timeIntervalSince(date))) ago"
    }

    private func dogLastEventTitle(_ type: EventType, state: TodayRenderState) -> String {
        state.dogLastEventTitles[type] ?? "Not logged"
    }

    private func dogPottyTitle(_ pottyType: DogPottyType, state: TodayRenderState) -> String {
        state.dogPottyTitles[pottyType] ?? "Not logged"
    }

    private func startNursing(_ side: NursingSide) {
        startTimer(.nursing, nursingSide: side)
    }

    private func refreshWidgetSnapshot() {
        WidgetSnapshotService.refresh(
            profile: profile,
            events: scopedEvents,
            prediction: prediction,
            solidsState: solidsProfileStates.first { $0.profileID == profile?.id }
        )
        WatchConnectivityService.shared.publishCurrentState()
    }

    private func scheduleRenderStateRefresh() {
        renderStateRefreshTask?.cancel()
        renderStateRefreshTask = Task { @MainActor in
            await AppInteractionMonitor.waitUntilIdle(for: 0.35)
            guard !Task.isCancelled else { return }
            refreshCachedRenderState()
        }
    }

    private func repeatLastEvent() {
        guard let source = EventMutationService.quickRepeatCandidate(
            in: scopedEvents,
            profileID: selectedProfileID
        ) else {
            showRepeatFeedback(
                title: "Nothing to repeat",
                subtitle: "Create a quick log first.",
                systemImage: "arrow.clockwise",
                tint: .secondary
            )
            return
        }

        guard let event = EventMutationService.repeatEvent(
                source,
                caregiverName: activeCaregiverName,
                profileID: selectedProfileID,
                profileType: profile?.profileType,
                context: modelContext
              ) else {
            return
        }
        showRepeatFeedback(
            title: "Repeated \(source.type.displayName)",
            subtitle: source.displayTitle,
            systemImage: source.activityType?.systemImage ?? source.type.systemImage(for: source.profileTypeSnapshot),
            tint: source.type.tint
        )
        Task {
            await eventChanged(
                event,
                refreshPrediction: event.type.affectsSleepPrediction,
                waitForSystemIntegrations: true
            )
        }
    }

    private func showRepeatFeedback(
        title: String,
        subtitle: String?,
        systemImage: String,
        tint: Color
    ) {
        let feedback = RepeatFeedback(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        )
        withAnimation(.snappy(duration: 0.22)) {
            repeatFeedback = feedback
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard repeatFeedback?.id == feedback.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                repeatFeedback = nil
            }
        }
    }

    private func performSmartQuickAction(_ action: QuickLogActionSnapshot) {
        deepLinkRouter.route(action.destinationURL(profileID: selectedProfileID))
        handlePendingProfileSwitch()
        handlePendingDeepLink()
        handlePendingAppointmentDeepLink()
        handlePendingPuppyGuideDeepLink()
        handlePendingRoutineDeepLink()
    }

    private func togglePinnedQuickAction(_ action: QuickLogActionSnapshot) {
        let isPinned = QuickLogActionPreferenceStore.togglePinnedAction(action.id, profileID: selectedProfileID)
        withAnimation(.snappy(duration: 0.18)) {
            pinnedQuickActionRevision += isPinned ? 1 : -1
        }
        refreshWidgetSnapshot()
    }

    private func smartQuickActionColor(_ tintName: String) -> Color {
        switch tintName {
        case "cyan": .cyan
        case "green": .green
        case "indigo": .indigo
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        default: .accentColor
        }
    }

    private func stop(_ event: BabyEvent) {
        EventMutationService.stopTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private func resume(_ event: BabyEvent) {
        EventMutationService.resumeTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func reset(_ event: BabyEvent) {
        EventMutationService.resetTimer(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func setStartTimeZone(_ identifier: String, for event: BabyEvent) {
        event.startTimeZoneIdentifier = identifier
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
        }
    }

    private func setEndTimeZone(_ identifier: String, for event: BabyEvent) {
        event.endTimeZoneIdentifier = identifier
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
        }
    }

    private func save(_ event: BabyEvent, endDate: Date? = nil) {
        EventMutationService.saveTimer(event, context: modelContext, endDate: endDate)
        Task {
            await eventChanged(
                event,
                refreshPrediction: true,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private func switchNursingSide(_ event: BabyEvent) {
        EventTimerService.switchNursingSide(event, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func setNursingSide(_ side: NursingSide, for event: BabyEvent) {
        EventTimerService.setNursingSide(event, to: side, context: modelContext)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
        }
    }

    private func markCompleted(_ appointment: DoctorAppointment) {
        appointment.isCompleted = true
        appointment.updatedAt = Date()
        guard PersistenceService.save(context: modelContext) else { return }
        Task {
            await notificationManager.cancelAppointmentReminders(
                appointmentID: appointment.id
            )
        }
    }

    private func handlePendingDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        // Profile-scoped actions publish the profile and action together. Apply
        // the explicit profile before consuming the action so child-only logs
        // are not dropped when a dog was previously selected.
        handlePendingProfileSwitch()
        guard let action = deepLinkRouter.consumeAction() else { return }
        switch action {
        case .showActiveTimer:
            activeTimerToEdit = EventTimerService.primaryActiveEvent(in: scopedEvents)
        case .showEvent(let id):
            if let event = scopedEvents.first(where: { $0.id == id }) {
                if event.isTimerDraft {
                    activeTimerToEdit = event
                } else {
                    editorRoute = EventEditorRoute(type: event.type, event: event)
                }
            }
        case .stopActiveTimer:
            if let event = EventTimerService.primaryActiveEvent(in: scopedEvents) {
                stop(event)
            }
        case .stopTimer(let id):
            if let event = scopedEvents.first(where: { $0.id == id && $0.isTimerRunning }) {
                stop(event)
            }
        case .resumeTimer(let id):
            if let event = scopedEvents.first(where: {
                $0.id == id && $0.isTimerDraft && !$0.isTimerRunning
            }) {
                resume(event)
            }
        case .switchNursingSide(let id):
            if let event = scopedEvents.first(where: { $0.id == id }) {
                switchNursingSide(event)
            }
        case .startTimer(let type, let side):
            if type == .sleep {
                if let existingTimer = activeTimer(of: .sleep) {
                    activeTimerToEdit = existingTimer
                } else {
                    showingSleepChooser = true
                }
            } else {
                startTimer(type, nursingSide: side)
            }
        case .startActivity(let activity):
            startTimer(.activity, activityType: activity)
        case .logDiaper:
            editorRoute = EventEditorRoute(type: .diaper)
        case .logEvent(let type):
            editorRoute = EventEditorRoute(
                type: profile?.profileType == .dog && type == .feed ? .food : type
            )
        case .logSolidFeed(let preset):
            guard let profile, profile.profileType == .child else { return }
            let state = solidsProfileStates.first { $0.profileID == profile.id }
            guard SolidsTrackingService.accessLevel(
                for: profile,
                events: scopedEvents,
                state: state
            ) == .full else { return }
            let resolvedPreset: SolidFeedEditorPreset
            if let plannedMealID = preset.plannedMealID {
                guard let plan = plannedSolidMeals.first(where: {
                    $0.id == plannedMealID && $0.profileID == profile.id && !$0.isCompleted
                }) else { return }
                resolvedPreset = SolidsTrackingService.preset(for: plan)
            } else {
                resolvedPreset = preset
            }
            editorRoute = EventEditorRoute(
                type: .feed,
                solidPreset: resolvedPreset
            )
        case .repeatLast:
            repeatLastEvent()
        }
    }

    private func handlePendingProfileSwitch() {
        guard let id = deepLinkRouter.pendingProfileID else { return }
        profileService.switchProfile(id: id, profiles: profiles)
        deepLinkRouter.pendingProfileID = nil
        refreshActiveSleepPlan()
    }

    private func handlePendingAppointmentDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard let command = deepLinkRouter.consumeAppointmentCommand() else { return }
        switch command {
        case .list:
            showingAppointments = true
        case .detail(let id), .notes(let id):
            appointmentToOpen = scopedAppointments.first { $0.id == id }
                ?? fetchAppointment(id: id)
        }
    }

    private func fetchAppointment(id: UUID) -> DoctorAppointment? {
        var descriptor = FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate<DoctorAppointment> { appointment in
                appointment.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func handlePendingPuppyGuideDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard deepLinkRouter.consumePuppyGuideCommand() != nil else { return }
        guard let targetProfile = dogProfileForPuppyGuide(),
              let guide = PuppyStageGuideService.shared.currentGuide(for: targetProfile) else {
            return
        }
        if profile?.id != targetProfile.id {
            profileService.switchProfile(targetProfile)
        }
        puppyGuideProfileToOpen = targetProfile
        puppyGuideToOpen = guide
    }

    private func handlePendingRoutineDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard deepLinkRouter.consumeRoutineCommand() != nil else { return }
        showingRoutineManager = true
    }

    private func dogProfileForPuppyGuide() -> BabyProfile? {
        if let profile, profile.profileType == .dog {
            return profile
        }
        return profiles.first { $0.profileType == .dog && !$0.isArchived }
    }

    private func eventChanged(
        _ event: BabyEvent,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false,
        solidPreset: SolidFeedEditorPreset? = nil
    ) async {
        event.profileID = event.profileID ?? selectedProfileID
        let currentEvents = scopedEvents.contains(where: { $0.id == event.id })
            ? scopedEvents
            : scopedEvents + [event]
        await EventMutationService.eventDidChange(
            event,
            profile: profile,
            events: currentEvents,
            records: scopedRecords,
            context: modelContext,
            settings: predictionSettings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes,
            refreshPrediction: refreshPrediction,
            waitForSystemIntegrations: waitForSystemIntegrations,
            solidPreset: solidPreset
        )
    }

    private func adjustStart(of event: BabyEvent, to date: Date) {
        EventTimerService.adjustStartDate(event, to: date)
        Task {
            await eventChanged(
                event,
                refreshPrediction: false,
                waitForSystemIntegrations: true
            )
            await syncActiveSleepPlanWakeAlert(for: event)
        }
    }

    private func delete(_ event: BabyEvent) {
        Task {
            await EventMutationService.delete(
                event,
                profile: profile,
                events: scopedEvents,
                records: scopedRecords,
                context: modelContext,
                settings: predictionSettings,
                notificationsEnabled: notificationsEnabled,
                notificationLeadMinutes: notificationLeadMinutes
            )
        }
    }

    private var deleteEventOptions: [AppActionSheetOption] {
        guard let event = eventPendingDelete else { return [] }
        return [
            AppActionSheetOption(
                title: "Delete \(event.type.displayName)",
                subtitle: "This cannot be undone.",
                systemImage: "trash.fill",
                tint: .red,
                role: .destructive
            ) {
                delete(event)
                eventPendingDelete = nil
            }
        ]
    }

    private func toggleLittleWindowAlerts() {
        if notificationsEnabled {
            notificationsEnabled = false
            Task {
                await notificationManager.cancelPendingLittleWindowAlerts()
            }
        } else {
            showingAlertPermissionPrompt = true
        }
    }

    private func refreshActiveSleepPlan() {
        activeSleepPlan = ActiveSleepPlanService.activePlan(
            for: selectedProfileID
        )
    }

    private func activateSleepPlan(_ plan: BackwardsSleepPlan) {
        guard let profileID = selectedProfileID else { return }
        activeSleepPlan = ActiveSleepPlanService.activate(
            plan: plan,
            profileID: profileID
        )
        Task {
            await ensureNotificationPermissionForPlan()
            await syncActiveSleepPlanWakeAlert()
        }
    }

    private func deactivateSleepPlan() {
        ActiveSleepPlanService.clear(profileID: selectedProfileID)
        activeSleepPlan = nil
        Task {
            await notificationManager.cancelActiveSleepPlanWakeAlert(
                profileID: selectedProfileID
            )
        }
    }

    private func wakeAlert(for event: BabyEvent?) -> ActiveSleepPlanWakeAlert? {
        ActiveSleepPlanService.wakeAlert(
            for: activeSleepPlan,
            profile: profile,
            events: scopedEvents,
            activeSleep: event,
            settings: predictionSettings
        )
    }

    private func ensureNotificationPermissionForPlan() async {
        let status = await notificationManager.getAuthorizationStatus()
        if status == .notDetermined {
            _ = await notificationManager.requestAuthorization()
        } else if status == .denied {
            showingPermissionDenied = true
        }
    }

    private func syncActiveSleepPlanWakeAlert(for event: BabyEvent? = nil) async {
        refreshActiveSleepPlan()
        let alert = wakeAlert(for: event ?? runningSleepTimer)
        if let alert {
            await notificationManager.scheduleActiveSleepPlanWakeAlert(
                alert,
                babyName: profile?.name ?? "Baby"
            )
        } else {
            await notificationManager.cancelActiveSleepPlanWakeAlert(
                profileID: selectedProfileID
            )
        }
    }

    private func enableLittleWindowAlerts() async {
        let status = await notificationManager.getAuthorizationStatus()
        let granted: Bool
        if status == .notDetermined {
            granted = await notificationManager.requestAuthorization()
        } else {
            granted = status == .authorized || status == .provisional || status == .ephemeral
        }
        guard granted else {
            notificationsEnabled = false
            showingPermissionDenied = true
            return
        }
        notificationsEnabled = true
        await notificationManager.rescheduleLittleWindowAlertIfNeeded(
            prediction: prediction,
            babyName: profile?.name ?? "Baby",
            profileID: selectedProfileID,
            settings: .current,
            isSleeping: activeEvents.contains {
                $0.isSleepBlock && $0.isTimerRunning
            }
        )
    }

    private func activityOptions(state: TodayRenderState) -> [AppActionSheetOption] {
        ActivityType.allCases.map { activity in
            let timerAlreadyActive = activity != .custom && state.hasActiveTimer(of: .activity)
            return AppActionSheetOption(
                title: activity.displayName,
                subtitle: timerAlreadyActive
                    ? "An activity timer is already active."
                    : (activity == .custom
                        ? "Open the editor for a custom activity."
                        : "Start a timer now."),
                systemImage: activity.systemImage,
                tint: .green,
                isEnabled: !timerAlreadyActive
            ) {
                if activity == .custom {
                    editorRoute = EventEditorRoute(type: .activity)
                } else {
                    startTimer(.activity, activityType: activity)
                }
            }
        }
    }
}

private struct RepeatFeedback: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color
}

private struct RepeatFeedbackBanner: View {
    let feedback: RepeatFeedback

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: feedback.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(feedback.tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = feedback.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.26), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct SleepKindChooser: ViewModifier {
    @Binding var isPresented: Bool
    let timerIsActive: Bool
    let startSleep: (SleepKind) -> Void

    func body(content: Content) -> some View {
        content.appActionSheet(
            isPresented: $isPresented,
            title: "Start Sleep",
            message: timerIsActive
                ? "A sleep timer is already active. Manage it from the timer card."
                : "This keeps daytime naps and overnight sleep accurate in History and Insights.",
            systemImage: "moon.zzz.fill",
            tint: .indigo,
            options: SleepKind.allCases.map { kind in
                AppActionSheetOption(
                    title: kind.displayName,
                    subtitle: timerIsActive
                        ? "A sleep timer is already active."
                        : sleepKindSubtitle(kind),
                    systemImage: kind.systemImage,
                    tint: sleepKindTint(kind),
                    isEnabled: !timerIsActive
                ) {
                    startSleep(kind)
                }
            }
        )
    }

    private func sleepKindSubtitle(_ kind: SleepKind) -> String {
        switch kind {
        case .nap: "Track a daytime sleep."
        case .nightSleep: "Track overnight sleep."
        case .nightWaking: "Track awake time during the night."
        }
    }

    private func sleepKindTint(_ kind: SleepKind) -> Color {
        switch kind {
        case .nap: .orange
        case .nightSleep: .indigo
        case .nightWaking: .pink
        }
    }
}

private struct QuickActionButton: View {
    var title: String
    var detail: String? = nil
    var subtitle: String? = nil
    var icon: String
    var color: Color
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionButtonLabel(
                title: title,
                detail: detail,
                subtitle: subtitle,
                icon: icon,
                color: color
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .accessibilityHint(isEnabled ? "" : "A timer of this type is already active")
    }
}

private struct SleepMiniPlanCard: View {
    var plan: SleepMiniPlan
    var openPlanner: () -> Void
    private var tint: Color {
        switch plan.tintName {
        case "cyan": .cyan
        case "green": .green
        case "mint": .mint
        case "purple": .purple
        default: .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.headline)
                    Text(plan.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !plan.timelineItems.isEmpty {
                VStack(spacing: 0) {
                    ForEach(plan.timelineItems) { item in
                        SleepMiniPlanTimelineRow(item: item)
                        if item.id != plan.timelineItems.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.steps, id: \.self) { step in
                    Label(step, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Button(action: openPlanner) {
                Label("Open Plan", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(16)
        .appSurface(cornerRadius: 18)
    }
}

private struct SleepMiniPlanTimelineRow: View {
    var item: SleepMiniPlanTimelineItem

    private var tint: Color {
        switch item.tintName {
        case "cyan": .cyan
        case "green": .green
        case "mint": .mint
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        default: .indigo
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    if item.isCurrent {
                        Text("NOW")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint, in: Capsule())
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(item.timeText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

private struct QuickActionButtonLabel: View {
    var title: String
    var detail: String? = nil
    var subtitle: String? = nil
    var icon: String
    var color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 84, alignment: .top)
        .contentShape(Rectangle())
    }
}

private struct CareCategoryCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID?
    let profileType: CareProfileType
    let onChange: () -> Void

    @State private var hiddenTypes: Set<EventType>

    init(
        profileID: UUID?,
        profileType: CareProfileType,
        onChange: @escaping () -> Void
    ) {
        self.profileID = profileID
        self.profileType = profileType
        self.onChange = onChange
        _hiddenTypes = State(initialValue: CareCategoryPreferenceStore.hiddenTypes(profileID: profileID))
    }

    var body: some View {
        let eventTypes = EventType.cases(for: profileType)
        let visibleTypeCount = eventTypes.filter { !hiddenTypes.contains($0) }.count

        List {
            Section {
                ForEach(eventTypes) { type in
                    Toggle(isOn: binding(for: type)) {
                        Label(type.displayName, systemImage: type.systemImage(for: profileType))
                    }
                    .disabled(!canChangeVisibility(for: type, visibleTypeCount: visibleTypeCount))
                }
            } header: {
                Text("Today Actions")
            } footer: {
                Text("Hidden categories stay available in history and existing logs.")
            }
            Section {
                Button("Reset to Defaults") {
                    hiddenTypes.removeAll()
                    CareCategoryPreferenceStore.reset(profileID: profileID)
                    onChange()
                }
            }
        }
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func binding(for type: EventType) -> Binding<Bool> {
        Binding(
            get: { !hiddenTypes.contains(type) },
            set: { isVisible in
                guard isVisible || canHide(type) else { return }
                if isVisible {
                    hiddenTypes.remove(type)
                } else {
                    hiddenTypes.insert(type)
                }
                CareCategoryPreferenceStore.setHiddenTypes(hiddenTypes, profileID: profileID)
                onChange()
            }
        )
    }

    private func canChangeVisibility(for type: EventType, visibleTypeCount: Int) -> Bool {
        hiddenTypes.contains(type) || visibleTypeCount > 1
    }

    private func canHide(_ type: EventType) -> Bool {
        hiddenTypes.contains(type) || EventType.cases(for: profileType).filter { !hiddenTypes.contains($0) }.count > 1
    }
}

private struct DogSummaryCard: View {
    var title: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())
                Spacer()
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}
