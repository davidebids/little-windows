import XCTest
@testable import LittleWindowsWatch

final class WatchCompanionProtocolTests: XCTestCase {
    func testChildCatalogKeepsSixCoreActionsFirst() {
        let actions = WatchActionCatalog.actions(profileTypeRawValue: "child")

        XCTAssertEqual(
            Array(actions.prefix(6).map(\.id)),
            ["sleep", "nursing", "feed", "diaper", "pumping", "tummy-time"]
        )
    }

    func testDogCatalogKeepsSixCoreActionsFirst() {
        let actions = WatchActionCatalog.actions(profileTypeRawValue: "dog")

        XCTAssertEqual(
            Array(actions.prefix(6).map(\.id)),
            ["food", "water", "potty", "walk", "treat", "rest"]
        )
    }

    func testTimerActionsAreIdentifiedForDuplicateStartFiltering() {
        let actions = WatchActionCatalog.actions(profileTypeRawValue: "child")

        XCTAssertTrue(actions.first { $0.id == "sleep" }?.startsTimer == true)
        XCTAssertTrue(actions.first { $0.id == "nursing" }?.startsTimer == true)
        XCTAssertFalse(actions.first { $0.id == "feed" }?.startsTimer == true)
    }

    func testStateContentComparisonIgnoresDeliveryMetadataOnly() {
        var original = WatchCompanionState.empty
        original.generatedAt = Date(timeIntervalSince1970: 1_000)
        original.revision = UUID()
        var refreshed = original
        refreshed.generatedAt = Date(timeIntervalSince1970: 2_000)
        refreshed.revision = UUID()

        XCTAssertTrue(original.hasSameContent(as: refreshed))

        refreshed.todayMetrics = [WatchMetricSnapshot(
            id: "feeds",
            title: "Feeds",
            value: "3",
            systemImage: "waterbottle.fill",
            tintName: "orange"
        )]
        XCTAssertFalse(original.hasSameContent(as: refreshed))
    }

