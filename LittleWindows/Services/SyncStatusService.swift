import CloudKit
import Foundation

@MainActor
final class SyncStatusService {
    private let containerIdentifier: String
    private let defaults: UserDefaults

    private(set) var availability: ICloudSyncAvailability = .checking
    private(set) var accountStatusDescription = "Checking iCloud..."
    private(set) var containerStatusDescription = PersistenceService.iCloudContainerIdentifier
    private(set) var lastCheckedAt: Date?
    private(set) var userFriendlyErrorMessage: String?

    var isICloudAvailable: Bool {
        availability == .available
    }

    init(
        containerIdentifier: String = PersistenceService.iCloudContainerIdentifier,
        defaults: UserDefaults = .standard
    ) {
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
    }

    func refreshStatus() async {
        lastCheckedAt = Date()
        guard PersistenceService.isICloudSyncEnabled(defaults: defaults) else {
            availability = .disabled
            accountStatusDescription = "Off"
            containerStatusDescription = "Local only"
            userFriendlyErrorMessage = nil
            return
        }

        do {
            let container = CKContainer(identifier: containerIdentifier)
            let status = try await container.accountStatus()
            switch status {
            case .available:
                availability = .available
                accountStatusDescription = "Signed in to iCloud"
                userFriendlyErrorMessage = nil
            case .noAccount:
                let message = "Sign in to iCloud in Settings to sync Little Windows across your devices."
                availability = .unavailable(message)
                accountStatusDescription = "No iCloud account"
                userFriendlyErrorMessage = message
            case .restricted:
                let message = "iCloud is restricted on this device. Your data is still saved locally."
                availability = .unavailable(message)
                accountStatusDescription = "iCloud restricted"
                userFriendlyErrorMessage = message
            case .couldNotDetermine:
                let message = "Little Windows could not determine iCloud status. Your data is still saved locally."
                availability = .unavailable(message)
                accountStatusDescription = "Could not determine"
                userFriendlyErrorMessage = message
            case .temporarilyUnavailable:
                let message = "iCloud is temporarily unavailable. Local changes will sync later."
                availability = .unavailable(message)
                accountStatusDescription = "Temporarily unavailable"
                userFriendlyErrorMessage = message
            @unknown default:
                let message = "Unknown iCloud status. Your data is still saved locally."
                availability = .unavailable(message)
                accountStatusDescription = "Unknown status"
                userFriendlyErrorMessage = message
            }
        } catch {
            let message = "iCloud is not available on this device. Your data is still saved locally."
            availability = .unavailable(message)
            accountStatusDescription = "Status check failed"
            userFriendlyErrorMessage = error.localizedDescription
        }
    }
}
