import XCTest

final class WeatherDashboardUITests: XCTestCase {
    func testOutdoorActivityChoicesSupportAccessibilityText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        app.terminate(); launch(app, url: "littlewindows://weather", largeText: true)
        XCTAssertTrue(app.buttons["weather.outdoor-toolbar"].waitForExistence(timeout: 15))
        app.buttons["weather.outdoor-toolbar"].tap()
        let activity = app.buttons["weather.outdoor-activity.00000000-0000-0000-0000-000000000101"]
        for _ in 0..<6 where !activity.isHittable { app.swipeUp() }
        activity.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        let choice = app.buttons["Story time outside"]
        for _ in 0..<6 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.isHittable)
        XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
        capture(app, "Activity choices with accessibility text")
        choice.tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(activity.value as? String, "Story time outside")
    }
    func testColdOutdoorActivityChooserPerformanceAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/reset-empty")
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 20))
        app.terminate(); launch(app, url: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 30))
        app.terminate()
        launch(app, url: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today", audit: true)
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 15))
        app.buttons["today.weather.header"].tap()
        XCTAssertTrue(app.buttons["weather.outdoor-toolbar"].waitForExistence(timeout: 5))
        app.buttons["weather.outdoor-toolbar"].tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        var before = try auditReport(app)
        let child = app.buttons["weather.outdoor-activity.00000000-0000-0000-0000-000000000101"]
        let started = ContinuousClock.now
        child.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Nature walk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Fetch"].exists)
        print("COLD ACTIVITY LIST interaction: \(started.duration(to: .now))")
        before = try checkAudit(app, since: before, phase: "activity chooser first open")
        app.buttons["Nature walk"].tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(child.value as? String, "Nature walk")
        before = try checkAudit(app, since: before, phase: "activity selection child")
        child.tap()
        XCTAssertTrue(app.buttons["Nature walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Nature walk"].isSelected)
        before = try checkAudit(app, since: before, phase: "activity chooser reopen")
        app.buttons["Nature walk"].tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        before = try checkAudit(app, since: before, phase: "unchanged choice")
        let dog = app.buttons["weather.outdoor-activity.00000000-0000-0000-0000-000000000102"]
        for _ in 0..<6 where !dog.isHittable { app.swipeUp() }
        dog.tap()
        XCTAssertTrue(app.buttons["Fetch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Stroller walk"].exists)
        before = try checkAudit(app, since: before, phase: "activity chooser dog")
        app.buttons["Fetch"].tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(dog.value as? String, "Fetch")
        before = try checkAudit(app, since: before, phase: "activity selection dog")
        for _ in 0..<6 where !child.isHittable { app.swipeDown() }
        XCTAssertEqual(child.value as? String, "Nature walk")
        child.tap()
        XCTAssertTrue(app.buttons["Nature walk"].waitForExistence(timeout: 5))
        before = try checkAudit(app, since: before, phase: "activity chooser cancel")
        app.navigationBars["Activity"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(child.value as? String, "Nature walk")
        _ = try checkAudit(app, since: before, phase: "cancel choice")
        app.terminate()
        launch(app, url: "littlewindows://weather")
        XCTAssertTrue(app.buttons["weather.outdoor-toolbar"].waitForExistence(timeout: 15))
        app.buttons["weather.outdoor-toolbar"].tap()
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        XCTAssertEqual(child.value as? String, "Nature walk")
        for _ in 0..<6 where !dog.isHittable { app.swipeUp() }
        XCTAssertEqual(dog.value as? String, "Fetch")
    }

    func testHourlyControlsChangeDisplayedForecast() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        app.buttons["today.weather.header"].tap()
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 5))
        let feelsLike = app.switches["weather.hourly.feels-like"]
        try revealWeatherControl(feelsLike, in: app)
        print("Hourly toggle frame: \(feelsLike.frame); enabled: \(feelsLike.isEnabled); \(feelsLike.debugDescription)")
        capture(app, "Hourly controls before toggle")
        let initial = try XCTUnwrap(feelsLike.value as? String)
        feelsLike.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -26, dy: 0)).tap()
        capture(app, "Hourly controls after toggle")
        XCTAssertNotEqual(feelsLike.value as? String, initial)
    }
    func testNativePresentationReferenceAudit() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment = ["LITTLE_WINDOWS_INTERACTION_AUDIT": "1", "LITTLE_WINDOWS_INTERACTION_REFERENCE": "1"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Native reference"].waitForExistence(timeout: 15))
        var before = try auditReport(app)
        for attempt in 0..<3 {
            app.buttons["Open reference form"].tap()
            XCTAssertTrue(app.navigationBars["Reference form"].waitForExistence(timeout: 5))
            before = try checkAudit(app, since: before, phase: "native form \(attempt)")
            app.navigationBars["Reference form"].buttons["Done"].tap()
        }
    }
    func testColdPresentationPerformanceAudit() throws {
        try coldPresentationAudit(referenceForm: false)
    }
    func testColdEssentialsPerformanceAudit() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/reset-empty")
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 20))
        app.terminate(); launch(app, url: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 30))
        app.buttons["today.menu"].tap(); app.buttons["Customize Today"].tap()
        XCTAssertTrue(app.navigationBars["Today & Tracking"].waitForExistence(timeout: 5))
        app.segmentedControls["today-settings.layout"].buttons["Essentials"].tap()
        app.navigationBars["Today & Tracking"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["today.essential.feed"].waitForExistence(timeout: 5))
        app.terminate()
        launch(app, url: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today", audit: true)
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 15))
        var before = try auditReport(app)
        for attempt in 0..<3 {
            app.buttons["today.menu"].tap()
            before = try checkAudit(app, since: before, phase: "profile menu Essentials \(attempt)")
            app.buttons["Customize Today"].tap()
            XCTAssertTrue(app.navigationBars["Today & Tracking"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.segmentedControls["today-settings.layout"].buttons["Essentials"].isSelected)
            before = try checkAudit(app, since: before, phase: "Customize Essentials \(attempt)")
            app.navigationBars["Today & Tracking"].buttons["Done"].tap()
            before = try checkAudit(app, since: before, phase: "Dismiss Customize Essentials \(attempt)")
        }
    }
    func testColdNativeFormOverTodayReferenceAudit() throws {
        try coldPresentationAudit(referenceForm: true)
    }
    private func coldPresentationAudit(referenceForm: Bool) throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/reset-empty")
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 20))
        app.terminate()
        launch(app, url: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 30))
        app.terminate()
        launch(app, url: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today", audit: true, referenceForm: referenceForm)
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 15))
        var before = try auditReport(app)
        app.buttons["today.menu"].tap(); app.buttons["Customize Today"].tap()
        let title = referenceForm ? "Reference form" : "Today & Tracking"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        before = try checkAudit(app, since: before, phase: "cold Customize")
        app.navigationBars[title].buttons["Done"].tap()
        app.buttons["today.weather.header"].tap()
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 5))
        _ = try checkAudit(app, since: before, phase: "cold weather")
    }
    func testWeatherAnimationScenesStayResponsiveAndStopWhenCovered() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        for symbol in ["sun.max.fill", "cloud.rain.fill", "cloud.snow.fill", "wind"] {
            app.terminate()
            launch(app, url: "littlewindows://weather", audit: true, sceneSymbol: symbol)
            XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 15))
            let condition = ["sun.max.fill": "Clear", "cloud.rain.fill": "Rain", "cloud.snow.fill": "Snow", "wind": "Windy"][symbol]!
            let current = app.descendants(matching: .any).matching(identifier: "weather.current-conditions").firstMatch
            XCTAssertTrue(current.label.contains(condition), "Expected the requested scene fixture")
            capture(app, "Animated weather \(symbol)")
            let before = try auditReport(app)
            Thread.sleep(forTimeInterval: 1)
            let after = try checkAudit(app, since: before, phase: "animated scene \(symbol)")
            let frames = after.counts["weather.scene.frame", default: 0] - before.counts["weather.scene.frame", default: 0]
            XCTAssertGreaterThan(frames, 0, "Scene should be animating while visible")
            XCTAssertLessThanOrEqual(Double(frames) / max(0.001, after.uptime - before.uptime), 35)
            XCTAssertLessThan((after.cpu - before.cpu) / max(0.001, after.uptime - before.uptime), 0.2)
            XCTAssertEqual(after.counts["weather.body", default: 0], before.counts["weather.body", default: 0])
            XCTAssertEqual(after.counts["hourly.body", default: 0], before.counts["hourly.body", default: 0])
            app.buttons["weather.outdoor-toolbar"].tap()
            XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
            let covered = try auditReport(app)
            Thread.sleep(forTimeInterval: 1)
            let settled = try auditReport(app)
            XCTAssertEqual(covered.counts["weather.scene.frame", default: 0], settled.counts["weather.scene.frame", default: 0])
        }
    }
    func testWeatherInteractionPerformanceAudit() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/reset-empty")
        guard app.navigationBars["Welcome"].waitForExistence(timeout: 20) else { XCTFail("Fixture reset failed"); return }
        app.terminate(); launch(app, url: "littlewindows://debug/seed-performance")
        guard app.buttons["today.menu"].waitForExistence(timeout: 30) else { XCTFail("Fixture preparation failed"); return }
        app.terminate()
        launch(app, url: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today", audit: true)
        guard app.buttons["today.menu"].waitForExistence(timeout: 15) else { XCTFail("Today unavailable"); return }
        var before = try auditReport(app)
        attachAudit(before, phase: "cold-launch-ready")
        let ready = try XCTUnwrap(before.paints.first { $0.name == "today.ready" })
        XCTAssertLessThanOrEqual(ready.ms, 1500, "Cold Today must draw usable care content within 1.5 seconds of app initialization")
        for attempt in 0..<6 {
            app.buttons["today.menu"].tap()
            before = try checkAudit(app, since: before, phase: "profile menu \(attempt)")
            app.buttons["Customize Today"].tap()
            XCTAssertTrue(app.navigationBars["Today & Tracking"].waitForExistence(timeout: 5))
            before = try checkAudit(app, since: before, phase: "Customize \(attempt)")
            app.navigationBars["Today & Tracking"].buttons["Done"].tap()
            before = try checkAudit(app, since: before, phase: "Dismiss Customize \(attempt)")
        }
        app.buttons["today.weather.header"].tap()
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 5))
        before = try checkAudit(app, since: before, phase: "cold weather open")
        // The test runner waits here; the app keeps animating normally. This
        // measures idle CPU and whether animation invalidates its parent views.
        Thread.sleep(forTimeInterval: 1)
        let animation = try checkAudit(app, since: before, phase: "visible weather animation")
        XCTAssertEqual(animation.counts["weather.body", default: 0], before.counts["weather.body", default: 0])
        XCTAssertEqual(animation.counts["hourly.body", default: 0], before.counts["hourly.body", default: 0])
        XCTAssertLessThan((animation.cpu-before.cpu)/max(0.001,animation.uptime-before.uptime), 0.2)
        before = animation
        let measure = app.segmentedControls["weather.hourly.measure"]
        try revealWeatherControl(measure, in: app)
        for attempt in 0..<3 {
            try revealWeatherControl(measure, in: app)
            measure.buttons["Precipitation"].tap()
            XCTAssertTrue(measure.buttons["Precipitation"].isSelected)
            measure.buttons["Temperature"].tap()
            XCTAssertTrue(measure.buttons["Temperature"].isSelected)
            let feelsLike = app.switches["weather.hourly.feels-like"]
            try revealWeatherControl(feelsLike, in: app)
            let initial = try XCTUnwrap(feelsLike.value as? String)
            // The AX frame includes the label. Tap the native switch itself,
            // not the middle of its noninteractive label.
            feelsLike.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -26, dy: 0)).tap()
            XCTAssertNotEqual(feelsLike.value as? String, initial)
            before = try checkAudit(app, since: before, phase: "hourly controls \(attempt)")
        }
        Thread.sleep(forTimeInterval: 1)
        let offscreen = try checkAudit(app, since: before, phase: "offscreen weather animation")
        XCTAssertEqual(offscreen.counts["weather.scene.frame", default: 0], before.counts["weather.scene.frame", default: 0])
        before = offscreen
        for _ in 0..<6 where !app.buttons["Show 10 days"].isHittable { app.swipeUp() }
        for attempt in 0..<5 {
            app.buttons["Show 10 days"].tap(); app.buttons["Show 7 days"].tap()
            before = try checkAudit(app, since: before, phase: "forecast expansion \(attempt)")
        }
        let day = app.buttons.matching(identifier: "weather.forecast-day").firstMatch
        for _ in 0..<6 where !day.isHittable { app.swipeDown() }
        for attempt in 0..<3 {
            day.tap(); XCTAssertTrue(app.buttons["weather.day.done"].waitForExistence(timeout: 5))
            before = try checkAudit(app, since: before, phase: "open day \(attempt)")
            app.buttons["weather.day.done"].tap()
            before = try checkAudit(app, since: before, phase: "close day \(attempt)")
        }
        app.buttons["weather.outdoor-toolbar"].tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        before = try checkAudit(app, since: before, phase: "outdoor preferences open")
        let activity = app.buttons["weather.outdoor-activity.00000000-0000-0000-0000-000000000101"]
        for title in ["Nature walk", "Picnic", "Park visit"] {
            activity.tap(); app.buttons[title].tap()
            before = try checkAudit(app, since: before, phase: "activity \(title)")
        }
        let wind = app.steppers["weather.outdoor.wind.00000000-0000-0000-0000-000000000101"]
        for _ in 0..<4 where !wind.isHittable { app.swipeUp() }
        for attempt in 0..<3 {
            wind.buttons.element(boundBy: 1).tap(); wind.buttons.element(boundBy: 0).tap()
            before = try checkAudit(app, since: before, phase: "comfort limits \(attempt)")
        }
        app.navigationBars["Outdoor Preferences"].buttons.element(boundBy: 0).tap()
        app.buttons["Location"].tap()
        XCTAssertTrue(app.navigationBars["Location"].waitForExistence(timeout: 5))
        before = try checkAudit(app, since: before, phase: "location settings open")
        app.segmentedControls["weather.temperature-unit"].buttons["Celsius"].tap()
        app.segmentedControls["weather.temperature-unit"].buttons["Fahrenheit"].tap()
        _ = try checkAudit(app, since: before, phase: "unit changes")
    }

    private struct AuditReport: Codable {
        struct Cycle: Codable { var index: Int; var ms: Double }
        struct Paint: Codable { var index: Int; var name: String; var ms: Double; var cpuMS: Double }
        struct ScrollFrame: Codable { var index: Int; var name: String; var frames: Int; var duration: Double; var maxGapMS: Double; var lateMS: Double }
        var cycle: Int
        var slowCycles: [Cycle]
        var counts: [String: Int]
        var cpu: Double
        var uptime: Double
        var paints: [Paint]
        var scrollFrames: [ScrollFrame]
        var pending: [String: Double]
    }
    private func auditReport(_ app: XCUIApplication) throws -> AuditReport {
        let value = try XCTUnwrap(app.staticTexts["performance.audit"].firstMatch.value as? String)
        return try JSONDecoder().decode(AuditReport.self, from: Data(value.utf8))
    }
    private func attachAudit(_ report: AuditReport, phase: String) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Interaction audit · \(phase)"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @discardableResult
    private func checkAudit(_ app: XCUIApplication, since before: AuditReport, phase: String) throws -> AuditReport {
        let after = try auditReport(app)
        let maxMS = after.slowCycles.filter { $0.index > before.cycle }.map(\.ms).max() ?? 0
        let latestPaint = before.paints.last?.index ?? 0
        let paints = after.paints.filter { $0.index > latestPaint }
        let expectedPaints: Int
        if phase.hasPrefix("hourly controls") { expectedPaints = 3 }
        else if ["activity Nature walk", "activity Picnic", "activity Park visit"].contains(phase) { expectedPaints = 2 }
        else if phase.hasPrefix("forecast expansion") || phase.hasPrefix("comfort limits") || phase == "unit changes" { expectedPaints = 2 }
        else if phase.hasPrefix("Customize") || phase.hasPrefix("cold Customize") || phase.hasPrefix("cold weather") || phase.hasPrefix("native form") || phase.hasPrefix("open day") || phase.hasPrefix("activity") || phase == "outdoor preferences open" || phase == "location settings open" { expectedPaints = 1 }
        else { expectedPaints = 0 }
        XCTAssertEqual(paints.count, expectedPaints, "\(phase) did not exercise every intended state change")
        let counts = after.counts.mapValues { $0 }.map { key, value in "\(key)=\(value - (before.counts[key] ?? 0))" }.sorted().joined(separator: " ")
        print("INTERACTION AUDIT \(phase): raw-loop=\(maxMS)ms paints=\(paints.map { "\($0.name)=\($0.ms)ms/\($0.cpuMS)cpu-ms" }.joined(separator: ",")) CPU=\((after.cpu-before.cpu)/max(0.001,after.uptime-before.uptime)) \(counts)")
        attachAudit(after, phase: phase)
        // XCTest's accessibility snapshots themselves run on the app's main
        // thread. Keep raw cycles in the report, but gate app actions on their
        // input-to-draw latency, not on the test driver's subsequent AX work.
        for paint in paints {
            let first = !before.paints.contains { $0.name == paint.name }
            let budget: Double
            switch paint.name {
            // Native reference measurements on the same dense Today screen
            // are ~170 ms cold. A blanket 100 ms sheet limit would fail even
            // an empty native Form. Keep controls and warm draws stricter.
            case "today.ready": budget = 1500
            case "customize": budget = first ? 225 : 150
            case "native.form": budget = first ? 175 : 100
            case "weather.open": budget = first ? 300 : 200
            case "day.open": budget = first ? 175 : 125
            case "outdoor.open": budget = 175
            case "activity.open", "activity.choose": budget = 175
            case "location.open": budget = 225
            default: budget = 100
            }
            XCTAssertLessThanOrEqual(paint.ms, budget, "\(phase): \(paint.name) missed its \(budget) ms first-draw budget")
        }
        if phase.hasPrefix("Customize") || phase.hasPrefix("Dismiss Customize") || phase.hasPrefix("activity") || phase.hasPrefix("comfort limits") {
            let historyDelta = after.counts["today.history-build", default: 0] - before.counts["today.history-build", default: 0]
            let minuteDelta = after.counts["today.minute-history-build", default: 0] - before.counts["today.minute-history-build", default: 0]
            XCTAssertLessThanOrEqual(historyDelta, minuteDelta, "\(phase) requested care history beyond its independent minute freshness tick")
            for key in ["TodayInit", "AvatarBlobRead"] {
                XCTAssertEqual(after.counts[key, default: 0], before.counts[key, default: 0], "\(phase) unexpectedly repeated \(key)")
            }
        }
        if phase.hasPrefix("activity") || phase.hasPrefix("comfort limits") {
            for key in ["hourly.body", "daily.body"] {
                XCTAssertEqual(after.counts[key, default: 0], before.counts[key, default: 0], "\(phase) rebuilt an unrelated forecast")
            }
        }
        XCTAssertTrue(after.pending.isEmpty, "\(phase) has an interaction that never drew: \(after.pending)")
        if phase.hasPrefix("profile menu") || phase.contains("weather animation") {
            XCTAssertLessThanOrEqual(maxMS, 100, "\(phase) blocked the main run loop")
        }
        return after
    }
    func testHourlyPlotSelectionAndScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        app.terminate(); launch(app, url: "littlewindows://weather")
        let plot = app.descendants(matching: .any).matching(identifier: "weather.hourly.plot").firstMatch
        for _ in 0..<8 where !plot.isHittable || plot.frame.minY < 100 || plot.frame.maxY > app.frame.maxY - 180 { app.swipeUp() }
        XCTAssertTrue(plot.isHittable)
        let readout = app.descendants(matching: .any).matching(identifier: "weather.hourly.readout").firstMatch
        let initial = readout.label
        plot.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 87, dy: 60)).tap()
        XCTAssertNotEqual(readout.label, initial)
        capture(app, "Hourly selected temperature and pinned axis")
        let scroll = app.scrollViews["weather.hourly.scroll"]
        let beforeTemperatureScroll = readout.label
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: scroll.frame.maxX - 20, dy: plot.frame.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -min(180, scroll.frame.width - 40), dy: 0)))
        XCTAssertNotEqual(readout.label, beforeTemperatureScroll, "Dragging the graph must inspect later hours without a tap")
        let measure = app.segmentedControls["weather.hourly.measure"]
        measure.buttons["Precipitation"].tap()
        XCTAssertTrue(readout.label.contains("Precipitation chance"))
        XCTAssertTrue(readout.label.contains("%"))
        let beforeScroll = readout.label
        scroll.swipeLeft()
        XCTAssertNotEqual(readout.label, beforeScroll, "Precipitation readings must follow scrolling without a tap")
        let later = readout.label
        scroll.swipeRight()
        XCTAssertNotEqual(readout.label, later, "Readings must follow scrolling in both directions")
        let hour = scroll.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'weather.hourly.hour.'")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(hour)
        hour?.tap()
        capture(app, "Hourly selected precipitation after scrolling")
    }
    func testHourlyPlotSupportsAccessibilityText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        app.terminate(); launch(app, url: "littlewindows://weather", largeText: true)
        let readout = app.descendants(matching: .any).matching(identifier: "weather.hourly.readout").firstMatch
        for _ in 0..<12 where !readout.isHittable { app.swipeUp() }
        XCTAssertTrue(readout.isHittable)
        capture(app, "Hourly accessibility readout")
        let plot = app.descendants(matching: .any).matching(identifier: "weather.hourly.plot").firstMatch
        for _ in 0..<6 where !plot.isHittable || plot.frame.maxY > app.frame.maxY - 100 { app.swipeUp() }
        XCTAssertTrue(plot.isHittable)
        let initial = readout.label
        let scroll = app.scrollViews["weather.hourly.scroll"]
        scroll.swipeLeft()
        XCTAssertNotEqual(readout.label, initial)
        capture(app, "Hourly accessibility plot and scale")
    }
    func testWeatherDashboardForecastPreferencesAndDayDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20))
        app.terminate()
        launch(app, url: "littlewindows://weather")
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "weather.current-conditions").firstMatch.waitForExistence(timeout: 10))
        capture(app, "Weather overview")
        for _ in 0..<6 where !app.buttons["Show 10 days"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Show 10 days"].isHittable)
        app.buttons["Show 10 days"].tap()
        XCTAssertTrue(app.buttons["Show 7 days"].exists)
        capture(app, "Weather daily forecast")
        // Repeated expansion must settle before a day can be opened; a whole-
        // layout animation previously caused a lazy-stack update loop here.
        for _ in 0..<2 {
            app.buttons["Show 7 days"].tap()
            XCTAssertTrue(app.buttons["Show 10 days"].exists)
            app.buttons["Show 10 days"].tap()
            XCTAssertTrue(app.buttons["Show 7 days"].exists)
        }
        let day = app.buttons.matching(identifier: "weather.forecast-day").firstMatch
        for _ in 0..<8 where !day.isHittable { app.swipeDown() }
        XCTAssertTrue(day.isHittable)
        day.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Precipitation chance'")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "Weather selected day")
        app.buttons["weather.day.done"].tap()
        XCTAssertTrue(app.buttons["weather.day.done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 5))
        let preferences = app.buttons["weather.outdoor-toolbar"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Outdoor Preferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Outdoor suggestions"].firstMatch.exists)
        let activity = app.buttons["weather.outdoor-activity.00000000-0000-0000-0000-000000000101"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        XCTAssertTrue(app.buttons["Nature walk"].waitForExistence(timeout: 5))
        app.buttons["Nature walk"].tap()
        XCTAssertTrue(activity.label.contains("Nature walk") || (activity.value as? String)?.contains("Nature walk") == true)
        capture(app, "Outdoor preferences")
    }
    func testWeatherLargeTextAndLocationSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20))
        app.terminate()
        launch(app, url: "littlewindows://weather", largeText: true)
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 15))
        capture(app, "Weather accessibility text")
        let profiles = app.buttons["weather.outdoor-participants"]
        for _ in 0..<6 where !profiles.isHittable { app.swipeUp() }
        XCTAssertTrue(profiles.isHittable)
        capture(app, "Outdoor accessibility text")
        let day = app.buttons.matching(identifier: "weather.forecast-day").firstMatch
        for _ in 0..<8 where !day.isHittable { app.swipeUp() }
        XCTAssertTrue(day.isHittable)
        capture(app, "Forecast accessibility text")
        day.tap()
        XCTAssertTrue(app.buttons["weather.day.done"].waitForExistence(timeout: 5))
        capture(app, "Selected day accessibility text")
        app.buttons["weather.day.done"].tap()
        app.buttons["Location"].tap()
        XCTAssertTrue(app.navigationBars["Location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["weather.temperature-unit"].exists)
        capture(app, "Weather location and units")
    }
    func testOutingProfilesAreDiscoverableAndSelectable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        app.terminate(); launch(app, url: "littlewindows://weather")
        XCTAssertTrue(app.buttons["weather.dashboard.done"].waitForExistence(timeout: 15))
        let profiles = app.buttons["weather.outdoor-participants"]
        for _ in 0..<4 where !profiles.isHittable { app.swipeUp() }
        XCTAssertTrue(profiles.isHittable)
        XCTAssertEqual(profiles.label, "Change outing profiles")
        XCTAssertTrue(app.staticTexts["Change"].exists)
        capture(app, "Outdoor profile selector")
        profiles.tap()
        XCTAssertTrue(app.buttons["Sample Dog"].waitForExistence(timeout: 5))
        app.buttons["Sample Dog"].tap()
        XCTAssertTrue((profiles.value as? String)?.contains("Sample Dog") == true)
        profiles.tap(); app.buttons["Sample Child"].tap()
        XCTAssertEqual(profiles.value as? String, "Sample Dog")
        capture(app, "Outdoor time for selected profile")
    }
    func testColdProductionScaleCustomizeOpensPromptly() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/reset-empty")
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 20))
        app.terminate()
        launch(app, url: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 30))
        app.terminate()
        launch(app, url: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 15))
        for attempt in 0..<3 {
            let menuStarted = ContinuousClock.now
            app.buttons["today.menu"].tap()
            XCTAssertTrue(appearsPromptly(app.buttons["Customize Today"]))
            print("Profile menu presentation \(attempt): \(menuStarted.duration(to: .now))")
            let started = ContinuousClock.now
            app.buttons["Customize Today"].tap()
            XCTAssertTrue(appearsPromptly(app.navigationBars["Today & Tracking"]))
            let elapsed = started.duration(to: .now)
            print("Customize presentation \(attempt): \(elapsed)")
            XCTAssertLessThan(elapsed, .seconds(3), "Customize must not rebuild the underlying care screen before opening")
            app.navigationBars["Today & Tracking"].buttons["Done"].tap()
        }
    }
    func testCurrentWeatherAndCustomizeStayResponsiveWhileDetailsAreSlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/reset-empty")
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 20))
        app.terminate()
        launch(app, url: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 30))
        app.terminate()
        app.launchEnvironment = ["LITTLE_WINDOWS_UI_TESTING": "1", "LITTLE_WINDOWS_WEATHER_SLOW_DETAILS": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://profile/00000000-0000-0000-0000-000000000101/today"]
        app.launchArguments = ["--little-windows-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["today.weather.temperatures"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["today.weather.header"].value as? String, "Updating forecast")
        app.buttons["today.menu"].tap()
        let started = ContinuousClock.now
        app.buttons["Customize Today"].tap()
        XCTAssertTrue(appearsPromptly(app.navigationBars["Today & Tracking"]))
        let elapsed = started.duration(to: .now)
        print("Customize while forecast details are pending: \(elapsed)")
        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertTrue(app.segmentedControls["today-settings.layout"].exists)
        capture(app, "Responsive customization during slow weather details")
    }
    func testCustomizeDestinationsAndSavedLayoutRemainAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        launch(app, url: "littlewindows://debug/seed-smoke")
        XCTAssertTrue(app.buttons["today.menu"].waitForExistence(timeout: 20))
        app.buttons["today.menu"].tap(); app.buttons["Customize Today"].tap()
        let root = app.navigationBars["Today & Tracking"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        app.segmentedControls["today-settings.layout"].buttons["Full"].tap()
        app.buttons["Full Layout Quick Actions"].tap()
        let quickActions = app.navigationBars["Full Quick Actions"]
        XCTAssertTrue(quickActions.waitForExistence(timeout: 5))
        quickActions.buttons["Done"].tap()
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        for title in ["Visible Sections", "Tracking & Reminders"] {
            app.buttons[title].tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            bar.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(root.waitForExistence(timeout: 5))
        }
        app.segmentedControls["today-settings.layout"].buttons["Essentials"].tap()
        app.buttons["Activities & Button Order"].tap()
        let activities = app.navigationBars["Activities & Order"]
        XCTAssertTrue(activities.waitForExistence(timeout: 5))
        activities.buttons.element(boundBy: 0).tap()
        root.buttons["Done"].tap()
        app.buttons["today.menu"].tap(); app.buttons["Customize Today"].tap()
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["today-settings.layout"].buttons["Essentials"].isSelected)
        root.buttons["Done"].tap()
        app.buttons["today.menu"].tap()
        XCTAssertTrue(app.buttons["Settings & Profiles"].exists)
        XCTAssertTrue(app.buttons["Log Another Activity"].exists)
    }

    private func appearsPromptly(_ element: XCUIElement) -> Bool {
        // The standard existence wait adds a one-second poll even when visible.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !element.exists, ContinuousClock.now < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists
    }
    private func revealWeatherControl(_ element: XCUIElement, in app: XCUIApplication) throws {
        let top = app.navigationBars["Weather"].frame.maxY + 16
        let bottom = app.frame.maxY - 100
        for _ in 0..<10 {
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            if exists, element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
            let movement: CGFloat
            if exists && frame.minY < top { movement = min(260, top + 50 - frame.minY) }
            else if exists { movement = max(-260, bottom - 50 - frame.maxY) }
            else { movement = -260 }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: movement)))
        }
        XCTFail("Weather control could not be revealed clear of the navigation bar: \(element.identifier)")
        throw NSError(domain: "WeatherUITest", code: 1)
    }
    private func launch(_ app: XCUIApplication, url: String, largeText: Bool = false, audit: Bool = false, referenceForm: Bool = false, referenceScroll: Bool = false, sceneSymbol: String? = nil) {
        app.launchEnvironment = ["LITTLE_WINDOWS_UI_TESTING": "1", "LITTLE_WINDOWS_WEATHER_PREVIEW": "1", "LITTLE_WINDOWS_START_URL": url,
            "LITTLE_WINDOWS_PRESENTATION_AUDIT": "1", "LITTLE_WINDOWS_UI_TEST_PROFILE_PHOTO": "1"]
        if audit { app.launchEnvironment["LITTLE_WINDOWS_INTERACTION_AUDIT"] = "1" }
        if let sceneSymbol { app.launchEnvironment["LITTLE_WINDOWS_WEATHER_SCENE"] = sceneSymbol }
        if referenceForm { app.launchEnvironment["LITTLE_WINDOWS_INTERACTION_REFERENCE"] = "2" }
        if referenceScroll { app.launchEnvironment["LITTLE_WINDOWS_INTERACTION_REFERENCE"] = "3" }
        app.launchArguments = ["--little-windows-ui-testing", "--weather-preview"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
