import Foundation

enum LittleWindowsTab: Hashable {
    case today
    case food
    case reports
    case milestones
    case nightLight
    case medical
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
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var selectedTab: LittleWindowsTab = .today
    @Published var pendingAction: DeepLinkAction?
    @Published var pendingNightLightCommand: NightLightCommand?
    @Published var pendingAppointmentCommand: AppointmentRouteCommand?
    @Published var pendingAgeGuideCommand: AgeGuideRouteCommand?
    @Published var pendingPuppyGuideCommand: PuppyGuideRouteCommand?
    @Published var pendingFoodCommand: FoodRouteCommand?
    @Published var pendingProfileID: UUID?
    @Published var selectedReportsMode: ReportsDisplayMode = ReportsDisplayMode(
        rawValue: UserDefaults.standard.string(forKey: "reportsDisplayMode") ?? ""
    ) ?? .day
    @Published var showingSettings = false
    @Published var isDataReady = false

    private init() {}

    func route(_ url: URL) {
        guard url.scheme == "littlewindows" else { return }
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

        if components == ["today"] {
            selectedTab = .today
        } else if components == ["food"] {
            selectedTab = .food
            pendingFoodCommand = .food
        } else if components == ["food", "shopping"] {
            selectedTab = .food
            pendingFoodCommand = .shopping
        } else if components == ["food", "quick-add"] {
            selectedTab = .food
            pendingFoodCommand = .quickAdd
        } else if components.count >= 3,
                  components[0] == "food",
                  components[1] == "shopping",
                  let uuid = UUID(uuidString: components[2]) {
            selectedTab = .food
            pendingFoodCommand = components.count >= 4 && components[3] == "mode"
                ? .shoppingMode(uuid)
                : .shoppingList(uuid)
        } else if components == ["food", "inventory"] {
            selectedTab = .food
            pendingFoodCommand = .inventory
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "inventory",
                  let uuid = UUID(uuidString: components[2]) {
            selectedTab = .food
            pendingFoodCommand = .inventoryItem(uuid)
        } else if components == ["food", "meal-prep"] {
            selectedTab = .food
            pendingFoodCommand = .mealPrep
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "meal-prep",
                  let uuid = UUID(uuidString: components[2]) {
            selectedTab = .food
            pendingFoodCommand = .mealPrepItem(uuid)
        } else if components.count == 3,
                  components[0] == "food",
                  components[1] == "stores",
                  let uuid = UUID(uuidString: components[2]) {
            selectedTab = .food
            pendingFoodCommand = .store(uuid)
        } else if components == ["history"] {
            selectedReportsMode = .day
            selectedTab = .reports
        } else if components == ["history", "list"] {
            selectedReportsMode = .list
            selectedTab = .reports
        } else if components == ["reports"] || components == ["calendar"] {
            selectedReportsMode = .day
            selectedTab = .reports
        } else if components.count == 2,
                  components[0] == "reports",
                  let mode = ReportsDisplayMode(rawValue: components[1]) {
            selectedReportsMode = mode
            selectedTab = .reports
        } else if components == ["settings"] {
            showingSettings = true
        } else if components == ["milestones"] || components == ["memories"] {
            selectedTab = .milestones
        } else if components == ["age-guides"] {
            selectedTab = .milestones
            pendingAgeGuideCommand = .list
        } else if components.count == 2,
                  components[0] == "age-guide",
                  let month = Int(components[1]) {
            selectedTab = .milestones
            pendingAgeGuideCommand = .detail(month)
        } else if components == ["appointments"] || components == ["visits"] {
            selectedTab = .today
            pendingAppointmentCommand = .list
        } else if components.count >= 2, components[0] == "appointment",
                  let uuid = UUID(uuidString: components[1]) {
            selectedTab = .today
            pendingAppointmentCommand = components.count >= 3 && components[2] == "notes"
                ? .notes(uuid)
                : .detail(uuid)
        } else if components == ["medical"] {
            selectedReportsMode = .summary
            selectedTab = .reports
        } else if components == ["insights"] {
            selectedReportsMode = .summary
            selectedTab = .reports
        } else if components == ["puppy-guide"] {
            selectedTab = .today
            pendingPuppyGuideCommand = .current
        } else if components == ["night-light"] {
            selectedTab = .nightLight
            pendingNightLightCommand = .open
        } else if components == ["night-light", "stop"] {
            selectedTab = .nightLight
            pendingNightLightCommand = .stop
        } else if components.count == 2,
                  components[0] == "night-light",
                  let preset = NightLightPresetKind(slug: components[1]) {
            selectedTab = .nightLight
            pendingNightLightCommand = .start(preset)
        } else if components == ["active-timer"] {
            selectedTab = .today
            pendingAction = .showActiveTimer
        } else if components == ["prediction"] {
            selectedReportsMode = .summary
            selectedTab = .reports
        } else if components.count == 2, components[0] == "event" {
            selectedTab = .today
            if let uuid = UUID(uuidString: components[1]) { pendingAction = .showEvent(uuid) }
        } else if components == ["action", "stop-active"] {
            selectedTab = .today
            pendingAction = .stopActiveTimer
        } else if components.count == 3, components[0] == "action", components[1] == "stop" {
            selectedTab = .today
            if let uuid = UUID(uuidString: components[2]) { pendingAction = .stopTimer(uuid) }
        } else if components.count == 3, components[0] == "action", components[1] == "resume" {
            selectedTab = .today
            if let uuid = UUID(uuidString: components[2]) { pendingAction = .resumeTimer(uuid) }
        } else if components.count == 3, components[0] == "action", components[1] == "switch-side" {
            selectedTab = .today
            if let uuid = UUID(uuidString: components[2]) { pendingAction = .switchNursingSide(uuid) }
        } else if components == ["quick-log", "sleep"] {
            selectedTab = .today
            pendingAction = .startTimer(.sleep, nil)
        } else if components == ["quick-log", "food"] {
            selectedTab = .today
            pendingAction = .logEvent(.food)
        } else if components == ["quick-log", "water"] {
            selectedTab = .today
            pendingAction = .logEvent(.water)
        } else if components == ["quick-log", "pee"] {
            selectedTab = .today
            pendingAction = .logEvent(.potty)
        } else if components == ["quick-log", "poop"] {
            selectedTab = .today
            pendingAction = .logEvent(.potty)
        } else if components == ["quick-log", "walk"] {
            selectedTab = .today
            pendingAction = .startTimer(.walk, nil)
        } else if components == ["quick-log", "medicine"] {
            selectedTab = .today
            pendingAction = .logEvent(.medicine)
        } else if components == ["quick-log", "nursing-left"] {
            selectedTab = .today
            pendingAction = .startTimer(.nursing, .left)
        } else if components == ["quick-log", "nursing-right"] {
            selectedTab = .today
            pendingAction = .startTimer(.nursing, .right)
        } else if components == ["quick-log", "tummy-time"] {
            selectedTab = .today
            pendingAction = .startActivity(.tummyTime)
        } else if components == ["quick-log", "story-time"] {
            selectedTab = .today
            pendingAction = .startActivity(.storyTime)
        } else if components == ["quick-log", "bath"] {
            selectedTab = .today
            pendingAction = .startActivity(.bath)
        } else if components == ["quick-log", "diaper"] {
            selectedTab = .today
            pendingAction = .logDiaper
        } else if components == ["quick-log", "temperature"] {
            selectedTab = .today
            pendingAction = .logEvent(.temperature)
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

    func presentSettings() {
        showingSettings = true
    }
}
