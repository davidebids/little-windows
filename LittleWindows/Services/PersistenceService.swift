import Foundation
import SwiftData

enum PersistenceService {
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
            FoodItem.self,
            InventoryLocation.self,
            InventoryItem.self,
            MealPrepItem.self,
            MealPrepUsage.self,
            FoodReminder.self
        ])
    }

    static func makeModelContainer() -> ModelContainer {
        syncModeAtStartup = familySyncMode()

        if shouldUseLocalStoreForValidation {
            return makeLocalModelContainer(
                startupMessage: "CloudKit-backed store skipped for local validation."
            )
        }

        switch syncModeAtStartup {
        case .localOnly:
            return makeLocalModelContainer()
        case .sharedFamilySync:
            return makeLocalModelContainer(
                startupMessage: "Family Sync uses a local SwiftData store plus CloudKit shared records."
            )
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
            } catch {
                return makeLocalModelContainer(
                    startupMessage: "CloudKit-backed store could not open: \(error.localizedDescription)"
                )
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
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static func makeLocalModelContainer(startupMessage: String? = nil) -> ModelContainer {
        startupErrorMessage = startupMessage
        isUsingCloudKitStore = false
        do {
            return try ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(
                        storeName,
                        schema: schema,
                        cloudKitDatabase: .none
                    )
                ]
            )
        } catch {
            fatalError("Unable to create the Little Windows data store: \(error)")
        }
    }

    static func recordLocalSave(at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: "lastSuccessfulLocalSaveAt")
        Task { @MainActor in
            CloudKitSharingService.noteLocalDataChanged()
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
