import CloudKit
import SwiftData
import SwiftUI
import UIKit

@main
struct LittleWindowsApp: App {
    private static let sharedModelContainer = PersistenceService.makeModelContainer()
    private let modelContainer = Self.sharedModelContainer
    @UIApplicationDelegateAdaptor(LittleWindowsAppDelegate.self) private var appDelegate

    init() {
        let container = Self.sharedModelContainer
        CloudKitSharingService.install(container: container)
        IntegrationCommandStore.installInAppHandler { url in
            let processed = await IntegrationCommandProcessor.process(
                url,
                container: container
            )
            if processed {
                IntegrationCommandStore.clearPendingURL(matching: url)
            }
            return processed
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await NotificationManager.shared.configure()
                    await SampleData.seedIfNeeded(in: modelContainer.mainContext)
                    ProfileMigrationService.ensureProfilesAndAssignments(
                        context: modelContainer.mainContext
                    )
                    if PersistenceService.isICloudSyncEnabled() {
                        CloudMigrationService.ensureMigrated(context: modelContainer.mainContext)
                    }
                    CloudKitSharingService.processPendingAcceptedShareIfNeeded()
                    if PersistenceService.familySyncMode() == .sharedFamilySync {
                        try? await CloudKitSharingService.shared.syncNow(
                            context: modelContainer.mainContext,
                            reason: .launch
                        )
                    }
                    await restoreSystemIntegrations()
                    DeepLinkRouter.shared.isDataReady = true
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func restoreSystemIntegrations() async {
        let context = modelContainer.mainContext
        let profiles = (try? context.fetch(FetchDescriptor<BabyProfile>())) ?? []
        let profile = ProfileService.shared.ensureSelection(in: profiles)
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { event in
                event.startDate >= recentCutoff || event.endDate == nil
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        let events = ((try? context.fetch(eventDescriptor)) ?? [])
            .filter { $0.matchesProfile(profile?.id) }
        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.actualSleepEventID == nil || record.generatedAt >= recentCutoff
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        let records = ((try? context.fetch(recordDescriptor)) ?? [])
            .filter { $0.matchesProfile(profile?.id) }
        let currentRecord = records
            .filter { $0.actualSleepEventID == nil }
            .max { $0.generatedAt < $1.generatedAt }
        let prediction: SleepPrediction?
        if let currentRecord {
            prediction = currentRecord.prediction
        } else {
            prediction = profile.flatMap {
                SleepPredictionEngine.predict(
                    profile: $0,
                    events: events,
                    records: records.filter { $0.actualSleepEventID != nil }
                )
            }
            if let prediction {
                let lastSleepID = events
                    .filter { $0.type == .sleep && $0.endDate != nil }
                    .max { $0.startDate < $1.startDate }?
                    .id
                context.insert(SleepPredictionRecord(
                    prediction: prediction,
                    basedOnLastSleepEventID: lastSleepID,
                    profileID: profile?.id
                ))
                try? context.save()
                PersistenceService.recordLocalSave()
            }
        }
        WidgetSnapshotService.refresh(profile: profile, events: events, prediction: prediction)
        Task { @MainActor in
            await NotificationManager.shared.rescheduleLittleWindowAlertIfNeeded(
                prediction: prediction,
                babyName: profile?.name ?? "Baby",
                profileID: profile?.id,
                isSleeping: events.contains { $0.type == .sleep && $0.isTimerRunning }
            )
            if let profile,
               UserDefaults.standard.bool(forKey: "monthlyAgeGuideNotificationsEnabled") {
                let readStates = ((try? context.fetch(FetchDescriptor<AgeGuideReadState>())) ?? [])
                    .filter { $0.matchesProfile(profile.id) }
                let timing = MonthlyAgeGuideNotificationTiming(
                    rawValue: UserDefaults.standard.string(
                        forKey: "monthlyAgeGuideNotificationTiming"
                    ) ?? ""
                ) ?? .monthlyBirthday
                await NotificationManager.shared.scheduleMonthlyAgeGuideNotification(
                    profile: profile,
                    readStates: readStates,
                    context: context,
                    timing: timing
                )
            }
            await LiveActivityManager.shared.synchronize(profile: profile, events: events)
        }
    }
}

final class LittleWindowsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudKitSharingService.handleAcceptedShare(metadata: cloudKitShareMetadata)
    }
}
