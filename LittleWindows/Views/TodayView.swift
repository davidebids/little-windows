import Combine
import CoreData
import SwiftData
import SwiftUI
import UIKit

struct EventEditorRoute: Identifiable {
    let id = UUID()
    var type: EventType
    var event: CareEvent?
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
    static func solidFoodSummary(for event: CareEvent) -> String? {
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

enum TodayDogQuickActionCatalog {
    static func enabledTypes(in visibleTypes: Set<EventType>) -> [EventType] {
        EventType.cases(for: .dog).filter(visibleTypes.contains)
    }
}

enum TodayEssentialsTimerPresentation {
    static func compactTimers(events: [CareEvent], represented: [CareEvent]) -> [CareEvent] {
        let representedIDs = Set(represented.map(\.id))
        return events.filter { $0.isTimerDraft && !representedIDs.contains($0.id) }
    }
}

/// Keep button context short enough to share the existing secondary text line.
enum TodayEssentialsEventDetail {
    static func durationText(seconds: TimeInterval) -> String {
        DurationFormatting.string(seconds: seconds).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    static func context(for event: CareEvent) -> String? {
        switch event.type {
        case .nursing:
            if event.isTimerDraft { return event.activeNursingSide?.displayName }
            if let side = event.nursingSideRawValue.flatMap(NursingSide.init(rawValue:)) {
                return side.displayName
            }
            let left = (event.leftDurationSeconds ?? 0) > 0
            let right = (event.rightDurationSeconds ?? 0) > 0
            if left && right { return "Both sides" }
            return left ? "Left" : right ? "Right" : nil
        case .diaper:
            guard let kind = event.diaperKind else { return nil }
            return kind == .both ? "Pee & poo" : kind.displayName
        case .potty:
            if event.profileTypeSnapshot == .dog {
                guard let kind = event.dogDetails.pottyType else { return nil }
                return kind == .both ? "Pee & poo" : kind.displayName
            }
            guard let kind = event.childPottyKind else { return nil }
            return kind == .both ? "Pee & poo" : kind.displayName
        case .feed:
            return event.feedKind?.displayName
        case .sleep:
            return event.sleepKind?.displayName
        default:
            return nil
        }
    }

    static func timerDetail(for event: CareEvent) -> String {
        if let context = context(for: event) {
            return "\(context) · \(event.isTimerRunning ? "Running" : "Stopped")"
        }
        return event.isTimerRunning ? "Running · tap to manage" : "Stopped · tap to finish"
    }
}

/// Time labels read this tiny value instead of scanning history on every tick.
struct TodayEssentialsHistorySummary {
    struct Record {
        var date: Date
        var context: String?
    }

    var latestRecords: [EventType: Record] = [:]
    var lastEndedDates: [EventType: Date] = [:]
    var nextTransition: Date?

    mutating func include(_ event: CareEvent, now: Date) {
        guard !event.isTimerDraft else { return }
        let logDate = event.endDate ?? event.startDate
        if logDate > now {
            nextTransition = min(nextTransition ?? logDate, logDate)
        } else if latestRecords[event.type].map({ logDate >= $0.date }) ?? true {
            latestRecords[event.type] = Record(date: logDate, context: TodayEssentialsEventDetail.context(for: event))
        }
        if (event.type == .sleep || event.type == .rest), let end = event.endDate, end <= now {
            lastEndedDates[event.type] = max(lastEndedDates[event.type] ?? end, end)
        }
    }

    func recentDetail(for type: EventType, now: Date) -> String {
        guard let record = latestRecords[type], record.date <= now else { return "No recent record · tap to log" }
        let elapsed = now.timeIntervalSince(record.date)
        if let context = record.context {
            return "\(context) · \(elapsed < 60 ? "Just logged" : "\(TodayEssentialsEventDetail.durationText(seconds: elapsed)) ago")"
        }
        return elapsed < 60 ? "Just logged" : "Last \(TodayEssentialsEventDetail.durationText(seconds: elapsed)) ago"
    }

    static func make(events: [CareEvent], now: Date) -> Self {
        var summary = Self()
        for event in events { summary.include(event, now: now) }
        return summary
    }
}

/// A hidden section must not keep its SwiftData queries and builders active.
struct TodayCareRenderRequirements {
    let preferences: CareTrackingPreferences
    let profileType: CareProfileType
    let hiddenTypes: Set<EventType>

    func includes(_ section: CareTodaySection) -> Bool {
        section.applies(to: profileType) && preferences.shows(section)
    }

    var sleepAnalysis: Bool { includes(.prediction) || includes(.sleepPlan) }
    var smartActions: Bool { preferences.layout == .full && includes(.actions) }
    var medication: Bool {
        preferences.allows(.medicine) && (includes(.medicationDue) ||
            (preferences.layout == .essentials && includes(.actions) &&
             preferences.essentialTypes(for: profileType, hidden: hiddenTypes).contains(.medicine)))
    }
    var historyOnMinuteTick: Bool {
        [.timeline, .prediction, .sleepPlan, .solids, .routines, .guides, .appointments, .summary]
            .contains(where: includes)
    }
}

private struct TodayRenderState {
    var profile: CareProfile?
    var profileID: UUID?
    var scopedEvents: [CareEvent]
    var scopedRecords: [SleepPredictionRecord]
    var scopedAppointments: [DoctorAppointment]
    var scopedAgeGuideReadStates: [AgeGuideReadState]
    var scopedPuppyGuideReadStates: [PuppyStageGuideReadState]
    var todayEvents: [CareEvent]
    var activeEvents: [CareEvent]
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
    var runningSleepTimer: CareEvent?
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
    var upcomingMedication: WatchMedicationSnapshot? = nil
    var trackingPreferences = CareTrackingPreferences()
    var hiddenCareTypes: Set<EventType> = []
    var essentialsHistory = TodayEssentialsHistorySummary()

    var renderRequirements: TodayCareRenderRequirements {
        TodayCareRenderRequirements(preferences: trackingPreferences,
            profileType: profile?.profileType ?? .child, hiddenTypes: hiddenCareTypes)
    }

    func shows(_ type: EventType) -> Bool {
        visibleCareTypes.contains(type)
    }

    func hasActiveTimer(of type: EventType) -> Bool {
        activeEvents.contains { $0.type == type && $0.isTimerDraft }
    }

    func activeTimer(of type: EventType) -> CareEvent? {
        activeEvents.first { $0.type == type && $0.isTimerDraft }
    }

    func compactEssentialTimers(preferences: CareTrackingPreferences, hidden: Set<EventType>) -> [CareEvent] {
        let represented = preferences.shows(.actions)
            ? preferences.essentialTypes(for: profile?.profileType ?? .child, hidden: hidden).compactMap(activeTimer)
            : []
        return TodayEssentialsTimerPresentation.compactTimers(events: activeEvents, represented: represented)
    }

    func visibleCareSections(preferences: CareTrackingPreferences, hidden: Set<EventType>, now: Date = Date()) -> Set<CareTodaySection> {
        guard let profile else { return [] }
        return Set(CareTodaySection.allCases.filter { section in
            guard section.applies(to: profile.profileType), preferences.shows(section) else { return false }
            switch section {
            case .actions:
                return preferences.layout == .essentials
                    ? !preferences.essentialTypes(for: profile.profileType, hidden: hidden).isEmpty
                    : !visibleCareTypes.isEmpty || (profile.profileType == .adult && preferences.allowsPrompts(.appointments))
            case .activeTimers:
                return preferences.layout == .essentials
                    ? !compactEssentialTimers(preferences: preferences, hidden: hidden).isEmpty
                    : !activeEvents.isEmpty
            case .medicationDue:
                return preferences.showsMedicationDueCard(scheduledAt: upcomingMedication?.scheduledAt,
                                                          profileType: profile.profileType, hidden: hidden, now: now)
            case .prediction:
                return !activeEvents.contains(where: { $0.isSleepBlock })
            case .sleepPlan:
                return sleepMiniPlan != nil && !activeEvents.contains(where: { $0.isSleepBlock })
            case .solids:
                return solidsAccessLevel == .readinessPreview || (solidsAccessLevel == .full &&
                    (nextPlannedSolidMeal != nil || dueSolidAllergenProgress != nil || !hasSolidHistory))
            case .guides:
                return profile.profileType == .dog
                    ? shouldShowPuppyGuideCard && currentPuppyGuide != nil
                    : shouldShowAgeGuideCard && currentAgeGuide != nil
            case .appointments:
                return !relevantAppointments.isEmpty
            case .summary:
                return [EventType.food, .water, .potty, .walk, .medicine].contains(where: preferences.allows)
            case .weather, .routines, .timeline:
                return true
            }
        })
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

/// Observe only routes that Today actually consumes. Weather presentation and
/// unrelated workspace navigation must not invalidate its query-backed content.
@MainActor
private final class TodayRouteObservation: ObservableObject {
    private var subscriptions = Set<AnyCancellable>()
    init(router: DeepLinkRouter = .shared) {
        router.$todayDisplayMode.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$pendingAction.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$pendingProfileID.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$pendingAppointmentCommand.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$pendingPuppyGuideCommand.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$pendingRoutineCommand.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$pendingAgeGuideCommand.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$isDataReady.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$showingSettings.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        router.$selectedTab.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
    }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private let deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var routeObservation = TodayRouteObservation()
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @Query private var allEvents: [CareEvent]
    @Query private var activeTimerEvents: [CareEvent]
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
    @State private var pendingActivityEditorRoute: EventEditorRoute?
    @State private var activeTimerToEdit: CareEvent?
    @State private var showingExplanation = false
    @State private var showingBackwardsPlanner = false
    @State private var duplicateTimerMessage: String?
    @State private var showingAlertPermissionPrompt = false
    @State private var showingPermissionDenied = false
    @State private var showingSleepChooser = false
    @State private var showingNursingChooser = false
    @State private var showingActivityChooser = false
    @State private var showingAppointments = false
    @State private var showingMedications = false
    @State private var appointmentToOpen: DoctorAppointment?
    @State private var selectedMilestoneTemplate: MilestoneTemplate?
    @State private var puppyGuideToOpen: PuppyStageGuide?
    @State private var puppyGuideProfileToOpen: CareProfile?
    @State private var showingProfileEditor = false
    @State private var showingRoutineManager = false
    @State private var routineRunRoute: CareRoutineRunRoute?
    @State private var pendingRoutineStepCompletion: PendingRoutineStepCompletion?
    @State private var eventPendingDelete: CareEvent?
    @State private var activeSleepPlan: ActiveSleepPlan?
    @State private var pinnedQuickActionRevision = 0
    @State private var categoryPreferenceRevision = 0
    @State private var repeatFeedback: RepeatFeedback?
    @State private var careCustomization = TodayCustomizationPresentation()
    @State private var cachedRenderState = TodayRenderState.empty
    @State private var displayDate = Date()
    @State private var hasCompletedInitialSetup = false
    @State private var renderStateRefreshTask: Task<Void, Never>?
    @State private var renderStateRefreshPending = false
    @State private var integrationAnalysisTask: Task<Void, Never>?
    @State private var integrationAnalysisRevision = UUID()
    @State private var timerMutationRenderDeferralActive = false
    @State private var timerSystemRefreshTask: Task<Void, Never>?
    @State private var timerSystemRefreshRevision = UUID()
    @State private var localEventMutationCount = 0
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var profileService = ProfileService.shared

    private var usesWideIPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var todayContentHorizontalMargin: CGFloat {
        usesWideIPadLayout ? 46 : 0
    }

    private var todayMenuLabelWidth: CGFloat {
        if #available(iOS 26.0, *) { return 24 }
        return 36
    }

    private var todayListContentHorizontalMargin: CGFloat? {
        usesWideIPadLayout ? todayContentHorizontalMargin : nil
    }

    private var quickActionGridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(),
                spacing: usesWideIPadLayout ? 14 : 8
            ),
            count: usesWideIPadLayout ? 5 : 3
        )
    }

    private var quickActionGridSpacing: CGFloat {
        usesWideIPadLayout ? 16 : 14
    }

    private var summaryGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: usesWideIPadLayout ? 3 : 2
        )
    }

