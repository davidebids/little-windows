import XCTest

final class UserVisibleFlowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.debidia.LittleWindows")

    func testBodyLocationVisualizationSelectsThroughLightweightHitTargets() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location")

        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 5))
        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)
        ).tap()

        let abdomen = app.buttons["body-location.selection.body.abdomen"].firstMatch
        XCTAssertTrue(
            abdomen.waitForExistence(timeout: 4),
            "Expected a center-torso tap to select the abdomen through the proxy collision geometry."
        )
    }

    func testBodyLocationBackSelectionMarkerVisualRegression() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location/bodyAreas/female")

        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        let back = app.buttons["body-location.orientation.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()

        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.44, dy: 0.75)
        ).tap()

        XCTAssertTrue(
            app.buttons["body-location.selection.body.calf.left"]
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Body location Back selection marker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBodyLocationFullBodyLandmarksMatchRenderedAnatomy() {
        continueAfterFailure = false

        let frontCases: [(name: String, point: CGVector, expectedID: String)] = [
            ("face", CGVector(dx: 0.50, dy: 0.18), "body.face"),
            ("neck", CGVector(dx: 0.50, dy: 0.245), "body.neck"),
            ("chest", CGVector(dx: 0.50, dy: 0.31), "body.chest"),
            ("abdomen", CGVector(dx: 0.50, dy: 0.42), "body.abdomen"),
            ("pelvis", CGVector(dx: 0.50, dy: 0.525), "body.pelvis"),
            ("right shoulder", CGVector(dx: 0.39, dy: 0.285), "body.shoulder.right"),
            ("left shoulder", CGVector(dx: 0.61, dy: 0.285), "body.shoulder.left"),
            ("right upper arm", CGVector(dx: 0.35, dy: 0.35), "body.upperArm.right"),
            ("left upper arm", CGVector(dx: 0.65, dy: 0.35), "body.upperArm.left"),
            ("right elbow", CGVector(dx: 0.365, dy: 0.39), "body.elbow.right"),
            ("left elbow", CGVector(dx: 0.635, dy: 0.39), "body.elbow.left"),
            ("right forearm", CGVector(dx: 0.33, dy: 0.445), "body.forearm.right"),
            ("left forearm", CGVector(dx: 0.67, dy: 0.445), "body.forearm.left"),
            ("right wrist", CGVector(dx: 0.29, dy: 0.495), "body.wrist.right"),
            ("left wrist", CGVector(dx: 0.71, dy: 0.495), "body.wrist.left"),
            ("right palm", CGVector(dx: 0.28, dy: 0.505), "body.hand.right"),
            ("left palm", CGVector(dx: 0.72, dy: 0.505), "body.hand.left"),
            ("right hip", CGVector(dx: 0.43, dy: 0.535), "body.hip.right"),
            ("left hip", CGVector(dx: 0.57, dy: 0.535), "body.hip.left")
        ]
        assertBodyLocationLandmarks(frontCases)

        let backCases: [(name: String, point: CGVector, expectedID: String)] = [
            ("back of head", CGVector(dx: 0.50, dy: 0.18), "body.head"),
            ("neck", CGVector(dx: 0.50, dy: 0.245), "body.neck"),
            ("upper back", CGVector(dx: 0.50, dy: 0.31), "body.upperBack"),
            ("lower back", CGVector(dx: 0.50, dy: 0.42), "body.lowerBack"),
            ("pelvis", CGVector(dx: 0.50, dy: 0.525), "body.pelvis"),
            ("left shoulder", CGVector(dx: 0.39, dy: 0.285), "body.shoulder.left"),
            ("right shoulder", CGVector(dx: 0.61, dy: 0.285), "body.shoulder.right"),
            ("left upper arm", CGVector(dx: 0.35, dy: 0.35), "body.upperArm.left"),
            ("right upper arm", CGVector(dx: 0.65, dy: 0.35), "body.upperArm.right"),
            ("left elbow", CGVector(dx: 0.365, dy: 0.39), "body.elbow.left"),
            ("right elbow", CGVector(dx: 0.635, dy: 0.39), "body.elbow.right"),
            ("left forearm", CGVector(dx: 0.33, dy: 0.445), "body.forearm.left"),
            ("right forearm", CGVector(dx: 0.67, dy: 0.445), "body.forearm.right"),
            ("left wrist", CGVector(dx: 0.29, dy: 0.495), "body.wrist.left"),
            ("right wrist", CGVector(dx: 0.71, dy: 0.495), "body.wrist.right"),
            ("left hand", CGVector(dx: 0.28, dy: 0.505), "body.hand.left"),
            ("right hand", CGVector(dx: 0.72, dy: 0.505), "body.hand.right"),
            ("left buttock", CGVector(dx: 0.43, dy: 0.535), "body.buttock.left"),
            ("right buttock", CGVector(dx: 0.57, dy: 0.535), "body.buttock.right")
        ]
        assertBodyLocationLandmarks(backCases, backView: true)
    }

    func testBodyLocationMaleFullBodyLandmarksMatchRenderedAnatomy() {
        continueAfterFailure = false

        let frontCases: [(name: String, point: CGVector, expectedID: String)] = [
            ("face", CGVector(dx: 0.50, dy: 0.16), "body.face"),
            ("neck", CGVector(dx: 0.50, dy: 0.235), "body.neck"),
            ("chest", CGVector(dx: 0.50, dy: 0.31), "body.chest"),
            ("abdomen", CGVector(dx: 0.50, dy: 0.42), "body.abdomen"),
            ("pelvis", CGVector(dx: 0.50, dy: 0.535), "body.pelvis"),
            ("right shoulder", CGVector(dx: 0.38, dy: 0.285), "body.shoulder.right"),
            ("left shoulder", CGVector(dx: 0.62, dy: 0.285), "body.shoulder.left"),
            ("right upper arm", CGVector(dx: 0.34, dy: 0.35), "body.upperArm.right"),
            ("left upper arm", CGVector(dx: 0.66, dy: 0.35), "body.upperArm.left"),
            ("right elbow", CGVector(dx: 0.35, dy: 0.40), "body.elbow.right"),
            ("left elbow", CGVector(dx: 0.65, dy: 0.40), "body.elbow.left"),
            ("right forearm", CGVector(dx: 0.30, dy: 0.45), "body.forearm.right"),
            ("left forearm", CGVector(dx: 0.70, dy: 0.45), "body.forearm.left"),
            ("right wrist", CGVector(dx: 0.265, dy: 0.50), "body.wrist.right"),
            ("left wrist", CGVector(dx: 0.735, dy: 0.50), "body.wrist.left"),
            ("right palm", CGVector(dx: 0.255, dy: 0.505), "body.hand.right"),
            ("left palm", CGVector(dx: 0.745, dy: 0.505), "body.hand.left"),
            ("right hip", CGVector(dx: 0.42, dy: 0.545), "body.hip.right"),
            ("left hip", CGVector(dx: 0.58, dy: 0.545), "body.hip.left")
        ]
        assertBodyLocationLandmarks(frontCases, variant: "male")

        let backCases: [(name: String, point: CGVector, expectedID: String)] = [
            ("back of head", CGVector(dx: 0.50, dy: 0.16), "body.head"),
            ("neck", CGVector(dx: 0.50, dy: 0.235), "body.neck"),
            ("upper back", CGVector(dx: 0.50, dy: 0.31), "body.upperBack"),
            ("lower back", CGVector(dx: 0.50, dy: 0.42), "body.lowerBack"),
            ("pelvis", CGVector(dx: 0.50, dy: 0.535), "body.pelvis"),
            ("left shoulder", CGVector(dx: 0.38, dy: 0.285), "body.shoulder.left"),
            ("right shoulder", CGVector(dx: 0.62, dy: 0.285), "body.shoulder.right"),
            ("left upper arm", CGVector(dx: 0.34, dy: 0.35), "body.upperArm.left"),
            ("right upper arm", CGVector(dx: 0.66, dy: 0.35), "body.upperArm.right"),
            ("left elbow", CGVector(dx: 0.35, dy: 0.40), "body.elbow.left"),
            ("right elbow", CGVector(dx: 0.65, dy: 0.40), "body.elbow.right"),
            ("left forearm", CGVector(dx: 0.30, dy: 0.45), "body.forearm.left"),
            ("right forearm", CGVector(dx: 0.70, dy: 0.45), "body.forearm.right"),
            ("left wrist", CGVector(dx: 0.265, dy: 0.50), "body.wrist.left"),
            ("right wrist", CGVector(dx: 0.735, dy: 0.50), "body.wrist.right"),
            ("left hand", CGVector(dx: 0.255, dy: 0.505), "body.hand.left"),
            ("right hand", CGVector(dx: 0.745, dy: 0.505), "body.hand.right"),
            ("left buttock", CGVector(dx: 0.42, dy: 0.545), "body.buttock.left"),
            ("right buttock", CGVector(dx: 0.58, dy: 0.545), "body.buttock.right")
        ]
        assertBodyLocationLandmarks(backCases, backView: true, variant: "male")
    }

    func testBodyLocationWristAndPalmResolveToDistinctRenderedAreas() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location/bodyAreas/female")
        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.71, dy: 0.495)
        ).tap()
        let wristSelections = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
        ).allElementsBoundByAccessibilityElement.map(\.identifier)
        XCTAssertTrue(
            app.buttons["body-location.selection.body.wrist.left"].firstMatch
                .waitForExistence(timeout: 2),
            "A tap on the visible left wrist crease should select the left wrist; selected \(wristSelections)."
        )

        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: 0.505)
        ).tap()
        XCTAssertTrue(
            app.buttons["body-location.selection.body.hand.left"].firstMatch
                .waitForExistence(timeout: 2),
            "A tap just beyond the wrist crease on the visible palm should select the left hand."
        )

        let back = app.buttons["body-location.orientation.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: 0.505)
        ).tap()
        XCTAssertTrue(
            app.buttons["body-location.selection.body.hand.right"].firstMatch
                .waitForExistence(timeout: 2),
            "A tap on the visible back of the right hand should remain a hand selection."
        )
    }

    func testBodyLocationUpperBodyInternalLayerLandmarksMatchRenderedAnatomy() {
        continueAfterFailure = false

        assertInternalBodyLandmarks(
            layer: "muscles",
            cases: [
                ("chest", CGVector(dx: 0.50, dy: 0.31), "muscle.pectorals"),
                ("abdomen", CGVector(dx: 0.50, dy: 0.42), "muscle.abdominals"),
                ("right shoulder", CGVector(dx: 0.39, dy: 0.285), "muscle.deltoid.right"),
                ("left shoulder", CGVector(dx: 0.61, dy: 0.285), "muscle.deltoid.left"),
                ("right upper arm", CGVector(dx: 0.35, dy: 0.35), "muscle.biceps.right"),
                ("left upper arm", CGVector(dx: 0.65, dy: 0.35), "muscle.biceps.left"),
                ("right forearm", CGVector(dx: 0.33, dy: 0.445), "muscle.forearm.right"),
                ("left forearm", CGVector(dx: 0.67, dy: 0.445), "muscle.forearm.left"),
                ("right hand", CGVector(dx: 0.28, dy: 0.505), "muscle.hand.right"),
                ("left hand", CGVector(dx: 0.72, dy: 0.505), "muscle.hand.left")
            ]
        )
        assertInternalBodyLandmarks(
            layer: "muscles",
            backView: true,
            cases: [
                ("upper back", CGVector(dx: 0.50, dy: 0.31), "muscle.trapezius"),
                ("lower back", CGVector(dx: 0.50, dy: 0.42), "muscle.lowerBack"),
                ("left upper arm", CGVector(dx: 0.35, dy: 0.35), "muscle.triceps.left"),
                ("right upper arm", CGVector(dx: 0.65, dy: 0.35), "muscle.triceps.right"),
                ("left buttock", CGVector(dx: 0.43, dy: 0.535), "muscle.gluteal.left"),
                ("right buttock", CGVector(dx: 0.57, dy: 0.535), "muscle.gluteal.right")
            ]
        )

        assertInternalBodyLandmarks(
            layer: "joints",
            cases: [
                ("neck", CGVector(dx: 0.50, dy: 0.245), "joint.cervicalSpine"),
                ("rib cage", CGVector(dx: 0.50, dy: 0.31), "joint.ribCage"),
                ("lower spine", CGVector(dx: 0.50, dy: 0.42), "joint.lumbarSpine"),
                ("right shoulder", CGVector(dx: 0.39, dy: 0.285), "joint.shoulder.right"),
                ("left shoulder", CGVector(dx: 0.61, dy: 0.285), "joint.shoulder.left"),
                ("right elbow", CGVector(dx: 0.365, dy: 0.39), "joint.elbow.right"),
                ("left elbow", CGVector(dx: 0.635, dy: 0.39), "joint.elbow.left"),
                ("right wrist", CGVector(dx: 0.29, dy: 0.495), "joint.wrist.right"),
                ("left wrist", CGVector(dx: 0.71, dy: 0.495), "joint.wrist.left")
            ]
        )

        assertInternalBodyLandmarks(
            layer: "nerves",
            cases: [
                ("right face", CGVector(dx: 0.485, dy: 0.18), "nerve.trigeminal.right"),
                ("left face", CGVector(dx: 0.515, dy: 0.18), "nerve.trigeminal.left"),
                ("right upper arm", CGVector(dx: 0.35, dy: 0.35), "nerve.median.right"),
                ("left upper arm", CGVector(dx: 0.65, dy: 0.35), "nerve.median.left"),
                ("right forearm", CGVector(dx: 0.33, dy: 0.445), "nerve.median.right"),
                ("left forearm", CGVector(dx: 0.67, dy: 0.445), "nerve.median.left")
            ]
        )
        assertInternalBodyLandmarks(
            layer: "nerves",
            backView: true,
            cases: [
                ("left upper arm", CGVector(dx: 0.35, dy: 0.35), "nerve.ulnar.left"),
                ("right upper arm", CGVector(dx: 0.65, dy: 0.35), "nerve.ulnar.right"),
                ("left forearm", CGVector(dx: 0.33, dy: 0.445), "nerve.ulnar.left"),
                ("right forearm", CGVector(dx: 0.67, dy: 0.445), "nerve.ulnar.right")
            ]
        )
    }

    func testBodyLocationVisibleOrgansSelectTheirRenderedStructure() {
        continueAfterFailure = false

        assertInternalBodyLandmarks(
            layer: "organs",
            cases: [
                ("brain", CGVector(dx: 0.50, dy: 0.18), "organ.brain"),
                ("right lung", CGVector(dx: 0.465, dy: 0.30), "organ.lung.right"),
                ("left lung", CGVector(dx: 0.535, dy: 0.30), "organ.lung.left"),
                ("heart", CGVector(dx: 0.545, dy: 0.325), "organ.heart"),
                ("liver", CGVector(dx: 0.47, dy: 0.38), "organ.liver"),
                ("intestines", CGVector(dx: 0.50, dy: 0.46), "organ.intestines"),
                ("bladder", CGVector(dx: 0.49, dy: 0.50), "organ.bladder")
            ]
        )
    }

    private func assertBodyLocationLandmarks(
        _ cases: [(name: String, point: CGVector, expectedID: String)],
        backView: Bool = false,
        variant: String = "female"
    ) {
        launch(startURL: "littlewindows://debug/body-location/bodyAreas/\(variant)")
        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        if backView {
            let back = app.buttons["body-location.orientation.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            back.tap()
        }

        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        for testCase in cases {
            visualization.coordinate(withNormalizedOffset: testCase.point).tap()
            let expected = app.buttons[
                "body-location.selection.\(testCase.expectedID)"
            ].firstMatch
            let didSelectExpected = expected.waitForExistence(timeout: 2)
            let selectedIdentifiers = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
            ).allElementsBoundByAccessibilityElement.map(\.identifier)
            XCTAssertTrue(
                didSelectExpected,
                "Expected a tap on the rendered \(testCase.name) to select \(testCase.expectedID); selected \(selectedIdentifiers)."
            )
        }
    }

    private func assertInternalBodyLandmarks(
        layer: String,
        backView: Bool = false,
        cases: [(name: String, point: CGVector, expectedID: String)]
    ) {
        launch(startURL: "littlewindows://debug/body-location/\(layer)/female")
        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        if backView {
            let back = app.buttons["body-location.orientation.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            back.tap()
        }

        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 6))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        for testCase in cases {
            visualization.coordinate(withNormalizedOffset: testCase.point).tap()
            let expected = app.buttons[
                "body-location.selection.\(testCase.expectedID)"
            ].firstMatch
            let didSelectExpected = expected.waitForExistence(timeout: 2)
            let selectedIdentifiers = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
            ).allElementsBoundByAccessibilityElement.map(\.identifier)
            XCTAssertTrue(
                didSelectExpected,
                "Expected \(layer) at the rendered \(testCase.name) to select \(testCase.expectedID); selected \(selectedIdentifiers)."
            )
        }
    }

    func testBodyLocationFocusedHandAcceptsDirectSelections() {
        continueAfterFailure = false

        let expectations = [
            (layer: "bodyAreas", structure: "body.middleFinger"),
            (layer: "muscles", structure: "muscle.hand"),
            (layer: "joints", structure: "joint.middleFinger"),
            (layer: "nerves", structure: "nerve.median")
        ]

        for expectation in expectations {
            launch(
                startURL: "littlewindows://debug/body-location/\(expectation.layer)/female"
            )

            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
            let hands = app.buttons["body-location.region.armsAndHands"]
            XCTAssertTrue(hands.waitForExistence(timeout: 4))
            hands.tap()

            for (focus, side) in [("Left hand", "left"), ("Right hand", "right")] {
                let hand = app.buttons[focus]
                XCTAssertTrue(hand.waitForExistence(timeout: 4))
                hand.tap()

                let visualization = app.otherElements["body-location.visualization"]
                XCTAssertTrue(visualization.waitForExistence(timeout: 5))
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                visualization.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).tap()

                XCTAssertTrue(
                    app.buttons[
                        "body-location.selection.\(expectation.structure).\(side)"
                    ]
                    .firstMatch
                    .waitForExistence(timeout: 4),
                    "Expected a direct tap on the focused \(focus.lowercased()) in the \(expectation.layer) layer to add its anatomy selection."
                )
            }
        }
    }

    func testBodyLocationFocusedFootAcceptsGranularSelections() {
        continueAfterFailure = false

        let expectedPrefixes: [(layer: String, structures: [String])] = [
            (
                layer: "bodyAreas",
                structures: [
                    "body.heel", "body.topOfFoot", "body.sole", "body.arch",
                    "body.ballOfFoot", "body.greatToe", "body.secondToe",
                    "body.middleToe", "body.fourthToe", "body.littleToe"
                ]
            ),
            (
                layer: "muscles",
                structures: ["muscle.achilles", "muscle.foot"]
            ),
            (
                layer: "joints",
                structures: [
                    "joint.ankle", "joint.heel", "joint.midfoot", "joint.greatToe",
                    "joint.secondToe", "joint.middleToe", "joint.fourthToe",
                    "joint.littleToe"
                ]
            ),
            (
                layer: "nerves",
                structures: ["nerve.tibial", "nerve.fibular", "nerve.plantar"]
            )
        ]

        for expectation in expectedPrefixes {
            launch(startURL: "littlewindows://debug/body-location/\(expectation.layer)/female")
            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))

            let regionScroll = app.scrollViews["body-location.region-scroll"]
            XCTAssertTrue(regionScroll.waitForExistence(timeout: 4))
            regionScroll.swipeLeft()
            let legsAndFeet = app.buttons["body-location.region.legsAndFeet"]
            XCTAssertTrue(legsAndFeet.waitForExistence(timeout: 4))
            legsAndFeet.tap()

            for (focus, side) in [("Left foot", "left"), ("Right foot", "right")] {
                let foot = app.buttons[focus]
                XCTAssertTrue(foot.waitForExistence(timeout: 4))
                foot.tap()

                let visualization = app.otherElements["body-location.visualization"]
                XCTAssertTrue(visualization.waitForExistence(timeout: 5))
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                visualization.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).tap()

                let selectedIdentifiers = app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
                ).allElementsBoundByAccessibilityElement.map(\.identifier)
                let expectedIdentifiers = expectation.structures.map {
                    "body-location.selection.\($0).\(side)"
                }
                XCTAssertFalse(
                    Set(selectedIdentifiers).isDisjoint(with: expectedIdentifiers),
                    "Expected a granular \(side) foot selection in \(expectation.layer); selected \(selectedIdentifiers)."
                )

                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "Foot fidelity female \(expectation.layer) \(side)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testBodyLocationFocusedFootPresentsTopAndSoleForBothModels() {
        continueAfterFailure = false

        for sex in ["female", "male"] {
            launch(startURL: "littlewindows://debug/body-location/bodyAreas/\(sex)")
            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))

            let regionScroll = app.scrollViews["body-location.region-scroll"]
            XCTAssertTrue(regionScroll.waitForExistence(timeout: 4))
            regionScroll.swipeLeft()
            let legsAndFeet = app.buttons["body-location.region.legsAndFeet"]
            XCTAssertTrue(legsAndFeet.waitForExistence(timeout: 4))
            legsAndFeet.tap()

            let leftFoot = app.buttons["Left foot"]
            XCTAssertTrue(leftFoot.waitForExistence(timeout: 4))
            leftFoot.tap()
            XCTAssertTrue(app.buttons["Side"].waitForExistence(timeout: 4))
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))

            let topAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            topAttachment.name = "Foot presentation \(sex) side"
            topAttachment.lifetime = .keepAlways
            add(topAttachment)

            app.buttons["Sole"].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let soleAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            soleAttachment.name = "Foot presentation \(sex) sole"
            soleAttachment.lifetime = .keepAlways
            add(soleAttachment)

            let visualization = app.otherElements["body-location.visualization"]
            visualization.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.69)
            ).tap()

            XCTAssertTrue(
                app.buttons["body-location.selection.body.heel.left"]
                    .firstMatch
                    .waitForExistence(timeout: 3),
                "A tap on the rendered heel must select the heel in Sole view."
            )

            let soleOrientation = app.buttons["body-location.orientation.back"]
            XCTAssertEqual(
                soleOrientation.value as? String,
                "Selected",
                "Selecting the sole must not reset the focused foot to its side view."
            )

            visualization.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)
            ).tap()
            XCTAssertEqual(
                soleOrientation.value as? String,
                "Selected",
                "Selecting a toe from the sole must keep the sole view open."
            )

            let toeSelections = [
                "body.greatToe.left", "body.secondToe.left",
                "body.middleToe.left", "body.fourthToe.left", "body.littleToe.left"
            ].map { app.buttons["body-location.selection.\($0)"] }
            XCTAssertTrue(
                toeSelections.contains { $0.waitForExistence(timeout: 1) },
                "A tap on the rendered toes must select a toe in Sole view."
            )
        }
    }

    func testBodyLocationFocusedFootSkeletonPresentationForBothModels() {
        continueAfterFailure = false

        for sex in ["female", "male"] {
            launch(startURL: "littlewindows://debug/body-location/joints/\(sex)")
            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))

            let regionScroll = app.scrollViews["body-location.region-scroll"]
            XCTAssertTrue(regionScroll.waitForExistence(timeout: 4))
            regionScroll.swipeLeft()
            let legsAndFeet = app.buttons["body-location.region.legsAndFeet"]
            XCTAssertTrue(legsAndFeet.waitForExistence(timeout: 4))
            legsAndFeet.tap()

            for focus in ["Left foot", "Right foot"] {
                let foot = app.buttons[focus]
                XCTAssertTrue(foot.waitForExistence(timeout: 4))
                foot.tap()

                let side = app.buttons["Side"]
                XCTAssertTrue(side.waitForExistence(timeout: 4))
                side.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                let sideAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                sideAttachment.name = "Foot skeleton \(sex) \(focus.lowercased()) side"
                sideAttachment.lifetime = .keepAlways
                add(sideAttachment)

                app.buttons["Sole"].tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                let soleAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                soleAttachment.name = "Foot skeleton \(sex) \(focus.lowercased()) sole"
                soleAttachment.lifetime = .keepAlways
                add(soleAttachment)
            }
        }
    }

    func testBodyLocationFocusedFootSoftTissuePresentationForBothModels() {
        continueAfterFailure = false

        for layer in ["muscles", "nerves"] {
            for sex in ["female", "male"] {
                launch(startURL: "littlewindows://debug/body-location/\(layer)/\(sex)")
                XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))

                let regionScroll = app.scrollViews["body-location.region-scroll"]
                XCTAssertTrue(regionScroll.waitForExistence(timeout: 4))
                regionScroll.swipeLeft()
                let legsAndFeet = app.buttons["body-location.region.legsAndFeet"]
                XCTAssertTrue(legsAndFeet.waitForExistence(timeout: 4))
                legsAndFeet.tap()

                for focus in ["Left foot", "Right foot"] {
                    let foot = app.buttons[focus]
                    XCTAssertTrue(foot.waitForExistence(timeout: 4))
                    foot.tap()

                    let side = app.buttons["Side"]
                    XCTAssertTrue(side.waitForExistence(timeout: 4))
                    side.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.6))

                    let sideAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    sideAttachment.name = "Foot \(layer) \(sex) \(focus.lowercased()) side"
                    sideAttachment.lifetime = .keepAlways
                    add(sideAttachment)

                    let sole = app.buttons["Sole"]
                    XCTAssertTrue(sole.waitForExistence(timeout: 4))
                    sole.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.6))

                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "Foot \(layer) \(sex) \(focus.lowercased()) sole"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testBodyLocationRightElbowTapResolvesToNearestJointLandmark() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location/joints/female")

        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 5))
        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.365, dy: 0.39)
        ).tap()

        let rightElbow = app.buttons["body-location.selection.joint.elbow.right"].firstMatch
        let didSelectRightElbow = rightElbow.waitForExistence(timeout: 4)
        let selectedIdentifiers = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
        ).allElementsBoundByAccessibilityElement.map(\.identifier)
        XCTAssertTrue(
            didSelectRightElbow,
            "Expected the rendered right elbow in \(visualization.frame); selected \(selectedIdentifiers)."
        )
    }

    func testBodyLocationFullBodyLowerLimbZonesStayOnTappedSideAndSegment() {
        continueAfterFailure = false

        let frontCases: [(name: String, point: CGVector, expectedID: String)] = [
            ("right upper knee", CGVector(dx: 0.445, dy: 0.665), "body.knee.right"),
            ("left upper knee", CGVector(dx: 0.555, dy: 0.665), "body.knee.left"),
            ("right lower knee", CGVector(dx: 0.445, dy: 0.69), "body.knee.right"),
            ("left lower knee", CGVector(dx: 0.555, dy: 0.69), "body.knee.left"),
            ("right upper shin", CGVector(dx: 0.44, dy: 0.72), "body.lowerLeg.right"),
            ("left upper shin", CGVector(dx: 0.56, dy: 0.72), "body.lowerLeg.left"),
            ("right lower leg", CGVector(dx: 0.44, dy: 0.75), "body.lowerLeg.right"),
            ("left lower leg", CGVector(dx: 0.56, dy: 0.75), "body.lowerLeg.left")
        ]

        for testCase in frontCases {
            launch(startURL: "littlewindows://debug/body-location/bodyAreas/female")
            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
            let visualization = app.otherElements["body-location.visualization"]
            XCTAssertTrue(visualization.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            visualization.coordinate(withNormalizedOffset: testCase.point).tap()

            let expected = app.buttons[
                "body-location.selection.\(testCase.expectedID)"
            ].firstMatch
            let didSelectExpected = expected.waitForExistence(timeout: 3)
            let selectedIdentifiers = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
            ).allElementsBoundByAccessibilityElement.map(\.identifier)
            XCTAssertTrue(
                didSelectExpected,
                "Expected the rendered \(testCase.name) to select \(testCase.expectedID); selected \(selectedIdentifiers)."
            )
        }

        for (name, point, expectedID) in [
            ("left calf", CGVector(dx: 0.44, dy: 0.75), "body.calf.left"),
            ("right calf", CGVector(dx: 0.56, dy: 0.75), "body.calf.right")
        ] {
            launch(startURL: "littlewindows://debug/body-location/bodyAreas/female")
            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
            let back = app.buttons["body-location.orientation.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            back.tap()
            let visualization = app.otherElements["body-location.visualization"]
            XCTAssertTrue(visualization.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))

            visualization.coordinate(withNormalizedOffset: point).tap()

            let expected = app.buttons["body-location.selection.\(expectedID)"].firstMatch
            let didSelectExpected = expected.waitForExistence(timeout: 3)
            let selectedIdentifiers = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
            ).allElementsBoundByAccessibilityElement.map(\.identifier)
            XCTAssertTrue(
                didSelectExpected,
                "Expected the rendered \(name) to select \(expectedID); selected \(selectedIdentifiers)."
            )
        }
    }

    func testBodyLocationBonesLayerSeparatesKneesFromThighAndShinBones() {
        continueAfterFailure = false

        let cases: [(name: String, point: CGVector, expectedID: String)] = [
            ("right knee", CGVector(dx: 0.445, dy: 0.665), "joint.knee.right"),
            ("left knee", CGVector(dx: 0.555, dy: 0.665), "joint.knee.left"),
            ("right shin", CGVector(dx: 0.44, dy: 0.72), "joint.shin.right"),
            ("left shin", CGVector(dx: 0.56, dy: 0.72), "joint.shin.left")
        ]

        for testCase in cases {
            launch(startURL: "littlewindows://debug/body-location/joints/female")
            XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
            let visualization = app.otherElements["body-location.visualization"]
            XCTAssertTrue(visualization.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            visualization.coordinate(withNormalizedOffset: testCase.point).tap()

            let expected = app.buttons[
                "body-location.selection.\(testCase.expectedID)"
            ].firstMatch
            let didSelectExpected = expected.waitForExistence(timeout: 3)
            let selectedIdentifiers = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "body-location.selection.")
            ).allElementsBoundByAccessibilityElement.map(\.identifier)
            XCTAssertTrue(
                didSelectExpected,
                "Expected the rendered \(testCase.name) to select \(testCase.expectedID); selected \(selectedIdentifiers)."
            )
        }
    }

    func testBodyLocationModelDragDoesNotScrollPicker() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location")

        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        let visualization = app.otherElements["body-location.visualization"]
        XCTAssertTrue(visualization.waitForExistence(timeout: 5))
        let initialMinY = visualization.frame.minY

        let dragPaths = [
            (CGVector(dx: 0.55, dy: 0.70), CGVector(dx: 0.55, dy: 0.25)),
            (CGVector(dx: 0.48, dy: 0.28), CGVector(dx: 0.48, dy: 0.68)),
            (CGVector(dx: 0.62, dy: 0.62), CGVector(dx: 0.35, dy: 0.30)),
            // A long downward pull used to be claimed by the sheet's own pan
            // recognizer even after the surrounding ScrollView was locked.
            (CGVector(dx: 0.50, dy: 0.18), CGVector(dx: 0.50, dy: 0.96))
        ]
        for (start, end) in dragPaths {
            visualization.coordinate(withNormalizedOffset: start).press(
                forDuration: 0.05,
                thenDragTo: visualization.coordinate(withNormalizedOffset: end)
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))

            XCTAssertTrue(
                app.navigationBars["Where is it?"].exists,
                "Dragging inside the model should not collapse or dismiss the picker."
            )
            XCTAssertEqual(
                visualization.frame.minY,
                initialMinY,
                accuracy: 1,
                "Dragging inside the model should rotate it without scrolling the picker."
            )
        }
    }

    func testBodyLocationAnatomyLayersLoadOnDemandAndRemainResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location")

        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        for layer in ["muscles", "joints", "nerves", "organs", "bodyAreas"] {
            let layerButton = app.buttons["body-location.layer.\(layer)"]
            XCTAssertTrue(layerButton.waitForExistence(timeout: 4))
            layerButton.tap()
            XCTAssertTrue(
                app.buttons["body-location.done"].waitForExistence(timeout: 6),
                "Expected the picker to stay responsive after loading \(layer)."
            )
        }
    }

    func testBodyLocationOrganLayerRendersItsInteractiveVascularView() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/body-location/organs")

        XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
        let organLayer = app.buttons["body-location.layer.organs"]
        XCTAssertTrue(organLayer.waitForExistence(timeout: 5))
        organLayer.tap()
        XCTAssertEqual(organLayer.value as? String, "Selected")
        XCTAssertTrue(app.otherElements["body-location.visualization"].waitForExistence(timeout: 6))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Body location organ and vascular layer"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let back = app.buttons["body-location.orientation.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let backScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        backScreenshot.name = "Body location posterior vascular alignment"
        backScreenshot.lifetime = .keepAlways
        add(backScreenshot)
    }

    func testBodyLocationAlignmentAuditCapturesEveryInternalLayerAroundFullRotation() {
        continueAfterFailure = false

        for sex in ["female", "male"] {
            for layer in ["muscles", "joints", "nerves", "organs"] {
                launch(startURL: "littlewindows://debug/body-location/\(layer)/\(sex)")

                XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
                let visualization = app.otherElements["body-location.visualization"]
                XCTAssertTrue(visualization.waitForExistence(timeout: 6))
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))

                attachAlignmentScreenshot(sex: sex, layer: layer, degrees: 0)
                for degrees in stride(from: 45, through: 315, by: 45) {
                    rotateAlignmentVisualization(visualization)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.18))
                    attachAlignmentScreenshot(sex: sex, layer: layer, degrees: degrees)
                }

                let reset = app.buttons["body-location.reset-view"]
                for pitch in ["up", "down"] {
                    XCTAssertTrue(reset.waitForExistence(timeout: 3))
                    reset.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.45))
                    pitchAlignmentVisualization(visualization, direction: pitch)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.18))
                    attachAlignmentScreenshot(
                        sex: sex,
                        layer: layer,
                        degrees: 0,
                        pitch: pitch
                    )
                    for degrees in stride(from: 45, through: 315, by: 45) {
                        rotateAlignmentVisualization(visualization)
                        RunLoop.current.run(until: Date().addingTimeInterval(0.18))
                        attachAlignmentScreenshot(
                            sex: sex,
                            layer: layer,
                            degrees: degrees,
                            pitch: pitch
                        )
                    }
                }
            }
        }
    }

    func testBodyLocationHandAnatomyFidelityFromMultipleAngles() {
        continueAfterFailure = false

        for sex in ["female", "male"] {
            for layer in ["muscles", "joints", "nerves"] {
                launch(startURL: "littlewindows://debug/body-location/\(layer)/\(sex)")

                XCTAssertTrue(app.navigationBars["Where is it?"].waitForExistence(timeout: 8))
                let visualization = app.otherElements["body-location.visualization"]
                XCTAssertTrue(visualization.waitForExistence(timeout: 6))
                let hands = app.buttons["body-location.region.armsAndHands"]
                XCTAssertTrue(hands.waitForExistence(timeout: 4))
                hands.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))

                let leftHand = app.buttons["Left hand"]
                XCTAssertTrue(leftHand.waitForExistence(timeout: 3))
                leftHand.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))

                attachHandScreenshot(sex: sex, layer: layer, hand: "left", angle: "front")
                rotateAlignmentVisualization(visualization)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                attachHandScreenshot(sex: sex, layer: layer, hand: "left", angle: "oblique")

                let back = app.buttons["body-location.orientation.back"]
                XCTAssertTrue(back.waitForExistence(timeout: 3))
                back.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                attachHandScreenshot(sex: sex, layer: layer, hand: "left", angle: "back")

                let rightHand = app.buttons["Right hand"]
                XCTAssertTrue(rightHand.waitForExistence(timeout: 3))
                rightHand.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                attachHandScreenshot(sex: sex, layer: layer, hand: "right", angle: "back")
            }
        }
    }

    private func rotateAlignmentVisualization(_ visualization: XCUIElement) {
        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.62, dy: 0.48)
        ).press(
            forDuration: 0.05,
            thenDragTo: visualization.coordinate(
                withNormalizedOffset: CGVector(dx: 0.355, dy: 0.48)
            )
        )
    }

    private func pitchAlignmentVisualization(
        _ visualization: XCUIElement,
        direction: String
    ) {
        let destinationY = direction == "up" ? 0.27 : 0.70
        visualization.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)
        ).press(
            forDuration: 0.05,
            thenDragTo: visualization.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: destinationY)
            )
        )
    }

    private func attachAlignmentScreenshot(
        sex: String,
        layer: String,
        degrees: Int,
        pitch: String = "level"
    ) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Alignment \(sex) \(layer) \(degrees) degrees \(pitch) pitch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachHandScreenshot(
        sex: String,
        layer: String,
        hand: String,
        angle: String
    ) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Hand fidelity \(sex) \(layer) \(hand) \(angle)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProfileAvatarFitsToolbarOnInitialLoad() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(
            startURL: "littlewindows://debug/seed-smoke",
            additionalEnvironment: ["LITTLE_WINDOWS_UI_TEST_PROFILE_PHOTO": "1"]
        )
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

    func testUnassignedLocalProfileCanOptIntoFamilySync() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(
            startURL: "littlewindows://debug/seed-smoke",
            additionalEnvironment: ["LITTLE_WINDOWS_UI_TEST_UNOWNED_PROFILE": "1"]
        )
        launch(startURL: "littlewindows://settings")

        let careProfiles = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Care Profiles")
        ).firstMatch
        XCTAssertTrue(careProfiles.waitForExistence(timeout: 5))
        careProfiles.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))

        let editProfile = app.buttons["Edit Sample Child"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 4))
        editProfile.tap()
        XCTAssertTrue(app.navigationBars["Edit Profile"].waitForExistence(timeout: 5))

        let sharingToggle = app.switches["Share this profile with Family Sync"]
        XCTAssertTrue(sharingToggle.waitForExistence(timeout: 4))
        XCTAssertTrue(sharingToggle.isEnabled)
        sharingToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let sharingEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1'"),
            object: sharingToggle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sharingEnabled], timeout: 3), .completed)
        app.navigationBars["Edit Profile"].buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(editProfile.waitForExistence(timeout: 4))
        editProfile.tap()
        XCTAssertTrue(app.navigationBars["Edit Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(sharingToggle.waitForExistence(timeout: 4))
        XCTAssertTrue(sharingToggle.isEnabled)
        XCTAssertEqual(sharingToggle.value as? String, "1")
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
        for label in ["Name", "Strength", "Strength unit"] {
            XCTAssertTrue(
                app.staticTexts[label].exists,
                "The \(label) label should remain visible independently of its input value."
            )
        }

        let formPicker = app.buttons["medication.form"]
        let doseUnitPicker = app.buttons["medication.dose-unit"]
        XCTAssertTrue(formPicker.exists)

        formPicker.tap()
        XCTAssertTrue(app.buttons["Liquid"].waitForExistence(timeout: 3))
        app.buttons["Liquid"].tap()

        assertPersistentMultilineField(
            identifier: "medication.instructions",
            maxScrolls: 3
        )

        for _ in 0..<3 where !doseUnitPicker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(doseUnitPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Dose"].exists)
        XCTAssertTrue(doseUnitPicker.label.contains("Milliliter (mL)"))

        doseUnitPicker.tap()
        XCTAssertTrue(app.buttons["Milligram (mg)"].waitForExistence(timeout: 3))
        app.buttons["Milligram (mg)"].tap()
        XCTAssertTrue(doseUnitPicker.label.contains("Milligram (mg)"))

        app.swipeUp()
        let supplyToggle = app.switches["Track quantity on hand"]
        for _ in 0..<5 where !supplyToggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(supplyToggle.waitForExistence(timeout: 3))
        let supplyControl = app.switches
            .matching(NSPredicate(format: "label == ''"))
            .allElementsBoundByIndex
            .first { abs($0.frame.midY - supplyToggle.frame.midY) < 4 }
            ?? supplyToggle
        supplyControl.tap()
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
        for _ in 0..<3 where !instructions.exists {
            app.swipeUp()
        }
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

    func testMedicationListOpensMedicationDetailWithoutBlocking() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(
            startURL: "littlewindows://debug/seed-smoke",
            additionalEnvironment: ["LITTLE_WINDOWS_MARKETING_CAPTURE": "1"]
        )
        launch(startURL: "littlewindows://medications")

        XCTAssertTrue(app.navigationBars["Medications"].waitForExistence(timeout: 8))
        let medication = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Vitamin D")
        ).firstMatch
        XCTAssertTrue(medication.waitForExistence(timeout: 4))

        let navigationStartedAt = ContinuousClock.now
        medication.tap()
        XCTAssertTrue(app.navigationBars["Vitamin D"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            navigationStartedAt.duration(to: .now),
            .seconds(4),
            "Opening a medication from Medication List should not block the app."
        )
        XCTAssertTrue(app.staticTexts["Schedule"].exists)
    }

    func testProductionScaleMedicationHistoryLoadsWithoutBlockingDetail() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000103/today")
        XCTAssertTrue(app.buttons["Sample Adult settings"].waitForExistence(timeout: 12))
        launch(startURL: "littlewindows://medications")

        XCTAssertTrue(app.navigationBars["Medications"].waitForExistence(timeout: 8))
        let medication = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Sample Medication")
        ).firstMatch
        XCTAssertTrue(medication.waitForExistence(timeout: 4))

        let navigationStartedAt = ContinuousClock.now
        medication.tap()
        XCTAssertTrue(app.navigationBars["Sample Medication"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            navigationStartedAt.duration(to: .now),
            .seconds(4),
            "Six thousand dose records must not block medication-detail navigation."
        )

        let historyStartedAt = ContinuousClock.now
        let loadedHistory = app.descendants(matching: .any)["medication-detail.history-loaded"]
        for _ in 0..<8 where !loadedHistory.exists {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(loadedHistory.waitForExistence(timeout: 4))
        XCTAssertLessThan(
            historyStartedAt.duration(to: .now),
            .seconds(10),
            "Bounded medication history should load and become scrollable promptly."
        )

        let scrollStartedAt = ContinuousClock.now
        app.swipeDown(velocity: .fast)
        XCTAssertLessThan(
            scrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Loaded medication history must not make the detail screen unresponsive."
        )
    }

    func testMedicationDetailOffersDirectSupplyTrackingSetup() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000103/today")
        XCTAssertTrue(app.buttons["Sample Adult settings"].waitForExistence(timeout: 12))
        launch(startURL: "littlewindows://medications")

        XCTAssertTrue(app.navigationBars["Medications"].waitForExistence(timeout: 8))
        let medication = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Sample Medication")
        ).firstMatch
        XCTAssertTrue(medication.waitForExistence(timeout: 4))
        medication.tap()
        XCTAssertTrue(app.navigationBars["Sample Medication"].waitForExistence(timeout: 4))

        let setup = app.buttons["medication.supply.setup"]
        for _ in 0..<6 where !setup.isHittable {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(setup.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Supply tracking is off"].exists)
        setup.tap()

        XCTAssertTrue(app.navigationBars["Supply Tracking"].waitForExistence(timeout: 4))
        let quantity = app.textFields["medication.supply.quantity"]
        XCTAssertTrue(quantity.exists)
        XCTAssertEqual(quantity.value as? String, "Enter quantity")
        XCTAssertTrue(app.staticTexts["tablets"].exists)
        quantity.tap()
        quantity.typeText("3")
        XCTAssertEqual(quantity.value as? String, "3")
        XCTAssertTrue(app.textFields["medication.supply.threshold"].exists)
        app.buttons["medication.supply.save"].tap()

        XCTAssertTrue(app.navigationBars["Sample Medication"].waitForExistence(timeout: 4))
        XCTAssertFalse(setup.exists)
        XCTAssertTrue(app.staticTexts["Remaining"].exists)
        XCTAssertTrue(app.staticTexts["Refill alert"].exists)
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

    func testProductionScaleSolidsAmountsAndPostSaveCareNavigationStayResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000101/quick-log/feed")

        XCTAssertTrue(app.navigationBars["Add Event"].waitForExistence(timeout: 8))
        let kindPicker = app.buttons["event.feed-kind"]
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 4))
        kindPicker.tap()
        XCTAssertTrue(app.buttons["Solid"].waitForExistence(timeout: 3))
        app.buttons["Solid"].tap()

        let chooseFoods = app.buttons["solid-food.choose"]
        XCTAssertTrue(chooseFoods.waitForExistence(timeout: 4))
        chooseFoods.tap()
        let foodSearch = app.searchFields["Search or enter a food"]
        XCTAssertTrue(foodSearch.waitForExistence(timeout: 4))
        foodSearch.tap()
        foodSearch.typeText("spinach")
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        }
        let spinach = app.buttons["solid-food.option.spinach"]
        XCTAssertTrue(spinach.waitForExistence(timeout: 3))
        spinach.tap()
        app.buttons["solid-food.use-selection"].tap()

        XCTAssertTrue(app.buttons["Spinach"].waitForExistence(timeout: 4))
        app.buttons["Spinach"].tap()
        XCTAssertTrue(app.navigationBars["Spinach"].waitForExistence(timeout: 4))

        let offered = app.textFields["solid-food.amount-offered"]
        XCTAssertTrue(offered.waitForExistence(timeout: 4))
        offered.tap()
        let offeredTypingStartedAt = ContinuousClock.now
        offered.typeText("12")
        XCTAssertLessThan(
            offeredTypingStartedAt.duration(to: .now),
            .seconds(2.5),
            "Typing an offered amount must not invalidate the full event editor or intake history."
        )

        let eaten = app.textFields["solid-food.amount-eaten"]
        XCTAssertTrue(eaten.waitForExistence(timeout: 2))
        eaten.tap()
        let eatenTypingStartedAt = ContinuousClock.now
        eaten.typeText("8")
        XCTAssertLessThan(
            eatenTypingStartedAt.duration(to: .now),
            .seconds(2.5),
            "Typing an eaten amount must stay local to the food detail editor."
        )

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Add Event"].waitForExistence(timeout: 3))
        app.navigationBars["Add Event"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))

        let careStartedAt = ContinuousClock.now
        app.tabBars.buttons["Care"].tap()
        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 3))
        XCTAssertLessThan(
            careStartedAt.duration(to: .now),
            .seconds(3),
            "Saving intake must not make the next primary-tab transition wait for derived nutrition or history work."
        )
        app.swipeUp(velocity: .fast)

        let postSaveDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        var opensToday = true
        while ContinuousClock.now < postSaveDeadline {
            let transitionStartedAt = ContinuousClock.now
            if opensToday {
                app.tabBars.buttons["Today"].tap()
                XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
                app.swipeUp(velocity: .fast)
            } else {
                app.tabBars.buttons["Care"].tap()
                XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 3))
                app.swipeUp(velocity: .fast)
            }
            XCTAssertLessThan(
                transitionStartedAt.duration(to: .now),
                .seconds(6),
                "Nutrition reconciliation and sleep analysis must not freeze either primary tab after intake is saved."
            )
            opensToday.toggle()
        }
    }

    func testProductionScaleCustomRecipeSaveDeleteKeepsRecipesScrollable() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://food/solids/recipes")

        XCTAssertTrue(app.navigationBars["Solids Recipes"].waitForExistence(timeout: 8))
        let create = app.buttons["solids.recipes.create-custom"]
        XCTAssertTrue(create.waitForExistence(timeout: 4))
        create.tap()

        XCTAssertTrue(app.navigationBars["Build Recipe"].waitForExistence(timeout: 4))
        let name = app.textFields["solids.custom-recipe.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Performance Spinach Mash")

        let chooseFood = app.buttons["solids.custom-recipe.choose-food"]
        XCTAssertTrue(chooseFood.waitForExistence(timeout: 3))
        chooseFood.tap()
        XCTAssertTrue(app.navigationBars["Choose Food"].waitForExistence(timeout: 3))
        let search = app.searchFields["Search foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("spinach")
        let spinach = app.buttons["solids.custom-recipe.food.spinach"]
        XCTAssertTrue(spinach.waitForExistence(timeout: 3))
        spinach.tap()

        let amount = app.textFields["solids.custom-recipe.ingredient-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("20")
        let addIngredient = app.buttons["solids.custom-recipe.add-ingredient"]
        XCTAssertTrue(addIngredient.waitForExistence(timeout: 3))
        addIngredient.tap()

        let save = app.buttons["solids.custom-recipe.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        let saveStartedAt = ContinuousClock.now
        save.tap()
        XCTAssertTrue(app.navigationBars["Solids Recipes"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            saveStartedAt.duration(to: .now),
            .seconds(4),
            "Saving one custom recipe must not block the recipes list on unrelated meal-plan history."
        )

        let postSaveScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            postSaveScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "The recipes list must accept scrolling immediately after a custom recipe is saved."
        )
        let postSaveDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        var scrollsUp = false
        while ContinuousClock.now < postSaveDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "Recipe persistence and query merging must not freeze the recipes list after save."
            )
            scrollsUp.toggle()
        }
        for _ in 0..<5 {
            app.swipeDown(velocity: .fast)
        }

        let customRecipe = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@",
            "Performance Spinach Mash"
        )).firstMatch
        XCTAssertTrue(customRecipe.waitForExistence(timeout: 4))
        customRecipe.tap()
        XCTAssertTrue(app.navigationBars["Performance Spinach Mash"].waitForExistence(timeout: 4))

        let delete = app.buttons["solids.custom-recipe.delete"]
        for _ in 0..<5 where !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let confirmDelete = app.buttons["Delete Recipe"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 3))
        let deleteStartedAt = ContinuousClock.now
        confirmDelete.tap()
        XCTAssertTrue(app.navigationBars["Solids Recipes"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            deleteStartedAt.duration(to: .now),
            .seconds(4),
            "Deleting one custom recipe must not scan or invalidate unrelated recipe and plan data."
        )

        let postDeleteScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            postDeleteScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "The recipes list must accept scrolling immediately after a custom recipe is deleted."
        )
        let postDeleteDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        scrollsUp = false
        while ContinuousClock.now < postDeleteDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "Recipe deletion and query merging must not freeze the recipes list at a later callback boundary."
            )
            scrollsUp.toggle()
        }
        XCTAssertFalse(customRecipe.exists)
    }

    func testProductionScaleAdultHealthKeepsNavigationAndMetricsResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000103/today")

        XCTAssertTrue(app.buttons["Sample Adult settings"].waitForExistence(timeout: 12))
        let reportsStartedAt = ContinuousClock.now
        app.tabBars.buttons["Reports"].tap()
        let reportsDestination = app.navigationBars.matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@",
            "Reports",
            "Health Log"
        )).firstMatch
        XCTAssertTrue(reportsDestination.waitForExistence(timeout: 4))
        XCTAssertLessThan(
            reportsStartedAt.duration(to: .now),
            .seconds(4),
            "Six thousand Adult Care observations must not delay opening Reports."
        )

        // Reports remembers its last segment across launches. Return to Day so
        // the measured Summary transition always constructs Adult Care anew.
        let day = app.buttons["Day"]
        XCTAssertTrue(day.waitForExistence(timeout: 3))
        day.tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 3))

        let summary = app.buttons["Summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        let healthLogStartedAt = ContinuousClock.now
        summary.tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.descendants(matching: .any)["adult-health.overview"].exists
        )
        XCTAssertLessThan(
            healthLogStartedAt.duration(to: .now),
            .seconds(4),
            "Adult Care must fetch bounded overview data instead of materializing the full history."
        )

        let reportPeriodPicker = app.segmentedControls["adult-report.period-picker"]
        XCTAssertTrue(reportPeriodPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(reportPeriodPicker.buttons["Week"].exists)
        XCTAssertTrue(reportPeriodPicker.buttons["Month"].exists)
        XCTAssertTrue(reportPeriodPicker.buttons["Year"].exists)

        let annualSummaryStartedAt = ContinuousClock.now
        reportPeriodPicker.buttons["Year"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["adult-report.medication-count"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["adult-report.pain-count"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["adult-report.blood-pressure-count"].exists
        )
        XCTAssertLessThan(
            annualSummaryStartedAt.duration(to: .now),
            .seconds(5),
            "The annual medication, pain, and blood-pressure summary must load without blocking Reports."
        )

        let initialScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            initialScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Adult Care should accept scrolling as soon as the health log opens."
        )

        // Return to the top, then explicitly load a secondary trend. Reports
        // keeps this work collapsed until requested so medication, pain, and
        // blood-pressure summaries do not perform a duplicate query at launch.
        let additionalTrends = app.descendants(matching: .any)[
            "adult-report.additional-trends-toggle"
        ]
        for _ in 0..<8 where !(additionalTrends.exists && additionalTrends.isHittable) {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(additionalTrends.waitForExistence(timeout: 3))
        XCTAssertTrue(additionalTrends.isHittable)
        additionalTrends.tap()

        let metricPicker = app.descendants(matching: .any)["adult-health.metric-picker"]
        for _ in 0..<8 where !(metricPicker.exists && metricPicker.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(metricPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(metricPicker.isHittable)
        metricPicker.tap()
        let heartRate = app.buttons["Heart rate"]
        XCTAssertTrue(heartRate.waitForExistence(timeout: 3))
        let metricStartedAt = ContinuousClock.now
        heartRate.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["adult-health.trend-loaded.heartRate"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertLessThan(
            metricStartedAt.duration(to: .now),
            .seconds(3),
            "Changing the Adult Care metric must fetch only its bounded trend."
        )

        let postMetricScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            postMetricScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Rendering a daily annual Adult Care trend must not block scrolling."
        )

        let bloodPressureSection = app.descendants(matching: .any)[
            "adult-report.blood-pressure"
        ]
        for _ in 0..<14 where !bloodPressureSection.exists {
            let reportScrollStartedAt = ContinuousClock.now
            app.swipeUp(velocity: .fast)
            XCTAssertLessThan(
                reportScrollStartedAt.duration(to: .now),
                .seconds(3.5),
                "Daily annual chart points must keep each Reports scroll responsive."
            )
        }
        XCTAssertTrue(bloodPressureSection.waitForExistence(timeout: 4))
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

    func testAppointmentEditorUsesPersistentFieldsWithoutDecorativePresets() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://appointment/00000000-0000-0000-0000-000000000301")

        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Appointment"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fast presets"].exists)

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

    func testAppointmentAddressAndNotesAreResponsiveOnColdEditorLoad() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")

        func openColdEditor(fieldIdentifier: String) -> XCUIElement {
            launch(startURL: "littlewindows://appointments")
            XCTAssertTrue(app.navigationBars["Appointments"].waitForExistence(timeout: 8))
            let add = app.buttons["Add"]
            XCTAssertTrue(add.waitForExistence(timeout: 4))
            add.tap()
            XCTAssertTrue(app.navigationBars["Add Appointment"].waitForExistence(timeout: 4))

            let field = app.descendants(matching: .any)
                .matching(identifier: fieldIdentifier)
                .firstMatch
            for _ in 0..<8 where !field.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(field.waitForExistence(timeout: 4))
            XCTAssertTrue(field.isHittable)
            return field
        }

        func assertResponsive(_ field: XCUIElement, text: String) {
            let focusStartedAt = Date()
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            let focusDuration = Date().timeIntervalSince(focusStartedAt)

            let typingStartedAt = Date()
            field.typeText(text)
            let typingDuration = Date().timeIntervalSince(typingStartedAt)

            XCTAssertEqual(field.value as? String, text)
            XCTAssertLessThan(focusDuration, 2.5, "Field focus took \(focusDuration)s")
            XCTAssertLessThan(typingDuration, 2.5, "Field typing took \(typingDuration)s")
        }

        assertResponsive(
            openColdEditor(fieldIdentifier: "appointment.address"),
            text: "123 Main Street"
        )
        assertResponsive(
            openColdEditor(fieldIdentifier: "appointment.notes"),
            text: "Bring recent records"
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

    func testFoodDetailShowsCompleteNutritionWithoutStartingALog() {
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
        XCTAssertFalse(app.navigationBars["Add Event"].exists)

        let expectedNutrients: [(identifier: String, value: String)] = [
            ("calories", "160 kcal"),
            ("protein", "2 g"),
            ("fat", "14.7 g"),
            ("fiber", "6.7 g"),
            ("iron", "0.55 mg"),
            ("zinc", "0.64 mg"),
            ("calcium", "12 mg"),
            ("vitamin-c", "10 mg")
        ]

        for expected in expectedNutrients {
            let row = app.descendants(matching: .any)[
                "solids.food.nutrition.\(expected.identifier)"
            ]
            for _ in 0..<12 where !row.exists {
                app.swipeUp()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 3), expected.identifier)
            XCTAssertTrue(
                row.label.contains(expected.value),
                "Expected \(row.label) to show \(expected.value)."
            )
        }

        XCTAssertTrue(app.staticTexts["All eight tracked nutrients are included."].exists)
        let source = app.descendants(matching: .any)["solids.food.nutrition.source"]
        for _ in 0..<3 where !source.exists {
            app.swipeUp()
        }
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertTrue(source.label.contains("USDA FoodData Central"))
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
        XCTAssertTrue(app.staticTexts["Delete planned meal?"].waitForExistence(timeout: 4))
        let confirmDelete = app.buttons["Delete Planned Meal"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 2))
        confirmDelete.tap()
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
        XCTAssertTrue(app.staticTexts["Child care"].exists)
        XCTAssertFalse(app.staticTexts["Daily care"].exists)
        XCTAssertFalse(app.staticTexts["Share care"].exists)
        XCTAssertFalse(app.staticTexts["Feeding"].exists)
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

    func testCareExportEntryOpensPDFReportForSelectedProfile() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://care")

        let exportReport = app.buttons["care.export-report"]
        XCTAssertTrue(exportReport.waitForExistence(timeout: 8))
        exportReport.tap()

        XCTAssertTrue(app.navigationBars["Care Report Export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample Child"].waitForExistence(timeout: 3))
        let pdfFormat = app.buttons["PDF"]
        XCTAssertTrue(pdfFormat.waitForExistence(timeout: 3))
        if !pdfFormat.isSelected {
            pdfFormat.tap()
        }
        let exportPDF = app.buttons["Export PDF Report"]
        for _ in 0..<3 where !exportPDF.exists {
            app.swipeUp()
        }
        XCTAssertTrue(exportPDF.waitForExistence(timeout: 3))
    }

    func testAdultCareStoryBuildsEpisodeIntelligenceAndRemainsResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://profile/00000000-0000-0000-0000-000000000103/today")
        XCTAssertTrue(app.buttons["Sample Adult settings"].waitForExistence(timeout: 12))

        app.tabBars.buttons["Care"].tap()
        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 4))
        let careStory = app.buttons["care.story"]
        XCTAssertTrue(careStory.waitForExistence(timeout: 4))

        let careHubAttachment = XCTAttachment(screenshot: app.screenshot())
        careHubAttachment.name = "Compact adult Care hub"
        careHubAttachment.lifetime = .keepAlways
        add(careHubAttachment)

        let navigationStartedAt = ContinuousClock.now
        careStory.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Care Story"].waitForExistence(timeout: 4))
        XCTAssertLessThan(
            navigationStartedAt.duration(to: .now),
            .seconds(4),
            "A large adult history must not delay opening Care Story."
        )
        let storyContentStartedAt = ContinuousClock.now

        XCTAssertTrue(
            app.descendants(matching: .any)["care-story.safety-note"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.segmentedControls["care-story.period-picker"].exists)
        XCTAssertFalse(app.segmentedControls["care-story.view-picker"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["care-story.chart"].exists)
        XCTAssertFalse(app.buttons["care-story.focus.symptom"].exists)

        for _ in 0..<3
            where !app.descendants(matching: .any)["care-story.chapter-hero"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["care-story.chapter-hero"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertLessThan(
            storyContentStartedAt.duration(to: .now),
            .seconds(4),
            "Production-scale Care Story chapters must become usable promptly."
        )

        let periodPicker = app.segmentedControls["care-story.period-picker"]
        let thirtyDayPeriod = periodPicker.buttons["30d"]
        let ninetyDayPeriod = periodPicker.buttons["90d"]
        XCTAssertTrue(thirtyDayPeriod.exists)
        XCTAssertTrue(ninetyDayPeriod.exists)
        thirtyDayPeriod.tap()
        let thirtyDayStory = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND value == %@",
                "care-story.chapter-hero",
                "30-day story"
            )
        ).firstMatch
        XCTAssertTrue(thirtyDayStory.waitForExistence(timeout: 5))

        let cachedPeriodStartedAt = ContinuousClock.now
        ninetyDayPeriod.tap()
        let ninetyDayStory = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND value == %@",
                "care-story.chapter-hero",
                "90-day story"
            )
        ).firstMatch
        XCTAssertTrue(ninetyDayStory.exists)
        XCTAssertFalse(app.descendants(matching: .any)["care-story.loading"].exists)
        XCTAssertLessThan(
            cachedPeriodStartedAt.duration(to: .now),
            .seconds(2),
            "Returning to a previously built story window should not rebuild its snapshot."
        )
        XCTAssertTrue(app.staticTexts["Care review"].waitForExistence(timeout: 3))

        for _ in 0..<3
            where !app.descendants(matching: .any)["care-story.change-pulse"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["care-story.change-pulse"]
                .waitForExistence(timeout: 4)
        )

        let populatedPulseCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "care-story.pulse-cell.")
        ).firstMatch
        for _ in 0..<3 where !populatedPulseCell.exists {
            app.swipeUp()
        }
        XCTAssertTrue(populatedPulseCell.waitForExistence(timeout: 4))
        populatedPulseCell.tap()
        XCTAssertTrue(app.navigationBars["Day Details"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.descendants(matching: .any)["care-story.pulse-records"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["Open Health Log"].exists)
        app.navigationBars["Day Details"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Care Story"].waitForExistence(timeout: 3))

        let reviewSources = app.buttons["care-story.review-sources"]
        for _ in 0..<8 {
            if reviewSources.waitForExistence(timeout: 0.75) { break }
            app.swipeUp()
        }
        XCTAssertTrue(reviewSources.waitForExistence(timeout: 4))
        reviewSources.tap()
        XCTAssertTrue(app.navigationBars["Story evidence"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.descendants(matching: .any)["care-story.source-records"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "These are the exact records counted in this chapter’s 14-day pulse."
                )
            ).firstMatch.exists
        )
        app.navigationBars["Story evidence"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Care Story"].waitForExistence(timeout: 3))

        let chapterAttachment = XCTAttachment(screenshot: app.screenshot())
        chapterAttachment.name = "Adult Care Story episode pulse"
        chapterAttachment.lifetime = .keepAlways
        add(chapterAttachment)

        let domainShifts = app.descendants(matching: .any)["care-story.domain-shifts"]
        for _ in 0..<6 {
            if domainShifts.waitForExistence(timeout: 0.75) { break }
            app.swipeUp()
        }
        XCTAssertTrue(domainShifts.waitForExistence(timeout: 4))

        let addToAppointment = app.buttons["care-story.add-to-appointment"]
        for _ in 0..<6 {
            if addToAppointment.waitForExistence(timeout: 0.75) { break }
            app.swipeUp()
        }
        XCTAssertTrue(addToAppointment.waitForExistence(timeout: 4))
        addToAppointment.tap()
        XCTAssertTrue(app.alerts["Care Story"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.alerts["Care Story"].staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Upcoming follow-up")
            ).firstMatch.exists
        )
        app.alerts["Care Story"].buttons["OK"].tap()

        let shareChapter = app.buttons["care-story.share-chapter"]
        for _ in 0..<4 {
            if shareChapter.waitForExistence(timeout: 0.75) { break }
            app.swipeUp()
        }
        XCTAssertTrue(shareChapter.waitForExistence(timeout: 4))

        let scrollOptions = XCTMeasureOptions()
        scrollOptions.iterationCount = 3
        measure(
            metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric],
            options: scrollOptions
        ) {
            app.swipeDown(velocity: .fast)
            app.swipeUp(velocity: .fast)
        }
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
        let eggAllergen = app.buttons["solid-allergen.egg"]
        for _ in 0..<8 where !eggAllergen.exists {
            app.swipeUp()
        }
        XCTAssertTrue(eggAllergen.waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["Delete planned meal?"].waitForExistence(timeout: 4))
        let confirmDelete = app.buttons["Delete Planned Meal"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 2))
        confirmDelete.tap()

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
        let rename = app.buttons["Rename Early days"]
        XCTAssertTrue(rename.waitForExistence(timeout: 4))
        rename.tap()
        let renamedField = app.textFields["List name"]
        XCTAssertTrue(
            renamedField.waitForExistence(timeout: 4),
            "The rename alert should present when the action sheet actually finishes dismissing."
        )
        XCTAssertEqual(renamedField.value as? String, "Early days")
        app.buttons["Cancel"].tap()
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
        XCTAssertTrue(app.staticTexts["Remove Produce?"].waitForExistence(timeout: 4))
        let removeSection = app.buttons["Remove Section"]
        XCTAssertTrue(removeSection.waitForExistence(timeout: 2))
        removeSection.tap()
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

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://quick-log/sleep")

        let nap = app.buttons["Nap"]
        XCTAssertTrue(nap.waitForExistence(timeout: 4))
        nap.tap()

        XCTAssertTrue(
            app.staticTexts["Running"].waitForExistence(timeout: 5),
            "Starting sleep should immediately show the active timer editor."
        )
        assertActiveTimerTicksContinuously()
        XCTAssertTrue(app.buttons["Stop"].exists)
    }

    func testStartingNonSleepTimerOpensRunningTimerEditor() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://quick-log/pumping")

        XCTAssertTrue(
            app.staticTexts["Pumping"].waitForExistence(timeout: 5),
            "Starting a non-sleep timer should immediately show its active timer editor."
        )
        XCTAssertTrue(app.staticTexts["Running"].exists)
        XCTAssertTrue(app.buttons["Stop"].exists)
    }

    func testPausedTimerEditorFinishAndSaveCommitsEvent() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://quick-log/sleep")

        let nap = app.buttons["Nap"]
        XCTAssertTrue(nap.waitForExistence(timeout: 5))
        nap.tap()

        let stop = app.scrollViews.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 4))

        let adjustStart = app.buttons["−1 min"]
        for _ in 0..<4 where !adjustStart.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(adjustStart.waitForExistence(timeout: 4))
        XCTAssertTrue(adjustStart.isHittable)
        adjustStart.tap()

        let finishAndSave = app.buttons["active-timer.finish-and-save"]
        for _ in 0..<4 where !finishAndSave.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(finishAndSave.waitForExistence(timeout: 4))
        XCTAssertTrue(finishAndSave.isHittable)
        finishAndSave.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        let scrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            scrollStartedAt.duration(to: .now),
            // XCUI's synthesized fast swipe takes about 2.7 seconds on the
            // current simulator runtime even when the app is fully idle.
            .seconds(3.5),
            "Today should accept scrolling immediately after a timer is saved."
        )
        XCTAssertFalse(
            app.staticTexts["Stopped · Ready to save"].exists,
            "Finishing in the editor must remove the paused timer from Today without a second save."
        )

        let postSaveDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        var scrollsUp = false
        while ContinuousClock.now < postSaveDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "Prediction, persistence, or system-surface work must not freeze Today at any point after a timer save."
            )
            scrollsUp.toggle()
        }

        let savedSleep = app.buttons["today-timeline.event.sleep"].firstMatch
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<8 where !elementIsClearOfTabBar(savedSleep, tabBar: tabBar) {
            app.swipeUp()
        }
        XCTAssertTrue(savedSleep.waitForExistence(timeout: 3))
        XCTAssertTrue(savedSleep.isHittable)
        XCTAssertTrue(
            elementIsClearOfTabBar(savedSleep, tabBar: tabBar),
            "The saved timer row must be visibly above the tab bar before testing its swipe action."
        )
        let savedEventID = savedSleep.value as? String
        let revealDeleteStartedAt = ContinuousClock.now
        savedSleep.swipeLeft()
        XCTAssertLessThan(
            revealDeleteStartedAt.duration(to: .now),
            .seconds(3.5),
            "The saved timer row must accept its delete swipe without waiting for background work."
        )
        let deleteAction = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 2))
        deleteAction.tap()

        XCTAssertTrue(app.staticTexts["Delete event?"].waitForExistence(timeout: 2))
        let confirmDelete = app.buttons["Delete Sleep"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 2))
        confirmDelete.tap()

        let postDeleteScrollStartedAt = ContinuousClock.now
        app.swipeDown(velocity: .fast)
        XCTAssertLessThan(
            postDeleteScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Today must remain scrollable immediately after an event is deleted."
        )
        if let savedEventID {
            XCTAssertFalse(
                app.buttons.matching(NSPredicate(format: "value == %@", savedEventID)).firstMatch.exists,
                "The deleted event should disappear from Today before persistence reconciliation."
            )
        }

        let postDeleteDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        scrollsUp = true
        while ContinuousClock.now < postDeleteDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "SwiftData deletion and related reconciliation must not freeze Today at any later callback boundary."
            )
            scrollsUp.toggle()
        }
        if let savedEventID {
            XCTAssertFalse(
                app.buttons.matching(NSPredicate(format: "value == %@", savedEventID)).firstMatch.exists,
                "The deleted event must stay removed after persistence reconciliation."
            )
        }
    }

    func testPausingTimerThenReturningKeepsTodayImmediatelyScrollable() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.buttons["Nap"].waitForExistence(timeout: 5))
        app.buttons["Nap"].tap()

        assertActiveTimerTicksContinuously()

        let stop = app.scrollViews.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let pauseStartedAt = ContinuousClock.now
        stop.tap()
        // `tap()` already waits for the app's interaction transaction to
        // settle. A second multi-second existence wait adds XCUI's one-second
        // polling quantum to the measured app latency and can fail even when
        // the stopped state is already rendered.
        XCTAssertTrue(app.staticTexts["Stopped"].exists)
        XCTAssertLessThan(
            pauseStartedAt.duration(to: .now),
            .seconds(2.5),
            "Pausing must update the editor without running broad reconciliation first."
        )

        let editorScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            editorScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "The timer editor should accept scrolling immediately after Stop."
        )
        let finishAndSave = app.buttons["active-timer.finish-and-save"]
        XCTAssertTrue(finishAndSave.waitForExistence(timeout: 2))
        XCTAssertTrue(
            finishAndSave.isHittable,
            "Finish & Save should be reachable without waiting for persistence or widget refreshes."
        )

        app.navigationBars["Timer"].buttons["Keep Timer"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Stopped · Ready to save"].exists)
        let scrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            scrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Today should accept scrolling immediately after a timer is paused."
        )
    }

    func testStoppingTimerFromTodayCardKeepsTodayImmediatelyScrollable() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.buttons["Nap"].waitForExistence(timeout: 5))
        app.buttons["Nap"].tap()
        assertActiveTimerTicksContinuously()

        let keepTimer = app.navigationBars["Timer"].buttons["Keep Timer"]
        XCTAssertTrue(keepTimer.waitForExistence(timeout: 3))
        keepTimer.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        let sleepTimerStatus = app.staticTexts["active-timer.status.sleep"]
        XCTAssertEqual(sleepTimerStatus.label, "Running now")

        let stop = app.buttons["active-timer.toggle.sleep"]
        XCTAssertTrue(stop.waitForExistence(timeout: 3))
        let stopStartedAt = ContinuousClock.now
        stop.tap()
        XCTAssertEqual(sleepTimerStatus.label, "Stopped · Ready to save")
        XCTAssertLessThan(
            stopStartedAt.duration(to: .now),
            .seconds(2),
            "Stopping from the Today card must update without blocking on persistence or integrations."
        )

        let scrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            scrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Today should accept scrolling immediately after Stop is tapped on the timer card."
        )

        let timerSurfaceRefreshSettled = expectation(description: "Timer surface refresh started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            timerSurfaceRefreshSettled.fulfill()
        }
        wait(for: [timerSurfaceRefreshSettled], timeout: 3)
        let postRefreshScrollStartedAt = ContinuousClock.now
        app.swipeDown(velocity: .fast)
        XCTAssertLessThan(
            postRefreshScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Widget and Live Activity refresh must not freeze Today after Stop."
        )
    }

    func testDiscardingPausedTimerKeepsTodayImmediatelyScrollable() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-smoke")
        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.buttons["Nap"].waitForExistence(timeout: 5))
        app.buttons["Nap"].tap()

        assertActiveTimerTicksContinuously()

        let stop = app.scrollViews.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 2))

        let discard = app.buttons["Discard Timer"].firstMatch
        for _ in 0..<5 where !discard.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(discard.isHittable)
        discard.tap()

        XCTAssertTrue(app.staticTexts["Discard Timer?"].waitForExistence(timeout: 3))
        let confirmDiscard = app.buttons["Discard Timer"].firstMatch
        XCTAssertTrue(confirmDiscard.waitForExistence(timeout: 3))
        confirmDiscard.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        let scrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            scrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Today should accept scrolling immediately after a timer is discarded."
        )
        let sleepTimerStatus = app.staticTexts["active-timer.status.sleep"]
        XCTAssertFalse(
            sleepTimerStatus.exists,
            "A discarded timer must not be resurrected as running on Today."
        )

        let delayedRefreshSettled = expectation(description: "Delayed timer refresh settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            delayedRefreshSettled.fulfill()
        }
        wait(for: [delayedRefreshSettled], timeout: 10)
        XCTAssertFalse(
            sleepTimerStatus.exists,
            "Delayed persistence or widget reconciliation must not restore a discarded timer."
        )
        let delayedScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            delayedScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Deferred persistence must not freeze Today several seconds after discard."
        )
    }

    func testDiscardingRunningTimerRemovesItFromTodayImmediately() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.buttons["Nap"].waitForExistence(timeout: 5))
        app.buttons["Nap"].tap()
        assertActiveTimerTicksContinuously()

        let discard = app.buttons["Discard Timer"].firstMatch
        for _ in 0..<5 where !discard.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(discard.isHittable)
        discard.tap()

        XCTAssertTrue(app.staticTexts["Discard Timer?"].waitForExistence(timeout: 3))
        let confirmDiscard = app.buttons["Discard Timer"].firstMatch
        XCTAssertTrue(confirmDiscard.waitForExistence(timeout: 3))
        confirmDiscard.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        XCTAssertFalse(
            app.staticTexts["active-timer.status.sleep"].waitForExistence(timeout: 1),
            "Discarding a running timer must remove it from Today immediately."
        )

        let scrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            scrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Today must remain scrollable after discarding a running timer."
        )

        let timerSurfaceRefreshSettled = expectation(description: "Discard surface refresh started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            timerSurfaceRefreshSettled.fulfill()
        }
        wait(for: [timerSurfaceRefreshSettled], timeout: 3)
        let postRefreshScrollStartedAt = ContinuousClock.now
        app.swipeDown(velocity: .fast)
        XCTAssertLessThan(
            postRefreshScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Discard reconciliation must not freeze Today after dismissal."
        )
    }

    func testProductionScaleTimerPauseDiscardKeepsTodayResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.buttons["Nap"].waitForExistence(timeout: 5))
        app.buttons["Nap"].tap()

        assertActiveTimerTicksContinuously()

        // Exercise the compact Today card, which is where a delayed SwiftData
        // merge previously interrupted an already-active scroll gesture.
        let sheetTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let sheetBottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        sheetTop.press(forDuration: 0.05, thenDragTo: sheetBottom)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))

        let stop = app.buttons["active-timer.toggle.sleep"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let pauseStartedAt = ContinuousClock.now
        stop.tap()
        XCTAssertTrue(app.staticTexts["active-timer.status.sleep"].label.contains("Stopped"))
        XCTAssertLessThan(
            pauseStartedAt.duration(to: .now),
            .seconds(2.5),
            "A production-scale history must not delay pausing a timer."
        )

        let scrollingDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        var scrollsUp = true
        while ContinuousClock.now < scrollingDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "A delayed timer persistence or system-surface callback must not freeze Today."
            )
            scrollsUp.toggle()
        }

        for _ in 0..<8 where !app.staticTexts["active-timer.status.sleep"].isHittable {
            app.swipeDown(velocity: .fast)
        }
        let timerStatus = app.staticTexts["active-timer.status.sleep"]
        XCTAssertTrue(timerStatus.isHittable)
        timerStatus.tap()

        let discard = app.buttons["Discard Timer"].firstMatch
        for _ in 0..<5 where !discard.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(discard.isHittable)
        discard.tap()

        XCTAssertTrue(app.staticTexts["Discard Timer?"].waitForExistence(timeout: 3))
        let confirmDiscard = app.buttons["Discard Timer"].firstMatch
        XCTAssertTrue(confirmDiscard.waitForExistence(timeout: 3))
        confirmDiscard.tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))
        let postDiscardDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        scrollsUp = true
        while ContinuousClock.now < postDiscardDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "Discard completion work must not freeze Today several seconds later."
            )
            scrollsUp.toggle()
        }
        XCTAssertFalse(app.staticTexts["active-timer.status.sleep"].exists)
    }

    func testProductionScaleTimerStartTimeEditingStaysResponsive() {
        continueAfterFailure = false

        launch(startURL: "littlewindows://debug/reset-empty")
        launch(startURL: "littlewindows://debug/seed-performance")
        launch(startURL: "littlewindows://quick-log/sleep")

        XCTAssertTrue(app.buttons["Nap"].waitForExistence(timeout: 5))
        app.buttons["Nap"].tap()
        assertActiveTimerTicksContinuously()

        let adjustStart = app.buttons["−5 min"]
        for _ in 0..<5 where !adjustStart.isHittable {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(adjustStart.waitForExistence(timeout: 3))
        XCTAssertTrue(adjustStart.isHittable)

        // Date controls can publish a stream of intermediate values. Every tap
        // must remain an editor-local change rather than synchronously queuing a
        // store save, widget refresh, prediction scan, and Live Activity update.
        for _ in 0..<6 {
            let adjustmentStartedAt = ContinuousClock.now
            adjustStart.tap()
            XCTAssertLessThan(
                adjustmentStartedAt.duration(to: .now),
                .seconds(1.5),
                "Backdating an active timer must stay responsive on every intermediate edit."
            )
        }
        assertActiveTimerTicksContinuously()

        let editorScrollStartedAt = ContinuousClock.now
        app.swipeUp(velocity: .fast)
        XCTAssertLessThan(
            editorScrollStartedAt.duration(to: .now),
            .seconds(3.5),
            "Editing a timer start time must not leave persistence work blocking the timer editor."
        )

        let keepTimer = app.navigationBars["Timer"].buttons["Keep Timer"]
        XCTAssertTrue(keepTimer.waitForExistence(timeout: 3))
        keepTimer.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 4))

        let scrollingDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        var scrollsUp = true
        while ContinuousClock.now < scrollingDeadline {
            let gestureStartedAt = ContinuousClock.now
            if scrollsUp {
                app.swipeUp(velocity: .fast)
            } else {
                app.swipeDown(velocity: .fast)
            }
            XCTAssertLessThan(
                gestureStartedAt.duration(to: .now),
                .seconds(4.5),
                "Persisting the final backdated start must not freeze Today later."
            )
            scrollsUp.toggle()
        }
        for _ in 0..<5 where !app.staticTexts["active-timer.status.sleep"].exists {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(app.staticTexts["active-timer.status.sleep"].exists)
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
        XCTAssertTrue(app.staticTexts["Archive Trip?"].waitForExistence(timeout: 3))
        let confirmArchiveTrip = app.buttons["Archive Trip"]
        XCTAssertTrue(confirmArchiveTrip.waitForExistence(timeout: 3))
        confirmArchiveTrip.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["trip.detail"].waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["trips.home"].waitForExistence(timeout: 5))
        let archivedTrip = app.staticTexts["Automation Trip Copy"]
        XCTAssertTrue(archivedTrip.waitForExistence(timeout: 3))
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

    private func assertActiveTimerTicksContinuously() {
        let elapsed = app.staticTexts["active-timer.elapsed"]
        XCTAssertTrue(
            elapsed.waitForExistence(timeout: 1.5),
            "Expected the active timer elapsed display to appear immediately."
        )

        var observedSeconds: [Int] = []
        let deadline = Date().addingTimeInterval(3.4)
        while Date() < deadline {
            if let seconds = timerSeconds(from: elapsed.label),
               observedSeconds.last != seconds {
                observedSeconds.append(seconds)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }

        XCTAssertGreaterThanOrEqual(
            observedSeconds.count,
            3,
            "The timer must repaint continuously; observed only \(observedSeconds)."
        )
        for (previous, current) in zip(observedSeconds, observedSeconds.dropFirst()) {
            XCTAssertGreaterThan(current, previous)
            XCTAssertLessThanOrEqual(
                current - previous,
                2,
                "The timer stalled and jumped from \(previous)s to \(current)s instead of incrementing each second."
            )
        }
    }

    private func timerSeconds(from label: String) -> Int? {
        let components = label.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return components[0] * 3_600 + components[1] * 60 + components[2]
    }

    private func elementIsClearOfTabBar(
        _ element: XCUIElement,
        tabBar: XCUIElement
    ) -> Bool {
        guard element.exists, element.isHittable else { return false }
        guard tabBar.exists else { return true }
        return element.frame.maxY <= tabBar.frame.minY - 8
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
