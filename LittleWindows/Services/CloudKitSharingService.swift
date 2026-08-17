import CloudKit
import CryptoKit
import Foundation
import SwiftData
import UIKit

enum FamilyShareCreationProgress: Equatable, Sendable {
    case checkingICloud
    case preparingData
    case creatingShare
    case uploadingData(completed: Int, total: Int)
    case finishing

    var statusText: String {
        switch self {
        case .checkingICloud:
            return "Checking iCloud..."
        case .preparingData:
            return "Preparing family data..."
        case .creatingShare:
            return "Creating the secure iCloud share..."
        case .uploadingData(let completed, let total):
            guard total > 0 else { return "Uploading family data..." }
            return "Uploading family data (\(completed) of \(total))..."
        case .finishing:
            return "Finishing Family Sync setup..."
        }
    }
}

enum FamilyShareAcceptancePhase: String, Equatable {
    case preparing
    case accepting
    case downloading
    case completed
    case failed

    var isInProgress: Bool {
        switch self {
        case .preparing, .accepting, .downloading:
            return true
        case .completed, .failed:
            return false
        }
    }

    var isTerminal: Bool {
        !isInProgress
    }
}

@MainActor
final class CloudKitSharingService {
    static let shared = CloudKitSharingService()
    nonisolated static let foregroundTimerPollIntervalSeconds: TimeInterval = 1
    nonisolated static let foregroundTimerFailureRetrySeconds: TimeInterval = 30
    nonisolated static let shareMembershipRefreshDebounceSeconds: TimeInterval = 0.35
    nonisolated static let familyEntityUploadBatchRecordLimit = 25
    nonisolated static let familyEntityUploadBatchByteLimit = 8 * 1_024 * 1_024
    nonisolated static let familySnapshotAssetByteLimit = 40 * 1_024 * 1_024
    nonisolated static let localMutationAutomaticRetryLimit = 5
    nonisolated static let cloudKitRequestTimeoutSeconds: TimeInterval = 30
    nonisolated static let cloudKitResourceTimeoutSeconds: TimeInterval = 180
    nonisolated static let acceptanceStatusDidChangeNotification = Notification.Name(
        "CloudKitSharingService.acceptanceStatusDidChange"
    )
    nonisolated static let acceptanceStatusMessageKey = "familySync.acceptanceStatusMessage"
    nonisolated static let acceptancePhaseKey = "familySync.acceptancePhase"
    nonisolated static let inactiveReasonKey = "familySync.inactiveReason"
    nonisolated static let inactiveEventIDKey = "familySync.inactiveEventID"
    nonisolated static let shareStateDidChangeNotification = Notification.Name(
        "CloudKitSharingService.shareStateDidChange"
    )
    nonisolated static let inactiveReasonUserInfoKey = "familySync.inactiveReason"

    private static var installedContainer: ModelContainer?
    private static var pendingAcceptedShareMetadata: CKShare.Metadata?
    private static var acceptanceTask: Task<Void, Never>?
    private static var isApplyingRemoteDataset = false

    private var localMutationSyncTask: Task<Void, Never>?
    private var localMutationSyncRequested = false
    private var isSynchronizing = false
    private var isRefreshingShareMembership = false
    private var shareMembershipRefreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var shareMembershipRefreshTask: Task<Void, Never>?
    private var datasetExporter: FamilySyncDatasetExporter?
    private var verifiedPushSubscriptionID: String?

    private let containerIdentifier: String
    private let defaults: UserDefaults
    private let statusDefaults: UserDefaults

    private enum Constant {
        static let zoneName = "LittleWindowsFamily"
        static let rootRecordName = "FamilyRoot"
        static let rootRecordType = "FamilyRoot"
        static let subscriptionIDPrefix = "LittleWindowsFamilySync"
        static let datasetAssetKey = "datasetAsset"
        static let datasetChecksumKey = "datasetChecksum"
        static let datasetUpdatedAtKey = "datasetUpdatedAt"
        static let schemaVersionKey = "schemaVersion"
        static let familyIDKey = "familyID"
        static let shareTitle = "Little Windows Family Sync"
        static let syncSchemaVersion = 5
        static let entityRecordType = "FamilyEntity"
        static let entityCollectionKey = "collection"
        static let entityIDKey = "entityID"
        static let entityPayloadAssetKey = "payloadAsset"
        static let entityChecksumKey = "payloadChecksum"
        static let entityDeletedKey = "isDeleted"
        static let entityUpdatedAtKey = "entityUpdatedAt"
    }

    private enum DefaultsKey {
        static let familyID = "familySync.familyID"
        static let role = "familySync.role"
        static let zoneName = "familySync.zoneName"
        static let ownerName = "familySync.ownerName"
        static let rootRecordName = "familySync.rootRecordName"
        static let shareRecordName = "familySync.shareRecordName"
        static let lastSyncAt = "familySync.lastSyncAt"
        static let lastUploadedAt = "familySync.lastUploadedAt"
        static let lastDownloadedAt = "familySync.lastDownloadedAt"
        static let lastDatasetChecksum = "familySync.lastDatasetChecksum"
        static let lastNotifiedDatasetChecksum = "familySync.lastNotifiedDatasetChecksum"
        static let pushSubscriptionID = "familySync.pushSubscriptionID"
        static let acceptanceStatusMessage = CloudKitSharingService.acceptanceStatusMessageKey
        static let acceptancePhase = CloudKitSharingService.acceptancePhaseKey
        static let acceptanceStatusAt = "familySync.acceptanceStatusAt"
        static let lastError = "familySync.lastError"
        static let pendingUpload = "familySync.pendingUpload"
        static let inactiveReason = CloudKitSharingService.inactiveReasonKey
        static let inactiveEventID = CloudKitSharingService.inactiveEventIDKey
        static let participantCount = "familySync.participantCount"
    }

    init(
        containerIdentifier: String = PersistenceService.iCloudContainerIdentifier,
        defaults: UserDefaults = .standard
    ) {
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
        statusDefaults = PersistenceService.operationalDefaults(for: defaults)
        if statusDefaults !== defaults {
            for key in Self.operationalDefaultsKeys
            where statusDefaults.object(forKey: key) == nil {
                if let existingValue = defaults.object(forKey: key) {
                    statusDefaults.set(existingValue, forKey: key)
                }
            }
        }
    }

    private nonisolated static let operationalDefaultsKeys = [
        DefaultsKey.lastSyncAt,
        DefaultsKey.lastUploadedAt,
        DefaultsKey.lastDownloadedAt,
        DefaultsKey.lastDatasetChecksum,
        DefaultsKey.lastNotifiedDatasetChecksum,
        DefaultsKey.pushSubscriptionID,
        DefaultsKey.lastError,
        DefaultsKey.pendingUpload,
        DefaultsKey.participantCount
    ]

    static func install(container: ModelContainer) {
        installedContainer = container
        shared.datasetExporter = FamilySyncDatasetExporter(modelContainer: container)
        if pendingAcceptedShareMetadata == nil,
           acceptanceTask == nil,
           shared.storedAcceptancePhase?.isInProgress == true {
            shared.recordAcceptance(
                "Family share setup was interrupted. Open the invitation again to retry.",
                phase: .failed
            )
        }
    }

    static func handleAcceptedShare(metadata: CKShare.Metadata) {
        guard acceptanceTask == nil else { return }
        shared.recordAcceptance(
            "Family share invite received. Preparing secure setup...",
            phase: .preparing
        )
        guard let container = installedContainer else {
            pendingAcceptedShareMetadata = metadata
            return
        }
        acceptanceTask = Task { @MainActor in
            shared.recordAcceptance(
                "Accepting the Family Sync invitation...",
                phase: .accepting
            )
            do {
                try await shared.acceptFamilyShare(
                    metadata: metadata,
                    context: container.mainContext
                )
                shared.recordAcceptance(
                    "Family share accepted. Shared family data is ready on this device.",
                    phase: .completed
                )
            } catch {
                shared.record(error: error)
                shared.recordAcceptance(
                    "Family share invite failed: \(error.localizedDescription)",
                    phase: .failed
                )
            }
            acceptanceTask = nil
        }
    }

    static func processPendingAcceptedShareIfNeeded() {
        guard let metadata = pendingAcceptedShareMetadata,
              installedContainer != nil else { return }
        pendingAcceptedShareMetadata = nil
        handleAcceptedShare(metadata: metadata)
    }

    static func noteLocalDataChanged() {
        guard !isApplyingRemoteDataset else { return }
        guard PersistenceService.familySyncMode() == .sharedFamilySync else { return }
        guard let container = installedContainer else { return }
        shared.statusDefaults.set(true, forKey: DefaultsKey.pendingUpload)
        shared.enqueueLocalMutationSync(context: container.mainContext)
    }