    func testOlderCachedProfileSnapshotStillDecodesWithoutActionPolicy() throws {
        let profileID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": profileID.uuidString,
            "name": "Test Child",
            "profileTypeRawValue": "child",
            "displayColor": "indigo"
        ])

        let profile = try JSONDecoder().decode(WatchProfileSnapshot.self, from: data)

        XCTAssertEqual(profile.id, profileID)
        XCTAssertNil(profile.hiddenCategoryRawValues)
        XCTAssertNil(profile.activeTimerCategoryRawValues)
    }

    func testTransportSnapshotStaysCompactWithManyProfiles() throws {
        var state = WatchCompanionState.empty
        state.generatedAt = Date()
        state.profiles = (0..<50).map { index in
            WatchProfileSnapshot(
                id: UUID(),
                name: "Test Profile \(index)",
                profileTypeRawValue: index.isMultiple(of: 2) ? "child" : "dog",
                displayColor: "indigo",
                hiddenCategoryRawValues: ["custom", "growth"],
                activeTimerCategoryRawValues: ["sleep"]
            )
        }
        state.selectedProfileID = state.profiles.first?.id
        state.allActions = WatchActionCatalog.actions(profileTypeRawValue: "child")
        state.favoriteActions = Array(state.allActions.prefix(6))
        state.todayMetrics = (0..<6).map {
            WatchMetricSnapshot(
                id: "metric-\($0)",
                title: "Metric \($0)",
                value: "12",
                systemImage: "circle.fill",
                tintName: "indigo"
            )
        }

        let encoded = try JSONEncoder().encode(state)

        XCTAssertLessThan(encoded.count, 64 * 1_024)
    }

    func testLiveTimerTimelineAdvancesEachMinuteWithoutRefreshingOtherWidgets() {
        let start = Date(timeIntervalSince1970: 1_000)
        let liveDates = WatchCompanionTimeline.entryDates(
            timerIsRunning: true,
            from: start
        )
        let staticDates = WatchCompanionTimeline.entryDates(
            timerIsRunning: false,
            from: start
        )

        XCTAssertEqual(liveDates.count, 61)
        XCTAssertEqual(liveDates[1].timeIntervalSince(liveDates[0]), 60)
        XCTAssertEqual(liveDates.last, start.addingTimeInterval(60 * 60))
        XCTAssertEqual(staticDates, [start])
    }

    func testCommandRoundTripPreservesAtomicStopAndSave() throws {
        let command = WatchCommand(
            kind: .stopAndSaveTimer,
            profileID: UUID(),
            eventID: UUID(),
            issuedAt: Date(timeIntervalSince1970: 1_000),
            timeZoneIdentifier: "America/Los_Angeles"
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: data)

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.kind, .stopAndSaveTimer)
    }

    func testManualTimerStartRoundTripKeepsTapAndStartTimesSeparate() throws {
        let issuedAt = Date(timeIntervalSince1970: 10_000)
        let timerStartDate = issuedAt.addingTimeInterval(-17 * 60)
        let command = WatchCommand(
            kind: .performAction,
            profileID: UUID(),
            eventID: UUID(),
            actionID: "sleep",
            optionID: "nap",
            issuedAt: issuedAt,
            timerStartDate: timerStartDate
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: data)

        XCTAssertEqual(decoded.issuedAt, issuedAt)
        XCTAssertEqual(decoded.timerStartDate, timerStartDate)
    }

    func testManualTimerStartUsesSingleMinutePrecision() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 10_000)
        let first = WatchTimerStartPolicy.normalizedManualStart(
            Date(timeIntervalSince1970: 9_125),
            now: now,
            calendar: calendar
        )
        let second = WatchTimerStartPolicy.normalizedManualStart(
            Date(timeIntervalSince1970: 9_185),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(second.timeIntervalSince(first), 60)
        XCTAssertEqual(calendar.component(.second, from: first), 0)
        XCTAssertEqual(calendar.component(.second, from: second), 0)
    }

    func testQuickBackdatedStartUsesMinutesAgoAndClampsToWatchRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 10_020)

        let fiveMinutesAgo = WatchTimerStartPolicy.quickBackdatedStart(
            minutesAgo: 5,
            now: now,
            calendar: calendar
        )
        let sixMinutesAgo = WatchTimerStartPolicy.quickBackdatedStart(
            minutesAgo: 6,
            now: now,
            calendar: calendar
        )
        let belowRange = WatchTimerStartPolicy.quickBackdatedStart(
            minutesAgo: 0,
            now: now,
            calendar: calendar
        )
        let aboveRange = WatchTimerStartPolicy.quickBackdatedStart(
            minutesAgo: 500,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(fiveMinutesAgo.timeIntervalSince(now), -300, accuracy: 0.001)
        XCTAssertEqual(sixMinutesAgo.timeIntervalSince(fiveMinutesAgo), -60, accuracy: 0.001)
        XCTAssertEqual(belowRange.timeIntervalSince(now), -60, accuracy: 0.001)
        XCTAssertEqual(aboveRange.timeIntervalSince(now), -7_200, accuracy: 0.001)
    }

    func testDiscardCommandRoundTrip() throws {
        let command = WatchCommand(
            kind: .discardTimer,
            profileID: UUID(),
            eventID: UUID()
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: data)

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.kind, .discardTimer)
    }

    func testDirectDeliveryNeverSkipsAnOlderCommand() {
        let profileID = UUID()
        let older = WatchCommand(
            kind: .performAction,
            profileID: profileID,
            issuedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = WatchCommand(
            kind: .performAction,
            profileID: profileID,
            issuedAt: Date(timeIntervalSince1970: 1_001)
        )

        XCTAssertEqual(
            WatchCommandDeliveryOrder.nextDirectCommand(
                in: [newer, older],
                outstandingBackgroundCommandIDs: [],
                directCommandInFlightID: nil
            )?.id,
            older.id
        )
        XCTAssertNil(WatchCommandDeliveryOrder.nextDirectCommand(
            in: [newer, older],
            outstandingBackgroundCommandIDs: [older.id],
            directCommandInFlightID: nil
        ))
        XCTAssertNil(WatchCommandDeliveryOrder.nextDirectCommand(
            in: [newer, older],
            outstandingBackgroundCommandIDs: [],
            directCommandInFlightID: older.id
        ))
    }

    func testStoppedTimerDoesNotContinueCounting() {
        let timer = WatchTimerSnapshot(
            id: UUID(),
            profileID: UUID(),
            title: "Sleep",
            systemImage: "moon.fill",
            displayStartDate: Date(timeIntervalSince1970: 0),
            isRunning: false,
            elapsedSeconds: 300,
            activeNursingSideRawValue: nil,
            leftDurationSeconds: 0,
            rightDurationSeconds: 0,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(timer.elapsed(at: Date(timeIntervalSince1970: 2_000)), 300)
    }

    func testCachedTimerWithoutReferenceDateStillDecodes() throws {
        let timer = WatchTimerSnapshot(
            id: UUID(),
            profileID: UUID(),
            title: "Sleep",
            systemImage: "moon.fill",
            displayStartDate: Date(timeIntervalSince1970: 800),
            isRunning: true,
            elapsedSeconds: 120,
            activeNursingSideRawValue: nil,
            leftDurationSeconds: 0,
            rightDurationSeconds: 0,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        let data = try JSONEncoder().encode(timer)
        let decoded = try JSONDecoder().decode(WatchTimerSnapshot.self, from: data)

        XCTAssertNil(decoded.elapsedReferenceDate)
        XCTAssertEqual(decoded.elapsed(at: Date(timeIntervalSince1970: 1_030)), 150)
    }

    func testRunningTimerUsesDedicatedElapsedReferenceDate() {
        let timer = WatchTimerSnapshot(
            id: UUID(),
            profileID: UUID(),
            title: "Nursing",
            systemImage: "figure.and.child.holdinghands",
            displayStartDate: Date(timeIntervalSince1970: 700),
            isRunning: true,
            elapsedSeconds: 120,
            activeNursingSideRawValue: "left",
            leftDurationSeconds: 120,
            rightDurationSeconds: 0,
            updatedAt: Date(timeIntervalSince1970: 950),
            elapsedReferenceDate: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(timer.elapsed(at: Date(timeIntervalSince1970: 1_030)), 150)
        XCTAssertEqual(timer.leftDuration(at: Date(timeIntervalSince1970: 1_030)), 150)
        XCTAssertEqual(timer.rightDuration(at: Date(timeIntervalSince1970: 1_030)), 0)
    }

    func testAccruingNursingTimerBanksCurrentSideBeforeSwitch() {
        var timer = WatchTimerSnapshot(
            id: UUID(),
            profileID: UUID(),
            title: "Nursing",
            systemImage: "figure.and.child.holdinghands",
            displayStartDate: Date(timeIntervalSince1970: 700),
            isRunning: true,
            elapsedSeconds: 180,
            activeNursingSideRawValue: "left",
            leftDurationSeconds: 120,
            rightDurationSeconds: 60,
            updatedAt: Date(timeIntervalSince1970: 900),
            elapsedReferenceDate: Date(timeIntervalSince1970: 1_000)
        )

        timer.accrueLiveDurations(at: Date(timeIntervalSince1970: 1_045))
        timer.activeNursingSideRawValue = "right"

        XCTAssertEqual(timer.elapsedSeconds, 225)
        XCTAssertEqual(timer.leftDurationSeconds, 165)
        XCTAssertEqual(timer.rightDurationSeconds, 60)
        XCTAssertEqual(timer.leftDuration(at: Date(timeIntervalSince1970: 1_055)), 165)
        XCTAssertEqual(timer.rightDuration(at: Date(timeIntervalSince1970: 1_055)), 70)
    }
}
