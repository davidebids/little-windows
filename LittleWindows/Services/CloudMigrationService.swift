import Foundation
import SwiftData

@MainActor
enum CloudMigrationService {
    static let migrationVersion = 1

    private static let hasMigratedKey = "hasMigratedLocalStoreToCloudKit"
    private static let completedAtKey = "migrationCompletedAt"
    private static let versionKey = "migrationVersion"
    private static let lastErrorKey = "cloudMigrationLastError"

    static func state(defaults: UserDefaults = .standard) -> CloudMigrationState {
        CloudMigrationState(
            hasMigratedLocalStoreToCloudKit: defaults.bool(forKey: hasMigratedKey),
            migrationCompletedAt: defaults.object(forKey: completedAtKey) as? Date,
            migrationVersion: defaults.integer(forKey: versionKey),
            lastErrorMessage: defaults.string(forKey: lastErrorKey)
        )
    }

    static func ensureMigrated(context: ModelContext, defaults: UserDefaults = .standard) {
        let currentState = state(defaults: defaults)
        guard !currentState.hasMigratedLocalStoreToCloudKit
                || currentState.migrationVersion < migrationVersion else {
            return
        }

        do {
            // Profile-scoped legacy migration is already performed by
            // SampleData.seedIfNeeded immediately before this call. Repeating
            // it here forced a second full-store audit on a fresh TestFlight
            // install while CloudKit records were still materializing.
            try context.save()

            let completedAt = Date()
            defaults.set(true, forKey: hasMigratedKey)
            defaults.set(completedAt, forKey: completedAtKey)
            defaults.set(migrationVersion, forKey: versionKey)
            defaults.removeObject(forKey: lastErrorKey)
            PersistenceService.recordLocalSave(at: completedAt, defaults: defaults)
        } catch {
            defaults.set(error.localizedDescription, forKey: lastErrorKey)
        }
    }
}
