import CloudKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class PersistenceStartupController: ObservableObject {
    @Published private(set) var modelContainer: ModelContainer?
    @Published private(set) var failure: PersistenceStartupFailure?
    @Published private(set) var recoveryBackups = [AutomaticRecoveryBackup]()
    @Published private(set) var isWorking = false
    @Published private(set) var operationErrorMessage: String?
    @Published private(set) var isDataReady = false
    private var hasStarted = false

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        // Give SwiftUI a frame to present the branded launch view before the
        // synchronous SwiftData store open begins.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #if DEBUG
        if let rawDelay = ProcessInfo.processInfo.environment[
            "LITTLE_WINDOWS_STARTUP_PREVIEW_DELAY_MS"
        ], let delay = Double(rawDelay), delay > 0 {
            try? await Task.sleep(for: .milliseconds(min(delay, 30_000)))
        }
        #endif
        attemptOpen()
    }

    func markDataReady() {
        isDataReady = true
    }

    func retry() {
        guard !isWorking else { return }
        isWorking = true
        operationErrorMessage = nil
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.attemptOpen()
            self?.isWorking = false
        }
    }

    func restore(_ backup: AutomaticRecoveryBackup) {
        recover(using: backup)
    }

    func startFresh() {
        recover(using: nil)
    }

    private func recover(using backup: AutomaticRecoveryBackup?) {
        guard !isWorking else { return }
        isWorking = true
        operationErrorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            do {
                let backupData = try backup.map {
                    try DataExportImportService.validatedRecoveryBackupData(at: $0.url)
                }
                let archiveURL = try PersistenceService.preserveUnreadableStore()
                let container = try PersistenceService.makeFreshLocalModelContainer(
                    preservedStoreAt: archiveURL
                )
                if let backupData {
                    try DataExportImportService.importData(
                        backupData,
                        context: container.mainContext,
                        recordLocalSave: false,
                        createRecoveryBackup: false
                    )
                    PersistenceService.recordLocalSave()
                    let hasProfiles = !((try? container.mainContext.fetch(
                        FetchDescriptor<CareProfile>()
                    )) ?? []).isEmpty
                    UserDefaults.standard.set(
                        hasProfiles,
                        forKey: FirstRunOnboarding.completedKey
                    )
                } else {
                    UserDefaults.standard.removeObject(
                        forKey: FirstRunOnboarding.completedKey
                    )
                }
                activate(container)
            } catch {
                operationErrorMessage = "Recovery could not finish: \(error.localizedDescription)"
                refreshRecoveryBackups()
            }
            isWorking = false
        }
    }

    private func attemptOpen() {
        do {
            activate(try PersistenceService.makeModelContainer())
        } catch let startupFailure as PersistenceStartupFailure {
            modelContainer = nil
            failure = startupFailure
            refreshRecoveryBackups()
            WidgetSnapshotService.clear()
            Task { await LiveActivityManager.shared.endAll() }
        } catch {
            modelContainer = nil
            failure = PersistenceStartupFailure(
                syncMode: PersistenceService.syncModeAtStartup,
                cloudErrorDescription: nil,
                localErrorDescription: error.localizedDescription,
                storeURL: PersistenceService.storeURL
            )
            refreshRecoveryBackups()
            WidgetSnapshotService.clear()
            Task { await LiveActivityManager.shared.endAll() }
        }
    }

    private func activate(_ container: ModelContainer) {
        isDataReady = false
        DeepLinkRouter.shared.isDataReady = false
        CloudKitSharingService.install(container: container)
        IntegrationCommandStore.installInAppHandler { url in
            let processed = await IntegrationCommandProcessor.process(
                url,
                container: container
            )
            if processed {
                IntegrationCommandStore.clearPendingURL(matching: url)
            }
            return processed
        }
        failure = nil
        operationErrorMessage = nil
        modelContainer = container
    }

    private func refreshRecoveryBackups() {
        recoveryBackups = DataExportImportService.automaticRecoveryBackups()
    }
}

@main
struct LittleWindowsApp: App {
    @StateObject private var startupController = PersistenceStartupController()
    @UIApplicationDelegateAdaptor(LittleWindowsAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if let modelContainer = startupController.modelContainer {
                ZStack {
                    RootView()
                        .modelContainer(modelContainer)
                        .opacity(startupController.isDataReady ? 1 : 0)
                        .allowsHitTesting(startupController.isDataReady)

                    if !startupController.isDataReady {
                        LittleWindowsLaunchView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: startupController.isDataReady)
                .task {
                    if !startupController.isDataReady {
                        await SampleData.seedIfNeeded(in: modelContainer.mainContext)
                        if PersistenceService.isICloudSyncEnabled() {
                            CloudMigrationService.ensureMigrated(context: modelContainer.mainContext)
                        }
                        DeepLinkRouter.shared.isDataReady = true
                        startupController.markDataReady()
                        scheduleLaunchMaintenance(container: modelContainer)
                    }
                }
            } else if startupController.failure != nil {
                PersistenceRecoveryView(controller: startupController)
            } else {
                LittleWindowsLaunchView()
                    .task {
                        await startupController.start()
                    }
            }
        }
    }

