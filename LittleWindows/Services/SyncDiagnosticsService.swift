import Foundation
import SwiftData

@MainActor
enum SyncDiagnosticsService {
    static func snapshot(context: ModelContext) -> SyncDiagnosticSnapshot {
        let profiles = (try? context.fetch(FetchDescriptor<BabyProfile>())) ?? []
        let profileIDs = Set(profiles.map(\.id))
        let events = (try? context.fetch(FetchDescriptor<BabyEvent>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<SleepPredictionRecord>())) ?? []
        let milestones = (try? context.fetch(FetchDescriptor<MilestoneEntry>())) ?? []
        let appointments = (try? context.fetch(FetchDescriptor<DoctorAppointment>())) ?? []
        let ageGuideStates = (try? context.fetch(FetchDescriptor<AgeGuideReadState>())) ?? []
        let puppyGuideStates = (try? context.fetch(FetchDescriptor<PuppyStageGuideReadState>())) ?? []
        let households = (try? context.fetch(FetchDescriptor<Household>())) ?? []
        let foodStores = (try? context.fetch(FetchDescriptor<FoodStore>())) ?? []
        let foodStoreSections = (try? context.fetch(FetchDescriptor<FoodStoreSection>())) ?? []
        let shoppingLists = (try? context.fetch(FetchDescriptor<ShoppingList>())) ?? []
        let shoppingItems = (try? context.fetch(FetchDescriptor<ShoppingListItem>())) ?? []
        let foodItems = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        let inventoryLocations = (try? context.fetch(FetchDescriptor<InventoryLocation>())) ?? []
        let inventoryItems = (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
        let mealPrepItems = (try? context.fetch(FetchDescriptor<MealPrepItem>())) ?? []
        let mealPrepUsages = (try? context.fetch(FetchDescriptor<MealPrepUsage>())) ?? []
        let foodReminders = (try? context.fetch(FetchDescriptor<FoodReminder>())) ?? []

        let orphanedCount =
            events.orphanedCount(profileIDs: profileIDs)
            + records.orphanedCount(profileIDs: profileIDs)
            + milestones.orphanedCount(profileIDs: profileIDs)
            + appointments.orphanedCount(profileIDs: profileIDs)
            + ageGuideStates.orphanedCount(profileIDs: profileIDs)
            + puppyGuideStates.orphanedCount(profileIDs: profileIDs)

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
                SyncDiagnosticCount(name: "Events", count: events.count),
                SyncDiagnosticCount(name: "Predictions", count: records.count),
                SyncDiagnosticCount(name: "Milestones", count: milestones.count),
                SyncDiagnosticCount(name: "Appointments", count: appointments.count),
                SyncDiagnosticCount(name: "Age guide states", count: ageGuideStates.count),
                SyncDiagnosticCount(name: "Puppy guide states", count: puppyGuideStates.count),
                SyncDiagnosticCount(name: "Households", count: households.count),
                SyncDiagnosticCount(name: "Food stores", count: foodStores.count),
                SyncDiagnosticCount(name: "Store sections", count: foodStoreSections.count),
                SyncDiagnosticCount(name: "Shopping lists", count: shoppingLists.count),
                SyncDiagnosticCount(name: "Shopping items", count: shoppingItems.count),
                SyncDiagnosticCount(name: "Food items", count: foodItems.count),
                SyncDiagnosticCount(name: "Inventory locations", count: inventoryLocations.count),
                SyncDiagnosticCount(name: "Inventory items", count: inventoryItems.count),
                SyncDiagnosticCount(name: "Meal prep items", count: mealPrepItems.count),
                SyncDiagnosticCount(name: "Meal prep usage", count: mealPrepUsages.count),
                SyncDiagnosticCount(name: "Food reminders", count: foodReminders.count)
            ],
            orphanedProfileScopedRecordCount: orphanedCount,
            duplicateChildProfileNameCount: duplicateChildProfiles,
            migrationState: CloudMigrationService.state(),
            lastLocalSaveAt: PersistenceService.lastLocalSaveAt()
        )
    }
}

private extension Array where Element: ProfileScopedRecord {
    func orphanedCount(profileIDs: Set<UUID>) -> Int {
        filter { record in
            guard let profileID = record.profileID else { return true }
            return !profileIDs.contains(profileID)
        }.count
    }
}
