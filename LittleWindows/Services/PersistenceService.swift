import Foundation
import SwiftData

enum PersistenceService {
    static let storeName = "LittleWindows"
    static let appGroupIdentifier = "group.com.debidia.LittleWindows"

    // Update this if the bundle/team container in Xcode differs.
    static let iCloudContainerIdentifier = "iCloud.com.debidia.LittleWindows"

    static private(set) var startupErrorMessage: String?
    static private(set) var isUsingCloudKitStore = true

    static var schema: Schema {
        Schema([
            BabyProfile.self,
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
        if shouldUseLocalStoreForValidation {
            return makeLocalModelContainer(
                startupMessage: "CloudKit-backed store skipped for local validation."
            )
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
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return true
        }
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static func makeLocalModelContainer(startupMessage: String) -> ModelContainer {
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
}
