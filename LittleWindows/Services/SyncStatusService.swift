import CloudKit
import Foundation

@MainActor
final class SyncStatusService {
    private struct CachedStatus {
        var availability: ICloudSyncAvailability
        var accountStatusDescription: String
        var containerStatusDescription: String
        var lastCheckedAt: Date
        var userFriendlyErrorMessage: String?
    }

    private static var cachedStatus: CachedStatus?
    private static let cacheDuration: TimeInterval = 30

    private let containerIdentifier: String
    private let defaults: UserDefaults

    private(set) var availability: ICloudSyncAvailability = .checking
    private(set) var accountStatusDescription = "Checking iCloud..."
    private(set) var containerStatusDescription = "Little Windows iCloud"
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

    func refreshStatus(force: Bool = false) async {
        if !force,
           let cached = Self.cachedStatus,
           Date().timeIntervalSince(cached.lastCheckedAt) < Self.cacheDuration {
            availability = cached.availability
            accountStatusDescription = cached.accountStatusDescription
            containerStatusDescription = cached.containerStatusDescription
            lastCheckedAt = cached.lastCheckedAt
            userFriendlyErrorMessage = cached.userFriendlyErrorMessage
            return
        }

        lastCheckedAt = Date()
        guard PersistenceService.isICloudSyncEnabled(defaults: defaults) else {
            availability = .disabled
            accountStatusDescription = "Off"
            containerStatusDescription = "Local only"
            userFriendlyErrorMessage = nil
            cacheCurrentStatus()
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
        cacheCurrentStatus()
    }

    private func cacheCurrentStatus() {
        guard let lastCheckedAt else { return }
        Self.cachedStatus = CachedStatus(
            availability: availability,
            accountStatusDescription: accountStatusDescription,
            containerStatusDescription: containerStatusDescription,
            lastCheckedAt: lastCheckedAt,
            userFriendlyErrorMessage: userFriendlyErrorMessage
        )
    }
}