    @MainActor
    private func scheduleLaunchMaintenance(container modelContainer: ModelContainer) {
        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            await NotificationManager.shared.configure()
            CloudKitSharingService.processPendingAcceptedShareIfNeeded()
        }

        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            await AppInteractionMonitor.waitUntilIdle()
            guard !Task.isCancelled else { return }
            if PersistenceService.familySyncMode() == .sharedFamilySync {
                _ = try? await CloudKitSharingService.shared.syncNow(
                    context: modelContainer.mainContext,
                    reason: .launch
                )
            }
        }
    }
}

private struct LittleWindowsLaunchView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.11),
                    Color(red: 0.055, green: 0.035, blue: 0.24),
                    Color(red: 0.12, green: 0.055, blue: 0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.purple.opacity(0.24))
                .frame(width: 330, height: 330)
                .blur(radius: 70)
                .offset(x: 130, y: 250)

            Circle()
                .fill(Color.indigo.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 65)
                .offset(x: -150, y: -260)

            VStack(spacing: 24) {
                LittleWindowsLaunchLogo()

                VStack(spacing: 7) {
                    Text("Little Windows")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(-0.7)

                    Text("Your day, made clearer.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                ProgressView()
                    .controlSize(.small)
                    .tint(Color(red: 1, green: 0.86, blue: 0.58))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Little Windows is loading")
    }
}

private struct LittleWindowsLaunchLogo: View {
    private let glow = LinearGradient(
        colors: [
            Color(red: 1, green: 0.98, blue: 0.78),
            Color(red: 1, green: 0.74, blue: 0.42),
            Color(red: 0.76, green: 0.48, blue: 1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 58,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 58,
                style: .continuous
            )
            .fill(Color(red: 0.025, green: 0.025, blue: 0.15).opacity(0.88))
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 58,
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 14,
                    topTrailingRadius: 58,
                    style: .continuous
                )
                .stroke(glow, lineWidth: 8)
            }

            Image(systemName: "moon.fill")
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(glow)
                .rotationEffect(.degrees(-14))
                .offset(x: -8, y: 7)

            Image(systemName: "sparkle")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.93, blue: 0.7))
                .offset(x: 39, y: -33)
        }
        .frame(width: 136, height: 154)
        .shadow(
            color: Color(red: 1, green: 0.72, blue: 0.45).opacity(0.28),
            radius: 17
        )
        .shadow(color: Color.purple.opacity(0.5), radius: 32, y: 12)
        .accessibilityHidden(true)
    }
}

private struct PersistenceRecoveryView: View {
    @ObservedObject var controller: PersistenceStartupController
    @State private var backupToRestore: AutomaticRecoveryBackup?
    @State private var confirmingFreshStart = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recoveryHeader

                    if let message = controller.operationErrorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }

                    recoveryActions

                    if !controller.recoveryBackups.isEmpty {
                        backupSection
                    }
                }
                .padding(22)
            }
            .background(AppTheme.background)
            .navigationTitle("Data Recovery")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .alert(
            "Restore this backup?",
            isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
            ),
            presenting: backupToRestore
        ) { backup in
            Button("Restore \(backup.displayName)", role: .destructive) {
                backupToRestore = nil
                controller.restore(backup)
            }
            Button("Cancel", role: .cancel) {
                backupToRestore = nil
            }
        } message: { _ in
            Text("The unreadable store will be preserved first. The backup will open in a new local-only store, so nothing is uploaded until you deliberately turn sync back on.")
        }
        .alert("Start with an empty store?", isPresented: $confirmingFreshStart) {
            Button("Start Empty", role: .destructive) {
                controller.startFresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Little Windows will preserve the unreadable store before creating an empty local-only store. This does not delete iCloud or Family Sync data.")
        }
        .overlay {
            if controller.isWorking {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView("Working safely...")
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private var recoveryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 16))

            Text("Little Windows couldn’t open its data store")
                .font(.title2.bold())
            Text("Your existing store has not been deleted or overwritten. Retry first, restore an automatic backup, or preserve the unreadable store and start safely with an empty local copy.")
                .foregroundStyle(.secondary)
        }
    }

    private var recoveryActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                controller.retry()
            } label: {
                Label("Retry Opening Data", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(role: .destructive) {
                confirmingFreshStart = true
            } label: {
                Label("Preserve Store and Start Empty", systemImage: "archivebox.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .disabled(controller.isWorking)
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatic recovery backups")
                .font(.headline)
            Text("These backups were created before a previous import or full deletion.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(controller.recoveryBackups) { backup in
                Button {
                    backupToRestore = backup
                } label: {
                    Label("Restore \(backup.displayName)", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(controller.isWorking)
            }
        }
        .padding(16)
        .appSurface(cornerRadius: 18)
    }

}

final class LittleWindowsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = LittleWindowsSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudKitSharingService.handleAcceptedShare(metadata: cloudKitShareMetadata)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        CloudKitSharingService.handleRemoteNotification(
            userInfo,
            completion: completionHandler
        )
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        SyncDiagnosticsService.recordRemoteNotificationRegistrationSuccess()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SyncDiagnosticsService.recordRemoteNotificationRegistrationFailure(error)
    }
}

final class LittleWindowsSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudKitSharingService.handleAcceptedShare(metadata: cloudKitShareMetadata)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Task { @MainActor in
            for context in URLContexts {
                let url = context.url
                if await IntegrationCommandStore.deliverToRunningApp(url) {
                    IntegrationCommandStore.clearPendingURL(matching: url)
                } else {
                    DeepLinkRouter.shared.route(url)
                }
            }
        }
    }
}
