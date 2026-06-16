import AppIntents
import Foundation

protocol LittleWindowsURLIntent: AppIntent {
    var destinationURL: URL { get }
}

extension LittleWindowsURLIntent {
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        IntegrationCommandStore.enqueue(destinationURL)
        if await IntegrationCommandStore.deliverToRunningApp(destinationURL) {
            return .result()
        }
        if #available(iOS 18.2, *) {
            return .result(opensIntent: OpenURLIntent(destinationURL))
        }
        return .result()
    }
}

struct StopActiveTimerIntent: LittleWindowsURLIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Active Timer"
    static let description = IntentDescription("Stops the primary timer without saving it, so it can be reviewed or resumed.")
    var destinationURL: URL { URL(string: "littlewindows://action/stop-active")! }
}

struct StopTimerIntent: LittleWindowsURLIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let description = IntentDescription("Stops the selected timer without saving it.")

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}

    init(eventID: String) {
        self.eventID = eventID
    }

    var destinationURL: URL {
        URL(string: "littlewindows://action/stop/\(eventID)")!
    }
}

struct ResumeTimerIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Resume Timer"
    static let description = IntentDescription("Resumes a stopped timer draft.")

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}

    init(eventID: String) {
        self.eventID = eventID
    }

    var destinationURL: URL {
        URL(string: "littlewindows://action/resume/\(eventID)")!
    }
}

struct SwitchNursingSideIntent: LittleWindowsURLIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Switch Nursing Side"

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}

    init(eventID: String) {
        self.eventID = eventID
    }

    var destinationURL: URL {
        URL(string: "littlewindows://action/switch-side/\(eventID)")!
    }
}

struct StartSleepTimerIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Sleep Timer"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/sleep")! }
}

struct StartNursingLeftIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Nursing Left"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/nursing-left")! }
}

struct StartNursingRightIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Nursing Right"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/nursing-right")! }
}

struct StartTummyTimeIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Tummy Time"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/tummy-time")! }
}

struct StartStoryTimeIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Story Time"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/story-time")! }
}

struct StartBathIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Bath"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/bath")! }
}

struct LogDiaperIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Diaper"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/diaper")! }
}

struct LogTemperatureIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Temperature"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/temperature")! }
}

struct OpenNightLightIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Open Night Light"
    var destinationURL: URL { URL(string: "littlewindows://night-light")! }
}

struct StartDiaperChangeLightIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Diaper Change Light"
    var destinationURL: URL {
        URL(string: "littlewindows://night-light/diaper-change")!
    }
}

struct StartNursingLightIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Nursing Light"
    var destinationURL: URL {
        URL(string: "littlewindows://night-light/nursing")!
    }
}

struct StartSoothingLightIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Soothing Light"
    var destinationURL: URL {
        URL(string: "littlewindows://night-light/soothing")!
    }
}

struct StopNightLightIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Stop Night Light"
    var destinationURL: URL {
        URL(string: "littlewindows://night-light/stop")!
    }
}

struct OpenLittleWindowsIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Open Little Windows"

    @Parameter(title: "Destination")
    var destination: String

    init() {
        destination = "today"
    }

    init(destination: String) {
        self.destination = destination
    }

    var destinationURL: URL {
        URL(string: "littlewindows://\(destination)")!
    }
}

struct LittleWindowsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSleepTimerIntent(),
            phrases: ["Start sleep in \(.applicationName)"],
            shortTitle: "Start Sleep",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: StartNursingLeftIntent(),
            phrases: ["Start nursing left in \(.applicationName)"],
            shortTitle: "Nurse Left",
            systemImageName: "l.circle.fill"
        )
        AppShortcut(
            intent: StartNursingRightIntent(),
            phrases: ["Start nursing right in \(.applicationName)"],
            shortTitle: "Nurse Right",
            systemImageName: "r.circle.fill"
        )
        AppShortcut(
            intent: StopActiveTimerIntent(),
            phrases: ["Stop the timer in \(.applicationName)"],
            shortTitle: "Stop Timer",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: OpenNightLightIntent(),
            phrases: ["Open the night light in \(.applicationName)"],
            shortTitle: "Night Light",
            systemImageName: "lightbulb.fill"
        )
        AppShortcut(
            intent: StartDiaperChangeLightIntent(),
            phrases: ["Start the diaper light in \(.applicationName)"],
            shortTitle: "Diaper Light",
            systemImageName: "lightbulb.min.fill"
        )
        AppShortcut(
            intent: StartSoothingLightIntent(),
            phrases: ["Start the soothing light in \(.applicationName)"],
            shortTitle: "Soothing Light",
            systemImageName: "moon.stars.fill"
        )
    }
}
