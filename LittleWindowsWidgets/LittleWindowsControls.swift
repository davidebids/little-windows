import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct StartSleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.StartSleep") {
            ControlWidgetButton(action: StartSleepTimerIntent()) {
                Label("Start Sleep", systemImage: "moon.stars.fill")
            }
        }
        .displayName("Start Sleep")
        .description("Start a sleep timer in Little Windows.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct StartNursingLeftControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.NursingLeft") {
            ControlWidgetButton(action: StartNursingLeftIntent()) {
                Label("Nurse Left", systemImage: "l.circle.fill")
            }
        }
        .displayName("Nurse Left")
        .description("Start a Left nursing timer.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct StartNursingRightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.NursingRight") {
            ControlWidgetButton(action: StartNursingRightIntent()) {
                Label("Nurse Right", systemImage: "r.circle.fill")
            }
        }
        .displayName("Nurse Right")
        .description("Start a Right nursing timer.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct StartTummyTimeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.TummyTime") {
            ControlWidgetButton(action: StartTummyTimeIntent()) {
                Label("Start Tummy", systemImage: "figure.play")
            }
        }
        .displayName("Start Tummy Time")
        .description("Start a tummy-time timer.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct StopActiveTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.StopTimer") {
            ControlWidgetButton(action: StopActiveTimerIntent()) {
                Label("Stop Timer", systemImage: "stop.fill")
            }
        }
        .displayName("Stop Active Timer")
        .description("Open Little Windows and immediately stop the primary timer.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct DiaperNightLightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.DiaperLight") {
            ControlWidgetButton(action: StartDiaperChangeLightIntent()) {
                Label("Diaper Light", systemImage: "lightbulb.min.fill")
            }
        }
        .displayName("Diaper Change Light")
        .description("Open a dim red light with a 10-minute timer.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct SoothingNightLightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleWindows.Control.SoothingLight") {
            ControlWidgetButton(action: StartSoothingLightIntent()) {
                Label("Soothing Light", systemImage: "moon.stars.fill")
            }
        }
        .displayName("Soothing Night Light")
        .description("Open the soothing light, breathing glow, and white noise.")
    }
}