    init(profileID: UUID? = nil) {
        InteractionPerformanceAudit.count("TodayInit")
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let recentCutoff = calendar.date(byAdding: .day, value: -45, to: todayStart) ?? todayStart
        let selectedProfileID = profileID ?? ProfileService.shared.selectedProfileID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        var eventDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate<CareEvent> { event in
                event.profileID == selectedProfileID &&
                    event.startDate >= recentCutoff &&
                    (event.timerStateRawValue == nil || event.endDate != nil)
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        _allEvents = Query(eventDescriptor)

        var activeTimerDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate<CareEvent> { event in
                event.profileID == selectedProfileID &&
                    event.timerStateRawValue != nil &&
                    event.endDate == nil
            },
            sortBy: [SortDescriptor(\CareEvent.updatedAt, order: .reverse)]
        )
        activeTimerDescriptor.fetchLimit = 30
        _activeTimerEvents = Query(activeTimerDescriptor)

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
    private var profile: CareProfile? {
        cachedRenderState.profile
    }
    private var selectedProfileID: UUID? { cachedRenderState.profileID }
    private var scopedEvents: [CareEvent] {
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
    private var activeEvents: [CareEvent] {
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
    private var runningSleepTimer: CareEvent? {
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

    private var renderStateRefreshIsDeferred: Bool {
        deepLinkRouter.showingSettings || showingProfileEditor || careCustomization.isPresented
    }

    private func refreshCachedRenderState() {
        refreshCachedRenderState(refreshesAnalysis: true)
    }

    private func refreshCachedRenderState(refreshesAnalysis: Bool) {
        // Today remains mounted underneath full-screen editing sheets. Building
        // its bounded event timeline while the user saves a profile needlessly
        // faults and sorts hundreds of rows on the main actor, delaying the
        // visible sheet. The dismissal path schedules one coalesced refresh.
        guard !renderStateRefreshIsDeferred else { renderStateRefreshPending = true; return }
        cachedRenderState = makeRenderState()
        if refreshesAnalysis {
            scheduleIntegrationAnalysisRefresh()
        }
    }

    private func scheduleIntegrationAnalysisRefresh() {
        integrationAnalysisTask?.cancel()
        guard let profile = cachedRenderState.profile,
              profile.profileType == .child,
              cachedRenderState.renderRequirements.sleepAnalysis,
              cachedRenderState.activeEvents.isEmpty else {
            // A timer draft already carries the exact live state needed by
            // Today, widgets, and Live Activities. Fetching and faulting up to
            // 60 days of history while its editor is open can contend with the
            // SwiftData insert and starve TimelineView updates on real devices.
            cachedRenderState.sleepPressure = nil
            cachedRenderState.sleepMiniPlan = nil
            integrationAnalysisTask = nil
            return
        }
        let profileID = profile.id
        let settings = predictionSettings
        let container = modelContext.container
        let revision = UUID()
        integrationAnalysisRevision = revision
        integrationAnalysisTask = Task.detached(priority: .utility) {
            // The persistence actor serializes reads and checks cancellation
            // before fetching; newer requests replace queued work immediately.
            guard !Task.isCancelled else { return }
            let analysis = await EventMutationService.integrationAnalysis(
                profileID: profileID,
                container: container,
                settings: settings
            )
            guard analysis.isAuthoritative, !Task.isCancelled else { return }
            await MainActor.run {
                guard integrationAnalysisRevision == revision,
                      cachedRenderState.profileID == profileID,
                      cachedRenderState.isSleeping == analysis.isSleeping else { return }
                guard !renderStateRefreshIsDeferred else { return }
                applyIntegrationAnalysis(analysis)
                integrationAnalysisTask = nil
            }
        }
    }

    private func applyIntegrationAnalysis(_ analysis: EventIntegrationAnalysis) {
        guard analysis.isAuthoritative,
              cachedRenderState.isSleeping == analysis.isSleeping else { return }
        var state = cachedRenderState
        state.prediction = analysis.prediction
        state.sleepPressure = state.isSleeping ? nil : analysis.pressure
        state.sleepMiniPlan = analysis.miniPlan
        cachedRenderState = state
    }

    private func invalidateIntegrationAnalysis() {
        integrationAnalysisRevision = UUID()
        integrationAnalysisTask?.cancel()
        integrationAnalysisTask = nil
    }

    private func makeRenderState() -> TodayRenderState {
        InteractionPerformanceAudit.count("today.history-build")
        let profile = profileService.selectedProfile(in: profiles)
        let profileID = profile?.id
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        // Every query owned by TodayView is already scoped to the selected profile.
        // Do not re-read every SwiftData property just to apply the same filter.
        // Timer drafts are intentionally queried separately from history. A
        // pause or resume updates one high-churn row; keeping it out of the
        // bounded history query prevents SwiftData from re-merging hundreds of
        // timeline rows while the user is scrolling Today.
        let scopedEvents = EventVisibilityStore.visibleEvents(
            in: activeTimerEvents + allEvents
        ).sorted { $0.startDate > $1.startDate }
        let trackingPreferences = CareTrackingPreferenceStore.preferences(profileID: profileID)
        let hiddenCareTypes = CareCategoryPreferenceStore.hiddenTypes(profileID: profileID, preferences: trackingPreferences)
        let requirements = TodayCareRenderRequirements(preferences: trackingPreferences,
            profileType: profile?.profileType ?? .child, hiddenTypes: hiddenCareTypes)
        let scopedRecords = requirements.sleepAnalysis ? records : []
        let scopedAppointments = requirements.includes(.appointments) ? appointments : []
        let scopedAgeGuideReadStates = requirements.includes(.guides) ? ageGuideReadStates : []
        let scopedPuppyGuideReadStates = requirements.includes(.guides) ? puppyStageGuideReadStates : []
        let currentHouseholdID = households.first?.id
        let needsRoutines = requirements.includes(.routines) || showingRoutineManager
        let visibleCareRoutines = needsRoutines ? CareRoutineService.visibleRoutines(
            routines: careRoutines,
            profileID: profileID,
            profileType: profile?.profileType,
            householdID: currentHouseholdID
        ).filter { routine in
            CareRoutineService.activeRun(for: routine, runs: careRoutineRuns) != nil
                || CareTrackingPreferenceStore.allowsRoutine(routine, steps: careRoutineSteps)
        } : []
        let careRoutineTodayItems = visibleCareRoutines.prefix(3).map { routine in
            CareRoutineTodayItem(
                routine: routine,
                steps: CareRoutineService.steps(for: routine, steps: careRoutineSteps),
                activeRun: CareRoutineService.activeRun(for: routine, runs: careRoutineRuns),
                latestRun: CareRoutineService.latestRun(for: routine, runs: careRoutineRuns)
            )
        }
        let existingRoutineKinds = Set(visibleCareRoutines.compactMap(\.templateKind))
        let suggestedRoutineTemplates = needsRoutines ? CareRoutineService.templates(for: profile?.profileType).filter {
            !existingRoutineKinds.contains($0.kind)
                && trackingPreferences.allowsPrompts(.routines)
                && $0.steps.allSatisfy { trackingPreferences.allowsRoutineStep(eventType: $0.eventType, action: $0.action) }
        } : []
        let currentAgeGuide = requirements.includes(.guides) ? profile.flatMap { AgeGuideService.shared.currentAgeGuide(for: $0) } : nil
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
        let currentPuppyGuide = requirements.includes(.guides) ? profile.flatMap { PuppyStageGuideService.shared.currentGuide(for: $0) } : nil
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
        var todayEvents: [CareEvent] = []
        var activeEvents: [CareEvent] = []
        var latestCompletedSleepEnd: Date?
        var latestStoppedDraftSleepEnd: Date?
        var dogLatestEvents: [EventType: CareEvent] = [:]
        var latestPeeEvent: CareEvent?
        var latestPoopEvent: CareEvent?
        var lastLoggedDates: [EventType: Date] = [:]
        var latestSolidFoodSummary: String?
        var dogPottyLastLoggedDates: [DogPottySubtitleKey: Date] = [:]
        var hasSolidHistory = false

        var essentialsHistory = TodayEssentialsHistorySummary()
        for event in scopedEvents {
            essentialsHistory.include(event, now: now)
            if event.isTimerDraft {
                activeEvents.append(event)
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
        // Prediction, pressure, and the day-ahead plan are carried forward
        // until the isolated analysis worker publishes a fresh result. On a
        // cold launch with a timer already open, restore the latest unresolved
        // prediction record without scanning history so discarding the draft
        // can reveal it immediately.
        let storedPrediction = scopedRecords
            .lazy
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }?
            .prediction
        let prediction = cachedRenderState.profileID == profileID
            ? cachedRenderState.prediction ?? storedPrediction
            : storedPrediction
        let sleepPressure = cachedRenderState.profileID == profileID
            ? cachedRenderState.sleepPressure
            : nil
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
        let sleepMiniPlan = cachedRenderState.profileID == profileID
            ? cachedRenderState.sleepMiniPlan
            : nil
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
        let visibleCareTypes = Set(EventType.cases(for: profile?.profileType ?? .child).filter {
            !hiddenCareTypes.contains($0) && trackingPreferences.allows($0)
        })
        let pinnedQuickActionIDs = requirements.smartActions
            ? QuickLogActionPreferenceStore.pinnedActionIDs(profileID: profileID) : []
        let smartQuickActions = requirements.smartActions ? WidgetSnapshotService.makeQuickActions(
            profileID: profileID,
            profileType: profile?.profileType ?? .child,
            events: scopedEvents,
            pinnedActionIDs: pinnedQuickActionIDs,
            now: now
        ) : []
        let solidsProfileState = requirements.includes(.solids) ? profileID.flatMap { targetProfileID in
            solidsProfileStates.first { $0.profileID == targetProfileID }
        } : nil
        let solidsAccessLevel = requirements.includes(.solids) ? profile.map {
            SolidsTrackingService.accessLevel(
                for: $0,
                events: scopedEvents,
                state: solidsProfileState
            )
        } ?? .hidden : .hidden
        let endOfToday = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: todayStart
        ) ?? now
        let nextPlannedSolidMeal = requirements.includes(.solids) ? profileID.flatMap { targetProfileID in
            plannedSolidMeals.first {
                $0.profileID == targetProfileID && !$0.isCompleted && $0.scheduledAt <= endOfToday
            }
        } : nil
        let dueSolidAllergenProgress = requirements.includes(.solids) ? profileID.flatMap { targetProfileID in
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
        } : nil
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
            hasSolidHistory: hasSolidHistory,
            upcomingMedication: profileID.flatMap {
                requirements.medication
                    ? WatchStateFactory.upcomingMedication(profileID: $0, context: modelContext, now: now, lookbackHours: 24)
                    : nil
            },
            trackingPreferences: trackingPreferences,
            hiddenCareTypes: hiddenCareTypes,
            essentialsHistory: essentialsHistory
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
        let _ = TodayPresentationAudit.event("TodayBody")
        let state = cachedRenderState
        let todayEvents = state.todayEvents
        let activeEvents = state.activeEvents
        let prediction = state.prediction
        let profile = state.profile
        let trackingPreferences = state.trackingPreferences
        let _ = InteractionPerformanceAudit.count("today.layout.\(trackingPreferences.layout.rawValue)")
        let visibleSections = state.visibleCareSections(
            preferences: trackingPreferences,
            hidden: state.hiddenCareTypes, now: displayDate
        )

        let listContent = ScrollViewReader { scrollProxy in
            List {
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Good \(greeting), \(activeCaregiverName)")
                                .font(trackingPreferences.layout == .essentials ? .headline : .title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            if let profile {
                                Text("\(profile.name) · \(profile.profileSubtitle)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .layoutPriority(1)
                        Spacer()
                        if let profile, trackingPreferences.shows(.timeline) {
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
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityLabel("\(todayEvents.count) logs today for \(profile.name)")
                            .accessibilityHint("Jumps to today's timeline")
                        }
                    }
                    .padding(.horizontal, 8)
                    .interactionScrollAudit("today")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: trackingPreferences.layout == .essentials ? 4 : 8,
                        leading: 0,
                        bottom: trackingPreferences.layout == .essentials ? 0 : 4,
                        trailing: 0
                    ))
                    .listRowSeparator(.hidden)
                    if trackingPreferences.shows(.weather) {
                        TodayWeatherHeader(chooseCity: {
                            DeepLinkRouter.shared.weatherProfileID = ProfileService.shared.selectedProfileID
                            DeepLinkRouter.shared.showingWeather = true
                        })
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                }
                .listSectionSpacing(0)

                if profile == nil {
                    noProfileSection
                } else {
                    if visibleSections.isEmpty {
                        Section {
                            emptyCareView(state, preferences: trackingPreferences)
                            .padding(.top, verticalSizeClass == .compact ? 16 : 64)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    if trackingPreferences.layout == .essentials, trackingPreferences.shows(.activeTimers) {
                        essentialsTimersSection(state, preferences: trackingPreferences)
                    }
                    if trackingPreferences.layout == .essentials, visibleSections.contains(.actions) {
                        essentialsActionsSection(state, preferences: trackingPreferences)
                    }
                    medicationDueSection(state, preferences: trackingPreferences)
                    if trackingPreferences.layout == .full, trackingPreferences.shows(.activeTimers) {
                        activeTimersSection(activeEvents)
                    }
                    if trackingPreferences.shows(.solids) { solidsTodaySection(state) }

                    if state.isDogProfile {
                        if trackingPreferences.shows(.summary) { dogTodaySummarySection(state) }
                        if trackingPreferences.shows(.guides) { puppyStageGuideSection(state) }
                    }

                    if trackingPreferences.shows(.prediction), profile?.profileType == .child,
                       !state.activeEvents.contains(where: { $0.isSleepBlock }) {
                        Section {
                            PredictionCard(
                                prediction: prediction,
                                babyName: profile?.name ?? "Baby",
                                awakeSinceDate: state.awakeSinceDate,
                                sleepPressure: state.sleepPressure,
                                alertStatusText: notificationManager.statusText(
                                    prediction: prediction,
                                    profileID: state.profileID,
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

                    if trackingPreferences.layout == .full, visibleSections.contains(.actions) {
                        if state.isDogProfile {
                            dogQuickActionsSection(state)
                        } else if profile?.profileType == .adult {
                            adultQuickActionsSection(state)
                        } else {
                            childQuickActionsSection(state)
                        }
                    }

                    if trackingPreferences.shows(.sleepPlan) { sleepMiniPlanSection(state) }
                    if trackingPreferences.shows(.routines) { careRoutinesSection(state) }

                    if trackingPreferences.shows(.timeline) {
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
                                            activeTimerToEdit = editableTimer(event)
                                        } else {
                                            editorRoute = EventEditorRoute(type: event.type, event: event)
                                        }
                                    } label: {
                                        EventRow(event: event)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier(
                                        "today-timeline.event.\(event.type.rawValue)"
                                    )
                                    .accessibilityValue(event.id.uuidString)
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
                    }

                    if !state.isDogProfile, trackingPreferences.shows(.guides) {
                        monthlyAgeGuideSection(state)
                    }

                    if trackingPreferences.shows(.appointments) { appointmentsSection(state) }
                }
            }
                .listStyle(.insetGrouped)
                .contentMargins(
                    .horizontal,
                    todayListContentHorizontalMargin,
                    for: .scrollContent
                )
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
        }

        let effectiveDisplayMode: TodayDisplayMode = profile == nil
            ? .home
            : deepLinkRouter.todayDisplayMode

        let presentedContent = VStack(spacing: 0) {
            if profile != nil {
                TodayDisplayModePicker(selection: Binding(get: { deepLinkRouter.todayDisplayMode }, set: { deepLinkRouter.todayDisplayMode = $0 }))
                    .padding(.horizontal, todayContentHorizontalMargin)
                Divider()
            }

            // The empty render cache is not a Home-mode request. Resolve the
            // initial profile first instead of building and querying Home only
            // to discard it when the care snapshot arrives in this update cycle.
            if !hasCompletedInitialSetup {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if effectiveDisplayMode == .care {
                listContent
                    .interactionPaintProbe("today.ready")
            } else if let householdID = households.first?.id {
                TodayHomeSummaryDataLoader(
                    householdID: householdID,
                    currentCaregiverName: activeCaregiverName
                ) { summary in
                    TodayHomeSummaryView(
                        summary: summary,
                        householdID: householdID,
                        caregiverName: activeCaregiverName,
                        open: openTodayHomeRoute,
                        openMedicationDose: deepLinkRouter.openMedicationDose
                    )
                }
            } else {
                ContentUnavailableView(
                    "Preparing your home",
                    systemImage: "house",
                    description: Text("Little Windows is setting up your household workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AppTheme.background
                .ignoresSafeArea()
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let profile {
                    TodayProfileMenu(profile: profile,
                        timers: activeEvents.map { .init(id: $0.id, title: $0.type.displayName) },
                        labelWidth: todayMenuLabelWidth, presentation: careCustomization,
                        logActivity: { type in performEssentialAction(type, state: cachedRenderState) },
                        editTimer: { id in
                            guard let event = cachedRenderState.activeEvents.first(where: { $0.id == id }) else { return }
                            activeTimerToEdit = editableTimer(event)
                        }, openSettings: { deepLinkRouter.presentSettings() },
                        customizationDismissed: {
                            guard renderStateRefreshPending else { return }
                            categoryPreferenceRevision += 1
                            scheduleRenderStateRefresh()
                        })
                } else {
                    ProfileToolbarSettingsButton(profile: nil) {
                        deepLinkRouter.presentSettings()
                    }
                }
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
        .sheet(isPresented: $showingMedications) {
            if let profile {
                NavigationStack {
                    MedicationsView(profile: profile)
                }
            }
        }
        .sheet(item: $appointmentToOpen) { appointment in
            NavigationStack {
                AppointmentDetailView(appointment: appointment)
            }
        }
        .sheet(item: $selectedMilestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template, profileID: profile?.id)
            }
        }
        .sheet(item: $puppyGuideToOpen) { guide in
            NavigationStack {
                PuppyStageGuideDetailView(
                    guide: guide,
                    profile: puppyGuideProfileToOpen ?? profile,
                    showsCloseButton: true
                )
            }
        }
        .sheet(isPresented: $showingProfileEditor) {
            NavigationStack {
                ProfileEditorView()
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
            options: showingActivityChooser ? activityOptions(state: state) : [],
            onDismiss: presentPendingActivityEditor
        )
        .appActionSheet(
            isPresented: $showingAlertPermissionPrompt,
            title: "Turn on Little Window Alerts?",
            message: "Little Windows can remind you before \(profile?.name ?? "your baby")'s next likely nap or bedtime window.",
            systemImage: "bell.badge.fill",
            tint: .purple,
            options: [
                AppActionSheetOption(
                    title: "Allow Notifications",
                    subtitle: "Continue to the iOS notification permission prompt.",
                    systemImage: "bell.badge.fill",
                    tint: .purple
                ) {
                    Task { await enableLittleWindowAlerts() }
                }
            ],
            cancelTitle: "Not Now"
        )
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

        return lifecycleView(presentedContent, state: state)
    }

    private func lifecycleView<Content: View>(
        _ content: Content,
        state: TodayRenderState
    ) -> some View {
        content
        .onChange(of: deepLinkRouter.pendingAction) { _, _ in
            handlePendingDeepLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { notification in
            guard notification.object as? UUID == state.profileID,
                  CareTrackingPreferenceStore.affectsCare(notification) else { return }
            if careCustomization.isPresented {
                renderStateRefreshPending = true
                return
            }
            categoryPreferenceRevision += 1
            scheduleRenderStateRefresh()
        }
        .onChange(of: preferenceRevision) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: deepLinkRouter.showingSettings) { _, showing in
            if !showing && renderStateRefreshPending { scheduleRenderStateRefresh() }
        }
        .onChange(of: showingProfileEditor) { _, showing in
            if !showing && renderStateRefreshPending { scheduleRenderStateRefresh() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave)
                .receive(on: RunLoop.main)
        ) { notification in
            // Event and timer workflows publish their exact optimistic state
            // before isolated persistence begins. Their worker saves must not
            // trigger a redundant full Today rebuild while system surfaces are
            // still synchronizing.
            guard localEventMutationCount == 0,
                  !timerMutationRenderDeferralActive,
                  timerSystemRefreshTask == nil,
                  saveNotificationAffectsToday(notification) else { return }
            scheduleRenderStateRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            // Drop pending, nonessential history work first. SwiftData fetches
            // already inside the framework cannot be force-cancelled, but this
            // prevents another scan from starting while iOS is under pressure.
            renderStateRefreshTask?.cancel()
            renderStateRefreshTask = nil
            invalidateIntegrationAnalysis()
            SystemIntegrationReconciler.invalidateInFlightReconciliation()
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
        .task(id: deepLinkRouter.isDataReady) {
            guard deepLinkRouter.isDataReady, !hasCompletedInitialSetup else { return }
            hasCompletedInitialSetup = true
            // RootView creates the household after onboarding. Creating one
            // here races the empty-store onboarding check and can suppress it.
            _ = profileService.ensureSelection(in: profiles)
            refreshCachedRenderState()
            refreshActiveSleepPlan()
            handlePendingProfileSwitch()
            handlePendingDeepLink()
            handlePendingAppointmentDeepLink()
            handlePendingPuppyGuideDeepLink()
            handlePendingRoutineDeepLink()
            guard !Task.isCancelled else { return }
            await syncActiveSleepPlanWakeAlert()
        }
        .task(id: state.profileID) {
            var elapsedMinutes = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                elapsedMinutes += 1
                // Timeline labels need a minute tick; sleep-pressure analysis
                // does not. Refresh that bounded history scan every five
                // minutes, while model saves still refresh it after real data
                // changes.
                let now = Date()
                let crossedDay = !Calendar.current.isDate(displayDate, inSameDayAs: now)
                displayDate = now
                let reachedFutureEntry = cachedRenderState.essentialsHistory.nextTransition.map { $0 <= now } ?? false
                if cachedRenderState.renderRequirements.historyOnMinuteTick || crossedDay || reachedFutureEntry {
                    InteractionPerformanceAudit.count("today.minute-history-build")
                    refreshCachedRenderState(refreshesAnalysis: elapsedMinutes.isMultiple(of: 5))
                } else if !renderStateRefreshIsDeferred, cachedRenderState.renderRequirements.medication,
                          let profileID = cachedRenderState.profileID {
                    // Relative labels have their own TimelineView; only dose
                    // availability can change without a care-history save.
                    cachedRenderState.upcomingMedication = WatchStateFactory.upcomingMedication(
                        profileID: profileID, context: modelContext, now: now, lookbackHours: 24)
                }
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

                    Text("Add a child, adult, or dog profile to start logging care, or import an existing backup from Settings.")
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
        if !state.isDogProfile,
           !state.activeEvents.contains(where: { $0.isSleepBlock }),
           let plan = state.sleepMiniPlan {
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
                    // Keep this destination local so Today refreshes don't
                    // repeatedly register a stack-wide FoodRoute handler.
                    NavigationLink {
                        todaySolidsDestination(.solidsHome, state: state)
                    } label: {
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
                    progress: [],
                    plans: plannedSolidMeals,
                    eventItems: [],
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

    private func openTodayHomeRoute(_ route: TodayHomeSummaryRoute) {
        switch route {
        case .food(let command):
            deepLinkRouter.openFood(command)
        case .appointment(let appointmentID, let profileID):
            deepLinkRouter.openAppointment(appointmentID, profileID: profileID)
        case .medications(let profileID):
            deepLinkRouter.openMedications(profileID: profileID)
        case .medication(let medicationID, let profileID):
            deepLinkRouter.openMedication(medicationID, profileID: profileID)
        case .routines(let profileID):
            deepLinkRouter.openRoutines(profileID: profileID)
        case .plannedSolidMeal(let mealID, let profileID):
            deepLinkRouter.openSolids(
                .plannedSolidMeal(mealID),
                profileID: profileID,
                returningTo: .today
            )
        case .solidAllergen(let allergenID, let profileID):
            deepLinkRouter.openSolids(
                .solidAllergen(allergenID),
                profileID: profileID,
                returningTo: .today
            )
        case .todayCare:
            deepLinkRouter.selectTodayCare()
        }
    }

    private func solidsCommand(for route: FoodRoute) -> FoodRouteCommand? {
        switch route {
        case .solidsHome: .solids
        case .solidsDatabase: .solidsDatabase
        case .solidsGuided: .solidsGuided
        case .solidsDigestive: .solidsDigestive
        case .solidFood(let id): .solidFood(id)
        case .customSolidFood(let id): .customSolidFood(id)
        case .solidsPlan: .solidsPlan
        case .plannedSolidMeal(let id): .plannedSolidMeal(id)
        case .solidsTracker(let initialFilter): .solidsTracker(initialFilter)
        case .solidMeal(let id): .solidMeal(id)
        case .solidsAllergens: .solidsAllergens
        case .solidAllergen(let id): .solidAllergen(id)
        case .solidsRecipes: .solidsRecipes
        case .solidsRecipe(let id): .solidsRecipe(id)
        case .solidFoodHistory, .todoList, .shoppingList, .shoppingMode,
             .packingTrip, .packingList, .itineraryItem, .inventoryItem, .mealPrepItem, .returnRequest,
             .store, .reminders:
            nil
        }
    }

    @ViewBuilder
    private func emptyCareView(_ state: TodayRenderState, preferences: CareTrackingPreferences) -> some View {
        let hidden = CareCategoryPreferenceStore.hiddenTypes(profileID: state.profileID)
        let allHidden = !CareTodaySection.allCases.contains {
            $0.applies(to: state.profile?.profileType ?? .child) && preferences.shows($0)
        }
        let noEssentials = preferences.layout == .essentials && preferences.shows(.actions)
        let noChoices = preferences.configuredEssentials(for: state.profile?.profileType ?? .child, hidden: hidden).isEmpty
        ContentUnavailableView {
            Label(allHidden ? "All sections are hidden" : noEssentials
                  ? (noChoices ? "Choose your essentials" : "Your essentials are paused")
                  : "Nothing to show right now", systemImage: "slider.horizontal.3")
        } description: {
            if allHidden {
                Text("Choose what to show in your \(preferences.layout.title) layout. Your records are still available in Reports.")
            } else if noEssentials && noChoices {
                Text("Add the activities you want to keep on Today in Activities & Button Order. Your records are still available in Reports.")
            } else if noEssentials {
                Text("Resume an activity in Tracking & Reminders, or choose different essentials. Your records stay saved.")
            } else {
                Text("Your visible sections have no updates. Customize Today to show logging buttons or other sections. Your records are still available in Reports.")
            }
        } actions: {
            Button("Customize Today") { careCustomization.isPresented = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("today.empty.customize")
        }
    }

    @ViewBuilder
    private func essentialsTimersSection(_ state: TodayRenderState, preferences: CareTrackingPreferences) -> some View {
        let timers = state.compactEssentialTimers(preferences: preferences,
            hidden: state.hiddenCareTypes)
        if !timers.isEmpty {
            Section {
                ForEach(timers) { event in
                    Button {
                        activeTimerToEdit = editableTimer(event)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: event.type.systemImage(for: event.profileTypeSnapshot))
                                .foregroundStyle(event.type.tint)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.displayTitle).font(.headline)
                                Text(event.isTimerRunning ? "Running timer · tap to manage" : "Stopped timer · tap to finish")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Group {
                                if event.isTimerRunning {
                                    Text(event.timerDisplayStartDate(), style: .timer)
                                } else {
                                    Text(DurationFormatting.liveString(seconds: event.timerElapsed()))
                                }
                            }
                            .font(.body.monospacedDigit())
                            .foregroundStyle(event.type.tint)
                            .fixedSize()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                        .contentShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.running-timer.\(event.type.rawValue)")
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listSectionSpacing(0)
        }
    }

    @ViewBuilder
    private func medicationDueSection(_ state: TodayRenderState, preferences: CareTrackingPreferences) -> some View {
        if preferences.showsMedicationDueCard(
            scheduledAt: state.upcomingMedication?.scheduledAt,
            profileType: state.profile?.profileType ?? .child,
            hidden: state.hiddenCareTypes
        ) {
            Section {
                EssentialsActionButton(
                    type: .medicine, profileType: state.profile?.profileType ?? .child,
                    detail: essentialDetail(.medicine, state: state, now: Date()), count: 4
                ) {
                    performEssentialAction(.medicine, state: state)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "Medication due")
            }
        }
    }

    private func essentialsActionsSection(_ state: TodayRenderState, preferences: CareTrackingPreferences) -> some View {
        let types = preferences.essentialTypes(
            for: state.profile?.profileType ?? .child,
            hidden: state.hiddenCareTypes
        )
        return Section {
            ForEach(types) { type in
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    EssentialsActionButton(
                        type: type,
                        profileType: state.profile?.profileType ?? .child,
                        detail: essentialDetail(type, state: state, now: context.date),
                        elapsedDuration: essentialElapsedDuration(type, state: state, now: context.date),
                        timerStart: state.activeTimer(of: type).flatMap {
                            $0.isTimerRunning ? $0.timerDisplayStartDate(at: context.date) : nil
                        },
                        stoppedTimerElapsed: state.activeTimer(of: type).flatMap {
                            $0.isTimerRunning ? nil : $0.timerElapsed(at: context.date)
                        },
                        count: types.count
                    ) {
                        performEssentialAction(type, state: state)
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listSectionSpacing(12)
    }

    private func essentialElapsedDuration(_ type: EventType, state: TodayRenderState, now: Date) -> String? {
        guard state.activeTimer(of: type) == nil else { return nil }
        if type == .medicine, state.upcomingMedication != nil { return nil }
        let date: Date?
        if type == .sleep || type == .rest {
            date = state.essentialsHistory.lastEndedDates[type] ?? state.essentialsHistory.latestRecords[type]?.date
        } else { date = state.essentialsHistory.latestRecords[type]?.date }
        guard let date, now.timeIntervalSince(date) >= 60 else { return nil }
        return TodayEssentialsEventDetail.durationText(seconds: now.timeIntervalSince(date))
    }

    private func essentialDetail(_ type: EventType, state: TodayRenderState, now: Date) -> String {
        if let timer = state.activeTimer(of: type) {
            return TodayEssentialsEventDetail.timerDetail(for: timer)
        }
        if type == .medicine, let dose = state.upcomingMedication {
            let time = dose.scheduledAt.formatted(date: .abbreviated, time: .shortened)
            return "\(dose.medicationName) · \(dose.scheduledAt <= now ? "Due" : "Next") \(time)"
        }
        if type == .sleep || type == .rest,
           let endedAt = state.essentialsHistory.lastEndedDates[type] {
            if now.timeIntervalSince(endedAt) < 60 { return "\(type.displayName) just ended" }
            return "Last \(type.displayName.lowercased()) ended \(TodayEssentialsEventDetail.durationText(seconds: now.timeIntervalSince(endedAt))) ago"
        }
        guard let record = state.essentialsHistory.latestRecords[type], record.date <= now else {
            return type == .medicine ? "Record a dose or review medications" : "No recent record · tap to log"
        }
        return state.essentialsHistory.recentDetail(for: type, now: now)
    }

    private func performEssentialAction(_ type: EventType, state: TodayRenderState) {
        guard let profileID = state.profileID,
              profileService.selectedProfile(in: profiles)?.id == profileID else {
            scheduleRenderStateRefresh()
            return
        }
        // A timer remains editable even if preferences change while its tile is visible.
        if let timer = state.activeTimer(of: type) {
            activeTimerToEdit = editableTimer(timer)
            return
        }
        switch type {
        case .sleep: showingSleepChooser = true
        case .nursing: showingNursingChooser = true
        case .pumping: startTimer(.pumping)
        case .activity: showingActivityChooser = true
        case .walk, .rest, .training, .grooming: startTimer(type)
        case .medicine:
            if let dose = state.upcomingMedication {
                deepLinkRouter.openMedicationDose(MedicationDoseRouteCommand(
                    profileID: dose.profileID, medicationID: dose.medicationID,
                    regimenID: dose.regimenID, phaseID: dose.phaseID,
                    occurrenceKey: dose.occurrenceKey, scheduledAt: dose.scheduledAt,
                    doseAmount: dose.doseAmount, doseUnit: dose.doseUnit
                ))
            } else if state.profile?.profileType == .adult {
                showingMedications = true
            } else {
                editorRoute = EventEditorRoute(type: .medicine)
            }
        default: editorRoute = EventEditorRoute(type: type)
        }
    }

    private func childQuickActionsSection(_ state: TodayRenderState) -> some View {
        Section {
            VStack(spacing: 14) {
                smartQuickActionsRow(state.smartQuickActions.filter { $0.id != "sleep" })

                if state.shows(.sleep) {
                    Button {
                        if let activeSleep = state.activeTimer(of: .sleep) {
                            activeTimerToEdit = editableTimer(activeSleep)
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
                    columns: quickActionGridColumns,
                    spacing: quickActionGridSpacing
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
                    if CareTrackingPreferenceStore.allowsPrompts(.appointments, profileID: state.profileID) {
                    QuickActionButton(title: "Visits", icon: "stethoscope", color: .indigo) {
                        showingAppointments = true
                    }
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

    private func adultQuickActionsSection(_ state: TodayRenderState) -> some View {
        Section {
            VStack(spacing: 14) {
                smartQuickActionsRow(state.smartQuickActions.filter { $0.id != "sleep" })
                LazyVGrid(
                    columns: quickActionGridColumns,
                    spacing: quickActionGridSpacing
                ) {
                    if state.shows(.medicine) {
                        QuickActionButton(title: "Medications", icon: "pills.fill", color: .red) {
                            showingMedications = true
                        }
                    }
                    adultHealthQuickAction(.symptom, title: "Symptom", color: .orange, state: state)
                    adultHealthQuickAction(.bloodPressure, title: "Blood pressure", color: .red, state: state)
                    adultHealthQuickAction(.heartRate, title: "Pulse", color: .pink, state: state)
                    adultHealthQuickAction(.oxygenSaturation, title: "Oxygen", color: .blue, state: state)
                    adultHealthQuickAction(.respiratoryRate, title: "Respiratory", color: .cyan, state: state)
                    adultHealthQuickAction(.glucose, title: "Glucose", color: .purple, state: state)
                    adultHealthQuickAction(.temperature, title: "Temperature", color: .red, state: state)
                    adultHealthQuickAction(.pain, title: "Pain", color: .orange, state: state)
                    adultHealthQuickAction(.growth, title: "Weight & height", color: .mint, state: state)
                    if state.shows(.sleep) {
                        QuickActionButton(
                            title: "Sleep",
                            subtitle: state.hasActiveTimer(of: .sleep)
                                ? "Timer active"
                                : lastEventSubtitle(.sleep, state: state),
                            icon: "moon.stars.fill",
                            color: .indigo
                        ) {
                            if let activeSleep = state.activeTimer(of: .sleep) {
                                activeTimerToEdit = editableTimer(activeSleep)
                            } else {
                                showingSleepChooser = true
                            }
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
                    if CareTrackingPreferenceStore.allowsPrompts(.appointments, profileID: state.profileID) {
                    QuickActionButton(title: "Visits", icon: "stethoscope", color: .indigo) {
                        showingAppointments = true
                    }
                    }
                    if state.shows(.custom) {
                        adultHealthQuickAction(.custom, title: "Custom", color: .gray, state: state)
                    }
                }
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Log care or health")
        } footer: {
            Text("Use Medications for scheduled and as-needed doses so reminders, history, and supply stay together.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func adultHealthQuickAction(
        _ type: EventType,
        title: String,
        color: Color,
        state: TodayRenderState
    ) -> some View {
        if state.shows(type) {
            QuickActionButton(
                title: title,
                subtitle: lastEventSubtitle(type, state: state),
                icon: type.systemImage(for: .adult),
                color: color
            ) {
                editorRoute = EventEditorRoute(type: type)
            }
        }
    }

    private func dogQuickActionsSection(_ state: TodayRenderState) -> some View {
        Section {
            VStack(spacing: 14) {
                smartQuickActionsRow(state.smartQuickActions)

                LazyVGrid(
                    columns: quickActionGridColumns,
                    spacing: quickActionGridSpacing
                ) {
                    ForEach(TodayDogQuickActionCatalog.enabledTypes(in: state.visibleCareTypes)) { type in
                        dogQuickAction(type, state: state)
                    }
                }
            }
            .padding(14)
            .appSurface()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            AppSectionHeader(title: "Log something")
        } footer: {
            Text("Walk, training, rest, and grooming timers use the same Live Activity and widget controls. No GPS route tracking or location permission is used.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func dogQuickAction(_ type: EventType, state: TodayRenderState) -> some View {
        switch type {
        case .potty:
            QuickActionButton(
                title: "Pee",
                subtitle: dogPottySubtitle(.pee, state: state),
                icon: "pawprint.fill",
                color: .teal
            ) {
                logDogPotty(.pee, accident: false)
            }
            .accessibilityIdentifier("dog-quick-action-potty-pee")
            QuickActionButton(
                title: "Poop",
                subtitle: dogPottySubtitle(.poop, state: state),
                icon: "pawprint.circle.fill",
                color: .teal
            ) {
                logDogPotty(.poop, accident: false)
            }
            .accessibilityIdentifier("dog-quick-action-potty-poop")
            QuickActionButton(
                title: "Accident",
                subtitle: dogPottySubtitle(.pee, state: state, accident: true),
                icon: "exclamationmark.triangle.fill",
                color: .orange
            ) {
                logDogPotty(.pee, accident: true)
            }
            .accessibilityIdentifier("dog-quick-action-potty-accident")
        case .walk, .rest, .training, .grooming:
            QuickActionButton(
                title: type == .walk ? "Start Walk" : type.displayName,
                subtitle: state.hasActiveTimer(of: type)
                    ? "Timer active"
                    : lastEventSubtitle(type, state: state),
                icon: type.systemImage(for: .dog),
                color: type.tint,
                isEnabled: !state.hasActiveTimer(of: type)
            ) {
                startTimer(type)
            }
            .accessibilityIdentifier("dog-quick-action-\(type.rawValue)")
        case .food, .water, .treat, .medicine, .symptom, .growth,
             .temperature, .vaccine, .glucose, .custom:
            QuickActionButton(
                title: type.displayName,
                subtitle: lastEventSubtitle(type, state: state),
                icon: type.systemImage(for: .dog),
                color: type.tint
            ) {
                editorRoute = EventEditorRoute(type: type)
            }
            .accessibilityIdentifier("dog-quick-action-\(type.rawValue)")
        case .sleep, .feed, .nursing, .pumping, .diaper, .activity,
             .bloodPressure, .heartRate, .oxygenSaturation, .respiratoryRate, .pain:
            EmptyView()
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

                if usesWideIPadLayout {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 12),
                            count: 4
                        ),
                        spacing: 12
                    ) {
                        ForEach(visibleActions) { action in
                            smartQuickActionTile(action, fillsWidth: true)
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(visibleActions) { action in
                                smartQuickActionTile(action, fillsWidth: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func smartQuickActionTile(
        _ action: QuickLogActionSnapshot,
        fillsWidth: Bool
    ) -> some View {
        let tint = smartQuickActionColor(action.tintName)
        return ZStack(alignment: .topTrailing) {
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
            .frame(width: fillsWidth ? nil : 136, height: 48)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
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
        .frame(width: fillsWidth ? nil : 136, height: 48)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func dogTodaySummarySection(_ state: TodayRenderState) -> some View {
        let preferences = CareTrackingPreferenceStore.preferences(profileID: state.profileID)
        if [EventType.food, .water, .potty, .walk, .medicine].contains(where: preferences.allows) {
            Section {
                LazyVGrid(columns: summaryGridColumns, spacing: 10) {
                    if preferences.allows(.food) {
                        DogSummaryCard(title: "Last food", value: dogLastEventTitle(.food, state: state), icon: "fork.knife", color: .orange)
                    }
                    if preferences.allows(.water) {
                        DogSummaryCard(title: "Last water", value: dogLastEventTitle(.water, state: state), icon: "drop.fill", color: .cyan)
                    }
                    if preferences.allows(.potty) {
                        DogSummaryCard(title: "Last pee", value: dogPottyTitle(.pee, state: state), icon: "pawprint.fill", color: .teal)
                    }
                    if preferences.allows(.potty) {
                        DogSummaryCard(title: "Last poop", value: dogPottyTitle(.poop, state: state), icon: "pawprint.circle.fill", color: .teal)
                    }
                    if preferences.allows(.walk) {
                        DogSummaryCard(title: "Last walk", value: dogLastEventTitle(.walk, state: state), icon: "figure.walk", color: .green)
                    }
                    if preferences.allows(.medicine) {
                        DogSummaryCard(title: "Medicine", value: dogLastEventTitle(.medicine, state: state), icon: "cross.case.fill", color: .red)
                    }
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
    }

    @ViewBuilder
    private func activeTimersSection(_ events: [CareEvent]) -> some View {
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
            manage: { presentRoutineManager() }
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

    private func activeTimerCard(for event: CareEvent) -> some View {
        ActiveTimerCard(
            event: event,
            planWakeAlert: wakeAlert(for: event),
            edit: { activeTimerToEdit = editableTimer(event) },
            toggleRunning: {
                event.isTimerRunning ? stop(event) : resume(event)
            },
            save: { save(event) },
            switchNursingSide: nursingSideSwitcher(for: event),
            setNursingSide: nursingSideSetter(for: event)
        )
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func activeTimerEditor(for event: CareEvent) -> some View {
        ActiveTimerEditorView(
            event: event,
            adjustStart: { date in adjustStart(of: event, to: date) },
            stop: { stop(event) },
            resume: { resume(event) },
            reset: { reset(event) },
            save: { endDate in save(event, endDate: endDate) },
            discard: { discardTimer(event) },
            setStartTimeZone: { setStartTimeZone($0, for: event) },
            setEndTimeZone: { setEndTimeZone($0, for: event) },
            setSleepConditions: { conditions in
                let draft = timerDraftForMutation(event)
                draft.sleepConditions = conditions
                persistTimerMutation(draft)
            },
            setSleepPredictionExclusion: { excluded in
                let draft = timerDraftForMutation(event)
                draft.excludeFromSleepPredictions = excluded
                draft.updatedAt = Date()
                persistTimerMutation(draft)
            },
            switchNursingSide: nursingSideSwitcher(for: event),
            setNursingSide: nursingSideSetter(for: event)
        )
    }

    private func editableTimer(_ event: CareEvent) -> CareEvent {
        event.modelContext == nil
            ? event
            : EventMutationService.detachedTimerCopy(event)
    }

    private func timerDraftForMutation(_ event: CareEvent) -> CareEvent {
        let draft = editableTimer(event)
        if activeTimerToEdit?.id == event.id, activeTimerToEdit !== draft {
            activeTimerToEdit = draft
        }
        return draft
    }

    private func nursingSideSwitcher(for event: CareEvent) -> (() -> Void)? {
        guard event.type == .nursing else { return nil }
        return { switchNursingSide(event) }
    }

    private func nursingSideSetter(for event: CareEvent) -> ((NursingSide) -> Void)? {
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
    ) -> CareEvent? {
        if let existingTimer = activeTimer(of: type) {
            if presentsEditor {
                activeTimerToEdit = editableTimer(existingTimer)
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
            context: modelContext,
            insertIntoContext: false
        )
        if let created {
            if presentsEditor {
                activeTimerToEdit = created
            }
            timerMutationRenderDeferralActive = true
            applyActiveTimerMutationToCachedRenderState(created)
            scheduleTimerSystemRefresh(
                events: scopedEvents,
                activeTimers: activeEvents,
                scheduleNotification: EventMutationService.shouldRefreshLittleWindowAlert(
                    after: created
                ),
                persistenceRequest: EventMutationService.timerPersistenceRequest(for: created),
                syncWakeAlert: created.isSleepBlock
            )
            return created
        } else {
            duplicateTimerMessage = "A \(type.displayName.lowercased()) timer is already running."
            return nil
        }
    }

    private func activeTimer(of type: EventType) -> CareEvent? {
        cachedRenderState.activeTimer(of: type)
    }

    private func logDogPotty(_ pottyType: DogPottyType, accident: Bool) {
        var details = DogEventDetails()
        details.pottyType = pottyType
        details.pottyLocation = accident ? .indoorAccident : .outside
        details.accident = accident
        let now = Date()
        let timeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        let event = CareEvent(
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
        WatchConnectivityService.shared.scheduleCurrentStatePublish()
    }

    private func scheduleRenderStateRefresh() {
        renderStateRefreshPending = true
        guard renderStateRefreshTask == nil, !renderStateRefreshIsDeferred else { return }
        // Coalesce notifications in this update cycle. A covering editor owns
        // its UI; dismissal explicitly requests the pending refresh, without a
        // polling timer or an arbitrary wait after saving.
        renderStateRefreshTask = Task { @MainActor in
            renderStateRefreshTask = nil
            guard !Task.isCancelled, renderStateRefreshPending, !renderStateRefreshIsDeferred else { return }
            renderStateRefreshPending = false
            refreshCachedRenderState()
            timerMutationRenderDeferralActive = false
        }
    }

    private func saveNotificationAffectsToday(_ notification: Notification) -> Bool {
        let keys: [ModelContext.NotificationKey] = [
            .insertedIdentifiers,
            .updatedIdentifiers,
            .deletedIdentifiers,
            .invalidatedAllIdentifiers
        ]
        var identifiers = [PersistentIdentifier]()
        for key in keys {
            if let values = notification.userInfo?[key] as? [PersistentIdentifier] {
                identifiers.append(contentsOf: values)
            } else if let values = notification.userInfo?[key]
                as? Set<PersistentIdentifier> {
                identifiers.append(contentsOf: values)
            } else if let values = notification.userInfo?[key.rawValue]
                as? [PersistentIdentifier] {
                identifiers.append(contentsOf: values)
            } else if let values = notification.userInfo?[key.rawValue]
                as? Set<PersistentIdentifier> {
                identifiers.append(contentsOf: values)
            }
        }

        // Some framework-generated saves omit identifier details. Preserve the
        // prior safe behavior for those instead of risking a stale timeline.
        guard !identifiers.isEmpty else { return true }
        return identifiers.contains {
            let entityName = $0.entityName
            return Self.todayRelevantEntityNames.contains(entityName)
                || Self.todayRelevantEntityNames.contains {
                    entityName.hasSuffix(".\($0)")
                }
        }
    }

    private static let todayRelevantEntityNames: Set<String> = [
        CareProfile.self,
        CareEvent.self,
        DoctorAppointment.self,
        SleepPredictionRecord.self,
        AgeGuideReadState.self,
        PuppyStageGuideReadState.self,
        CareRoutine.self,
        CareRoutineStep.self,
        CareRoutineRun.self,
        Household.self,
        PlannedSolidMeal.self,
        SolidsProfileState.self,
        SolidAllergenProgress.self,
        Medication.self,
        MedicationRegimen.self,
        MedicationSchedulePhase.self,
        MedicationDoseRecord.self
    ].map { String(describing: $0) }.reduce(into: Set<String>()) {
        $0.insert($1)
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
                context: modelContext,
                insertIntoContext: false
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

    private func stop(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventMutationService.stopTimer(draft, context: modelContext)
        persistTimerMutation(draft, syncWakeAlert: true)
    }

    private func resume(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventMutationService.resumeTimer(draft, context: modelContext)
        persistTimerMutation(draft, syncWakeAlert: true)
    }

    private func reset(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventMutationService.resetTimer(draft, context: modelContext)
        persistTimerMutation(draft, syncWakeAlert: true)
    }

    private func setStartTimeZone(_ identifier: String, for event: CareEvent) {
        let draft = timerDraftForMutation(event)
        draft.startTimeZoneIdentifier = identifier
        persistTimerMutation(draft)
    }

    private func setEndTimeZone(_ identifier: String, for event: CareEvent) {
        let draft = timerDraftForMutation(event)
        draft.endTimeZoneIdentifier = identifier
        persistTimerMutation(draft)
    }

    @discardableResult
    private func save(_ event: CareEvent, endDate: Date? = nil) -> Bool {
        let draft = timerDraftForMutation(event)
        let didFinish = EventMutationService.saveTimer(
            draft,
            context: modelContext,
            endDate: endDate
        )
        guard didFinish else {
            return !draft.isTimerDraft && draft.endDate != nil
        }
        timerMutationRenderDeferralActive = true
        applyCommittedTimerToCachedRenderState(draft)
        scheduleTimerSystemRefresh(
            events: scopedEvents,
            activeTimers: activeEvents,
            scheduleNotification: true,
            refreshPredictionFor: draft,
            persistenceRequest: EventMutationService.timerPersistenceRequest(for: draft),
            syncWakeAlert: true
        )
        return true
    }

    private func applyCommittedTimerToCachedRenderState(_ event: CareEvent) {
        invalidateIntegrationAnalysis()
        var state = cachedRenderState
        state.activeEvents.removeAll { $0.id == event.id }

        let now = Date()
        let logDate = event.endDate ?? event.startDate
        if event.occursOnLocalDay(now),
           !state.todayEvents.contains(where: { $0.id == event.id }) {
            state.todayEvents.append(event)
            state.todayEvents.sort { $0.startDate > $1.startDate }
        }
        if logDate <= now,
           state.lastLoggedDates[event.type].map({ logDate > $0 }) ?? true {
            state.lastLoggedDates[event.type] = logDate
        }

        if event.isSleepBlock {
            state.runningSleepTimer = nil
            state.isSleeping = false
            state.awakeSinceDate = event.endDate
            state.prediction = nil
            state.sleepPressure = nil
            state.sleepMiniPlan = nil
        }
        state.essentialsHistory = .make(events: state.scopedEvents, now: now)
        state.essentialsHistory.include(event, now: now)
        cachedRenderState = state
    }

    private func persistTimerMutation(
        _ event: CareEvent,
        syncWakeAlert: Bool = false
    ) {
        timerMutationRenderDeferralActive = true
        applyActiveTimerMutationToCachedRenderState(event)
        scheduleTimerSystemRefresh(
            events: scopedEvents,
            activeTimers: activeEvents,
            scheduleNotification: EventMutationService.shouldRefreshLittleWindowAlert(
                after: event
            ),
            persistenceRequest: EventMutationService.timerPersistenceRequest(for: event),
            syncWakeAlert: syncWakeAlert
        )
    }

    private func applyActiveTimerMutationToCachedRenderState(_ event: CareEvent) {
        invalidateIntegrationAnalysis()
        var state = cachedRenderState
        if let index = state.scopedEvents.firstIndex(where: { $0.id == event.id }) {
            state.scopedEvents[index] = event
        } else {
            state.scopedEvents.append(event)
            state.scopedEvents.sort { $0.startDate > $1.startDate }
        }
        if let index = state.activeEvents.firstIndex(where: { $0.id == event.id }) {
            state.activeEvents[index] = event
        } else {
            state.activeEvents.append(event)
            state.activeEvents.sort { $0.startDate < $1.startDate }
        }
        if event.isSleepBlock {
            state.runningSleepTimer = event.isTimerRunning ? event : nil
            state.isSleeping = event.isTimerRunning
            state.awakeSinceDate = event.isTimerRunning ? nil : event.updatedAt
        }
        cachedRenderState = state
    }

    private func scheduleTimerSystemRefresh(
        events: [CareEvent],
        activeTimers: [CareEvent],
        scheduleNotification: Bool,
        refreshPredictionFor event: CareEvent? = nil,
        persistenceRequest: TimerPersistenceRequest? = nil,
        syncWakeAlert: Bool,
        discardedTimerID: UUID? = nil
    ) {
        timerSystemRefreshTask?.cancel()
        let refreshRevision = UUID()
        timerSystemRefreshRevision = refreshRevision
        let currentProfile = profile
        let currentSettings = predictionSettings
        let alertsEnabled = notificationsEnabled
        let leadMinutes = notificationLeadMinutes
        let surfaceRevision = Date()
        let timerSnapshot = WidgetSnapshotService.refreshActiveTimerState(
            profile: currentProfile,
            events: activeTimers,
            now: surfaceRevision
        )
        let container = modelContext.container
        let currentPrediction = prediction
        let profileID = currentProfile?.id
        let profileName = currentProfile?.name ?? "Baby"
        let hasSleepDraft = activeTimers.contains {
            $0.isSleepBlock && $0.isTimerDraft
        }
        let hasRunningSleepDraft = activeTimers.contains {
            $0.isSleepBlock && $0.isTimerRunning
        }

        // ActivityKit coordination can take several seconds. Dispatching it
        // independently preserves mutation ordering through the snapshot
        // revision without retaining the SwiftUI interaction transaction.
        Task.detached(priority: .utility) {
            await LiveActivityManager.shared.synchronize(
                timer: timerSnapshot,
                revision: surfaceRevision
            )
        }

        if event == nil {
            // Draft changes are a one-row durable write followed by optional
            // system notifications. A discarded draft uses the same fast path:
            // it never changed historical prediction inputs, so rebuilding the
            // entire profile here only burns CPU while Today is scrolling.
            timerSystemRefreshTask = Task.detached(priority: .userInitiated) {
                let persisted: Bool
                if let persistenceRequest {
                    persisted = await EventMutationService.persistTimerMutation(
                        persistenceRequest,
                        container: container
                    )
                } else {
                    persisted = true
                }
                guard !Task.isCancelled else { return }

                let shouldContinue = await MainActor.run {
                    guard timerSystemRefreshRevision == refreshRevision else { return false }
                    timerMutationRenderDeferralActive = false
                    if !persisted {
                        if let discardedTimerID {
                            EventVisibilityStore.restore(discardedTimerID)
                        }
                        refreshCachedRenderState()
                        timerSystemRefreshTask = nil
                    }
                    return persisted
                }
                guard shouldContinue, !Task.isCancelled else { return }

                if scheduleNotification {
                    await NotificationManager.shared.schedule(
                        prediction: currentPrediction,
                        babyName: profileName,
                        profileID: profileID,
                        leadMinutes: leadMinutes,
                        enabled: alertsEnabled,
                        isSleeping: hasSleepDraft
                    )
                }
                guard !Task.isCancelled else { return }
                WatchConnectivityService.shared.scheduleCurrentStatePublish()
                if syncWakeAlert {
                    if hasRunningSleepDraft {
                        await syncActiveSleepPlanWakeAlert()
                    } else {
                        await NotificationManager.shared.cancelActiveSleepPlanWakeAlert(
                            profileID: profileID
                        )
                    }
                }
                if discardedTimerID != nil {
                    // Restore pressure/day-ahead details with one low-priority
                    // scan only after a cold launch that had no pre-timer
                    // analysis to retain. A draft never changes historical
                    // inputs, so the normal discard path needs no rebuild.
                    await MainActor.run {
                        if cachedRenderState.sleepPressure == nil,
                           cachedRenderState.sleepMiniPlan == nil {
                            scheduleIntegrationAnalysisRefresh()
                        }
                    }
                }
                await MainActor.run {
                    guard timerSystemRefreshRevision == refreshRevision else { return }
                    timerSystemRefreshTask = nil
                }
            }
            return
        }

        timerSystemRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            if let persistenceRequest,
               !(await EventMutationService.persistTimerMutation(
                    persistenceRequest,
                    container: modelContext.container
               )) {
                if let discardedTimerID {
                    EventVisibilityStore.restore(discardedTimerID)
                }
                timerMutationRenderDeferralActive = false
                refreshCachedRenderState()
                timerSystemRefreshTask = nil
                return
            }
            guard !Task.isCancelled else { return }
            if let event {
                let outcome = await EventMutationService.eventDidChange(
                    event,
                    profile: currentProfile,
                    context: modelContext,
                    settings: currentSettings,
                    notificationsEnabled: alertsEnabled,
                    notificationLeadMinutes: leadMinutes,
                    refreshPrediction: true,
                    waitForSystemIntegrations: false,
                    eventAlreadyPersisted: persistenceRequest != nil
                )
                if let analysis = outcome.analysis {
                    applyIntegrationAnalysis(analysis)
                }
            }
            guard !Task.isCancelled else { return }
            WatchConnectivityService.shared.scheduleCurrentStatePublish()
            if syncWakeAlert {
                await syncActiveSleepPlanWakeAlert()
            }
            // The optimistic timer state already contains the exact mutation
            // that the isolated writer committed. Rebuilding every Today
            // section here needlessly competes with a gesture if persistence
            // finishes while the user is scrolling. Clear the merge guard and
            // publish the isolated worker's immutable analysis directly; a
            // persistence failure above still performs the full corrective
            // render-state rebuild.
            timerMutationRenderDeferralActive = false
            timerSystemRefreshTask = nil
        }
    }

    private func switchNursingSide(_ event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventTimerService.switchNursingSide(draft, context: modelContext)
        persistTimerMutation(draft, syncWakeAlert: true)
    }

    private func setNursingSide(_ side: NursingSide, for event: CareEvent) {
        let draft = timerDraftForMutation(event)
        EventTimerService.setNursingSide(draft, to: side, context: modelContext)
        persistTimerMutation(draft)
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
                .map(editableTimer)
        case .showEvent(let id):
            if let event = scopedEvents.first(where: { $0.id == id }) {
                if event.isTimerDraft {
                    activeTimerToEdit = editableTimer(event)
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
                    activeTimerToEdit = editableTimer(existingTimer)
                } else {
                    showingSleepChooser = true
                }
            } else {
                startTimer(type, nursingSide: side)
            }
        case .startActivity(let activity):
            guard let profile,
                  activity.isAvailable(for: profile.profileType) else { return }
            startTimer(.activity, activityType: activity)
        case .logDiaper:
            editorRoute = EventEditorRoute(type: .diaper)
        case .logEvent(let type):
            guard let profile else { return }
            let resolvedType = profile.profileType == .dog && type == .feed ? .food : type
            guard EventType.cases(for: profile.profileType).contains(resolvedType) else { return }
            editorRoute = EventEditorRoute(type: resolvedType)
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
                resolvedPreset = plannedSolidMealPreset(for: plan)
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

    private func plannedSolidMealPreset(for plan: PlannedSolidMeal) -> SolidFeedEditorPreset {
        var recipes: [CustomSolidRecipe] = []
        if let trackingID = plan.recipeID {
            let prefix = "custom-recipe-"
            if trackingID.hasPrefix(prefix),
               let recipeID = UUID(uuidString: String(trackingID.dropFirst(prefix.count))) {
                var descriptor = FetchDescriptor<CustomSolidRecipe>(
                    predicate: #Predicate { $0.id == recipeID }
                )
                descriptor.fetchLimit = 1
                if let recipe = try? modelContext.fetch(descriptor).first {
                    recipes.append(recipe)
                }
            }
        }

        let customFoodIDs = Set((plan.foodIDs + recipes.flatMap { $0.ingredients.map(\.foodID) })
            .compactMap { trackingID -> UUID? in
                let prefix = "custom-"
                guard trackingID.hasPrefix(prefix) else { return nil }
                return UUID(uuidString: String(trackingID.dropFirst(prefix.count)))
            })
        var customFoods: [SolidFoodCatalogItem] = []
        customFoods.reserveCapacity(customFoodIDs.count)
        for foodID in customFoodIDs {
            var descriptor = FetchDescriptor<SolidFoodCatalogItem>(
                predicate: #Predicate { $0.id == foodID }
            )
            descriptor.fetchLimit = 1
            if let food = try? modelContext.fetch(descriptor).first {
                customFoods.append(food)
            }
        }
        return SolidsTrackingService.preset(
            for: plan,
            customRecipes: recipes,
            customFoods: customFoods
        )
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

    private func presentRoutineManager() {
        showingRoutineManager = true
        // A direct routine link still loads the manager when its Today card is
        // hidden; hiding presentation must not disable the feature itself.
        refreshCachedRenderState(refreshesAnalysis: false)
    }

    private func handlePendingRoutineDeepLink() {
        guard deepLinkRouter.isDataReady else { return }
        guard deepLinkRouter.consumeRoutineCommand() != nil else { return }
        presentRoutineManager()
    }

    private func dogProfileForPuppyGuide() -> CareProfile? {
        if let profile, profile.profileType == .dog {
            return profile
        }
        return profiles.first { $0.profileType == .dog && !$0.isArchived }
    }

    private func eventChanged(
        _ event: CareEvent,
        refreshPrediction: Bool = true,
        waitForSystemIntegrations: Bool = false,
        solidPreset: SolidFeedEditorPreset? = nil
    ) async {
        localEventMutationCount += 1
        applyChangedEventToCachedRenderState(event)
        defer {
            localEventMutationCount = max(0, localEventMutationCount - 1)
        }
        event.profileID = event.profileID ?? selectedProfileID
        let outcome = await EventMutationService.eventDidChange(
            event,
            profile: profile,
            context: modelContext,
            settings: predictionSettings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes,
            refreshPrediction: refreshPrediction,
            waitForSystemIntegrations: waitForSystemIntegrations,
            solidPreset: solidPreset
        )
        if let analysis = outcome.analysis {
            applyIntegrationAnalysis(analysis)
        }
        if !outcome.didPersist {
            refreshCachedRenderState()
        }
    }

    private func applyChangedEventToCachedRenderState(_ event: CareEvent) {
        var state = cachedRenderState
        state.scopedEvents.removeAll { $0.id == event.id }
        state.scopedEvents.append(event)
        state.scopedEvents.sort { $0.startDate > $1.startDate }
        state.todayEvents.removeAll { $0.id == event.id }
        if !event.isTimerDraft && event.occursOnLocalDay(Date()) {
            state.todayEvents.append(event)
            state.todayEvents.sort { $0.startDate > $1.startDate }
        }
        let logDate = event.endDate ?? event.startDate
        if !event.isTimerDraft, logDate <= Date() {
            state.lastLoggedDates[event.type] = logDate
            if event.type == .feed, event.feedKind == .solid {
                state.latestSolidFoodSummary = TodayFeedQuickActionDetail.solidFoodSummary(for: event)
                state.hasSolidHistory = true
            }
        }
        state.essentialsHistory = .make(events: state.scopedEvents, now: Date())
        cachedRenderState = state
    }

    private func adjustStart(of event: CareEvent, to date: Date) {
        let draft = timerDraftForMutation(event)
        EventTimerService.adjustStartDate(draft, to: date)
        persistTimerMutation(draft, syncWakeAlert: true)
    }

    private func discardTimer(_ event: CareEvent) {
        guard event.isTimerDraft else { return }
        let eventID = event.id
        let wasSleepTimer = event.isSleepBlock
        let shouldScheduleNotification = EventMutationService.shouldRefreshLittleWindowAlert(
            after: event
        )
        let remainingEvents = scopedEvents.filter { $0.id != eventID }

        timerMutationRenderDeferralActive = true
        guard EventMutationService.discardTimer(
            event,
            context: modelContext,
            deleteFromContext: false
        ) else {
            timerMutationRenderDeferralActive = false
            return
        }
        applyDiscardedTimerToCachedRenderState(
            eventID: eventID,
            wasSleepTimer: wasSleepTimer,
            remainingEvents: remainingEvents
        )
        scheduleTimerSystemRefresh(
            events: remainingEvents,
            activeTimers: activeEvents,
            scheduleNotification: shouldScheduleNotification,
            persistenceRequest: EventMutationService.timerPersistenceRequest(
                for: event,
                deleting: true
            ),
            syncWakeAlert: wasSleepTimer,
            discardedTimerID: eventID
        )
    }

    private func applyDiscardedTimerToCachedRenderState(
        eventID: UUID,
        wasSleepTimer: Bool,
        remainingEvents: [CareEvent]
    ) {
        invalidateIntegrationAnalysis()
        var state = cachedRenderState
        state.scopedEvents = remainingEvents
        state.activeEvents.removeAll { $0.id == eventID }
        guard wasSleepTimer else {
            cachedRenderState = state
            return
        }

        state.runningSleepTimer = state.activeEvents.first {
            $0.isSleepBlock && $0.isTimerRunning
        }
        state.isSleeping = state.runningSleepTimer != nil
        if state.runningSleepTimer == nil {
            state.awakeSinceDate = remainingEvents.lazy
                .filter(\.isSleepBlock)
                .compactMap { sleep in
                    if sleep.isTimerDraft {
                        return sleep.isTimerRunning ? nil : sleep.updatedAt
                    }
                    return sleep.endDate
                }
                .max()
        }
        cachedRenderState = state
    }

    private func delete(_ event: CareEvent) {
        let eventID = event.id
        let currentProfile = profile
        let currentSettings = predictionSettings
        let alertsEnabled = notificationsEnabled
        let leadMinutes = notificationLeadMinutes

        EventVisibilityStore.markPendingDeletion(eventID)
        applyPendingEventDeletionToCachedRenderState(event)
        localEventMutationCount += 1

        Task { @MainActor in
            defer { localEventMutationCount = max(0, localEventMutationCount - 1) }
            // Finish the confirmation action's update cycle, then let the
            // isolated SwiftData worker perform the actual deletion.
            await Task.yield()
            guard !Task.isCancelled else { return }
            let outcome = await EventMutationService.delete(
                event,
                profile: currentProfile,
                context: modelContext,
                settings: currentSettings,
                notificationsEnabled: alertsEnabled,
                notificationLeadMinutes: leadMinutes
            )
            if !outcome.didPersist {
                EventVisibilityStore.restore(eventID)
                refreshCachedRenderState()
            } else if let analysis = outcome.analysis {
                applyIntegrationAnalysis(analysis)
            }
        }
    }

    private func applyPendingEventDeletionToCachedRenderState(_ event: CareEvent) {
        invalidateIntegrationAnalysis()
        var state = cachedRenderState
        state.scopedEvents.removeAll { $0.id == event.id }
        state.todayEvents.removeAll { $0.id == event.id }
        state.activeEvents.removeAll { $0.id == event.id }

        let now = Date()
        state.lastLoggedDates[event.type] = state.scopedEvents.lazy
            .filter { $0.type == event.type && !$0.isTimerDraft }
            .compactMap { candidate -> Date? in
                let logDate = candidate.endDate ?? candidate.startDate
                return logDate <= now ? logDate : nil
            }
            .max()
        if event.type == .feed, event.feedKind == .solid {
            let remainingSolidFeeds = state.scopedEvents.lazy.filter {
                $0.type == .feed && $0.feedKind == .solid && !$0.isTimerDraft
            }
            state.hasSolidHistory = !remainingSolidFeeds.isEmpty
            state.latestSolidFoodSummary = remainingSolidFeeds
                .filter { ($0.endDate ?? $0.startDate) <= now }
                .max { ($0.endDate ?? $0.startDate) < ($1.endDate ?? $1.startDate) }
                .flatMap(TodayFeedQuickActionDetail.solidFoodSummary)
        }
        if state.isDogProfile {
            switch event.type {
            case .food, .water, .walk, .medicine:
                state.dogLastEventTitles[event.type] = state.scopedEvents.lazy
                    .filter { $0.type == event.type && !$0.isTimerDraft }
                    .max { $0.startDate < $1.startDate }?
                    .displayTitle ?? "Not logged"
            case .potty:
                let remainingPottyEvents = state.scopedEvents.lazy.filter {
                    $0.type == .potty && !$0.isTimerDraft
                }
                state.dogPottyTitles[.pee] = remainingPottyEvents
                    .filter { $0.dogDetails.pottyType?.hasPee == true }
                    .max { $0.startDate < $1.startDate }?
                    .displayTitle ?? "Not logged"
                state.dogPottyTitles[.poop] = remainingPottyEvents
                    .filter { $0.dogDetails.pottyType?.hasPoop == true }
                    .max { $0.startDate < $1.startDate }?
                    .displayTitle ?? "Not logged"
            default:
                break
            }
        }
        if event.isSleepBlock {
            state.prediction = nil
            state.sleepPressure = nil
            state.sleepMiniPlan = nil
            state.awakeSinceDate = state.scopedEvents.lazy
                .filter { $0.isSleepBlock && !$0.isTimerDraft }
                .compactMap(\.endDate)
                .filter { $0 <= now }
                .max()
        }
        state.essentialsHistory = .make(events: state.scopedEvents, now: Date())
        cachedRenderState = state
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

    private func wakeAlert(for event: CareEvent?) -> ActiveSleepPlanWakeAlert? {
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

    private func syncActiveSleepPlanWakeAlert(for event: CareEvent? = nil) async {
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
        let profileType = profile?.profileType ?? .child
        return ActivityType.cases(for: profileType).map { activity in
            let timerAlreadyActive = activity != .custom && state.hasActiveTimer(of: .activity)
            return AppActionSheetOption(
                id: "activity.\(activity.rawValue)",
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
                    // Let the chooser finish its dismissal before presenting
                    // another sheet. Building EventEditorView during the
                    // dismissal animation caused a measurable main-thread
                    // layout hitch on physical devices.
                    pendingActivityEditorRoute = EventEditorRoute(type: .activity)
                } else {
                    startTimer(.activity, activityType: activity)
                }
            }
        }
    }

    private func presentPendingActivityEditor() {
        guard let route = pendingActivityEditorRoute else { return }
        pendingActivityEditorRoute = nil
        editorRoute = route
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
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
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

struct CareCategoryCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID?
    let profileType: CareProfileType
    let onChange: () -> Void

    @State private var hiddenTypes: Set<EventType>
    @State private var pausedTypes: Set<EventType>

    init(
        profileID: UUID?,
        profileType: CareProfileType,
        onChange: @escaping () -> Void
    ) {
        self.profileID = profileID
        self.profileType = profileType
        self.onChange = onChange
        _hiddenTypes = State(initialValue: CareCategoryPreferenceStore.hiddenTypes(profileID: profileID))
        _pausedTypes = State(initialValue: CareTrackingPreferenceStore.preferences(profileID: profileID).pausedTypes)
    }

    var body: some View {
        let eventTypes = EventType.cases(for: profileType)
        let visibleTypeCount = eventTypes.filter { !hiddenTypes.contains($0) }.count

        List {
            Section {
                ForEach(eventTypes) { type in
                    Toggle(isOn: binding(for: type)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(type.displayName, systemImage: type.systemImage(for: profileType))
                            if pausedTypes.contains(type) {
                                Text("Paused in Tracking & Reminders")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!canChangeVisibility(for: type, visibleTypeCount: visibleTypeCount))
                }
            } header: {
                Text("Today Actions")
            } footer: {
                Text("Hidden categories stay available in history and existing logs. Paused categories return to Today when resumed in Tracking & Reminders.")
            }
            Section {
                Button("Reset to Defaults") {
                    hiddenTypes.removeAll()
                    CareCategoryPreferenceStore.reset(profileID: profileID)
                    onChange()
                }
            }
        }
        .navigationTitle("Full Quick Actions")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { _ in
            hiddenTypes = CareCategoryPreferenceStore.hiddenTypes(profileID: profileID)
            pausedTypes = CareTrackingPreferenceStore.preferences(profileID: profileID).pausedTypes
        }
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

private struct TodayDisplayModePicker: View {
    @Binding var selection: TodayDisplayMode

    var body: some View {
        Picker("Today view", selection: $selection) {
            ForEach(TodayDisplayMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("today.mode-toggle")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }
}

private struct TodayHomeSummaryRefreshKey: Equatable {
    var householdID: UUID
    var caregiverName: String
    var caregiverIdentifier: String
    var familySyncEnabled: Bool
    var revision: Int
}

private struct TodayHomeSummaryDataLoader<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PersistenceService.familySyncModeKey)
    private var syncModeRawValue = FamilySyncMode.privateICloudSync.rawValue
    @State private var reader = TodayHomeSummaryReader()
    @State private var cachedSummary: TodayHomeSummary?
    @State private var summaryRevision = 0
    @State private var summaryFailed = false
    let householdID: UUID
    let currentCaregiverName: String
    @ViewBuilder var content: (TodayHomeSummary) -> Content

    var body: some View {
        let familySyncEnabled = FamilySyncMode(rawValue: syncModeRawValue) == .sharedFamilySync
        let caregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier()
        let refreshKey = TodayHomeSummaryRefreshKey(householdID: householdID,
            caregiverName: currentCaregiverName, caregiverIdentifier: caregiverIdentifier,
            familySyncEnabled: familySyncEnabled, revision: summaryRevision)
        Group {
            if let cachedSummary {
                content(cachedSummary)
            } else if summaryFailed {
                ContentUnavailableView {
                    Label("Home couldn't load", systemImage: "house")
                } actions: {
                    Button("Try again") { summaryRevision &+= 1 }
                }
            } else {
                ProgressView("Loading home…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
            }
        }
        .task(id: refreshKey) {
            do {
                let summary = try await reader.read(container: modelContext.container,
                    householdID: householdID, currentCaregiverName: currentCaregiverName,
                    caregiverIdentifier: caregiverIdentifier, familySyncEnabled: familySyncEnabled)
                guard !Task.isCancelled, let summary else { return }
                if cachedSummary != summary { cachedSummary = summary }
                summaryFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                summaryFailed = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .receive(on: RunLoop.main)) { notification in
            if TodayHomeSummaryReader.isRelevantSave(notification) { summaryRevision &+= 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: RunLoop.main)) { _ in summaryRevision &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { notification in
            guard CareTrackingPreferenceStore.affectsCare(notification) else { return }
            summaryRevision &+= 1
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                summaryRevision &+= 1
            }
        }
        .task(id: familySyncEnabled) {
            guard familySyncEnabled else { return }
            _ = HouseholdAttentionService.registerCurrentFamilyCaregiver(
                householdID: householdID, context: modelContext)
        }
    }
}

private struct TodayHomeSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyCaregiverIdentity.displayName) private var familyCaregivers: [FamilyCaregiverIdentity]

    let summary: TodayHomeSummary
    let householdID: UUID
    let caregiverName: String
    let open: (TodayHomeSummaryRoute) -> Void
    let openMedicationDose: (MedicationDoseRouteCommand) -> Void

    @State private var sessionSnoozes = [String: TodaySnoozedAttentionItem]()
    @State private var unsnoozedSourceKeys = Set<String>()
    @State private var attentionNow = Date()
    @State private var isSnoozedExpanded = false
    @State private var showingAllAttention = false
    @State private var actionErrorMessage: String?
    @State private var refillTaskPendingPickupID: UUID?

    init(
        summary: TodayHomeSummary,
        householdID: UUID,
        caregiverName: String,
        open: @escaping (TodayHomeSummaryRoute) -> Void,
        openMedicationDose: @escaping (MedicationDoseRouteCommand) -> Void
    ) {
        self.summary = summary
        self.householdID = householdID
        self.caregiverName = caregiverName
        self.open = open
        self.openMedicationDose = openMedicationDose
    }

    private var greetingTitle: String {
        let name = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholderNames = ["caregiver", "caregiver 1", "caregiver 2"]
        guard !name.isEmpty,
              let normalizedName = CaregiverIdentityService.normalizedName(name),
              !placeholderNames.contains(normalizedName) else {
            return "Welcome home"
        }
        return "Welcome, \(name)"
    }

    private var currentCaregiverIdentifier: String {
        CaregiverIdentityService.stableCaregiverIdentifier()
    }

    private var visibleAttentionItems: [TodayHomeSummaryItem] {
        Array(allVisibleAttentionItems.prefix(TodayHomeSummaryService.attentionItemLimit))
    }

    private var allVisibleAttentionItems: [TodayHomeSummaryItem] {
        var itemsByID = Dictionary(
            summary.allAttentionItems.map { ($0.id, $0) },
            uniquingKeysWith: { current, candidate in
                (candidate.sourceUpdatedAt ?? .distantPast)
                    > (current.sourceUpdatedAt ?? .distantPast)
                    ? candidate
                    : current
            }
        )
        for snoozed in summary.snoozedAttentionItems where
            unsnoozedSourceKeys.contains(snoozed.item.sourceKey ?? "") || snoozed.until <= attentionNow {
            itemsByID[snoozed.item.id] = snoozed.item
        }
        let activeSessionSnoozeKeys = Set(sessionSnoozes.compactMap { sourceKey, snoozed in
            snoozed.until > attentionNow ? sourceKey : nil
        })
        return itemsByID.values
            .filter { item in
                item.sourceKey.map { !activeSessionSnoozeKeys.contains($0) } ?? true
            }
            .sorted(by: attentionPrecedes)
    }

    private var visibleSnoozedAttentionItems: [TodaySnoozedAttentionItem] {
        var itemsBySourceKey = [String: TodaySnoozedAttentionItem]()
        let currentSourceKeys = Set(
            summary.allAttentionItems.compactMap(\.sourceKey)
                + summary.snoozedAttentionItems.compactMap { $0.item.sourceKey }
        )
        for snoozed in summary.snoozedAttentionItems {
            guard let sourceKey = snoozed.item.sourceKey,
                  snoozed.until > attentionNow,
                  !unsnoozedSourceKeys.contains(sourceKey) else { continue }
            itemsBySourceKey[sourceKey] = snoozed
        }
        for (sourceKey, snoozed) in sessionSnoozes where
            snoozed.until > attentionNow && currentSourceKeys.contains(sourceKey) {
            itemsBySourceKey[sourceKey] = snoozed
        }
        return itemsBySourceKey.values.sorted { $0.until < $1.until }
    }

    private var nextSnoozeWakeDate: Date? {
        visibleSnoozedAttentionItems.map(\.until).min()
    }

    private func attentionPrecedes(
        _ lhs: TodayHomeSummaryItem,
        _ rhs: TodayHomeSummaryItem
    ) -> Bool {
        if lhs.urgency != rhs.urgency {
            return lhs.urgency.rawValue > rhs.urgency.rawValue
        }
        let lhsDate = lhs.sortDate ?? .distantFuture
        let rhsDate = rhs.sortDate ?? .distantFuture
        return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate < rhsDate
    }

    private var scopedFamilyCaregivers: [FamilyCaregiverIdentity] {
        familyCaregivers.filter { $0.householdID == householdID }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(greetingTitle)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    TodayWeatherHeader(chooseCity: {
                        DeepLinkRouter.shared.weatherProfileID = ProfileService.shared.selectedProfileID
                        DeepLinkRouter.shared.showingWeather = true
                    })
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                .listRowSeparator(.hidden)
            }

            if summary.isQuiet {
                Section {
                    ContentUnavailableView(
                        greetingTitle,
                        systemImage: "house.fill",
                        description: Text("Your home is all clear—there are no open household items to surface right now.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !visibleAttentionItems.isEmpty {
                Section {
                    TodayHomeAttentionCard(
                        householdID: householdID,
                        items: visibleAttentionItems,
                        caregivers: scopedFamilyCaregivers,
                        currentCaregiverIdentifier: currentCaregiverIdentifier,
                        open: open,
                        acknowledge: acknowledge,
                        claim: claim,
                        takeResponsibility: takeResponsibility,
                        clearClaim: clearClaim,
                        complete: complete,
                        snooze: snooze,
                        medicationAction: performMedicationAction
                    )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    HStack {
                        AppSectionHeader(title: "Needs attention", subtitle: "\(allVisibleAttentionItems.count)")
                        Spacer()
                        if allVisibleAttentionItems.count > visibleAttentionItems.count {
                            Button("View all") { showingAllAttention = true }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            if !visibleSnoozedAttentionItems.isEmpty {
                Section {
                    if isSnoozedExpanded {
                        TodaySnoozedAttentionCard(
                            items: visibleSnoozedAttentionItems,
                            open: open,
                            unsnooze: unsnooze
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Button {
                        withAnimation(.snappy) {
                            isSnoozedExpanded.toggle()
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Snoozed")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Text("\(visibleSnoozedAttentionItems.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: isSnoozedExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .textCase(nil)
                    .accessibilityLabel("Snoozed items")
                    .accessibilityValue(isSnoozedExpanded ? "Expanded" : "Collapsed")
                }
            }

            if let handoff = summary.handoff {
                Section {
                    TodayCaregiverHandoffCard(
                        householdID: householdID,
                        handoff: handoff,
                        items: allVisibleAttentionItems,
                        currentCaregiverIdentifier: currentCaregiverIdentifier,
                        acknowledge: acknowledge,
                        open: open
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    AppSectionHeader(title: "Handoff", subtitle: "Family Sync")
                }
            }

            ForEach(Array(summary.sections.enumerated()), id: \.element.id) { index, section in
                Section {
                    TodayHomeSummaryCard(section: section, open: open)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    if index == 0 {
                        AppSectionHeader(title: "Home & Planning")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .ignoresSafeArea(.keyboard)
        .accessibilityIdentifier("today.home.summary")
        .onChange(of: visibleSnoozedAttentionItems.isEmpty) { _, isEmpty in
            if isEmpty {
                isSnoozedExpanded = false
            }
        }
        .task(id: nextSnoozeWakeDate) {
            guard let wakeDate = nextSnoozeWakeDate else { return }
            let delay = wakeDate.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            let now = Date()
            _ = HouseholdAttentionSnoozeStore.activeSnoozes(now: now)
            attentionNow = now
        }
        .sheet(isPresented: $showingAllAttention) {
            NavigationStack {
                ScrollView {
                    TodayHomeAttentionCard(
                        householdID: householdID,
                        items: allVisibleAttentionItems,
                        caregivers: scopedFamilyCaregivers,
                        currentCaregiverIdentifier: currentCaregiverIdentifier,
                        open: { route in
                            showingAllAttention = false
                            open(route)
                        },
                        acknowledge: acknowledge,
                        claim: claim,
                        takeResponsibility: takeResponsibility,
                        clearClaim: clearClaim,
                        complete: complete,
                        snooze: snooze,
                        medicationAction: performMedicationAction
                    )
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle("Needs attention")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingAllAttention = false }
                    }
                }
            }
        }
        .alert("Couldn't Complete Action", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "Please try again.")
        }
        .appActionSheet(
            isPresented: Binding(
                get: { refillTaskPendingPickupID != nil },
                set: { if !$0 { refillTaskPendingPickupID = nil } }
            ),
            title: "Mark refill picked up?",
            message: "This adds the fill quantity to medication supply and reduces remaining refills by one.",
            systemImage: "bag.badge.checkmark.fill",
            tint: .green,
            options: refillTaskPendingPickupID.map { refillTaskID in
                [AppActionSheetOption(
                    title: "Confirm Pickup",
                    subtitle: "Record the fill and close the refill task.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                ) {
                    refillTaskPendingPickupID = nil
                    completeRefillTask(refillTaskID, pickupConfirmed: true)
                }]
            } ?? [],
            cancelAction: { refillTaskPendingPickupID = nil }
        )
    }

    private func acknowledge(_ item: TodayHomeSummaryItem) {
        guard let sourceKey = item.sourceKey,
              let sourceUpdatedAt = item.sourceUpdatedAt else { return }
        guard HouseholdAttentionService.acknowledge(
            sourceKey: sourceKey,
            sourceUpdatedAt: sourceUpdatedAt,
            householdID: householdID,
            profileID: item.profileID,
            context: modelContext
        ) else {
            actionErrorMessage = "This item couldn't be marked seen. Please try again."
            return
        }
    }

    private func claim(_ item: TodayHomeSummaryItem, _ caregiver: FamilyCaregiverIdentity) {
        guard let sourceKey = item.sourceKey else { return }
        guard HouseholdAttentionService.claim(
            sourceKey: sourceKey,
            householdID: householdID,
            profileID: item.profileID,
            caregiverIdentifier: caregiver.caregiverIdentifier,
            caregiverName: caregiver.displayName,
            context: modelContext
        ) else {
            actionErrorMessage = "Responsibility couldn't be assigned. Please try again."
            return
        }
    }

    private func takeResponsibility(_ item: TodayHomeSummaryItem) {
        guard let sourceKey = item.sourceKey else { return }
        guard HouseholdAttentionService.claim(
            sourceKey: sourceKey,
            householdID: householdID,
            profileID: item.profileID,
            caregiverIdentifier: currentCaregiverIdentifier,
            caregiverName: CaregiverIdentityService.currentCaregiverName(),
            context: modelContext
        ) else {
            actionErrorMessage = "Responsibility couldn't be assigned. Please try again."
            return
        }
    }

    private func clearClaim(_ item: TodayHomeSummaryItem) {
        guard let sourceKey = item.sourceKey else { return }
        guard HouseholdAttentionService.clearClaim(
            sourceKey: sourceKey,
            householdID: householdID,
            profileID: item.profileID,
            context: modelContext
        ) else {
            actionErrorMessage = "The assignment couldn't be cleared. Please try again."
            return
        }
    }

    private func complete(_ item: TodayHomeSummaryItem) {
        if let refillTaskID = item.refillTaskID {
            completeRefillTask(refillTaskID)
            return
        }
        guard let followUpID = item.followUpID else { return }
        let descriptor = FetchDescriptor<AppointmentFollowUp>(
            predicate: #Predicate { $0.id == followUpID }
        )
        guard let followUp = try? modelContext.fetch(descriptor).first else { return }
        guard HouseholdAttentionService.setFollowUpCompleted(
            followUp,
            completed: true,
            context: modelContext
        ) else {
            actionErrorMessage = "The follow-up couldn't be completed. Please try again."
            return
        }
    }

    private func completeRefillTask(
        _ refillTaskID: UUID,
        pickupConfirmed: Bool = false
    ) {
        let taskDescriptor = FetchDescriptor<MedicationRefillTask>(
            predicate: #Predicate { $0.id == refillTaskID }
        )
        guard let task = try? modelContext.fetch(taskDescriptor).first else { return }
        let medicationID = task.medicationID
        let medicationDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == medicationID }
        )
        guard let medication = try? modelContext.fetch(medicationDescriptor).first else { return }
        if task.status == .readyForPickup, !pickupConfirmed {
            refillTaskPendingPickupID = refillTaskID
            return
        }
        let nextStatus: MedicationRefillStatus = switch task.status {
        case .needsRequest: .requested
        case .requested: .readyForPickup
        case .readyForPickup: .pickedUp
        case .pickedUp, .cancelled: task.status
        }
        guard MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: nextStatus,
            context: modelContext
        ) else {
            actionErrorMessage = nextStatus == .pickedUp
                ? "Add a fill quantity in Medications before completing pickup."
                : "The refill task couldn't be updated."
            return
        }
    }

    private func snooze(_ item: TodayHomeSummaryItem, until date: Date) {
        guard let sourceKey = item.sourceKey else { return }
        HouseholdAttentionSnoozeStore.snooze(sourceKey: sourceKey, until: date)
        sessionSnoozes[sourceKey] = TodaySnoozedAttentionItem(item: item, until: date)
        unsnoozedSourceKeys.remove(sourceKey)
        attentionNow = Date()
    }

    private func unsnooze(_ snoozed: TodaySnoozedAttentionItem) {
        guard let sourceKey = snoozed.item.sourceKey else { return }
        HouseholdAttentionSnoozeStore.clear(sourceKey: sourceKey)
        sessionSnoozes.removeValue(forKey: sourceKey)
        unsnoozedSourceKeys.insert(sourceKey)
        attentionNow = Date()
    }

    private func performMedicationAction(
        _ item: TodayHomeSummaryItem,
        status: MedicationDoseStatus?
    ) {
        guard let medication = item.medicationAttention else { return }
        openMedicationDose(MedicationDoseRouteCommand(
            profileID: medication.profileID,
            medicationID: medication.medicationID,
            regimenID: medication.regimenID,
            phaseID: medication.phaseID,
            occurrenceKey: medication.occurrenceKey,
            scheduledAt: medication.scheduledAt,
            doseAmount: medication.doseAmount,
            doseUnit: medication.doseUnit,
            status: status
        ))
    }

}

private struct TodayHomeAttentionCard: View {
    let householdID: UUID
    let items: [TodayHomeSummaryItem]
    let caregivers: [FamilyCaregiverIdentity]
    let currentCaregiverIdentifier: String
    let open: (TodayHomeSummaryRoute) -> Void
    let acknowledge: (TodayHomeSummaryItem) -> Void
    let claim: (TodayHomeSummaryItem, FamilyCaregiverIdentity) -> Void
    let takeResponsibility: (TodayHomeSummaryItem) -> Void
    let clearClaim: (TodayHomeSummaryItem) -> Void
    let complete: (TodayHomeSummaryItem) -> Void
    let snooze: (TodayHomeSummaryItem, Date) -> Void
    let medicationAction: (TodayHomeSummaryItem, MedicationDoseStatus?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 50) }
                TodayHomeAttentionRow(
                    householdID: householdID,
                    item: item,
                    caregivers: caregivers,
                    currentCaregiverIdentifier: currentCaregiverIdentifier,
                    open: { open(item.route) },
                    acknowledge: { acknowledge(item) },
                    claim: { claim(item, $0) },
                    takeResponsibility: { takeResponsibility(item) },
                    clearClaim: { clearClaim(item) },
                    complete: { complete(item) },
                    snooze: { snooze(item, $0) },
                    medicationAction: { medicationAction(item, $0) }
                )
            }
        }
        .padding(.horizontal, 12)
        .appSurface(cornerRadius: 20)
    }
}

private struct TodaySnoozedAttentionCard: View {
    let items: [TodaySnoozedAttentionItem]
    let open: (TodayHomeSummaryRoute) -> Void
    let unsnooze: (TodaySnoozedAttentionItem) -> Void

    private func snoozedForText(until date: Date, now: Date) -> String {
        let totalMinutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if totalMinutes < 60 {
            return "Snoozed for \(totalMinutes) min"
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            let duration = minutes == 0 ? "\(totalHours) hr" : "\(totalHours) hr \(minutes) min"
            return "Snoozed for \(duration)"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        let dayLabel = "\(days) day\(days == 1 ? "" : "s")"
        let duration = hours == 0 ? dayLabel : "\(dayLabel) \(hours) hr"
        return "Snoozed for \(duration)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, snoozed in
                if index > 0 { Divider().padding(.leading, 50) }
                HStack(spacing: 10) {
                    Button { open(snoozed.item.route) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: snoozed.item.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(snoozed.item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                TimelineView(.periodic(from: .now, by: 60)) { context in
                                    Text(snoozedForText(until: snoozed.until, now: context.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    Button("Unsnooze") { unsnooze(snoozed) }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(cornerRadius: 20)
    }
}

private struct TodayHomeAttentionRow: View {
    let householdID: UUID
    let item: TodayHomeSummaryItem
    let caregivers: [FamilyCaregiverIdentity]
    let currentCaregiverIdentifier: String
    let open: () -> Void
    let acknowledge: () -> Void
    let claim: (FamilyCaregiverIdentity) -> Void
    let takeResponsibility: () -> Void
    let clearClaim: () -> Void
    let complete: () -> Void
    let snooze: (Date) -> Void
    let medicationAction: (MedicationDoseStatus?) -> Void

    @State private var showingHandoffNoteEditor = false

    private var tint: Color {
        switch item.urgency {
        case .normal: item.category.tint
        case .attention: .orange
        case .urgent: .red
        }
    }

    private var assignmentText: String? {
        if item.supportsClaim,
           let claimed = item.claimedCaregiverName,
           !claimed.isEmpty {
            return "Responsible: \(claimed)"
        }
        if item.isFamilyShared && item.supportsClaim {
            return "Unassigned"
        }
        return nil
    }

    private var acknowledgementText: String? {
        guard !item.acknowledgedByNames.isEmpty else { return nil }
        return "Seen by \(item.acknowledgedByNames.joined(separator: ", "))"
    }

    private var supportingText: String? {
        var seen = Set<String>()
        var fragments = [String]()
        let badgeKey = item.badge.map(normalizedMetadataKey)

        func appendUniqueFragments(from value: String?) {
            guard let value else { return }
            for fragment in value.components(separatedBy: " · ") {
                let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = normalizedMetadataKey(trimmed)
                guard key != badgeKey, seen.insert(key).inserted else { continue }
                fragments.append(trimmed)
            }
        }

        appendUniqueFragments(from: item.detail)
        appendUniqueFragments(from: item.profileName)
        appendUniqueFragments(from: item.dueLabel)
        return fragments.isEmpty ? nil : fragments.joined(separator: " · ")
    }

    private func normalizedMetadataKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if let badge = item.badge {
                                Text(badge)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tint.opacity(0.1), in: Capsule())
                            }
                        }
                        if let supportingText {
                            Text(supportingText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let assignmentText {
                            Text(assignmentText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    }

                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                if let acknowledgementText {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                        Text(acknowledgementText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                }

                if item.medicationAttention != nil {
                    Button("Taken") { medicationAction(.taken) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    Button("Other…") { medicationAction(nil) }
                        .buttonStyle(.bordered)
                } else if item.followUpID != nil || item.refillTaskID != nil {
                    Button(item.completionLabel ?? "Complete", systemImage: "checkmark") {
                        complete()
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }

                if item.isFamilyShared && !item.currentCaregiverHasAcknowledged {
                    Button(action: acknowledge) {
                        Label("Seen", systemImage: "eye.fill")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                Button {
                    snooze(Date().addingTimeInterval(60 * 60))
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Snooze 1h")
                    }
                    .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Snooze \(item.title) for one hour")

                Menu {
                    Button("Snooze 1 hour", systemImage: "clock") {
                        snooze(Date().addingTimeInterval(60 * 60))
                    }
                    Button("Snooze until tomorrow", systemImage: "sunrise.fill") {
                        let tomorrow = Calendar.current.date(
                            byAdding: .day,
                            value: 1,
                            to: Calendar.current.startOfDay(for: Date())
                        ) ?? Date().addingTimeInterval(24 * 60 * 60)
                        snooze(tomorrow.addingTimeInterval(8 * 60 * 60))
                    }
                    if item.isFamilyShared {
                        Divider()
                        if item.supportsClaim,
                           item.claimedCaregiverIdentifier != currentCaregiverIdentifier {
                            Button("Take responsibility", systemImage: "person.crop.circle.badge.checkmark") {
                                takeResponsibility()
                            }
                        }
                        if item.supportsClaim && !caregivers.isEmpty {
                            Menu("Assign or reassign", systemImage: "person.badge.plus") {
                                ForEach(caregivers) { caregiver in
                                    Button(caregiver.displayName) { claim(caregiver) }
                                }
                            }
                        }
                        if item.supportsClaim && item.claimedCaregiverIdentifier != nil {
                            Button("Clear assignment", systemImage: "person.badge.minus") {
                                clearClaim()
                            }
                        }
                        Button("Add handoff note", systemImage: "square.and.pencil") {
                            showingHandoffNoteEditor = true
                        }
                    }
                    Divider()
                    Button("Open source", systemImage: "arrow.up.right") { open() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("More actions for \(item.title)")
            }
            .font(.caption.weight(.semibold))
            .controlSize(.small)
            .padding(.leading, 48)
        }
        .padding(.vertical, 10)
        .sheet(isPresented: $showingHandoffNoteEditor) {
            CaregiverHandoffNoteSheet(householdID: householdID, item: item)
        }
    }
}

private struct TodayCaregiverHandoffCard: View {
    let householdID: UUID
    let handoff: TodayCaregiverHandoffSummary
    let items: [TodayHomeSummaryItem]
    let currentCaregiverIdentifier: String
    let acknowledge: (TodayHomeSummaryItem) -> Void
    let open: (TodayHomeSummaryRoute) -> Void

    @State private var showingHandoffNoteEditor = false
    @State private var showingAllHandoffNotes = false
    @State private var handoffNoteToEdit: TodayHandoffNoteSummary?
    @State private var isVisible = false

    private var needsAcknowledgement: TodayHomeSummaryItem? {
        handoff.needsAcknowledgementItemID.flatMap { id in items.first { $0.id == id } }
    }

    private var nextUp: TodayHomeSummaryItem? {
        handoff.nextUpItemID.flatMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if handoff.activityCount > 0 {
                Label {
                    Text("Since you last checked: \(handoff.activityCount) shared update\(handoff.activityCount == 1 ? "" : "s")")
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Label("No new shared updates since your last check", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !handoff.recentActivities.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Recent changes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(handoff.recentActivities) { activity in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.blue)
                            Text(activity.text)
                                .font(.caption)
                            Spacer(minLength: 4)
                            Text(activity.occurredAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if let item = needsAcknowledgement {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Needs your acknowledgement")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Mark seen") { acknowledge(item) }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            if let item = nextUp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next up for you")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Button { open(item.route) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !handoff.recentNotes.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Label("Recent handoff notes", systemImage: "text.bubble")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(handoff.notes.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                        Spacer()
                        if handoff.notes.count > handoff.recentNotes.count {
                            Button("View all") { showingAllHandoffNotes = true }
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    ForEach(handoff.recentNotes) { note in
                        TodayHandoffNoteRow(
                            note: note,
                            openSource: open,
                            edit: note.authorCaregiverIdentifier == currentCaregiverIdentifier
                                ? { handoffNoteToEdit = note }
                                : nil
                        )
                    }
                }
            }

            Button {
                showingHandoffNoteEditor = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                    Text("Add handoff note")
                }
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(cornerRadius: 20)
        .sheet(isPresented: $showingHandoffNoteEditor) {
            CaregiverHandoffNoteSheet(householdID: householdID, item: nil)
        }
        .sheet(item: $handoffNoteToEdit) { note in
            CaregiverHandoffNoteEditSheet(householdID: householdID, note: note)
        }
        .sheet(isPresented: $showingAllHandoffNotes) {
            TodayHandoffNotesSheet(
                householdID: householdID,
                notes: handoff.notes,
                currentCaregiverIdentifier: currentCaregiverIdentifier,
                open: open
            )
        }
        .onAppear {
            isVisible = true
            markVisibleActivityReviewed()
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: handoff.latestObservedActivityAt) { _, _ in
            guard isVisible else { return }
            markVisibleActivityReviewed()
        }
    }

    private func markVisibleActivityReviewed() {
        guard let reviewedThrough = handoff.latestObservedActivityAt else { return }
        CaregiverHandoffCheckpointStore.markReviewed(
            caregiverIdentifier: currentCaregiverIdentifier,
            at: reviewedThrough
        )
    }
}

private struct TodayHandoffNoteRow: View {
    let note: TodayHandoffNoteSummary
    var showsFullDate = false
    var openSource: ((TodayHomeSummaryRoute) -> Void)?
    var edit: (() -> Void)?

    private var authorInitial: String {
        note.authorName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "?"
    }

    private var staticRelativeCreatedAt: String {
        note.createdAt.formatted(
            .relative(presentation: .named, unitsStyle: .abbreviated)
        )
    }

    private var wasEdited: Bool {
        note.updatedAt > note.createdAt
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(authorInitial)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.blue)
                .frame(width: 26, height: 26)
                .background(Color.blue.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note.authorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if showsFullDate {
                        Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        // A formatted string stays static instead of installing
                        // SwiftUI's live relative-date timer for every note row.
                        Text(staticRelativeCreatedAt)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if wasEdited {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let edit {
                        Button(action: edit) {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit handoff note")
                    }
                }

                if let sourceTitle = note.sourceTitle {
                    if let sourceRoute = note.sourceRoute, let openSource {
                        Button {
                            openSource(sourceRoute)
                        } label: {
                            TodayHandoffSourceLabel(title: sourceTitle, isLink: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open linked item, \(sourceTitle)")
                    } else {
                        TodayHandoffSourceLabel(title: sourceTitle, isLink: false)
                    }
                }

                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: edit == nil ? .combine : .contain)
    }
}

private struct TodayHandoffNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let householdID: UUID
    let notes: [TodayHandoffNoteSummary]
    let currentCaregiverIdentifier: String
    let open: (TodayHomeSummaryRoute) -> Void

    @State private var noteToEdit: TodayHandoffNoteSummary?

    var body: some View {
        NavigationStack {
            List(notes) { note in
                TodayHandoffNoteRow(
                    note: note,
                    showsFullDate: true,
                    openSource: { route in
                        dismiss()
                        open(route)
                    },
                    edit: note.authorCaregiverIdentifier == currentCaregiverIdentifier
                        ? { noteToEdit = note }
                        : nil
                )
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle("Handoff Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $noteToEdit) { note in
            CaregiverHandoffNoteEditSheet(householdID: householdID, note: note)
        }
    }
}

private struct TodayHandoffSourceLabel: View {
    let title: String
    let isLink: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isLink ? "link" : "doc.text")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isLink ? Color.blue : Color.secondary)
            Text(isLink ? "Linked to" : "Related to")
                .foregroundStyle(.tertiary)
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(isLink ? Color.primary : Color.secondary)
            if isLink {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            (isLink ? Color.blue : Color.secondary).opacity(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    (isLink ? Color.blue : Color.secondary).opacity(0.12),
                    lineWidth: 1
                )
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct CaregiverHandoffNoteSheet: View {
    @Environment(\.modelContext) private var modelContext

    let householdID: UUID
    let item: TodayHomeSummaryItem?

    var body: some View {
        CaregiverHandoffNoteEditor(
            scopeTitle: item?.title ?? "Household handoff",
            initialBody: "",
            saveTitle: "Add",
            saveErrorTitle: "Couldn't Add Note",
            saveErrorMessage: "The handoff note wasn't saved. Please try again."
        ) { body in
            HouseholdAttentionService.addHandoffNote(
                householdID: householdID,
                profileID: item?.profileID,
                sourceKey: item?.sourceKey,
                sourceTitle: item?.title,
                body: body,
                context: modelContext
            ) != nil
        }
    }
}

private struct CaregiverHandoffNoteEditSheet: View {
    @Environment(\.modelContext) private var modelContext

    let householdID: UUID
    let note: TodayHandoffNoteSummary

    var body: some View {
        CaregiverHandoffNoteEditor(
            scopeTitle: note.sourceTitle ?? "Household handoff",
            initialBody: note.body,
            saveTitle: "Save",
            saveErrorTitle: "Couldn't Save Changes",
            saveErrorMessage: "The handoff note wasn't updated. Please try again."
        ) { body in
            HouseholdAttentionService.updateHandoffNote(
                id: note.id,
                householdID: householdID,
                body: body,
                context: modelContext
            )
        }
    }
}

private struct CaregiverHandoffNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let scopeTitle: String
    let saveTitle: String
    let saveErrorTitle: String
    let saveErrorMessage: String
    let save: (String) -> Bool

    @State private var bodyText: String
    @State private var shouldFocusBody = false
    @State private var showingSaveError = false

    init(
        scopeTitle: String,
        initialBody: String,
        saveTitle: String,
        saveErrorTitle: String,
        saveErrorMessage: String,
        save: @escaping (String) -> Bool
    ) {
        self.scopeTitle = scopeTitle
        self.saveTitle = saveTitle
        self.saveErrorTitle = saveErrorTitle
        self.saveErrorMessage = saveErrorMessage
        self.save = save
        _bodyText = State(initialValue: initialBody)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(scopeTitle)
                        .font(.subheadline)
                }

                ZStack(alignment: .topLeading) {
                    HandoffNoteTextView(
                        text: $bodyText,
                        shouldBecomeFirstResponder: shouldFocusBody
                    )

                    if bodyText.isEmpty {
                        Text("Short handoff note")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 150)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .background(AppTheme.background)
            .task {
                // Let the sheet complete its presentation before asking UIKit to
                // install the keyboard. Doing both in one SwiftUI transaction
                // triggers a second full layout pass for the sheet.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                shouldFocusBody = true
            }
            .navigationTitle("Handoff Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        if save(bodyText) {
                            dismiss()
                        } else {
                            showingSaveError = true
                        }
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(saveErrorTitle, isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
}

private struct HandoffNoteTextView: UIViewRepresentable {
    @Binding var text: String
    let shouldBecomeFirstResponder: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 4
        textView.keyboardDismissMode = .interactive
        textView.accessibilityLabel = "Short handoff note"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }

        guard shouldBecomeFirstResponder,
              !context.coordinator.didRequestFirstResponder,
              textView.window != nil else { return }

        context.coordinator.didRequestFirstResponder = true
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: textView.text.utf16.count, length: 0)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        var didRequestFirstResponder = false

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

private struct TodayHomeSummaryCard: View {
    let section: TodayHomeSummarySection
    let open: (TodayHomeSummaryRoute) -> Void

    private var tint: Color { section.category.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: section.category.systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.category.title)
                        .font(.headline)
                    Text(section.countLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Spacer()

                Button {
                    open(section.category.route)
                } label: {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .accessibilityLabel("Open \(section.category.title) in Home")
            }

            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            if section.items.isEmpty {
                Text(section.emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        Divider()
                            .padding(.leading, 50)
                            .opacity(index == 0 ? 0 : 1)
                        TodayHomeSummaryRow(item: item) { open(item.route) }
                    }
                }
                .padding(.top, 5)
            }

            if let remainderText = section.remainderText {
                Text(remainderText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 6)
                    .padding(.leading, 50)
            }
        }
        .padding(14)
        .appSurface(cornerRadius: 20)
        .accessibilityIdentifier("today.home.section.\(section.category.rawValue)")
    }
}

private struct TodayHomeSummaryRow: View {
    let item: TodayHomeSummaryItem
    let action: () -> Void

    private var tint: Color {
        switch item.urgency {
        case .normal: item.category.tint
        case .attention: .orange
        case .urgent: .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let badge = item.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.1), in: Capsule())
                        }
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this item in the Home tab")
    }
}

private extension TodayHomeSummaryCategory {
    var tint: Color {
        switch self {
        case .todos: .indigo
        case .shopping: .blue
        case .kitchen: .green
        case .trips: .cyan
        case .returns: .orange
        case .medications: .red
        case .appointments: .indigo
        case .routines: .purple
        case .solids: .orange
        }
    }
}
