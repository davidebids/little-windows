import Foundation

enum ICloudSyncAvailability: Equatable {
    case checking
    case available
    case unavailable(String)

    var title: String {
        switch self {
        case .checking:
            return "Waiting for iCloud"
        case .available:
            return "iCloud Sync On"
        case .unavailable:
            return "iCloud unavailable"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Checking this device's iCloud account."
        case .available:
            return "Private iCloud Sync keeps your Little Windows data available on devices signed into the same Apple Account."
        case .unavailable(let message):
            return message
        }
    }
}

struct CloudMigrationState: Equatable {
    var hasMigratedLocalStoreToCloudKit: Bool
    var migrationCompletedAt: Date?
    var migrationVersion: Int
    var lastErrorMessage: String?
}

struct SyncDiagnosticCount: Identifiable, Equatable {
    var name: String
    var count: Int

    var id: String { name }
}

struct SyncDiagnosticSnapshot: Equatable {
    var generatedAt: Date
    var profileCount: Int
    var activeProfileCount: Int
    var recordCounts: [SyncDiagnosticCount]
    var orphanedProfileScopedRecordCount: Int
    var duplicateEthanProfileCount: Int
    var migrationState: CloudMigrationState
    var lastLocalSaveAt: Date?
}

enum FamilyShareMode: String, Equatable {
    case localOnly
    case privateICloudSync
    case sharedFamilySync

    var displayName: String {
        switch self {
        case .localOnly:
            return "Local only"
        case .privateICloudSync:
            return "Private iCloud Sync"
        case .sharedFamilySync:
            return "Shared Family Sync"
        }
    }
}

struct FamilyShareState: Equatable {
    var mode: FamilyShareMode
    var ownerDescription: String
    var participantDescription: String
    var sharingIsImplemented: Bool
    var lastErrorMessage: String?
}