    static func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let container = installedContainer else {
            completion(.noData)
            return
        }
        guard shared.isFamilySyncPush(userInfo: userInfo) else {
            completion(.noData)
            return
        }
        Task { @MainActor in
            do {
                let changed = try await shared.syncNow(
                    context: container.mainContext,
                    reason: .remoteNotification
                )
                if shared.storedRole == .owner {
                    await shared.refreshShareMembership()
                    shared.postShareStateDidChange()
                }
                completion(changed ? .newData : .noData)
            } catch {
                shared.record(error: error)
                completion(.failed)
            }
        }
    }

    func currentState(privateSyncAvailable: Bool) -> FamilyShareState {
        currentFamilySyncStatus(privateSyncAvailable: privateSyncAvailable)
    }

    func currentFamilySyncStatus(privateSyncAvailable: Bool? = nil) -> FamilyShareState {
        let syncMode = PersistenceService.familySyncMode(defaults: defaults)
        let role = storedRole
        let hasShare = storedRootRecordID != nil
        let canUseStoredShare = hasShare && role != .none
        let availability = privateSyncAvailable ?? syncMode.requiresICloudAccount
        let lastError = statusDefaults.string(forKey: DefaultsKey.lastError)
        let inactiveReason = defaults.string(forKey: DefaultsKey.inactiveReason)
            .flatMap(FamilyShareInactiveReason.init(rawValue:))
        let status: FamilyShareStatus
        if inactiveReason != nil {
            status = .accessEnded
        } else if syncMode == .localOnly {
            status = .localOnly
        } else if !availability {
            status = .needsICloud
        } else if lastError != nil {
            status = .error
        } else if syncMode == .sharedFamilySync && hasShare {
            status = .sharing
        } else {
            status = .readyToShare
        }

        return FamilyShareState(
            mode: syncMode == .sharedFamilySync ? .sharedFamilySync
                : (syncMode == .privateICloudSync ? .privateICloudSync : .localOnly),
            syncMode: syncMode,
            role: role,
            status: status,
            ownerDescription: ownerDescription(role: role),
            participantDescription: participantDescription(role: role),
            sharingIsImplemented: true,
            participantCount: statusDefaults.integer(forKey: DefaultsKey.participantCount),
            lastSyncAt: statusDefaults.object(forKey: DefaultsKey.lastSyncAt) as? Date,
            pendingUploadCount: statusDefaults.bool(forKey: DefaultsKey.pendingUpload) ? 1 : 0,
            pendingDownloadCount: 0,
            canResumeShare: inactiveReason == nil && syncMode == .privateICloudSync
                && availability && canUseStoredShare,
            canCreateShare: inactiveReason == nil && syncMode != .localOnly
                && availability && !hasShare,
            canManageShare: inactiveReason == nil && availability && role == .owner && hasShare,
            canSyncNow: inactiveReason == nil && syncMode == .sharedFamilySync && hasShare,
            canLeaveShare: inactiveReason == nil && syncMode == .sharedFamilySync,
            inactiveReason: inactiveReason,
            lastAcceptanceMessage: defaults.string(forKey: DefaultsKey.acceptanceStatusMessage),
            lastErrorMessage: lastError
        )
    }

    func startFamilyShare() async -> Result<CKShare, Error> {
        guard let container = Self.installedContainer else {
            return .failure(FamilySharingError.missingModelContainer)
        }
        do {
            return .success(try await createFamilyShare(context: container.mainContext))
        } catch {
            return .failure(error)
        }
    }

    func createFamilyShare(
        context: ModelContext,
        progress: @escaping (FamilyShareCreationProgress) -> Void = { _ in }
    ) async throws -> CKShare {
        progress(.checkingICloud)
        try await requireICloudAccount()
        progress(.preparingData)
        let payload = try await makeDatasetPayload(fallbackContext: context)
        defer { payload.removeTemporaryFile() }

        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let familyID = UUID().uuidString
        let zoneID = CKRecordZone.ID(
            zoneName: Self.familySyncZoneName(familyID: familyID),
            ownerName: CKCurrentUserDefaultName
        )
        let zone = CKRecordZone(zoneID: zoneID)
        var zoneWasCreated = false
        do {
            progress(.creatingShare)
            try await save(zone: zone, in: database)
            zoneWasCreated = true

            let rootID = CKRecord.ID(recordName: Constant.rootRecordName, zoneID: zoneID)
            let root = CKRecord(recordType: Constant.rootRecordType, recordID: rootID)
            root[Constant.familyIDKey] = familyID as CKRecordValue
            let usesSnapshotAsset = payload.data.count <= Self.familySnapshotAssetByteLimit
            applyDatasetPayload(
                payload,
                to: root,
                includeSnapshotAsset: usesSnapshotAsset
            )

            let share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
            if let iconData = Self.shareIconData {
                share[CKShare.SystemFieldKey.thumbnailImageData] = iconData as CKRecordValue
            }
            share.publicPermission = .none

            if usesSnapshotAsset {
                progress(.uploadingData(completed: 0, total: 1))
            }
            try await modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true,
                in: database
            )
            if usesSnapshotAsset {
                progress(.uploadingData(completed: 1, total: 1))
            } else {
                try await uploadEntityChanges(
                    from: nil,
                    to: payload.data,
                    rootRecordID: rootID,
                    database: database
                ) { completed, total in
                    progress(.uploadingData(completed: completed, total: total))
                }
            }

            progress(.finishing)
            try await saveBaselineData(payload.data)
            store(
                mode: .sharedFamilySync,
                role: .owner,
                familyID: familyID,
                rootRecordID: rootID,
                shareRecordID: share.recordID
            )
            updateShareMembership(from: share)
            statusDefaults.removeObject(forKey: DefaultsKey.lastError)
            markSynced(uploaded: true, downloaded: false)
            schedulePushSubscriptionSetup(rootRecordID: rootID, role: .owner)
            return share
        } catch {
            if zoneWasCreated {
                scheduleZoneCleanup(zoneID: zoneID, database: database)
            }
            throw error
        }
    }

    func resumeFamilyShare(context: ModelContext) async throws {
        try await requireICloudAccount()
        guard let rootID = storedRootRecordID,
              storedRole != .none else {
            throw FamilySharingError.missingShare
        }
        PersistenceService.setFamilySyncMode(.sharedFamilySync, defaults: defaults)
        do {
            try await ensureFamilySyncPushSubscription(rootRecordID: rootID, role: storedRole)
            _ = try await syncNow(context: context, reason: .manual)
            statusDefaults.removeObject(forKey: DefaultsKey.lastError)
        } catch {
            PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
            throw error
        }
    }

    func existingShare() async throws -> CKShare? {
        let role = storedRole
        guard role != .none,
              let shareID = storedShareRecordID,
              let rootID = storedRootRecordID else {
            throw FamilySharingError.missingShare
        }
        let result: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            result = try await database(for: role).records(for: [shareID])
        } catch {
            throw await shareAccessErrorIfNeeded(error, rootRecordID: rootID, role: role)
        }
        guard let shareResult = result[shareID] else {
            throw FamilySharingError.missingShare
        }
        switch shareResult {
        case .success(let record):
            guard let share = record as? CKShare else {
                throw FamilySharingError.missingShare
            }
            updateShareMembership(from: share)
            return share
        case .failure(let error):
            throw await shareAccessErrorIfNeeded(error, rootRecordID: rootID, role: role)
        }
    }

    func refreshShareMembership() async {
        guard storedRole != .none else { return }
        if isRefreshingShareMembership {
            await withCheckedContinuation { continuation in
                shareMembershipRefreshWaiters.append(continuation)
            }
            return
        }
        isRefreshingShareMembership = true
        defer {
            isRefreshingShareMembership = false
            let waiters = shareMembershipRefreshWaiters
            shareMembershipRefreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        do {
            _ = try await existingShare()
            statusDefaults.removeObject(forKey: DefaultsKey.lastError)
        } catch {
            record(error: error)
        }
    }

    func acceptFamilyShare(metadata: CKShare.Metadata, context: ModelContext) async throws {
        try await requireICloudAccount()
        _ = try DataExportImportService.createAutomaticRecoveryBackup(
            context: context,
            reason: "before-family-share"
        )
        let localPayload = try await makeDatasetPayload(fallbackContext: context)
        defer { localPayload.removeTemporaryFile() }
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let accepted = try await container.accept([metadata])
        guard case .success(let share)? = accepted[metadata] else {
            throw FamilySharingError.shareAcceptanceFailed
        }
        guard let rootID = metadata.hierarchicalRootRecordID else {
            throw FamilySharingError.missingShare
        }
        recordAcceptance(
            "Invitation accepted. Downloading shared family data...",
            phase: .downloading
        )
        let root = try await fetchRootRecord(id: rootID, role: .participant)
        try requireCurrentSyncSchema(root)

        store(
            mode: .sharedFamilySync,
            role: .participant,
            familyID: root[Constant.familyIDKey] as? String,
            rootRecordID: rootID,
            shareRecordID: share.recordID
        )
        updateShareMembership(from: share)
        try await ensureFamilySyncPushSubscription(rootRecordID: rootID, role: .participant)
        let remoteData = try await datasetData(from: root, template: localPayload.data)
        let mergedData = try await mergeFamilySyncData(
            base: nil,
            local: localPayload.data,
            remote: remoteData,
            localChangedAt: PersistenceService.lastLocalSaveAt(defaults: defaults),
            remoteChangedAt: root[Constant.datasetUpdatedAtKey] as? Date
        )
        let mergedPayload = try await makeDatasetPayload(from: mergedData)
        defer { mergedPayload.removeTemporaryFile() }
        if mergedPayload.checksum != localPayload.checksum {
            try await importDataset(mergedData, from: root, context: context)
        }
        if mergedPayload.checksum != (root[Constant.datasetChecksumKey] as? String) {
            try await uploadEntityChanges(
                from: remoteData,
                to: mergedData,
                rootRecordID: rootID,
                database: database(for: .participant)
            )
            applyDatasetPayload(mergedPayload, to: root)
            _ = try await database(for: .participant).modifyRecords(
                saving: [root],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
        }
        try await saveBaselineData(mergedData)
        statusDefaults.removeObject(forKey: DefaultsKey.lastError)
        if !CaregiverIdentityService.hasExplicitCurrentCaregiverName(defaults: defaults) {
            defaults.set(true, forKey: CaregiverIdentityService.needsLogNamePromptKey)
        }
        markSynced(uploaded: false, downloaded: true)
        await SystemIntegrationReconciler.reconcile(context: context)
    }

    @discardableResult
    func syncNow(context: ModelContext, reason: FamilySyncReason) async throws -> Bool {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return false
        }
        guard !isSynchronizing else { return false }
        isSynchronizing = true
        defer { isSynchronizing = false }
        if reason.requiresExplicitAccountCheck {
            try await requireICloudAccount()
        }
        guard let rootID = storedRootRecordID else {
            throw FamilySharingError.missingShare
        }
        if reason.ensuresPushSubscription {
            try await ensureFamilySyncPushSubscription(rootRecordID: rootID, role: storedRole)
            _ = try? await existingShare()
        }

        let pendingUpload = statusDefaults.bool(forKey: DefaultsKey.pendingUpload)
        if reason.usesLightweightRemoteCheck, !pendingUpload {
            let metadataRoot = try await fetchRootRecord(
                id: rootID,
                role: storedRole,
                desiredKeys: [
                    Constant.datasetChecksumKey,
                    Constant.datasetUpdatedAtKey,
                    Constant.schemaVersionKey
                ]
            )
            try requireCurrentSyncSchema(metadataRoot)
            let remoteChecksum = metadataRoot[Constant.datasetChecksumKey] as? String
            guard Self.foregroundPollNeedsDownload(
                remoteChecksum: remoteChecksum,
                lastKnownChecksum: statusDefaults.string(forKey: DefaultsKey.lastDatasetChecksum),
                pendingUpload: pendingUpload
            ) else {
                // A frequent foreground or push check with no remote changes must
                // be completely silent. Updating sync timestamps here used to
                // invalidate every `@AppStorage`-backed SwiftUI view on each
                // poll, producing the repeating Today/timer scroll freeze.
                if reason != .foregroundTimerPoll {
                    markSynced(uploaded: false, downloaded: false)
                }
                statusDefaults.removeObject(forKey: DefaultsKey.lastError)
                return false
            }
            // The full record is fetched below only when its checksum changed.
        }

        let root = try await fetchRootRecord(id: rootID, role: storedRole)
        try requireCurrentSyncSchema(root)
        let remoteChecksum = root[Constant.datasetChecksumKey] as? String
        let remoteUpdatedAt = root[Constant.datasetUpdatedAtKey] as? Date
        let localPayload = try await makeDatasetPayload(fallbackContext: context)
        defer { localPayload.removeTemporaryFile() }
        if remoteChecksum == localPayload.checksum {
            try await saveBaselineData(localPayload.data)
            statusDefaults.removeObject(forKey: DefaultsKey.lastError)
            markSynced(uploaded: false, downloaded: false)
            return false
        }

        if Self.localMutationCanUploadWithoutDownload(
            reason: reason,
            remoteChecksum: remoteChecksum,
            lastKnownChecksum: statusDefaults.string(forKey: DefaultsKey.lastDatasetChecksum)
        ) {
            let baselineData = await loadBaselineData()
            let baselinePayload: FamilySyncDatasetPayload?
            if let baselineData {
                baselinePayload = try await makeDatasetPayload(from: baselineData)
            } else {
                baselinePayload = nil
            }
            defer { baselinePayload?.removeTemporaryFile() }
            let remoteData: Data
            if let baselineData,
               baselinePayload?.checksum == remoteChecksum {
                remoteData = baselineData
            } else {
                remoteData = try await datasetData(from: root, template: localPayload.data)
            }
            try await uploadEntityChanges(
                from: remoteData,
                to: localPayload.data,
                rootRecordID: rootID,
                database: database(for: storedRole)
            )
            applyDatasetPayload(localPayload, to: root)
            _ = try await database(for: storedRole).modifyRecords(
                saving: [root],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try await saveBaselineData(localPayload.data)
            statusDefaults.set(localPayload.checksum, forKey: DefaultsKey.lastDatasetChecksum)
            statusDefaults.removeObject(forKey: DefaultsKey.lastError)
            markSynced(uploaded: true, downloaded: false)
            return true
        }

        let baselineData = await loadBaselineData()
        let baselineChecksum: FamilySyncDatasetPayload?
        if let baselineData {
            baselineChecksum = try await makeDatasetPayload(from: baselineData)
        } else {
            baselineChecksum = nil
        }
        let remoteData: Data
        if let baselineData,
           baselineChecksum?.checksum == remoteChecksum {
            remoteData = baselineData
            baselineChecksum?.removeTemporaryFile()
        } else {
            baselineChecksum?.removeTemporaryFile()
            remoteData = try await datasetData(from: root, template: localPayload.data)
        }
        let notification = reason == .remoteNotification
            ? FamilySyncActivityDiff.notification(
                localData: localPayload.data,
                remoteData: remoteData
            )
            : nil
        let mergedData = try await mergeFamilySyncData(
            base: baselineData,
            local: localPayload.data,
            remote: remoteData,
            localChangedAt: PersistenceService.lastLocalSaveAt(defaults: defaults),
            remoteChangedAt: remoteUpdatedAt
        )
        let mergedPayload = try await makeDatasetPayload(from: mergedData)
        defer { mergedPayload.removeTemporaryFile() }
        let downloaded = mergedPayload.checksum != localPayload.checksum
        let needsUpload = mergedPayload.checksum != remoteChecksum

        if downloaded {
            try await importDataset(mergedData, from: root, context: context)
        }
        if needsUpload {
            try await uploadEntityChanges(
                from: remoteData,
                to: mergedData,
                rootRecordID: rootID,
                database: database(for: storedRole)
            )
            applyDatasetPayload(mergedPayload, to: root)
            _ = try await database(for: storedRole).modifyRecords(
                saving: [root],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
        }
        try await saveBaselineData(mergedData)
        statusDefaults.set(mergedPayload.checksum, forKey: DefaultsKey.lastDatasetChecksum)
        statusDefaults.removeObject(forKey: DefaultsKey.lastError)
        markSynced(uploaded: needsUpload, downloaded: downloaded)
        if downloaded {
            await SystemIntegrationReconciler.reconcile(context: context)
        }
        await notifyAboutRemoteChangesIfNeeded(
            notification,
            remoteChecksum: remoteChecksum
        )
        return downloaded || needsUpload
    }

    private func enqueueLocalMutationSync(context: ModelContext) {
        localMutationSyncRequested = true
        guard localMutationSyncTask == nil else { return }

        localMutationSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var busyRetryAttempt = 0
            while self.localMutationSyncRequested, !Task.isCancelled {
                self.localMutationSyncRequested = false
                self.statusDefaults.set(true, forKey: DefaultsKey.pendingUpload)
                do {
                    let changed = try await self.syncNow(
                        context: context,
                        reason: .localMutation
                    )
                    if !changed,
                       self.statusDefaults.bool(forKey: DefaultsKey.pendingUpload) {
                        self.localMutationSyncRequested = true
                        let delay = Self.localMutationBusyRetryDelaySeconds(
                            attempt: busyRetryAttempt
                        )
                        busyRetryAttempt += 1
                        try? await Task.sleep(for: .seconds(delay))
                    } else {
                        busyRetryAttempt = 0
                    }
                } catch {
                    self.record(error: error)
                    guard PersistenceService.familySyncMode(defaults: self.defaults) == .sharedFamilySync,
                          self.statusDefaults.bool(forKey: DefaultsKey.pendingUpload),
                          busyRetryAttempt < Self.localMutationAutomaticRetryLimit else {
                        break
                    }
                    self.localMutationSyncRequested = true
                    let delay = Self.localMutationBusyRetryDelaySeconds(
                        attempt: busyRetryAttempt
                    )
                    busyRetryAttempt += 1
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
            self.localMutationSyncTask = nil
            if self.localMutationSyncRequested {
                self.enqueueLocalMutationSync(context: context)
            }
        }
    }

    func pollForForegroundTimerChanges(context: ModelContext) async throws -> Bool {
        try await syncNow(context: context, reason: .foregroundTimerPoll)
    }

    nonisolated static func foregroundPollNeedsDownload(
        remoteChecksum: String?,
        lastKnownChecksum: String?,
        pendingUpload: Bool
    ) -> Bool {
        guard !pendingUpload, let remoteChecksum else { return false }
        return remoteChecksum != lastKnownChecksum
    }

    nonisolated static func localMutationCanUploadWithoutDownload(
        reason: FamilySyncReason,
        remoteChecksum: String?,
        lastKnownChecksum: String?
    ) -> Bool {
        reason == .localMutation
            && remoteChecksum != nil
            && remoteChecksum == lastKnownChecksum
    }

    nonisolated static func localMutationBusyRetryDelaySeconds(attempt: Int) -> TimeInterval {
        let boundedAttempt = min(max(0, attempt), 4)
        return min(30, 2 * pow(2, Double(boundedAttempt)))
    }

    nonisolated static func foregroundPollFailureRetryDelaySeconds(attempt: Int) -> TimeInterval {
        localMutationBusyRetryDelaySeconds(attempt: attempt)
    }

    private func refreshTimerSurfaces(context: ModelContext) async {
        let profiles = (try? context.fetch(FetchDescriptor<CareProfile>())) ?? []
        let profile = ProfileService.shared.ensureSelection(in: profiles)
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var eventDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate<CareEvent> { event in
                event.startDate >= recentCutoff || event.endDate == nil
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        let events = ((try? context.fetch(eventDescriptor)) ?? [])
            .filter { $0.matchesProfile(profile?.id) }
        let records = ((try? context.fetch(FetchDescriptor<SleepPredictionRecord>())) ?? [])
            .filter { $0.matchesProfile(profile?.id) }
        let prediction = records
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }?
            .prediction

        let selectedProfileID = profile?.id
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var solidsStateDescriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == selectedProfileID }
        )
        solidsStateDescriptor.fetchLimit = 1
        WidgetSnapshotService.refresh(
            profile: profile,
            events: events,
            prediction: prediction,
            solidsState: (try? context.fetch(solidsStateDescriptor))?.first
        )
        await LiveActivityManager.shared.synchronize(profile: profile, events: events)
    }

    func leaveFamilyShare(context: ModelContext, deleteLocalData: Bool) async throws {
        let role = storedRole
        let rootID = storedRootRecordID
        let shareID = storedShareRecordID

        if let rootID {
            try? await deleteFamilySyncPushSubscription(rootRecordID: rootID, role: role)
        }
        if role == .participant {
            guard let shareID else { throw FamilySharingError.missingShare }
            do {
                _ = try await database(for: role).deleteRecord(withID: shareID)
            } catch {
                guard Self.isTerminalShareAccessError(error) else { throw error }
            }
        }
        if deleteLocalData {
            try deleteLocalDataWithoutEnqueuingFamilySync(context: context)
            statusDefaults.removeObject(forKey: DefaultsKey.lastUploadedAt)
            await SystemIntegrationReconciler.reconcile(context: context)
        }
        if role == .owner {
            suspendActiveShareOnThisDevice()
        } else {
            resetActiveShareState()
        }
    }

    func stopFamilyShareForEveryone() async throws {
        try await requireICloudAccount()
        guard storedRole == .owner,
              let shareID = storedShareRecordID else {
            throw FamilySharingError.missingShare
        }
        do {
            _ = try await CKContainer(identifier: containerIdentifier)
                .privateCloudDatabase
                .deleteRecord(withID: shareID)
        } catch {
            guard Self.isTerminalShareAccessError(error) else { throw error }
        }
        if let rootID = storedRootRecordID {
            try? await deleteFamilySyncPushSubscription(rootRecordID: rootID, role: .owner)
        }
        resetActiveShareState()
    }

    func handleOwnerStoppedSharing() async {
        guard storedRole == .owner else { return }
        if let rootID = storedRootRecordID {
            try? await deleteFamilySyncPushSubscription(rootRecordID: rootID, role: .owner)
        }
        resetActiveShareState()
    }

    func handleShareSheetDidSave() {
        statusDefaults.removeObject(forKey: DefaultsKey.lastError)
        shareMembershipRefreshTask?.cancel()
        shareMembershipRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    for: .seconds(Self.shareMembershipRefreshDebounceSeconds)
                )
            } catch {
                return
            }
            await self.refreshShareMembership()
            guard !Task.isCancelled else { return }
            self.postShareStateDidChange()
        }
    }

    func handleShareSheetSaveFailed(_ error: Error) {
        record(error: error)
        postShareStateDidChange()
    }

    func resolveInactiveShare(context: ModelContext, deleteLocalData: Bool) throws {
        if deleteLocalData {
            try deleteLocalDataWithoutEnqueuingFamilySync(context: context)
            SystemIntegrationReconciler.requestReconciliation()
        }
        defaults.removeObject(forKey: DefaultsKey.inactiveReason)
        defaults.removeObject(forKey: DefaultsKey.inactiveEventID)
        postShareStateDidChange()
    }

    private func ownerDescription(role: FamilyShareRole) -> String {
        switch role {
        case .owner:
            if let name = primaryCaregiverName {
                return "\(name) owns the shared family data."
            }
            return "You own the shared family data."
        case .participant:
            return "Another iCloud user owns this shared family data."
        case .none:
            return "Not sharing a family record zone."
        }
    }

    private func participantDescription(role: FamilyShareRole) -> String {
        switch role {
        case .owner:
            return "Manage caregivers from the iCloud share sheet."
        case .participant:
            return "Accepted family share."
        case .none:
            return "No accepted family share."
        }
    }

    var shareTitle: String {
        guard let name = primaryCaregiverName else {
            return Constant.shareTitle
        }
        return "\(name)'s Little Windows"
    }

    static var shareIconData: Data? {
        cachedShareIconData
    }

    private static let cachedShareIconData: Data? = {
        let size = CGSize(width: 180, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor.systemTeal.setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: 40).fill()

            let symbolConfig = UIImage.SymbolConfiguration(
                pointSize: 86,
                weight: .semibold
            )
            let symbol = UIImage(
                systemName: "figure.and.child.holdinghands",
                withConfiguration: symbolConfig
            ) ?? UIImage(systemName: "person.2.fill", withConfiguration: symbolConfig)
            UIColor.white.setFill()
            let symbolSize = symbol?.size ?? .zero
            let symbolRect = CGRect(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol?.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: symbolRect)

            UIColor.white.withAlphaComponent(0.16).setStroke()
            context.cgContext.setLineWidth(6)
            UIBezierPath(
                roundedRect: bounds.insetBy(dx: 3, dy: 3),
                cornerRadius: 37
            ).stroke()
        }
        return image.pngData()
    }()

    private var primaryCaregiverName: String? {
        let raw = defaults.string(forKey: "caregiverOne")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty, raw != "Caregiver 1" else { return nil }
        return raw
    }

    private var storedRole: FamilyShareRole {
        defaults.string(forKey: DefaultsKey.role)
            .flatMap(FamilyShareRole.init(rawValue:)) ?? .none
    }

    private var storedRootRecordID: CKRecord.ID? {
        storedRecordID(recordKey: DefaultsKey.rootRecordName)
    }

    private var storedShareRecordID: CKRecord.ID? {
        storedRecordID(recordKey: DefaultsKey.shareRecordName)
    }

    private func storedRecordID(recordKey: String) -> CKRecord.ID? {
        guard let recordName = defaults.string(forKey: recordKey),
              let zoneName = defaults.string(forKey: DefaultsKey.zoneName) else {
            return nil
        }
        let ownerName = defaults.string(forKey: DefaultsKey.ownerName) ?? CKCurrentUserDefaultName
        return CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
    }

    private func store(
        mode: FamilySyncMode,
        role: FamilyShareRole,
        familyID: String?,
        rootRecordID: CKRecord.ID,
        shareRecordID: CKRecord.ID
    ) {
        PersistenceService.setFamilySyncMode(mode, defaults: defaults)
        defaults.set(role.rawValue, forKey: DefaultsKey.role)
        defaults.set(familyID, forKey: DefaultsKey.familyID)
        defaults.set(rootRecordID.zoneID.zoneName, forKey: DefaultsKey.zoneName)
        defaults.set(rootRecordID.zoneID.ownerName, forKey: DefaultsKey.ownerName)
        defaults.set(rootRecordID.recordName, forKey: DefaultsKey.rootRecordName)
        defaults.set(shareRecordID.recordName, forKey: DefaultsKey.shareRecordName)
        defaults.removeObject(forKey: DefaultsKey.inactiveReason)
        defaults.removeObject(forKey: DefaultsKey.inactiveEventID)
    }

    private func clearStoredShare() {
        verifiedPushSubscriptionID = nil
        for key in [
            DefaultsKey.familyID,
            DefaultsKey.role,
            DefaultsKey.zoneName,
            DefaultsKey.ownerName,
            DefaultsKey.rootRecordName,
            DefaultsKey.shareRecordName,
            DefaultsKey.acceptanceStatusMessage,
            DefaultsKey.acceptancePhase,
            DefaultsKey.acceptanceStatusAt,
            DefaultsKey.inactiveReason,
            DefaultsKey.inactiveEventID,
            CaregiverIdentityService.familySyncCaregiverNamesKey
        ] {
            defaults.removeObject(forKey: key)
        }
        for key in Self.operationalDefaultsKeys {
            statusDefaults.removeObject(forKey: key)
            if statusDefaults !== defaults {
                // Remove legacy operational values from the standard domain
                // only when the share itself is explicitly cleared.
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func resetActiveShareState() {
        localMutationSyncTask?.cancel()
        localMutationSyncTask = nil
        localMutationSyncRequested = false
        clearStoredShare()
        removeBaselineData()
        PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
        postShareStateDidChange()
    }

    private func suspendActiveShareOnThisDevice() {
        localMutationSyncTask?.cancel()
        localMutationSyncTask = nil
        localMutationSyncRequested = false
        verifiedPushSubscriptionID = nil
        statusDefaults.removeObject(forKey: DefaultsKey.pushSubscriptionID)
        statusDefaults.removeObject(forKey: DefaultsKey.pendingUpload)
        statusDefaults.removeObject(forKey: DefaultsKey.lastError)
        PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
        postShareStateDidChange()
    }

    private func deleteLocalDataWithoutEnqueuingFamilySync(
        context: ModelContext
    ) throws {
        Self.isApplyingRemoteDataset = true
        defer { Self.isApplyingRemoteDataset = false }
        try DataExportImportService.deleteAll(context: context)
    }

    private func deactivateStoredShare(
        reason: FamilyShareInactiveReason,
        notifyUser: Bool
    ) async {
        localMutationSyncTask?.cancel()
        localMutationSyncTask = nil
        localMutationSyncRequested = false
        clearStoredShare()
        removeBaselineData()
        PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
        defaults.set(reason.rawValue, forKey: DefaultsKey.inactiveReason)
        defaults.set(UUID().uuidString, forKey: DefaultsKey.inactiveEventID)
        postShareStateDidChange(reason: reason)
        if notifyUser {
            await NotificationManager.shared.showFamilySyncAccessEndedNotification(reason: reason)
        }
    }

    private func postShareStateDidChange(reason: FamilyShareInactiveReason? = nil) {
        var userInfo: [String: String]?
        if let reason {
            userInfo = [Self.inactiveReasonUserInfoKey: reason.rawValue]
        }
        NotificationCenter.default.post(
            name: Self.shareStateDidChangeNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    private func requireICloudAccount() async throws {
        let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
        guard status == .available else {
            throw FamilySharingError.iCloudUnavailable
        }
    }

    private func database(for role: FamilyShareRole) -> CKDatabase {
        let container = CKContainer(identifier: containerIdentifier)
        return role == .participant ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private func isFamilySyncPush(userInfo: [AnyHashable: Any]) -> Bool {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return false
        }
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let subscriptionID = notification.subscriptionID else {
            return false
        }
        if let storedSubscriptionID = statusDefaults.string(forKey: DefaultsKey.pushSubscriptionID) {
            return subscriptionID == storedSubscriptionID
        }
        return subscriptionID.hasPrefix(Constant.subscriptionIDPrefix)
    }

    private func ensureFamilySyncPushSubscription(
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) async throws {
        let subscriptionID = Self.subscriptionID(for: rootRecordID, role: role)
        if verifiedPushSubscriptionID == subscriptionID {
            return
        }
        let database = database(for: role)
        do {
            let subscription = try await database.subscription(for: subscriptionID)
            if Self.familySyncPushSubscription(
                subscription,
                matches: rootRecordID,
                role: role
            ) {
                statusDefaults.set(subscriptionID, forKey: DefaultsKey.pushSubscriptionID)
                verifiedPushSubscriptionID = subscriptionID
                return
            }
            _ = try await database.deleteSubscription(withID: subscriptionID)
        } catch {
            guard Self.isMissingPushSubscriptionError(error) else { throw error }
        }
        let subscription = Self.familySyncPushSubscription(
            rootRecordID: rootRecordID,
            role: role,
            subscriptionID: subscriptionID
        )
        _ = try await database.save(subscription)
        statusDefaults.set(subscriptionID, forKey: DefaultsKey.pushSubscriptionID)
        verifiedPushSubscriptionID = subscriptionID
    }

    private func schedulePushSubscriptionSetup(
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.storedRootRecordID == rootRecordID,
                  self.storedRole == role else { return }
            do {
                try await self.ensureFamilySyncPushSubscription(
                    rootRecordID: rootRecordID,
                    role: role
                )
            } catch {
                // Foreground polling remains available, and launch/manual sync retries setup.
            }
        }
    }

    nonisolated static func familySyncPushSubscription(
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole,
        subscriptionID: String
    ) -> CKSubscription {
        let subscription: CKSubscription
        if role == .participant {
            subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        } else {
            subscription = CKRecordZoneSubscription(
                zoneID: rootRecordID.zoneID,
                subscriptionID: subscriptionID
            )
        }
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        return subscription
    }

    nonisolated static func familySyncPushSubscription(
        _ subscription: CKSubscription,
        matches rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) -> Bool {
        guard subscription.notificationInfo?.shouldSendContentAvailable == true else {
            return false
        }
        switch role {
        case .participant:
            return subscription is CKDatabaseSubscription
        case .owner:
            guard let zoneSubscription = subscription as? CKRecordZoneSubscription else {
                return false
            }
            return zoneSubscription.zoneID == rootRecordID.zoneID
        case .none:
            return false
        }
    }

    nonisolated static func isMissingPushSubscriptionError(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if cloudError.code == .unknownItem {
            return true
        }
        guard cloudError.code == .partialFailure,
              let errors = cloudError.partialErrorsByItemID?.values,
              !errors.isEmpty else {
            return false
        }
        return errors.allSatisfy { error in
            (error as? CKError)?.code == .unknownItem
        }
    }

    private func deleteFamilySyncPushSubscription(
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) async throws {
        let subscriptionID = statusDefaults.string(forKey: DefaultsKey.pushSubscriptionID)
            ?? Self.subscriptionID(for: rootRecordID, role: role)
        _ = try await database(for: role).deleteSubscription(withID: subscriptionID)
        if verifiedPushSubscriptionID == subscriptionID {
            verifiedPushSubscriptionID = nil
        }
    }

    private static func subscriptionID(
        for rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) -> String {
        let zoneName = rootRecordID.zoneID.zoneName
            .replacingOccurrences(of: ":", with: "-")
        let ownerName = rootRecordID.zoneID.ownerName
            .replacingOccurrences(of: ":", with: "-")
        return "\(Constant.subscriptionIDPrefix).\(role.rawValue).\(ownerName).\(zoneName)"
    }

    private func fetchRootRecord(
        id: CKRecord.ID,
        role: FamilyShareRole,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> CKRecord {
        let database = database(for: role)
        let results: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            results = try await database.records(for: [id], desiredKeys: desiredKeys)
        } catch {
            throw await shareAccessErrorIfNeeded(error, rootRecordID: id, role: role)
        }
        guard let result = results[id] else {
            throw FamilySharingError.missingShare
        }
        switch result {
        case .success(let record):
            if role == .owner,
               PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync,
               storedRootRecordID == id,
               storedShareRecordID != nil,
               record.share == nil {
                await deactivateStoredShare(
                    reason: .shareNoLongerAvailable,
                    notifyUser: false
                )
                throw FamilySharingError.shareAccessEnded
            }
            return record
        case .failure(let error):
            throw await shareAccessErrorIfNeeded(error, rootRecordID: id, role: role)
        }
    }

    private func shareAccessErrorIfNeeded(
        _ error: Error,
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) async -> Error {
        guard Self.isTerminalShareAccessError(error),
              PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync,
              storedRootRecordID == rootRecordID,
              storedRole == role else {
            return error
        }
        let reason: FamilyShareInactiveReason = role == .participant
            ? .accessEnded
            : .shareNoLongerAvailable
        await deactivateStoredShare(reason: reason, notifyUser: role == .participant)
        return FamilySharingError.shareAccessEnded
    }

    nonisolated static func isTerminalShareAccessError(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if isTerminalShareAccessError(code: cloudError.code) {
            return true
        }
        switch cloudError.code {
        case .partialFailure:
            guard let errors = cloudError.partialErrorsByItemID?.values,
                  !errors.isEmpty else { return false }
            return errors.allSatisfy(isTerminalShareAccessError)
        default:
            return false
        }
    }

    nonisolated static func isTerminalShareAccessError(code: CKError.Code) -> Bool {
        switch code {
        case .unknownItem, .zoneNotFound, .permissionFailure, .userDeletedZone:
            return true
        default:
            return false
        }
    }

    private func makeDatasetPayload(
        fallbackContext context: ModelContext
    ) async throws -> FamilySyncDatasetPayload {
        if let datasetExporter {
            return try await Task.detached(priority: .utility) {
                try await datasetExporter.export()
            }.value
        }
        return try FamilySyncDatasetPayload(
            data: DataExportImportService.exportData(
                context: context,
                includeCaregiverIdentity: false,
                profileScope: .familyShared
            )
        )
    }

    private func makeDatasetPayload(from data: Data) async throws -> FamilySyncDatasetPayload {
        try await Task.detached(priority: .utility) {
            try FamilySyncDatasetPayload(data: data)
        }.value
    }

    private func mergeFamilySyncData(
        base: Data?,
        local: Data,
        remote: Data,
        localChangedAt: Date?,
        remoteChangedAt: Date?
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try DataExportImportService.mergeFamilySyncData(
                base: base,
                local: local,
                remote: remote,
                localChangedAt: localChangedAt,
                remoteChangedAt: remoteChangedAt
            )
        }.value
    }

    private func applyDatasetPayload(
        _ payload: FamilySyncDatasetPayload,
        to root: CKRecord,
        includeSnapshotAsset: Bool = false
    ) {
        if includeSnapshotAsset {
            root[Constant.datasetAssetKey] = CKAsset(fileURL: payload.fileURL)
        }
        root[Constant.datasetChecksumKey] = payload.checksum as CKRecordValue
        root[Constant.datasetUpdatedAtKey] = Date() as CKRecordValue
        root[Constant.schemaVersionKey] = Constant.syncSchemaVersion as CKRecordValue
    }

    private func requireCurrentSyncSchema(_ root: CKRecord) throws {
        let version = (root[Constant.schemaVersionKey] as? NSNumber)?.intValue
            ?? root[Constant.schemaVersionKey] as? Int
        guard version == Constant.syncSchemaVersion else {
            throw FamilySharingError.unsupportedSchema
        }
    }

    private func importDataset(
        _ data: Data,
        from root: CKRecord,
        context: ModelContext
    ) async throws {
        Self.isApplyingRemoteDataset = true
        defer { Self.isApplyingRemoteDataset = false }
        try DataExportImportService.importData(
            data,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false,
            preservePrivateProfiles: true
        )
        if let checksum = root[Constant.datasetChecksumKey] as? String {
            statusDefaults.set(checksum, forKey: DefaultsKey.lastDatasetChecksum)
        }
    }

    private func datasetData(from root: CKRecord, template: Data) async throws -> Data {
        let snapshotData: Data?
        if let asset = root[Constant.datasetAssetKey] as? CKAsset,
           let fileURL = asset.fileURL {
            snapshotData = try Data(contentsOf: fileURL)
        } else {
            snapshotData = nil
        }
        let records = try await queryAllEntityRecords(
            database: database(for: storedRole),
            zoneID: root.recordID.zoneID
        )
        let snapshotPayloads = try snapshotData.map {
            try DataExportImportService.familySyncEntityPayloads(from: $0)
        } ?? [:]
        var updatedPayloads: [String: Data] = [:]
        var deletedKeys: Set<String> = []
        for record in records {
            guard let collection = record[Constant.entityCollectionKey] as? String,
                  let entityID = record[Constant.entityIDKey] as? String else {
                continue
            }
            let key = DataExportImportService.familySyncEntityKey(
                collection: collection,
                id: entityID
            )
            if (record[Constant.entityDeletedKey] as? NSNumber)?.boolValue == true {
                deletedKeys.insert(key)
                continue
            }
            guard let asset = record[Constant.entityPayloadAssetKey] as? CKAsset,
                  let fileURL = asset.fileURL else {
                continue
            }
            updatedPayloads[key] = try Data(contentsOf: fileURL)
        }
        let payloads = Self.applyingFamilyEntityChanges(
            base: snapshotPayloads,
            updates: updatedPayloads,
            deletedKeys: deletedKeys
        )
        return try DataExportImportService.familySyncData(
            template: snapshotData ?? template,
            entityPayloads: payloads
        )
    }

    nonisolated static func applyingFamilyEntityChanges(
        base: [String: Data],
        updates: [String: Data],
        deletedKeys: Set<String>
    ) -> [String: Data] {
        var result = base
        for key in deletedKeys {
            result.removeValue(forKey: key)
        }
        for (key, data) in updates where !deletedKeys.contains(key) {
            result[key] = data
        }
        return result
    }

    private func uploadEntityChanges(
        from remoteData: Data?,
        to mergedData: Data,
        rootRecordID: CKRecord.ID,
        database: CKDatabase,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let changes = try await Task.detached(priority: .utility) {
            let remotePayloads = try remoteData.map {
                try DataExportImportService.familySyncEntityPayloads(from: $0)
            } ?? [:]
            let mergedPayloads = try DataExportImportService.familySyncEntityPayloads(
                from: mergedData
            )
            return Set(remotePayloads.keys)
                .union(mergedPayloads.keys)
                .filter { remotePayloads[$0] != mergedPayloads[$0] }
                .sorted()
                .map {
                    FamilySyncEntityChange(key: $0, data: mergedPayloads[$0])
                }
        }.value
        guard !changes.isEmpty else {
            progress?(0, 0)
            return
        }

        let batchRanges = Self.familyEntityUploadBatchRanges(
            payloadSizes: changes.map { $0.data?.count ?? 0 }
        )
        let now = Date()
        var completed = 0
        progress?(completed, changes.count)
        for range in batchRanges {
            var temporaryPayloads: [FamilySyncEntityPayload] = []
            defer { temporaryPayloads.forEach { $0.removeTemporaryFile() } }
            var records: [CKRecord] = []
            records.reserveCapacity(range.count)
            for change in changes[range] {
                guard let parts = DataExportImportService.familySyncEntityKeyParts(change.key) else {
                    continue
                }
                let recordID = CKRecord.ID(
                    recordName: "\(parts.collection).\(parts.id)",
                    zoneID: rootRecordID.zoneID
                )
                let record = CKRecord(
                    recordType: Constant.entityRecordType,
                    recordID: recordID
                )
                record.parent = Self.familyEntityParentReference(rootRecordID: rootRecordID)
                record[Constant.entityCollectionKey] = parts.collection as CKRecordValue
                record[Constant.entityIDKey] = parts.id as CKRecordValue
                record[Constant.entityUpdatedAtKey] = now as CKRecordValue
                if let data = change.data {
                    let payload = try FamilySyncEntityPayload(data: data)
                    temporaryPayloads.append(payload)
                    record[Constant.entityPayloadAssetKey] = CKAsset(fileURL: payload.fileURL)
                    record[Constant.entityChecksumKey] = payload.checksum as CKRecordValue
                    record[Constant.entityDeletedKey] = NSNumber(value: false)
                } else {
                    record[Constant.entityPayloadAssetKey] = nil
                    record[Constant.entityChecksumKey] = "deleted" as CKRecordValue
                    record[Constant.entityDeletedKey] = NSNumber(value: true)
                }
                records.append(record)
            }
            try await modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false,
                in: database
            )
            completed += range.count
            progress?(completed, changes.count)
        }
    }

    nonisolated static func familyEntityUploadBatchRanges(
        payloadSizes: [Int],
        recordLimit: Int = familyEntityUploadBatchRecordLimit,
        byteLimit: Int = familyEntityUploadBatchByteLimit
    ) -> [Range<Int>] {
        guard !payloadSizes.isEmpty, recordLimit > 0, byteLimit > 0 else { return [] }
        var ranges: [Range<Int>] = []
        var start = 0
        var count = 0
        var bytes = 0
        for (index, payloadSize) in payloadSizes.enumerated() {
            let size = max(payloadSize, 0)
            if count > 0,
               count >= recordLimit || bytes + size > byteLimit {
                ranges.append(start..<index)
                start = index
                count = 0
                bytes = 0
            }
            count += 1
            bytes += size
        }
        ranges.append(start..<payloadSizes.count)
        return ranges
    }

    nonisolated static func familyEntityParentReference(
        rootRecordID: CKRecord.ID
    ) -> CKRecord.Reference {
        CKRecord.Reference(recordID: rootRecordID, action: .none)
    }

    nonisolated static func familySyncZoneName(familyID: String) -> String {
        "\(Constant.zoneName)-\(familyID)"
    }

    private func queryAllEntityRecords(
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await queryEntityRecordPage(
                database: database,
                zoneID: zoneID,
                cursor: cursor
            )
            records.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        return records
    }

    private func queryEntityRecordPage(
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let collector = FamilySyncQueryPageCollector()
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(
                    query: CKQuery(
                        recordType: Constant.entityRecordType,
                        predicate: NSPredicate(value: true)
                    )
                )
                operation.zoneID = zoneID
            }
            operation.desiredKeys = [
                Constant.entityCollectionKey,
                Constant.entityIDKey,
                Constant.entityPayloadAssetKey,
                Constant.entityChecksumKey,
                Constant.entityDeletedKey,
                Constant.entityUpdatedAtKey
            ]
            operation.resultsLimit = 200
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    collector.append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (collector.records, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func save(zone: CKRecordZone, in database: CKDatabase) async throws {
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )
        configure(operation)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.modifyRecordZonesResultBlock = { result in
                    continuation.resume(with: result.map { _ in () })
                }
                database.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    private func delete(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: nil,
            recordZoneIDsToDelete: [zoneID]
        )
        configure(operation)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.modifyRecordZonesResultBlock = { result in
                    continuation.resume(with: result.map { _ in () })
                }
                database.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    private func scheduleZoneCleanup(zoneID: CKRecordZone.ID, database: CKDatabase) {
        Task { @MainActor [weak self] in
            try? await self?.delete(zoneID: zoneID, in: database)
        }
    }

    private func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool,
        in database: CKDatabase
    ) async throws {
        guard !records.isEmpty || !recordIDs.isEmpty else { return }
        let operation = CKModifyRecordsOperation(
            recordsToSave: records,
            recordIDsToDelete: recordIDs
        )
        operation.savePolicy = savePolicy
        operation.isAtomic = atomically
        configure(operation)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.modifyRecordsResultBlock = { result in
                    continuation.resume(with: result)
                }
                database.add(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    private func configure(_ operation: CKOperation) {
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = Self.cloudKitRequestTimeoutSeconds
        configuration.timeoutIntervalForResource = Self.cloudKitResourceTimeoutSeconds
        operation.configuration = configuration
        operation.qualityOfService = .userInitiated
    }

    private func markSynced(uploaded: Bool, downloaded: Bool) {
        let now = Date()
        statusDefaults.set(now, forKey: DefaultsKey.lastSyncAt)
        if statusDefaults.bool(forKey: DefaultsKey.pendingUpload) {
            statusDefaults.set(false, forKey: DefaultsKey.pendingUpload)
        }
        if uploaded {
            statusDefaults.set(now, forKey: DefaultsKey.lastUploadedAt)
        }
        if downloaded {
            statusDefaults.set(now, forKey: DefaultsKey.lastDownloadedAt)
        }
    }

    private var baselineFileURL: URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("LittleWindows", isDirectory: true)
            .appendingPathComponent("FamilySync", isDirectory: true)
            .appendingPathComponent("last-synced-dataset.json")
    }

    private func loadBaselineData() async -> Data? {
        let url = baselineFileURL
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
    }

    private func saveBaselineData(_ data: Data) async throws {
        let url = baselineFileURL
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }.value
    }

    private func removeBaselineData() {
        try? FileManager.default.removeItem(at: baselineFileURL)
    }

    private func updateShareMembership(from share: CKShare) {
        let hadPreviousValue = statusDefaults.object(forKey: DefaultsKey.participantCount) != nil
        let previousCount = statusDefaults.integer(forKey: DefaultsKey.participantCount)
        let count = share.participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }.count
        statusDefaults.set(count, forKey: DefaultsKey.participantCount)
        let currentUserRecordID = share.currentUserParticipant?.userIdentity.userRecordID
        let formatter = PersonNameComponentsFormatter()
        let caregiverNames = share.participants.compactMap { participant -> String? in
            guard participant.role == .owner || participant.acceptanceStatus == .accepted else {
                return nil
            }
            if let currentUserRecordID,
               participant.userIdentity.userRecordID == currentUserRecordID {
                return nil
            }
            guard let components = participant.userIdentity.nameComponents else { return nil }
            let name = formatter.string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        CaregiverIdentityService.storeFamilySyncCaregiverNames(
            caregiverNames,
            defaults: defaults
        )
        guard hadPreviousValue, count != previousCount else { return }
        let joined = count > previousCount
        Task { @MainActor in
            await NotificationManager.shared.showFamilySyncActivityNotification(
                FamilySyncActivityNotification(
                    title: joined ? "Caregiver joined Family Sync" : "Caregiver left Family Sync",
                    body: joined
                        ? "A caregiver can now access the shared family data."
                        : "A caregiver no longer has access to the shared family data.",
                    deepLinkPath: "settings/family-sync",
                    category: .general
                )
            )
        }
    }

    private func record(error: Error) {
        guard defaults.string(forKey: DefaultsKey.inactiveReason) == nil else { return }
        statusDefaults.set(error.localizedDescription, forKey: DefaultsKey.lastError)
    }

    private var storedAcceptancePhase: FamilyShareAcceptancePhase? {
        defaults.string(forKey: DefaultsKey.acceptancePhase)
            .flatMap(FamilyShareAcceptancePhase.init(rawValue:))
    }

    private func recordAcceptance(
        _ message: String,
        phase: FamilyShareAcceptancePhase
    ) {
        defaults.set(message, forKey: DefaultsKey.acceptanceStatusMessage)
        defaults.set(Date(), forKey: DefaultsKey.acceptanceStatusAt)
        defaults.set(phase.rawValue, forKey: DefaultsKey.acceptancePhase)
        NotificationCenter.default.post(
            name: Self.acceptanceStatusDidChangeNotification,
            object: nil
        )
    }

    private func notifyAboutRemoteChangesIfNeeded(
        _ notification: FamilySyncActivityNotification?,
        remoteChecksum: String?
    ) async {
        guard let notification else { return }
        if let remoteChecksum,
           statusDefaults.string(forKey: DefaultsKey.lastNotifiedDatasetChecksum) == remoteChecksum {
            return
        }
        await NotificationManager.shared.showFamilySyncActivityNotification(notification)
        if let remoteChecksum {
            statusDefaults.set(remoteChecksum, forKey: DefaultsKey.lastNotifiedDatasetChecksum)
        }
    }
}

enum FamilySyncReason: Equatable {
    case launch
    case localMutation
    case manual
    case remoteNotification
    case foregroundTimerPoll

    var usesLightweightRemoteCheck: Bool {
        self == .launch || self == .remoteNotification || self == .foregroundTimerPoll
    }

    var requiresExplicitAccountCheck: Bool {
        self == .manual
    }

    var ensuresPushSubscription: Bool {
        self == .launch || self == .manual
    }
}

private struct FamilySyncEntityChange: Sendable {
    let key: String
    let data: Data?
}

private struct FamilySyncDatasetPayload: Sendable {
    let data: Data
    let checksum: String
    let fileURL: URL

    init(data: Data) throws {
        self.data = data
        let canonicalData = try DataExportImportService.familySyncCanonicalData(from: data)
        checksum = SHA256.hash(data: canonicalData)
            .map { String(format: "%02x", $0) }
            .joined()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LittleWindowsFamilySync", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
    }

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private struct FamilySyncEntityPayload: Sendable {
    let checksum: String
    let fileURL: URL

    init(data: Data) throws {
        checksum = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LittleWindowsFamilySyncEntities", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
    }

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private final class FamilySyncQueryPageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CKRecord] = []

    var records: [CKRecord] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ record: CKRecord) {
        lock.lock()
        values.append(record)
        lock.unlock()
    }
}

