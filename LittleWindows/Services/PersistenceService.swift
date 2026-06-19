import Foundation
import SwiftData

enum PersistenceService {
    static let storeName = "LittleWindows"
    static let appGroupIdentifier = "group.com.debidia.LittleWindows"
    static let iCloudSyncEnabledKey = "isICloudSyncEnabled"

    // Update this if the bundle/team container in Xcode differs.
    static let iCloudContainerIdentifier = "iCloud.com.debidia.LittleWindows"

    static private(set) var startupErrorMessage: String?
    static private(set) var isUsingCloudKitStore = true
    static private(set) var iCloudSyncEnabledAtStartup = true

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
        iCloudSyncEnabledAtStartup = isICloudSyncEnabled()

        if shouldUseLocalStoreForValidation {
            return makeLocalModelContainer(
                startupMessage: "CloudKit-backed store skipped for local validation."
            )
        }

        guard iCloudSyncEnabledAtStartup else {
            return makeLocalModelContainer()
        }

        do {
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
    }

    static func lastLocalSaveAt(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: "lastSuccessfulLocalSaveAt") as? Date
    }

    static func isICloudSyncEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: iCloudSyncEnabledKey) != nil else {
            return true
        }
        return defaults.bool(forKey: iCloudSyncEnabledKey)
    }

    static func setICloudSyncEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: iCloudSyncEnabledKey)
    }

    static var iCloudSyncChangeRequiresRestart: Bool {
        isICloudSyncEnabled() != iCloudSyncEnabledAtStartup
    }
}
