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
            PredictionFactor.self
        ])
    }

    static func makeModelContainer() -> ModelContainer {
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
            startupErrorMessage = "CloudKit-backed store could not open: \(error.localizedDescription)"
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
    }

    static func recordLocalSave(at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: "lastSuccessfulLocalSaveAt")
    }

    static func lastLocalSaveAt(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: "lastSuccessfulLocalSaveAt") as? Date
    }
}
