import CloudKit
import CryptoKit
import Foundation
import SwiftData
import UIKit

@MainActor
final class CloudKitSharingService {
    static let shared = CloudKitSharingService()

    private static var installedContainer: ModelContainer?
    private static var pendingAcceptedShareMetadata: CKShare.Metadata?
    private static var isApplyingRemoteDataset = false

    private let containerIdentifier: String
    private let defaults: UserDefaults

    private enum Constant {
        static let zoneName = "LittleWindowsFamily"
        static let rootRecordName = "FamilyRoot"
        static let rootRecordType = "FamilyRoot"
        static let datasetAssetKey = "datasetAsset"
        static let datasetChecksumKey = "datasetChecksum"
        static let datasetUpdatedAtKey = "datasetUpdatedAt"
        static let schemaVersionKey = "schemaVersion"
        static let familyIDKey = "familyID"
        static let shareTitle = "Little Windows Family Sync"
        static let syncSchemaVersion = 1
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
        static let lastError = "familySync.lastError"
        static let pendingUpload = "familySync.pendingUpload"
    }

    init(
        containerIdentifier: String = PersistenceService.iCloudContainerIdentifier,
        defaults: UserDefaults = .standard
    ) {
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
    }

    static func install(container: ModelContainer) {
        installedContainer = container
    }

