import Combine
import Foundation
import SwiftData

@MainActor
final class ICloudSyncSettingsViewModel: ObservableObject {
    @Published private(set) var availability: ICloudSyncAvailability = .checking
    @Published private(set) var isICloudSyncEnabled = PersistenceService.isICloudSyncEnabled()
    @Published private(set) var syncMode = PersistenceService.familySyncMode()
    @Published private(set) var requiresRestart = PersistenceService.iCloudSyncChangeRequiresRestart
    @Published private(set) var accountStatusDescription = "Checking iCloud..."
    @Published private(set) var containerStatusDescription = PersistenceService.iCloudContainerIdentifier
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var diagnostics: SyncDiagnosticSnapshot?
    @Published private(set) var isLoadingDiagnostics = false
    @Published private(set) var startupErrorMessage = PersistenceService.startupErrorMessage

    private let statusService = SyncStatusService()

    func setICloudSyncEnabled(_ enabled: Bool) {
        PersistenceService.setICloudSyncEnabled(enabled)
        isICloudSyncEnabled = enabled
        syncMode = PersistenceService.familySyncMode()
        requiresRestart = PersistenceService.iCloudSyncChangeRequiresRestart
    }

    func refreshStatus(force: Bool = false) async {
        await statusService.refreshStatus(force: force)
        availability = statusService.availability
        isICloudSyncEnabled = PersistenceService.isICloudSyncEnabled()
        syncMode = PersistenceService.familySyncMode()
        requiresRestart = PersistenceService.iCloudSyncChangeRequiresRestart
        accountStatusDescription = statusService.accountStatusDescription
        containerStatusDescription = statusService.containerStatusDescription
        lastCheckedAt = statusService.lastCheckedAt
        startupErrorMessage = PersistenceService.startupErrorMessage
    }

    func refresh(context: ModelContext) async {
        await refreshStatus(force: true)
        await loadDiagnostics(context: context)
    }

    func loadDiagnostics(context: ModelContext) async {
        guard !isLoadingDiagnostics else { return }
        isLoadingDiagnostics = true
        defer { isLoadingDiagnostics = false }
        diagnostics = SyncDiagnosticsService.snapshot(context: context)
    }
}
