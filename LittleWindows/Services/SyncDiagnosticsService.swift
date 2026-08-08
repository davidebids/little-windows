import Foundation
import SwiftData
import UIKit

@MainActor
enum SyncDiagnosticsService {
    private enum DefaultsKey {
        static let lastRemoteNotificationRegistrationAt =
            "syncDiagnostics.lastRemoteNotificationRegistrationAt"
        static let lastRemoteNotificationRegistrationError =
            "syncDiagnostics.lastRemoteNotificationRegistrationError"
    }

    static func recordRemoteNotificationRegistrationSuccess(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        defaults.set(now, forKey: DefaultsKey.lastRemoteNotificationRegistrationAt)
        defaults.removeObject(forKey: DefaultsKey.lastRemoteNotificationRegistrationError)
    }

    static func recordRemoteNotificationRegistrationFailure(
        _ error: Error,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        defaults.set(now, forKey: DefaultsKey.lastRemoteNotificationRegistrationAt)
        defaults.set(
            error.localizedDescription,
            forKey: DefaultsKey.lastRemoteNotificationRegistrationError
        )
    }

    static func snapshot(context: ModelContext) -> SyncDiagnosticSnapshot {
        let profiles = (try? context.fetch(FetchDescriptor<CareProfile>())) ?? []
        let profileIDs = Set(profiles.map(\.id))
        let eventCount = count(CareEvent.self, context: context)
        let recordCount = count(SleepPredictionRecord.self, context: context)
        let milestoneCount = count(MilestoneEntry.self, context: context)
        let appointmentCount = count(DoctorAppointment.self, context: context)
        let ageGuideStateCount = count(AgeGuideReadState.self, context: context)
        let puppyGuideStateCount = count(PuppyStageGuideReadState.self, context: context)
        let solidsProfileStateCount = count(SolidsProfileState.self, context: context)
        let solidFoodProgressCount = count(SolidFoodProgress.self, context: context)
        let solidFoodEventItemCount = count(SolidFoodEventItem.self, context: context)
        let solidAllergenProgressCount = count(SolidAllergenProgress.self, context: context)
        let plannedSolidMealCount = count(PlannedSolidMeal.self, context: context)
        let medicationCount = count(Medication.self, context: context)
        let medicationRegimenCount = count(MedicationRegimen.self, context: context)
        let medicationPhaseCount = count(MedicationSchedulePhase.self, context: context)
        let medicationDoseCount = count(MedicationDoseRecord.self, context: context)
        let medicationSupplyLogCount = count(MedicationSupplyLog.self, context: context)

        let orphanedCount =
            orphanedCount(total: eventCount, profileIDs: profileIDs) { profileID in
                count(CareEvent.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: recordCount, profileIDs: profileIDs) { profileID in
                count(SleepPredictionRecord.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: milestoneCount, profileIDs: profileIDs) { profileID in
                count(MilestoneEntry.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: appointmentCount, profileIDs: profileIDs) { profileID in
                count(DoctorAppointment.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: ageGuideStateCount, profileIDs: profileIDs) { profileID in
                count(AgeGuideReadState.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: puppyGuideStateCount, profileIDs: profileIDs) { profileID in
                count(PuppyStageGuideReadState.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: solidsProfileStateCount, profileIDs: profileIDs) { profileID in
                count(SolidsProfileState.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: solidFoodProgressCount, profileIDs: profileIDs) { profileID in
                count(SolidFoodProgress.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: solidFoodEventItemCount, profileIDs: profileIDs) { profileID in
                count(SolidFoodEventItem.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: solidAllergenProgressCount, profileIDs: profileIDs) { profileID in
                count(SolidAllergenProgress.self, profileID: profileID, context: context)
            }
            + orphanedCount(total: plannedSolidMealCount, profileIDs: profileIDs) { profileID in
                count(PlannedSolidMeal.self, profileID: profileID, context: context)
            }
            + orphanedProfileScopedCount(Medication.self, profileIDs: profileIDs, context: context)
            + orphanedProfileScopedCount(MedicationRegimen.self, profileIDs: profileIDs, context: context)
            + orphanedProfileScopedCount(MedicationSchedulePhase.self, profileIDs: profileIDs, context: context)
            + orphanedProfileScopedCount(MedicationDoseRecord.self, profileIDs: profileIDs, context: context)
            + orphanedProfileScopedCount(MedicationSupplyLog.self, profileIDs: profileIDs, context: context)

        let duplicateChildProfiles = Dictionary(grouping: profiles.filter {
            !$0.isArchived
                && $0.profileType == .child
        }, by: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .values
            .map { max(0, $0.count - 1) }
            .reduce(0, +)

        return SyncDiagnosticSnapshot(
            generatedAt: Date(),
            profileCount: profiles.count,
            activeProfileCount: profiles.filter { !$0.isArchived }.count,
            recordCounts: [
                SyncDiagnosticCount(name: "Profiles", count: profiles.count),
                SyncDiagnosticCount(name: "Events", count: eventCount),
                SyncDiagnosticCount(name: "Predictions", count: recordCount),
                SyncDiagnosticCount(name: "Milestones", count: milestoneCount),
                SyncDiagnosticCount(name: "Appointments", count: appointmentCount),
                SyncDiagnosticCount(name: "Age guide states", count: ageGuideStateCount),
                SyncDiagnosticCount(name: "Puppy guide states", count: puppyGuideStateCount),
                SyncDiagnosticCount(name: "Solids profile states", count: solidsProfileStateCount),
                SyncDiagnosticCount(name: "Solid food progress", count: solidFoodProgressCount),
                SyncDiagnosticCount(name: "Solid food event items", count: solidFoodEventItemCount),
                SyncDiagnosticCount(name: "Solid allergen progress", count: solidAllergenProgressCount),
                SyncDiagnosticCount(name: "Planned solid meals", count: plannedSolidMealCount),
                SyncDiagnosticCount(name: "Medications", count: medicationCount),
                SyncDiagnosticCount(name: "Medication regimens", count: medicationRegimenCount),
                SyncDiagnosticCount(name: "Medication phases", count: medicationPhaseCount),
                SyncDiagnosticCount(name: "Medication doses", count: medicationDoseCount),
                SyncDiagnosticCount(name: "Medication supply logs", count: medicationSupplyLogCount),
                SyncDiagnosticCount(name: "Households", count: count(Household.self, context: context)),
                SyncDiagnosticCount(name: "Food stores", count: count(FoodStore.self, context: context)),
                SyncDiagnosticCount(name: "Store sections", count: count(FoodStoreSection.self, context: context)),
                SyncDiagnosticCount(name: "Shopping lists", count: count(ShoppingList.self, context: context)),
                SyncDiagnosticCount(name: "Shopping items", count: count(ShoppingListItem.self, context: context)),
                SyncDiagnosticCount(name: "Food items", count: count(FoodItem.self, context: context)),
                SyncDiagnosticCount(name: "Inventory locations", count: count(InventoryLocation.self, context: context)),
                SyncDiagnosticCount(name: "Inventory items", count: count(InventoryItem.self, context: context)),
                SyncDiagnosticCount(name: "Meal prep items", count: count(MealPrepItem.self, context: context)),
                SyncDiagnosticCount(name: "Meal prep usage", count: count(MealPrepUsage.self, context: context)),
                SyncDiagnosticCount(name: "Food reminders", count: count(FoodReminder.self, context: context))
            ],
            orphanedProfileScopedRecordCount: orphanedCount,
            duplicateChildProfileNameCount: duplicateChildProfiles,
            migrationState: CloudMigrationService.state(),
            lastLocalSaveAt: PersistenceService.lastLocalSaveAt(),
            isRegisteredForRemoteNotifications:
                UIApplication.shared.isRegisteredForRemoteNotifications,
            lastRemoteNotificationRegistrationAt: UserDefaults.standard.object(
                forKey: DefaultsKey.lastRemoteNotificationRegistrationAt
            ) as? Date,
            lastRemoteNotificationRegistrationError: UserDefaults.standard.string(
                forKey: DefaultsKey.lastRemoteNotificationRegistrationError
            )
        )
    }

    private static func count<Record: PersistentModel>(
        _ type: Record.Type,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<Record>())) ?? 0
    }

    private static func orphanedCount(
        total: Int,
        profileIDs: Set<UUID>,
        validCount: (UUID) -> Int
    ) -> Int {
        max(0, total - profileIDs.reduce(0) { $0 + validCount($1) })
    }

    private static func orphanedProfileScopedCount<Record: PersistentModel & ProfileScopedRecord>(
        _ type: Record.Type,
        profileIDs: Set<UUID>,
        context: ModelContext
    ) -> Int {
        ((try? context.fetch(FetchDescriptor<Record>())) ?? []).filter {
            $0.profileID.map(profileIDs.contains) != true
        }.count
    }

    private static func count(
        _ type: CareEvent.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<CareEvent>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: SleepPredictionRecord.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: MilestoneEntry.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<MilestoneEntry>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: DoctorAppointment.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: AgeGuideReadState.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<AgeGuideReadState>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: PuppyStageGuideReadState.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<PuppyStageGuideReadState>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: SolidsProfileState.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: SolidFoodProgress.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: SolidFoodEventItem.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<SolidFoodEventItem>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: SolidAllergenProgress.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }

    private static func count(
        _ type: PlannedSolidMeal.Type,
        profileID: UUID,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? 0
    }
}