    static func handleAcceptedShare(metadata: CKShare.Metadata) {
        guard let container = installedContainer else {
            pendingAcceptedShareMetadata = metadata
            return
        }
        Task { @MainActor in
            do {
                try await shared.acceptFamilyShare(
                    metadata: metadata,
                    context: container.mainContext
                )
            } catch {
                shared.record(error: error)
            }
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
        shared.defaults.set(true, forKey: DefaultsKey.pendingUpload)
        Task { @MainActor in
            do {
                try await shared.syncNow(
                    context: container.mainContext,
                    reason: .localMutation
                )
            } catch {
                shared.record(error: error)
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
        let availability = privateSyncAvailable ?? syncMode.requiresICloudAccount
        let lastError = defaults.string(forKey: DefaultsKey.lastError)
        let status: FamilyShareStatus
        if syncMode == .localOnly {
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
            participantCount: defaults.integer(forKey: "familySync.participantCount"),
            lastSyncAt: defaults.object(forKey: DefaultsKey.lastSyncAt) as? Date,
            pendingUploadCount: defaults.bool(forKey: DefaultsKey.pendingUpload) ? 1 : 0,
            pendingDownloadCount: 0,
            canCreateShare: syncMode != .localOnly && availability && !hasShare,
            canManageShare: syncMode == .sharedFamilySync && role == .owner && hasShare,
            canSyncNow: syncMode == .sharedFamilySync && hasShare,
            canLeaveShare: syncMode == .sharedFamilySync,
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

    func createFamilyShare(context: ModelContext) async throws -> CKShare {
        try await requireICloudAccount()
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let familyID = UUID().uuidString
        let zoneID = CKRecordZone.ID(
            zoneName: Constant.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let zone = CKRecordZone(zoneID: zoneID)
        try await save(zone: zone, in: database)

        let rootID = CKRecord.ID(recordName: Constant.rootRecordName, zoneID: zoneID)
        let root = CKRecord(recordType: Constant.rootRecordType, recordID: rootID)
        root[Constant.familyIDKey] = familyID as CKRecordValue
        try writeDatasetAsset(from: context, into: root)

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
        if let iconData = Self.shareIconData {
            share[CKShare.SystemFieldKey.thumbnailImageData] = iconData as CKRecordValue
        }
        share.publicPermission = .none

        _ = try await database.modifyRecords(
            saving: [root, share],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        store(
            mode: .sharedFamilySync,
            role: .owner,
            familyID: familyID,
            rootRecordID: rootID,
            shareRecordID: share.recordID
        )
        defaults.removeObject(forKey: DefaultsKey.lastError)
        markSynced(uploaded: true, downloaded: false)
        return share
    }

    func existingShare() async throws -> CKShare? {
        guard storedRole == .owner,
              let shareID = storedShareRecordID else { return nil }
        let result = try await CKContainer(identifier: containerIdentifier)
            .privateCloudDatabase
            .records(for: [shareID])
        guard case .success(let record)? = result[shareID] else { return nil }
        return record as? CKShare
    }

    func acceptFamilyShare(metadata: CKShare.Metadata, context: ModelContext) async throws {
        try await requireICloudAccount()
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let accepted = try await container.accept([metadata])
        guard case .success(let share)? = accepted[metadata] else {
            throw FamilySharingError.shareAcceptanceFailed
        }
        guard let rootID = metadata.hierarchicalRootRecordID else {
            throw FamilySharingError.missingShare
        }
        let root = try await fetchRootRecord(id: rootID, role: .participant)

        store(
            mode: .sharedFamilySync,
            role: .participant,
            familyID: root[Constant.familyIDKey] as? String,
            rootRecordID: rootID,
            shareRecordID: share.recordID
        )
        try importDataset(from: root, context: context)
        defaults.removeObject(forKey: DefaultsKey.lastError)
        markSynced(uploaded: false, downloaded: true)
    }

    func syncNow(context: ModelContext, reason: FamilySyncReason) async throws {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return
        }
        try await requireICloudAccount()
        guard let rootID = storedRootRecordID else {
            throw FamilySharingError.missingShare
        }

        var root = try await fetchRootRecord(id: rootID, role: storedRole)
        let localData = try DataExportImportService.exportData(context: context)
        let localChecksum = checksum(for: localData)
        let remoteChecksum = root[Constant.datasetChecksumKey] as? String
        let remoteUpdatedAt = root[Constant.datasetUpdatedAtKey] as? Date
        let lastUploadedAt = defaults.object(forKey: DefaultsKey.lastUploadedAt) as? Date
        let hasLocalPending = defaults.bool(forKey: DefaultsKey.pendingUpload)
            || localChecksum != defaults.string(forKey: DefaultsKey.lastDatasetChecksum)

        if let remoteUpdatedAt,
           let lastUploadedAt,
           remoteUpdatedAt > lastUploadedAt,
           remoteChecksum != localChecksum {
            try importDataset(from: root, context: context)
            markSynced(uploaded: false, downloaded: true)
            if !hasLocalPending || reason == .launch {
                return
            }
            root = try await fetchRootRecord(id: rootID, role: storedRole)
        }

        guard hasLocalPending || reason == .manual else {
            markSynced(uploaded: false, downloaded: false)
            return
        }

        try writeDatasetAsset(from: context, into: root)
        let database = database(for: storedRole)
        _ = try await database.modifyRecords(
            saving: [root],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        defaults.set(localChecksum, forKey: DefaultsKey.lastDatasetChecksum)
        defaults.removeObject(forKey: DefaultsKey.lastError)
        markSynced(uploaded: true, downloaded: false)
    }

    func leaveFamilyShare(context: ModelContext, deleteLocalData: Bool) async throws {
        if deleteLocalData {
            try DataExportImportService.deleteAll(context: context)
        }
        clearStoredShare()
        PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
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
    }

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
    }

    private func clearStoredShare() {
        for key in [
            DefaultsKey.familyID,
            DefaultsKey.role,
            DefaultsKey.zoneName,
            DefaultsKey.ownerName,
            DefaultsKey.rootRecordName,
            DefaultsKey.shareRecordName,
            DefaultsKey.lastSyncAt,
            DefaultsKey.lastUploadedAt,
            DefaultsKey.lastDownloadedAt,
            DefaultsKey.lastDatasetChecksum,
            DefaultsKey.lastError,
            DefaultsKey.pendingUpload
        ] {
            defaults.removeObject(forKey: key)
        }
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

    private func fetchRootRecord(
        id: CKRecord.ID,
        role: FamilyShareRole
    ) async throws -> CKRecord {
        let database = database(for: role)
        let results = try await database.records(for: [id])
        guard case .success(let record)? = results[id] else {
            throw FamilySharingError.missingShare
        }
        return record
    }

    private func writeDatasetAsset(from context: ModelContext, into root: CKRecord) throws {
        let data = try DataExportImportService.exportData(context: context)
        let checksum = checksum(for: data)
        let fileURL = try writeTemporaryDataset(data)
        root[Constant.datasetAssetKey] = CKAsset(fileURL: fileURL)
        root[Constant.datasetChecksumKey] = checksum as CKRecordValue
        root[Constant.datasetUpdatedAtKey] = Date() as CKRecordValue
        root[Constant.schemaVersionKey] = Constant.syncSchemaVersion as CKRecordValue
    }

    private func importDataset(from root: CKRecord, context: ModelContext) throws {
        guard let asset = root[Constant.datasetAssetKey] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw FamilySharingError.missingDataset
        }
        let data = try Data(contentsOf: fileURL)
        Self.isApplyingRemoteDataset = true
        defer { Self.isApplyingRemoteDataset = false }
        try DataExportImportService.importData(
            data,
            context: context,
            recordLocalSave: false
        )
        if let checksum = root[Constant.datasetChecksumKey] as? String {
            defaults.set(checksum, forKey: DefaultsKey.lastDatasetChecksum)
        }
    }

    private func writeTemporaryDataset(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LittleWindowsFamilySync", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func save(zone: CKRecordZone, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordZonesOperation(
                recordZonesToSave: [zone],
                recordZoneIDsToDelete: nil
            )
            operation.modifyRecordZonesResultBlock = { result in
                continuation.resume(with: result.map { _ in () })
            }
            database.add(operation)
        }
    }

    private func checksum(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func markSynced(uploaded: Bool, downloaded: Bool) {
        let now = Date()
        defaults.set(now, forKey: DefaultsKey.lastSyncAt)
        defaults.set(false, forKey: DefaultsKey.pendingUpload)
        if uploaded {
            defaults.set(now, forKey: DefaultsKey.lastUploadedAt)
        }
        if downloaded {
            defaults.set(now, forKey: DefaultsKey.lastDownloadedAt)
        }
    }

    private func record(error: Error) {
        defaults.set(error.localizedDescription, forKey: DefaultsKey.lastError)
    }
}

enum FamilySyncReason {
    case launch
    case localMutation
    case manual
}

enum FamilySharingError: LocalizedError {
    case missingModelContainer
    case iCloudUnavailable
    case missingShare
    case missingDataset
    case shareAcceptanceFailed

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
        }
    }
}

@MainActor
enum CloudKitFamilySyncConflictResolver {
    static func resolveDuplicateActiveTimers(
        in context: ModelContext,
        now: Date = Date()
    ) {
        let events = (try? context.fetch(FetchDescriptor<BabyEvent>())) ?? []
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
