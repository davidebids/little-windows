import SwiftData
import XCTest
@testable import LittleWindows

final class SolidsFeatureTests: XCTestCase {
    func testTodayFeedQuickActionShowsLatestSolidFoodNamesCompactly() {
        let event = CareEvent(type: .feed)
        event.feedKind = .solid
        event.solidFoodDetails = [
            SolidFoodLogDetail(foodID: "huckleberry", foodName: "Huckleberry"),
            SolidFoodLogDetail(foodID: "yogurt", foodName: "Yogurt"),
            SolidFoodLogDetail(foodID: "oat", foodName: "Oat")
        ]

        XCTAssertEqual(
            TodayFeedQuickActionDetail.solidFoodSummary(for: event),
            "Huckleberry + 2 more"
        )
    }

    func testTodayFeedQuickActionFallsBackToLegacySolidFoodDescription() {
        let event = CareEvent(type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Huckleberry, Yogurt"

        XCTAssertEqual(
            TodayFeedQuickActionDetail.solidFoodSummary(for: event),
            "Huckleberry + Yogurt"
        )

        event.feedKind = .bottle
        XCTAssertNil(TodayFeedQuickActionDetail.solidFoodSummary(for: event))
    }

    func testCatalogContainsMoreThanFourHundredUniqueFoods() {
        let foods = SolidsReferenceCatalog.foods
        XCTAssertGreaterThanOrEqual(foods.count, 400)
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
        XCTAssertTrue(foods.allSatisfy { !$0.name.isEmpty })
    }

    func testEveryCatalogFoodHasPreparationAndSourceMetadata() {
        for food in SolidsReferenceCatalog.foods {
            XCTAssertFalse(food.preparations.isEmpty, food.name)
            XCTAssertFalse(food.sourceURLs.isEmpty, food.name)
            XCTAssertTrue(food.preparations.allSatisfy { !$0.instructions.isEmpty }, food.name)
            XCTAssertTrue(food.preparations.allSatisfy {
                !$0.servingAmount.firstServing.isEmpty && !$0.servingAmount.routineServing.isEmpty
            }, "\(food.name) should include first and routine serving amounts")
            XCTAssertTrue(food.preparations.allSatisfy {
                $0.instructions.localizedCaseInsensitiveContains(food.name)
            }, "Preparation guidance should identify \(food.name), not just its category")
            XCTAssertTrue(food.preparations.map(\.minimumAgeMonths).allSatisfy {
                $0 >= food.minimumAgeMonths
            }, food.name)
            XCTAssertFalse(food.servingVisuals.isEmpty, food.name)
            XCTAssertTrue(food.servingVisuals.allSatisfy { !$0.assetName.isEmpty }, food.name)
            XCTAssertFalse(food.details.introductionSummary.isEmpty, food.name)
            XCTAssertFalse(food.details.backgroundSummary?.isEmpty ?? true, food.name)
            XCTAssertFalse(food.details.nutritionSummary.isEmpty, food.name)
            XCTAssertFalse(food.details.allergenSummary.isEmpty, food.name)
            XCTAssertFalse(food.details.choosingGuidance.isEmpty, food.name)
            XCTAssertFalse(food.details.storageGuidance.isEmpty, food.name)
            XCTAssertGreaterThanOrEqual(food.details.questions.count, 2, food.name)
            XCTAssertTrue(food.details.questions.allSatisfy {
                !$0.question.isEmpty && !$0.answer.isEmpty
            }, food.name)
            XCTAssertGreaterThanOrEqual(food.sourceURLs.count, 4, food.name)
            XCTAssertEqual(Set(food.sourceURLs).count, food.sourceURLs.count, food.name)
            XCTAssertTrue(food.sourceURLs.contains {
                $0.host == "fdc.nal.usda.gov" && $0.absoluteString.localizedCaseInsensitiveContains("food-search")
            }, "\(food.name) should have an ingredient-specific USDA lookup")
        }
    }

    func testPeanutButterUsesSpecificCopyAndServingAmounts() throws {
        let peanutButter = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Peanut butter"))
        let firstStage = try XCTUnwrap(peanutButter.preparations.first)

        XCTAssertTrue(firstStage.servingAmount.firstServing.contains("1 tsp"))
        XCTAssertTrue(firstStage.servingAmount.routineServing.contains("2 tsp"))
        XCTAssertTrue(peanutButter.details.introductionSummary.localizedCaseInsensitiveContains("smooth"))
        XCTAssertTrue(peanutButter.details.introductionSummary.localizedCaseInsensitiveContains("thinned"))

        let displayedCopy = [
            peanutButter.details.introductionSummary,
            peanutButter.details.backgroundSummary ?? "",
            peanutButter.details.nutritionSummary,
            peanutButter.details.allergenSummary,
            peanutButter.details.choosingGuidance,
            peanutButter.details.storageGuidance,
            peanutButter.safetyNote,
            peanutButter.chokingGuidance
        ] + peanutButter.preparations.flatMap { stage in
            [stage.instructions, stage.servingAmount.firstServing, stage.servingAmount.routineServing]
        } + peanutButter.preparationWalkthrough(stageIndex: 0).actions.map(\.detail)

        XCTAssertFalse(displayedCopy.contains { $0.localizedCaseInsensitiveContains("bones") })
        XCTAssertFalse(displayedCopy.contains { $0.localizedCaseInsensitiveContains("skin") })
    }

    func testEveryIngredientUsesRichEditorialCopyInsteadOfCategoryBoilerplate() {
        let retiredBoilerplate = [
            "Depending on its variety and preparation",
            "Choose produce without mold, major bruising",
            "Store according to the produce's normal",
            "Prepare it until very soft",
            "Serve as part of family meals in safe, manageable pieces"
        ]

        for food in SolidsReferenceCatalog.foods {
            let content = [
                food.details.introductionSummary,
                food.details.backgroundSummary ?? "",
                food.details.nutritionSummary,
                food.details.choosingGuidance,
                food.details.storageGuidance,
                food.safetyNote,
                food.chokingGuidance
            ] + food.preparations.map(\.instructions)

            for boilerplate in retiredBoilerplate {
                XCTAssertFalse(
                    content.contains { $0.localizedCaseInsensitiveContains(boilerplate) },
                    "\(food.name) still contains retired generic copy: \(boilerplate)"
                )
            }
            XCTAssertTrue(
                food.details.questions.allSatisfy {
                    $0.question.localizedCaseInsensitiveContains(food.name)
                        || $0.answer.localizedCaseInsensitiveContains(food.name)
                },
                "Every practical answer should stay anchored to \(food.name)"
            )
        }
    }

    func testCatalogCopyStaysAccurateToEachFoodsPhysicalForm() throws {
        func displayedCopy(for food: SolidsReferenceFood) -> String {
            let details = [
                food.details.introductionSummary,
                food.details.backgroundSummary ?? "",
                food.details.nutritionSummary,
                food.details.allergenSummary,
                food.details.choosingGuidance,
                food.details.storageGuidance,
                food.safetyNote,
                food.chokingGuidance
            ]
            let questions = food.details.questions.flatMap { [$0.question, $0.answer] }
            let stages = food.preparations.flatMap {
                [$0.instructions, $0.servingAmount.firstServing, $0.servingAmount.routineServing]
            }
            let walkthroughs = food.preparations.indices.flatMap { index in
                food.preparationWalkthrough(stageIndex: index).actions.flatMap {
                    [$0.title, $0.detail, $0.completionLabel]
                }
            }
            return (details + questions + stages + walkthroughs).joined(separator: "\n").lowercased()
        }

        let retiredCrossCategoryCopy = [
            "skin, bones, shell",
            "one-size-fits-all food shape",
            "a bean should mash through the center, tofu should compress",
            "remove every shell, tail, bone",
            "remove all bone, cartilage, skin, and gristle",
            "stems, sticks, pods, woody fibers"
        ]
        for food in SolidsReferenceCatalog.foods {
            let copy = displayedCopy(for: food)
            XCTAssertFalse(copy.contains("\\(name"), "\(food.name) contains an uninterpolated template placeholder")
            for phrase in retiredCrossCategoryCopy {
                XCTAssertFalse(copy.contains(phrase), "\(food.name) contains cross-category copy: \(phrase)")
            }
        }

        let applesauce = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Applesauce"))
        let applesauceCopy = displayedCopy(for: applesauce)
        XCTAssertFalse(applesauceCopy.contains("wash applesauce"))
        XCTAssertFalse(applesauceCopy.contains("raw applesauce"))
        XCTAssertFalse(applesauceCopy.contains("pit"))
        XCTAssertFalse(applesauceCopy.contains("core"))
        XCTAssertTrue(applesauceCopy.contains("unsweetened"))
        XCTAssertTrue(applesauceCopy.contains("scoopable"))

        let pineapple = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Pineapple"))
        XCTAssertFalse(pineapple.chokingGuidance.localizedCaseInsensitiveContains("hard raw pineapple chunks"))

        let breadfruit = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Breadfruit"))
        let breadfruitCopy = displayedCopy(for: breadfruit)
        XCTAssertFalse(breadfruitCopy.contains("gummy ball"))
        XCTAssertTrue(breadfruitCopy.contains("cook"))

        let groundBeef = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Ground beef"))
        let groundBeefCopy = displayedCopy(for: groundBeef)
        XCTAssertFalse(groundBeefCopy.contains("bone"))
        XCTAssertFalse(groundBeefCopy.contains("shell"))
        XCTAssertFalse(groundBeefCopy.contains("tough skin"))
        XCTAssertTrue(groundBeefCopy.contains("moist"))

        let chickenThigh = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Chicken thigh"))
        let chickenThighCopy = displayedCopy(for: chickenThigh)
        XCTAssertTrue(chickenThighCopy.contains("boneless portion"))
        XCTAssertTrue(chickenThighCopy.contains("cooked on the bone"))
        XCTAssertTrue(chickenThighCopy.contains("inspect it again"))

        let peanutButter = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Peanut butter"))
        let peanutButterCopy = displayedCopy(for: peanutButter)
        XCTAssertFalse(peanutButterCopy.contains("whole peanut butter"))
        XCTAssertFalse(peanutButterCopy.contains("bone"))
        XCTAssertFalse(peanutButterCopy.contains("skin"))
        XCTAssertTrue(peanutButterCopy.contains("thin"))

        let smoothie = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Fruit smoothie bowl"))
        let smoothieCopy = displayedCopy(for: smoothie)
        XCTAssertFalse(smoothieCopy.contains("bone"))
        XCTAssertFalse(smoothieCopy.contains("shell"))
        XCTAssertTrue(smoothieCopy.contains("spoon"))

        let eggYolk = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Egg yolk"))
        let eggYolkCopy = displayedCopy(for: eggYolk)
        XCTAssertFalse(eggYolkCopy.contains("white and yolk"))
        XCTAssertFalse(eggYolkCopy.contains("both white"))
        XCTAssertTrue(eggYolkCopy.contains("moist"))
        XCTAssertEqual(eggYolk.servingVisuals, [.spoon, .spoon, .spoon, .spoon])

        let silkenTofu = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Silken tofu"))
        let silkenTofuCopy = displayedCopy(for: silkenTofu)
        XCTAssertFalse(silkenTofuCopy.contains("a bean should"))
        XCTAssertFalse(silkenTofuCopy.contains("patty or cake"))
        XCTAssertFalse(silkenTofuCopy.contains("rubbery skin"))
        XCTAssertTrue(silkenTofuCopy.contains("scoopable"))

        let tahini = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Tahini"))
        let tahiniCopy = displayedCopy(for: tahini)
        XCTAssertFalse(tahiniCopy.contains("whole tahini"))
        XCTAssertFalse(tahiniCopy.contains("grind tahini"))
        XCTAssertTrue(tahiniCopy.contains("smooth"))

        let bayLeaf = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Bay leaf flavor"))
        let bayLeafCopy = displayedCopy(for: bayLeaf)
        XCTAssertTrue(bayLeafCopy.contains("remove"))
        XCTAssertTrue(bayLeaf.preparations.allSatisfy {
            $0.servingAmount.firstServing.localizedCaseInsensitiveContains("no leaf in the serving")
        })

        let sprouts = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Mung bean sprout"))
        let sproutCopy = displayedCopy(for: sprouts)
        XCTAssertTrue(sproutCopy.contains("steaming hot"))
        XCTAssertTrue(sprouts.sourceURLs.contains(SolidsSourceLibrary.fdaProduceSafety))
        XCTAssertFalse(sprouts.isIronRich)

        for name in ["Cactus pear", "Prickly pear"] {
            let pear = try XCTUnwrap(SolidsReferenceCatalog.food(named: name))
            let pearCopy = displayedCopy(for: pear)
            XCTAssertTrue(pearCopy.contains("glochid"), name)
            XCTAssertTrue(pearCopy.contains("spine"), name)
            XCTAssertTrue(pearCopy.contains("outer skin"), name)
        }

        let swordfish = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Swordfish"))
        XCTAssertFalse(swordfish.isEligibleForGuidedPath)
        XCTAssertTrue(swordfish.safetyNote.localizedCaseInsensitiveContains("choice to avoid"))

        let mackerel = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Mackerel"))
        XCTAssertFalse(mackerel.isEligibleForGuidedPath)
        XCTAssertTrue(mackerel.safetyNote.localizedCaseInsensitiveContains("king mackerel"))

        let tuna = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Tuna"))
        XCTAssertFalse(tuna.isEligibleForGuidedPath)
        XCTAssertTrue(tuna.safetyNote.localizedCaseInsensitiveContains("bigeye tuna"))
    }

    func testIngredientFormsKeepTheirOwnPreparationProgressions() throws {
        let cassava = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Cassava"))
        XCTAssertTrue(cassava.safetyNote.localizedCaseInsensitiveContains("never serve cassava raw"))
        XCTAssertTrue(cassava.preparations[0].instructions.localizedCaseInsensitiveContains("cyanogenic"))

        let waterChestnut = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Water chestnut"))
        XCTAssertEqual(waterChestnut.servingVisuals.first, .mashed)
        XCTAssertTrue(waterChestnut.preparations[0].instructions.localizedCaseInsensitiveContains("mince"))
        XCTAssertTrue(waterChestnut.preparations[1].instructions.localizedCaseInsensitiveContains("mincing"))

        let artichoke = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Artichoke"))
        XCTAssertTrue(artichoke.preparations[0].instructions.localizedCaseInsensitiveContains("heart"))
        XCTAssertTrue(artichoke.preparations[0].instructions.localizedCaseInsensitiveContains("choke"))
        XCTAssertFalse(artichoke.preparations[0].instructions.localizedCaseInsensitiveContains("floret"))

        let brusselsSprouts = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Brussels sprouts"))
        XCTAssertTrue(brusselsSprouts.preparations[0].instructions.localizedCaseInsensitiveContains("quarter"))
        XCTAssertTrue(brusselsSprouts.preparations[0].instructions.localizedCaseInsensitiveContains("do not serve a whole bud"))

        let silkenTofu = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Silken tofu"))
        XCTAssertEqual(silkenTofu.servingVisuals, [.spoon, .spoon, .spoon, .spoon])
        XCTAssertTrue(silkenTofu.preparations[0].instructions.localizedCaseInsensitiveContains("custard"))

        let miso = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Miso"))
        XCTAssertEqual(miso.servingVisuals, [.spoon, .spoon, .spoon, .spoon])
        XCTAssertTrue(miso.preparations.allSatisfy {
            $0.instructions.localizedCaseInsensitiveContains("season")
                || $0.instructions.localizedCaseInsensitiveContains("sodium")
                || $0.instructions.localizedCaseInsensitiveContains("salty")
        })

        let fermentedTofu = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Fermented tofu"))
        XCTAssertEqual(fermentedTofu.servingVisuals, [.spoon, .spoon, .spoon, .spoon])
        XCTAssertTrue(fermentedTofu.preparations[0].instructions.localizedCaseInsensitiveContains("sodium"))

        let scallop = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Scallop"))
        XCTAssertTrue(scallop.preparations[0].instructions.localizedCaseInsensitiveContains("shell fragments"))
        XCTAssertTrue(scallop.preparations[0].instructions.localizedCaseInsensitiveContains("mince"))

        let squid = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Squid"))
        XCTAssertTrue(squid.preparations[0].instructions.localizedCaseInsensitiveContains("rings"))
        XCTAssertTrue(squid.preparations[0].instructions.localizedCaseInsensitiveContains("mince"))

        let liver = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Chicken liver"))
        XCTAssertTrue(liver.safetyNote.localizedCaseInsensitiveContains("vitamin A"))
        XCTAssertTrue(liver.preparations[2].instructions.localizedCaseInsensitiveContains("modest"))

        let soup = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Vegetable soup"))
        XCTAssertEqual(soup.servingVisuals, [.spoon, .spoon, .spoon, .spoon])
        XCTAssertTrue(soup.preparations[0].instructions.localizedCaseInsensitiveContains("thick scoopable"))

        let paneer = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Paneer"))
        XCTAssertTrue(paneer.preparations[0].instructions.localizedCaseInsensitiveContains("does not melt"))
        XCTAssertTrue(paneer.preparations[0].instructions.localizedCaseInsensitiveContains("firm cube"))

        let milkInFood = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Pasteurized milk in food"))
        XCTAssertTrue(milkInFood.preparations[0].instructions.localizedCaseInsensitiveContains("main drink"))
    }

    func testVerifiedIngredientSourcesAreBundledWithoutRuntimeFetching() throws {
        let apple = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Apple"))
        XCTAssertTrue(apple.sourceURLs.contains(SolidsSourceLibrary.aapFruitJuice))
        XCTAssertTrue(apple.sourceURLs.contains {
            $0.host == "fdc.nal.usda.gov" && $0.absoluteString.contains("Apple")
        })

        let blackBean = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Black bean"))
        XCTAssertTrue(blackBean.sourceURLs.contains {
            $0.host == "fdc.nal.usda.gov" && $0.absoluteString.contains("Black%20bean")
        })

        let catalogURLs = SolidsReferenceCatalog.foods.flatMap(\.sourceURLs)
        let approvedHosts: Set<String> = [
            "doi.org",
            "fdc.nal.usda.gov",
            "www.cdc.gov",
            "www.fda.gov",
            "www.healthychildren.org",
            "www.nccih.nih.gov",
            "www.nhs.uk",
            "www.niaid.nih.gov",
            "www.who.int"
        ]
        XCTAssertTrue(catalogURLs.allSatisfy { url in
            url.host.map(approvedHosts.contains) == true
        })
    }

    func testSourceLabelsDescribeTheirDistinctGuidance() {
        let introduction = SolidsSourceLibrary.displayName(for: SolidsSourceLibrary.cdcIntroduction)
        let choking = SolidsSourceLibrary.displayName(for: SolidsSourceLibrary.cdcChoking)
        let fruitJuice = SolidsSourceLibrary.displayName(for: SolidsSourceLibrary.aapFruitJuice)
        let allergens = SolidsSourceLibrary.displayName(for: SolidsSourceLibrary.aapAllergenIntroduction)
        let produceSafety = SolidsSourceLibrary.displayName(for: SolidsSourceLibrary.fdaProduceSafety)

        XCTAssertEqual(introduction, "CDC — Starting solid foods")
        XCTAssertEqual(choking, "CDC — Choking prevention")
        XCTAssertNotEqual(introduction, choking)
        XCTAssertEqual(fruitJuice, "AAP — Fruit juice guidance")
        XCTAssertEqual(allergens, "AAP — Allergen introduction guidance")
        XCTAssertEqual(produceSafety, "FDA — Produce and sprout safety")
        XCTAssertNotEqual(fruitJuice, allergens)
    }

    func testAllergenSourceLabelsMatchEveryLinkedDestination() {
        for allergen in SolidsAllergen.allCases {
            let guidance = SolidsReferenceCatalog.allergenGuidance(allergen)
            for url in guidance.sourceURLs {
                let label = SolidsSourceLibrary.displayName(for: url)
                XCTAssertNotEqual(label, "Reference source", "Missing source label for \(url)")
                if url == SolidsSourceLibrary.aapAllergenIntroduction {
                    XCTAssertEqual(label, "AAP — Allergen introduction guidance")
                } else if url == SolidsSourceLibrary.fdaAllergens {
                    XCTAssertEqual(label, "FDA major allergens")
                } else if url == SolidsSourceLibrary.niaidPeanutGuidance {
                    XCTAssertEqual(label, "NIAID peanut introduction guidance")
                }
            }
        }
    }

    func testPreparationWalkthroughAddsOperationalStepsInsteadOfRepeatingTheOverview() {
        let expectedKinds = Set(SolidsPreparationActionKind.allCases)

        for food in SolidsReferenceCatalog.foods {
            for index in food.preparations.indices {
                let walkthrough = food.preparationWalkthrough(stageIndex: index)
                XCTAssertEqual(walkthrough.stage, food.preparations[index], food.name)
                XCTAssertEqual(walkthrough.actions.count, 6, food.name)
                XCTAssertEqual(Set(walkthrough.actions.map(\.kind)), expectedKinds, food.name)
                XCTAssertEqual(Set(walkthrough.actions.map(\.id)).count, walkthrough.actions.count, food.name)
                XCTAssertTrue(walkthrough.actions.allSatisfy {
                    !$0.title.isEmpty && !$0.detail.isEmpty && !$0.completionLabel.isEmpty
                }, food.name)
                XCTAssertFalse(walkthrough.actions.contains {
                    $0.detail == walkthrough.stage.instructions
                }, "The walkthrough must add operational detail rather than copy the age overview for \(food.name).")
            }
        }
    }

    func testPreparationWalkthroughUsesFoodStageAndAllergenSpecificChecks() throws {
        let acai = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Açaí"))
        let acaiWalkthrough = acai.preparationWalkthrough(stageIndex: 1)
        XCTAssertEqual(acaiWalkthrough.visual, .spoon)
        XCTAssertTrue(acaiWalkthrough.actions.first { $0.kind == .clean }?.detail.localizedCaseInsensitiveContains("seedless pulp") == true)
        XCTAssertTrue(acaiWalkthrough.actions.first { $0.kind == .prepare }?.detail.localizedCaseInsensitiveContains("thaw") == true)
        XCTAssertTrue(acaiWalkthrough.actions.first { $0.kind == .shape }?.detail.localizedCaseInsensitiveContains("scoopable") == true)
        XCTAssertFalse(acaiWalkthrough.actions.contains {
            $0.detail.localizedCaseInsensitiveContains("slices")
        })

        let scallop = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Scallop"))
        let scallopWalkthrough = scallop.preparationWalkthrough(stageIndex: 0)
        XCTAssertTrue(scallopWalkthrough.actions.first { $0.kind == .clean }?.detail.localizedCaseInsensitiveContains("shell") == true)

        let egg = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Egg"))
        let eggWalkthrough = egg.preparationWalkthrough(stageIndex: 0)
        XCTAssertTrue(eggWalkthrough.actions.first { $0.kind == .serve }?.detail.localizedCaseInsensitiveContains("Egg") == true)
        XCTAssertTrue(eggWalkthrough.actions.first { $0.kind == .serve }?.detail.localizedCaseInsensitiveContains("first introduction") == true)
    }

    func testAcaiUsesPulpSpecificProgressionInsteadOfGenericFruitShapes() throws {
        let food = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Açaí"))

        XCTAssertEqual(food.preparations.map(\.minimumAgeMonths), [6, 9, 12, 18])
        XCTAssertTrue(food.preparations[0].instructions.localizedCaseInsensitiveContains("pulp"))
        XCTAssertTrue(food.preparations[1].instructions.localizedCaseInsensitiveContains("keep serving it as pulp"))
        XCTAssertTrue(food.preparations[3].instructions.localizedCaseInsensitiveContains("smoothie"))
        XCTAssertEqual(food.servingVisuals, [.spoon, .spoon, .spoon, .spoon])
        XCTAssertTrue(food.sourceURLs.contains(SolidsSourceLibrary.aapFruitJuice))
        XCTAssertTrue(food.sourceURLs.contains(SolidsSourceLibrary.nccihAcai))
        XCTAssertTrue(food.sourceURLs.contains(SolidsSourceLibrary.datePalmFruitAllergy))
        XCTAssertTrue(food.sourceURLs.contains(SolidsSourceLibrary.heartOfPalmAnaphylaxis))
        XCTAssertTrue(food.sourceURLs.contains(SolidsSourceLibrary.whoComplementaryFeeding))
        XCTAssertTrue(food.sourceURLs.contains(SolidsSourceLibrary.espghanSugarPosition))
        XCTAssertEqual(Set(food.sourceURLs).count, food.sourceURLs.count)
        XCTAssertTrue(food.details.introductionSummary.localizedCaseInsensitiveContains("seedless pulp"))
        XCTAssertTrue(food.details.backgroundSummary?.localizedCaseInsensitiveContains("Amazon") == true)
        XCTAssertTrue(food.details.nutritionSummary.localizedCaseInsensitiveContains("anthocyanins"))
        XCTAssertTrue(food.details.nutritionSummary.localizedCaseInsensitiveContains("too limited"))
        XCTAssertTrue(food.details.allergenSummary.localizedCaseInsensitiveContains("not one of the nine"))
        XCTAssertTrue(food.details.allergenSummary.localizedCaseInsensitiveContains("do not establish"))
        XCTAssertTrue(food.details.choosingGuidance.localizedCaseInsensitiveContains("caffeine"))
        XCTAssertEqual(food.details.questions.count, 2)
        XCTAssertTrue(food.details.questions.contains {
            $0.question.localizedCaseInsensitiveContains("bowl")
                && $0.answer.localizedCaseInsensitiveContains("honey")
        })
        XCTAssertTrue(food.details.questions.contains {
            $0.question.localizedCaseInsensitiveContains("juice")
                && $0.answer.localizedCaseInsensitiveContains("12 months")
        })

        let incompatibleRecommendations = [
            "large soft piece",
            "soft pieces",
            "soft slices",
            "soft wedge",
            "graspable piece",
            "manageable pieces",
            "slice"
        ]
        for stage in food.preparations {
            for phrase in incompatibleRecommendations {
                XCTAssertFalse(
                    stage.instructions.localizedCaseInsensitiveContains(phrase),
                    "Açaí should not recommend \(phrase) at \(stage.title): \(stage.instructions)"
                )
            }
        }
    }

    func testNonPieceableFoodsStayScoopableAcrossAgeStages() throws {
        let expectedVisuals: [String: [SolidsServingVisual]] = [
            "Açaí": [.spoon, .spoon, .spoon, .spoon],
            "Applesauce": [.spoon, .spoon, .spoon, .spoon],
            "Oatmeal": [.spoon, .spoon, .spoon, .spoon],
            "Greek yogurt": [.spoon, .spoon, .spoon, .spoon],
            "Peanut butter": [.spoon, .thinSpread, .thinSpread, .thinSpread]
        ]
        let incompatibleRecommendations = [
            "large soft piece",
            "soft pieces",
            "soft spears",
            "soft slices",
            "easy-to-hold wedge",
            "manageable pieces"
        ]

        for (name, visuals) in expectedVisuals {
            let food = try XCTUnwrap(SolidsReferenceCatalog.food(named: name))
            XCTAssertEqual(food.servingVisuals, visuals, name)
            for stage in food.preparations {
                for phrase in incompatibleRecommendations {
                    XCTAssertFalse(
                        stage.instructions.localizedCaseInsensitiveContains(phrase),
                        "\(name) should stay scoopable at \(stage.title): \(stage.instructions)"
                    )
                }
            }
        }
    }

    func testFruitPreparationProgressionsReflectPhysicalForm() throws {
        let applesauce = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Applesauce"))
        let blueberry = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Blueberry"))
        let orange = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Orange"))
        let apple = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Apple"))
        let passionFruit = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Passion fruit"))
        let coconut = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Coconut flesh"))

        XCTAssertTrue(applesauce.preparations[1].instructions.localizedCaseInsensitiveContains("spoon food"))
        XCTAssertTrue(blueberry.preparations[1].instructions.localizedCaseInsensitiveContains("flatten"))
        XCTAssertTrue(orange.preparations[0].instructions.localizedCaseInsensitiveContains("membrane"))
        XCTAssertTrue(apple.preparations[0].instructions.localizedCaseInsensitiveContains("steam or bake"))
        XCTAssertTrue(passionFruit.preparations[1].instructions.localizedCaseInsensitiveContains("pulp food"))
        XCTAssertTrue(coconut.preparations[0].instructions.localizedCaseInsensitiveContains("finely grated"))

        XCTAssertEqual(
            Set([applesauce, blueberry, orange, apple, passionFruit, coconut].map { $0.preparations[1].instructions }).count,
            6
        )
    }

    func testOtherIngredientFormsDoNotFallBackToCategoryShapes() throws {
        let rice = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Rice"))
        let bayLeaf = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Bay leaf flavor"))
        let cinnamon = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Cinnamon"))
        let walnut = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Walnut"))
        let cottageCheese = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Cottage cheese"))
        let cheddar = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Cheddar cheese"))

        XCTAssertTrue(rice.preparations[0].instructions.localizedCaseInsensitiveContains("moist scoopable clump"))
        XCTAssertFalse(rice.preparations[0].instructions.localizedCaseInsensitiveContains("large graspable piece"))
        XCTAssertEqual(rice.servingVisuals, [.spoon, .spoon, .spoon, .spoon])

        XCTAssertTrue(bayLeaf.preparations.allSatisfy {
            $0.instructions.localizedCaseInsensitiveContains("remove")
        })
        XCTAssertTrue(cinnamon.preparations.allSatisfy {
            $0.instructions.localizedCaseInsensitiveContains("ground")
        })

        XCTAssertTrue(walnut.preparations.allSatisfy {
            $0.instructions.localizedCaseInsensitiveContains("whole")
                || $0.instructions.localizedCaseInsensitiveContains("nut pieces")
        })
        XCTAssertFalse(walnut.preparations.contains {
            $0.instructions.localizedCaseInsensitiveContains("manageable pieces")
        })

        XCTAssertEqual(cottageCheese.servingVisuals, [.spoon, .spoon, .spoon, .spoon])
        XCTAssertTrue(cottageCheese.preparations[1].instructions.localizedCaseInsensitiveContains("scoopable"))
        XCTAssertEqual(cheddar.servingVisuals, [.shredded, .shredded, .softPieces, .softPieces])
        XCTAssertTrue(cheddar.preparations[0].instructions.localizedCaseInsensitiveContains("finely grate"))
    }

    func testFoodDatabaseFiltersCoverAgeTypesAllergensNutritionAndTracking() throws {
        let apple = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Apple"))
        let honey = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Honey"))
        let lentil = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Lentil"))
        let salmon = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Salmon"))
        let shrimp = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Shrimp"))
        let peanutButter = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Peanut butter"))
        let waffle = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Waffle"))

        var filters = SolidsFoodDatabaseFilters.empty
        filters.ageMonths = 6
        XCTAssertTrue(filters.matches(apple, progress: nil))
        XCTAssertFalse(filters.matches(honey, progress: nil))
        filters.ageMonths = 12
        XCTAssertTrue(filters.matches(honey, progress: nil))

        filters = .empty
        filters.selectedTypes = [.fish]
        XCTAssertTrue(filters.matches(salmon, progress: nil))
        XCTAssertFalse(filters.matches(shrimp, progress: nil))
        filters.selectedTypes = [.fish, .shellfish]
        XCTAssertTrue(filters.matches(salmon, progress: nil))
        XCTAssertTrue(filters.matches(shrimp, progress: nil))
        XCTAssertTrue(SolidsFoodTypeFilter.vegan.matches(apple))
        XCTAssertTrue(SolidsFoodTypeFilter.legume.matches(peanutButter))
        XCTAssertTrue(SolidsFoodTypeFilter.prepared.matches(waffle))

        filters = .empty
        filters.excludedAllergenIDs = [SolidsAllergen.peanuts.rawValue]
        XCTAssertFalse(filters.matches(peanutButter, progress: nil))
        XCTAssertTrue(filters.matches(apple, progress: nil))
        filters.excludedAllergenIDs = [SolidsAllergen.milk.rawValue]
        XCTAssertFalse(filters.matches(waffle, progress: nil), "Possible allergens should also be excluded")

        filters = .empty
        filters.ironFilter = .ironRich
        XCTAssertTrue(filters.matches(lentil, progress: nil))
        XCTAssertFalse(filters.matches(apple, progress: nil))

        let tried = SolidsFoodProgressFilterValue(status: .tried, isFavorite: true)
        filters = .empty
        filters.trackingFilter = .tried
        XCTAssertTrue(filters.matches(apple, progress: tried))
        XCTAssertFalse(filters.matches(apple, progress: nil))
        filters.trackingFilter = .favorites
        XCTAssertTrue(filters.matches(apple, progress: tried))
        filters.trackingFilter = .notTried
        XCTAssertTrue(filters.matches(apple, progress: nil))
        XCTAssertFalse(filters.matches(apple, progress: tried))

        filters.ageMonths = 9
        filters.selectedTypes = [.fruit, .vegetable]
        filters.excludedAllergenIDs = [SolidsAllergen.milk.rawValue]
        filters.ironFilter = .notIronRich
        XCTAssertEqual(filters.activeCount, 6)
    }

    func testEveryFoodDatabaseTypeFilterHasCatalogResults() {
        for type in SolidsFoodTypeFilter.allCases {
            XCTAssertTrue(
                SolidsReferenceCatalog.foods.contains(where: type.matches),
                "Expected at least one catalog food for \(type.displayName)"
            )
        }
    }

    func testEveryCatalogFoodHasABundledVisual() throws {
        XCTAssertTrue(
            SolidsReferenceCatalog.foods.allSatisfy { !$0.visualEmoji.isEmpty && $0.visualEmoji != "🍽️" }
        )
        XCTAssertGreaterThan(Set(SolidsReferenceCatalog.foods.map(\.visualEmoji)).count, 20)

        let expectedVisuals = [
            "Cactus pear": "🌵",
            "Cantaloupe": "🍈",
            "Cape gooseberry": "🫐",
            "Cherimoya": "🍈",
            "Cherry": "🍒",
            "Clementine": "🍊",
            "Cloudberry": "🫐",
            "Coconut flesh": "🥥",
            "Crab apple": "🍎",
            "Cranberry": "🫐",
            "Currant": "🫐",
            "Date": "🌴"
        ]
        for (name, emoji) in expectedVisuals {
            XCTAssertEqual(try XCTUnwrap(SolidsReferenceCatalog.food(named: name)).visualEmoji, emoji, name)
        }
    }

    func testGuidedPathAndRecipeLibraryAreCompleteAndStable() {
        XCTAssertEqual(SolidsReferenceCatalog.guidedFoods.count, 100)
        XCTAssertEqual(Set(SolidsReferenceCatalog.guidedFoods.map(\.id)).count, 100)
        XCTAssertTrue(SolidsReferenceCatalog.guidedFoods.allSatisfy(\.isEligibleForGuidedPath))

        let recipes = SolidsReferenceCatalog.recipes
        XCTAssertGreaterThanOrEqual(recipes.count, 400)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count)
        XCTAssertGreaterThanOrEqual(Set(recipes.map(\.instructions)).count, 400)
        XCTAssertTrue(recipes.allSatisfy { !$0.ingredients.isEmpty })
        XCTAssertTrue(recipes.allSatisfy { !$0.instructions.isEmpty })
        XCTAssertTrue(recipes.allSatisfy { $0.servings > 0 })
        let linkedIngredientNames = recipes.flatMap { recipe in
            recipe.ingredients.flatMap { [$0.foodName] + $0.substitutionNames }
        }
        let missingIngredients = Set(linkedIngredientNames.filter {
            SolidsReferenceCatalog.food(named: $0) == nil
        }).sorted()
        XCTAssertTrue(
            missingIngredients.isEmpty,
            "Every recipe ingredient and substitution must deep-link, plan, and log as a catalog food. Missing: \(missingIngredients)"
        )
    }

