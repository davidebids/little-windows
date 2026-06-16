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
            let profiles = try context.fetch(FetchDescriptor<BabyProfile>())
            ProfileMigrationService.ensureProfilesAndAssignments(
                context: context,
                profiles: profiles
            )
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