@ModelActor
private actor FamilySyncDatasetExporter {
    func export() throws -> FamilySyncDatasetPayload {
        try FamilySyncDatasetPayload(
            data: DataExportImportService.exportData(
                context: modelContext,
                includeCaregiverIdentity: false,
                profileScope: .familyShared
            )
        )
    }
}

enum FamilySharingError: LocalizedError {
    case missingModelContainer
    case iCloudUnavailable
    case missingShare
    case missingDataset
    case shareAcceptanceFailed
    case shareAccessEnded
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .missingModelContainer:
            return "Family Sync is not ready yet. Try again after Little Windows finishes launching."
        case .iCloudUnavailable:
            return "Sign in to iCloud before using Family Sync."
        case .missingShare:
            return "Little Windows could not find the shared family record."
        case .missingDataset:
            return "The shared family record does not contain Little Windows data yet."
        case .shareAcceptanceFailed:
            return "Little Windows could not accept this iCloud share."
        case .shareAccessEnded:
            return "Family Sync access ended. The data already on this device remains available as a private copy."
        case .unsupportedSchema:
            return "This pre-release Family Sync share uses an older data format. Stop the share on the owner's device, then create and invite caregivers to a new share."
        }
    }
}

enum FamilySyncActivityDiff {
    static func notification(
        localData: Data,
        remoteData: Data,
        currentCaregiverName: String = CaregiverIdentityService.currentCaregiverName()
    ) -> FamilySyncActivityNotification? {
        guard let local = try? FamilySyncDatasetSnapshot(data: localData),
              let remote = try? FamilySyncDatasetSnapshot(data: remoteData) else {
            return nil
        }
        return remote.changeCandidates(
            comparedTo: local,
            currentCaregiverName: currentCaregiverName
        )
            .sorted { left, right in
                if left.date != right.date { return left.date > right.date }
                return left.priority > right.priority
            }
            .first?
            .notification
    }
}

