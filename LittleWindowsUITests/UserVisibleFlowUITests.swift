import XCTest

final class UserVisibleFlowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.debidia.LittleWindows")

    func testSettingsMonthlyGuideNavigation() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://settings"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        let monthlyGuideRow = app.buttons["Monthly guide notifications"]
        for _ in 0..<4 where !monthlyGuideRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(monthlyGuideRow.waitForExistence(timeout: 3))

        monthlyGuideRow.tap()
        XCTAssertTrue(app.navigationBars["Monthly Guides"].waitForExistence(timeout: 4))
    }

    func testSolidFoodVisualPickerAndReactionControls() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/seed-smoke"
        ]
        app.launch()
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://quick-log/feed"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Add Event"].waitForExistence(timeout: 8))

        let kindPicker = app.buttons["event.feed-kind"]
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 4))
        kindPicker.tap()
        XCTAssertTrue(app.buttons["Solid"].waitForExistence(timeout: 2))
        app.buttons["Solid"].tap()

        let chooseFoods = app.buttons["solid-food.choose"]
        XCTAssertTrue(chooseFoods.waitForExistence(timeout: 4))
        chooseFoods.tap()

        XCTAssertTrue(app.navigationBars["Choose Foods"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Custom food"].exists)
        let foodSearch = app.searchFields["Search or enter a food"]
        XCTAssertTrue(foodSearch.waitForExistence(timeout: 3))
        foodSearch.tap()
        foodSearch.typeText("spinach")
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        }
        let spinach = app.buttons["solid-food.option.spinach"]
        XCTAssertTrue(spinach.waitForExistence(timeout: 3))
        spinach.tap()
        XCTAssertEqual(spinach.value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 2))
        app.buttons["solid-food.use-selection"].tap()

        XCTAssertTrue(app.staticTexts["Spinach"].waitForExistence(timeout: 4))
        let lovedReaction = app.buttons["solid-reaction.loved"]
        for _ in 0..<3 where !lovedReaction.exists {
            app.swipeUp()
        }
        XCTAssertTrue(lovedReaction.exists)
        XCTAssertTrue(app.buttons["solid-allergen.exposure"].exists)
        XCTAssertTrue(app.buttons["solid-allergen.reaction"].exists)
    }

    func testStoreSectionsHaveVisibleAddReorderAndRemoveControls() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/reset-empty"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/seed-smoke"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://food/stores/00000000-0000-0000-0000-000000000801"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(app.navigationBars["Neighborhood Market"].waitForExistence(timeout: 8))

        XCTAssertTrue(app.buttons["Edit"].exists)
        XCTAssertTrue(app.buttons["Remove Produce"].exists)
        let newSectionName = app.textFields["store.add-section.name"]
        newSectionName.tap()
        newSectionName.typeText("Bakery")
        app.buttons["store.add-section"].tap()
        XCTAssertTrue(app.buttons["Remove Bakery"].waitForExistence(timeout: 4))

        app.buttons["Remove Produce"].tap()
        XCTAssertTrue(app.alerts["Remove Produce?"].waitForExistence(timeout: 4))
        app.alerts["Remove Produce?"].buttons["Remove Section"].tap()
        XCTAssertTrue(app.buttons["Remove Produce"].waitForNonExistence(timeout: 4))
    }

    func testShoppingListCreationCanAddAndSelectAStore() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/reset-empty"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/seed-smoke"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://food/shopping"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(waitForAnyText(["Reusable Lists", "Weekly groceries"], timeout: 8))

        app.buttons["Create shopping list"].tap()
        XCTAssertTrue(app.navigationBars["New Shopping List"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["shopping-list.add-store"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "General lists work anywhere. Add a store to organize this list using that store's aisles and sections."
            ].exists
        )

        let listName = app.textFields["shopping-list.name"]
        listName.tap()
        listName.typeText("Test Errand List")
        app.buttons["shopping-list.add-store"].tap()

        XCTAssertTrue(app.navigationBars["New Store"].waitForExistence(timeout: 4))
        let storeName = app.textFields["store.name"]
        storeName.tap()
        storeName.typeText("Test Market")
        app.buttons["store.save"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Test Market")
            ).firstMatch.waitForExistence(timeout: 4),
            "The newly created store should be selected without losing the list draft."
        )
        app.buttons["shopping-list.save"].tap()
        XCTAssertTrue(app.staticTexts["Test Errand List"].waitForExistence(timeout: 5))
    }

    func testStartingSleepOpensRunningTimerEditor() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/reset-empty"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/seed-smoke"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://quick-log/sleep"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        let nap = app.buttons["Nap"]
        XCTAssertTrue(nap.waitForExistence(timeout: 4))
        nap.tap()

        XCTAssertTrue(
            app.staticTexts["Running"].waitForExistence(timeout: 5),
            "Starting sleep should immediately show the active timer editor."
        )
        XCTAssertTrue(app.buttons["Stop"].exists)
    }

    func testStartingNonSleepTimerOpensRunningTimerEditor() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/reset-empty"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://debug/seed-smoke"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://quick-log/pumping"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        XCTAssertTrue(
            app.staticTexts["Pumping"].waitForExistence(timeout: 5),
            "Starting a non-sleep timer should immediately show its active timer editor."
        )
        XCTAssertTrue(app.staticTexts["Running"].exists)
        XCTAssertTrue(app.buttons["Stop"].exists)
    }

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
