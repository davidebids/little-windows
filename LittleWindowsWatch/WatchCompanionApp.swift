import SwiftUI
import WatchKit

final class WatchCompanionAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        Task { @MainActor in
            WatchConnectivityClient.shared.handle(backgroundTasks)
        }
    }
}

@main
struct LittleWindowsWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchCompanionAppDelegate.self)
    private var appDelegate
    @StateObject private var connectivity = WatchConnectivityClient.shared
    @State private var showsNightLight = false
    @State private var showsWeather = false

    var body: some Scene {
        WindowGroup {
            Group {
                if showsNightLight {
                    WatchNightLightView { showsNightLight = false }
                } else if showsWeather {
                    NavigationStack {
                        WatchWeatherView()
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showsWeather = false } } }
                    }
                } else {
                    WatchHomeView { showsNightLight = true }
                }
            }
            .environmentObject(connectivity)
            .onOpenURL { url in
                if WatchAppRoute.isNightLight(url) {
                    showsNightLight = true
                } else if url.scheme == "littlewindows", url.host == "watch", url.path == "/weather" {
                    showsWeather = true
                }
            }
            .task {
                #if DEBUG
                if WeatherPreviewData.enabled && CommandLine.arguments.contains("--weather-detail") { showsWeather = true }
                #endif
                connectivity.start()
                connectivity.requestRefresh()
            }
        }
    }
}
