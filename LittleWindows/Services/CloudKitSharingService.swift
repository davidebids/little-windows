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
        static let subscriptionIDPrefix = "LittleWindowsFamilySync"
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
        static let lastNotifiedDatasetChecksum = "familySync.lastNotifiedDatasetChecksum"
        static let pushSubscriptionID = "familySync.pushSubscriptionID"
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
            canResumeShare: syncMode == .privateICloudSync && availability && canUseStoredShare,
            canCreateShare: syncMode != .localOnly && availability && !hasShare,
            canManageShare: availability && role == .owner && hasShare,
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
        try await ensureFamilySyncPushSubscription(rootRecordID: rootID, role: .owner)
        defaults.removeObject(forKey: DefaultsKey.lastError)
        markSynced(uploaded: true, downloaded: false)
        return share
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
            defaults.removeObject(forKey: DefaultsKey.lastError)
        } catch {
            PersistenceService.setFamilySyncMode(.privateICloudSync, defaults: defaults)
            throw error
        }
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
        try await ensureFamilySyncPushSubscription(rootRecordID: rootID, role: .participant)
        try importDataset(from: root, context: context)
        defaults.removeObject(forKey: DefaultsKey.lastError)
        markSynced(uploaded: false, downloaded: true)
    }

    @discardableResult
    func syncNow(context: ModelContext, reason: FamilySyncReason) async throws -> Bool {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return false
        }
        try await requireICloudAccount()
        guard let rootID = storedRootRecordID else {
            throw FamilySharingError.missingShare
        }
        try await ensureFamilySyncPushSubscription(rootRecordID: rootID, role: storedRole)

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
            let remoteData = try datasetData(from: root)
            let notification = reason == .remoteNotification
                ? FamilySyncActivityDiff.notification(localData: localData, remoteData: remoteData)
                : nil
            try importDataset(remoteData, from: root, context: context)
            markSynced(uploaded: false, downloaded: true)
            await notifyAboutRemoteChangesIfNeeded(
                notification,
                remoteChecksum: remoteChecksum
            )
            if !hasLocalPending || reason == .launch {
                return true
            }
            root = try await fetchRootRecord(id: rootID, role: storedRole)
        }

        guard hasLocalPending || reason == .manual else {
            markSynced(uploaded: false, downloaded: false)
            return false
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
        return true
    }

    func leaveFamilyShare(context: ModelContext, deleteLocalData: Bool) async throws {
        if deleteLocalData {
            try DataExportImportService.deleteAll(context: context)
        }
        if let rootID = storedRootRecordID {
            try? await deleteFamilySyncPushSubscription(rootRecordID: rootID, role: storedRole)
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
            DefaultsKey.lastNotifiedDatasetChecksum,
            DefaultsKey.pushSubscriptionID,
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

    private func isFamilySyncPush(userInfo: [AnyHashable: Any]) -> Bool {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return false
        }
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let subscriptionID = notification.subscriptionID else {
            return false
        }
        if let storedSubscriptionID = defaults.string(forKey: DefaultsKey.pushSubscriptionID) {
            return subscriptionID == storedSubscriptionID
        }
        return subscriptionID.hasPrefix(Constant.subscriptionIDPrefix)
    }

    private func ensureFamilySyncPushSubscription(
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) async throws {
        let subscriptionID = Self.subscriptionID(for: rootRecordID, role: role)
        if defaults.string(forKey: DefaultsKey.pushSubscriptionID) == subscriptionID {
            return
        }
        let subscription = CKRecordZoneSubscription(
            zoneID: rootRecordID.zoneID,
            subscriptionID: subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        _ = try await database(for: role).save(subscription)
        defaults.set(subscriptionID, forKey: DefaultsKey.pushSubscriptionID)
    }

    private func deleteFamilySyncPushSubscription(
        rootRecordID: CKRecord.ID,
        role: FamilyShareRole
    ) async throws {
        let subscriptionID = defaults.string(forKey: DefaultsKey.pushSubscriptionID)
            ?? Self.subscriptionID(for: rootRecordID, role: role)
        _ = try await database(for: role).deleteSubscription(withID: subscriptionID)
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
        try importDataset(datasetData(from: root), from: root, context: context)
    }

    private func importDataset(
        _ data: Data,
        from root: CKRecord,
        context: ModelContext
    ) throws {
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

    private func datasetData(from root: CKRecord) throws -> Data {
        guard let asset = root[Constant.datasetAssetKey] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw FamilySharingError.missingDataset
        }
        return try Data(contentsOf: fileURL)
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

    private func notifyAboutRemoteChangesIfNeeded(
        _ notification: FamilySyncActivityNotification?,
        remoteChecksum: String?
    ) async {
        guard let notification else { return }
        if let remoteChecksum,
           defaults.string(forKey: DefaultsKey.lastNotifiedDatasetChecksum) == remoteChecksum {
            return
        }
        await NotificationManager.shared.showFamilySyncActivityNotification(notification)
        if let remoteChecksum {
            defaults.set(remoteChecksum, forKey: DefaultsKey.lastNotifiedDatasetChecksum)
        }
    }
}

enum FamilySyncReason {
    case launch
    case localMutation
    case manual
    case remoteNotification
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

enum FamilySyncActivityDiff {
    static func notification(
        localData: Data,
        remoteData: Data
    ) -> FamilySyncActivityNotification? {
        guard let local = try? FamilySyncDatasetSnapshot(data: localData),
              let remote = try? FamilySyncDatasetSnapshot(data: remoteData) else {
            return nil
        }
        return remote.changeCandidates(comparedTo: local)
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
        var inventoryItems: [InventoryItemDigest]?
        var mealPrepItems: [MealPrepItemDigest]?
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

    struct FoodReminderDigest: Decodable {
        var id: UUID
        var typeRawValue: String
        var title: String
        var relatedShoppingListID: UUID?
        var relatedMealPrepItemID: UUID?
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
    var inventoryItemsByID: [UUID: InventoryItemDigest]
    var mealPrepItemsByID: [UUID: MealPrepItemDigest]
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
        inventoryItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.inventoryItems ?? []).map { ($0.id, $0) }
        )
        mealPrepItemsByID = Dictionary(
            uniqueKeysWithValues: (envelope.mealPrepItems ?? []).map { ($0.id, $0) }
        )
        foodRemindersByID = Dictionary(
            uniqueKeysWithValues: (envelope.foodReminders ?? []).map { ($0.id, $0) }
        )
    }

    func changeCandidates(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        var candidates = [ChangeCandidate]()
        candidates.append(contentsOf: eventChanges(comparedTo: local))
        candidates.append(contentsOf: milestoneChanges(comparedTo: local))
        candidates.append(contentsOf: appointmentChanges(comparedTo: local))
        candidates.append(contentsOf: shoppingListChanges(comparedTo: local))
        candidates.append(contentsOf: shoppingItemChanges(comparedTo: local))
        candidates.append(contentsOf: inventoryChanges(comparedTo: local))
        candidates.append(contentsOf: mealPrepChanges(comparedTo: local))
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

    private func foodReminderChanges(comparedTo local: FamilySyncDatasetSnapshot) -> [ChangeCandidate] {
        foodRemindersByID.values.compactMap { reminder in
            let previous = local.foodRemindersByID[reminder.id]
            guard isNewOrUpdated(remoteDate: reminder.updatedAt, localDate: previous?.updatedAt) else {
                return nil
            }
            let action = reminder.isEnabled ? (previous == nil ? "added" : "updated") : "turned off"
            let path: String
            if let listID = reminder.relatedShoppingListID {
                path = "food/shopping/\(listID.uuidString)"
            } else if let mealPrepID = reminder.relatedMealPrepItemID {
                path = "food/meal-prep/\(mealPrepID.uuidString)"
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
