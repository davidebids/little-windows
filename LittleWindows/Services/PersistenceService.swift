import Foundation
import SwiftData

struct PersistenceStartupFailure: LocalizedError {
    var syncMode: FamilySyncMode
    var cloudErrorDescription: String?
    var localErrorDescription: String
    var storeURL: URL

    var errorDescription: String? {
        "Little Windows could not open its data store."
    }
}

enum PersistenceService {
    static let localSaveDidFailNotification = Notification.Name(
        "PersistenceService.localSaveDidFail"
    )
    static let localSaveErrorKey = "lastLocalSaveError"

    static let storeName = "LittleWindows"
    static let appGroupIdentifier = "group.com.debidia.LittleWindows"
    static let iCloudSyncEnabledKey = "isICloudSyncEnabled"
    static let familySyncModeKey = "familySyncMode"

    // Update this if the bundle/team container in Xcode differs.
    static let iCloudContainerIdentifier = "iCloud.com.debidia.LittleWindows"

    static private(set) var startupErrorMessage: String?
    static private(set) var isUsingCloudKitStore = true
    static private(set) var syncModeAtStartup: FamilySyncMode = .privateICloudSync

    static var iCloudSyncEnabledAtStartup: Bool {
        syncModeAtStartup.requiresICloudAccount
    }

    static var schema: Schema {
        Schema([
            BabyProfile.self,
            PhotoAttachment.self,
            SolidFoodCatalogItem.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self,
            Household.self,
            FoodStore.self,
            FoodStoreSection.self,
            ShoppingList.self,
            ShoppingListItem.self,
            HomeTodoList.self,
            HomeTodoItem.self,
            PackingTrip.self,
            TripTraveler.self,
            PackingBag.self,
            PackingItem.self,
            FoodItem.self,
            InventoryLocation.self,
            InventoryItem.self,
            MealPrepItem.self,
            MealPrepUsage.self,
            ReturnRequest.self,
            ReturnItem.self,
            ReturnPackage.self,
            FoodReminder.self,
            CareRoutine.self,
            CareRoutineStep.self,
            CareRoutineRun.self
        ])
    }

    static func makeModelContainer() throws -> ModelContainer {
        syncModeAtStartup = familySyncMode()

        if shouldUseLocalStoreForValidation {
            do {
                return try makeLocalModelContainer(
                    startupMessage: "CloudKit-backed store skipped for local validation."
                )
            } catch {
                throw startupFailure(localError: error)
            }
        }

        switch syncModeAtStartup {
        case .localOnly:
            do {
                return try makeLocalModelContainer()
            } catch {
                throw startupFailure(localError: error)
            }
        case .sharedFamilySync:
            do {
                return try makeLocalModelContainer(
                    startupMessage: "Family Sync uses a local SwiftData store plus CloudKit shared records."
                )
            } catch {
                throw startupFailure(localError: error)
            }
        case .privateICloudSync:
            do {
                isUsingCloudKitStore = true
                startupErrorMessage = nil
                return try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(
                            storeName,
                            schema: schema,
                            cloudKitDatabase: .private(iCloudContainerIdentifier)
                        )
                    ]
                )
            } catch let cloudError {
                do {
                    return try makeLocalModelContainer(
                        startupMessage: "CloudKit-backed store could not open: \(cloudError.localizedDescription)"
                    )
                } catch let localError {
                    throw startupFailure(
                        cloudError: cloudError,
                        localError: localError
                    )
                }
            }
        }
    }

    private static var shouldUseLocalStoreForValidation: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["LW_CLOUDKIT_SYNC_SMOKE"] != nil {
            return false
        }
        if environment["LITTLE_WINDOWS_UI_TESTING"] == "1" {
            return true
        }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return true
        }
#if targetEnvironment(simulator)
        return true
