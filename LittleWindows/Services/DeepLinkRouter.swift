import Foundation

enum LittleWindowsTab: String, Hashable, Codable {
    case today
    case food
    case reports
    case milestones
    case nightLight
    case medical
}

struct SolidsNavigationOrigin: Equatable {
    var tab: LittleWindowsTab
    var insightsSection: InsightsSection?
    var feedingInsightsMode: FeedingInsightsMode?

    init(
        tab: LittleWindowsTab,
        insightsSection: InsightsSection? = nil,
        feedingInsightsMode: FeedingInsightsMode? = nil
    ) {
        self.tab = tab
        self.insightsSection = insightsSection
        self.feedingInsightsMode = feedingInsightsMode
    }
}

enum AppNavigationLaunchPolicy {
    static let initialTab = LittleWindowsTab.today
}

enum ReportsDisplayMode: String, CaseIterable, Identifiable {
    case day
    case list
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .list: "List"
        case .summary: "Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .day: "calendar.day.timeline.left"
        case .list: "list.bullet"
        case .summary: "chart.bar.xaxis"
        }
    }
}

enum AppointmentRouteCommand: Equatable {
    case list
    case detail(UUID)
    case notes(UUID)
}

enum AgeGuideRouteCommand: Equatable {
    case list
    case detail(Int)
}

enum PuppyGuideRouteCommand: Equatable {
    case current
}

enum RoutineRouteCommand: Equatable {
    case list
}

enum NightLightCommand: Equatable {
    case open
    case start(NightLightPresetKind?)
    case stop
}

enum DeepLinkAction: Equatable {
    case showActiveTimer
    case showEvent(UUID)
    case stopActiveTimer
    case stopTimer(UUID)
    case resumeTimer(UUID)
    case switchNursingSide(UUID)
    case startTimer(EventType, NursingSide?)
    case startActivity(ActivityType)
    case logDiaper
    case logEvent(EventType)
    case logSolidFeed(SolidFeedEditorPreset)
    case repeatLast
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var selectedTab: LittleWindowsTab
    @Published var pendingAction: DeepLinkAction?
    @Published var pendingNightLightCommand: NightLightCommand?
    @Published var pendingAppointmentCommand: AppointmentRouteCommand?
    @Published var pendingAgeGuideCommand: AgeGuideRouteCommand?
    @Published var pendingPuppyGuideCommand: PuppyGuideRouteCommand?
    @Published var pendingRoutineCommand: RoutineRouteCommand?
    @Published var pendingSolidsCommand: FoodRouteCommand?
    @Published var pendingSolidsOrigin: SolidsNavigationOrigin?
    @Published var pendingFoodCommand: FoodRouteCommand?
    @Published var pendingInsightsSection: InsightsSection?
    @Published var pendingFeedingInsightsMode: FeedingInsightsMode?
    @Published var pendingProfileID: UUID?
    @Published var selectedReportsMode: ReportsDisplayMode = ReportsDisplayMode(
        rawValue: UserDefaults.standard.string(forKey: "reportsDisplayMode") ?? ""
    ) ?? .day
    @Published var showingSettings = false
    @Published var showingFamilySyncSettings = false
    @Published var isDataReady = false

    private init() {
        selectedTab = AppNavigationLaunchPolicy.initialTab
    }

    func openToday(
        action: DeepLinkAction,
        profileID: UUID? = nil
    ) {
        if let profileID { pendingProfileID = profileID }
        // Publish the action before selecting Today. RootView creates the Today
        // hierarchy lazily, so it must be waiting when that hierarchy appears.
        pendingAction = action
        selectedTab = .today
    }

    func openSolids(
        _ command: FoodRouteCommand,
        profileID: UUID? = nil,
        returningTo returnTab: LittleWindowsTab?,
        insightsSection: InsightsSection? = nil,
        feedingInsightsMode: FeedingInsightsMode? = nil
    ) {
        if let profileID { pendingProfileID = profileID }
        pendingSolidsOrigin = returnTab.map {
            SolidsNavigationOrigin(
                tab: $0,
                insightsSection: insightsSection,
                feedingInsightsMode: feedingInsightsMode
            )
        }
        pendingSolidsCommand = command
        selectedTab = .milestones
    }