private struct FamilySyncDatasetSnapshot {
    struct Envelope: Decodable {
        var profiles: [Profile]
        var events: [Event]
        var milestones: [Milestone]?
        var appointments: [Appointment]?
        var shoppingLists: [ShoppingListDigest]?
        var shoppingListItems: [ShoppingListItemDigest]?
        var homeTodoLists: [HomeTodoListDigest]?
        var homeTodoItems: [HomeTodoItemDigest]?
        var packingTrips: [PackingTripDigest]?
        var packingItems: [PackingItemDigest]?
        var inventoryItems: [InventoryItemDigest]?
        var mealPrepItems: [MealPrepItemDigest]?
        var returnRequests: [ReturnRequestDigest]?
        var returnItems: [ReturnItemDigest]?
        var returnPackages: [ReturnPackageDigest]?
        var foodReminders: [FoodReminderDigest]?
    }

    struct Profile: Decodable {
        var id: UUID
        var name: String
    }

    struct Event: Decodable {
        var id: UUID
        var profileID: UUID?
        var typeRawValue: String
        var title: String?
        var createdAt: Date
        var updatedAt: Date
        var caregiverName: String?
        var sleepKindRawValue: String?
        var feedKindRawValue: String?
        var activityTypeRawValue: String?
    }

    struct Milestone: Decodable {
        var id: UUID
        var profileID: UUID?
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var caregiverName: String?
    }