#else
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
#endif
    }

    private static func makeLocalModelContainer(
        startupMessage: String? = nil
    ) throws -> ModelContainer {
        startupErrorMessage = startupMessage
        isUsingCloudKitStore = false
        return try ModelContainer(
            for: schema,
            configurations: [localModelConfiguration]
        )
    }

    private static var localModelConfiguration: ModelConfiguration {
        ModelConfiguration(
            storeName,
            schema: schema,
            cloudKitDatabase: .none
        )
    }

    static var storeURL: URL {
        localModelConfiguration.url
    }

    private static func startupFailure(
        cloudError: Error? = nil,
        localError: Error
    ) -> PersistenceStartupFailure {
        isUsingCloudKitStore = false
        let failure = PersistenceStartupFailure(
            syncMode: syncModeAtStartup,
            cloudErrorDescription: cloudError?.localizedDescription,
            localErrorDescription: localError.localizedDescription,
            storeURL: storeURL
        )
        startupErrorMessage = failure.localizedDescription
        return failure
    }

    static func makeFreshLocalModelContainer(
        preservedStoreAt archiveURL: URL?
    ) throws -> ModelContainer {
        setFamilySyncMode(.localOnly)
        syncModeAtStartup = .localOnly
        let message: String
        if archiveURL != nil {
            message = "The previous unreadable store was preserved. Little Windows opened a new local-only store."
        } else {
            message = "Little Windows opened a new local-only store."
        }
        return try makeLocalModelContainer(startupMessage: message)
    }

    @discardableResult
    static func preserveUnreadableStore(
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL? {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let archiveRoot = applicationSupport
            .appendingPathComponent("LittleWindows", isDirectory: true)
            .appendingPathComponent("UnreadableStores", isDirectory: true)
        return try preserveStoreArtifacts(
            at: storeURL,
            archiveRoot: archiveRoot,
            fileManager: fileManager,
            now: now
        )
    }

    @discardableResult
    static func preserveStoreArtifacts(
        at storeURL: URL,
        archiveRoot: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL? {
        let parent = storeURL.deletingLastPathComponent()
        let storeFilename = storeURL.lastPathComponent
        let storeBaseName = storeURL.deletingPathExtension().lastPathComponent
        let supportDirectoryName = ".\(storeBaseName)_SUPPORT"
        let artifacts = try fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: []
        )
        .filter { url in
            let name = url.lastPathComponent
            return name == storeFilename
                || name.hasPrefix("\(storeFilename)-")
                || name == supportDirectoryName
        }

        guard !artifacts.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let archiveURL = archiveRoot.appendingPathComponent(
            "unreadable-store-\(timestamp)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: archiveURL,
            withIntermediateDirectories: true
        )

        do {
            for artifact in artifacts {
                try fileManager.copyItem(
                    at: artifact,
                    to: archiveURL.appendingPathComponent(artifact.lastPathComponent)
                )
            }
        } catch {
            try? fileManager.removeItem(at: archiveURL)
            throw error
        }

        for artifact in artifacts {
            try fileManager.removeItem(at: artifact)
        }
        return archiveURL
    }

    static func recordLocalSave(at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: localSaveErrorKey)
        defaults.set(date, forKey: "lastSuccessfulLocalSaveAt")
        Task { @MainActor in
            CloudKitSharingService.noteLocalDataChanged()
        }
    }

    @MainActor
    @discardableResult
    static func save(
        context: ModelContext,
        recordForSync: Bool = true,
        defaults: UserDefaults = .standard
    ) -> Bool {
        do {
            try context.save()
            if recordForSync {
                recordLocalSave(defaults: defaults)
            }
            return true
        } catch {
            context.rollback()
            defaults.set(error.localizedDescription, forKey: localSaveErrorKey)
            NotificationCenter.default.post(
                name: localSaveDidFailNotification,
                object: nil,
                userInfo: ["message": error.localizedDescription]
            )
            return false
        }
    }

    static func lastLocalSaveAt(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: "lastSuccessfulLocalSaveAt") as? Date
    }

    static func isICloudSyncEnabled(defaults: UserDefaults = .standard) -> Bool {
        familySyncMode(defaults: defaults).requiresICloudAccount
    }

    static func setICloudSyncEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: iCloudSyncEnabledKey)
        setFamilySyncMode(enabled ? .privateICloudSync : .localOnly, defaults: defaults)
    }

    static func familySyncMode(defaults: UserDefaults = .standard) -> FamilySyncMode {
        if let rawValue = defaults.string(forKey: familySyncModeKey),
           let mode = FamilySyncMode(rawValue: rawValue) {
            return mode
        }
        guard defaults.object(forKey: iCloudSyncEnabledKey) != nil else {
            return .privateICloudSync
        }
        return defaults.bool(forKey: iCloudSyncEnabledKey) ? .privateICloudSync : .localOnly
    }

    static func setFamilySyncMode(_ mode: FamilySyncMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: familySyncModeKey)
        defaults.set(mode.requiresICloudAccount, forKey: iCloudSyncEnabledKey)
    }

    static var iCloudSyncChangeRequiresRestart: Bool {
        familySyncMode() != syncModeAtStartup
    }
}
