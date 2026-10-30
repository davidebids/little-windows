import SwiftData
import SwiftUI
import XCTest
@testable import LittleWindows

@MainActor
final class CareTrackingPreferenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExistingInstallKeepsFullLayoutWithoutPausingCategories() {
        let preferences = CareTrackingPreferences()
        XCTAssertEqual(preferences.layout, .full)
        XCTAssertTrue(preferences.pausedTypes.isEmpty)
        XCTAssertTrue(CareTodaySection.allCases.allSatisfy(preferences.shows))
    }

    func testEssentialsHasItsOwnMinimalDefaultsAndProfileAppropriateActivities() {
        var preferences = CareTrackingPreferences()
        preferences.set("layout", value: ["essentials"])
        XCTAssertEqual(CareTodaySection.allCases.filter(preferences.shows), [.actions])
        XCTAssertEqual(preferences.essentialTypes(for: .child), [.sleep, .feed, .diaper, .medicine])
        XCTAssertEqual(preferences.essentialTypes(for: .adult), [.medicine, .symptom, .bloodPressure, .sleep])
        XCTAssertEqual(preferences.essentialTypes(for: .dog), [.food, .potty, .walk, .rest])
    }

    func testHidingASectionDoesNotPauseTrackingOrPrompts() {
        var preferences = CareTrackingPreferences()
        preferences.set("section.full.prediction", value: ["false"])
        preferences.set("section.full.timeline", value: ["false"])
        XCTAssertFalse(preferences.shows(.prediction))
        XCTAssertFalse(preferences.shows(.timeline))
        XCTAssertTrue(preferences.allows(.sleep))
        XCTAssertTrue(preferences.allowsPrompts(.prediction))
        preferences.set("layout", value: ["essentials"])
        preferences.set("section.essentials.timeline", value: ["true"])
        XCTAssertTrue(preferences.shows(.timeline))
        preferences.set("layout", value: ["full"])
        XCTAssertFalse(preferences.shows(.timeline))
    }

    func testPauseQuietsRelatedSectionsWithoutErasingChosenOrder() {
        var preferences = CareTrackingPreferences()
        preferences.set("essentials", value: ["diaper", "sleep", "feed"])
        preferences.set("paused.sleep", value: ["true"])
        preferences.set("paused.feed", value: ["true"])
        XCTAssertEqual(preferences.essentialTypes(for: .child), [.diaper])
        XCTAssertEqual(preferences.configuredEssentials(for: .child), [.diaper, .sleep, .feed])
        XCTAssertFalse(preferences.shows(.prediction))
        XCTAssertFalse(preferences.shows(.sleepPlan))
        XCTAssertFalse(preferences.shows(.solids))
        preferences.set("paused.sleep", value: ["false"])
        XCTAssertEqual(preferences.essentialTypes(for: .child), [.diaper, .sleep])
    }

    func testExplicitSelectionCanBeEmptyAndRejectsUnsupportedOrDuplicateTypes() {
        var preferences = CareTrackingPreferences()
        preferences.set("essentials", value: [])
        XCTAssertTrue(preferences.essentialTypes(for: .child).isEmpty)
        preferences.set("essentials", value: ["diaper", "diaper", "walk", "unknown", "sleep"])
        XCTAssertEqual(preferences.essentialTypes(for: .child), [.diaper, .sleep])
        XCTAssertEqual(preferences.essentialTypes(for: .dog), [.walk])
    }

    func testLegacyHiddenActionsOnlyAffectInitialEssentialsAndNeverBecomePauses() {
        var preferences = CareTrackingPreferences()
        XCTAssertEqual(preferences.essentialTypes(for: .child, hidden: [.diaper]), [.sleep, .feed, .medicine])
        XCTAssertTrue(preferences.allows(.diaper))
        preferences.set("essentials", value: ["diaper"])
        XCTAssertEqual(preferences.essentialTypes(for: .child, hidden: [.diaper]), [.diaper])
    }

    func testOfflineEditsToDifferentFieldsMergeInEitherDirection() throws {
        var deviceA = CareTrackingPreferences()
        var deviceB = CareTrackingPreferences()
        deviceA.set("paused.sleep", value: ["true"], now: now, revision: "a")
        deviceB.set("paused.diaper", value: ["true"], now: now, revision: "b")
        deviceB.set("layout", value: ["essentials"], now: now, revision: "c")
        let merged = deviceA.merging(deviceB)
        XCTAssertEqual(merged, deviceB.merging(deviceA))
        XCTAssertEqual(merged.pausedTypes, [.sleep, .diaper])
        XCTAssertEqual(merged.layout, .essentials)
        XCTAssertEqual(try JSONDecoder().decode(CareTrackingPreferences.self, from: JSONEncoder().encode(merged)), merged)
    }

    func testNewerResumeWinsOverStalePauseAndEqualTimeConflictsConverge() {
        var stale = CareTrackingPreferences()
        var resumed = CareTrackingPreferences()
        stale.set("paused.sleep", value: ["true"], now: now, revision: "a")
        resumed.set("paused.sleep", value: ["false"], now: now.addingTimeInterval(1), revision: "b")
        XCTAssertTrue(stale.merging(resumed).allows(.sleep))
        XCTAssertEqual(stale.merging(resumed), resumed.merging(stale))
        resumed.set("paused.sleep", value: ["false"], now: now, revision: "b")
        XCTAssertEqual(stale.merging(resumed), resumed.merging(stale))
        XCTAssertTrue(stale.merging(resumed).allows(.sleep))
        XCTAssertEqual(stale.merging(resumed).merging(stale), stale.merging(resumed))
    }

    func testProfileIsolationInvalidPayloadAndVersionFallback() throws {
        let suite = "CareTrackingTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        var preferences = CareTrackingPreferences()
        preferences.set("paused.feed", value: ["true"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(first))
        XCTAssertFalse(CareTrackingPreferenceStore.preferences(profileID: first, defaults: defaults).allows(.feed))
        XCTAssertTrue(CareTrackingPreferenceStore.preferences(profileID: second, defaults: defaults).allows(.feed))
        defaults.set(Data("invalid".utf8), forKey: CareTrackingPreferenceStore.key(second))
        XCTAssertEqual(CareTrackingPreferenceStore.preferences(profileID: second, defaults: defaults).layout, .full)
        preferences.version = 2
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(first))
        XCTAssertTrue(CareTrackingPreferenceStore.preferences(profileID: first, defaults: defaults).allows(.feed))
    }

    func testNotificationPolicyQuietsCategoryRequestsButLeavesHouseholdAndOtherProfilesAlone() throws {
        let suite = "CareTrackingNotifications-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        var preferences = CareTrackingPreferences()
        preferences.set("paused.sleep", value: ["true"])
        preferences.set("paused.feed", value: ["true"])
        preferences.set("paused.medicine", value: ["true"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(id))
        let info: [AnyHashable: Any] = ["profileID": id.uuidString]
        for identifier in ["profile.\(id).littlewindow.next", "profile.\(id).sleepPressure.ready", "profile.\(id).activeSleepPlan.wake", "solids.meal.test", "solids.allergen.test", "medication.test.followup", "medication.test.snooze"] {
            XCTAssertFalse(CareTrackingPreferenceStore.allowsNotification(identifier: identifier, userInfo: info, defaults: defaults), identifier)
        }
        XCTAssertTrue(CareTrackingPreferenceStore.allowsNotification(identifier: "food.reminder.test", userInfo: info, defaults: defaults))
        XCTAssertTrue(CareTrackingPreferenceStore.allowsNotification(identifier: "medication.test", userInfo: ["profileID": UUID().uuidString], defaults: defaults))
        XCTAssertFalse(CareTrackingPreferenceStore.allowsNotification(identifier: "routine.reminder.test", userInfo: ["deepLink": "littlewindows://profile/\(id)/routines", "trackingCategoryRawValues": ["sleep"]], defaults: defaults))
        XCTAssertTrue(CareTrackingPreferenceStore.allowsNotification(identifier: "routine.reminder.test", userInfo: ["deepLink": "littlewindows://routines"], defaults: defaults))
    }

    func testPausedSleepKeepsHistoryAndActiveTimerButRemovesPredictionAndQuickActions() throws {
        let id = UUID()
        var preferences = CareTrackingPreferences()
        preferences.set("paused.sleep", value: ["true"])
        preferences.set("paused.diaper", value: ["true"])
        let key = CareTrackingPreferenceStore.key(id)
        UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let sleep = CareEvent(profileID: id, type: .sleep, startDate: now.addingTimeInterval(-600))
        sleep.timerStateRawValue = "running"
        let diaper = CareEvent(profileID: id, type: .diaper, startDate: now.addingTimeInterval(-1200), endDate: now.addingTimeInterval(-1200))
        let snapshot = WidgetSnapshotService.makeSnapshot(profileID: id, babyName: "Test Child", events: [sleep, diaper], prediction: nil, now: now)
        XCTAssertNotNil(snapshot.activeTimer)
        let paths = snapshot.resolvedQuickActions.map(\.destinationPath)
        XCTAssertFalse(paths.contains("quick-log/sleep"))
        XCTAssertFalse(paths.contains("quick-log/diaper"))
        XCTAssertFalse((snapshot.todaySummary.summaryMetrics ?? []).contains { $0.eventTypeRawValue == "sleep" || $0.eventTypeRawValue == "diaper" })
        XCTAssertEqual(diaper.profileID, id)
        XCTAssertEqual(diaper.type, .diaper)
        XCTAssertTrue(sleep.isTimerDraft)
        XCTAssertEqual(NotificationManager.shared.statusText(prediction: nil, profileID: id), "Sleep tracking is paused")
        XCTAssertEqual(NotificationManager.sleepPressureStatusText(pressure: nil, enabled: true, profileID: id), "Sleep tracking is paused")
    }

    func testRoutineAndHomeSuggestionsRespectPausesWithoutChangingStoredPlans() throws {
        let container = try ModelContainer(for: PersistenceService.schema, configurations: [
            ModelConfiguration(schema: PersistenceService.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        let profile = CareProfile(name: "Test Child", birthDate: now.addingTimeInterval(-200 * 86_400))
        context.insert(profile)
        let routine = CareRoutine(scope: .profile, profileType: .child, profileID: profile.id, title: "Bedtime", reminderEnabled: true, reminderTimeMinutesAfterMidnight: 0)
        let step = CareRoutineStep(routineID: routine.id, title: "Sleep", action: .startTimer, eventType: .sleep, sortOrder: 0)
        context.insert(routine)
        context.insert(step)
        let plan = PlannedSolidMeal(profileID: profile.id, scheduledAt: now, title: "Meal", foodIDs: [], foodNames: [])
        context.insert(plan)
        try context.save()
        let key = CareTrackingPreferenceStore.key(profile.id)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        XCTAssertTrue(CareTrackingPreferenceStore.allowsRoutine(routine))
        var preferences = CareTrackingPreferences()
        preferences.set("paused.sleep", value: ["true"])
        preferences.set("paused.feed", value: ["true"])
        UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: key)
        XCTAssertFalse(CareTrackingPreferenceStore.allowsRoutine(routine))
        let summary = TodayHomeSummaryService.summary(
            householdID: UUID(), currentCaregiverName: "Test Caregiver", todoLists: [], todoItems: [],
            shoppingLists: [], shoppingItems: [], inventoryItems: [], mealPrepItems: [], mealPrepUsages: [],
            packingTrips: [], packingItems: [], itineraryItems: [], returnRequests: [], returnItems: [], returnPackages: [],
            reminders: [], profiles: [profile], careRoutines: [routine], plannedSolidMeals: [plan], now: now
        )
        XCTAssertFalse(summary.allAttentionItems.contains { $0.category == .routines || $0.category == .solids })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedSolidMeal>()), 1)
        XCTAssertFalse(plan.isCompleted)
        XCTAssertTrue(routine.reminderEnabled)
    }

    func testEssentialsButtonsKeepLargeTouchAreasAtNarrowWidthsAndAccessibilityText() throws {
        let regular = UIHostingController(rootView: EssentialsActionButton(
            type: .diaper, profileType: .child, detail: "Last 45 minutes ago", count: 3, action: {}
        ))
        let regularSize = regular.sizeThatFits(in: CGSize(width: 288, height: 2_000))
        XCTAssertGreaterThanOrEqual(regularSize.height, 148)
        XCTAssertEqual(regularSize.width, 288, accuracy: 1)
        let accessible = UIHostingController(rootView: EssentialsActionButton(
            type: .bloodPressure, profileType: .adult,
            detail: "No recent record · tap to log", count: 3, action: {}
        ).dynamicTypeSize(.accessibility3))
        let accessibleSize = accessible.sizeThatFits(in: CGSize(width: 288, height: 2_000))
        XCTAssertGreaterThan(accessibleSize.height, regularSize.height)
        let renderer = ImageRenderer(content: VStack(spacing: 12) {
            ForEach([EventType.sleep, .feed, .diaper]) { type in
                EssentialsActionButton(type: type, profileType: .child, detail: "No recent record · tap to log", count: 3, action: {})
            }
        }.padding(16).frame(width: 390).background(Color(uiColor: .systemBackground)))
        let rendered = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "Essentials production buttons at iPhone width"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