    func openFood(_ command: FoodRouteCommand) {
        pendingFoodCommand = command
        selectedTab = .food
    }

    func consumeSolidsOrigin() -> SolidsNavigationOrigin? {
        defer { pendingSolidsOrigin = nil }
        return pendingSolidsOrigin
    }

    func route(_ url: URL) {
        guard url.scheme == "littlewindows" else { return }
        pendingSolidsOrigin = nil
        pendingFeedingInsightsMode = nil
        var components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        if components.count >= 2,
           components[0] == "profile",
           let profileID = UUID(uuidString: components[1]) {
            pendingProfileID = profileID
            components.removeFirst(2)
            if components.isEmpty {
                components = ["today"]
            }
        }

        // Keep the original Food & Home URLs working while moving the workspace
        // to the profile-scoped Care tab.
        if components.count >= 2,
           components[0] == "care",
           components[1] == "solids" {
            components[0] = "food"
        }

        if components == ["today"] {
            selectedTab = .today
        } else if components == ["food"] {
            openFood(.food)
        } else if components == ["food", "solids"] {
            openSolids(.solids, returningTo: nil)
        } else if components == ["food", "solids", "database"] {
            openSolids(.solidsDatabase, returningTo: nil)
        } else if components == ["food", "solids", "guided"] {
            openSolids(.solidsGuided, returningTo: nil)
        } else if components.count == 4,
                  components[0] == "food",
                  components[1] == "solids",
                  components[2] == "foods" {
            openSolids(.solidFood(components[3]), returningTo: nil)
        } else if components.count == 4,
                  components[0] == "food",
                  components[1] == "solids",
                  components[2] == "custom",
                  let uuid = UUID(uuidString: components[3]) {
            openSolids(.customSolidFood(uuid), returningTo: nil)
        } else if components == ["food", "solids", "plan"] {
            openSolids(.solidsPlan, returningTo: nil)
        } else if components.count >= 4,
                  components[0] == "food",
                  components[1] == "solids",
                  components[2] == "plan",
                  let uuid = UUID(uuidString: components[3]) {
            if components.count == 5, components[4] == "log" {
                openToday(action: .logSolidFeed(
                    SolidFeedEditorPreset(plannedMealID: uuid)
                ))
            } else {
                openSolids(.plannedSolidMeal(uuid), returningTo: nil)
            }
        } else if components == ["food", "solids", "tracker"] {
            openSolids(.solidsTracker, returningTo: nil)
        } else if components.count == 4,
                  components[0] == "food",
                  components[1] == "solids",
                  components[2] == "tracker",
                  let uuid = UUID(uuidString: components[3]) {
            openSolids(.solidMeal(uuid), returningTo: nil)
        } else if components == ["food", "solids", "allergens"] {
            openSolids(.solidsAllergens, returningTo: nil)
        } else if components.count == 4,
                  components[0] == "food",
                  components[1] == "solids",
                  components[2] == "allergens" {
            openSolids(.solidAllergen(components[3]), returningTo: nil)
        } else if components == ["food", "solids", "recipes"] {
            openSolids(.solidsRecipes, returningTo: nil)
        } else if components.count == 4,
                  components[0] == "food",
                  components[1] == "solids",
                  components[2] == "recipes" {
            openSolids(.solidsRecipe(components[3]), returningTo: nil)
        } else if components == ["food", "todos"] {
            openFood(.todos)
        } else if components.count == 5,
                  components[0] == "food",
                  components[1] == "trips",
                  components[3] == "itinerary",
                  let tripID = UUID(uuidString: components[2]),
                  let itemID = UUID(uuidString: components[4]) {
            openFood(.itineraryItem(tripID, itemID))
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "todos",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(.todoList(uuid))
        } else if components == ["food", "shopping"] {
            openFood(.shopping)
        } else if components == ["food", "quick-add"] {
            openFood(.quickAdd)
        } else if components.count >= 3,
                  components[0] == "food",
                  components[1] == "shopping",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(components.count >= 4 && components[3] == "mode"
                ? .shoppingMode(uuid)
                : .shoppingList(uuid))
        } else if components == ["food", "trips"] {
            openFood(.trips)
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "trips",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(.packingTrip(uuid))
        } else if components == ["food", "inventory"] {
            openFood(.inventory)
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "inventory",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(.inventoryItem(uuid))
        } else if components == ["food", "meal-prep"] {
            openFood(.mealPrep)
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "meal-prep",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(.mealPrepItem(uuid))
        } else if components == ["food", "returns"] {
            openFood(.returns)
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "returns",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(.returnRequest(uuid))
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "stores",
                  let uuid = UUID(uuidString: components[2]) {
            openFood(.store(uuid))
        } else if components == ["history"] {
            selectedReportsMode = .day
            selectedTab = .reports
        } else if components == ["history", "list"] {
            selectedReportsMode = .list
            selectedTab = .reports
        } else if components == ["reports"] || components == ["calendar"] {
            selectedReportsMode = .day
            selectedTab = .reports
        } else if components == ["reports", "feeding"] || components == ["insights", "feeding"] {
            selectedReportsMode = .summary
            pendingInsightsSection = .feeding
            selectedTab = .reports
        } else if components.count == 2,
                  components[0] == "reports",
                  let mode = ReportsDisplayMode(rawValue: components[1]) {
            selectedReportsMode = mode
            selectedTab = .reports
        } else if components == ["settings"] {
            showingSettings = true
        } else if components == ["settings", "family-sync"] {
            showingSettings = true
            showingFamilySyncSettings = true
        } else if components == ["care"]
                    || components == ["milestones"]
                    || components == ["memories"] {
            selectedTab = .milestones
        } else if components == ["age-guides"] {
            pendingAgeGuideCommand = .list
            selectedTab = .milestones
        } else if components.count == 2,
                  components[0] == "age-guide",
                  let month = Int(components[1]) {
            pendingAgeGuideCommand = .detail(month)
            selectedTab = .milestones
        } else if components == ["appointments"] || components == ["visits"] {
            pendingAppointmentCommand = .list
            selectedTab = .today
        } else if components == ["routines"] {
            pendingRoutineCommand = .list
            selectedTab = .today
        } else if components.count >= 2, components[0] == "appointment",
                  let uuid = UUID(uuidString: components[1]) {
            pendingAppointmentCommand = components.count >= 3 && components[2] == "notes"
                ? .notes(uuid)
                : .detail(uuid)
            selectedTab = .today
        } else if components == ["medical"] {
            selectedReportsMode = .summary
            selectedTab = .reports
        } else if components == ["insights"] {
            selectedReportsMode = .summary
            selectedTab = .reports
        } else if components == ["puppy-guide"] {
            pendingPuppyGuideCommand = .current
            selectedTab = .today
        } else if components == ["night-light"] {
            pendingNightLightCommand = .open
            selectedTab = .nightLight
        } else if components == ["night-light", "stop"] {
            pendingNightLightCommand = .stop
            selectedTab = .nightLight
        } else if components.count == 2,
                  components[0] == "night-light",
                  let preset = NightLightPresetKind(slug: components[1]) {
            pendingNightLightCommand = .start(preset)
            selectedTab = .nightLight
        } else if components == ["active-timer"] {
            openToday(action: .showActiveTimer)
        } else if components == ["prediction"] {
            selectedReportsMode = .summary
            selectedTab = .reports
        } else if components.count == 2, components[0] == "event" {
            if let uuid = UUID(uuidString: components[1]) {
                openToday(action: .showEvent(uuid))
            } else {
                selectedTab = .today
            }
        } else if components == ["action", "stop-active"] {
            openToday(action: .stopActiveTimer)
        } else if components.count == 3, components[0] == "action", components[1] == "stop" {
            if let uuid = UUID(uuidString: components[2]) {
                openToday(action: .stopTimer(uuid))
            } else {
                selectedTab = .today
            }
        } else if components.count == 3, components[0] == "action", components[1] == "resume" {
            if let uuid = UUID(uuidString: components[2]) {
                openToday(action: .resumeTimer(uuid))
            } else {
                selectedTab = .today
            }
        } else if components.count == 3, components[0] == "action", components[1] == "switch-side" {
            if let uuid = UUID(uuidString: components[2]) {
                openToday(action: .switchNursingSide(uuid))
            } else {
                selectedTab = .today
            }
        } else if components == ["quick-log", "sleep"] {
            openToday(action: .startTimer(.sleep, nil))
        } else if components == ["quick-log", "feed"] {
            openToday(action: .logEvent(.feed))
        } else if components == ["quick-log", "solids"] {
            openToday(action: .logSolidFeed(.empty))
        } else if components == ["quick-log", "pumping"] {
            openToday(action: .startTimer(.pumping, nil))
        } else if components == ["quick-log", "child-potty"] {
            openToday(action: .logEvent(.potty))
        } else if components == ["quick-log", "repeat-last"] {
            openToday(action: .repeatLast)
        } else if components == ["quick-log", "food"] {
            openToday(action: .logEvent(.food))
        } else if components == ["quick-log", "water"] {
            openToday(action: .logEvent(.water))
        } else if components == ["quick-log", "pee"] {
            openToday(action: .logEvent(.potty))
        } else if components == ["quick-log", "poop"] {
            openToday(action: .logEvent(.potty))
        } else if components == ["quick-log", "walk"] {
            openToday(action: .startTimer(.walk, nil))
        } else if components == ["quick-log", "training"] {
            openToday(action: .startTimer(.training, nil))
        } else if components == ["quick-log", "medicine"] {
            openToday(action: .logEvent(.medicine))
        } else if components == ["quick-log", "nursing-left"] {
            openToday(action: .startTimer(.nursing, .left))
        } else if components == ["quick-log", "nursing-right"] {
            openToday(action: .startTimer(.nursing, .right))
        } else if components == ["quick-log", "tummy-time"] {
            openToday(action: .startActivity(.tummyTime))
        } else if components == ["quick-log", "story-time"] {
            openToday(action: .startActivity(.storyTime))
        } else if components == ["quick-log", "bath"] {
            openToday(action: .startActivity(.bath))
        } else if components == ["quick-log", "diaper"] {
            openToday(action: .logDiaper)
        } else if components == ["quick-log", "temperature"] {
            openToday(action: .logEvent(.temperature))
        } else {
            selectedTab = .today
        }
    }

    func consumeAction() -> DeepLinkAction? {
        defer { pendingAction = nil }
        return pendingAction
    }

    func consumeNightLightCommand() -> NightLightCommand? {
        defer { pendingNightLightCommand = nil }
        return pendingNightLightCommand
    }

    func consumeAppointmentCommand() -> AppointmentRouteCommand? {
        defer { pendingAppointmentCommand = nil }
        return pendingAppointmentCommand
    }

    func consumeAgeGuideCommand() -> AgeGuideRouteCommand? {
        defer { pendingAgeGuideCommand = nil }
        return pendingAgeGuideCommand
    }

    func consumePuppyGuideCommand() -> PuppyGuideRouteCommand? {
        defer { pendingPuppyGuideCommand = nil }
        return pendingPuppyGuideCommand
    }

    func consumeRoutineCommand() -> RoutineRouteCommand? {
        defer { pendingRoutineCommand = nil }
        return pendingRoutineCommand
    }

    func presentSettings() {
        showingSettings = true
    }
}
