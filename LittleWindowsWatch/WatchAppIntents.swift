import AppIntents

private protocol WatchQuickActionIntent: AppIntent {
    static var actionID: String { get }
    static var optionID: String? { get }
}

extension WatchQuickActionIntent {
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let submitted = await MainActor.run {
            let client = WatchConnectivityClient.shared
            guard let action = client.state.allActions.first(where: { $0.id == Self.actionID }) else {
                return false
            }
            return client.perform(action, optionID: Self.optionID)
        }
        if submitted {
            return .result(dialog: "Added to Little Windows.")
        }
        return .result(dialog: "That action isn't available for the selected profile right now.")
    }
}

struct WatchStartSleepIntent: WatchQuickActionIntent {
    static let title: LocalizedStringResource = "Start Nap"
    static let actionID = "sleep"
    static let optionID: String? = "nap"
}

struct WatchStartNursingLeftIntent: WatchQuickActionIntent {
    static let title: LocalizedStringResource = "Nurse Left"
    static let actionID = "nursing"
    static let optionID: String? = "left"
}

struct WatchStartNursingRightIntent: WatchQuickActionIntent {
    static let title: LocalizedStringResource = "Nurse Right"
    static let actionID = "nursing"
    static let optionID: String? = "right"
}

struct WatchLogWetDiaperIntent: WatchQuickActionIntent {
    static let title: LocalizedStringResource = "Log Wet Diaper"
    static let actionID = "diaper"
    static let optionID: String? = "wet"
}

struct WatchLogDogFoodIntent: WatchQuickActionIntent {
    static let title: LocalizedStringResource = "Log Dog Food"
    static let actionID = "food"
    static let optionID: String? = nil
}

struct WatchStartDogWalkIntent: WatchQuickActionIntent {
    static let title: LocalizedStringResource = "Start Dog Walk"
    static let actionID = "walk"
    static let optionID: String? = nil
}

struct LittleWindowsWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchStartSleepIntent(),
            phrases: ["Start a nap in \(.applicationName)"],
            shortTitle: "Start Nap",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: WatchStartNursingLeftIntent(),
            phrases: ["Nurse left in \(.applicationName)"],
            shortTitle: "Nurse Left",
            systemImageName: "l.circle.fill"
        )
        AppShortcut(
            intent: WatchStartNursingRightIntent(),
            phrases: ["Nurse right in \(.applicationName)"],
            shortTitle: "Nurse Right",
            systemImageName: "r.circle.fill"
        )
        AppShortcut(
            intent: WatchLogWetDiaperIntent(),
            phrases: ["Log a wet diaper in \(.applicationName)"],
            shortTitle: "Wet Diaper",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: WatchLogDogFoodIntent(),
            phrases: ["Log dog food in \(.applicationName)"],
            shortTitle: "Dog Food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: WatchStartDogWalkIntent(),
            phrases: ["Start a dog walk in \(.applicationName)"],
            shortTitle: "Dog Walk",
            systemImageName: "figure.walk"
        )
    }
}
