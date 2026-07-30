import XCTest

final class UserVisibleFlowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.debidia.LittleWindows")

    func testGuidedFeedingSkillTogglesWithoutBlocking() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://care/solids")

        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
            XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 5))
        }

        launch(startURL: "littlewindows://care/solids/guided")
        XCTAssertTrue(app.navigationBars["Guided Solids"].waitForExistence(timeout: 8))

        let skillID = "solids.feeding-skill.bringsFoodToMouth"
        let feedingSkill = app.buttons[skillID]
        for _ in 0..<20 where !feedingSkill.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(feedingSkill.waitForExistence(timeout: 3))
        XCTAssertTrue(feedingSkill.isHittable)
        XCTAssertEqual(feedingSkill.value as? String, "Not completed")

        let checkStartedAt = ContinuousClock.now
        feedingSkill.tap()
        XCTAssertEqual(app.buttons[skillID].value as? String, "Completed")
        XCTAssertLessThan(
            checkStartedAt.duration(to: .now),
            .milliseconds(1_500),
            "Checking a feeding skill should update before background persistence begins."
        )

        let uncheckStartedAt = ContinuousClock.now
        app.buttons[skillID].tap()
        XCTAssertEqual(app.buttons[skillID].value as? String, "Not completed")
        XCTAssertLessThan(
            uncheckStartedAt.duration(to: .now),
            .milliseconds(1_500),
            "Unchecking a feeding skill should update before background persistence begins."
        )
    }

    func testGuidedPlanSetupKeepsTheStartDateWithItsPreview() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://care/solids")

        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
            XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 5))
        }

        launch(startURL: "littlewindows://care/solids/guided")
        XCTAssertTrue(app.navigationBars["Guided Solids"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Create your guided plan"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1. Choose the first meal date"].exists)
        XCTAssertTrue(app.datePickers["solids.guided.start-date"].exists)

        let reviewStep = app.staticTexts["2. Review the first week"]
        for _ in 0..<5 where !reviewStep.exists {
            app.swipeUp()
        }
        XCTAssertTrue(reviewStep.waitForExistence(timeout: 3))

        let buildJourney = app.buttons["solids.guided.build-journey"]
        for _ in 0..<15 where !buildJourney.exists {
            app.swipeUp()
        }
        XCTAssertTrue(buildJourney.waitForExistence(timeout: 4))
        XCTAssertEqual(buildJourney.label, "Add full journey to Planner")
        buildJourney.tap()
        XCTAssertTrue(app.buttons["Add guided journey"].waitForExistence(timeout: 4))
    }

    func testSolidsRequiresExplicitActivationAndNeverOpensForDog() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://care/solids")

        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Log solids"].exists)
        activate.tap()
        XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 5))

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/foods/avocado")
        XCTAssertTrue(app.navigationBars["Avocado"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["solids.serving-photo.mashed"].waitForExistence(timeout: 4))

        launch(startURL: "littlewindows://care/solids/guided")
        XCTAssertTrue(app.navigationBars["Guided Solids"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Create your guided plan"].exists)
        XCTAssertTrue(app.staticTexts["1. Choose the first meal date"].exists)
        XCTAssertTrue(app.staticTexts["2. Review the first week"].exists)
        let feedingSkill = app.buttons["solids.feeding-skill.bringsFoodToMouth"]
        for _ in 0..<20 where !feedingSkill.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Feeding skills"].exists)
        XCTAssertTrue(feedingSkill.waitForExistence(timeout: 3))
        XCTAssertTrue(feedingSkill.isHittable)
        XCTAssertEqual(feedingSkill.value as? String, "Not completed")
        let skillTapStartedAt = ContinuousClock.now
        feedingSkill.tap()
        XCTAssertEqual(
            app.buttons["solids.feeding-skill.bringsFoodToMouth"].value as? String,
            "Completed"
        )
        XCTAssertLessThan(
            skillTapStartedAt.duration(to: .now),
            .seconds(2),
            "A feeding-skill checkmark should not wait for persistence."
        )
        let skillUncheckStartedAt = ContinuousClock.now
        app.buttons["solids.feeding-skill.bringsFoodToMouth"].tap()
        XCTAssertEqual(
            app.buttons["solids.feeding-skill.bringsFoodToMouth"].value as? String,
            "Not completed"
        )
        XCTAssertLessThan(
            skillUncheckStartedAt.duration(to: .now),
            .seconds(2),
            "Removing a feeding-skill checkmark should not wait for persistence."
        )

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000102/food/solids")
        XCTAssertTrue(app.staticTexts["Sample Dog's little big moments"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Solids for'")).firstMatch.exists)
    }

    func testFoodDatabaseFiltersApplyAndReset() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")

        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
        }
        let database = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Food database'")).firstMatch
        XCTAssertTrue(database.waitForExistence(timeout: 5))
        database.tap()
        XCTAssertTrue(app.navigationBars["Food Database"].waitForExistence(timeout: 5))

        let filters = app.buttons["solids.foods.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 3))
        filters.tap()
        XCTAssertTrue(app.navigationBars["Food Filters"].waitForExistence(timeout: 4))

        let fruit = app.buttons["solids.foods.filter.type.fruit"]
        XCTAssertTrue(fruit.waitForExistence(timeout: 4))
        fruit.tap()
        let apply = app.buttons["solids.foods.filter.apply"]
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Show '")).firstMatch.exists)
        apply.tap()

        XCTAssertTrue(app.navigationBars["Food Database"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["1 active filter"].waitForExistence(timeout: 3))

        filters.tap()
        XCTAssertTrue(app.navigationBars["Food Filters"].waitForExistence(timeout: 4))
        app.buttons["Reset"].tap()
        app.buttons["solids.foods.filter.apply"].tap()
        XCTAssertFalse(app.staticTexts["1 active filter"].exists)
    }

    func testPreparationWalkthroughUsesAnInteractiveChecklist() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")

        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
        }

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/foods/acai")
        XCTAssertTrue(app.navigationBars["Açaí"].waitForExistence(timeout: 8))

        let openWalkthrough = app.buttons["solids.preparation.open"]
        for _ in 0..<10 where !openWalkthrough.exists {
            app.swipeUp()
        }
        XCTAssertTrue(openWalkthrough.waitForExistence(timeout: 4))
        openWalkthrough.tap()

        XCTAssertTrue(app.navigationBars["Prepare Açaí"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["solids.preparation.walkthrough"].exists)
        XCTAssertTrue(app.staticTexts["Preparation checklist"].exists)
        XCTAssertTrue(app.staticTexts["Step 1 of 6"].exists)
        XCTAssertTrue(app.staticTexts["0 of 6 done"].exists)

        let complete = app.buttons["solids.preparation.complete"]
        XCTAssertTrue(complete.exists)
        complete.tap()

        XCTAssertTrue(app.staticTexts["Step 2 of 6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 of 6 done"].exists)

        app.buttons["solids.preparation.step.3"].tap()
        XCTAssertTrue(app.staticTexts["Step 4 of 6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Target: Preloaded spoon"].exists)
    }

    func testTodaySolidsReadinessBackReturnsToToday() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today")

        let readiness = app.buttons["today.solids-readiness"]
        XCTAssertTrue(readiness.waitForExistence(timeout: 8))
        readiness.tap()
        XCTAssertTrue(app.staticTexts["Solids for Sample Child"].waitForExistence(timeout: 5))

        let backToToday = app.navigationBars.buttons["Today"]
        XCTAssertTrue(backToToday.waitForExistence(timeout: 4))
        backToToday.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        XCTAssertTrue(readiness.waitForExistence(timeout: 4))
        XCTAssertEqual(app.tabBars.buttons["Today"].isSelected, true)
    }

    func testTodayFullSolidsShortcutReturnsToToday() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")

        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today")
        let guided = app.buttons["today.solids.guided"]
        XCTAssertTrue(guided.waitForExistence(timeout: 8))
        guided.tap()

        XCTAssertTrue(app.navigationBars["Guided Solids"].waitForExistence(timeout: 8))
        let back = app.buttons["solids.return-to-origin"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        XCTAssertEqual(back.label, "Today")
        back.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.tabBars.buttons["Today"].isSelected, true)
    }

    func testCarePlacesFeedingBeforeMemoryContent() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://care")

        let feeding = app.buttons["care.solids"]
        let memoryHeading = app.staticTexts["Sample Child's little big moments"]
        XCTAssertTrue(feeding.waitForExistence(timeout: 8))
        XCTAssertTrue(memoryHeading.waitForExistence(timeout: 4))
        XCTAssertLessThan(feeding.frame.minY, memoryHeading.frame.minY)

        feeding.tap()
        XCTAssertTrue(app.staticTexts["Solids for Sample Child"].waitForExistence(timeout: 5))

        let backToCare = app.navigationBars.buttons["Care"]
        XCTAssertTrue(backToCare.waitForExistence(timeout: 4))
        backToCare.tap()

        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 4))
        XCTAssertTrue(feeding.waitForExistence(timeout: 4))
        XCTAssertEqual(app.tabBars.buttons["Care"].isSelected, true)
    }

    func testHomeAreasStayBelowNavigationBarWhenPulledDown() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://food")

        let homeAreas = app.staticTexts["home.areas.title"]
        let navigationBar = app.navigationBars["Home"]
        XCTAssertTrue(homeAreas.waitForExistence(timeout: 8))
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 4))

        let initialY = homeAreas.frame.minY
        app.swipeDown()

        XCTAssertGreaterThanOrEqual(homeAreas.frame.minY, navigationBar.frame.maxY - 1)
        XCTAssertEqual(homeAreas.frame.minY, initialY, accuracy: 1)
    }

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

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()
        XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 5))

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/quick-log/feed")
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
        let selectionStartedAt = ContinuousClock.now
        spinach.tap()
        XCTAssertEqual(spinach.value as? String, "Selected")
        XCTAssertLessThan(
            selectionStartedAt.duration(to: .now),
            .milliseconds(1_250),
            "Selecting a food should not rebuild the full bundled catalog."
        )
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 2))
        app.buttons["solid-food.use-selection"].tap()

        XCTAssertTrue(app.staticTexts["Spinach"].waitForExistence(timeout: 4))
        app.buttons["Spinach"].tap()
        XCTAssertTrue(app.navigationBars["Spinach"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["solid-reaction.preference"].exists)
        XCTAssertTrue(app.buttons["solid-allergen.egg"].exists)
        let reactionToggle = app.switches["solid-reaction.observed"]
        for _ in 0..<6 where !reactionToggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(reactionToggle.exists)
    }

    func testFoodDatabaseNotesPersistAfterUninterruptedTyping() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        let spinachURL = "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/foods/spinach"
        launch(startURL: spinachURL)
        XCTAssertTrue(app.navigationBars["Spinach"].waitForExistence(timeout: 8))

        let notes = app.textFields["solids.food.notes"]
        for _ in 0..<12 where !notes.exists {
            app.swipeUp()
        }
        XCTAssertTrue(notes.waitForExistence(timeout: 4))
        let focusStartedAt = Date()
        notes.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.exists,
            "The ingredient notes field should accept focus without waiting for persistence setup."
        )
        XCTAssertLessThan(
            Date().timeIntervalSince(focusStartedAt),
            1.25,
            "Opening the keyboard for ingredient notes took too long."
        )
        let noteText = "Steam until soft and mix into oatmeal."
        notes.typeText(noteText)
        XCTAssertEqual(notes.value as? String, noteText)

        app.navigationBars["Spinach"].buttons.firstMatch.tap()
        launch(startURL: spinachURL)
        XCTAssertTrue(app.navigationBars["Spinach"].waitForExistence(timeout: 8))

        let reopenedNotes = app.textFields["solids.food.notes"]
        for _ in 0..<12 where !reopenedNotes.exists {
            app.swipeUp()
        }
        XCTAssertTrue(reopenedNotes.waitForExistence(timeout: 4))
        XCTAssertEqual(reopenedNotes.value as? String, noteText)
    }

    func testNewSolidsPlanSavesAndClosesPromptly() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/plan")
        XCTAssertTrue(app.navigationBars["Plan Meals"].waitForExistence(timeout: 8))
        let add = app.buttons["solids.plan.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 4))
        add.tap()

        let editor = app.navigationBars["New Solids Plan"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        let search = app.searchFields["Find foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        search.tap()
        search.typeText("avocado")
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        }
        let avocado = app.buttons["solids.plan.food.avocado"]
        XCTAssertTrue(avocado.waitForExistence(timeout: 4))
        avocado.tap()
        let closeSearch = app.buttons["close"]
        if closeSearch.waitForExistence(timeout: 2) {
            closeSearch.tap()
        }

        let save = app.buttons["solids.plan.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        XCTAssertTrue(save.isEnabled)
        let saveStartedAt = Date()
        save.tap()
        let saveInteractionDuration = Date().timeIntervalSince(saveStartedAt)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        XCTAssertLessThan(
            saveInteractionDuration,
            2,
            "Saving a new solids plan should dismiss the editor promptly after the local save."
        )
        XCTAssertTrue(app.staticTexts["Avocado"].waitForExistence(timeout: 4))
    }

    func testSolidsCrossTabLinksReturnToTheOriginatingReport() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        let feedingReport = app.buttons["solids.view-feeding-report"]
        for _ in 0..<10 where !feedingReport.exists {
            app.swipeUp()
        }
        XCTAssertTrue(feedingReport.waitForExistence(timeout: 4))
        feedingReport.tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 8))

        openFeedingReportDetail("reports.feeding.allergens", destinationTitle: "Allergens")
        returnFromSolidsToReports()

        openFeedingReportDetail("reports.feeding.solids-tracker", destinationTitle: "Food Tracker")
        returnFromSolidsToReports()
    }

    private func openFeedingReportDetail(_ identifier: String, destinationTitle: String) {
        let detail = app.buttons[identifier]
        for _ in 0..<12 where !detail.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            detail.waitForExistence(timeout: 4),
            "The Feeding report should restore before opening \(destinationTitle)."
        )
        detail.tap()
        XCTAssertTrue(app.navigationBars[destinationTitle].waitForExistence(timeout: 8))
    }

    private func returnFromSolidsToReports() {
        let back = app.buttons["solids.return-to-origin"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 8))
    }

    func testSolidsRecipesShowFirstStageIdeasAfterEarlyActivation() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        launch(
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/recipes"
        )
        XCTAssertTrue(app.navigationBars["Solids Recipes"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["solids.recipes.planning-ahead"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Avocado bean mash"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["0 meal ideas"].exists)
    }

    func testSolidsMultiOptionActionsUseAppDrawers() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
        }

        launch(
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/recipes/avocado-bean-mash"
        )
        XCTAssertTrue(app.navigationBars["Avocado bean mash"].waitForExistence(timeout: 8))

        let swap = app.buttons["solids.recipe.swap.0"]
        XCTAssertTrue(swap.waitForExistence(timeout: 4))
        swap.tap()
        XCTAssertTrue(app.staticTexts["Swap Avocado"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Avocado"].exists)
        app.buttons["Cancel"].tap()

        let addMissing = app.buttons["solids.recipe.add-missing-ingredients"]
        for _ in 0..<12 where !addMissing.exists {
            app.swipeUp()
        }
        XCTAssertTrue(addMissing.waitForExistence(timeout: 4))
        addMissing.tap()
        XCTAssertTrue(app.staticTexts["Add missing ingredients"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Weekly groceries"].exists)
        app.buttons["Cancel"].tap()

        launch(
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/guided"
        )
        XCTAssertTrue(app.navigationBars["Guided Solids"].waitForExistence(timeout: 8))
        let buildJourney = app.buttons["solids.guided.build-journey"]
        for _ in 0..<20 where !buildJourney.exists {
            app.swipeUp()
        }
        XCTAssertTrue(buildJourney.waitForExistence(timeout: 4))
        buildJourney.tap()
        XCTAssertTrue(app.buttons["Add guided journey"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Add '")).firstMatch.exists
        )
    }

    func testFeedingInsightsKeepMilkSolidsAndCombinedPatternsSeparate() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        launch(startURL: "littlewindows://reports/feeding")
        let modeControl = app.segmentedControls["insights.feeding.mode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 8))

        XCTAssertTrue(
            app.descendants(matching: .any)["insights.feeding.bottle"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Bottle ounces"].exists)
        XCTAssertFalse(app.staticTexts["Solid meals"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["insights.feeding.patterns"].exists)

        modeControl.buttons["Solids"].tap()
        XCTAssertTrue(app.staticTexts["Solid meals"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Bottle ounces"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["insights.feeding.patterns"].exists)

        modeControl.buttons["Patterns"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["insights.feeding.patterns"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["All feeding sessions / day"].exists)
        XCTAssertFalse(app.staticTexts["Bottle ounces"].exists)
        XCTAssertFalse(app.staticTexts["Solid meals"].exists)
    }

    func testDiaperEditorOffersOptionalRashDetail() {
        continueAfterFailure = false

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://quick-log/diaper"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Add Event"].waitForExistence(timeout: 8))
        let rashToggle = app.switches["diaper-rash-toggle"]
        XCTAssertTrue(rashToggle.waitForExistence(timeout: 4))
        XCTAssertEqual(rashToggle.value as? String, "0")
        rashToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1'"),
            object: rashToggle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 2), .completed)
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
            expectedText: ["Care", "Rolled from tummy to back"]
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

    func testTripPackingCreationAddItemAndPackFlow() {
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
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://food/trips"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 8)
        )
        let newTrip = app.buttons["trips.new"]
        XCTAssertTrue(newTrip.waitForExistence(timeout: 4))
        newTrip.tap()

        XCTAssertTrue(app.navigationBars["New Trip"].waitForExistence(timeout: 4))
        let tripName = app.textFields["trip.create.name"]
        XCTAssertTrue(tripName.exists)
        tripName.tap()
        tripName.typeText("Automation Trip")
        addOfflineTripDestination(named: "Test City One", index: 1)
        addOfflineTripDestination(named: "Test City Two", index: 2)
        app.buttons["trip.create.save"].tap()

        XCTAssertTrue(app.navigationBars["Automation Trip"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["trip.detail"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Test City One")
            ).firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Test City Two")
            ).firstMatch.waitForExistence(timeout: 3)
        )

        app.buttons["trip.actions"].tap()
        app.buttons["Manage Bags"].tap()
        XCTAssertTrue(app.navigationBars["Bags"].waitForExistence(timeout: 4))

        let newBagName = app.textFields["trip.bag.new.name"]
        let addBag = app.buttons["trip.bag.add"]
        XCTAssertTrue(newBagName.waitForExistence(timeout: 3))
        XCTAssertTrue(addBag.exists)
        XCTAssertFalse(addBag.isEnabled)

        newBagName.tap()
        newBagName.typeText("Carry-on")
        XCTAssertTrue(addBag.isEnabled)
        addBag.tap()

        let bagConfirmation = app.descendants(matching: .any)["trip.bag.added"]
        XCTAssertTrue(bagConfirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(bagConfirmation.label.contains("Carry-on added"))
        XCTAssertFalse(addBag.isEnabled, "Adding a bag should reset the form for the next one.")

        newBagName.typeText("Checked bag")
        XCTAssertTrue(addBag.isEnabled)
        addBag.tap()
        XCTAssertTrue(bagConfirmation.label.contains("Checked bag added"))
        XCTAssertFalse(addBag.isEnabled)
        XCTAssertFalse(app.buttons["Save Changes"].exists)
        app.navigationBars["Bags"].buttons["Done"].tap()

        app.buttons["trip.actions"].tap()
        app.buttons["Manage Bags"].tap()
        XCTAssertTrue(app.navigationBars["Bags"].waitForExistence(timeout: 4))

        let existingBagName = app.textFields.matching(
            identifier: "trip.bag.existing.name"
        ).element(boundBy: 1)
        for _ in 0..<4 where !existingBagName.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(existingBagName.waitForExistence(timeout: 3))
        XCTAssertTrue(existingBagName.isHittable)
        let originalBagName = existingBagName.value as? String ?? "Carry-on"
        existingBagName.tap()
        existingBagName.typeText(" Updated")
        let renamedBagName = (existingBagName.value as? String ?? "Updated Carry-on")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(renamedBagName, originalBagName)
        app.navigationBars["Bags"].buttons["Done"].tap()

        app.buttons["trip.actions"].tap()
        app.buttons["Manage Bags"].tap()
        XCTAssertTrue(app.navigationBars["Bags"].waitForExistence(timeout: 4))
        let reopenedBagName = app.textFields.matching(
            identifier: "trip.bag.existing.name"
        ).element(boundBy: 1)
        for _ in 0..<4 where !reopenedBagName.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(
            reopenedBagName.waitForExistence(timeout: 4),
            "Bag name changes should persist without a separate save action."
        )
        XCTAssertEqual(reopenedBagName.value as? String, renamedBagName)
        app.navigationBars["Bags"].buttons["Done"].tap()

        let addPackingItem = app.buttons["trip.item.add"]
        XCTAssertTrue(addPackingItem.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(addPackingItem.frame.width, 44)
        XCTAssertGreaterThanOrEqual(addPackingItem.frame.height, 36)
        let tripActions = app.buttons["trip.actions"]
        XCTAssertTrue(tripActions.exists)
        XCTAssertLessThanOrEqual(
            addPackingItem.frame.maxX,
            tripActions.frame.minX,
            "The add and actions buttons should remain adjacent in the trailing toolbar."
        )
        XCTAssertLessThanOrEqual(
            tripActions.frame.minX - addPackingItem.frame.maxX,
            4,
            "The add and actions buttons should use compact spacing."
        )
        let reorderPackingItems = app.buttons["trip.items.reorder-mode"]
        if reorderPackingItems.exists {
            XCTAssertEqual(reorderPackingItems.label, "Reorder")
            XCTAssertLessThanOrEqual(
                reorderPackingItems.frame.maxX,
                addPackingItem.frame.minX,
                "Reorder should sit before the adjacent add and actions buttons."
            )
            XCTAssertLessThanOrEqual(
                addPackingItem.frame.minX - reorderPackingItems.frame.maxX,
                4,
                "Reorder and add should use compact spacing."
            )
            reorderPackingItems.tap()
            XCTAssertEqual(reorderPackingItems.label, "Done")
            reorderPackingItems.tap()
            XCTAssertEqual(reorderPackingItems.label, "Reorder")
        }
        addPackingItem.tap()

        XCTAssertTrue(app.navigationBars["Add Packing Item"].waitForExistence(timeout: 4))
        let itemName = app.textFields["trip.item.name"]
        itemName.tap()
        itemName.typeText("Automation Item")
        let responsibilityChoice = app.buttons["trip.item.caregiver-choice"]
        for _ in 0..<3 where !responsibilityChoice.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(responsibilityChoice.waitForExistence(timeout: 3))
        responsibilityChoice.tap()
        let enterNewName = app.buttons["Enter a new name"]
        XCTAssertTrue(enterNewName.waitForExistence(timeout: 3))
        enterNewName.tap()

        let responsiblePersonName = app.textFields["trip.item.caregiver"]
        XCTAssertTrue(responsiblePersonName.waitForExistence(timeout: 3))
        responsiblePersonName.tap()
        responsiblePersonName.typeText("Sample Person")
        app.buttons["trip.item.save"].tap()

        let createdItem = app.staticTexts["Automation Item"]
        for _ in 0..<4 {
            if createdItem.exists { break }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(createdItem.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Assigned to Sample Person"].exists)
        let itemToggle = app.buttons.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".toggle")
        ).firstMatch
        XCTAssertTrue(itemToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(itemToggle.label, "Mark packed")
        let packedToggleIdentifier = itemToggle.identifier
        itemToggle.tap()
        XCTAssertTrue(
            app.buttons[packedToggleIdentifier].waitForNonExistence(timeout: 3),
            "Packed items should leave the default Remaining filter."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "trip-packing-detail"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["trip.actions"].tap()
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.detail"].waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Automation Trip Copy"].waitForExistence(timeout: 5))

        let originalTrip = app.staticTexts["Automation Trip"]
        XCTAssertTrue(originalTrip.waitForExistence(timeout: 3))
        originalTrip.tap()
        XCTAssertTrue(app.navigationBars["Automation Trip"].waitForExistence(timeout: 5))

        app.buttons["trip.actions"].tap()
        let deleteTrip = app.buttons["trip.delete"]
        XCTAssertTrue(deleteTrip.waitForExistence(timeout: 3))
        deleteTrip.tap()

        let confirmDeleteTrip = app.buttons["Delete Trip"]
        XCTAssertTrue(confirmDeleteTrip.waitForExistence(timeout: 3))
        confirmDeleteTrip.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["trip.detail"].waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Automation Trip"].exists)
        let copiedTrip = app.staticTexts["Automation Trip Copy"]
        XCTAssertTrue(copiedTrip.waitForExistence(timeout: 3))
        copiedTrip.tap()
        XCTAssertTrue(app.navigationBars["Automation Trip Copy"].waitForExistence(timeout: 5))

        app.buttons["trip.actions"].tap()
        let archiveTrip = app.buttons["Archive"]
        XCTAssertTrue(archiveTrip.waitForExistence(timeout: 3))
        archiveTrip.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["trip.detail"].waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 3))
        let archivedTrip = app.staticTexts["Automation Trip Copy"]
        XCTAssertTrue(archivedTrip.exists)
        archivedTrip.tap()

        XCTAssertTrue(app.navigationBars["Automation Trip Copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.archived.read-only"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["trip.item.add"].exists)
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".toggle")).count,
            0,
            "Archived packing items should not expose pack or unpack controls."
        )

        app.buttons["trip.actions"].tap()
        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Duplicate"].exists)
        XCTAssertTrue(app.buttons["trip.delete"].exists)
        XCTAssertFalse(app.buttons["Edit Trip"].exists)
        XCTAssertFalse(app.buttons["Manage Travelers"].exists)
        XCTAssertFalse(app.buttons["Manage Bags"].exists)
        XCTAssertFalse(app.buttons["Mark Complete"].exists)
        XCTAssertFalse(app.buttons["Reopen Trip"].exists)
    }

    func testEditPackingItemScrollKeepsDraftResponsive() {
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
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://food/trips"
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 8))
        app.buttons["trips.new"].tap()

        let tripName = app.textFields["trip.create.name"]
        XCTAssertTrue(tripName.waitForExistence(timeout: 4))
        tripName.tap()
        tripName.typeText("Editor Scroll Trip")
        addOfflineTripDestination(named: "Test Destination", index: 1)
        app.buttons["trip.create.save"].tap()
        XCTAssertTrue(app.navigationBars["Editor Scroll Trip"].waitForExistence(timeout: 6))

        let starterItem = app.staticTexts["Identification and travel documents"]
        XCTAssertTrue(starterItem.waitForExistence(timeout: 5))
        starterItem.tap()
        XCTAssertTrue(app.navigationBars["Edit Packing Item"].waitForExistence(timeout: 4))
        let itemEditor = app.descendants(matching: .any)["trip.item.editor"]
        XCTAssertTrue(itemEditor.waitForExistence(timeout: 3))

        itemEditor.swipeUp()
        let notesField = app.descendants(matching: .any)["trip.item.notes"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 3))
        notesField.tap()
        notesField.typeText(
            "Keep this long packing note together and make sure it wraps inside the form instead of extending beyond the right edge of the screen."
        )
        XCTAssertLessThanOrEqual(notesField.frame.maxX, itemEditor.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(notesField.frame.minX, itemEditor.frame.minX - 1)
        XCTAssertGreaterThan(notesField.frame.height, 36)

        let responsibilityChoice = app.buttons["trip.item.caregiver-choice"]
        for _ in 0..<3 where !responsibilityChoice.isHittable {
            itemEditor.swipeUp()
        }
        XCTAssertTrue(responsibilityChoice.waitForExistence(timeout: 3))
        responsibilityChoice.tap()
        let enterNewName = app.buttons["Enter a new name"]
        XCTAssertTrue(enterNewName.waitForExistence(timeout: 3))
        enterNewName.tap()

        let personNameField = app.textFields["trip.item.caregiver"]
        XCTAssertTrue(personNameField.waitForExistence(timeout: 3))
        personNameField.tap()
        personNameField.typeText("Test Person")
        itemEditor.swipeDown()
        itemEditor.swipeUp()
        itemEditor.swipeDown()
        itemEditor.swipeUp()

        XCTAssertTrue(app.buttons["trip.item.save"].isEnabled)
        XCTAssertTrue(personNameField.waitForExistence(timeout: 3))
        XCTAssertEqual(personNameField.value as? String, "Test Person")
    }

    func testBackgroundForegroundKeepsOpenHomeDetailButColdLaunchStartsToday() {
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
        XCTAssertTrue(waitForAnyText(["Today", "Sample Child"], timeout: 8))

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://food/shopping/00000000-0000-0000-0000-000000000501"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Weekly groceries"].waitForExistence(timeout: 8))

        XCUIDevice.shared.press(.home)
        let backgroundDeadline = Date().addingTimeInterval(4)
        while app.state == .runningForeground, Date() < backgroundDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertNotEqual(app.state, .runningForeground)

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(
            app.navigationBars["Weekly groceries"].waitForExistence(timeout: 4),
            "Foregrounding should return to the open Home detail instead of resetting to Today."
        )
        XCTAssertFalse(app.staticTexts["Little Windows is loading"].exists)

        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertFalse(
            app.navigationBars["Weekly groceries"].exists,
            "A fresh process should start on Today instead of restoring the previous screen."
        )
    }

    private func addOfflineTripDestination(named name: String, index: Int) {
        let returnKey = app.keyboards.buttons["return"]
        if returnKey.exists {
            returnKey.tap()
        }
        let addDestination = app.buttons["trip.destination.add"]
        for _ in 0..<4 {
            if addDestination.exists, addDestination.isHittable { break }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(addDestination.waitForExistence(timeout: 3))
        XCTAssertTrue(addDestination.isHittable)
        addDestination.tap()

        let destinationLink = app.buttons["trip.destination.select.\(index)"]
        XCTAssertTrue(destinationLink.waitForExistence(timeout: 3))
        destinationLink.tap()

        XCTAssertTrue(app.navigationBars["Destination"].waitForExistence(timeout: 3))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText(name)

        let offlineChoice = app.buttons["trip.destination.offline"]
        XCTAssertTrue(offlineChoice.waitForExistence(timeout: 4))
        for _ in 0..<3 {
            if offlineChoice.isHittable { break }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(offlineChoice.isHittable)
        offlineChoice.tap()
        XCTAssertTrue(
            app.navigationBars["New Trip"].waitForExistence(timeout: 5),
            "Expected to return to trip creation after choosing \(name); app state \(app.state.rawValue).\n\(app.debugDescription)"
        )
    }

    private func launch(startURL: String) {
        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": startURL
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
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
