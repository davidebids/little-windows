import XCTest

final class UserVisibleFlowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.debidia.LittleWindows")

    func testProfileAvatarFitsToolbarOnInitialLoad() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today")

        let profileSettings = app.buttons["Sample Child settings"]
        XCTAssertTrue(profileSettings.waitForExistence(timeout: 8))
        XCTAssertTrue(profileSettings.isHittable)
        XCTAssertEqual(profileSettings.frame.width, 36, accuracy: 1)
        XCTAssertEqual(
            profileSettings.frame.width,
            profileSettings.frame.height,
            accuracy: 1
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Profile avatar on initial Today load"
        attachment.lifetime = .keepAlways
        add(attachment)

        profileSettings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testDogTodayShowsAllEnabledCareCategories() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000102/today")

        for identifier in [
            "dog-quick-action-treat",
            "dog-quick-action-grooming",
            "dog-quick-action-vaccine",
            "dog-quick-action-custom"
        ] {
            let button = app.buttons[identifier]
            for _ in 0..<12 where !button.isHittable {
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(button.exists, "Expected enabled dog action \(identifier) to appear on Today.")
            XCTAssertTrue(button.isHittable, "Expected enabled dog action \(identifier) to be reachable.")
        }
    }

    func testPuppyStageGuideOpenedFromTodayHasCloseControl() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://puppy-guide")

        XCTAssertTrue(app.navigationBars["6 Months"].waitForExistence(timeout: 8))
        let closeButton = app.buttons["puppy-stage-guide.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 4))
        closeButton.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Puppy Stage Guide"].exists)
    }

    func testPuppyStageGuideCardActionsAreAligned() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000102/today")

        let readButton = app.buttons["puppy-stage-guide.read"]
        for _ in 0..<12 where !readButton.isHittable {
            app.swipeUp(velocity: .slow)
        }

        let addMilestoneButton = app.buttons["puppy-stage-guide.add-milestone"]
        let logTrainingButton = app.buttons["puppy-stage-guide.log-training"]
        XCTAssertTrue(readButton.isHittable)
        XCTAssertTrue(addMilestoneButton.isHittable)
        XCTAssertTrue(logTrainingButton.isHittable)

        for button in [addMilestoneButton, logTrainingButton] {
            XCTAssertEqual(button.frame.minY, readButton.frame.minY, accuracy: 2)
            XCTAssertEqual(button.frame.height, readButton.frame.height, accuracy: 2)
            XCTAssertEqual(button.frame.width, readButton.frame.width, accuracy: 2)
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Aligned puppy stage guide actions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMedicationEditorKeepsLabelsVisibleForPopulatedValues() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://medications")

        XCTAssertTrue(app.navigationBars["Medications"].waitForExistence(timeout: 8))
        let addMedication = app.buttons["Add Medication"]
        XCTAssertTrue(addMedication.waitForExistence(timeout: 4))
        addMedication.tap()

        XCTAssertTrue(app.navigationBars["Add Medication"].waitForExistence(timeout: 4))
        for label in ["Name", "Strength", "Strength unit", "Instructions", "Dose", "Dose unit"] {
            XCTAssertTrue(
                app.staticTexts[label].exists,
                "The \(label) label should remain visible independently of its input value."
            )
        }

        let formPicker = app.buttons["medication.form"]
        let doseUnitPicker = app.buttons["medication.dose-unit"]
        XCTAssertTrue(formPicker.exists)
        XCTAssertTrue(doseUnitPicker.exists)

        formPicker.tap()
        XCTAssertTrue(app.buttons["Liquid"].waitForExistence(timeout: 3))
        app.buttons["Liquid"].tap()
        XCTAssertTrue(doseUnitPicker.label.contains("Milliliter (mL)"))

        doseUnitPicker.tap()
        XCTAssertTrue(app.buttons["Milligram (mg)"].waitForExistence(timeout: 3))
        app.buttons["Milligram (mg)"].tap()
        XCTAssertTrue(doseUnitPicker.label.contains("Milligram (mg)"))

        assertPersistentMultilineField(
            identifier: "medication.instructions",
            maxScrolls: 2
        )

        let supplyToggle = app.switches["Track quantity on hand"]
        for _ in 0..<5 where !supplyToggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(supplyToggle.waitForExistence(timeout: 3))
        supplyToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let supplyEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1'"),
            object: supplyToggle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [supplyEnabled], timeout: 3), .completed)

        let quantityLabel = app.staticTexts["Quantity on hand"]
        for _ in 0..<3 where !quantityLabel.exists {
            app.swipeUp()
        }
        XCTAssertTrue(quantityLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Refill alert at"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Medication editor persistent labels"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMedicationInstructionsFocusAndTypingIsResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://medications")

        XCTAssertTrue(app.navigationBars["Medications"].waitForExistence(timeout: 8))
        app.buttons["Add Medication"].tap()
        XCTAssertTrue(app.navigationBars["Add Medication"].waitForExistence(timeout: 4))

        let instructions = app.descendants(matching: .any)
            .matching(identifier: "medication.instructions")
            .firstMatch
        XCTAssertTrue(instructions.waitForExistence(timeout: 4))

        let focusStartedAt = Date()
        instructions.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let focusDuration = Date().timeIntervalSince(focusStartedAt)

        let typingStartedAt = Date()
        instructions.typeText("Take with food")
        let typingDuration = Date().timeIntervalSince(typingStartedAt)

        XCTAssertEqual(instructions.value as? String, "Take with food")
        XCTAssertLessThan(focusDuration, 2.5, "Instructions focus took \(focusDuration)s")
        XCTAssertLessThan(typingDuration, 2.5, "Instructions typing took \(typingDuration)s")
    }

    func testHouseholdOnlySetupAndCareDeepLinkPrompt() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")

        let nameField = app.textFields["firstRun.caregiverName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        XCTAssertEqual(nameField.value as? String, "Enter name here")
        nameField.tap()
        nameField.typeText("Test Caregiver")

        let householdChoice = app.buttons["firstRun.householdOnly"]
        XCTAssertTrue(householdChoice.waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts[
                "Add a care profile now for daily tracking and a personalized Care workspace."
            ].exists
        )
        householdChoice.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Welcome, Test Caregiver"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Night Light"].exists)
        XCTAssertFalse(app.tabBars.buttons["Reports"].exists)
        XCTAssertFalse(app.tabBars.buttons["Care"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Care"].exists)

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 4))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.open(URL(string: "littlewindows://settings/family-sync")!)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.navigationBars["Family Sync"].waitForExistence(timeout: 5))
        let householdSharingDescription = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Home, Food, trips, returns, reminders, and other household data"
            )
        ).firstMatch
        XCTAssertTrue(
            householdSharingDescription.waitForExistence(timeout: 5)
        )
        app.navigationBars["Family Sync"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let profilesLink = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Care Profiles")
        ).firstMatch
        XCTAssertTrue(profilesLink.waitForExistence(timeout: 4))
        profilesLink.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No care profiles yet"].exists)
        let emptyProfilesDescription = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                "Add a child, adult, or dog whenever you want to start care tracking. Your Home, Food, and Night Light setup will stay exactly as it is."
            )
        ).firstMatch
        XCTAssertTrue(
            emptyProfilesDescription.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["profiles.empty.add"].exists)
        let emptyProfilesAttachment = XCTAttachment(screenshot: app.screenshot())
        emptyProfilesAttachment.name = "Household-only empty profiles"
        emptyProfilesAttachment.lifetime = .keepAlways
        add(emptyProfilesAttachment)

        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.staticTexts["Add a care profile"].waitForExistence(timeout: 8))
        let addProfile = app.buttons["profile-required.add-profile"]
        XCTAssertTrue(addProfile.exists)
        XCTAssertTrue(app.staticTexts["Care logging"].exists)

        app.open(URL(string: "littlewindows://reports/summary")!)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(addProfile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Care reports"].waitForExistence(timeout: 5))

        // A newer household link must dismiss both an already-visible prompt
        // and any delayed prompt that has not presented yet.
        app.open(URL(string: "littlewindows://food")!)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(addProfile.waitForNonExistence(timeout: 5))

        app.open(URL(string: "littlewindows://quick-log/sleep")!)
        app.open(URL(string: "littlewindows://night-light")!)
        XCTAssertTrue(app.navigationBars["Night Light"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertFalse(addProfile.exists)

        // Care navigation arriving over Settings must dismiss Settings first so
        // SwiftUI has a single sheet presenter for the profile requirement.
        app.open(URL(string: "littlewindows://settings")!)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.open(URL(string: "littlewindows://reports/summary")!)
        XCTAssertTrue(addProfile.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Care reports"].exists)

        addProfile.tap()
        XCTAssertTrue(app.navigationBars["Add Profile"].waitForExistence(timeout: 5))
        let childName = app.textFields["Child name"]
        XCTAssertTrue(childName.waitForExistence(timeout: 3))
        childName.tap()
        childName.typeText("Test Child")
        app.navigationBars["Add Profile"].buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Reports"].exists)
        XCTAssertTrue(app.tabBars.buttons["Care"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Care"].isSelected)

        // The inverse transition should be just as complete: archiving the last
        // profile preserves it in Settings and immediately restores Home mode.
        app.open(URL(string: "littlewindows://settings")!)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let careProfiles = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Care Profiles")
        ).firstMatch
        XCTAssertTrue(careProfiles.waitForExistence(timeout: 4))
        careProfiles.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        let profileRow = app.buttons.containing(
            .staticText,
            identifier: "Test Child"
        ).firstMatch
        XCTAssertTrue(profileRow.waitForExistence(timeout: 4))
        profileRow.swipeLeft()
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 3))
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.buttons["Archive and Switch to Home"].waitForExistence(timeout: 3))
        app.buttons["Archive and Switch to Home"].tap()
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5))

        app.open(URL(string: "littlewindows://today")!)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertFalse(app.tabBars.buttons["Reports"].exists)
        XCTAssertFalse(app.tabBars.buttons["Care"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Care"].exists)
    }

    func testArchivingRemainingProfileAfterOtherArchivesExplainsHomeMode() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://settings")

        let careProfiles = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Care Profiles")
        ).firstMatch
        XCTAssertTrue(careProfiles.waitForExistence(timeout: 5))
        careProfiles.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))

        let deletableRow = app.buttons.containing(
            .staticText,
            identifier: "Sample Dog"
        ).firstMatch
        XCTAssertTrue(deletableRow.waitForExistence(timeout: 4))
        deletableRow.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete Profile"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Remove this profile and its history."].exists)
        app.buttons["Cancel"].tap()

        func archiveProfile(named name: String) {
            let row = app.buttons.containing(.staticText, identifier: name).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 4))
            row.swipeLeft()
            let archiveButton = app.buttons["Archive"]
            XCTAssertTrue(archiveButton.waitForExistence(timeout: 3))
            archiveButton.tap()
            XCTAssertTrue(app.buttons["Archive Profile"].waitForExistence(timeout: 3))
            app.buttons["Archive Profile"].tap()
        }

        archiveProfile(named: "Sample Child")

        let finalRow = app.buttons.containing(
            .staticText,
            identifier: "Sample Dog"
        ).firstMatch
        XCTAssertTrue(finalRow.waitForExistence(timeout: 4))
        finalRow.swipeLeft()
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 3))
        app.buttons["Archive"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "This is the last active care profile."
                )
            ).firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["Archive and Switch to Home"].exists)
        app.buttons["Archive and Switch to Home"].tap()

        app.open(URL(string: "littlewindows://today")!)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertFalse(app.tabBars.buttons["Reports"].exists)
        XCTAssertFalse(app.tabBars.buttons["Care"].exists)
    }

    func testFirstRunOffersRestoreFromICloud() {
        continueAfterFailure = false

        launch(
            startURL: "littlewindows://debug/reset-empty",
            additionalEnvironment: [
                "LITTLE_WINDOWS_UI_TEST_ICLOUD_RESTORE_WAITING": "1"
            ]
        )

        let restoreButton = app.buttons["firstRun.restoreFromICloud"]
        XCTAssertTrue(
            restoreButton.waitForExistence(timeout: 4),
            "A returning user should be able to restore Private iCloud Sync data from onboarding."
        )
        XCTAssertTrue(
            app.staticTexts["Already use Little Windows?"].exists
        )

        restoreButton.tap()
        XCTAssertTrue(
            app.otherElements["firstRun.iCloudRestoreProgress"]
                .waitForExistence(timeout: 2),
            "iCloud restore should show progress while synced data is arriving."
        )
        XCTAssertTrue(app.staticTexts["Restoring from iCloud…"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testProductionScaleStoreKeepsPrimaryNavigationResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 25))

        // Exercise the TestFlight-shaped path as well: a completely fresh
        // process opening an already-large, CloudKit-compatible store.
        app.terminate()
        app.launchEnvironment = ["LITTLE_WINDOWS_UI_TESTING": "1"]
        let coldLaunchStartedAt = ContinuousClock.now
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertLessThan(
            coldLaunchStartedAt.duration(to: .now),
            .seconds(10),
            "A populated production store should not block a fresh app launch."
        )

        // A swipe can only complete after the bulk seed/save has released the
        // app, and it also verifies that maintenance yields to active scrolling.
        app.swipeUp()
        app.swipeDown()

        assertResponsiveTab("Home", navigationTitle: "Home")
        let tripsArea = app.buttons["home-area.trips"]
        for _ in 0..<8 where !tripsArea.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(tripsArea.waitForExistence(timeout: 4))
        let tripsStartedAt = ContinuousClock.now
        tripsArea.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 4)
        )
        XCTAssertLessThan(
            tripsStartedAt.duration(to: .now),
            .seconds(4),
            "A production-scale packing history should not block opening Trips."
        )
        app.swipeUp()
        app.swipeDown()

        assertResponsiveTab("Reports", navigationTitle: "Reports")
        app.swipeUp()
        assertResponsiveTab("Care", navigationTitle: "Care")

        let solids = app.buttons["care.solids"]
        XCTAssertTrue(solids.waitForExistence(timeout: 4))
        let solidsStartedAt = ContinuousClock.now
        solids.tap()
        XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            solidsStartedAt.duration(to: .now),
            .seconds(4),
            "A populated solids workspace should open without blocking the app."
        )

        let foodDatabase = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Food database")
        ).firstMatch
        for _ in 0..<4 where !foodDatabase.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(foodDatabase.waitForExistence(timeout: 4))
        XCTAssertTrue(foodDatabase.isHittable)
        foodDatabase.tap()
        XCTAssertTrue(app.navigationBars["Food Database"].waitForExistence(timeout: 4))
        app.swipeUp()
        app.swipeDown()
        assertResponsiveTab("Today", navigationTitle: "Today")
    }

    func testProductionScaleTodayScrollFramePacing() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 25))

        // Measure the rendered frames, not just whether a swipe eventually
        // finishes. This catches repeated main-thread work that is too short to
        // register as a hang but still makes physical-device scrolling janky.
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric],
            options: options
        ) {
            app.swipeUp(velocity: .fast)
        }
    }

    func testProductionScaleInputEditorsAcceptTypingPromptly() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://food/shopping/00000000-0000-0000-0000-000000000501")

        let quickAdd = app.textFields["Add item"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 8))
        quickAdd.tap()
        let shoppingTypingStartedAt = ContinuousClock.now
        quickAdd.typeText("Milk")
        XCTAssertEqual(quickAdd.value as? String, "Milk")
        XCTAssertLessThan(
            shoppingTypingStartedAt.duration(to: .now),
            .seconds(4),
            "Typing into a populated shopping list should not rebuild the entire list."
        )

        launch(startURL: "littlewindows://milestones")
        let captureMemory = app.buttons["Capture a memory"]
        XCTAssertTrue(captureMemory.waitForExistence(timeout: 8))
        captureMemory.tap()

        let milestoneTitle = app.textFields["What happened?"]
        XCTAssertTrue(milestoneTitle.waitForExistence(timeout: 4))
        milestoneTitle.tap()
        let milestoneTypingStartedAt = ContinuousClock.now
        milestoneTitle.typeText("First wave")
        XCTAssertEqual(milestoneTitle.value as? String, "First wave")
        XCTAssertLessThan(
            milestoneTypingStartedAt.duration(to: .now),
            .seconds(4),
            "Opening a photo-capable editor should not delay its first text input."
        )
    }

    func testProductionScaleTodoEditorFocusesTitlePromptly() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://food/todos/00000000-0000-0000-0000-000000000401")

        let addItem = app.buttons["home.todo.add-item"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 8))
        let focusStartedAt = ContinuousClock.now
        addItem.tap()

        let title = app.textFields["home.todo.title"]
        // The keyboard is the focus success condition. Waiting for the field and
        // keyboard separately double-counts XCUI's polling delay in this budget.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(
            focusStartedAt.duration(to: .now),
            .seconds(4),
            "Opening a populated to-do list should not delay title-field focus."
        )

        title.typeText("Schedule pickup")
        XCTAssertEqual(title.value as? String, "Schedule pickup")
    }

    func testGrowthWeightAcceptsSeparatePoundsAndDecimalOunces() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/today")

        let growth = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Growth")
        ).firstMatch
        for _ in 0..<12 where !growth.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(growth.waitForExistence(timeout: 4))
        XCTAssertTrue(growth.isHittable)
        growth.tap()

        XCTAssertTrue(app.navigationBars["Add Event"].waitForExistence(timeout: 8))
        let weightRow = app.buttons["growth-weight-row"]
        XCTAssertTrue(weightRow.waitForExistence(timeout: 4))
        weightRow.tap()

        let pounds = app.buttons["growth-weight-pounds-input"]
        let ounces = app.buttons["growth-weight-ounces-input"]
        XCTAssertTrue(pounds.waitForExistence(timeout: 4))
        XCTAssertTrue(ounces.exists)

        app.buttons["growth-keypad-1"].tap()
        app.buttons["growth-keypad-6"].tap()
        ounces.tap()
        app.buttons["growth-keypad-4"].tap()
        app.buttons["growth-keypad-decimal"].tap()
        app.buttons["growth-keypad-4"].tap()

        XCTAssertEqual(pounds.value as? String, "16")
        XCTAssertEqual(ounces.value as? String, "4.4")
        app.buttons["growth-measurement-save"].tap()

        XCTAssertTrue(weightRow.waitForExistence(timeout: 4))
        XCTAssertEqual(weightRow.value as? String, "16 lb 4.4 oz")
    }

    private func assertResponsiveTab(_ tab: String, navigationTitle: String) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        let startedAt = ContinuousClock.now
        button.tap()
        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 4))
        // waitForExistence polls the accessibility tree at roughly one-second
        // intervals, so allow one polling interval above the three-second app
        // responsiveness budget. A four-second timeout still fails a genuinely
        // blocked transition while avoiding failures caused only by poll phase.
        XCTAssertLessThan(
            startedAt.duration(to: .now),
            .seconds(4),
            "\(tab) should remain responsive with production-scale local and synced data."
        )
    }

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

        let previewLink = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
                "solids.guided.food.",
                "solids.guided.recipe."
            )
        ).firstMatch
        for _ in 0..<8 where !previewLink.exists {
            app.swipeUp()
        }
        XCTAssertTrue(previewLink.waitForExistence(timeout: 4))
        let previewTitle = previewLink.label
        previewLink.tap()
        XCTAssertTrue(
            app.navigationBars[previewTitle].waitForExistence(timeout: 4),
            "A guided meal title should open its preparation guidance."
        )
        app.navigationBars[previewTitle].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Guided Solids"].waitForExistence(timeout: 4))

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
        let servingPhoto = app.images["solids.serving-photo.mashed"]
        for _ in 0..<8 where !servingPhoto.exists {
            app.swipeUp()
        }
        XCTAssertTrue(servingPhoto.waitForExistence(timeout: 4))

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
        for _ in 0..<8 where !fruit.exists {
            app.swipeUp()
        }
        XCTAssertTrue(fruit.waitForExistence(timeout: 4))
        fruit.tap()
        let apply = app.buttons["solids.foods.filter.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 3))
        XCTAssertTrue(apply.label.hasPrefix("Show "))
        apply.tap()

        XCTAssertTrue(app.navigationBars["Food Database"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["1 active filter"].waitForExistence(timeout: 3))

        filters.tap()
        XCTAssertTrue(app.navigationBars["Food Filters"].waitForExistence(timeout: 4))
        app.buttons["Reset"].tap()
        app.buttons["solids.foods.filter.apply"].tap()
        XCTAssertFalse(app.staticTexts["1 active filter"].exists)
    }

    func testFoodDatabaseSearchRemainsResponsiveWithRichCatalogContent() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/database"
        )
        XCTAssertTrue(app.navigationBars["Food Database"].waitForExistence(timeout: 5))

        // This is intentionally the first interaction in a newly launched app
        // process. A warm second visit would hide catalog and SwiftData faults.
        app.swipeDown()
        let search = app.searchFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))

        let focusStartedAt = ContinuousClock.now
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            focusStartedAt.duration(to: .now),
            .seconds(3),
            "Focusing the food database search field should not initialize rich food guidance."
        )

        let searchStartedAt = ContinuousClock.now
        search.typeText("pineapple")
        XCTAssertTrue(app.staticTexts["Pineapple"].waitForExistence(timeout: 3))
        XCTAssertLessThan(
            searchStartedAt.duration(to: .now),
            .seconds(4),
            "Typing and filtering the rich food catalog should remain responsive."
        )
        XCTAssertFalse(app.staticTexts["Avocado"].exists)
    }

    func testAppointmentMultilineFieldsUsePersistentLeadingLabels() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://appointment/00000000-0000-0000-0000-000000000301")

        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Appointment"].waitForExistence(timeout: 5))

        assertPersistentMultilineField(
            identifier: "appointment.address",
            maxScrolls: 6
        )
        assertPersistentMultilineField(
            identifier: "appointment.notes",
            maxScrolls: 4
        )
        assertPersistentMultilineField(
            identifier: "appointment.question.new",
            maxScrolls: 4
        )
    }

    func testSolidsSummaryCardsOpenMatchingLists() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")

        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
            XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 5))
        }

        let tried = app.buttons["solids.metric.tried"]
        XCTAssertTrue(tried.waitForExistence(timeout: 4))
        tried.tap()
        XCTAssertTrue(app.navigationBars["Food Tracker"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.buttons["solids.tracker.filter.tried"].value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["No foods have been marked tried yet."].exists)

        app.navigationBars["Food Tracker"].buttons.element(boundBy: 0).tap()
        let wantToTry = app.buttons["solids.metric.want-to-try"]
        XCTAssertTrue(wantToTry.waitForExistence(timeout: 4))
        wantToTry.tap()
        XCTAssertTrue(app.navigationBars["Food Tracker"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.buttons["solids.tracker.filter.wantToTry"].value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["No foods are saved to Want to try yet."].exists)

        app.navigationBars["Food Tracker"].buttons.element(boundBy: 0).tap()
        let planned = app.buttons["solids.metric.planned"]
        XCTAssertTrue(planned.waitForExistence(timeout: 4))
        planned.tap()
        XCTAssertTrue(app.navigationBars["Plan Meals"].waitForExistence(timeout: 4))
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

    func testIngredientTrackingAndShoppingControlsRemainInteractive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")

        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
        }

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/foods/lentil")
        XCTAssertTrue(app.navigationBars["Lentil"].waitForExistence(timeout: 8))

        let favorite = app.buttons["solids.food.favorite"]
        for _ in 0..<20 where !favorite.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(favorite.isHittable)
        favorite.tap()
        XCTAssertTrue(app.buttons["Remove favorite"].waitForExistence(timeout: 4))

        let addToShoppingList = app.buttons["Add to shopping list"]
        for _ in 0..<5 where !addToShoppingList.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(addToShoppingList.isHittable)
        addToShoppingList.tap()

        XCTAssertTrue(app.staticTexts["Add Lentil to a list"].waitForExistence(timeout: 4))
        let weeklyGroceries = app.buttons["Weekly groceries"]
        XCTAssertTrue(weeklyGroceries.waitForExistence(timeout: 4))
        weeklyGroceries.tap()
        XCTAssertTrue(app.staticTexts["Added Lentil to Weekly groceries."].waitForExistence(timeout: 4))
    }

    func testRecipePlanAndLogActionsRemainInteractiveWhenSolidsWasStartedEarly() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")

        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()
        XCTAssertTrue(app.buttons["Log solids"].waitForExistence(timeout: 5))

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/recipes/avocado-bean-mash")
        XCTAssertTrue(app.navigationBars["Avocado bean mash"].waitForExistence(timeout: 8))

        let plan = app.buttons["solids.recipe.plan-tomorrow"]
        for _ in 0..<12 where !plan.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(plan.isHittable)
        plan.tap()
        XCTAssertTrue(app.staticTexts["Added to tomorrow's meal plan."].waitForExistence(timeout: 5))
        app.buttons["OK"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["solids.recipe.planned-tomorrow"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["solids.recipe.plan-tomorrow"].exists)

        let planned = app.buttons["solids.recipe.planned-tomorrow"]
        XCTAssertTrue(planned.waitForExistence(timeout: 5))
        planned.tap()
        XCTAssertTrue(app.navigationBars["Planned Meal"].waitForExistence(timeout: 5))
        let delete = app.buttons["solids.plan.delete"]
        for _ in 0..<12 where !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        let deleteAlert = app.alerts["Delete planned meal?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 4))
        deleteAlert.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Avocado bean mash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["solids.recipe.plan-tomorrow"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)["solids.recipe.planned-tomorrow"].exists
        )

        let log = app.buttons["solids.recipe.log"]
        XCTAssertTrue(log.isHittable)
        log.tap()
        XCTAssertTrue(app.navigationBars["Add Event"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["solid-food.choose"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Avocado"].exists)
        XCTAssertTrue(app.staticTexts["Black bean"].exists)

        let save = app.navigationBars["Add Event"].buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        let solidFoodSummary = app.staticTexts["Solid · Avocado + Black bean"]
        for _ in 0..<8 where !solidFoodSummary.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            solidFoodSummary.waitForExistence(timeout: 4),
            "The Feed action should identify the foods in the latest solid meal."
        )
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

    func testTodayHomeSummaryHandsOffToHomeAndRetainsModeForSession() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")

        let homeMode = app.segmentedControls.buttons["Home"]
        XCTAssertTrue(homeMode.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        homeMode.tap()

        let openToDo = app.buttons["Open To-Do in Home"]
        XCTAssertTrue(openToDo.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertFalse(app.tabBars.buttons["Home"].isSelected)
        let homeSummaryScreenshot = XCTAttachment(screenshot: app.screenshot())
        homeSummaryScreenshot.name = "Today Home summary"
        homeSummaryScreenshot.lifetime = .keepAlways
        add(homeSummaryScreenshot)

        let openShopping = app.buttons["Open Shopping in Home"]
        XCTAssertTrue(openShopping.waitForExistence(timeout: 4))
        openShopping.tap()

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        XCTAssertTrue(app.buttons["home-area.shopping"].isSelected)

        app.tabBars.buttons["Today"].tap()
        let retainedHomeMode = app.segmentedControls.buttons["Home"]
        XCTAssertTrue(retainedHomeMode.waitForExistence(timeout: 6))
        XCTAssertTrue(retainedHomeMode.isSelected)

        let careMode = app.segmentedControls.buttons["Care"]
        XCTAssertTrue(careMode.waitForExistence(timeout: 4))
        careMode.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Open To-Do in Home"].exists)

        app.segmentedControls.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Open To-Do in Home"].waitForExistence(timeout: 4))
        app.terminate()
        app.launchEnvironment = ["LITTLE_WINDOWS_UI_TESTING": "1"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.buttons["Care"].isSelected)
        XCTAssertFalse(app.buttons["Open To-Do in Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
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

    func testAppleWatchSettingsAndFavoritesNavigation() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://settings")

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        let watchRow = app.buttons.containing(
            .staticText,
            identifier: "Apple Watch"
        ).firstMatch
        for _ in 0..<8 where !watchRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(watchRow.waitForExistence(timeout: 4))
        watchRow.tap()

        XCTAssertTrue(app.navigationBars["Apple Watch"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Status"].exists)
        XCTAssertTrue(app.buttons["Send Latest State"].exists)

        let favoritesRow = app.buttons.containing(
            .staticText,
            identifier: "Watch Favorites"
        ).firstMatch
        for _ in 0..<5 where !favoritesRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(favoritesRow.waitForExistence(timeout: 4))
        favoritesRow.tap()

        XCTAssertTrue(app.navigationBars["Watch Favorites"].waitForExistence(timeout: 4))
        let customMode = app.segmentedControls.buttons["Custom"]
        XCTAssertTrue(customMode.waitForExistence(timeout: 3))
        customMode.tap()
        XCTAssertTrue(customMode.isSelected)
        let customHeader = app.staticTexts["watch.favorites.custom-header"]
        XCTAssertTrue(customHeader.waitForExistence(timeout: 3))

        let outdoorPlay = app.buttons["watch.favorite.add.outdoor-play"]
        for _ in 0..<8 where !outdoorPlay.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(outdoorPlay.waitForExistence(timeout: 3))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Apple Watch Favorites Settings"
        attachment.lifetime = .keepAlways
        add(attachment)
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

        let plannedMeal = app.buttons["solids.plan.row"]
        XCTAssertTrue(plannedMeal.waitForExistence(timeout: 4))
        plannedMeal.tap()
        XCTAssertTrue(app.navigationBars["Planned Meal"].waitForExistence(timeout: 4))

        let delete = app.buttons["solids.plan.delete"]
        for _ in 0..<12 where !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 4))
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        let deleteAlert = app.alerts["Delete planned meal?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 4))
        XCTAssertTrue(deleteAlert.buttons["Delete"].waitForExistence(timeout: 2))
        deleteAlert.buttons["Delete"].tap()

        XCTAssertTrue(app.navigationBars["Plan Meals"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["No meals planned"].waitForExistence(timeout: 4))
    }

    func testEarlyActivatedPlannerExplainsAndResolvesHardMinimumAge() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        XCTAssertTrue(activate.waitForExistence(timeout: 8))
        activate.tap()

        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/plan")
        XCTAssertTrue(app.navigationBars["Plan Meals"].waitForExistence(timeout: 8))
        app.buttons["solids.plan.add"].tap()
        XCTAssertTrue(app.navigationBars["New Solids Plan"].waitForExistence(timeout: 4))

        let search = app.searchFields["Find foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        search.tap()
        search.typeText("honey")
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        }

        let honey = app.buttons["solids.plan.food.honey"]
        XCTAssertTrue(honey.waitForExistence(timeout: 4))
        XCTAssertTrue(honey.isEnabled)
        XCTAssertTrue(app.staticTexts["Available at 12 months"].exists)
        honey.tap()

        XCTAssertTrue(app.staticTexts["Honey is available at 12 months"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Move meal to 12 months"].exists)
        let viewGuidance = app.buttons["View food guidance"]
        XCTAssertTrue(viewGuidance.exists)
        viewGuidance.tap()

        XCTAssertTrue(app.navigationBars["Honey guidance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Available from 12 months"].exists)
        app.buttons["Done"].tap()

        XCTAssertTrue(honey.waitForExistence(timeout: 4))
        honey.tap()
        let moveMeal = app.buttons["Move meal to 12 months"]
        XCTAssertTrue(moveMeal.waitForExistence(timeout: 4))
        moveMeal.tap()
        XCTAssertTrue(
            app.staticTexts["Moved the meal to 12 months and added Honey."].waitForExistence(timeout: 4)
        )
        let closeSearch = app.buttons["close"]
        if closeSearch.waitForExistence(timeout: 2) {
            closeSearch.tap()
        }
        let save = app.buttons["solids.plan.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        XCTAssertTrue(save.isEnabled)
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

    func testNamedRecipeListIsVisibleAndClearlySelectedOnRecipesScreen() {
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
        let newList = app.buttons["New recipe list"]
        for _ in 0..<12 where !newList.exists {
            app.swipeUp()
        }
        XCTAssertTrue(newList.waitForExistence(timeout: 4))
        newList.tap()

        let nameField = app.textFields["List name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        nameField.tap()
        nameField.typeText("Early days")
        app.buttons["Create and add"].tap()
        XCTAssertTrue(app.staticTexts["Early days"].waitForExistence(timeout: 5))

        launch(
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/recipes"
        )
        XCTAssertTrue(app.staticTexts["Your recipe lists"].waitForExistence(timeout: 8))
        let list = app.buttons["Recipe list: Early days"]
        XCTAssertTrue(list.waitForExistence(timeout: 4))
        list.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["solids.recipes.active-list"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Showing 1 meal in this recipe list"].exists)

        let manage = app.buttons["Manage recipe lists"]
        XCTAssertTrue(manage.waitForExistence(timeout: 4))
        manage.tap()
        XCTAssertTrue(app.buttons["Rename Early days"].waitForExistence(timeout: 4))
    }

    func testFoodRecipeAndIngredientLinksOpenThePageTheyName() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids")
        let activate = app.buttons["Start solids workspace"]
        if activate.waitForExistence(timeout: 5) {
            activate.tap()
        }

        launch(
            startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/food/solids/foods/avocado"
        )
        XCTAssertTrue(app.navigationBars["Avocado"].waitForExistence(timeout: 8))

        let recipe = app.buttons["solids.food.recipe.avocado-bean-mash"]
        for _ in 0..<16 where !recipe.exists {
            app.swipeUp()
        }
        XCTAssertTrue(recipe.waitForExistence(timeout: 4))
        recipe.tap()
        XCTAssertTrue(app.navigationBars["Avocado bean mash"].waitForExistence(timeout: 5))

        let ingredient = app.buttons["solids.recipe.ingredient.avocado"]
        XCTAssertTrue(ingredient.waitForExistence(timeout: 4))
        ingredient.tap()
        XCTAssertTrue(
            app.navigationBars["Avocado"].waitForExistence(timeout: 5),
            "A recipe ingredient row should open that ingredient's food page."
        )
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

    func testTripItineraryDirectionsOpensMapsInsteadOfEditor() {
        continueAfterFailure = false
        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://food/trips")

        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 8))
        app.buttons["trips.new"].tap()
        let tripName = app.textFields["trip.create.name"]
        XCTAssertTrue(tripName.waitForExistence(timeout: 4))
        tripName.tap()
        tripName.typeText("Directions Test Trip")
        addOfflineTripDestination(named: "Sample Destination", index: 1)
        app.buttons["trip.create.save"].tap()

        XCTAssertTrue(app.navigationBars["Directions Test Trip"].waitForExistence(timeout: 6))
        app.buttons["trip.itinerary.add"].tap()
        let addItem = app.buttons["Add Itinerary Item"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 3))
        addItem.tap()
        XCTAssertTrue(app.navigationBars["Add Itinerary Item"].waitForExistence(timeout: 4))

        let titleField = app.textFields["trip.itinerary.editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("Sample Brunch")
        let keyboardReturn = app.keyboards.buttons["return"].firstMatch
        if keyboardReturn.exists { keyboardReturn.tap() }

        let locationLink = app.buttons["trip.itinerary.editor.location"]
        let itemEditor = app.descendants(matching: .any)["trip.itinerary.editor"]
        for _ in 0..<2 where !locationLink.exists || !locationLink.isHittable {
            itemEditor.swipeUp()
        }
        XCTAssertTrue(locationLink.waitForExistence(timeout: 3))
        locationLink.tap()
        XCTAssertTrue(app.navigationBars["Destination"].waitForExistence(timeout: 3))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Sample Venue")
        let keyboardSearch = app.keyboards.buttons["Search"].firstMatch
        if keyboardSearch.exists { keyboardSearch.tap() }
        let offlineLocation = app.buttons["trip.destination.offline"]
        XCTAssertTrue(offlineLocation.waitForExistence(timeout: 3))
        for _ in 0..<2 where !offlineLocation.isHittable { app.swipeUp() }
        XCTAssertTrue(offlineLocation.isHittable)
        offlineLocation.tap()

        XCTAssertTrue(app.navigationBars["Add Itinerary Item"].waitForExistence(timeout: 3))
        app.buttons["trip.itinerary.editor.save"].tap()
        let itemSummary = app.buttons["Sample Brunch"]
        XCTAssertTrue(itemSummary.waitForExistence(timeout: 4))
        let directions = app.buttons.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".directions")
        ).firstMatch
        XCTAssertTrue(directions.waitForExistence(timeout: 3))
        XCTAssertTrue(directions.isHittable)
        XCTAssertLessThan(
            directions.frame.maxY - itemSummary.frame.minY,
            140,
            "The itinerary card summary and actions should remain compact."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "trip-itinerary-item-card"
        attachment.lifetime = .keepAlways
        add(attachment)

        itemSummary.tap()
        XCTAssertTrue(app.navigationBars["Edit Itinerary Item"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(directions.waitForExistence(timeout: 3))

        directions.tap()
        XCTAssertFalse(
            app.navigationBars["Edit Itinerary Item"].waitForExistence(timeout: 1),
            "Directions must not trigger the itinerary row's edit action."
        )
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(
            maps.wait(for: .runningForeground, timeout: 5),
            "Directions should launch Apple Maps."
        )
    }

    func testTripItineraryCreationLabelsOptionsAndResponsiveness() throws {
        continueAfterFailure = false
        var accessibilityFindings = [String]()
        func auditCurrentItinerary(_ context: String) throws {
            try app.performAccessibilityAudit { issue in
                let details = XCTAttachment(string: issue.element.debugDescription)
                details.name = "Accessibility element (\(context)) — \(issue.compactDescription)"
                details.lifetime = .keepAlways
                self.add(details)
                guard let element = issue.element else { return true }
                let elementDescription = element.debugDescription
                let isNativeItineraryAction = ["Add an idea", "Add option"].contains(element.label)
                let isUnreliableNativeTextCheck = issue.compactDescription.contains("Dynamic Type")
                    || issue.compactDescription.contains("Text clipped")
                if isNativeItineraryAction && isUnreliableNativeTextCheck {
                    return true
                }
                let list = self.app.descendants(matching: .any)["trip.itinerary"]
                let tabBar = self.app.tabBars.firstMatch
                let visibleTop = list.exists ? list.frame.minY : self.app.frame.minY
                let visibleBottom = tabBar.exists ? tabBar.frame.minY - 32 : self.app.frame.maxY - 112
                let elementFrame = element.frame
                guard elementFrame.minY >= visibleTop,
                      elementFrame.maxY <= visibleBottom else {
                    return true
                }
                accessibilityFindings.append(
                    "\(context) — \(issue.compactDescription): \(elementDescription)"
                )
                return true
            }
        }

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://food/trips")

        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 8))
        app.buttons["trips.new"].tap()
        let tripName = app.textFields["trip.create.name"]
        XCTAssertTrue(tripName.waitForExistence(timeout: 4))
        tripName.tap()
        tripName.typeText("Itinerary Audit Trip")
        addOfflineTripDestination(named: "Sample Destination", index: 1)
        app.buttons["trip.create.save"].tap()

        XCTAssertTrue(app.navigationBars["Itinerary Audit Trip"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["trip.itinerary"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.segmentedControls.buttons["Itinerary"].isSelected)
        XCTAssertTrue(app.buttons["trip.actions"].exists)

        app.buttons["trip.itinerary.add"].tap()
        let addItem = app.buttons["Add Itinerary Item"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 3))
        let editorStartedAt = ContinuousClock.now
        addItem.tap()
        XCTAssertTrue(app.navigationBars["Add Itinerary Item"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            editorStartedAt.duration(to: .now),
            .seconds(4),
            "Opening the itinerary editor should remain responsive."
        )

        let itemEditor = app.descendants(matching: .any)["trip.itinerary.editor"]
        XCTAssertTrue(itemEditor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Title"].exists)
        XCTAssertTrue(app.staticTexts["Type"].exists)
        XCTAssertTrue(app.staticTexts["Status"].exists)
        XCTAssertTrue(app.staticTexts["Schedule"].exists)
        XCTAssertTrue(app.staticTexts["Day"].exists)
        XCTAssertTrue(app.staticTexts["Start"].exists)

        let titleField = app.textFields["trip.itinerary.editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        let typingStartedAt = ContinuousClock.now
        titleField.typeText("Sample Reservation")
        XCTAssertEqual(titleField.value as? String, "Sample Reservation")
        XCTAssertLessThan(
            typingStartedAt.duration(to: .now),
            .seconds(3),
            "Typing should not rebuild or stall the itinerary."
        )
        let keyboardReturn = app.keyboards.buttons["return"].firstMatch
        if keyboardReturn.exists {
            keyboardReturn.tap()
        }

        let locationLink = app.buttons["trip.itinerary.editor.location"]
        for _ in 0..<2 where !locationLink.exists || !locationLink.isHittable {
            itemEditor.swipeUp()
        }
        XCTAssertTrue(locationLink.waitForExistence(timeout: 3))
        XCTAssertTrue(locationLink.isHittable)
        locationLink.tap()
        XCTAssertTrue(app.navigationBars["Destination"].waitForExistence(timeout: 3))

        let locationSearch = app.searchFields.firstMatch
        XCTAssertTrue(locationSearch.waitForExistence(timeout: 3))
        locationSearch.tap()
        locationSearch.typeText("Sample Activity Place")
        let locationKeyboardSearch = app.keyboards.buttons["Search"].firstMatch
        if locationKeyboardSearch.exists {
            locationKeyboardSearch.tap()
        }
        let offlineLocation = app.buttons["trip.destination.offline"]
        XCTAssertTrue(offlineLocation.waitForExistence(timeout: 3))
        for _ in 0..<2 where !offlineLocation.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(offlineLocation.isHittable)
        let locationSelectionStartedAt = ContinuousClock.now
        offlineLocation.tap()
        let itemEditorNavigationBar = app.navigationBars["Add Itinerary Item"]
        let locationSelectionDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !itemEditorNavigationBar.exists, ContinuousClock.now < locationSelectionDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(itemEditorNavigationBar.exists)
        XCTAssertLessThan(
            locationSelectionStartedAt.duration(to: .now),
            .seconds(2),
            "Selecting an activity location should return to the editor promptly."
        )
        XCTAssertTrue(app.staticTexts["Sample Activity Place"].exists)
        app.buttons["trip.itinerary.editor.location"].tap()
        XCTAssertTrue(app.navigationBars["Destination"].waitForExistence(timeout: 3))
        let clearLocation = app.buttons["Clear Destination"]
        XCTAssertTrue(clearLocation.waitForExistence(timeout: 3))
        clearLocation.tap()
        XCTAssertTrue(app.navigationBars["Add Itinerary Item"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Sample Activity Place"].exists)

        itemEditor.swipeUp()
        XCTAssertTrue(app.staticTexts["Provider or property"].waitForExistence(timeout: 3))
        for _ in 0..<2 where !app.staticTexts["Confirmation number"].exists {
            itemEditor.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Confirmation number"].waitForExistence(timeout: 3))
        for _ in 0..<2 where !app.staticTexts["Notes"].exists {
            itemEditor.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Notes"].waitForExistence(timeout: 3))

        let addLink = app.buttons["Add Link"]
        for _ in 0..<3 where !addLink.exists || !addLink.isHittable {
            itemEditor.swipeUp()
        }
        XCTAssertTrue(addLink.waitForExistence(timeout: 3))
        XCTAssertTrue(addLink.isHittable)
        addLink.tap()

        let linkLabel = app.textFields.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".label")
        ).firstMatch
        let linkURL = app.textFields.matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".url")
        ).firstMatch
        XCTAssertTrue(linkLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(linkURL.waitForExistence(timeout: 3))

        let linkFocusStartedAt = ContinuousClock.now
        linkLabel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            linkFocusStartedAt.duration(to: .now),
            .seconds(2),
            "The link label should accept focus promptly."
        )
        let linkLabelTypingStartedAt = ContinuousClock.now
        linkLabel.typeText("Official Site")
        XCTAssertEqual(linkLabel.value as? String, "Official Site")
        XCTAssertLessThan(
            linkLabelTypingStartedAt.duration(to: .now),
            .seconds(2),
            "Typing a link label should not rebuild or stall the itinerary editor."
        )

        linkURL.tap()
        let linkURLTypingStartedAt = ContinuousClock.now
        linkURL.typeText("https://sample.test/menu")
        XCTAssertEqual(linkURL.value as? String, "https://sample.test/menu")
        XCTAssertLessThan(
            linkURLTypingStartedAt.duration(to: .now),
            .seconds(3),
            "Typing a link URL should not rebuild or stall the itinerary editor."
        )

        let saveItem = app.buttons["trip.itinerary.editor.save"]
        XCTAssertTrue(saveItem.isEnabled)
        let saveStartedAt = ContinuousClock.now
        saveItem.tap()
        XCTAssertTrue(app.staticTexts["Sample Reservation"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            saveStartedAt.duration(to: .now),
            .seconds(4),
            "Saving an itinerary item should update the day promptly."
        )

        app.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let addIdeaText = app.staticTexts["Add an idea"]
        XCTAssertTrue(addIdeaText.waitForExistence(timeout: 3))
        let regularAddIdeaHeight = addIdeaText.frame.height
        try auditCurrentItinerary("ideas and day items")
        app.swipeDown()
        app.swipeDown()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        app.buttons["trip.itinerary.add"].tap()
        let addGroup = app.buttons["Add Option Group"]
        XCTAssertTrue(addGroup.waitForExistence(timeout: 3))
        addGroup.tap()
        XCTAssertTrue(app.navigationBars["New Option Group"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Title"].exists)
        XCTAssertTrue(app.staticTexts["Decision notes"].exists)
        let groupTitle = app.textFields["trip.itinerary.group-editor.title"]
        XCTAssertTrue(groupTitle.waitForExistence(timeout: 3))
        groupTitle.tap()
        groupTitle.typeText("Weather Options")
        let groupEditor = app.descendants(matching: .any)["trip.itinerary.group-editor"]
        groupEditor.swipeUp()
        let assignToDay = app.switches["Assign to a day"]
        XCTAssertEqual(assignToDay.value as? String, "0")
        XCTAssertTrue(assignToDay.isHittable)
        assignToDay.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let toggleEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: assignToDay
        )
        XCTAssertEqual(XCTWaiter.wait(for: [toggleEnabled], timeout: 2), .completed)
        XCTAssertEqual(assignToDay.value as? String, "1")
        let saveGroup = app.buttons["trip.itinerary.group-editor.save"]
        XCTAssertTrue(saveGroup.isEnabled)
        saveGroup.tap()
        XCTAssertTrue(app.staticTexts["Weather Options"].waitForExistence(timeout: 4))
        let optionGroup = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "trip.itinerary.group.")
        ).firstMatch
        XCTAssertTrue(optionGroup.waitForExistence(timeout: 3))
        let addOptionText = app.staticTexts["Add option"]
        XCTAssertTrue(addOptionText.waitForExistence(timeout: 3))
        let regularAddOptionHeight = addOptionText.frame.height
        let ideasHeader = app.staticTexts["Ideas · No Day Yet"]
        XCTAssertTrue(ideasHeader.waitForExistence(timeout: 3))
        XCTAssertLessThan(
            optionGroup.frame.minY,
            ideasHeader.frame.minY,
            "A group assigned to a day should render under that day, not under Ideas."
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        try auditCurrentItinerary("option group")
        XCTAssertTrue(
            accessibilityFindings.isEmpty,
            "Accessibility audit findings:\n\(accessibilityFindings.joined(separator: "\n\n"))"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "trip-itinerary-detail"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1",
            "LITTLE_WINDOWS_START_URL": "littlewindows://food/trips"
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 8))
        let savedTrip = app.staticTexts["Itinerary Audit Trip"]
        XCTAssertTrue(savedTrip.waitForExistence(timeout: 4))
        savedTrip.tap()
        XCTAssertTrue(app.navigationBars["Itinerary Audit Trip"].waitForExistence(timeout: 6))

        let largeAddOption = app.staticTexts["Add option"]
        for _ in 0..<4 where !largeAddOption.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(largeAddOption.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            largeAddOption.frame.height,
            regularAddOptionHeight * 1.4,
            "Add option should grow at the largest accessibility text size."
        )

        let largeAddIdea = app.staticTexts["Add an idea"]
        for _ in 0..<6 where !largeAddIdea.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(largeAddIdea.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            largeAddIdea.frame.height,
            regularAddIdeaHeight * 1.4,
            "Add an idea should grow at the largest accessibility text size."
        )
        XCTAssertGreaterThanOrEqual(app.buttons["Add an idea"].frame.height, 44)

        let largeTextAttachment = XCTAttachment(screenshot: app.screenshot())
        largeTextAttachment.name = "trip-itinerary-accessibility-text"
        largeTextAttachment.lifetime = .keepAlways
        add(largeTextAttachment)
    }

    func testTripActivitiesUseCompactSelectionScreen() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://food/trips")

        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 8))
        app.buttons["trips.new"].tap()
        XCTAssertTrue(app.navigationBars["New Trip"].waitForExistence(timeout: 4))

        let activitiesLink = app.buttons["trip.activities.open"]
        for _ in 0..<8 where !activitiesLink.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(activitiesLink.waitForExistence(timeout: 3))
        XCTAssertTrue(activitiesLink.isHittable)
        XCTAssertEqual(activitiesLink.value as? String, "None selected")
        activitiesLink.tap()

        XCTAssertTrue(app.navigationBars["Activities"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["0 selected"].exists)

        let beach = app.buttons["trip.activity.beach"]
        let sightseeing = app.buttons["trip.activity.sightseeing"]
        XCTAssertTrue(beach.waitForExistence(timeout: 3))
        XCTAssertTrue(sightseeing.waitForExistence(timeout: 3))
        beach.tap()
        sightseeing.tap()

        XCTAssertEqual(beach.value as? String, "Selected")
        XCTAssertEqual(sightseeing.value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["2 selected"].exists)

        app.navigationBars["Activities"].buttons["New Trip"].tap()
        XCTAssertTrue(app.navigationBars["New Trip"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.buttons["trip.activities.open"].value as? String,
            "2 selected: Beach, Sightseeing"
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
        let packingWorkspace = app.segmentedControls.buttons["Packing"]
        XCTAssertTrue(packingWorkspace.waitForExistence(timeout: 3))
        packingWorkspace.tap()
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
        app.segmentedControls.buttons["Packing"].tap()
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
        let packingWorkspace = app.segmentedControls.buttons["Packing"]
        XCTAssertTrue(packingWorkspace.waitForExistence(timeout: 3))
        packingWorkspace.tap()

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

        let keyboardSearch = app.keyboards.buttons["Search"].firstMatch
        if keyboardSearch.exists {
            keyboardSearch.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        let offlineChoice = app.buttons["trip.destination.offline"]
        XCTAssertTrue(offlineChoice.waitForExistence(timeout: 4))
        for _ in 0..<3 {
            if offlineChoice.isHittable { break }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(offlineChoice.isHittable)
        offlineChoice.tap()
        if !app.navigationBars["New Trip"].waitForExistence(timeout: 2), offlineChoice.exists {
            offlineChoice.tap()
        }
        XCTAssertTrue(
            app.navigationBars["New Trip"].waitForExistence(timeout: 5),
            "Expected to return to trip creation after choosing \(name); app state \(app.state.rawValue).\n\(app.debugDescription)"
        )
    }

    private func launch(
        startURL: String,
        additionalEnvironment: [String: String] = [:]
    ) {
        app.terminate()
        var launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1"
        ]
        launchEnvironment.merge(additionalEnvironment) { _, newValue in newValue }
        app.launchEnvironment = launchEnvironment
        app.launchArguments = ["--little-windows-ui-testing"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        app.open(URL(string: startURL)!)

        // Foregrounding only proves that the process launched; it does not prove
        // that RootView has consumed the debug route and committed its store
        // mutation. Wait for the route's stable destination before terminating
        // the process for the next step in a reset -> seed -> deep-link flow.
        if startURL == "littlewindows://debug/reset-empty" {
            XCTAssertTrue(
                app.navigationBars["Welcome"].waitForExistence(timeout: 12),
                "Expected empty-store onboarding after reset.\n\(app.debugDescription)"
            )
        } else if startURL == "littlewindows://debug/seed-smoke"
                    || startURL == "littlewindows://debug/seed-performance" {
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 25))
        }
    }

    private func visit(name: String, startURL: String, expectedText: [String]) {
        app.terminate()
        app.launchEnvironment = [
            "LITTLE_WINDOWS_UI_TESTING": "1"
        ]
        app.launchArguments = ["--little-windows-ui-testing"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "Expected app to foreground for \(name)"
        )
        app.open(URL(string: startURL)!)
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

    private func assertPersistentMultilineField(
        identifier: String,
        maxScrolls: Int
    ) {
        let label = app.staticTexts["\(identifier).label"]
        let field = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        for _ in 0..<maxScrolls where !label.exists || !field.exists {
            app.swipeUp()
        }
        XCTAssertTrue(label.waitForExistence(timeout: 3), "Missing label for \(identifier)")
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing input for \(identifier)")
        XCTAssertEqual(
            label.frame.minX,
            field.frame.minX,
            accuracy: 3,
            "The label and input should share a leading edge for \(identifier)."
        )
        XCTAssertGreaterThan(
            field.frame.minY,
            label.frame.minY,
            "The persistent label should remain above the input for \(identifier)."
        )
    }
}