    func testGuidedMealLinksPreferRecipesOverIngredientDetails() throws {
        let food = try XCTUnwrap(SolidsReferenceCatalog.guidedFoods.first)
        let recipe = try XCTUnwrap(SolidsReferenceCatalog.recipes.first)
        let date = Date(timeIntervalSince1970: 2_000_000_000)

        let recipeSuggestion = SolidsGuidedMealSuggestion(
            dayOffset: 0,
            scheduledAt: date,
            foods: [food],
            recipe: recipe,
            stage: .firstBites
        )
        XCTAssertEqual(recipeSuggestion.primaryDestination, .recipe(recipe.id))
        XCTAssertEqual(recipeSuggestion.primaryDestinationTitle, recipe.title)

        let singleFoodSuggestion = SolidsGuidedMealSuggestion(
            dayOffset: 1,
            scheduledAt: date,
            foods: [food],
            recipe: nil,
            stage: .firstBites
        )
        XCTAssertEqual(singleFoodSuggestion.primaryDestination, .food(food.id))
        XCTAssertEqual(singleFoodSuggestion.primaryDestinationTitle, food.name)
    }

    @MainActor
    func testGuidedRecipeSuggestionsContainTheFoodsInTheirLinkedRecipe() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -12, to: now)!
        )
        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            startingAt: now,
            count: 100
        )

        var familiarFoodIDs = Set<String>()
        var recipeCount = 0
        for suggestion in suggestions {
            if let recipe = suggestion.recipe {
                recipeCount += 1
                let linkedFoodIDs = Set(recipe.foodNames.compactMap {
                    SolidsReferenceCatalog.food(named: $0)?.id
                })
                XCTAssertEqual(
                    Set(suggestion.foods.map(\.id)),
                    linkedFoodIDs,
                    "\(recipe.title) should display and plan the same foods as its linked recipe."
                )
                XCTAssertEqual(suggestion.kind, .recipe)
                XCTAssertTrue(
                    linkedFoodIDs.subtracting([suggestion.foods[0].id]).isSubset(of: familiarFoodIDs),
                    "\(recipe.title) should not introduce an unfamiliar companion ingredient."
                )
            }
            familiarFoodIDs.formUnion(suggestion.foods.map(\.id))
        }
        XCTAssertGreaterThan(recipeCount, 0)
    }

    func testCatalogIndexesPreserveFoodRecipeAndSearchResults() throws {
        let foods = SolidsReferenceCatalog.foods
        let recipes = SolidsReferenceCatalog.recipes

        for recipe in recipes {
            XCTAssertEqual(SolidsReferenceCatalog.recipe(id: recipe.id), recipe)
        }

        for food in foods {
            XCTAssertEqual(SolidsReferenceCatalog.food(id: food.id), food)
            for lookupName in [food.name] + food.aliases {
                let key = SolidFoodSelection.normalizedName(lookupName)
                let expected = foods.first { candidate in
                    SolidFoodSelection.normalizedName(candidate.name) == key
                        || candidate.aliases.contains {
                            SolidFoodSelection.normalizedName($0) == key
                        }
                }
                XCTAssertEqual(SolidsReferenceCatalog.food(named: lookupName), expected, lookupName)
            }

            let expectedRecipeIDs = recipes.filter { recipe in
                recipe.foodNames.contains {
                    SolidsReferenceCatalog.food(named: $0)?.id == food.id
                }
            }.map(\.id)
            XCTAssertEqual(
                SolidsReferenceCatalog.recipes(containingFoodID: food.id).map(\.id),
                expectedRecipeIDs,
                food.name
            )
        }

        for query in ["berry", "chickpea", "sweet potato", "yogurt"] {
            let expectedFoodIDs = foods.filter { food in
                ([food.name] + food.aliases).contains {
                    SolidFoodSelection.normalizedName($0)
                        .contains(SolidFoodSelection.normalizedName(query))
                }
            }.map(\.id)
            XCTAssertEqual(SolidsReferenceCatalog.search(query).map(\.id), expectedFoodIDs, query)

            let expectedRecipeIDs = recipes.filter { recipe in
                recipe.title.localizedCaseInsensitiveContains(query)
                    || recipe.foodNames.contains { $0.localizedCaseInsensitiveContains(query) }
            }.map(\.id)
            XCTAssertEqual(SolidsReferenceCatalog.searchRecipes(query).map(\.id), expectedRecipeIDs, query)
        }

        for allergen in SolidsAllergen.allCases {
            XCTAssertEqual(
                SolidsReferenceCatalog.recipes(containingAllergenID: allergen.rawValue).map(\.id),
                recipes.filter { $0.allergenIDs.contains(allergen.rawValue) }.map(\.id)
            )
        }
    }

    func testCatalogSeparatesConfirmedAndPossibleAllergens() throws {
        let egg = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Egg"))
        XCTAssertEqual(egg.allergenIDs, [SolidsAllergen.egg.rawValue])
        XCTAssertTrue(egg.possibleAllergenIDs.isEmpty)

        let waffle = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Waffle"))
        XCTAssertTrue(waffle.allergenIDs.isEmpty)
        XCTAssertTrue(waffle.possibleAllergenIDs.contains(SolidsAllergen.wheat.rawValue))
        XCTAssertFalse(waffle.servingVisuals.isEmpty)
        XCTAssertFalse(waffle.chokingGuidance.isEmpty)
    }

    func testIngredientNamesDoNotCreateSubstringAllergenFalsePositives() throws {
        let eggplant = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Eggplant"))
        XCTAssertFalse(eggplant.allergenIDs.contains(SolidsAllergen.egg.rawValue))

        let milkfish = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Milkfish"))
        XCTAssertFalse(milkfish.allergenIDs.contains(SolidsAllergen.milk.rawValue))
        XCTAssertTrue(milkfish.allergenIDs.contains(SolidsAllergen.fish.rawValue))

        let hummus = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Hummus"))
        XCTAssertTrue(hummus.possibleAllergenIDs.contains(SolidsAllergen.sesame.rawValue))

        let zaatar = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Za'atar herb blend"))
        XCTAssertTrue(zaatar.possibleAllergenIDs.contains(SolidsAllergen.sesame.rawValue))
    }

    @MainActor
    func testMajorAllergenMetadata() throws {
        XCTAssertEqual(try XCTUnwrap(SolidsReferenceCatalog.food(named: "Peanut butter")).allergenIDs, ["peanuts"])
        XCTAssertEqual(try XCTUnwrap(SolidsReferenceCatalog.food(named: "Egg")).allergenIDs, ["egg"])
        XCTAssertTrue(try XCTUnwrap(SolidsReferenceCatalog.food(named: "Tahini")).allergenIDs.contains("sesame"))
        XCTAssertTrue(try XCTUnwrap(SolidsReferenceCatalog.food(named: "Tofu")).allergenIDs.contains("soy"))

        let introduced = Set(SolidsAllergen.allCases.map(\.rawValue))
        for allergen in SolidsAllergen.allCases {
            XCTAssertFalse(
                SolidsTrackingService.recommendedRecipes(
                    for: allergen,
                    ageMonths: 12,
                    introducedAllergenIDs: introduced
                ).isEmpty,
                "Missing a plannable recipe for \(allergen.displayName)"
            )
        }
    }

    @MainActor
    func testSolidsAccessIsChildAndAgeScoped() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oneMonthOld = calendar.date(byAdding: .month, value: -1, to: now)!
        let fiveMonthsOld = calendar.date(byAdding: .month, value: -5, to: now)!
        let sixMonthsOld = calendar.date(byAdding: .month, value: -6, to: now)!

        let infant = CareProfile(name: "Test Child", birthDate: oneMonthOld)
        XCTAssertEqual(
            SolidsTrackingService.accessLevel(for: infant, events: [], state: nil, now: now, calendar: calendar),
            .hidden
        )

        let previewChild = CareProfile(name: "Test Child", birthDate: fiveMonthsOld)
        XCTAssertEqual(
            SolidsTrackingService.accessLevel(for: previewChild, events: [], state: nil, now: now, calendar: calendar),
            .readinessPreview
        )

        let eligibleChild = CareProfile(name: "Test Child", birthDate: sixMonthsOld)
        XCTAssertEqual(
            SolidsTrackingService.accessLevel(for: eligibleChild, events: [], state: nil, now: now, calendar: calendar),
            .full
        )

        let dog = CareProfile(profileType: .dog, name: "Test Dog", birthDate: sixMonthsOld)
        XCTAssertEqual(
            SolidsTrackingService.accessLevel(for: dog, events: [], state: nil, now: now, calendar: calendar),
            .hidden
        )
    }

    func testSolidsReportingSummarizesTheSelectedPeriodWithoutDoubleCountingAllergens() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let profileID = UUID()
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12))!
        let secondDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!
        let periodStart = calendar.startOfDay(for: firstDay)
        let periodEnd = calendar.startOfDay(for: secondDay)

        let firstMeal = CareEvent(
            profileID: profileID,
            type: .feed,
            startDate: firstDay,
            startTimeZoneIdentifier: "UTC"
        )
        firstMeal.feedKind = .solid
        let secondMeal = CareEvent(
            profileID: profileID,
            type: .feed,
            startDate: secondDay,
            startTimeZoneIdentifier: "UTC"
        )
        secondMeal.feedKind = .solid

        let items = [
            SolidFoodEventItem(
                eventID: firstMeal.id,
                profileID: profileID,
                foodID: "egg",
                foodNameSnapshot: "Egg",
                allergenIDs: ["egg"],
                suspectedReaction: true,
                createdAt: firstDay
            ),
            SolidFoodEventItem(
                eventID: firstMeal.id,
                profileID: profileID,
                foodID: "egg-yolk",
                foodNameSnapshot: "Egg yolk",
                allergenIDs: ["egg"],
                createdAt: firstDay
            ),
            SolidFoodEventItem(
                eventID: secondMeal.id,
                profileID: profileID,
                foodID: "avocado",
                foodNameSnapshot: "Avocado",
                createdAt: secondDay
            )
        ]
        let progress = [
            SolidFoodProgress(
                profileID: profileID,
                foodID: "egg",
                foodNameSnapshot: "Egg",
                status: .tried,
                firstTriedAt: firstDay
            ),
            SolidFoodProgress(
                profileID: profileID,
                foodID: "avocado",
                foodNameSnapshot: "Avocado",
                status: .tried,
                firstTriedAt: secondDay
            )
        ]

        let report = SolidsReportingService.snapshot(
            profileID: profileID,
            events: [firstMeal, secondMeal],
            eventItems: items,
            progress: progress,
            period: periodStart...periodEnd,
            calendar: calendar
        )

        XCTAssertEqual(report.mealCount, 2)
        XCTAssertEqual(report.uniqueFoodCount, 3)
        XCTAssertEqual(report.newFoodCount, 2)
        XCTAssertEqual(report.allergenExposureCount, 1)
        XCTAssertEqual(report.reactionObservationCount, 1)
        XCTAssertEqual(report.daily.map(\.meals), [1, 1])
        XCTAssertEqual(report.daily.map(\.newFoods), [1, 1])
    }

    @MainActor
    func testSolidLogCreatesFoodExposureRecords() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: configuration
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -8, to: Date())!
        )
        let event = CareEvent(profileID: profile.id, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Avocado, Egg"
        context.insert(profile)
        context.insert(event)

        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: SolidFeedEditorPreset(
                foodIDs: ["avocado", "egg"],
                foodNames: ["Avocado", "Egg"]
            ),
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )

        let items = try context.fetch(FetchDescriptor<SolidFoodEventItem>())
        let progress = try context.fetch(FetchDescriptor<SolidFoodProgress>())
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(progress.count, 2)
        XCTAssertTrue(progress.allSatisfy { $0.status == .tried && $0.exposureCount == 1 })
        XCTAssertEqual(items.first(where: { $0.foodID == "egg" })?.allergenIDs, ["egg"])
    }

    @MainActor
    func testBackfillBatchesAFullHistoryWithoutLosingProgress() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        )
        context.insert(profile)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let events = (0..<24).map { index in
            let event = CareEvent(
                profileID: profile.id,
                type: .feed,
                startDate: start.addingTimeInterval(Double(index) * 86_400)
            )
            event.feedKind = .solid
            let isEgg = index.isMultiple(of: 2)
            event.foodDescription = isEgg ? "Egg" : "Avocado"
            event.solidFoodDetails = [
                SolidFoodLogDetail(
                    foodID: isEgg ? "egg" : "avocado",
                    foodName: isEgg ? "Egg" : "Avocado",
                    allergenIDs: isEgg ? [SolidsAllergen.egg.rawValue] : [],
                    confirmedAllergenPortionIDs: isEgg ? [SolidsAllergen.egg.rawValue] : []
                )
            ]
            context.insert(event)
            return event
        }

        SolidsTrackingService.backfillProgress(
            profileID: profile.id,
            events: events,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )
        // A second screen can briefly hold stale query arrays. The backfill
        // must remain idempotent without falling back to per-event rewrites.
        SolidsTrackingService.backfillProgress(
            profileID: profile.id,
            events: events,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolidFoodEventItem>()), 24)
        let progress = try context.fetch(FetchDescriptor<SolidFoodProgress>())
        XCTAssertEqual(progress.first { $0.foodID == "egg" }?.exposureCount, 12)
        XCTAssertEqual(progress.first { $0.foodID == "avocado" }?.exposureCount, 12)
        let allergen = try XCTUnwrap(context.fetch(FetchDescriptor<SolidAllergenProgress>()).first)
        XCTAssertEqual(allergen.introductionStep, 3)
        XCTAssertEqual(allergen.status, .tolerated)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<SolidsProfileState>()).first).isActivated)
    }

    @MainActor
    func testPerFoodReactionDetailsStayAttributedToTheCorrectFood() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -8, to: Date())!
        )
        let event = CareEvent(profileID: profile.id, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Avocado, Egg"
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "avocado",
                foodName: "Avocado",
                preference: .liked
            ),
            SolidFoodLogDetail(
                foodID: "egg",
                foodName: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue],
                preference: .disliked,
                servingAmount: "2 tsp",
                suspectedReaction: true,
                symptoms: [.hivesOrRash],
                severity: .mild,
                onsetMinutes: 15,
                durationMinutes: 30,
                responseNotes: "Observed and documented.",
                followUp: .discussWithClinician
            )
        ]
        context.insert(profile)
        context.insert(event)

        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: nil,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )

        let items = try context.fetch(FetchDescriptor<SolidFoodEventItem>())
        let egg = try XCTUnwrap(items.first { $0.foodID == "egg" })
        let avocado = try XCTUnwrap(items.first { $0.foodID == "avocado" })
        XCTAssertTrue(egg.suspectedReaction)
        XCTAssertEqual(egg.symptoms, [.hivesOrRash])
        XCTAssertEqual(egg.onsetMinutes, 15)
        XCTAssertEqual(egg.servingAmount, "2 tsp")
        XCTAssertEqual(egg.followUp, .discussWithClinician)
        XCTAssertFalse(avocado.suspectedReaction)
        XCTAssertTrue(avocado.allergenIDs.isEmpty)

        let allergen = try XCTUnwrap(
            context.fetch(FetchDescriptor<SolidAllergenProgress>()).first
        )
        XCTAssertEqual(allergen.allergenID, SolidsAllergen.egg.rawValue)
        XCTAssertEqual(allergen.status, .suspectedReaction)
        XCTAssertEqual(allergen.exposureMealCount, 1)
    }

    @MainActor
    func testReconcileSolidFeedRemovesDerivedRecordsAfterKindChanges() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -8, to: Date())!
        )
        let event = CareEvent(profileID: profile.id, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Egg"
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "egg",
                foodName: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue]
            )
        ]
        context.insert(profile)
        context.insert(event)

        SolidsTrackingService.reconcileSolidFeed(event: event, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SolidFoodEventItem>()).count, 1)

        event.feedKind = .bottle
        event.solidFoodDetails = []
        SolidsTrackingService.reconcileSolidFeed(event: event, context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<SolidFoodEventItem>()).isEmpty)
        let progress = try XCTUnwrap(context.fetch(FetchDescriptor<SolidFoodProgress>()).first)
        XCTAssertEqual(progress.exposureCount, 0)
        XCTAssertEqual(progress.status, .notTried)
        let allergen = try XCTUnwrap(context.fetch(FetchDescriptor<SolidAllergenProgress>()).first)
        XCTAssertEqual(allergen.exposureMealCount, 0)
        XCTAssertEqual(allergen.status, .notStarted)
    }

    @MainActor
    func testDeletingAnEventRemovesPreviouslyDerivedSolidRecordsAfterItsTypeChanges() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -8, to: Date())!
        )
        let event = CareEvent(profileID: profile.id, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Egg"
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "egg",
                foodName: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue]
            )
        ]
        context.insert(profile)
        context.insert(event)

        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: nil,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<SolidFoodEventItem>()).count, 1)

        // Imported or interrupted edits can leave derived records attached to
        // an event whose primary type has already changed.
        event.type = .custom
        await EventMutationService.delete(
            event,
            profile: profile,
            events: [event],
            records: [],
            context: context,
            settings: .default,
            notificationsEnabled: false,
            notificationLeadMinutes: 10
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<SolidFoodEventItem>()).isEmpty)
    }

    @MainActor
    func testRepeatedSolidFeedPreservesDetailsAndUpdatesTracking() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -8, to: Date())!
        )
        let source = CareEvent(profileID: profile.id, type: .feed)
        source.feedKind = .solid
        source.endDate = source.startDate
        source.foodDescription = "Egg"
        source.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "egg",
                foodName: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue],
                preference: .liked,
                servingAmount: "2 tsp"
            )
        ]
        context.insert(profile)
        context.insert(source)

        let repeated = try XCTUnwrap(EventMutationService.repeatEvent(
            source,
            caregiverName: "Caregiver 1",
            profileID: profile.id,
            profileType: .child,
            context: context,
            at: source.startDate.addingTimeInterval(3_600)
        ))
        XCTAssertEqual(repeated.solidFoodDetails, source.solidFoodDetails)

        SolidsTrackingService.reconcileSolidFeed(event: repeated, context: context)
        let items = try context.fetch(FetchDescriptor<SolidFoodEventItem>())
            .filter { $0.eventID == repeated.id }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.servingAmount, "2 tsp")
        XCTAssertEqual(items.first?.reaction, .liked)
    }

    @MainActor
    func testEditingAnOlderMealPreservesChronologicalFirstAndLastExposure() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let olderDate = Date(timeIntervalSince1970: 2_000_000_000)
        let newerDate = olderDate.addingTimeInterval(86_400)
        let older = CareEvent(profileID: profileID, type: .feed, startDate: olderDate)
        older.feedKind = .solid
        older.foodDescription = "Egg"
        older.solidFoodDetails = [
            SolidFoodLogDetail(foodID: "egg", foodName: "Egg", preference: .liked)
        ]
        let newer = CareEvent(profileID: profileID, type: .feed, startDate: newerDate)
        newer.feedKind = .solid
        newer.foodDescription = "Egg"
        newer.solidFoodDetails = [
            SolidFoodLogDetail(foodID: "egg", foodName: "Egg", preference: .disliked)
        ]
        context.insert(older)
        context.insert(newer)

        SolidsTrackingService.recordSolidFeed(
            event: older,
            preset: nil,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )
        SolidsTrackingService.recordSolidFeed(
            event: newer,
            preset: nil,
            eventItems: [],
            progress: try context.fetch(FetchDescriptor<SolidFoodProgress>()),
            plans: [],
            profileStates: [],
            context: context
        )

        older.solidFoodDetails = [
            SolidFoodLogDetail(foodID: "egg", foodName: "Egg", preference: .loved)
        ]
        SolidsTrackingService.recordSolidFeed(
            event: older,
            preset: nil,
            eventItems: [],
            progress: try context.fetch(FetchDescriptor<SolidFoodProgress>()),
            plans: [],
            profileStates: [],
            context: context
        )

        let record = try XCTUnwrap(context.fetch(FetchDescriptor<SolidFoodProgress>()).first)
        XCTAssertEqual(record.exposureCount, 2)
        XCTAssertEqual(record.firstTriedAt, olderDate)
        XCTAssertEqual(record.lastTriedAt, newerDate)
        XCTAssertEqual(record.lastReactionRawValue, SolidReaction.disliked.rawValue)
    }

    @MainActor
    func testGuidedSuggestionsAreAgeAwareAndExcludeReactionAllergens() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: calendar.date(byAdding: .month, value: -9, to: now)!
        )
        let avocadoProgress = SolidFoodProgress(
            profileID: profile.id,
            foodID: "avocado",
            foodNameSnapshot: "Avocado",
            status: .tried,
            exposureCount: 2
        )
        let eggReaction = SolidFoodEventItem(
            eventID: UUID(),
            profileID: profile.id,
            foodID: "egg",
            foodNameSnapshot: "Egg",
            allergenIDs: [SolidsAllergen.egg.rawValue],
            suspectedReaction: true
        )
        let eggProgress = SolidAllergenProgress(
            profileID: profile.id,
            allergenID: SolidsAllergen.egg.rawValue,
            status: .suspectedReaction
        )

        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [avocadoProgress],
            eventItems: [eggReaction],
            allergenProgress: [eggProgress],
            plans: [],
            startingAt: now,
            count: 7,
            calendar: calendar
        )

        XCTAssertEqual(
            suggestions.filter { $0.kind != .familiarRepeat }.count,
            7
        )
        XCTAssertGreaterThanOrEqual(suggestions.count, 7)
        XCTAssertTrue(suggestions.flatMap(\.foods).allSatisfy { $0.minimumAgeMonths <= 9 })
        XCTAssertTrue(suggestions.flatMap(\.foods).allSatisfy {
            !$0.allergenIDs.contains(SolidsAllergen.egg.rawValue)
        })
        XCTAssertTrue(suggestions.dropFirst().allSatisfy { $0.scheduledAt > suggestions[0].scheduledAt })
        XCTAssertTrue(suggestions.contains { $0.foods.contains(where: { $0.isIronRich }) })
    }

    @MainActor
    func testGuidedFirstWeekStartsWithSimpleFoodsAndDeliberateRepeats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: try XCTUnwrap(calendar.date(byAdding: .month, value: -6, to: startDate))
        )

        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            startingAt: startDate,
            count: 7,
            calendar: calendar
        )
        let firstWeek = Array(suggestions.prefix(7))

        XCTAssertEqual(firstWeek.count, 7)
        XCTAssertEqual(firstWeek.map { $0.foods.first?.name }, [
            "Avocado", "Avocado", "Lentil", "Lentil", "Oatmeal", "Oatmeal", "Egg"
        ])
        XCTAssertEqual(firstWeek.map(\.kind), [
            .firstTaste,
            .familiarRepeat,
            .firstTaste,
            .familiarRepeat,
            .firstTaste,
            .familiarRepeat,
            .firstTaste
        ])
        XCTAssertTrue(firstWeek.allSatisfy { $0.recipe == nil && $0.foods.count == 1 })
        XCTAssertEqual(firstWeek.last?.allergenID, SolidsAllergen.egg.rawValue)
        XCTAssertEqual(firstWeek.last?.allergenIntroductionStep, 1)

        let openingIntroductions = firstWeek.filter { $0.kind == .firstTaste }.prefix(3)
        XCTAssertTrue(openingIntroductions.contains { $0.foods.first?.isIronRich == true })
    }

    @MainActor
    func testGuidedAllergensFollowAStableOrderAndCompleteEachSeries() {
        let startDate = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -6, to: startDate)!
        )
        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            startingAt: startDate,
            count: 100
        )

        var seen = Set<String>()
        let allergenOrder = suggestions.compactMap(\.allergenID).filter {
            seen.insert($0).inserted
        }
        XCTAssertEqual(allergenOrder, [
            SolidsAllergen.egg.rawValue,
            SolidsAllergen.peanuts.rawValue,
            SolidsAllergen.milk.rawValue,
            SolidsAllergen.wheat.rawValue,
            SolidsAllergen.soy.rawValue,
            SolidsAllergen.sesame.rawValue,
            SolidsAllergen.treeNuts.rawValue,
            SolidsAllergen.fish.rawValue,
            SolidsAllergen.crustaceanShellfish.rawValue
        ])
        for allergenID in allergenOrder {
            let series = suggestions.filter { $0.allergenID == allergenID }
            XCTAssertEqual(series.compactMap(\.allergenIntroductionStep), [1, 2, 3])
            XCTAssertEqual(Set(series.compactMap { $0.foods.first?.id }).count, 1)
            XCTAssertTrue(series.allSatisfy { $0.recipe == nil && $0.foods.count == 1 })
        }
    }

    @MainActor
    func testGuidedPlansCanBeBuiltShiftedAndSwapped() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -9, to: Date())!
        )
        context.insert(profile)
        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            count: 2
        )
        let created = SolidsTrackingService.buildGuidedPlan(
            from: suggestions,
            profileID: profile.id,
            startingPosition: 1,
            context: context
        )
        XCTAssertEqual(created.count, suggestions.count)
        XCTAssertTrue(created.allSatisfy(\.isGuided))
        XCTAssertTrue(created.allSatisfy { $0.recipeID == nil })
        XCTAssertTrue(created.allSatisfy { $0.foodIDs.count == 1 })

        let originalDate = try XCTUnwrap(created.first?.scheduledAt)
        SolidsTrackingService.shiftUpcomingGuidedPlans(
            profileID: profile.id,
            onOrAfter: originalDate.addingTimeInterval(-1),
            byDays: 1,
            plans: created,
            context: context
        )
        XCTAssertGreaterThan(created[0].scheduledAt, originalDate)

        let replacement = try XCTUnwrap(SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: created,
            startingAt: created[0].scheduledAt,
            count: 1
        ).first)
        let originalFoodIDs = created[0].foodIDs
        SolidsTrackingService.replaceGuidedPlan(created[0], with: replacement, context: context)
        XCTAssertNotEqual(created[0].foodIDs, originalFoodIDs)
    }

    @MainActor
    func testNamedRecipeCollectionsPersistAndRejectDuplicateNames() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let state = SolidsProfileState(profileID: profileID)
        context.insert(state)

        let collection = try XCTUnwrap(SolidsTrackingService.createRecipeCollection(
            name: "Weeknight meals",
            initialRecipeIDs: ["apple-oatmeal"],
            profileID: profileID,
            existingState: state,
            context: context
        ))
        XCTAssertNil(SolidsTrackingService.createRecipeCollection(
            name: "weeknight meals",
            profileID: profileID,
            existingState: state,
            context: context
        ))
        SolidsTrackingService.toggleRecipe(
            recipeID: "avocado-bean-mash",
            collectionID: collection.id,
            profileID: profileID,
            existingState: state,
            context: context
        )
        XCTAssertEqual(Set(state.recipeCollections[0].recipeIDs), ["apple-oatmeal", "avocado-bean-mash"])
        XCTAssertTrue(SolidsTrackingService.renameRecipeCollection(
            collectionID: collection.id,
            name: "Daycare meals",
            profileID: profileID,
            existingState: state,
            context: context
        ))
        XCTAssertEqual(state.recipeCollections[0].name, "Daycare meals")
    }

    @MainActor
    func testDeletingCustomFoodPreservesTrackedHistory() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let customFood = SolidFoodCatalogItem(name: "Family lentil patty")
        let foodID = "custom-\(customFood.id.uuidString.lowercased())"
        let progress = SolidFoodProgress(
            profileID: profileID,
            foodID: foodID,
            foodNameSnapshot: customFood.name,
            status: .tried,
            exposureCount: 1
        )
        let item = SolidFoodEventItem(
            eventID: UUID(),
            profileID: profileID,
            foodID: foodID,
            foodNameSnapshot: customFood.name,
            servingAmount: "1 small piece"
        )
        context.insert(customFood)
        context.insert(progress)
        context.insert(item)
        XCTAssertTrue(SolidFoodCatalogService.delete(customFood, context: context))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolidFoodCatalogItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolidFoodProgress>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SolidFoodEventItem>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SolidFoodProgress>()).first?.foodNameSnapshot, "Family lentil patty")
    }

    func testFoodHistoryRouteRestoresWithoutCatalogRecord() throws {
        let route = FoodRoute.solidFoodHistory("custom-deleted", "Family lentil patty")
        let encoded = try JSONEncoder().encode(route)
        XCTAssertEqual(try JSONDecoder().decode(FoodRoute.self, from: encoded), route)
    }

    func testFilteredFoodTrackerRouteRestoresItsSelection() throws {
        let route = FoodRoute.solidsTracker(.wantToTry)
        let encoded = try JSONEncoder().encode(route)
        XCTAssertEqual(try JSONDecoder().decode(FoodRoute.self, from: encoded), route)
    }

    @MainActor
    func testAllergenProgressCountsUniqueMealsAndMarksThreeAsTolerated() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -9, to: Date())!
        )
        context.insert(profile)
        let baseDate = Date(timeIntervalSince1970: 2_000_000_000)

        for day in 0..<3 {
            let date = Calendar.current.date(byAdding: .day, value: day, to: baseDate)!
            let event = CareEvent(profileID: profile.id, type: .feed, startDate: date)
            event.feedKind = .solid
            event.foodDescription = "Egg"
            event.solidFoodDetails = [
                SolidFoodLogDetail(
                    foodID: "egg",
                    foodName: "Egg",
                    allergenIDs: [SolidsAllergen.egg.rawValue],
                    confirmedAllergenPortionIDs: [SolidsAllergen.egg.rawValue],
                    preference: .liked
                )
            ]
            context.insert(event)
            SolidsTrackingService.recordSolidFeed(
                event: event,
                preset: nil,
                eventItems: [],
                progress: [],
                plans: [],
                profileStates: [],
                context: context,
                now: date
            )
        }

        let records = try context.fetch(FetchDescriptor<SolidAllergenProgress>())
        let egg = try XCTUnwrap(records.first { $0.allergenID == SolidsAllergen.egg.rawValue })
        XCTAssertEqual(egg.exposureMealCount, 3)
        XCTAssertEqual(egg.introductionStep, 3)
        XCTAssertEqual(egg.status, .tolerated)
        XCTAssertNotNil(egg.nextExposureDueAt)
    }

    @MainActor
    func testIncidentalAllergenMealsDoNotCompleteIntroduction() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let baseDate = Date(timeIntervalSince1970: 2_000_000_000)

        for day in 0..<3 {
            let date = Calendar.current.date(byAdding: .day, value: day, to: baseDate)!
            let event = CareEvent(profileID: profileID, type: .feed, startDate: date)
            event.feedKind = .solid
            event.foodDescription = "Egg"
            event.solidFoodDetails = [
                SolidFoodLogDetail(
                    foodID: "egg",
                    foodName: "Egg",
                    allergenIDs: [SolidsAllergen.egg.rawValue],
                    confirmedAllergenPortionIDs: []
                )
            ]
            context.insert(event)
            SolidsTrackingService.recordSolidFeed(
                event: event,
                preset: nil,
                eventItems: [],
                progress: [],
                plans: [],
                profileStates: [],
                context: context,
                now: date
            )
        }

        let egg = try XCTUnwrap(
            context.fetch(FetchDescriptor<SolidAllergenProgress>())
                .first { $0.allergenID == SolidsAllergen.egg.rawValue }
        )
        XCTAssertEqual(egg.exposureMealCount, 3)
        XCTAssertEqual(egg.introductionStep, 0)
        XCTAssertEqual(egg.status, .introducing)
        XCTAssertNil(egg.firstIntroducedAt)
    }

    @MainActor
    func testManualAllergenSafetyOverrideSurvivesReconciliation() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        SolidsTrackingService.updateAllergenStatus(
            .avoidPendingAdvice,
            allergenID: SolidsAllergen.egg.rawValue,
            profileID: profileID,
            notes: "Caregiver choice",
            context: context
        )
        for day in 0..<3 {
            context.insert(SolidFoodEventItem(
                eventID: UUID(),
                profileID: profileID,
                foodID: "egg",
                foodNameSnapshot: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue],
                confirmedAllergenPortionIDs: [SolidsAllergen.egg.rawValue],
                createdAt: Date().addingTimeInterval(Double(day) * 86_400)
            ))
        }

        SolidsTrackingService.reconcileAllergenProgress(profileID: profileID, context: context)

        let egg = try XCTUnwrap(context.fetch(FetchDescriptor<SolidAllergenProgress>()).first)
        XCTAssertEqual(egg.introductionStep, 3)
        XCTAssertEqual(egg.status, .avoidPendingAdvice)
        XCTAssertEqual(egg.statusOverride, .avoidPendingAdvice)
    }

    @MainActor
    func testManualReactionOverridePersistsUntilANewReactionIsLogged() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        context.insert(SolidFoodEventItem(
            eventID: UUID(),
            profileID: profileID,
            foodID: "egg",
            foodNameSnapshot: "Egg",
            allergenIDs: [SolidsAllergen.egg.rawValue],
            confirmedAllergenPortionIDs: [SolidsAllergen.egg.rawValue],
            suspectedReaction: true
        ))
        SolidsTrackingService.reconcileAllergenProgress(profileID: profileID, context: context)
        let egg = try XCTUnwrap(context.fetch(FetchDescriptor<SolidAllergenProgress>()).first)
        XCTAssertEqual(egg.status, .suspectedReaction)

        SolidsTrackingService.updateAllergenStatus(
            .tolerated,
            allergenID: SolidsAllergen.egg.rawValue,
            profileID: profileID,
            notes: "Caregiver reviewed",
            context: context
        )
        SolidsTrackingService.reconcileAllergenProgress(profileID: profileID, context: context)
        XCTAssertEqual(egg.status, .tolerated)
        XCTAssertEqual(egg.statusOverride, .tolerated)

        let newReaction = CareEvent(profileID: profileID, type: .feed)
        newReaction.feedKind = .solid
        newReaction.foodDescription = "Egg"
        newReaction.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "egg",
                foodName: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue],
                confirmedAllergenPortionIDs: [],
                suspectedReaction: true
            )
        ]
        context.insert(newReaction)
        SolidsTrackingService.recordSolidFeed(
            event: newReaction,
            preset: nil,
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )
        XCTAssertNil(egg.statusOverride)
        XCTAssertEqual(egg.status, .suspectedReaction)
        XCTAssertNil(egg.nextExposureDueAt)
    }

    @MainActor
    func testGuidedJourneyUsesChosenDateAndTracksObservedSkills() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let chosenDate = Date(timeIntervalSince1970: 2_010_000_000)
        let state = SolidsProfileState(profileID: profileID)
        context.insert(state)

        SolidsTrackingService.startGuidedPath(
            profileID: profileID,
            existingState: state,
            context: context,
            startDate: chosenDate
        )
        SolidsTrackingService.toggleFeedingSkill(
            .usesPreloadedSpoon,
            profileID: profileID,
            existingState: state,
            context: context
        )

        XCTAssertEqual(state.guidedStartDate, chosenDate)
        XCTAssertEqual(state.completedFeedingSkillIDs, [SolidsFeedingSkill.usesPreloadedSpoon.rawValue])
    }

    @MainActor
    func testSolidsWriterPoolReusesBackgroundActorsPerContainer() async throws {
        let schema = PersistenceService.schema
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "SolidsWriterPoolTests-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )

        let firstPlanWriter = await SolidsWriterPool.shared.planWriter(for: container)
        let repeatedPlanWriter = await SolidsWriterPool.shared.planWriter(for: container)
        let firstFoodWriter = await SolidsWriterPool.shared.foodProgressWriter(for: container)
        let repeatedFoodWriter = await SolidsWriterPool.shared.foodProgressWriter(for: container)

        XCTAssertTrue(firstPlanWriter === repeatedPlanWriter)
        XCTAssertTrue(firstFoodWriter === repeatedFoodWriter)
    }

    @MainActor
    func testBackgroundFeedingSkillWriterKeepsTheNewestSnapshot() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        container.mainContext.insert(SolidsProfileState(profileID: profileID))
        try container.mainContext.save()
        let writer = SolidsFeedingSkillWriter(modelContainer: container)
        let newestSkills: Set<String> = [
            SolidsFeedingSkill.bringsFoodToMouth.rawValue,
            SolidsFeedingSkill.usesPreloadedSpoon.rawValue
        ]

        await writer.schedulePersistence(
            profileID: profileID,
            completedSkillIDs: [SolidsFeedingSkill.bringsFoodToMouth.rawValue],
            revision: 1
        )
        await writer.schedulePersistence(
            profileID: profileID,
            completedSkillIDs: newestSkills,
            revision: 2
        )
        try await Task.sleep(for: .seconds(1))
        let staleWriteError = await writer.persist(
            profileID: profileID,
            completedSkillIDs: [],
            revision: 1
        )
        XCTAssertNil(staleWriteError)

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let savedState = try XCTUnwrap(verificationContext.fetch(descriptor).first)
        XCTAssertEqual(Set(savedState.completedFeedingSkillIDs), newestSkills)
    }

    @MainActor
    func testBackgroundFoodProgressWriterCoalescesRapidChanges() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let writer = SolidsFoodProgressWriter(modelContainer: container)

        await writer.scheduleStatus(
            .wantToTry,
            profileID: profileID,
            foodID: "banana",
            foodName: "Banana",
            revision: 1
        )
        await writer.scheduleStatus(
            .notTried,
            profileID: profileID,
            foodID: "banana",
            foodName: "Banana",
            revision: 2
        )
        await writer.scheduleFavorite(
            true,
            profileID: profileID,
            foodID: "banana",
            foodName: "Banana",
            revision: 1
        )
        await writer.scheduleNotes(
            "Soft spears worked well.",
            profileID: profileID,
            foodID: "banana",
            foodName: "Banana",
            revision: 1
        )
        try await Task.sleep(for: .milliseconds(450))

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<SolidFoodProgress>(
            predicate: #Predicate { $0.profileID == profileID && $0.foodID == "banana" }
        )
        let record = try XCTUnwrap(verificationContext.fetch(descriptor).first)
        XCTAssertEqual(record.status, .notTried)
        XCTAssertTrue(record.isFavorite)
        XCTAssertEqual(record.notes, "Soft spears worked well.")
    }

    @MainActor
    func testBackgroundRecipeWriterPersistsLatestPreferencesAndMembership() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let collection = SolidRecipeCollection(name: "Daycare")
        container.mainContext.insert(SolidsProfileState(
            profileID: profileID,
            recipeCollections: [collection]
        ))
        try container.mainContext.save()
        let writer = SolidsRecipePreferenceWriter(modelContainer: container)

        let firstFavoriteError = await writer.setFavorite(
            true,
            recipeID: "banana-oat-mash",
            profileID: profileID,
            revision: 1
        )
        let latestFavoriteError = await writer.setFavorite(
            false,
            recipeID: "banana-oat-mash",
            profileID: profileID,
            revision: 2
        )
        let wantToTryError = await writer.setWantToTry(
            true,
            recipeID: "banana-oat-mash",
            profileID: profileID,
            revision: 1
        )
        let membershipError = await writer.setMembership(
            true,
            recipeID: "banana-oat-mash",
            collectionID: collection.id,
            profileID: profileID,
            revision: 1
        )
        let newCollectionID = UUID()
        let createCollectionError = await writer.createCollection(
            id: newCollectionID,
            name: "Weekend",
            initialRecipeIDs: ["banana-oat-mash"],
            profileID: profileID
        )
        let renameCollectionError = await writer.renameCollection(
            id: newCollectionID,
            name: "Weekend Meals",
            profileID: profileID
        )
        XCTAssertNil(firstFavoriteError)
        XCTAssertNil(latestFavoriteError)
        XCTAssertNil(wantToTryError)
        XCTAssertNil(membershipError)
        XCTAssertNil(createCollectionError)
        XCTAssertNil(renameCollectionError)

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = try XCTUnwrap(verificationContext.fetch(descriptor).first)
        XCTAssertFalse(state.favoriteRecipeIDs.contains("banana-oat-mash"))
        XCTAssertTrue(state.wantToTryRecipeIDs.contains("banana-oat-mash"))
        XCTAssertTrue(state.recipeCollections.first?.recipeIDs.contains("banana-oat-mash") == true)
        XCTAssertTrue(state.recipeCollections.contains {
            $0.id == newCollectionID
                && $0.name == "Weekend Meals"
                && $0.recipeIDs.contains("banana-oat-mash")
        })

        let deleteCollectionError = await writer.deleteCollection(
            id: newCollectionID,
            profileID: profileID
        )
        XCTAssertNil(deleteCollectionError)
        let deletionContext = ModelContext(container)
        let deletedState = try XCTUnwrap(deletionContext.fetch(descriptor).first)
        XCTAssertFalse(deletedState.recipeCollections.contains { $0.id == newCollectionID })
    }

    @MainActor
    func testBackgroundActivationAndShoppingWritersPersistWithoutMainContextSaves() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let householdID = UUID()
        let list = ShoppingList(householdID: householdID, name: "Groceries")
        container.mainContext.insert(list)
        try container.mainContext.save()

        let stateWriter = SolidsProfileStateWriter(modelContainer: container)
        let activationError = await stateWriter.activate(profileID: profileID)
        XCTAssertNil(activationError)
        let shoppingWriter = SolidsShoppingListWriter(modelContainer: container)
        let listID = list.id
        let firstAdd = await shoppingWriter.addFoods(
            [
                SolidsShoppingFoodWrite(foodID: "banana", foodName: "Banana"),
                SolidsShoppingFoodWrite(foodID: "avocado", foodName: "Avocado")
            ],
            listID: listID,
            householdID: householdID
        )
        XCTAssertNil(firstAdd.error)
        XCTAssertEqual(firstAdd.count, 2)
        let duplicateAdd = await shoppingWriter.addFoods(
            [SolidsShoppingFoodWrite(foodID: "banana", foodName: "Banana")],
            listID: listID,
            householdID: householdID
        )
        XCTAssertNil(duplicateAdd.error)
        XCTAssertEqual(duplicateAdd.count, 0)

        let verificationContext = ModelContext(container)
        let stateDescriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        XCTAssertTrue(try XCTUnwrap(verificationContext.fetch(stateDescriptor).first).isActivated)
        let itemDescriptor = FetchDescriptor<ShoppingListItem>(
            predicate: #Predicate { $0.shoppingListID == listID }
        )
        XCTAssertEqual(try verificationContext.fetch(itemDescriptor).count, 2)
    }

    @MainActor
    func testBackgroundAllergenWriterDoesNotLoseNotes() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let allergenID = SolidsAllergen.peanuts.rawValue
        let writer = SolidsAllergenProgressWriter(modelContainer: container)

        let firstError = await writer.setNotes(
            "Served stirred into oatmeal.",
            allergenID: allergenID,
            profileID: profileID,
            revision: 1
        )
        let latestError = await writer.setNotes(
            "Served thinly stirred into oatmeal.",
            allergenID: allergenID,
            profileID: profileID,
            revision: 2
        )
        let statusError = await writer.setStatus(
            .tolerated,
            allergenID: allergenID,
            profileID: profileID,
            revision: 1
        )
        let clearOverrideError = await writer.clearStatusOverride(
            allergenID: allergenID,
            profileID: profileID,
            revision: 2
        )
        XCTAssertNil(firstError)
        XCTAssertNil(latestError)
        XCTAssertNil(statusError)
        XCTAssertNil(clearOverrideError)

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<SolidAllergenProgress>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.allergenID == allergenID
            }
        )
        let record = try XCTUnwrap(verificationContext.fetch(descriptor).first)
        XCTAssertEqual(record.notes, "Served thinly stirred into oatmeal.")
        XCTAssertNil(record.statusOverride)
        XCTAssertEqual(record.status, .notStarted)
    }

    @MainActor
    func testBackgroundGuidedPlanWriterBuildsTheJourneyInOneTransaction() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let startDate = Date(timeIntervalSince1970: 2_010_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -8, to: startDate)!
        )
        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            startingAt: startDate,
            count: 12
        )
        let writes = suggestions.enumerated().map { index, suggestion in
            SolidsGuidedPlanWrite(suggestion: suggestion, guidedPosition: index + 1)
        }
        let writer = SolidsGuidedPlanWriter(modelContainer: container)

        let result = await writer.buildJourney(
            profileID: profileID,
            startDate: startDate,
            writes: writes
        )

        XCTAssertNil(result.error)
        XCTAssertEqual(result.count, writes.count)
        let shiftResult = await writer.shiftUpcomingPlans(
            profileID: profileID,
            onOrAfter: .distantPast,
            byDays: 1,
            now: startDate
        )
        XCTAssertNil(shiftResult.error)
        XCTAssertEqual(shiftResult.count, writes.count)
        let verificationContext = ModelContext(container)
        let planDescriptor = FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let plans = try verificationContext.fetch(planDescriptor)
        XCTAssertEqual(plans.count, writes.count)
        XCTAssertEqual(Set(plans.compactMap(\.guidedPosition)), Set(1...writes.count))
        XCTAssertTrue(plans.allSatisfy(\.isGuided))
        for (plan, write) in zip(
            plans.sorted { ($0.guidedPosition ?? 0) < ($1.guidedPosition ?? 0) },
            writes.sorted { $0.guidedPosition < $1.guidedPosition }
        ) {
            XCTAssertEqual(
                plan.scheduledAt,
                Calendar.current.date(byAdding: .day, value: 1, to: write.scheduledAt)
            )
        }

        let stateDescriptor = FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        let state = try XCTUnwrap(verificationContext.fetch(stateDescriptor).first)
        XCTAssertTrue(state.isActivated)
        XCTAssertEqual(state.guidedStartDate, startDate)
    }

    @MainActor
    func testBackgroundPlanWriterCreatesUpdatesAndDeletesWithoutMainContextWrites() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let scheduledAt = Date(timeIntervalSince1970: 2_020_000_000)
        let writer = SolidsPlanWriter(modelContainer: container)

        let created = await writer.saveEditorPlan(SolidsPlanEditorWrite(
            planID: nil,
            profileID: profileID,
            scheduledAt: scheduledAt,
            foodIDs: ["banana"],
            foodNames: ["Banana"],
            notes: "Serve soft.",
            reminderEnabled: false,
            reminderOffsetMinutes: 30
        ))
        XCTAssertNil(created.error)
        let planID = try XCTUnwrap(created.planID)

        let updated = await writer.saveEditorPlan(SolidsPlanEditorWrite(
            planID: planID,
            profileID: profileID,
            scheduledAt: scheduledAt.addingTimeInterval(3_600),
            foodIDs: ["banana", "avocado"],
            foodNames: ["Banana", "Avocado"],
            notes: "Updated notes.",
            reminderEnabled: false,
            reminderOffsetMinutes: 15
        ))
        XCTAssertNil(updated.error)
        XCTAssertEqual(updated.planID, planID)

        var verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.id == planID }
        )
        let plan = try XCTUnwrap(verificationContext.fetch(descriptor).first)
        XCTAssertEqual(plan.foodIDs, ["banana", "avocado"])
        XCTAssertEqual(plan.notes, "Updated notes.")
        XCTAssertEqual(plan.reminderOffsetMinutes, 15)

        let deleteError = await writer.deletePlans([planID])
        XCTAssertNil(deleteError)
        verificationContext = ModelContext(container)
        descriptor = FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.id == planID }
        )
        XCTAssertNil(try verificationContext.fetch(descriptor).first)
    }

    @MainActor
    func testTomorrowPlanDuplicatePoliciesReturnExistingMealInsteadOfCreatingAnother() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let tomorrow = Date(timeIntervalSince1970: 2_020_000_000)
        let writer = SolidsPlanWriter(modelContainer: container)

        let recipeWrite = SolidsPlanEditorWrite(
            planID: nil,
            profileID: profileID,
            scheduledAt: tomorrow,
            foodIDs: ["avocado", "black-bean"],
            foodNames: ["Avocado", "Black bean"],
            notes: "Avocado bean mash",
            reminderEnabled: false,
            reminderOffsetMinutes: 30,
            title: "Avocado bean mash",
            recipeID: "avocado-bean-mash",
            duplicatePolicy: .matchingRecipeOnDay
        )
        let firstRecipeResult = await writer.saveEditorPlan(recipeWrite)
        let duplicateRecipeResult = await writer.saveEditorPlan(recipeWrite)

        XCTAssertNil(firstRecipeResult.error)
        XCTAssertNil(duplicateRecipeResult.error)
        XCTAssertEqual(duplicateRecipeResult.planID, firstRecipeResult.planID)
        XCTAssertTrue(duplicateRecipeResult.wasAlreadyPresent)

        let customFoodWrite = SolidsPlanEditorWrite(
            planID: nil,
            profileID: profileID,
            scheduledAt: tomorrow.addingTimeInterval(3_600),
            foodIDs: ["custom-sample"],
            foodNames: ["Sample food"],
            notes: "",
            reminderEnabled: false,
            reminderOffsetMinutes: 30,
            duplicatePolicy: .containingSelectedFoodOnDay
        )
        let firstCustomResult = await writer.saveEditorPlan(customFoodWrite)
        let duplicateCustomResult = await writer.saveEditorPlan(customFoodWrite)

        XCTAssertNil(firstCustomResult.error)
        XCTAssertNil(duplicateCustomResult.error)
        XCTAssertEqual(duplicateCustomResult.planID, firstCustomResult.planID)
        XCTAssertTrue(duplicateCustomResult.wasAlreadyPresent)

        let verificationContext = ModelContext(container)
        let profilePlans = try verificationContext.fetch(FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.profileID == profileID }
        ))
        XCTAssertEqual(profilePlans.count, 2)
    }

    @MainActor
    func testGuidedJourneyCanBuildACompleteFirstHundred() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -6, to: now)!
        )
        let suggestions = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            startingAt: now,
            count: 100
        )
        let introductions = suggestions.filter { $0.kind != .familiarRepeat }
        XCTAssertEqual(introductions.count, 100)
        XCTAssertEqual(Set(introductions.map { $0.foods[0].id }).count, 100)
    }

    @MainActor
    func testFeedingSkillsRepersonalizeWithoutRebuildingTheJourney() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scheduledAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 11, minute: 30))
        )
        let profile = CareProfile(
            name: "Test Child",
            birthDate: try XCTUnwrap(calendar.date(byAdding: .month, value: -12, to: scheduledAt))
        )
        let food = try XCTUnwrap(SolidsReferenceCatalog.food(named: "Apple"))
        let original = SolidsGuidedMealSuggestion(
            dayOffset: 4,
            scheduledAt: scheduledAt,
            foods: [food],
            recipe: SolidsReferenceCatalog.recipes.first,
            stage: .firstBites,
            preparationNotes: "Original notes"
        )

        let updated = try XCTUnwrap(SolidsTrackingService.applyingFeedingSkills(
            to: [original],
            for: profile,
            completedSkillIDs: [SolidsFeedingSkill.scoopsWithUtensil.rawValue],
            calendar: calendar
        ).first)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.scheduledAt, original.scheduledAt)
        XCTAssertEqual(updated.foods, original.foods)
        XCTAssertEqual(updated.recipe, original.recipe)
        XCTAssertEqual(updated.stage, original.stage)
        XCTAssertNotEqual(updated.preparationNotes, original.preparationNotes)
        XCTAssertTrue(updated.preparationNotes.contains("For observed skills:"))
    }

    @MainActor
    func testGuidedAllergenStepsOnlyCountConfirmedIntroductionPortions() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -9, to: now)!
        )
        let incidentalEgg = (0..<2).map { offset in
            SolidFoodEventItem(
                eventID: UUID(),
                profileID: profile.id,
                foodID: "egg",
                foodNameSnapshot: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue],
                confirmedAllergenPortionIDs: [],
                createdAt: now.addingTimeInterval(Double(offset) * 86_400)
            )
        }

        let eggSuggestion = try XCTUnwrap(SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: incidentalEgg,
            allergenProgress: [],
            plans: [],
            startingAt: now,
            count: 100
        ).first { $0.allergenID == SolidsAllergen.egg.rawValue })

        XCTAssertEqual(eggSuggestion.allergenIntroductionStep, 1)
        XCTAssertNotNil(eggSuggestion.allergenServingGuidance)
    }

    @MainActor
    func testGuidedSuggestionsUseObservedSkillsAndSubstituteForBlockedAllergens() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -12, to: now)!
        )
        let basic = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            startingAt: now,
            count: 1
        )
        let skilled = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: [],
            plans: [],
            completedSkillIDs: [SolidsFeedingSkill.usesPincerGrasp.rawValue],
            startingAt: now,
            count: 1
        )
        XCTAssertNotEqual(basic.first?.preparationNotes, skilled.first?.preparationNotes)

        let blocked = SolidsAllergen.allCases.map {
            SolidAllergenProgress(
                profileID: profile.id,
                allergenID: $0.rawValue,
                status: .avoidPendingAdvice
            )
        }
        let substitutes = SolidsTrackingService.guidedSuggestions(
            for: profile,
            progress: [],
            eventItems: [],
            allergenProgress: blocked,
            plans: [],
            startingAt: now,
            count: 100
        )
        XCTAssertEqual(substitutes.filter { $0.kind != .familiarRepeat }.count, 100)
        XCTAssertTrue(substitutes.flatMap(\.foods).allSatisfy { $0.allergenIDs.isEmpty })
    }

    @MainActor
    func testAllergenStatusNotesAndAutomaticProgressRemainIndependent() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        SolidsTrackingService.updateAllergenStatus(
            .tolerated,
            allergenID: SolidsAllergen.egg.rawValue,
            profileID: profileID,
            notes: "Manual state",
            context: context
        )
        SolidsTrackingService.updateAllergenNotes(
            allergenID: SolidsAllergen.egg.rawValue,
            profileID: profileID,
            notes: "Updated note only",
            context: context
        )
        SolidsTrackingService.reconcileAllergenProgress(profileID: profileID, context: context)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<SolidAllergenProgress>()).first)
        XCTAssertEqual(record.status, .tolerated)
        XCTAssertEqual(record.statusOverride, .tolerated)
        XCTAssertEqual(record.notes, "Updated note only")

        SolidsTrackingService.clearAllergenStatusOverride(
            allergenID: SolidsAllergen.egg.rawValue,
            profileID: profileID,
            context: context
        )
        XCTAssertEqual(record.status, .notStarted)
        XCTAssertNil(record.statusOverride)
    }

    @MainActor
    func testAllergenPlannerBuildsOnlyMissingIntroductionStepsAndPresetsConfirmation() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -9, to: now)!
        )
        let progress = SolidAllergenProgress(
            profileID: profile.id,
            allergenID: SolidsAllergen.egg.rawValue,
            status: .introducing,
            introductionStep: 1
        )
        context.insert(profile)
        context.insert(progress)

        let created = SolidsTrackingService.buildAllergenPlan(
            for: .egg,
            profile: profile,
            progress: progress,
            allProgress: [progress],
            existingPlans: [],
            context: context,
            now: now
        )
        XCTAssertEqual(created.compactMap(\.allergenIntroductionStep), [2, 3])
        XCTAssertTrue(created.allSatisfy { $0.allergenID == SolidsAllergen.egg.rawValue })
        XCTAssertTrue(created.allSatisfy { !$0.isGuided })
        XCTAssertTrue(created.allSatisfy { $0.allergenServingGuidance?.isEmpty == false })
        let preset = SolidsTrackingService.preset(for: created[0])
        XCTAssertEqual(
            preset.confirmedAllergenPortionIDs,
            [SolidsAllergen.egg.rawValue]
        )
        let eggID = try XCTUnwrap(created[0].foodIDs.first)
        XCTAssertTrue(preset.allergenIDsByFoodID[eggID]?.contains(SolidsAllergen.egg.rawValue) == true)
        XCTAssertTrue(SolidsTrackingService.buildAllergenPlan(
            for: .egg,
            profile: profile,
            progress: progress,
            allProgress: [progress],
            existingPlans: created,
            context: context,
            now: now
        ).isEmpty)
    }

    @MainActor
    func testCustomPlannedFoodsRespectLinkedInventoryAndCreateCanonicalShoppingLinks() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let household = Household(name: "Home")
        let list = ShoppingList(householdID: household.id, name: "Test Market")
        let location = InventoryLocation(
            householdID: household.id,
            name: "Pantry",
            locationType: .pantry
        )
        let customID = "custom-family-patty"
        let canonical = FoodItem(
            householdID: household.id,
            canonicalName: "Family patty",
            foodReferenceID: customID
        )
        let inventory = InventoryItem(
            householdID: household.id,
            foodItemID: canonical.id,
            name: "Family patty",
            quantity: 2,
            locationID: location.id
        )
        context.insert(household)
        context.insert(list)
        context.insert(location)
        context.insert(canonical)
        context.insert(inventory)

        XCTAssertEqual(SolidsTrackingService.addPlannedFoodsToShoppingList(
            foodIDs: [customID],
            foodNames: ["Family patty"],
            list: list,
            existingItems: [],
            inventoryItems: [inventory],
            foodItems: [canonical],
            skipAvailableInventory: true,
            context: context
        ), 0)
        XCTAssertEqual(SolidsTrackingService.addPlannedFoodsToShoppingList(
            foodIDs: ["custom-oat-bite"],
            foodNames: ["Oat bite"],
            list: list,
            existingItems: [],
            inventoryItems: [inventory],
            foodItems: [canonical],
            skipAvailableInventory: true,
            context: context
        ), 1)
        let shoppingItem = try XCTUnwrap(context.fetch(FetchDescriptor<ShoppingListItem>()).first)
        let linkedFood = try XCTUnwrap(context.fetch(FetchDescriptor<FoodItem>()).first {
            $0.id == shoppingItem.foodItemID
        })
        XCTAssertEqual(linkedFood.foodReferenceID, "custom-oat-bite")

        let profileID = UUID()
        SolidsTrackingService.setStatus(
            .wantToTry,
            foodID: customID,
            foodName: "Family patty",
            profileID: profileID,
            progress: [],
            context: context
        )
        SolidsTrackingService.toggleFavorite(
            foodID: customID,
            foodName: "Family patty",
            profileID: profileID,
            progress: [],
            context: context
        )
        let customProgress = try XCTUnwrap(context.fetch(FetchDescriptor<SolidFoodProgress>()).first {
            $0.profileID == profileID && $0.foodID == customID
        })
        XCTAssertEqual(customProgress.status, .wantToTry)
        XCTAssertTrue(customProgress.isFavorite)
    }

    @MainActor
    func testCustomFoodPresetCarriesAllergensIntoARecordedMeal() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let customID = "custom-test-spread"
        let event = CareEvent(profileID: profileID, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Test spread"
        context.insert(event)

        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: SolidFeedEditorPreset(
                foodIDs: [customID],
                foodNames: ["Test spread"],
                allergenIDsByFoodID: [customID: [SolidsAllergen.sesame.rawValue]],
                confirmedAllergenPortionIDs: [SolidsAllergen.sesame.rawValue]
            ),
            eventItems: [],
            progress: [],
            plans: [],
            profileStates: [],
            context: context
        )

        let item = try XCTUnwrap(context.fetch(FetchDescriptor<SolidFoodEventItem>()).first)
        XCTAssertEqual(item.foodID, customID)
        XCTAssertEqual(item.allergenIDs, [SolidsAllergen.sesame.rawValue])
        XCTAssertEqual(item.confirmedAllergenPortionIDs, [SolidsAllergen.sesame.rawValue])
    }

    func testWidgetSolidsEligibilityChangesAtSixMonthsWithoutRefreshingSnapshot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let birthday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let birthDate = calendar.date(byAdding: .month, value: -6, to: birthday)!
        let summary = TodaySummarySnapshot(
            profileID: UUID(),
            profileName: "Test Child",
            profileTypeRawValue: CareProfileType.child.rawValue,
            totalSleepSeconds: 0,
            napCount: 0,
            careSessionCount: 0,
            diaperCount: 0,
            profileBirthDate: birthDate,
            solidsWorkspaceActivated: false,
            hasSolidHistory: false
        )
        XCTAssertFalse(summary.allowsSolids(at: birthday.addingTimeInterval(-1), calendar: calendar))
        XCTAssertTrue(summary.allowsSolids(at: birthday, calendar: calendar))
    }

    @MainActor
    func testWidgetSolidsActionRequiresAgeActivationOrHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profileID = UUID()
        let oneMonthBirthDate = calendar.date(byAdding: .month, value: -1, to: now)!
        let sixMonthBirthDate = calendar.date(byAdding: .month, value: -6, to: now)!

        let hidden = WidgetSnapshotService.makeSnapshot(
            profileID: profileID,
            profileType: .child,
            profileBirthDate: oneMonthBirthDate,
            babyName: "Test Child",
            events: [],
            prediction: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(hidden.todaySummary.resolvedAllowsSolids)

        let activated = WidgetSnapshotService.makeSnapshot(
            profileID: profileID,
            profileType: .child,
            profileBirthDate: oneMonthBirthDate,
            solidsWorkspaceActivated: true,
            babyName: "Test Child",
            events: [],
            prediction: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(activated.todaySummary.resolvedAllowsSolids)

        let ageEligible = WidgetSnapshotService.makeSnapshot(
            profileID: profileID,
            profileType: .child,
            profileBirthDate: sixMonthBirthDate,
            babyName: "Test Child",
            events: [],
            prediction: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(ageEligible.todaySummary.resolvedAllowsSolids)

        let dog = WidgetSnapshotService.makeSnapshot(
            profileID: profileID,
            profileType: .dog,
            profileBirthDate: sixMonthBirthDate,
            solidsWorkspaceActivated: true,
            babyName: "Test Dog",
            events: [],
            prediction: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(dog.todaySummary.resolvedAllowsSolids)
    }

    @MainActor
    func testEditingLoggedMealKeepsItsPlanCompleted() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let event = CareEvent(profileID: profileID, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Avocado"
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "avocado",
                foodName: "Avocado",
                confirmedAllergenPortionIDs: [],
                preference: .liked,
                servingAmount: "3 tbsp",
                notes: "Soft spears"
            )
        ]
        let plan = PlannedSolidMeal(
            profileID: profileID,
            scheduledAt: Date(),
            foodIDs: ["avocado"],
            foodNames: ["Avocado"]
        )
        context.insert(event)
        context.insert(plan)

        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: SolidFeedEditorPreset(
                foodIDs: ["avocado"],
                foodNames: ["Avocado"],
                plannedMealID: plan.id
            ),
            eventItems: [],
            progress: [],
            plans: [plan],
            profileStates: [],
            context: context
        )
        XCTAssertEqual(plan.completedEventID, event.id)

        event.foodDescription = "Avocado, Banana"
        event.solidFoodDetails = [
            SolidFoodLogDetail(foodID: "avocado", foodName: "Avocado"),
            SolidFoodLogDetail(foodID: "banana", foodName: "Banana")
        ]
        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: nil,
            eventItems: [],
            progress: [],
            plans: [plan],
            profileStates: [],
            context: context
        )

        XCTAssertEqual(plan.completedEventID, event.id)
    }

    @MainActor
    func testNewSolidsDeepLinksResolveToSpecificDestinations() {
        let router = DeepLinkRouter.shared
        let customFoodID = UUID()
        let eventID = UUID()

        router.route(URL(string: "littlewindows://food/solids/custom/\(customFoodID.uuidString)")!)
        XCTAssertEqual(router.selectedTab, .milestones)
        XCTAssertEqual(router.pendingSolidsCommand, .customSolidFood(customFoodID))

        router.route(URL(string: "littlewindows://care/solids/tracker/\(eventID.uuidString)")!)
        XCTAssertEqual(router.pendingSolidsCommand, .solidMeal(eventID))

        router.route(URL(string: "littlewindows://food/solids/allergens/egg")!)
        XCTAssertEqual(router.pendingSolidsCommand, .solidAllergen("egg"))

        router.route(URL(string: "littlewindows://quick-log/solids")!)
        XCTAssertEqual(router.consumeAction(), .logSolidFeed(.empty))

        router.route(URL(string: "littlewindows://reports/feeding")!)
        XCTAssertEqual(router.selectedTab, .reports)
        XCTAssertEqual(router.selectedReportsMode, .summary)
        XCTAssertEqual(router.pendingInsightsSection, .feeding)
        router.pendingInsightsSection = nil
        router.pendingSolidsCommand = nil
    }

    @MainActor
    func testInAppSolidsNavigationCarriesAndConsumesItsOrigin() {
        let router = DeepLinkRouter.shared
        let profileID = UUID()

        for origin in [LittleWindowsTab.today, .food, .reports] {
            router.openSolids(
                .solidsAllergens,
                profileID: profileID,
                returningTo: origin
            )

            XCTAssertEqual(router.selectedTab, .milestones)
            XCTAssertEqual(router.pendingProfileID, profileID)
            XCTAssertEqual(router.pendingSolidsCommand, .solidsAllergens)
            XCTAssertEqual(
                router.consumeSolidsOrigin(),
                SolidsNavigationOrigin(tab: origin, insightsSection: nil)
            )
            XCTAssertNil(router.pendingSolidsOrigin)
        }

        router.openSolids(
            .solidsAllergens,
            profileID: profileID,
            returningTo: .reports,
            insightsSection: .feeding,
            feedingInsightsMode: .solids
        )
        XCTAssertEqual(
            router.consumeSolidsOrigin(),
            SolidsNavigationOrigin(
                tab: .reports,
                insightsSection: .feeding,
                feedingInsightsMode: .solids
            )
        )

        router.pendingFeedingInsightsMode = .solids
        router.route(URL(string: "littlewindows://food/solids/allergens")!)
        XCTAssertNil(router.pendingSolidsOrigin, "External routes should fall back to the Care root.")
        XCTAssertNil(router.pendingFeedingInsightsMode)
        router.pendingProfileID = nil
        router.pendingSolidsCommand = nil
    }

    @MainActor
    func testSolidsRecordsRoundTripThroughBackup() throws {
        let source = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let sourceContext = source.mainContext
        let profile = CareProfile(
            name: "Test Child",
            birthDate: Calendar.current.date(byAdding: .month, value: -9, to: Date())!
        )
        let event = CareEvent(profileID: profile.id, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Avocado"
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "avocado",
                foodName: "Avocado",
                confirmedAllergenPortionIDs: [],
                preference: .liked,
                servingAmount: "3 tbsp",
                notes: "Soft spears"
            )
        ]
        let plan = PlannedSolidMeal(
            profileID: profile.id,
            scheduledAt: Date(),
            foodIDs: ["avocado"],
            foodNames: ["Avocado"],
            recipeID: "avocado-oat-mash",
            isGuided: true,
            guidedPosition: 8,
            allergenID: SolidsAllergen.egg.rawValue,
            allergenIntroductionStep: 2,
            allergenServingGuidance: "Example serving guidance",
            allergenObservationMinutes: 10,
            reminderEnabled: true,
            reminderOffsetMinutes: 20
        )
        sourceContext.insert(profile)
        sourceContext.insert(event)
        sourceContext.insert(plan)
        sourceContext.insert(SolidAllergenProgress(
            profileID: profile.id,
            allergenID: SolidsAllergen.egg.rawValue,
            status: .avoidPendingAdvice,
            statusOverride: .avoidPendingAdvice,
            notes: "Caregiver choice"
        ))
        SolidsTrackingService.recordSolidFeed(
            event: event,
            preset: SolidFeedEditorPreset(
                foodIDs: ["avocado"],
                foodNames: ["Avocado"],
                plannedMealID: plan.id
            ),
            eventItems: [],
            progress: [],
            plans: [plan],
            profileStates: [],
            context: sourceContext
        )
        let sourceState = try XCTUnwrap(
            sourceContext.fetch(FetchDescriptor<SolidsProfileState>()).first
        )
        sourceState.recipeCollections = [
            SolidRecipeCollection(name: "Breakfasts", recipeIDs: ["apple-oatmeal"])
        ]
        sourceState.completedFeedingSkillIDs = [SolidsFeedingSkill.usesPreloadedSpoon.rawValue]

        let data = try DataExportImportService.exportData(context: sourceContext)
        let destination = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        try DataExportImportService.importData(
            data,
            context: destination.mainContext,
            createRecoveryBackup: false
        )

        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<SolidsProfileState>()), 1)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<SolidFoodProgress>()), 1)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<SolidFoodEventItem>()), 1)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<PlannedSolidMeal>()), 1)
        let importedPlan = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<PlannedSolidMeal>()).first
        )
        XCTAssertNotNil(importedPlan.completedEventID)
        XCTAssertEqual(importedPlan.recipeID, "avocado-oat-mash")
        XCTAssertTrue(importedPlan.isGuided)
        XCTAssertEqual(importedPlan.guidedPosition, 8)
        XCTAssertEqual(importedPlan.allergenID, SolidsAllergen.egg.rawValue)
        XCTAssertEqual(importedPlan.allergenIntroductionStep, 2)
        XCTAssertEqual(importedPlan.allergenServingGuidance, "Example serving guidance")
        XCTAssertEqual(importedPlan.allergenObservationMinutes, 10)
        XCTAssertTrue(importedPlan.reminderEnabled)
        XCTAssertEqual(importedPlan.reminderOffsetMinutes, 20)
        let importedItem = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SolidFoodEventItem>()).first
        )
        XCTAssertEqual(importedItem.servingAmount, "3 tbsp")
        XCTAssertEqual(importedItem.confirmedAllergenPortionIDs, [])
        XCTAssertEqual(importedItem.notes, "Soft spears")
        let importedState = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SolidsProfileState>()).first
        )
        XCTAssertEqual(importedState.recipeCollections.first?.name, "Breakfasts")
        XCTAssertEqual(importedState.recipeCollections.first?.recipeIDs, ["apple-oatmeal"])
        XCTAssertEqual(importedState.completedFeedingSkillIDs, [SolidsFeedingSkill.usesPreloadedSpoon.rawValue])
        let importedAllergen = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SolidAllergenProgress>()).first
        )
        XCTAssertEqual(importedAllergen.status, .avoidPendingAdvice)
        XCTAssertEqual(importedAllergen.statusOverride, .avoidPendingAdvice)
        XCTAssertEqual(importedAllergen.notes, "Caregiver choice")
    }

    @MainActor
    func testBackgroundCustomFoodWriterCreatesUpdatesAndDeletes() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let writer = SolidsCustomFoodWriter(modelContainer: container)
        let created = await writer.save(SolidsCustomFoodWrite(
            itemID: nil,
            name: "Family lentil patty",
            photoDraft: nil,
            removeExistingPhoto: false,
            allergenIDs: [],
            minimumAgeMonths: 9,
            preparationNotes: "Serve soft",
            safetyNotes: "Check the center"
        ))
        XCTAssertNil(created.error)
        let itemID = try XCTUnwrap(created.itemID)

        let updated = await writer.save(SolidsCustomFoodWrite(
            itemID: itemID,
            name: "Soft lentil patty",
            photoDraft: nil,
            removeExistingPhoto: false,
            allergenIDs: [SolidsAllergen.sesame.rawValue],
            minimumAgeMonths: 9,
            preparationNotes: "Serve in strips",
            safetyNotes: "Keep moist"
        ))
        XCTAssertNil(updated.error)

        var verificationContext = ModelContext(container)
        let item = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<SolidFoodCatalogItem>()).first)
        XCTAssertEqual(item.name, "Soft lentil patty")
        XCTAssertEqual(item.allergenIDs, [SolidsAllergen.sesame.rawValue])
        XCTAssertEqual(item.preparationNotes, "Serve in strips")

        let deleteError = await writer.delete(itemID: itemID)
        XCTAssertNil(deleteError)
        verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<SolidFoodCatalogItem>()), 0)
    }

    @MainActor
    func testBackgroundMealPrepWriterCreatesItem() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let writer = SolidsMealPrepWriter(modelContainer: container)
        let error = await writer.create(SolidsMealPrepWrite(
            name: "Vegetable rice bowl",
            servings: 3,
            locationID: UUID(),
            householdID: UUID(),
            preparedDate: Date(),
            notes: "Carrot, rice",
            tags: "solids,lunch"
        ))
        XCTAssertNil(error)

        let verificationContext = ModelContext(container)
        let item = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<MealPrepItem>()).first)
        XCTAssertEqual(item.name, "Vegetable rice bowl")
        XCTAssertEqual(item.servingsRemaining, 3)
        XCTAssertEqual(item.notes, "Carrot, rice")
    }

    @MainActor
    func testBackgroundBackfillWriterIsCompleteAndIdempotent() async throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let profileID = UUID()
        let event = CareEvent(profileID: profileID, type: .feed)
        event.feedKind = .solid
        event.foodDescription = "Egg"
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "egg",
                foodName: "Egg",
                allergenIDs: [SolidsAllergen.egg.rawValue],
                confirmedAllergenPortionIDs: [SolidsAllergen.egg.rawValue],
                preference: .liked
            )
        ]
        container.mainContext.insert(event)
        try container.mainContext.save()

        let writer = SolidsBackfillWriter(modelContainer: container)
        let first = await writer.backfill(profileID: profileID)
        XCTAssertEqual(first.count, 1)
        XCTAssertNil(first.error)
        let second = await writer.backfill(profileID: profileID)
        XCTAssertEqual(second.count, 0)
        XCTAssertNil(second.error)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<SolidFoodEventItem>()), 1)
        let progress = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<SolidFoodProgress>()).first)
        XCTAssertEqual(progress.foodID, "egg")
        XCTAssertEqual(progress.exposureCount, 1)
        let state = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<SolidsProfileState>()).first)
        XCTAssertTrue(state.isActivated)
        let allergen = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<SolidAllergenProgress>()).first)
        XCTAssertEqual(allergen.status, .introducing)
        XCTAssertEqual(allergen.introductionStep, 1)
    }
}