    struct Appointment: Decodable {
        var id: UUID
        var profileID: UUID?
        var title: String
        var appointmentTypeRawValue: String
        var createdAt: Date
        var updatedAt: Date
        var isCompleted: Bool
        var caregiverName: String?
    }

    struct ShoppingListDigest: Decodable {
        var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var isArchived: Bool
    }

    struct ShoppingListItemDigest: Decodable {
        var id: UUID
        var shoppingListID: UUID
        var name: String
        var isChecked: Bool
        var checkedAt: Date?
        var lastUncheckedAt: Date?
        var addedBy: String?
        var createdAt: Date
        var updatedAt: Date
        var lastPurchasedAt: Date?
    }

    struct HomeTodoListDigest: Decodable {
        var id: UUID
        var name: String
        var notes: String?
        var createdAt: Date
        var updatedAt: Date
        var isArchived: Bool
        var sortOrder: Int?
    }

    struct HomeTodoItemDigest: Decodable {
        var id: UUID
        var todoListID: UUID
        var title: String
        var notes: String?
        var isCompleted: Bool
        var addedBy: String?
        var assignedCaregiverName: String?
        var completedBy: String?
        var completedAt: Date?
        var lastReopenedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var sortOrder: Int?
    }

    struct PackingTripDigest: Decodable {
        var id: UUID
        var title: String
        var destinationName: String?
        var destinationDetail: String?
        var destinationLatitude: Double?
        var destinationLongitude: Double?
        var destinationTimeZoneIdentifier: String?
        var destinationStops: [TripDestinationStop]?
        var timeZoneIdentifier: String?
        var startDate: Date
        var endDate: Date
        var statusRawValue: String
        var createdBy: String?
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var isArchived: Bool
    }

