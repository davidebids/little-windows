import XCTest

final class UserVisibleFlowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.debidia.LittleWindows")

    func testPlanDayArcAppearsInPlanner() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/seed-smoke"
        ]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "Expected app to foreground for plan day arc"
        )
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        var planButton = firstExistingButton(["Plan", "Plan bedtime"])
        for _ in 0..<6 where !planButton.exists {
            app.swipeUp()
            planButton = firstExistingButton(["Plan", "Plan bedtime"])
        }
        XCTAssertTrue(planButton.waitForExistence(timeout: 4), "Expected the planner button on Today")
        planButton.tap()

        XCTAssertTrue(
            waitForAnyText(["Plan bedtime", "Day Layout"], timeout: 6),
            "Expected the backwards sleep planner to open"
        )
        for _ in 0..<5 where !app.staticTexts["Wake to bedtime"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            app.staticTexts["Wake to bedtime"].waitForExistence(timeout: 4),
            "Expected the plan day arc to be visible"
        )
        app.swipeUp()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "plan-day-arc"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPhysicalUserVisibleFlowPass() {
        continueAfterFailure = false

        visit(
            name: "01-first-run-onboarding",
            startURL: "littlewindows://debug/reset-empty",
            expectedText: ["Set up your care home", "Welcome"]
        )
        visit(
            name: "02-seeded-today",
            startURL: "littlewindows://debug/seed-smoke",
            expectedText: ["Today", "Sample Child"]
        )
        visit(
            name: "03-reports-list",
            startURL: "littlewindows://history/list",
            expectedText: ["Reports", "Events"]
        )
        visit(
            name: "04-reports-summary",
            startURL: "littlewindows://reports/summary",
            expectedText: ["Reports", "Summary"]
        )
        visit(
            name: "05-shopping-list",
            startURL: "littlewindows://food/shopping/00000000-0000-0000-0000-000000000501",
            expectedText: ["Weekly groceries", "Bananas"]
        )
        visit(
            name: "06-shopping-mode",
            startURL: "littlewindows://food/shopping/00000000-0000-0000-0000-000000000501/mode",
            expectedText: ["Shopping Mode", "Bananas"]
        )
        visit(
            name: "07-inventory-item",
            startURL: "littlewindows://food/inventory/00000000-0000-0000-0000-000000000601",
            expectedText: ["Applesauce pouches"]
        )
        visit(
            name: "08-meal-prep-detail",
            startURL: "littlewindows://food/meal-prep/00000000-0000-0000-0000-000000000701",
            expectedText: ["Veggie puree cubes"]
        )
        visit(
            name: "09-appointment-detail",
            startURL: "littlewindows://appointment/00000000-0000-0000-0000-000000000301",
            expectedText: ["Six month checkup", "Neighborhood Clinic"]
        )
        visit(
            name: "10-event-detail",
            startURL: "littlewindows://event/00000000-0000-0000-0000-000000000201",
            expectedText: ["Sleep"]
        )
        visit(
            name: "11-milestones",
            startURL: "littlewindows://milestones",
            expectedText: ["Milestones", "Rolled from tummy to back"]
        )
        visit(
            name: "12-age-guide-detail",
            startURL: "littlewindows://age-guide/5",
            expectedText: ["5 Months", "Baby at 5 Months"]
        )
        visit(
            name: "13-dog-today",
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000102/today",
            expectedText: ["Today", "Sample Dog"]
        )
        visit(
            name: "14-puppy-guide",
            startURL: "littlewindows://puppy-guide",
            expectedText: ["Puppy Stage Guide", "Sample Dog at 6 Months"]
        )
        visit(
            name: "15-night-light",
            startURL: "littlewindows://night-light/diaper-change",
            expectedText: ["Night Light"]
        )
        visit(
            name: "16-settings",
            startURL: "littlewindows://settings",
            expectedText: ["Settings"]
        )
    }

    private func visit(name: String, startURL: String, expectedText: [String]) {
        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": startURL
        ]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "Expected app to foreground for \(name)"
        )
        let foundExpectedText = waitForAnyText(expectedText, timeout: 8)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(
            foundExpectedText,
            "Expected one of \(expectedText) for \(name)"
        )
    }

    private func waitForAnyText(_ values: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if values.contains(where: { value in
                app.staticTexts[value].exists
                    || app.navigationBars[value].exists
                    || app.buttons[value].exists
            }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func firstExistingButton(_ labels: [String]) -> XCUIElement {
        for label in labels {
            let button = app.buttons[label]
            if button.exists {
                return button
            }
        }
        return app.buttons[labels[0]]
    }
}
