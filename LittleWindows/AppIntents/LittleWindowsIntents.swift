import AppIntents
import Foundation

protocol LittleWindowsURLIntent: AppIntent {
    var destinationURL: URL { get }
}

extension LittleWindowsURLIntent {
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        let commandURL = IntegrationCommandStore.enqueue(destinationURL)
        if await IntegrationCommandStore.deliverToRunningApp(commandURL) {
            return .result()
        }
        if #available(iOS 18.2, *) {
            return .result(opensIntent: OpenURLIntent(commandURL))
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

struct ResumeTimerIntent: LittleWindowsURLIntent, LiveActivityIntent {
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

struct RepeatLastLogIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Repeat Last Log"
    static let description = IntentDescription("Repeats the most recent quick-repeatable care log.")
    var destinationURL: URL { URL(string: "littlewindows://quick-log/repeat-last")! }
}

struct LogFeedIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Feed"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/feed")! }
}

struct LogSolidsIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Solids"
    static let description = IntentDescription("Opens a solids meal when a child profile is active.")
    var destinationURL: URL { URL(string: "littlewindows://quick-log/solids")! }
}

struct OpenSolidsIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Open Solids"
    static let description = IntentDescription("Opens the solids food database, plans, and tracker when a child profile is active.")
    var destinationURL: URL { URL(string: "littlewindows://care/solids")! }
}

struct LogMedicineIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Medicine"
    static let description = IntentDescription("Opens Medications to record a scheduled or as-needed dose.")
    var destinationURL: URL { URL(string: "littlewindows://quick-log/medicine")! }
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

struct LogDogFoodIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Dog Food"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/food")! }
}

struct LogDogWaterIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Log Dog Water"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/water")! }
}

struct StartDogWalkIntent: LittleWindowsURLIntent {
    static let title: LocalizedStringResource = "Start Dog Walk"
    var destinationURL: URL { URL(string: "littlewindows://quick-log/walk")! }
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