    struct PackingItemDigest: Decodable {
        var id: UUID
        var tripID: UUID
        var title: String
        var priorityRawValue: String
        var stateRawValue: String
        var addedBy: String?
        var assignedCaregiverName: String?
        var caregiverReminderEnabled: Bool?
        var packedBy: String?
        var packedAt: Date?
        var createdAt: Date
        var updatedAt: Date
    }

    struct InventoryItemDigest: Decodable {
        var id: UUID
        var name: String
        var quantity: Double
        var unit: String
        var createdAt: Date
        var updatedAt: Date
        var lastUsedAt: Date?
        var statusRawValue: String
    }

    struct MealPrepItemDigest: Decodable {
        var id: UUID
        var name: String
        var servingsRemaining: Double
        var servingUnitRawValue: String
        var createdAt: Date
        var updatedAt: Date
        var lastUsedAt: Date?
        var isArchived: Bool
    }

    struct ReturnRequestDigest: Decodable {
        var id: UUID
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var isArchived: Bool
    }

    struct ReturnItemDigest: Decodable {
        var id: UUID
        var returnRequestID: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct ReturnPackageDigest: Decodable {
        var id: UUID
        var returnRequestID: UUID
        var name: String
        var carrierRawValue: String
        var droppedOffAt: Date?
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date
    }

    struct FoodReminderDigest: Decodable {
        var id: UUID
        var typeRawValue: String
        var title: String
        var relatedTodoListID: UUID?
        var relatedShoppingListID: UUID?
        var relatedMealPrepItemID: UUID?
        var relatedReturnRequestID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var isEnabled: Bool
    }

    struct ChangeCandidate {
        var date: Date
        var priority: Int
        var notification: FamilySyncActivityNotification
    }

