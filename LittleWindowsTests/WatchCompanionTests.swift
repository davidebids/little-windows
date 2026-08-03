import SwiftData
import XCTest
@testable import LittleWindows

final class WatchCompanionTests: XCTestCase {
    @MainActor
    func testWatchStartsProfileScopedSleepTimer() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)
        let eventID = UUID()
        let issuedAt = Date().addingTimeInterval(-90)

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .performAction,
                profileID: profile.id,
                eventID: eventID,
                actionID: "sleep",
                optionID: "nap",
                issuedAt: issuedAt,
                timeZoneIdentifier: "America/Los_Angeles"
            ),
            container: container
        )

        XCTAssertEqual(acknowledgement.status, .applied)
        let event = try XCTUnwrap(fetchEvent(eventID, context: container.mainContext))
        XCTAssertEqual(event.profileID, profile.id)
        XCTAssertEqual(event.sleepKind, .nap)
        XCTAssertTrue(event.isTimerRunning)
        XCTAssertEqual(event.startDate, issuedAt)
        XCTAssertEqual(event.startTimeZoneIdentifier, "America/Los_Angeles")
    }

    @MainActor
    func testWatchCatalogIncludesSafeChildCareChoices() throws {
        let actions = WatchActionCatalog.actions(profileTypeRawValue: "child")

        XCTAssertEqual(
            Set(actions.map(\.id)),
            Set([
                "sleep", "nursing", "feed", "diaper", "pumping", "tummy-time",
                "potty", "story-time", "brush-teeth", "indoor-play",
                "outdoor-play", "screen-time", "bath"
            ])
        )
        XCTAssertTrue(actions.first { $0.id == "sleep" }?.options.contains {
            $0.id == "nightWaking"
        } == true)
        XCTAssertFalse(actions.first { $0.id == "feed" }?.options.contains {
            $0.id == "solid"
        } == true)
    }

    @MainActor
    func testWatchStartsOutdoorPlayTimerWithActivitySubtype() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)
        let eventID = UUID()

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .performAction,
                profileID: profile.id,
                eventID: eventID,
                actionID: "outdoor-play"
            ),
            container: container
        )

        XCTAssertEqual(acknowledgement.status, .applied)
        let event = try XCTUnwrap(fetchEvent(eventID, context: container.mainContext))
        XCTAssertEqual(event.type, .activity)
        XCTAssertEqual(event.activityType, .outdoorPlay)
        XCTAssertTrue(event.isTimerRunning)
    }

    @MainActor
    func testWatchCatalogIncludesDogGroomingTimer() {
        let grooming = WatchActionCatalog.actions(profileTypeRawValue: "dog")
            .first { $0.id == "grooming" }

        XCTAssertEqual(grooming?.categoryRawValue, EventType.grooming.rawValue)
        XCTAssertTrue(grooming?.startsTimer == true)
    }

    @MainActor
    func testWatchStopAndSaveUsesWatchTapTimeAtomically() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let startDate = Date().addingTimeInterval(-600)
        let stopDate = startDate.addingTimeInterval(420)
        let event = BabyEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: startDate,
            startTimeZoneIdentifier: "America/Los_Angeles",
            caregiverName: "Caregiver"
        )
        event.timerState = .running
        event.timerAccumulatedSeconds = 0
        event.activeTimerSegmentStartDate = startDate
        event.updatedAt = startDate
        container.mainContext.insert(profile)
        container.mainContext.insert(event)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .stopAndSaveTimer,
                profileID: profile.id,
                eventID: event.id,
                issuedAt: stopDate,
                timeZoneIdentifier: "America/Los_Angeles",
                expectedEventUpdatedAt: startDate
            ),
            container: container
        )

        XCTAssertEqual(acknowledgement.status, .applied)
        XCTAssertFalse(event.isTimerDraft)
        XCTAssertEqual(event.endDate, stopDate)
        XCTAssertEqual(event.duration ?? 0, 420, accuracy: 0.01)
    }

    @MainActor
    func testWatchDiscardRemovesPausedDraftWithoutSaving() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let pausedAt = Date().addingTimeInterval(-30)
        let event = BabyEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: pausedAt.addingTimeInterval(-300),
            startTimeZoneIdentifier: "America/Los_Angeles"
        )
        event.timerState = .stopped
        event.timerAccumulatedSeconds = 300
        event.activeTimerSegmentStartDate = nil
        event.updatedAt = pausedAt
        container.mainContext.insert(profile)
        container.mainContext.insert(event)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .discardTimer,
                profileID: profile.id,
                eventID: event.id,
                expectedEventUpdatedAt: pausedAt
            ),
            container: container
        )

        XCTAssertEqual(acknowledgement.status, .applied)
        XCTAssertNil(fetchEvent(event.id, context: container.mainContext))
        XCTAssertNil(acknowledgement.state?.activeTimer)
        XCTAssertTrue(acknowledgement.state?.allActions.contains {
            $0.id == "sleep"
        } == true)
    }

    @MainActor
    func testWatchQuickLogCreatesCompleteDogPottyEvent() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            profileType: .dog,
            name: "Test Dog",
            birthDate: Date().addingTimeInterval(-500 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)
        let eventID = UUID()

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .performAction,
                profileID: profile.id,
                eventID: eventID,
                actionID: "potty",
                optionID: "poop"
            ),
            container: container
        )

        XCTAssertEqual(acknowledgement.status, .applied)
        let event = try XCTUnwrap(fetchEvent(eventID, context: container.mainContext))
        XCTAssertEqual(event.type, .potty)
        XCTAssertEqual(event.profileTypeSnapshot, .dog)
        XCTAssertEqual(event.dogDetails.pottyType, .poop)
        XCTAssertEqual(event.dogDetails.pottyLocation, .outside)
        XCTAssertNotNil(event.endDate)
    }

    @MainActor
    func testDuplicateOfflineDeliveryCreatesOnlyOneEvent() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            profileType: .dog,
            name: "Test Dog",
            birthDate: Date().addingTimeInterval(-500 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let command = WatchCommand(
            kind: .performAction,
            profileID: profile.id,
            eventID: UUID(),
            actionID: "food"
        )

        let first = await WatchCommandProcessor.process(command, container: container)
        let duplicate = await WatchCommandProcessor.process(command, container: container)
        let profileID = profile.id
        let events = try container.mainContext.fetch(FetchDescriptor<BabyEvent>(
            predicate: #Predicate { $0.profileID == profileID }
        ))

        XCTAssertEqual(first.status, .applied)
        XCTAssertEqual(duplicate.status, .duplicate)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, command.eventID)
    }

    @MainActor
    func testDifferentRetryCommandIDStillCannotDuplicateEvent() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            profileType: .dog,
            name: "Test Dog",
            birthDate: Date().addingTimeInterval(-500 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let eventID = UUID()
        let first = WatchCommand(
            kind: .performAction,
            profileID: profile.id,
            eventID: eventID,
            actionID: "food"
        )
        let retriedWithNewCommandID = WatchCommand(
            kind: .performAction,
            profileID: profile.id,
            eventID: eventID,
            actionID: "food"
        )

        let firstAcknowledgement = await WatchCommandProcessor.process(
            first,
            container: container
        )
        let retryAcknowledgement = await WatchCommandProcessor.process(
            retriedWithNewCommandID,
            container: container
        )
        let profileID = profile.id
        let events = try container.mainContext.fetch(FetchDescriptor<BabyEvent>(
            predicate: #Predicate { $0.profileID == profileID }
        ))

        XCTAssertEqual(firstAcknowledgement.status, .applied)
        XCTAssertEqual(retryAcknowledgement.status, .duplicate)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, eventID)
    }

    @MainActor
    func testHiddenCategoryIsRejectedEvenFromStaleWatchState() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        CareCategoryPreferenceStore.setHidden(true, type: .diaper, profileID: profile.id)
        defer { CareCategoryPreferenceStore.reset(profileID: profile.id) }
        ProfileService.shared.switchProfile(profile)

        let state = WatchStateFactory.make(context: container.mainContext)
        let profileSnapshot = try XCTUnwrap(
            state.profiles.first { $0.id == profile.id }
        )

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .performAction,
                profileID: profile.id,
                eventID: UUID(),
                actionID: "diaper",
                optionID: "wet"
            ),
            container: container
        )
        let profileID = profile.id
        let events = try container.mainContext.fetch(FetchDescriptor<BabyEvent>(
            predicate: #Predicate { $0.profileID == profileID }
        ))

        XCTAssertEqual(acknowledgement.status, .rejected)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(profileSnapshot.hiddenCategoryRawValues, [EventType.diaper.rawValue])
    }

    @MainActor
    func testWatchStateOmitsTimerActionWhileThatTypeIsActive() throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let startDate = Date().addingTimeInterval(-90)
        let event = BabyEvent(
            profileID: profile.id,
            type: .nursing,
            startDate: startDate,
            startTimeZoneIdentifier: "America/Los_Angeles"
        )
        event.timerState = .running
        event.timerAccumulatedSeconds = 0
        event.activeTimerSegmentStartDate = startDate
        event.nursingSide = .left
        event.activeNursingSide = .left
        event.updatedAt = startDate
        container.mainContext.insert(profile)
        container.mainContext.insert(event)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)

        let state = WatchStateFactory.make(context: container.mainContext)

        XCTAssertNotNil(state.activeTimer)
        XCTAssertFalse(state.allActions.contains { $0.id == "nursing" })
        XCTAssertFalse(state.favoriteActions.contains { $0.id == "nursing" })
        XCTAssertTrue(state.allActions.contains { $0.id == "sleep" })
        XCTAssertEqual(
            state.selectedProfile?.activeTimerCategoryRawValues,
            [EventType.nursing.rawValue]
        )
    }

    @MainActor
    func testStaleWatchTimerCommandDoesNotOverwriteNewerPhoneEdit() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let snapshotDate = Date().addingTimeInterval(-600)
        let phoneEditDate = Date().addingTimeInterval(-60)
        let event = BabyEvent(
            profileID: profile.id,
            type: .sleep,
            startDate: snapshotDate,
            startTimeZoneIdentifier: "America/Los_Angeles"
        )
        event.timerState = .running
        event.activeTimerSegmentStartDate = snapshotDate
        event.updatedAt = phoneEditDate
        container.mainContext.insert(profile)
        container.mainContext.insert(event)
        try container.mainContext.save()

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .stopTimer,
                profileID: profile.id,
                eventID: event.id,
                issuedAt: Date(),
                expectedEventUpdatedAt: snapshotDate
            ),
            container: container
        )

        XCTAssertEqual(acknowledgement.status, .rejected)
        XCTAssertTrue(event.isTimerRunning)
        XCTAssertNil(event.endDate)
    }

    @MainActor
    func testWatchNursingSnapshotKeepsTotalAndActiveSideInSync() throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let startDate = Date().addingTimeInterval(-300)
        let snapshotDate = startDate.addingTimeInterval(120)
        let event = BabyEvent(
            profileID: profile.id,
            type: .nursing,
            startDate: startDate,
            startTimeZoneIdentifier: "America/Los_Angeles"
        )
        event.timerState = .running
        event.timerAccumulatedSeconds = 0
        event.activeTimerSegmentStartDate = startDate
        event.nursingSide = .left
        event.activeNursingSide = .left
        event.leftDurationSeconds = 0
        event.rightDurationSeconds = 0
        event.updatedAt = startDate.addingTimeInterval(60)
        container.mainContext.insert(profile)
        container.mainContext.insert(event)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)

        let snapshot = WatchStateFactory.make(
            context: container.mainContext,
            now: snapshotDate
        )
        let timer = try XCTUnwrap(snapshot.activeTimer)

        XCTAssertEqual(timer.elapsed(at: snapshotDate), 120, accuracy: 0.01)
        XCTAssertEqual(timer.leftDuration(at: snapshotDate), 120, accuracy: 0.01)
        XCTAssertEqual(timer.rightDuration(at: snapshotDate), 0, accuracy: 0.01)
        XCTAssertEqual(
            timer.elapsed(at: snapshotDate.addingTimeInterval(30)),
            150,
            accuracy: 0.01
        )
        XCTAssertEqual(
            timer.leftDuration(at: snapshotDate.addingTimeInterval(30)),
            150,
            accuracy: 0.01
        )
    }

    @MainActor
    func testWatchNursingSwitchBanksPreviousSide() async throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let startDate = Date().addingTimeInterval(-120)
        let switchDate = startDate.addingTimeInterval(75)
        let event = BabyEvent(
            profileID: profile.id,
            type: .nursing,
            startDate: startDate,
            startTimeZoneIdentifier: "America/Los_Angeles"
        )
        event.timerState = .running
        event.timerAccumulatedSeconds = 0
        event.activeTimerSegmentStartDate = startDate
        event.nursingSide = .left
        event.activeNursingSide = .left
        event.leftDurationSeconds = 0
        event.rightDurationSeconds = 0
        event.updatedAt = startDate
        container.mainContext.insert(profile)
        container.mainContext.insert(event)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)

        let acknowledgement = await WatchCommandProcessor.process(
            WatchCommand(
                kind: .switchNursingSide,
                profileID: profile.id,
                eventID: event.id,
                issuedAt: switchDate,
                expectedEventUpdatedAt: startDate
            ),
            container: container
        )
        let timer = try XCTUnwrap(acknowledgement.state?.activeTimer)
        let laterDate = switchDate.addingTimeInterval(20)

        XCTAssertEqual(acknowledgement.status, .applied)
        XCTAssertEqual(timer.activeNursingSideRawValue, "right")
        XCTAssertEqual(timer.leftDuration(at: laterDate), 75, accuracy: 0.01)
        XCTAssertEqual(timer.rightDuration(at: laterDate), 20, accuracy: 0.01)
        XCTAssertEqual(timer.elapsed(at: laterDate), 95, accuracy: 0.01)
    }

    @MainActor
    func testCustomWatchFavoritesKeepSavedOrderAndMaximum() throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)
        WatchFavoritePreferenceStore.setCustomActionIDs(
            [
                "diaper", "sleep", "diaper", "feed", "nursing",
                "pumping", "tummy-time", "potty"
            ],
            profileID: profile.id
        )
        defer {
            WatchFavoritePreferenceStore.useSmartFavorites(profileID: profile.id)
        }

        let state = WatchStateFactory.make(context: container.mainContext)

        XCTAssertEqual(
            state.favoriteActions.map(\.id),
            ["diaper", "sleep", "feed", "nursing", "pumping", "tummy-time"]
        )
        XCTAssertEqual(
            WatchFavoritePreferenceStore.customActionIDs(profileID: profile.id),
            ["diaper", "sleep", "feed", "nursing", "pumping", "tummy-time"]
        )
    }

    @MainActor
    func testCustomWatchFavoritesStillRespectHiddenCategories() throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)
        WatchFavoritePreferenceStore.setCustomActionIDs(
            ["diaper", "sleep"],
            profileID: profile.id
        )
        CareCategoryPreferenceStore.setHidden(
            true,
            type: .diaper,
            profileID: profile.id
        )
        defer {
            WatchFavoritePreferenceStore.useSmartFavorites(profileID: profile.id)
            CareCategoryPreferenceStore.reset(profileID: profile.id)
        }

        let state = WatchStateFactory.make(context: container.mainContext)

        XCTAssertEqual(state.favoriteActions.map(\.id), ["sleep"])
        XCTAssertFalse(state.allActions.contains { $0.id == "diaper" })
    }

    func testWatchStateReceiptRoundTripsRevision() throws {
        let revision = UUID()
        let receipt = WatchStateReceipt(
            schemaVersion: WatchCompanionProtocol.schemaVersion,
            stateRevision: revision,
            receivedAt: Date()
        )

        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(WatchStateReceipt.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, WatchCompanionProtocol.schemaVersion)
        XCTAssertEqual(decoded.stateRevision, revision)
        XCTAssertEqual(decoded.receivedAt, receipt.receivedAt)
    }

    @MainActor
    func testWatchStateFactoryLargeHistoryPerformance() throws {
        let container = try makeInMemoryContainer()
        let profile = BabyProfile(
            name: "Test Child",
            birthDate: Date().addingTimeInterval(-180 * 86_400)
        )
        let now = Date()
        container.mainContext.insert(profile)
        for index in 0..<600 {
            let loggedAt = now.addingTimeInterval(TimeInterval(-index * 1_200))
            let event = BabyEvent(
                profileID: profile.id,
                type: index.isMultiple(of: 2) ? .diaper : .feed,
                startDate: loggedAt,
                endDate: loggedAt,
                startTimeZoneIdentifier: "America/Los_Angeles",
                endTimeZoneIdentifier: "America/Los_Angeles"
            )
            event.profileTypeSnapshot = .child
            container.mainContext.insert(event)
        }
        try container.mainContext.save()
        ProfileService.shared.switchProfile(profile)

        var lastState = WatchCompanionState.empty
        measure(metrics: [XCTClockMetric()]) {
            lastState = WatchStateFactory.make(
                context: container.mainContext,
                now: now
            )
        }

        XCTAssertEqual(lastState.selectedProfileID, profile.id)
        XCTAssertLessThanOrEqual(lastState.todayMetrics.count, 6)
        XCTAssertLessThanOrEqual(lastState.favoriteActions.count, 6)
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = PersistenceService.schema
        let configuration = ModelConfiguration(
            "WatchCompanionTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func fetchEvent(_ id: UUID, context: ModelContext) -> BabyEvent? {
        var descriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
