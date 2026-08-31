import XCTest
import simd
@testable import LittleWindows

final class BodyLocationTests: XCTestCase {
    func testRadiatingPathPreservesOrderAndStopsAtFourSelections() throws {
        var record = BodyLocationRecord(
            modelVariant: .neutral,
            pattern: .radiating
        )
        let structureIDs = [
            "body.lowerBack",
            "body.buttock.left",
            "body.posteriorThigh.left",
            "body.calf.left",
            "body.foot.left"
        ]

        for structureID in structureIDs.prefix(4) {
            XCTAssertEqual(
                record.toggle(try structure(structureID)),
                .added
            )
        }

        XCTAssertEqual(record.toggle(try structure(structureIDs[4])), .limitReached)
        XCTAssertEqual(record.selections.map(\.structureID), Array(structureIDs.prefix(4)))
        XCTAssertEqual(
            record.summary,
            "Radiates: Lower back → Left buttock → Left back of thigh → Left calf"
        )
    }

    func testSpotPatternReplacesThePreviousSelection() throws {
        var record = BodyLocationRecord(modelVariant: .female, pattern: .spot)

        XCTAssertEqual(record.toggle(try structure("body.head")), .added)
        XCTAssertEqual(record.toggle(try structure("joint.knee.right")), .replaced)

        XCTAssertEqual(record.selections.map(\.structureID), ["joint.knee.right"])
        XCTAssertEqual(record.summary, "Right knee joint")
    }

    func testSexAwareOrganCatalogUsesProfileAnatomy() {
        let femaleIDs = organIDs(for: .female)
        let maleIDs = organIDs(for: .male)
        let neutralIDs = organIDs(for: .neutral)

        XCTAssertTrue(femaleIDs.contains("organ.uterus"))
        XCTAssertTrue(femaleIDs.contains("organ.ovary.left"))
        XCTAssertFalse(femaleIDs.contains("organ.prostate"))

        XCTAssertTrue(maleIDs.contains("organ.prostate"))
        XCTAssertFalse(maleIDs.contains("organ.uterus"))

        XCTAssertFalse(neutralIDs.contains("organ.uterus"))
        XCTAssertFalse(neutralIDs.contains("organ.prostate"))
        XCTAssertTrue(neutralIDs.contains("organ.heart"))
    }

    func testProfileSexSelectsExpectedModelVariant() {
        XCTAssertEqual(BodyModelVariant(profileSex: .female), .female)
        XCTAssertEqual(BodyModelVariant(profileSex: .male), .male)
        XCTAssertEqual(BodyModelVariant(profileSex: .unknown), .neutral)
    }

    func testProfileSexChangeUpdatesModelAndDropsOnlyUnavailableAnatomy() throws {
        var record = BodyLocationRecord(
            modelVariant: .female,
            pattern: .multiple,
            selections: [
                BodyLocationSelection(structure: try structure("organ.uterus")),
                BodyLocationSelection(structure: try structure("organ.heart"))
            ]
        )

        record.adoptProfileSex(.male)

        XCTAssertEqual(record.modelVariant, .male)
        XCTAssertEqual(record.selections.map(\.structureID), ["organ.heart"])
    }

    func testDiffuseWithoutASelectionPersistsAndClearResetsTheRecord() {
        var record = BodyLocationRecord(modelVariant: .neutral, pattern: .diffuse)

        XCTAssertTrue(record.hasValue)
        XCTAssertEqual(record.summary, "Diffuse")

        record.clear()

        XCTAssertFalse(record.hasValue)
        XCTAssertEqual(record.pattern, .spot)
        XCTAssertNil(record.summary)
    }

    func testSwitchingToSpotKeepsOnlyTheFirstLocation() throws {
        var record = BodyLocationRecord(modelVariant: .neutral, pattern: .multiple)
        XCTAssertEqual(record.toggle(try structure("body.lowerBack")), .added)
        XCTAssertEqual(record.toggle(try structure("body.calf.left")), .added)

        record.pattern = .spot

        XCTAssertEqual(record.selections.map(\.structureID), ["body.lowerBack"])
    }