    var profilesByID: [UUID: Profile]
    var eventsByID: [UUID: Event]
    var milestonesByID: [UUID: Milestone]
    var appointmentsByID: [UUID: Appointment]
    var shoppingListsByID: [UUID: ShoppingListDigest]
    var shoppingItemsByID: [UUID: ShoppingListItemDigest]
    var homeTodoListsByID: [UUID: HomeTodoListDigest]
    var homeTodoItemsByID: [UUID: HomeTodoItemDigest]
    var packingTripsByID: [UUID: PackingTripDigest]
    var packingItemsByID: [UUID: PackingItemDigest]
    var inventoryItemsByID: [UUID: InventoryItemDigest]
    var mealPrepItemsByID: [UUID: MealPrepItemDigest]
    var returnRequestsByID: [UUID: ReturnRequestDigest]
    var returnItemsByID: [UUID: ReturnItemDigest]
    var returnPackagesByID: [UUID: ReturnPackageDigest]
    var foodRemindersByID: [UUID: FoodReminderDigest]

    init(data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        profilesByID = Dictionary(uniqueKeysWithValues: envelope.profiles.map { ($0.id, $0) })
        eventsByID = Dictionary(uniqueKeysWithValues: envelope.events.map { ($0.id, $0) })
        milestonesByID = Dictionary(
            uniqueKeysWithValues: (envelope.milestones ?? []).map { ($0.id, $0) }
        )
        appointmentsByID = Dictionary(
            uniqueKeysWithValues: (envelope.appointments ?? []).map { ($0.id, $0) }
        )
        shoppingListsByID = Dictionary(
            uniqueKeysWithValues: (envelope.shoppingLists ?? []).map { ($0.id, $0) }
        )
        shoppingItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.shoppingListItems ?? []).map { ($0.id, $0) }
        )
        homeTodoListsByID = Dictionary(
            uniqueKeysWithValues: (envelope.homeTodoLists ?? []).map { ($0.id, $0) }
        )
        homeTodoItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.homeTodoItems ?? []).map { ($0.id, $0) }
        )
        packingTripsByID = Dictionary(
            uniqueKeysWithValues: (envelope.packingTrips ?? []).map { ($0.id, $0) }
        )
        packingItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.packingItems ?? []).map { ($0.id, $0) }
        )
        inventoryItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.inventoryItems ?? []).map { ($0.id, $0) }
        )
        mealPrepItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.mealPrepItems ?? []).map { ($0.id, $0) }
        )
        returnRequestsByID = Dictionary(
            uniqueKeysWithValues: (envelope.returnRequests ?? []).map { ($0.id, $0) }
        )
        returnItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.returnItems ?? []).map { ($0.id, $0) }
        )
        returnPackagesByID = Dictionary(
            uniqueKeysWithValues: (envelope.returnPackages ?? []).map { ($0.id, $0) }
        )
        foodRemindersByID = Dictionary(
            uniqueKeysWithValues: (envelope.foodReminders ?? []).map { ($0.id, $0) }
        )
    }

    func changeCandidates(
        comparedTo local: FamilySyncDatasetSnapshot,
        currentCaregiverName: String
    ) -> [ChangeCandidate] {
        var candidates = [ChangeCandidate]()
        candidates.append(contentsOf: eventChanges(comparedTo: local))
        candidates.append(contentsOf: milestoneChanges(comparedTo: local))
        candidates.append(contentsOf: appointmentChanges(comparedTo: local))
        candidates.append(contentsOf: shoppingListChanges(comparedTo: local))
        candidates.append(contentsOf: shoppingItemChanges(comparedTo: local))
        candidates.append(contentsOf: homeTodoChanges(comparedTo: local))
        candidates.append(contentsOf: packingTripChanges(
            comparedTo: local,
            currentCaregiverName: currentCaregiverName
        ))
        candidates.append(contentsOf: inventoryChanges(comparedTo: local))
        candidates.append(contentsOf: mealPrepChanges(comparedTo: local))
        candidates.append(contentsOf: returnChanges(comparedTo: local))
        candidates.append(contentsOf: foodReminderChanges(comparedTo: local))
        return candidates
    }

    private func eventChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        eventsByID.values.compactMap { event in
            let previous = local.eventsByID[event.id]
            guard isNewOrUpdated(remoteDate: event.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let actor = actorName(event.caregiverName)
            let action = previous == nil ? "added" : "updated"
            let profileName = event.profileID.flatMap { profilesByID[$0]?.name }
            let title = profileName.map { "\($0) \(eventDisplayName(event).lowercased())" }
                ?? eventDisplayName(event)
            return ChangeCandidate(
                date: event.updatedAt,
                priority: 90,
                notification: FamilySyncActivityNotification(
                    title: "Shared care updated",
                    body: "\(actor) \(action) \(title).",
                    deepLinkPath: event.profileID.map { "profile/\($0.uuidString)/history" } ?? "history"
                )
            )
        }
    }

    private func milestoneChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        milestonesByID.values.compactMap { milestone in
            let previous = local.milestonesByID[milestone.id]
            guard isNewOrUpdated(
                remoteDate: milestone.updatedAt,
                localDate: previous?.updatedAt
            ) else {
                return nil
            }
            let actor = actorName(milestone.caregiverName)
            let action = previous == nil ? "added milestone" : "updated milestone"
            return ChangeCandidate(
                date: milestone.updatedAt,
                priority: 75,
                notification: FamilySyncActivityNotification(
                    title: "Milestone shared",
                    body: "\(actor) \(action): \(milestone.title).",
                    deepLinkPath: milestone.profileID.map { "profile/\($0.uuidString)/milestones" } ?? "milestones"
                )
            )
        }
    }

    private func appointmentChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        appointmentsByID.values.compactMap { appointment in
            let previous = local.appointmentsByID[appointment.id]
            guard isNewOrUpdated(
                remoteDate: appointment.updatedAt,
                localDate: previous?.updatedAt
            ) else {
                return nil
            }
            let actor = actorName(appointment.caregiverName)
            let action: String
            if appointment.isCompleted && previous?.isCompleted != true {
                action = "completed"
            } else {
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: appointment.updatedAt,
                priority: 80,
                notification: FamilySyncActivityNotification(
                    title: "Appointment updated",
                    body: "\(actor) \(action) \(appointmentDisplayName(appointment)).",
                    deepLinkPath: appointment.profileID.map {
                        "profile/\($0.uuidString)/appointment/\(appointment.id.uuidString)"
                    } ?? "appointment/\(appointment.id.uuidString)"
                )
            )
        }
    }

    private func shoppingListChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        shoppingListsByID.values.compactMap { list in
            let previous = local.shoppingListsByID[list.id]
            guard isNewOrUpdated(remoteDate: list.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let action: String
            if list.isArchived && previous?.isArchived != true {
                action = "archived"
            } else {
                action = previous == nil ? "created" : "updated"
            }
            return ChangeCandidate(
                date: list.updatedAt,
                priority: 70,
                notification: FamilySyncActivityNotification(
                    title: "Shopping list updated",
                    body: "A caregiver \(action) \(list.name).",
                    deepLinkPath: "food/shopping/\(list.id.uuidString)"
                )
            )
        }
    }

    private func shoppingItemChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        shoppingItemsByID.values.compactMap { item in
            let previous = local.shoppingItemsByID[item.id]
            guard isNewOrUpdated(remoteDate: item.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let actor = actorName(item.addedBy)
            let listName = shoppingListsByID[item.shoppingListID]?.name ?? "a shopping list"
            let action: String
            if item.isChecked && previous?.isChecked != true {
                action = "checked off"
            } else if !item.isChecked && previous?.isChecked == true {
                action = "reactivated"
            } else {
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: item.updatedAt,
                priority: 100,
                notification: FamilySyncActivityNotification(
                    title: "Shopping list updated",
                    body: "\(actor) \(action) \(item.name) on \(listName).",
                    deepLinkPath: "food/shopping/\(item.shoppingListID.uuidString)"
                )
            )
        }
    }

    private func homeTodoChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        var candidates = homeTodoListsByID.values.compactMap { list -> ChangeCandidate? in
            let previous = local.homeTodoListsByID[list.id]
            guard isNewOrUpdated(remoteDate: list.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            if let previous,
               list.name == previous.name,
               list.notes == previous.notes,
               list.isArchived == previous.isArchived {
                return nil
            }
            let action: String
            if list.isArchived && previous?.isArchived != true {
                action = "removed"
            } else {
                action = previous == nil ? "created" : "updated"
            }
            return ChangeCandidate(
                date: list.updatedAt,
                priority: 68,
                notification: FamilySyncActivityNotification(
                    title: "Home to-do updated",
                    body: "A caregiver \(action) \(list.name).",
                    deepLinkPath: "food/todos/\(list.id.uuidString)",
                    category: .homeTodo
                )
            )
        }

        candidates.append(contentsOf: homeTodoItemsByID.values.compactMap { item in
            let previous = local.homeTodoItemsByID[item.id]
            guard isNewOrUpdated(remoteDate: item.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            if let previous,
               item.title == previous.title,
               item.notes == previous.notes,
               item.isCompleted == previous.isCompleted,
               item.addedBy == previous.addedBy,
               item.assignedCaregiverName == previous.assignedCaregiverName,
               item.completedBy == previous.completedBy,
               item.completedAt == previous.completedAt,
               item.lastReopenedAt == previous.lastReopenedAt {
                return nil
            }
            let listName = homeTodoListsByID[item.todoListID]?.name ?? "a to-do list"
            let actor: String
            let action: String
            if item.isCompleted && previous?.isCompleted != true {
                actor = actorName(item.completedBy ?? item.addedBy)
                action = "completed"
            } else if !item.isCompleted && previous?.isCompleted == true {
                actor = actorName(item.addedBy)
                action = "reopened"
            } else {
                actor = actorName(item.addedBy)
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: item.updatedAt,
                priority: 98,
                notification: FamilySyncActivityNotification(
                    title: "Home to-do updated",
                    body: "\(actor) updated \(listName): \(action) \(item.title).",
                    deepLinkPath: "food/todos/\(item.todoListID.uuidString)",
                    category: .homeTodo
                )
            )
        })

        return candidates
    }

    private func inventoryChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        inventoryItemsByID.values.compactMap { item in
            let previous = local.inventoryItemsByID[item.id]
            guard isNewOrUpdated(remoteDate: item.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let action: String
            if item.statusRawValue == "usedUp" && previous?.statusRawValue != "usedUp" {
                action = "marked used up"
            } else {
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: item.updatedAt,
                priority: 55,
                notification: FamilySyncActivityNotification(
                    title: "Inventory updated",
                    body: "A caregiver \(action) \(item.name).",
                    deepLinkPath: "food/inventory/\(item.id.uuidString)"
                )
            )
        }
    }

    private func packingTripChanges(
        comparedTo local: FamilySyncDatasetSnapshot,
        currentCaregiverName: String
    ) -> [ChangeCandidate] {
        var candidates = packingTripsByID.values.compactMap { trip -> ChangeCandidate? in
            let previous = local.packingTripsByID[trip.id]
            guard isNewOrUpdated(remoteDate: trip.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            if let previous,
               trip.title == previous.title,
               trip.destinationName == previous.destinationName,
               trip.destinationDetail == previous.destinationDetail,
               trip.destinationLatitude == previous.destinationLatitude,
               trip.destinationLongitude == previous.destinationLongitude,
               trip.destinationTimeZoneIdentifier == previous.destinationTimeZoneIdentifier,
               trip.destinationStops == previous.destinationStops,
               trip.timeZoneIdentifier == previous.timeZoneIdentifier,
               trip.startDate == previous.startDate,
               trip.endDate == previous.endDate,
               trip.statusRawValue == previous.statusRawValue,
               trip.isArchived == previous.isArchived {
                return nil
            }
            let actor = actorName(trip.createdBy)
            let action: String
            if trip.isArchived && previous?.isArchived != true {
                action = "archived"
            } else if trip.statusRawValue == PackingTripStatus.completed.rawValue,
                      previous?.statusRawValue != PackingTripStatus.completed.rawValue {
                action = "completed"
            } else {
                action = previous == nil ? "created" : "updated"
            }
            return ChangeCandidate(
                date: trip.updatedAt,
                priority: 72,
                notification: FamilySyncActivityNotification(
                    title: "Trip packing updated",
                    body: "\(actor) \(action) \(trip.title).",
                    deepLinkPath: "food/trips/\(trip.id.uuidString)",
                    category: .trip
                )
            )
        }

        let tripIDs = Set(packingItemsByID.values.map(\.tripID))
        for tripID in tripIDs {
            let remoteItems = packingItemsByID.values.filter { $0.tripID == tripID }
            let changedItems = remoteItems.filter { item in
                let previous = local.packingItemsByID[item.id]
                return isNewOrUpdated(remoteDate: item.updatedAt, localDate: previous?.updatedAt)
                    && (previous == nil
                        || previous?.stateRawValue != item.stateRawValue
                        || previous?.title != item.title
                        || previous?.priorityRawValue != item.priorityRawValue
                        || previous?.assignedCaregiverName != item.assignedCaregiverName
                        || previous?.caregiverReminderEnabled != item.caregiverReminderEnabled)
            }
            guard !changedItems.isEmpty,
                  let latest = changedItems.max(by: { $0.updatedAt < $1.updatedAt }) else {
                continue
            }
            let newlyAssignedToCurrent = changedItems.filter { item in
                CaregiverIdentityService.namesMatch(
                    item.assignedCaregiverName,
                    currentCaregiverName
                ) && !CaregiverIdentityService.namesMatch(
                    local.packingItemsByID[item.id]?.assignedCaregiverName,
                    currentCaregiverName
                )
            }
            if let latestAssignment = newlyAssignedToCurrent.max(by: { $0.updatedAt < $1.updatedAt }) {
                let tripTitle = packingTripsByID[tripID]?.title ?? "a trip"
                let itemText = newlyAssignedToCurrent.count == 1 ? "item" : "items"
                candidates.append(ChangeCandidate(
                    date: latestAssignment.updatedAt,
                    priority: 78,
                    notification: FamilySyncActivityNotification(
                        title: "Packing assigned to you",
                        body: "You were assigned \(newlyAssignedToCurrent.count) \(itemText) for \(tripTitle).",
                        deepLinkPath: "food/trips/\(tripID.uuidString)",
                        category: .trip
                    )
                ))
            }
            let newlyPacked = changedItems.filter {
                $0.stateRawValue == PackingItemState.packed.rawValue
                    && local.packingItemsByID[$0.id]?.stateRawValue != PackingItemState.packed.rawValue
            }
            let added = changedItems.filter { local.packingItemsByID[$0.id] == nil }
            guard !newlyPacked.isEmpty || !added.isEmpty else { continue }
            let trip = packingTripsByID[tripID]
            let tripTitle = trip?.title ?? "a trip"
            let actor = actorName(latest.packedBy ?? latest.addedBy)
            let remaining = remoteItems.filter { $0.stateRawValue == PackingItemState.needed.rawValue }.count
            let body: String
            if !newlyPacked.isEmpty {
                body = "\(actor) packed \(newlyPacked.count) \(newlyPacked.count == 1 ? "item" : "items") for \(tripTitle). \(remaining) remaining."
            } else {
                body = "\(actor) added \(added.count) \(added.count == 1 ? "item" : "items") to \(tripTitle)."
            }
            candidates.append(ChangeCandidate(
                date: latest.updatedAt,
                priority: 73,
                notification: FamilySyncActivityNotification(
                    title: "Trip packing updated",
                    body: body,
                    deepLinkPath: "food/trips/\(tripID.uuidString)",
                    category: .trip
                )
            ))
        }
        return candidates
    }

    private func mealPrepChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        mealPrepItemsByID.values.compactMap { item in
            let previous = local.mealPrepItemsByID[item.id]
            guard isNewOrUpdated(remoteDate: item.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let action: String
            if item.isArchived && previous?.isArchived != true {
                action = "archived"
            } else if item.servingsRemaining < (previous?.servingsRemaining ?? item.servingsRemaining) {
                action = "used"
            } else {
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: item.updatedAt,
                priority: 50,
                notification: FamilySyncActivityNotification(
                    title: "Meal prep updated",
                    body: "A caregiver \(action) \(item.name).",
                    deepLinkPath: "food/meal-prep/\(item.id.uuidString)"
                )
            )
        }
    }

    private func returnChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        var candidates = returnRequestsByID.values.compactMap { request -> ChangeCandidate? in
            let previous = local.returnRequestsByID[request.id]
            guard isNewOrUpdated(remoteDate: request.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let action: String
            if request.isArchived && previous?.isArchived != true {
                action = "removed"
            } else if request.completedAt != nil && previous?.completedAt == nil {
                action = "completed"
            } else {
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: request.updatedAt,
                priority: 48,
                notification: FamilySyncActivityNotification(
                    title: "Return updated",
                    body: "A caregiver \(action) \(returnTitle(for: request.id)).",
                    deepLinkPath: "food/returns/\(request.id.uuidString)"
                )
            )
        }

        candidates.append(contentsOf: returnPackagesByID.values.compactMap { package in
            let previous = local.returnPackagesByID[package.id]
            guard isNewOrUpdated(remoteDate: package.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let requestTitle = returnTitle(for: package.returnRequestID)
            let packageName = package.name.isEmpty ? package.carrierRawValue : package.name
            let action: String
            if package.completedAt != nil && previous?.completedAt == nil {
                action = "completed"
            } else if package.droppedOffAt != nil && previous?.droppedOffAt == nil {
                action = "dropped off"
            } else {
                action = previous == nil ? "added" : "updated"
            }
            return ChangeCandidate(
                date: package.updatedAt,
                priority: 49,
                notification: FamilySyncActivityNotification(
                    title: "Return package updated",
                    body: "A caregiver \(action) \(packageName) for \(requestTitle).",
                    deepLinkPath: "food/returns/\(package.returnRequestID.uuidString)"
                )
            )
        })

        candidates.append(contentsOf: returnItemsByID.values.compactMap { item in
            let previous = local.returnItemsByID[item.id]
            guard isNewOrUpdated(remoteDate: item.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let requestTitle = returnTitle(for: item.returnRequestID, excluding: item.id)
            let action = previous == nil ? "added" : "updated"
            return ChangeCandidate(
                date: item.updatedAt,
                priority: 47,
                notification: FamilySyncActivityNotification(
                    title: "Return item updated",
                    body: "A caregiver \(action) \(item.name) for \(requestTitle).",
                    deepLinkPath: "food/returns/\(item.returnRequestID.uuidString)"
                )
            )
        })

        return candidates
    }

    private func returnTitle(for requestID: UUID, excluding excludedItemID: UUID? = nil) -> String {
        if let item = returnItemsByID.values
            .filter({ $0.returnRequestID == requestID && $0.id != excludedItemID })
            .sorted(by: { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) })
            .first {
            return item.name
        }
        return "a return"
    }

    private func foodReminderChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        foodRemindersByID.values.compactMap { reminder in
            let previous = local.foodRemindersByID[reminder.id]
            guard isNewOrUpdated(remoteDate: reminder.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let action = reminder.isEnabled ? (previous == nil ? "added" : "updated") : "turned off"
            let path: String
            if let todoListID = reminder.relatedTodoListID {
                path = "food/todos/\(todoListID.uuidString)"
            } else if let listID = reminder.relatedShoppingListID {
                path = "food/shopping/\(listID.uuidString)"
            } else if let mealPrepID = reminder.relatedMealPrepItemID {
                path = "food/meal-prep/\(mealPrepID.uuidString)"
            } else if let returnRequestID = reminder.relatedReturnRequestID {
                path = "food/returns/\(returnRequestID.uuidString)"
            } else {
                path = "food"
            }
            return ChangeCandidate(
                date: reminder.updatedAt,
                priority: 45,
                notification: FamilySyncActivityNotification(
                    title: "Food reminder updated",
                    body: "A caregiver \(action) \(reminder.title).",
                    deepLinkPath: path
                )
            )
        }
    }

    private func isNewOrUpdated(remoteDate: Date, localDate: Date?) -> Bool {
        guard let localDate else { return true }
        return remoteDate.timeIntervalSince(localDate) > 0.5
    }

    private func actorName(_ rawValue: String?) -> String {
        guard let name = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name != "Caregiver 1",
              name != "Caregiver 2" else {
            return "A caregiver"
        }
        return name
    }

    private func eventDisplayName(_ event: Event) -> String {
        if let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let type = EventType(rawValue: event.typeRawValue) {
            switch type {
            case .sleep:
                return event.sleepKindRawValue.map { "\($0.capitalized) sleep" }
                    ?? type.displayName
            case .feed:
                return event.feedKindRawValue?.capitalized ?? type.displayName
            case .activity:
                return event.activityTypeRawValue?.capitalized ?? type.displayName
            default:
                return type.displayName
            }
        }
        return "event"
    }

    private func appointmentDisplayName(_ appointment: Appointment) -> String {
        let title = appointment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return "\(appointment.appointmentTypeRawValue) appointment"
        }
        return title
    }
}

@MainActor
enum CloudKitFamilySyncConflictResolver {
    static func resolveDuplicateActiveTimers(
        in context: ModelContext,
        now: Date = Date()
    ) {
        let events = (try? context.fetch(FetchDescriptor<CareEvent>())) ?? []
        let activeTimers = events.filter(\.isTimerDraft)
        let grouped = Dictionary(grouping: activeTimers) { event in
            "\(event.profileID?.uuidString ?? "none"):\(event.typeRawValue)"
        }
        for timers in grouped.values where timers.count > 1 {
            let sorted = timers.sorted { left, right in
                if left.createdAt != right.createdAt {
                    return left.createdAt < right.createdAt
                }
                return left.startDate < right.startDate
            }
            for duplicate in sorted.dropFirst() {
                if duplicate.isTimerRunning {
                    let elapsed = duplicate.timerElapsed(at: now)
                    duplicate.timerAccumulatedSeconds = elapsed
                }
                duplicate.timerState = .stopped
                duplicate.activeTimerSegmentStartDate = nil
                duplicate.updatedAt = max(duplicate.updatedAt, now)
            }
        }
    }
}
