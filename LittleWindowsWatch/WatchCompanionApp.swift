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

    var body: some Scene {
        WindowGroup {
            Group {
                if showsNightLight {
                    WatchNightLightView { showsNightLight = false }
                } else {
                    WatchHomeView { showsNightLight = true }
                }
            }
            .environmentObject(connectivity)
            .onOpenURL { url in
                if WatchAppRoute.isNightLight(url) {
                    showsNightLight = true
                }
            }
            .task {
                connectivity.start()
                connectivity.requestRefresh()
            }
        }
    }
}
