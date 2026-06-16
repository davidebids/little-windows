import Foundation

enum LittleWindowsTab: Hashable {
    case today
    case history
    case insights
    case milestones
    case nightLight
    case medical
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
    @Published var pendingProfileID: UUID?
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
        } else if components == ["history"] {
            selectedTab = .history
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
            selectedTab = .insights
        } else if components == ["insights"] {
            selectedTab = .insights
        } else if components == ["puppy-guide"] {
            selectedTab = .milestones
            pendingAgeGuideCommand = .list
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
            selectedTab = .insights
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

    func presentSettings() {
        showingSettings = true
    }
}
