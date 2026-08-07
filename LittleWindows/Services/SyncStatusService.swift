import CloudKit
import Foundation
import SwiftData

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

enum ICloudRestoreEligibility: Equatable {
    case ready
    case unavailable(String)
}

enum ICloudRestoreOutcome: Equatable {
    case restored(profileCount: Int)
    case noDataArrived
    case unavailable(String)
    case failed(String)
}

@MainActor
enum ICloudRestoreService {
    static let defaultWaitDuration: Duration = .seconds(45)
    static let defaultPollInterval: Duration = .seconds(1)

    nonisolated static func eligibility(
        syncMode: FamilySyncMode,
        isUsingCloudKitStore: Bool,
        availability: ICloudSyncAvailability
    ) -> ICloudRestoreEligibility {
        guard syncMode == .privateICloudSync else {
            return .unavailable(
                "This install is not using Private iCloud Sync. You can import a JSON backup or continue with a new setup."
            )
        }
        guard isUsingCloudKitStore else {
            return .unavailable(
                "Little Windows could not open its private iCloud store on this launch. Check iCloud and reopen the app, or import a JSON backup."
            )
        }

        switch availability {
        case .available:
            return .ready
        case .checking:
            return .unavailable("Little Windows is still checking iCloud. Please try again.")
        case .disabled:
            return .unavailable(
                "Private iCloud Sync is turned off. You can import a JSON backup or continue with a new setup."
            )
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    static func restore(
        context: ModelContext
    ) async -> ICloudRestoreOutcome {
        #if DEBUG
        if ProcessInfo.processInfo.environment[
            "LITTLE_WINDOWS_UI_TEST_ICLOUD_RESTORE_WAITING"
        ] == "1" {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return .noDataArrived
            }
            return .noDataArrived
        }
        #endif

        return await restore(
            context: context,
            statusService: SyncStatusService(),
            waitDuration: defaultWaitDuration,
            pollInterval: defaultPollInterval
        )
    }

    static func restore(
        context: ModelContext,
        statusService: SyncStatusService,
        waitDuration: Duration,
        pollInterval: Duration
    ) async -> ICloudRestoreOutcome {
        let storeEligibility = eligibility(
            syncMode: PersistenceService.syncModeAtStartup,
            isUsingCloudKitStore: PersistenceService.isUsingCloudKitStore,
            availability: .available
        )
        if case .unavailable(let message) = storeEligibility {
            return .unavailable(message)
        }

        await statusService.refreshStatus(force: true)
        switch eligibility(
            syncMode: PersistenceService.syncModeAtStartup,
            isUsingCloudKitStore: PersistenceService.isUsingCloudKitStore,
            availability: statusService.availability
        ) {
        case .ready:
            return await waitForImportedProfiles(
                context: context,
                waitDuration: waitDuration,
                pollInterval: pollInterval
            )
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    static func waitForImportedProfiles(
        context: ModelContext,
        waitDuration: Duration,
        pollInterval: Duration
    ) async -> ICloudRestoreOutcome {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: waitDuration)

        while !Task.isCancelled {
            do {
                let profiles = try context.fetch(FetchDescriptor<CareProfile>())
                if !profiles.isEmpty {
                    _ = ProfileService.shared.ensureSelection(in: profiles)
                    return .restored(profileCount: profiles.count)
                }
            } catch {
                return .failed("Little Windows could not read the restored data: \(error.localizedDescription)")
            }

            guard clock.now < deadline else { break }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }

        return .noDataArrived
    }
}