    func testBodyLocationRecordRoundTripsAndKeepsDisplaySnapshot() throws {
        let unknownStructure = BodyLocationSelection(
            structureID: "future.structure",
            layerRawValue: BodyAnatomyLayer.nerves.rawValue,
            displayNameSnapshot: "Saved structure name"
        )
        let original = BodyLocationRecord(
            modelVariant: .neutral,
            pattern: .multiple,
            selections: [unknownStructure],
            customText: "  more detail  "
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BodyLocationRecord.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.summary, "Saved structure name · more detail")
    }

    func testLegacyHealthDetailsDecodeWithoutStructuredLocations() throws {
        let data = try XCTUnwrap(
            """
            {
              "symptomName": "Headache",
              "symptomBodyLocation": "Behind left eye",
              "painScore": 4,
              "painLocation": "Lower back"
            }
            """.data(using: .utf8)
        )

        let details = try JSONDecoder().decode(HealthObservationDetails.self, from: data)

        XCTAssertNil(details.symptomBodyLocationRecord)
        XCTAssertNil(details.painBodyLocationRecord)
        XCTAssertEqual(details.symptomLocationSummary, "Behind left eye")
        XCTAssertEqual(details.painLocationSummary, "Lower back")
    }

    func testStructuredSummaryTakesPriorityOverLegacyFallback() throws {
        let selected = BodyLocationSelection(structure: try structure("nerve.sciatic.left"))
        let details = HealthObservationDetails(
            symptomBodyLocation: "Legacy text",
            symptomBodyLocationRecord: BodyLocationRecord(
                modelVariant: .female,
                pattern: .spot,
                selections: [selected]
            )
        )

        XCTAssertEqual(details.symptomLocationSummary, "Left sciatic nerve")
    }

