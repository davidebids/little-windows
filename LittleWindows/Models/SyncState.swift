import Foundation

enum FamilySyncMode: String, CaseIterable, Identifiable, Equatable {
    case localOnly
    case privateICloudSync
    case sharedFamilySync

    var id: String { rawValue }

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

    var requiresICloudAccount: Bool {
        self != .localOnly
    }
}

enum ICloudSyncAvailability: Equatable {
    case checking
    case available
    case disabled
    case unavailable(String)

    var title: String {
        switch self {
        case .checking:
            return "Waiting for iCloud"
        case .available:
            return "iCloud Sync On"
        case .disabled:
            return "iCloud Sync Off"
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
        case .disabled:
            return "iCloud Sync is turned off. Little Windows keeps data local to this device."
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
    var duplicateChildProfileNameCount: Int
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

enum FamilyShareRole: String, Equatable {
    case none
    case owner
    case participant

    var displayName: String {
        switch self {
        case .none:
            return "Not sharing"
        case .owner:
            return "Owner"
        case .participant:
            return "Participant"
        }
    }
}

enum FamilyShareStatus: String, Equatable {
    case notConfigured
    case readyToShare
    case sharing
    case needsICloud
    case localOnly
    case error

    var displayName: String {
        switch self {
        case .notConfigured:
            return "Not configured"
        case .readyToShare:
            return "Ready"
        case .sharing:
            return "Sharing"
        case .needsICloud:
            return "Needs iCloud"
        case .localOnly:
            return "Local only"
        case .error:
            return "Needs attention"
        }
    }
}

struct FamilyShareState: Equatable {
    var mode: FamilyShareMode
    var syncMode: FamilySyncMode
    var role: FamilyShareRole
    var status: FamilyShareStatus
    var ownerDescription: String
    var participantDescription: String
    var sharingIsImplemented: Bool
    var participantCount: Int
    var lastSyncAt: Date?
    var pendingUploadCount: Int
    var pendingDownloadCount: Int
    var canResumeShare: Bool
    var canCreateShare: Bool
    var canManageShare: Bool
    var canSyncNow: Bool
    var canLeaveShare: Bool
    var lastAcceptanceMessage: String?
    var lastErrorMessage: String?
}
