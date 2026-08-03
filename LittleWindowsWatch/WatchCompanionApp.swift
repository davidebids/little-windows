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

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(connectivity)
                .task {
                    connectivity.start()
                    connectivity.requestRefresh()
                }
        }
    }
}
