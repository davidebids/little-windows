import Combine
import Foundation
import SwiftData

@MainActor
final class ICloudSyncSettingsViewModel: ObservableObject {
    @Published private(set) var availability: ICloudSyncAvailability = .checking
    @Published private(set) var accountStatusDescription = "Checking iCloud..."
    @Published private(set) var containerStatusDescription = PersistenceService.iCloudContainerIdentifier
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var diagnostics: SyncDiagnosticSnapshot?
    @Published private(set) var startupErrorMessage = PersistenceService.startupErrorMessage

    private let statusService = SyncStatusService()

    func refresh(context: ModelContext) async {
        await statusService.refreshStatus()
        availability = statusService.availability
        accountStatusDescription = statusService.accountStatusDescription
        containerStatusDescription = statusService.containerStatusDescription
        lastCheckedAt = statusService.lastCheckedAt
        diagnostics = SyncDiagnosticsService.snapshot(context: context)
        startupErrorMessage = PersistenceService.startupErrorMessage
    }
}