    func testHealthDetailsRoundTripDiffuseLocationRecord() throws {
        let original = HealthObservationDetails(
            painLocation: "Diffuse",
            painBodyLocationRecord: BodyLocationRecord(
                modelVariant: .female,
                pattern: .diffuse
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthObservationDetails.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.painLocationSummary, "Diffuse")
    }

    func testHandDetailCatalogIncludesEachDigitAndInternalLayerTargets() {
        let identifiers = Set(BodyAnatomyCatalog.structures.map(\.id))

        for side in ["left", "right"] {
            XCTAssertTrue(identifiers.contains("body.thumb.\(side)"))
            XCTAssertTrue(identifiers.contains("body.indexFinger.\(side)"))
            XCTAssertTrue(identifiers.contains("body.middleFinger.\(side)"))
            XCTAssertTrue(identifiers.contains("body.ringFinger.\(side)"))
            XCTAssertTrue(identifiers.contains("body.littleFinger.\(side)"))
            XCTAssertTrue(identifiers.contains("muscle.hand.\(side)"))
            XCTAssertTrue(identifiers.contains("joint.thumb.\(side)"))
            XCTAssertTrue(identifiers.contains("joint.littleFinger.\(side)"))
            XCTAssertTrue(identifiers.contains("nerve.median.\(side)"))
            XCTAssertTrue(identifiers.contains("nerve.ulnar.\(side)"))
        }
    }

    func testCatalogCoversCommonPainSitesAcrossTheEntireBody() {
        let identifiers = Set(BodyAnatomyCatalog.structures.map(\.id))
        let expected: Set<String> = [
            "body.scalp", "body.forehead", "body.temple.left", "body.eye.left",
            "body.ear.left", "body.jaw.left", "body.throat", "body.backOfNeck",
            "body.collarbone.left", "body.sternum", "body.rib.left",
            "body.shoulderBlade.left", "body.midBack.left", "body.upperAbdomen.left",
            "body.navel", "body.lowerAbdomen.left", "body.flank.left", "body.sacrum",
            "body.tailbone", "body.groin.left", "body.shoulder.left",
            "body.posteriorUpperArm.left", "body.innerElbow.left",
            "body.backOfElbow.left", "body.outerForearm.left", "body.palm.left",
            "body.backOfHand.left", "body.innerThigh.left", "body.outerThigh.left",
            "body.backOfKnee.left", "body.shin.left", "body.innerAnkle.left",
            "body.outerAnkle.left", "body.heel.left", "body.sole.left",
            "muscle.neck.left", "muscle.deltoid.left", "muscle.rotatorCuff.left",
            "muscle.rhomboid.left", "muscle.latissimus.left", "muscle.oblique.left",
            "muscle.hipFlexor.left", "muscle.adductor.left", "muscle.itBand.left",
            "muscle.shin.left", "joint.tmj.left", "joint.thoracicSpine",
            "joint.sacrumCoccyx", "nerve.cervical.left", "nerve.radial.left",
            "nerve.intercostal.left", "nerve.sciatic.left"
        ]

        XCTAssertTrue(expected.isSubset(of: identifiers), expected.subtracting(identifiers).sorted().joined(separator: ", "))
        for leftID in expected.filter({ $0.hasSuffix(".left") }) {
            XCTAssertTrue(
                identifiers.contains(leftID.replacingOccurrences(of: ".left", with: ".right")),
                "Expected a right-side counterpart for \(leftID)."
            )
        }
    }

    func testExpandedSurfacePainZonesResolveFromDistinctAnatomicalTargets() {
        let scale: Float = 2.55
        let female = BodyModelVariant.female

        XCTAssertEqual(BodySurfaceMapper.headBodyAreaID(
            at: SIMD3<Float>(0.045, 0.75, 0.12) * scale,
            variant: female
        ), "body.eye.left")
        XCTAssertEqual(BodySurfaceMapper.headBodyAreaID(
            at: SIMD3<Float>(-0.08, 0.74, 0.10) * scale,
            variant: female
        ), "body.temple.right")
        XCTAssertEqual(BodySurfaceMapper.neckBodyAreaID(
            at: SIMD3<Float>(0, 0.625, -0.09) * scale,
            variant: female
        ), "body.backOfNeck")
        XCTAssertEqual(BodySurfaceMapper.upperTorsoBodyAreaID(
            at: SIMD3<Float>(0.10, 0.51, 0.12) * scale,
            variant: female
        ), "body.collarbone.left")
        XCTAssertEqual(BodySurfaceMapper.upperTorsoBodyAreaID(
            at: SIMD3<Float>(-0.11, 0.445, -0.12) * scale,
            variant: female
        ), "body.shoulderBlade.right")
        XCTAssertEqual(BodySurfaceMapper.lowerTorsoBodyAreaID(
            at: SIMD3<Float>(0.15, 0.15, -0.08) * scale,
            variant: female
        ), "body.flank.left")
        XCTAssertEqual(BodySurfaceMapper.pelvisBodyAreaID(
            at: SIMD3<Float>(0, -0.07, -0.10) * scale,
            variant: female
        ), "body.tailbone")
        XCTAssertEqual(BodySurfaceMapper.shoulderBodyAreaID(
            at: SIMD3<Float>(0.12, 0.515, 0.11) * scale,
            side: .left,
            variant: female
        ), "body.collarbone.left")
        XCTAssertEqual(BodySurfaceMapper.shoulderBodyAreaID(
            at: SIMD3<Float>(-0.19, 0.54, 0.08) * scale,
            side: .right,
            variant: female
        ), "body.shoulder.right")
        XCTAssertEqual(BodySurfaceMapper.upperLimbBodyAreaID(
            at: SIMD3<Float>(0.335, 0.135, -0.06) * scale,
            side: .left,
            variant: female
        ), "body.outerForearm.left")
        XCTAssertEqual(BodySurfaceMapper.upperLimbBodyAreaID(
            at: SIMD3<Float>(-0.465, -0.048, 0.07) * scale,
            side: .right,
            variant: female
        ), "body.palm.right")
        XCTAssertEqual(BodySurfaceMapper.lowerLimbBodyAreaID(
            at: SIMD3<Float>(0.075, -0.30, 0.07) * scale,
            side: .left,
            variant: female
        ), "body.innerThigh.left")
        XCTAssertEqual(BodySurfaceMapper.lowerLimbBodyAreaID(
            at: SIMD3<Float>(-0.09, -0.08, 0.07) * scale,
            side: .right,
            variant: female
        ), "body.groin.right")
        XCTAssertEqual(BodySurfaceMapper.lowerLimbBodyAreaID(
            at: SIMD3<Float>(-0.18, -0.45, 0.06) * scale,
            side: .right,
            variant: female
        ), "body.outerKnee.right")
        XCTAssertEqual(BodySurfaceMapper.lowerLimbBodyAreaID(
            at: SIMD3<Float>(0.12, -0.62, 0.07) * scale,
            side: .left,
            variant: female
        ), "body.shin.left")
    }

    func testJointSelectionUsesNearestAnatomicalLandmarkAndExactMarkerAnchor() {
        let rightElbow = BodySurfaceMapper.markerPosition(
            for: "joint.elbow.right",
            variant: .female
        )
        let nearbyTap = rightElbow + SIMD3<Float>(-0.07 * 2.55, -0.05 * 2.55, 0)

        XCTAssertEqual(
            BodySurfaceMapper.jointID(at: nearbyTap, variant: .female),
            "joint.elbow.right"
        )
        XCTAssertEqual(rightElbow.x, -0.270386 * 2.55, accuracy: 0.0001)
        XCTAssertEqual(rightElbow.y, 0.272200 * 2.55, accuracy: 0.0001)
    }

    func testMaleJointMarkerUsesTheSameRegistrationAsMaleHitTesting() {
        let leftWrist = BodySurfaceMapper.markerPosition(
            for: "joint.wrist.left",
            variant: .male
        )

        XCTAssertEqual(
            BodySurfaceMapper.jointID(at: leftWrist, variant: .male),
            "joint.wrist.left"
        )
    }

    func testLowerLimbSelectionBandsKeepKneeShinAndAnkleDistinct() {
        let scale: Float = 2.55

        XCTAssertEqual(
            BodySurfaceMapper.lowerLimbBodyAreaID(
                at: SIMD3<Float>(-0.12, -0.44, 0.08) * scale,
                side: .right,
                variant: .female
            ),
            "body.knee.right"
        )
        XCTAssertEqual(
            BodySurfaceMapper.lowerLimbBodyAreaID(
                at: SIMD3<Float>(-0.12, -0.60, 0.08) * scale,
                side: .right,
                variant: .female
            ),
            "body.shin.right"
        )
        XCTAssertEqual(
            BodySurfaceMapper.lowerLimbJointID(
                at: SIMD3<Float>(0.12, -0.60, 0.02) * scale,
                side: .left,
                variant: .female
            ),
            "joint.shin.left"
        )
        XCTAssertEqual(
            BodySurfaceMapper.lowerLimbJointID(
                at: SIMD3<Float>(0.14, -0.76, 0.02) * scale,
                side: .left,
                variant: .female
            ),
            "joint.ankle.left"
        )

        // Once a rendered segment proxy wins the hit test, neighboring height
        // bands must not reclassify its boundary pixels as the adjacent limb.
        XCTAssertEqual(
            BodySurfaceMapper.kneeBodyAreaID(
                at: SIMD3<Float>(-0.12, -0.36, 0.08) * scale,
                side: .right,
                variant: .female
            ),
            "body.knee.right"
        )
        XCTAssertEqual(
            BodySurfaceMapper.lowerLegBodyAreaID(
                at: SIMD3<Float>(0.12, -0.49, 0.08) * scale,
                side: .left,
                variant: .female
            ),
            "body.shin.left"
        )
    }

    func testEveryFullBodyJointMarkerResolvesBackToItsOwnMeshLandmark() {
        let structureIDs = [
            "joint.cervicalSpine", "joint.ribCage", "joint.lumbarSpine",
            "joint.shoulder.left", "joint.shoulder.right",
            "joint.elbow.left", "joint.elbow.right",
            "joint.wrist.left", "joint.wrist.right",
            "joint.sacroiliac.left", "joint.sacroiliac.right",
            "joint.hip.left", "joint.hip.right",
            "joint.femur.left", "joint.femur.right",
            "joint.knee.left", "joint.knee.right",
            "joint.shin.left", "joint.shin.right",
            "joint.ankle.left", "joint.ankle.right"
        ]

        for variant in [BodyModelVariant.female, .male] {
            for structureID in structureIDs {
                let marker = BodySurfaceMapper.markerPosition(
                    for: structureID,
                    variant: variant
                )
                XCTAssertEqual(
                    BodySurfaceMapper.jointID(at: marker, variant: variant),
                    structureID,
                    "Expected \(variant.rawValue) marker \(structureID) to use the same measured mesh landmark as hit testing."
                )
            }
        }
    }

    func testFootDetailCatalogProvidesGranularSurfaceAndInternalSelections() {
        let expectedIDs: Set<String> = [
            "body.heel.left", "body.topOfFoot.left", "body.sole.left",
            "body.arch.left", "body.ballOfFoot.left", "body.greatToe.left",
            "body.secondToe.left", "body.middleToe.left", "body.fourthToe.left",
            "body.littleToe.left", "muscle.achilles.left", "muscle.foot.left",
            "joint.heel.left", "joint.midfoot.left", "joint.greatToe.left",
            "joint.secondToe.left", "joint.middleToe.left", "joint.fourthToe.left",
            "joint.littleToe.left", "joint.femur.left", "joint.shin.left",
            "nerve.tibial.left", "nerve.fibular.left",
            "nerve.plantar.left"
        ]
        let availableIDs = Set(BodyAnatomyCatalog.structures(
            layer: .bodyAreas,
            region: .legsAndFeet,
            variant: .female
        ).map(\.id))
            .union(BodyAnatomyCatalog.structures(
                layer: .muscles,
                region: .legsAndFeet,
                variant: .female
            ).map(\.id))
            .union(BodyAnatomyCatalog.structures(
                layer: .joints,
                region: .legsAndFeet,
                variant: .female
            ).map(\.id))
            .union(BodyAnatomyCatalog.structures(
                layer: .nerves,
                region: .legsAndFeet,
                variant: .female
            ).map(\.id))

        XCTAssertTrue(expectedIDs.isSubset(of: availableIDs))
        for id in expectedIDs {
            XCTAssertEqual(BodyAnatomyCatalog.structure(id: id)?.side, .left)
            XCTAssertNotNil(BodyAnatomyCatalog.structure(id: id.replacingOccurrences(
                of: ".left",
                with: ".right"
            )))
        }
    }

    func testFootDetailMarkersStayOnTheSelectedSideForBothModels() {
        for variant in [BodyModelVariant.female, .male] {
            let left = BodySurfaceMapper.markerPosition(
                for: "body.greatToe.left",
                variant: variant
            )
            let right = BodySurfaceMapper.markerPosition(
                for: "body.greatToe.right",
                variant: variant
            )

            XCTAssertGreaterThan(left.x, 0)
            XCTAssertLessThan(right.x, 0)
            XCTAssertLessThan(left.y, -0.7 * 2.55)
            XCTAssertLessThan(right.y, -0.7 * 2.55)
        }
    }

    func testSoleFootDetailProvidesAnIndividualTargetForEveryToe() throws {
        let toeIDs = [
            "greatToe", "secondToe", "middleToe", "fourthToe", "littleToe"
        ]
        let sceneScale: Float = 2.55

        for variant in [BodyModelVariant.female, .male] {
            for focus in [BodyFootDetailFocus.left, .right] {
                let side = focus == .left ? "left" : "right"
                XCTAssertEqual(
                    FootDetailStructureMapper.toeSelectionProxies(
                        focus: focus,
                        variant: variant
                    ).map(\.id),
                    toeIDs
                )

                for toeID in toeIDs {
                    let structureID = "body.\(toeID).\(side)"
                    let marker = try XCTUnwrap(
                        FootDetailStructureMapper.markerPosition(
                            for: structureID,
                            focus: focus,
                            variant: variant,
                            soleView: true
                        )
                    )
                    XCTAssertEqual(
                        FootDetailStructureMapper.structureID(
                            layer: .bodyAreas,
                            focus: focus,
                            at: marker / sceneScale,
                            variant: variant,
                            soleView: true
                        ),
                        structureID,
                        "Expected the \(variant.rawValue) \(side) sole marker to resolve to \(toeID)."
                    )
                }
            }
        }
    }

    func testSelectionMarkerDepthTracksFrontBackAndSoleOrientations() {
        let anchor = SIMD3<Float>(0, 0, 0)
        let depth: Float = 0.075
        let expectedOffset = depth * 2.55
        let front = AnatomyMarkerPlacement.displayedPosition(
            from: anchor,
            yaw: 0,
            pitch: 0,
            canonicalDepth: depth
        )
        let back = AnatomyMarkerPlacement.displayedPosition(
            from: anchor,
            yaw: .pi,
            pitch: 0,
            canonicalDepth: depth
        )
        let sole = AnatomyMarkerPlacement.displayedPosition(
            from: anchor,
            yaw: 0,
            pitch: -.pi / 2,
            canonicalDepth: depth
        )

        XCTAssertEqual(front.z, expectedOffset, accuracy: 0.0001)
        XCTAssertEqual(back.z, -expectedOffset, accuracy: 0.0001)
        XCTAssertEqual(sole.y, -expectedOffset, accuracy: 0.0001)
    }

    func testSelectionMarkerDepthFollowsPerspectiveRayForOffCenterArm() {
        let anchor = SIMD3<Float>(0.72, 0.31, 0.08)
        let camera = SIMD3<Float>(0, 0, 3.1)
        let depth: Float = 0.115
        let direction = simd_normalize(camera - anchor)
        let expected = anchor + direction * depth * 2.55
        let displayed = AnatomyMarkerPlacement.displayedPosition(
            from: anchor,
            toward: camera,
            canonicalDepth: depth
        )

        XCTAssertEqual(displayed.x, expected.x, accuracy: 0.0001)
        XCTAssertEqual(displayed.y, expected.y, accuracy: 0.0001)
        XCTAssertEqual(displayed.z, expected.z, accuracy: 0.0001)
    }

    func testUpperLimbDefaultMarkersMatchRenderedCenterlines() {
        let expected: [(id: String, point: SIMD3<Float>)] = [
            ("body.shoulder.left", SIMD3(0.19, 0.545, 0.015)),
            ("body.upperArm.left", SIMD3(0.228, 0.403, 0.05)),
            ("body.elbow.left", SIMD3(0.265, 0.272, 0.015)),
            ("body.forearm.left", SIMD3(0.335, 0.135, 0.04)),
            ("body.wrist.left", SIMD3(0.408, 0.001, 0.025)),
            ("body.hand.left", SIMD3(0.465, -0.048, 0.064))
        ]

        for value in expected {
            let marker = BodySurfaceMapper.markerPosition(
                for: value.id,
                variant: .female
            ) / 2.55
            XCTAssertEqual(marker.x, value.point.x, accuracy: 0.0001, value.id)
            XCTAssertEqual(marker.y, value.point.y, accuracy: 0.0001, value.id)
            XCTAssertEqual(marker.z, value.point.z, accuracy: 0.0001, value.id)

            let rightID = value.id.replacingOccurrences(of: ".left", with: ".right")
            let rightMarker = BodySurfaceMapper.markerPosition(
                for: rightID,
                variant: .female
            ) / 2.55
            XCTAssertEqual(rightMarker.x, -value.point.x, accuracy: 0.0001, rightID)
            XCTAssertEqual(rightMarker.y, value.point.y, accuracy: 0.0001, rightID)
            XCTAssertEqual(rightMarker.z, value.point.z, accuracy: 0.0001, rightID)
        }
    }

    func testPosteriorThighDefaultMarkerStartsOnTheBackOfTheBody() {
        for variant in [BodyModelVariant.female, .male] {
            for side in ["left", "right"] {
                XCTAssertLessThan(
                    BodySurfaceMapper.markerPosition(
                        for: "body.posteriorThigh.\(side)",
                        variant: variant
                    ).z,
                    0
                )
            }
        }
    }

    private func organIDs(for variant: BodyModelVariant) -> Set<String> {
        Set(BodyAnatomyCatalog.structures(
            layer: .organs,
            region: .all,
            variant: variant
        ).map(\.id))
    }

    private func structure(_ id: String) throws -> BodyAnatomyStructure {
        try XCTUnwrap(BodyAnatomyCatalog.structure(id: id))
    }
}
