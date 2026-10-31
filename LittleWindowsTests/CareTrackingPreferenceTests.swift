import SwiftData
import SwiftUI
import XCTest
@testable import LittleWindows

@MainActor
final class CareTrackingPreferenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private final class CloudStore: CareTrackingCloudStore {
        var dictionaryRepresentation: [String: Any] = [:]
        var writes = 0
        var synchronizations = 0
        func data(forKey key: String) -> Data? { dictionaryRepresentation[key] as? Data }
        func set(_ value: Any?, forKey key: String) {
            dictionaryRepresentation[key] = value
            writes += 1
        }
        func synchronize() -> Bool { synchronizations += 1; return true }
    }

    private func device() throws -> UserDefaults {
        let suite = "CareTrackingDevice-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testRealStoreRoundTripMergesOfflineDevicesAndDoesNotRepublishUnchangedValues() throws {
        let cloud = CloudStore()
        let first = try device(), second = try device()
        let profileID = UUID(), otherID = UUID()
        for defaults in [first, second] { PersistenceService.setICloudSyncEnabled(false, defaults: defaults) }
        CareTrackingPreferenceStore.update(profileID: profileID, defaults: first, store: cloud) {
            $0.set("layout", value: ["essentials"])
            $0.set("paused.sleep", value: ["true"])
        }
        CareTrackingPreferenceStore.update(profileID: profileID, defaults: second, store: cloud) {
            $0.set("paused.feed", value: ["true"])
            $0.set("essentials", value: ["diaper", "sleep"])
        }
        XCTAssertEqual(cloud.writes, 0)
        for defaults in [first, second] { PersistenceService.setICloudSyncEnabled(true, defaults: defaults) }
        for defaults in [first, second, first] { CareTrackingPreferenceStore.synchronize(defaults: defaults, store: cloud) }
        let merged = CareTrackingPreferenceStore.preferences(profileID: profileID, defaults: first)
        XCTAssertEqual(merged, CareTrackingPreferenceStore.preferences(profileID: profileID, defaults: second))
        XCTAssertEqual(merged.pausedTypes, [.sleep, .feed])
        XCTAssertEqual(merged.layout, .essentials)
        XCTAssertEqual(merged.essentialTypes(for: .child), [.diaper])
        XCTAssertTrue(CareTrackingPreferenceStore.preferences(profileID: otherID, defaults: first).pausedTypes.isEmpty)
        let writes = cloud.writes
        CareTrackingPreferenceStore.synchronize(defaults: first, store: cloud)
        XCTAssertEqual(cloud.writes, writes)
    }

    func testStoreHonorsDeliberateResumeAfterReceivingFutureDatedPause() throws {
        let cloud = CloudStore(), defaults = try device()
        let profileID = UUID()
        var remote = CareTrackingPreferences()
        remote.set("paused.medicine", value: ["true"], now: Date().addingTimeInterval(86_400))
        cloud.set(try JSONEncoder().encode(remote), forKey: CareTrackingPreferenceStore.key(profileID))
        CareTrackingPreferenceStore.update(profileID: profileID, defaults: defaults, store: cloud) {
            $0.set("paused.medicine", value: ["false"])
        }
        let saved = CareTrackingPreferenceStore.preferences(profileID: profileID, defaults: defaults)
        XCTAssertTrue(saved.allows(.medicine))
        let uploaded = try JSONDecoder().decode(CareTrackingPreferences.self, from: XCTUnwrap(cloud.data(forKey: CareTrackingPreferenceStore.key(profileID))))
        XCTAssertEqual(saved, uploaded)
    }

    func testStoreDoesNotOverwriteNewerCloudSchema() throws {
        let cloud = CloudStore(), defaults = try device()
        let id = UUID()
        var remote = CareTrackingPreferences()
        remote.version = 2
        let data = try JSONEncoder().encode(remote)
        cloud.set(data, forKey: CareTrackingPreferenceStore.key(id))
        let writes = cloud.writes
        CareTrackingPreferenceStore.update(profileID: id, defaults: defaults, store: cloud) { $0.set("layout", value: ["essentials"]) }
        XCTAssertEqual(cloud.writes, writes)
        XCTAssertEqual(cloud.data(forKey: CareTrackingPreferenceStore.key(id)), data)
    }

    func testDisplayOnlyChangesDoNotRequireSystemReconciliationButTrackingAndWidgetChoicesDo() {
        let original = CareTrackingPreferences()
        var display = original
        display.selectLayout(.essentials, for: .child)
        display.set("essentials", value: ["diaper", "sleep", "feed"])
        display.set("section.essentials.timeline", value: ["true"])
        XCTAssertFalse(display.needsSystemReconciliation(comparedTo: original))
        XCTAssertFalse(original.needsSystemReconciliation(comparedTo: display))
        for key in ["paused.feed", "paused.medicine", "prompts.guides", "hidden.sleep"] {
            var changed = display
            changed.set(key, value: [key.hasPrefix("prompts.") ? "false" : "true"])
            XCTAssertTrue(changed.needsSystemReconciliation(comparedTo: display), key)
            XCTAssertTrue(display.needsSystemReconciliation(comparedTo: changed), key)
            var sameValues = changed
            sameValues.set(key, value: changed.fields[key]!.value)
            XCTAssertFalse(sameValues.needsSystemReconciliation(comparedTo: changed), key)
        }
    }

    func testOrderChangesPublishLatestValuesWithoutForcingCloudSynchronizationPerEdit() throws {
        let cloud = CloudStore(), defaults = try device()
        let profileID = UUID()
        PersistenceService.setICloudSyncEnabled(true, defaults: defaults)
        for order in [["sleep", "feed", "diaper"], ["diaper", "sleep", "feed"], ["feed", "diaper", "sleep"]] {
            CareTrackingPreferenceStore.update(profileID: profileID, defaults: defaults, store: cloud) {
                $0.set("essentials", value: order)
            }
        }
        let remote = try JSONDecoder().decode(CareTrackingPreferences.self,
            from: XCTUnwrap(cloud.data(forKey: CareTrackingPreferenceStore.key(profileID))))
        XCTAssertEqual(remote.configuredEssentials(for: .child), [.feed, .diaper, .sleep])
        XCTAssertEqual(remote, CareTrackingPreferenceStore.preferences(profileID: profileID, defaults: defaults))
        XCTAssertEqual(cloud.writes, 3)
        XCTAssertEqual(cloud.synchronizations, 0)
    }

    func testResetOnlyChangesCurrentLayoutAndKeepsTrackingPauses() {
        var preferences = CareTrackingPreferences()
        preferences.set("essentials", value: ["diaper", "feed"])
        preferences.set("section.essentials.timeline", value: ["true"])
        preferences.set("hidden.sleep", value: ["true"])
        preferences.set("paused.feed", value: ["true"])
        preferences.resetCurrentLayout(for: .child)
        XCTAssertEqual(preferences.configuredEssentials(for: .child), [.diaper, .feed])
        XCTAssertEqual(preferences.fields["section.essentials.timeline"]?.value, ["true"])
        XCTAssertEqual(preferences.fields["hidden.sleep"]?.value, ["false"])
        XCTAssertFalse(preferences.allows(.feed))
        preferences.set("layout", value: ["essentials"])
        preferences.set("section.full.weather", value: ["false"])
        preferences.resetCurrentLayout(for: .child)
        XCTAssertEqual(preferences.configuredEssentials(for: .child), [.sleep, .feed, .diaper])
        XCTAssertFalse(preferences.shows(.timeline))
        XCTAssertEqual(preferences.fields["section.full.weather"]?.value, ["false"])
        XCTAssertFalse(preferences.allows(.feed))
    }

    func testMedicationDueIsConditionalHideableAndDoesNotDuplicateChosenMedicationTile() {
        var preferences = CareTrackingPreferences()
        preferences.set("layout", value: ["essentials"])
        XCTAssertFalse(preferences.showsMedicationDueCard(scheduledAt: nil, profileType: .child))
        XCTAssertTrue(preferences.showsMedicationDueCard(scheduledAt: Date(), profileType: .child))
        preferences.set("essentials", value: ["sleep", "medicine"])
        XCTAssertFalse(preferences.showsMedicationDueCard(scheduledAt: Date(), profileType: .child))
        preferences.set("section.essentials.actions", value: ["false"])
        XCTAssertTrue(preferences.showsMedicationDueCard(scheduledAt: Date(), profileType: .child))
        preferences.set("section.essentials.medicationDue", value: ["false"])
        XCTAssertFalse(preferences.showsMedicationDueCard(scheduledAt: Date(), profileType: .child))
        preferences.set("section.essentials.medicationDue", value: ["true"])
        preferences.set("paused.medicine", value: ["true"])
        XCTAssertFalse(preferences.showsMedicationDueCard(scheduledAt: Date(), profileType: .child))
    }

    func testFirstEssentialsSelectionStaysIndependentFromLaterFullEditsAndResets() {
        for profileType in [CareProfileType.child, .adult, .dog] {
            var preferences = CareTrackingPreferences()
            let defaults = CareTrackingPreferences.defaultEssentials(for: profileType)
            let initiallyHidden = Set(defaults.prefix(1))
            preferences.selectLayout(.essentials, for: profileType, hidden: initiallyHidden)
            let selected = preferences.configuredEssentials(for: profileType)
            XCTAssertEqual(selected, Array(defaults.dropFirst()))
            preferences.selectLayout(.full, for: profileType)
            preferences.resetCurrentLayout(for: profileType)
            preferences.selectLayout(.essentials, for: profileType, hidden: Set(defaults))
            XCTAssertEqual(preferences.configuredEssentials(for: profileType), selected)
            preferences.set("essentials", value: [])
            preferences.selectLayout(.full, for: profileType)
            preferences.selectLayout(.essentials, for: profileType)
            XCTAssertTrue(preferences.configuredEssentials(for: profileType).isEmpty)
        }
    }

    func testCompactTimersKeepStoppedAndConcurrentDraftsWithoutDuplicatingTheRepresentedTimer() {
        let id = UUID()
        let represented = CareEvent(profileID: id, type: .nursing, startDate: now)
        let concurrent = CareEvent(profileID: id, type: .nursing, startDate: now)
        let stopped = CareEvent(profileID: id, type: .sleep, startDate: now)
        stopped.timerState = .stopped
        stopped.timerAccumulatedSeconds = 120
        let saved = CareEvent(profileID: id, type: .sleep, startDate: now, endDate: now.addingTimeInterval(60))
        let events = [represented, concurrent, stopped, saved]
        XCTAssertEqual(TodayEssentialsTimerPresentation.compactTimers(events: events, represented: [represented]).map(\.id),
                       [concurrent.id, stopped.id])
        XCTAssertEqual(TodayEssentialsTimerPresentation.compactTimers(events: events, represented: []).map(\.id),
                       [represented.id, concurrent.id, stopped.id])
        XCTAssertFalse(stopped.isTimerRunning)
        XCTAssertEqual(stopped.timerElapsed(at: now.addingTimeInterval(600)), 120)
    }

    func testSwitchingAnExistingEssentialsLayoutToFullPreservesItsImplicitChoices() {
        var preferences = CareTrackingPreferences()
        preferences.set("layout", value: ["essentials"])
        preferences.selectLayout(.full, for: .child, hidden: [.feed])
        preferences.selectLayout(.essentials, for: .child)
        XCTAssertEqual(preferences.configuredEssentials(for: .child), [.sleep, .diaper])
    }

    func testMedicationDueUsesLocalDayBoundaryAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let tonight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 30)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 15)))
        var preferences = CareTrackingPreferences()
        preferences.set("layout", value: ["essentials"])
        XCTAssertTrue(preferences.showsMedicationDueCard(scheduledAt: tonight, profileType: .child, now: current, calendar: calendar))
        XCTAssertFalse(preferences.showsMedicationDueCard(scheduledAt: tomorrow, profileType: .child, now: current, calendar: calendar))
        XCTAssertFalse(preferences.showsMedicationDueCard(scheduledAt: current.addingTimeInterval(-25 * 60 * 60), profileType: .child, now: current, calendar: calendar))
    }

    func testGuideAndAppointmentPausesAlsoQuietTheirRoutineStepsAndNotifications() throws {
        let defaults = try device(), id = UUID()
        var preferences = CareTrackingPreferences()
        preferences.set("prompts.guides", value: ["false"])
        preferences.set("prompts.appointments", value: ["false"])
        defaults.set(try JSONEncoder().encode(preferences), forKey: CareTrackingPreferenceStore.key(id))
        for action in [CareRoutineStepAction.openAgeGuide, .openPuppyGuide, .openAppointments] {
            XCTAssertFalse(preferences.allowsRoutineStep(eventType: nil, action: action))
        }
        XCTAssertTrue(preferences.allowsRoutineStep(eventType: nil, action: .checklist))
        XCTAssertFalse(CareTrackingPreferenceStore.allowsNotification(
            identifier: "routine.reminder.test",
            userInfo: ["profileID": id.uuidString, "trackingPromptSectionRawValues": ["guides"]], defaults: defaults
        ))
    }

    func testOneOffRecordInPausedCategoryPersistsWithoutResumingOrReappearingInSuggestions() async throws {
        let container = try ModelContainer(for: PersistenceService.schema, configurations: [
            ModelConfiguration(schema: PersistenceService.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let profile = CareProfile(name: "Test Child", birthDate: now.addingTimeInterval(-180 * 86_400))
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let key = CareTrackingPreferenceStore.key(profile.id)
        var preferences = CareTrackingPreferences()
        preferences.set("paused.feed", value: ["true"])
        UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let event = CareEvent(profileID: profile.id, type: .feed, startDate: now, endDate: now)
        event.feedKind = .bottle
        let saved = await EventMutationService.persistStandaloneEvent(event, container: container)
        XCTAssertTrue(saved)
        let stored = try ModelContext(container).fetch(FetchDescriptor<CareEvent>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.profileID, profile.id)
        XCTAssertFalse(CareTrackingPreferenceStore.allows(.feed, profileID: profile.id))
        let snapshot = WidgetSnapshotService.makeSnapshot(profileID: profile.id, babyName: "Test Child", events: stored, prediction: nil, now: now)
        XCTAssertFalse(snapshot.resolvedQuickActions.contains { $0.destinationPath == "quick-log/feed" })
    }

    func testWidgetUsesAdultMetricsAndRemainingEnabledCategoriesRatherThanBlankSummary() {
        var snapshot = WidgetSnapshotService.makeSnapshot(profileID: UUID(), profileType: .adult, babyName: "Test Adult", events: [], prediction: nil)
        XCTAssertEqual(snapshot.todaySummary.widgetMetrics?.map(\.id), ["medicine", "symptoms", "blood-pressure", "heart-rate"])
        let metric = CareSummaryMetricSnapshot(id: "growth", title: "Growth", value: "1", systemImage: "ruler", tintName: "green", eventTypeRawValue: "growth")
        snapshot.todaySummary.summaryMetrics = [metric]
        XCTAssertEqual(snapshot.todaySummary.widgetMetrics, [metric])
        snapshot.todaySummary.summaryMetrics = []
        XCTAssertEqual(snapshot.todaySummary.widgetMetrics, [])
        snapshot.todaySummary.summaryMetrics = nil
        XCTAssertNil(snapshot.todaySummary.widgetMetrics)
    }

    func testExistingInstallKeepsFullLayoutWithoutPausingCategories() {
        let preferences = CareTrackingPreferences()
        XCTAssertEqual(preferences.layout, .full)
        XCTAssertTrue(preferences.pausedTypes.isEmpty)
        XCTAssertTrue(CareTodaySection.allCases.filter { $0 != .medicationDue }.allSatisfy(preferences.shows))
        XCTAssertFalse(preferences.shows(.medicationDue))
    }

    func testEssentialsHasItsOwnMinimalDefaultsAndProfileAppropriateActivities() {
        var preferences = CareTrackingPreferences()
        preferences.set("layout", value: ["essentials"])
        XCTAssertEqual(CareTodaySection.allCases.filter(preferences.shows), [.actions, .medicationDue, .activeTimers])
        XCTAssertEqual(preferences.essentialTypes(for: .child), [.sleep, .feed, .diaper])
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
        preferences.set("section.essentials.activeTimers", value: ["false"])
        XCTAssertFalse(preferences.shows(.activeTimers))
        preferences.set("section.essentials.timeline", value: ["true"])
        XCTAssertTrue(preferences.shows(.timeline))
        preferences.set("layout", value: ["full"])
        XCTAssertTrue(preferences.shows(.activeTimers))
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
        XCTAssertEqual(preferences.essentialTypes(for: .child, hidden: [.diaper]), [.sleep, .feed])
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
        resumed = CareTrackingPreferences()
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
        XCTAssertGreaterThanOrEqual(regularSize.height, 120)
        XCTAssertEqual(regularSize.width, 288, accuracy: 1)
        let accessible = UIHostingController(rootView: EssentialsActionButton(
            type: .bloodPressure, profileType: .adult,
            detail: "No recent record · tap to log", count: 3, action: {}
        ).dynamicTypeSize(.accessibility3))
        let accessibleSize = accessible.sizeThatFits(in: CGSize(width: 288, height: 2_000))
        XCTAssertGreaterThan(accessibleSize.height, regularSize.height)
        XCTAssertEqual(accessibleSize.width, 288, accuracy: 1)
        let accessibleRenderer = ImageRenderer(content: EssentialsActionButton(
            type: .bloodPressure, profileType: .adult,
            detail: "No recent record · tap to log", count: 3, action: {}
        ).dynamicTypeSize(.accessibility3).frame(width: 288).background(Color(uiColor: .systemBackground)))
        let accessibleAttachment = XCTAttachment(image: try XCTUnwrap(accessibleRenderer.uiImage))
        accessibleAttachment.name = "Essentials full-width accessibility text"
        accessibleAttachment.lifetime = .keepAlways
        add(accessibleAttachment)
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
