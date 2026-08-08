import Foundation

enum SolidsFoodCategory: String, CaseIterable, Codable, Identifiable {
    case fruit
    case vegetable
    case grain
    case beanAndPlantProtein
    case meat
    case seafood
    case dairy
    case egg
    case nutAndSeed
    case herbAndFlavor
    case preparedFood

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fruit: "Fruit"
        case .vegetable: "Vegetables"
        case .grain: "Grains & starches"
        case .beanAndPlantProtein: "Beans & plant proteins"
        case .meat: "Meat & poultry"
        case .seafood: "Fish & shellfish"
        case .dairy: "Dairy"
        case .egg: "Egg"
        case .nutAndSeed: "Nuts & seeds"
        case .herbAndFlavor: "Herbs & flavors"
        case .preparedFood: "Prepared foods"
        }
    }

    var systemImage: String {
        switch self {
        case .fruit: "leaf.fill"
        case .vegetable: "carrot.fill"
        case .grain: "takeoutbag.and.cup.and.straw.fill"
        case .beanAndPlantProtein: "leaf.fill"
        case .meat: "fork.knife"
        case .seafood: "fish.fill"
        case .dairy: "mug.fill"
        case .egg: "oval.fill"
        case .nutAndSeed: "circle.hexagongrid.fill"
        case .herbAndFlavor: "camera.macro"
        case .preparedFood: "frying.pan.fill"
        }
    }

    var fallbackEmoji: String {
        switch self {
        case .fruit: "🍎"
        case .vegetable: "🥕"
        case .grain: "🌾"
        case .beanAndPlantProtein: "🫘"
        case .meat: "🍖"
        case .seafood: "🐟"
        case .dairy: "🥛"
        case .egg: "🥚"
        case .nutAndSeed: "🥜"
        case .herbAndFlavor: "🌿"
        case .preparedFood: "🍲"
        }
    }

}

enum SolidsAllergen: String, CaseIterable, Codable, Identifiable {
    case milk
    case egg
    case fish
    case crustaceanShellfish
    case treeNuts
    case peanuts
    case wheat
    case soy
    case sesame

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .milk: "Milk"
        case .egg: "Egg"
        case .fish: "Fish"
        case .crustaceanShellfish: "Crustacean shellfish"
        case .treeNuts: "Tree nuts"
        case .peanuts: "Peanuts"
        case .wheat: "Wheat"
        case .soy: "Soy"
        case .sesame: "Sesame"
        }
    }
}

struct SolidsAllergenIntroductionStep: Identifiable, Hashable {
    var number: Int
    var title: String
    var detail: String
    var id: Int { number }
}

struct SolidsAllergenGuidance: Hashable {
    var allergen: SolidsAllergen
    var safeForm: String
    var exampleServing: String
    var steps: [SolidsAllergenIntroductionStep]
    var sourceURLs: [URL]
}

struct SolidsServingAmountGuidance: Hashable {
    var firstServing: String
    var routineServing: String
}

struct SolidsPreparationStage: Identifiable, Hashable {
    var minimumAgeMonths: Int
    var title: String
    var instructions: String
    var servingAmount = SolidsServingAmountGuidance(firstServing: "", routineServing: "")
    var id: Int { minimumAgeMonths }
}

enum SolidsPreparationActionKind: String, CaseIterable, Hashable {
    case choose
    case clean
    case prepare
    case shape
    case verify
    case serve

    var systemImage: String {
        switch self {
        case .choose: "checkmark.seal.fill"
        case .clean: "drop.fill"
        case .prepare: "frying.pan.fill"
        case .shape: "scissors"
        case .verify: "hand.tap.fill"
        case .serve: "fork.knife"
        }
    }
}

struct SolidsPreparationAction: Identifiable, Hashable {
    var kind: SolidsPreparationActionKind
    var title: String
    var detail: String
    var completionLabel: String
    var id: String { kind.rawValue }
}

struct SolidsPreparationWalkthrough: Hashable {
    var stage: SolidsPreparationStage
    var visual: SolidsServingVisual
    var actions: [SolidsPreparationAction]
}

struct SolidsFoodQuestion: Identifiable, Hashable {
    var question: String
    var answer: String
    var id: String { question }
}

struct SolidsFoodDetails: Hashable {
    var introductionSummary: String
    var backgroundSummary: String?
    var nutritionSummary: String
    var allergenSummary: String
    var choosingGuidance: String
    var storageGuidance: String
    var questions: [SolidsFoodQuestion]
}

enum SolidsServingVisual: String, Hashable {
    case mashed
    case spear
    case flattened
    case shredded
    case thinSpread
    case softPieces
    case flakes
    case spoon

    var systemImage: String {
        switch self {
        case .mashed: "takeoutbag.and.cup.and.straw.fill"
        case .spear: "rectangle.portrait.fill"
        case .flattened: "oval.fill"
        case .shredded: "line.3.horizontal"
        case .thinSpread: "square.fill"
        case .softPieces: "square.grid.3x3.fill"
        case .flakes: "fish.fill"
        case .spoon: "fork.knife"
        }
    }

    var displayName: String {
        switch self {
        case .mashed: "Mashed or blended"
        case .spear: "Soft, graspable spear"
        case .flattened: "Flattened"
        case .shredded: "Finely shredded"
        case .thinSpread: "Thinly spread"
        case .softPieces: "Soft pieces"
        case .flakes: "Soft flakes"
        case .spoon: "Preloaded spoon"
        }
    }

    var assetName: String {
        "solids-serving-\(rawValue)"
    }
}

struct SolidsReferenceFood: Identifiable, Hashable {
    var id: String
    var name: String
    var category: SolidsFoodCategory
    var aliases: [String]
    var minimumAgeMonths: Int
    var isIronRich: Bool
    var allergenIDs: [String]
    var possibleAllergenIDs: [String]
    var details: SolidsFoodDetails
    var safetyNote: String
    var chokingGuidance: String
    var nutritionHighlights: [String]
    var preparations: [SolidsPreparationStage]
    var servingVisuals: [SolidsServingVisual]
    var sourceURLs: [URL]

    var isEligibleForGuidedPath: Bool {
        // Keep foods with useful educational pages but an explicit young-child
        // avoidance recommendation out of generated meal suggestions.
        !["mackerel", "swordfish", "tuna"].contains(id)
    }

    var visualEmoji: String {
        SolidsFoodVisual.emoji(for: name, category: category)
    }

    func preparation(forAgeMonths months: Int) -> SolidsPreparationStage {
        preparations.last(where: { $0.minimumAgeMonths <= months }) ?? preparations[0]
    }

    func preparationWalkthrough(stageIndex: Int) -> SolidsPreparationWalkthrough {
        let safeIndex = min(max(stageIndex, 0), preparations.count - 1)
        let stage = preparations[safeIndex]
        let visual = servingVisuals[min(safeIndex, servingVisuals.count - 1)]
        let cleanAction = preparationCleaningAction

        return SolidsPreparationWalkthrough(
            stage: stage,
            visual: visual,
            actions: [
                SolidsPreparationAction(
                    kind: .choose,
                    title: "Check the ingredient",
                    detail: details.choosingGuidance,
                    completionLabel: "Ingredient and label checked"
                ),
                SolidsPreparationAction(
                    kind: .clean,
                    title: cleanAction.title,
                    detail: cleanAction.detail,
                    completionLabel: cleanAction.completionLabel
                ),
                SolidsPreparationAction(
                    kind: .prepare,
                    title: preparationActionTitle,
                    detail: preparationActionDetail,
                    completionLabel: "Base preparation complete"
                ),
                SolidsPreparationAction(
                    kind: .shape,
                    title: "Make the \(visual.displayName.lowercased()) form",
                    detail: shapeActionDetail(visual: visual, stage: stage),
                    completionLabel: "Shape and size checked"
                ),
                SolidsPreparationAction(
                    kind: .verify,
                    title: "Run the final texture check",
                    detail: textureCheckDetail(visual: visual),
                    completionLabel: "Texture and hazards checked"
                ),
                SolidsPreparationAction(
                    kind: .serve,
                    title: "Plate and serve",
                    detail: servingActionDetail,
                    completionLabel: "Ready to serve"
                )
            ]
        )
    }

    private var normalizedName: String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var preparationCleaningAction: (title: String, detail: String, completionLabel: String) {
        if normalizedName == "acai" {
            return (
                "Confirm the prepared form",
                "Use commercially prepared seedless pulp, purée, or plain powder. Check that a frozen packet is intact and that a bowl or blend contains no honey for a child under 12 months, stimulant ingredients, whole nuts, granola, or other hard toppings.",
                "Prepared form and ingredients checked"
            )
        }
        if ["cactus pear", "prickly pear"].contains(normalizedName) {
            return (
                "Choose a fully de-spined fruit",
                "Use commercially de-spined \(name.lowercased()) or wear protective gloves while removing every spine and hair-like glochid. Wash the fruit, cut off the ends, peel away the entire outer skin, and keep the discarded peel away from the serving area.",
                "Spines and peel completely removed"
            )
        }
        switch category {
        case .fruit:
            let form = SolidsReferenceCatalog.fruitPreparationForm(name: name)
            if form == .sauce {
                return (
                    "Check the package and portion",
                    "Confirm that \(name.lowercased()) is unsweetened, contains no honey for a child under 12 months, and has an intact container. Spoon a small amount into a clean bowl rather than feeding from and saving the same container.",
                    "Package and serving portion checked"
                )
            }
            let inspection: String
            switch form {
            case .sauce:
                inspection = ""
            case .smallRoundBerry:
                inspection = "Remove any stem or firm dried flower end and discard damaged berries."
            case .aggregateBerry:
                inspection = "Remove the stem and discard any firm core or damaged section."
            case .roundOrSlipperyFruit:
                inspection = "Open or cut it, then remove its pit, large seed, husk, or inedible peel as applicable."
            case .citrus:
                inspection = "Remove peel, seeds, tough membrane, and excess pith."
            case .firmFruit:
                inspection = "Remove the core and seeds; peel only when the skin is tough or damaged."
            case .stoneFruit:
                inspection = "Remove the entire pit and peel only if the skin is tough or damaged."
            case .melon:
                inspection = "Wash the rind before cutting, then remove all rind and hard seeds from the edible flesh."
            case .softFruit:
                inspection = "Remove the specific stem, hard seed, core, or inedible peel this fruit contains, following its food-specific safety note."
            case .seededPulp:
                inspection = "Wash the outside before opening, keep the rind out of the serving, and remove any large or unexpectedly hard seed."
            case .arils:
                inspection = "Open the fruit and separate the arils completely from the rind and membrane."
            case .driedStickyFruit:
                inspection = "Confirm the package is intact and the pit has been removed; inspect the fruit again before softening it."
            case .gratedFlesh:
                inspection = "Choose packaged finely grated or ground flesh without hard shell fragments, or safely open fresh coconut and keep every shell piece out of the edible portion."
            case .cookBeforeServing:
                inspection = "Wash before cutting, then peel, core, seed, or otherwise trim only as this food's specific guidance requires before thorough cooking."
            }
            let washing = form == .driedStickyFruit || form == .gratedFlesh
                ? ""
                : "Wash \(name.lowercased()) under running water before cutting. "
            return (
                form == .driedStickyFruit || form == .gratedFlesh ? "Inspect the prepared fruit" : "Wash and inspect the fruit",
                "\(washing)\(inspection) \(safetyNote)",
                "Fruit-specific inspection complete"
            )
        case .vegetable:
            let form = SolidsReferenceCatalog.vegetablePreparationForm(name: name)
            let trimming: String
            switch form {
            case .leafy:
                trimming = "Separate and rinse the leaves well and remove thick, damaged, or woody stems."
            case .flower:
                trimming = "Rinse between florets and trim woody leaves or the dry end of the stem."
            case .compactBud:
                trimming = "Remove damaged outer leaves, trim the dry stem end, and rinse the compact bud."
            case .squash:
                trimming = "Wash the outside before cutting, then remove hard rind and seeds when this variety requires it."
            case .roundKernel:
                trimming = "Rinse loose kernels or peas, or wash the pod or cob before removing the edible pieces."
            case .pod:
                trimming = "Rinse the pods and remove the stem, strings, and tough seams."
            case .stalk:
                trimming = "Rinse well and trim the dry end plus any woody or stringy section."
            case .bulb:
                trimming = "Remove papery outer material or the root end as applicable, then rinse the edible layers."
            case .softFlesh:
                trimming = "Wash before cutting and remove the stem plus any tough peel or hard seed identified in the food-specific guidance."
            case .root, .tuber:
                trimming = "Scrub under running water, trim damaged sections, and peel when the skin is tough, damaged, or specifically excluded by the guidance."
            case .fibrousSpecialty:
                trimming = "Follow the food-specific trimming instructions and keep only the identified edible portion; discard tough, spiny, irritating, or fibrous material."
            }
            return (
                "Wash and trim",
                "\(trimming) For packaged frozen or canned \(name.lowercased()), check sodium and prepare according to the label. \(safetyNote)",
                "Vegetable washed and trimmed"
            )
        case .grain:
            let form = SolidsReferenceCatalog.grainPreparationForm(name: name)
            let check: String
            switch form {
            case .bread:
                check = "Review the allergen label, sodium, whole nuts or hard seeds, crust firmness, and whether the bread tears easily instead of compressing into a gummy mass."
            case .pasta:
                check = "Review the allergen label and choose a shape that can be cooked very tender, shortened, or otherwise adapted. Measure enough cooking water and sauce to keep it moist."
            case .puffedCereal:
                check = "Check added sugar, sodium, allergens, and hard clusters, then test that the exact puff dissolves readily before it is used as a finger food."
            case .softGrain:
                check = "Sort whole dry grains for debris when applicable, review packaged cereal for allergens and added sugar, and measure enough liquid for a moist finished texture."
            }
            return (
                "Measure and inspect",
                "Check \(name.lowercased()) before preparation. \(check)",
                "Grain and liquid checked"
            )
        case .beanAndPlantProtein:
            let form = SolidsReferenceCatalog.plantProteinPreparationForm(name: name)
            if form == .wholePulse {
                return (
                    "Inspect, rinse, and sort",
                    "Remove debris from dried \(name.lowercased()). Drain and rinse canned versions when appropriate, choose no-salt-added or lower-sodium products when practical, and plan to cook until the center mashes easily.",
                    "Pulse sorted and rinsed"
                )
            }
            if form == .sprout {
                return (
                    "Rinse and set up for thorough cooking",
                    "Rinse \(name.lowercased()) and keep it separate from ready-to-eat food. Rinsing alone does not remove the sprout food-safety risk, so plan to cook it thoroughly until steaming hot.",
                    "Sprouts rinsed and cooking setup ready"
                )
            }
            return (
                "Check the product and label",
                "Inspect \(name.lowercased()) for damaged packaging, follow its refrigeration directions, and review sodium plus soy, wheat, sesame, or other allergens. Assess the actual firmness or thickness before preparing it.",
                "Package, label, and texture checked"
            )
        case .meat:
            let form = SolidsReferenceCatalog.meatPreparationForm(name: name)
            let trimGuidance: String
            switch form {
            case .organ:
                trimGuidance = "After cooking, remove membrane, tough ducts, or connective tissue."
            case .ground:
                trimGuidance = "Inspect the ingredient list for sodium and allergens and plan to keep any crumbles, patty, or meatball tender and moist."
            case .boneIn:
                trimGuidance = "After cooking, take all meat off the bone and inspect again for loose bone, cartilage, gristle, and tough skin."
            case .tenderCut:
                trimGuidance = "Use a boneless portion for the child's serving. If the cut was cooked on the bone, take the meat off and inspect it again, then remove any gristle or tough connective tissue actually present."
            }
            return (
                "Prevent cross-contamination",
                "Keep raw \(name.lowercased()) separate from ready-to-eat food and do not rinse raw meat or poultry, which can spread droplets. Wash hands, board, knife, and surfaces. \(trimGuidance)",
                "Raw-meat setup is separate"
            )
        case .seafood:
            let form = SolidsReferenceCatalog.seafoodPreparationForm(name: name)
            let inspection: String
            switch form {
            case .crustacean:
                inspection = "Remove the entire shell and tail after cooking and check for fragments."
            case .bivalve:
                inspection = "Use only the flesh after cooking and check it carefully for shell fragments."
            case .cephalopod:
                inspection = "Remove any inedible internal material and plan to discard sections that remain rubbery."
            case .smallFish, .fillet:
                inspection = "Plan to inspect the cooked flesh again for bones, which may be easier to find after cooking."
            }
            return (
                "Identify and inspect",
                "Confirm the exact species and current fish advice, keep raw \(name.lowercased()) cold, and prevent cross-contamination. \(inspection)",
                "Species and food-specific hazards checked"
            )
        case .dairy:
            if normalizedName.contains("in food") {
                return (
                    "Check the dairy ingredient",
                    "Confirm that \(name.lowercased()) is pasteurized, review the allergen label, and measure it into a dish rather than planning to offer it as the main milk drink before 12 months.",
                    "Dairy ingredient checked"
                )
            }
            if SolidsReferenceCatalog.scoopablePreparationKind(name: name, category: category) == .smoothDairy {
                return (
                    "Check pasteurization and the label",
                    "Confirm that \(name.lowercased()) is pasteurized, choose an unsweetened product when available, and check the container, use-by date, sodium, and any mix-ins or hard toppings.",
                    "Scoopable dairy checked"
                )
            }
            return (
                "Check pasteurization and cheese texture",
                "Confirm that \(name.lowercased()) is pasteurized, review sodium and ingredients, and assess its actual moisture and firmness before choosing whether to crumble, grate, melt, or slice it thinly.",
                "Pasteurization and cheese texture checked"
            )
        case .egg:
            return (
                "Set up for full cooking",
                "Use a clean, uncracked egg or pasteurized egg product. Keep raw egg and its utensils away from ready-to-eat food, and check any prepared egg dish for milk, wheat, soy, or other added allergens.",
                "Egg and added ingredients checked"
            )
        case .nutAndSeed:
            if normalizedName.contains("butter") || normalizedName == "tahini" {
                return (
                    "Choose a smooth spread",
                    "Confirm the exact allergen on the label and choose smooth \(name.lowercased()) without crunchy pieces. Measure only the amount being thinned or spread for this meal.",
                    "Smooth spread and allergen checked"
                )
            }
            if normalizedName.contains("ground") {
                return (
                    "Inspect the ground product",
                    "Confirm the exact allergen on the label and check \(name.lowercased()) for hard pieces or coarse fragments before mixing it fully into moist food.",
                    "Ground product and allergen checked"
                )
            }
            return (
                "Choose the safe form",
                "Do not plate whole or chopped \(name.lowercased()) for a baby or young toddler. Set up a fine grinder or choose a smooth butter or another food-specific softened form, and confirm the exact allergen on the package.",
                "Whole and hard pieces excluded"
            )
        case .herbAndFlavor:
            let form = SolidsReferenceCatalog.flavorPreparationForm(name: name)
            let preparation: String
            switch form {
            case .bayLeaf:
                preparation = "Use the leaf only for infusion and plan to remove it before plating."
            case .fibrousAromatic:
                preparation = "Trim woody ends or outer layers and prepare to grate, pound, or infuse it finely."
            case .leafyHerb:
                preparation = "Wash fresh leaves and remove firm stems before finely chopping them."
            case .groundSpice:
                preparation = "Measure a small pinch and exclude whole hard spice pieces or loose spoonfuls of powder."
            }
            return (
                "Prepare the flavoring form",
                "Choose culinary \(name.lowercased()) without added salt or stimulant ingredients. \(preparation)",
                "Flavoring form checked"
            )
        case .preparedFood:
            return (
                "Audit the whole recipe",
                "List every component in \(name.lowercased()) and identify allergens, honey, added sugar, sodium, and the actual firmest, roundest, stickiest, or chewiest ingredient. Modify only the hazards present in this recipe, and verify that each component has a safe form.",
                "Every component checked"
            )
        }
    }

    private var preparationActionTitle: String {
        switch category {
        case .fruit:
            return SolidsReferenceCatalog.fruitPreparationForm(name: name) == .sauce
                ? "Set the scoopable texture"
                : "Prepare the edible fruit"
        case .vegetable: return "Cook and adapt the vegetable"
        case .grain: return "Prepare the grain's actual form"
        case .beanAndPlantProtein:
            switch SolidsReferenceCatalog.plantProteinPreparationForm(name: name) {
            case .spread: return "Adjust the spread"
            case .seasoning: return "Measure into the dish"
            case .sprout: return "Cook the sprouts thoroughly"
            default: return "Cook or soften the protein"
            }
        case .meat: return "Cook fully and retain moisture"
        case .seafood: return "Cook fully and inspect again"
        case .dairy:
            if normalizedName.contains("in food") { return "Cook it into the dish" }
            return SolidsReferenceCatalog.scoopablePreparationKind(name: name, category: category) == .smoothDairy
                ? "Keep it scoopable"
                : "Adapt the cheese texture"
        case .egg: return normalizedName == "egg yolk" ? "Cook and moisten the yolk" : "Cook through without drying"
        case .nutAndSeed:
            return normalizedName.contains("butter") || normalizedName == "tahini"
                ? "Thin the smooth spread"
                : "Make a fine, moist form"
        case .herbAndFlavor:
            return SolidsReferenceCatalog.flavorPreparationForm(name: name) == .bayLeaf
                ? "Infuse and remove"
                : "Prepare a small culinary amount"
        case .preparedFood:
            return SolidsReferenceCatalog.preparedFoodPreparationForm(name: name) == .sweetener
                ? "Measure into another food"
                : "Cook every component"
        }
    }

    private var preparationActionDetail: String {
        if normalizedName == "acai" {
            return "Thaw only the pulp needed for the meal, or stir a small amount of plain powder into porridge, yogurt, or another moist food. Mix until the color and texture are even, with no dry powder pockets or frozen center."
        }
        if normalizedName == "honey" {
            return "Use only after the first birthday. Measure a small amount into another food rather than offering honey directly from a spoon or container."
        }
        if ["cactus pear", "prickly pear"].contains(normalizedName) {
            return "After every spine, hair-like glochid, and the outer skin has been removed, use only the soft flesh. Mash it or cut it into a large soft piece, removing any unexpectedly hard seed."
        }
        switch category {
        case .fruit:
            switch SolidsReferenceCatalog.fruitPreparationForm(name: name) {
            case .sauce:
                return "Stir \(name.lowercased()) and spoon a small portion into a clean bowl. It should stay on a tilted spoon but release easily, without a watery layer or dense sticky mound."
            case .smallRoundBerry:
                return "Cook \(name.lowercased()) if firm, then mash or flatten every berry so it no longer holds a small round shape."
            case .aggregateBerry:
                return "Use very ripe \(name.lowercased()), remove its stem, and mash, flatten, or tear it into soft sections. Discard a firm core if present."
            case .roundOrSlipperyFruit:
                return "Remove the fruit-specific pit, large seed, husk, or inedible peel, then mash the ripe flesh or cut it lengthwise so no whole round shape remains."
            case .citrus:
                return "Remove peel, seeds, tough membrane, and excess pith. Offer only the juicy pulp in soft pieces or a manageable membrane-free segment."
            case .firmFruit:
                return "Remove the core and seeds, then cook or finely grate \(name.lowercased()) until it is no longer a hard raw chunk. Cool cooked fruit before shaping."
            case .stoneFruit:
                return "Remove the pit, then use very ripe flesh or cook it until soft. Peel only when the skin is tough or slippery enough to interfere with eating."
            case .melon:
                return "Remove rind and hard seeds, then use soft flesh that crushes easily. Cut a broad slab or soft piece rather than making small slippery melon balls."
            case .softFruit:
                return "Use fully ripe flesh and remove only the stem, core, tough peel, or hard seed that this fruit actually has. Cook it first if the flesh does not squash easily."
            case .seededPulp:
                return "Scoop the soft pulp away from the rind, then remove any large or unexpectedly hard seed. Mash or stir the pulp into a scoopable food."
            case .arils:
                return "Separate the arils from rind and membrane, then crush or flatten every aril rather than leaving firm round pieces intact."
            case .driedStickyFruit:
                return "Remove the pit, soak or simmer until very soft, then mash or mince \(name.lowercased()) into moist food so it cannot form a dense sticky mouthful."
            case .gratedFlesh:
                return "Finely grate or grind the flesh and mix it completely into moist food. Do not leave hard chunks, chewy strips, or dry flakes."
            case .cookBeforeServing:
                return "Trim \(name.lowercased()) as its guidance describes, cook it thoroughly until the center crushes easily, and keep the finished portion moist."
            }
        case .vegetable:
            switch SolidsReferenceCatalog.vegetablePreparationForm(name: name) {
            case .leafy:
                return "Cook the leaves and stems until tender, chop across their fibers, and mix them through moist food so they do not form a leafy wad."
            case .flower:
                return "Cook the thickest stem and florets until both crush easily. Offer a large soft floret or mash it after cooling."
            case .compactBud:
                return "Cook through the dense center, then halve, quarter, mash, or flatten the bud so it is not served whole and round."
            case .squash:
                return "Remove hard rind and seeds, cook the flesh until it crushes easily, and keep it moist rather than cutting firm cubes."
            case .roundKernel:
                return "Cook until soft, then mash or flatten every kernel or pea so it no longer remains a small round piece."
            case .pod:
                return "Trim strings and seams, cook the pod until soft, then split or chop it across the fibers instead of serving a firm intact pod."
            case .stalk:
                return "Trim woody or stringy sections, cook until tender, and cut across the fibers into a form that bends or crushes easily."
            case .bulb:
                return "Cook \(name.lowercased()) until soft and mix it into moist food rather than leaving firm chunks or large slippery layers."
            case .softFlesh:
                return "Remove the stem and any tough peel or hard seed, then use ripe or cooked flesh that squashes easily and is not cut into small slippery cubes."
            case .root:
                return "Cook until the center crushes easily, or use the food-specific finely grated form where the guidance permits it. Do not serve hard raw chunks."
            case .tuber:
                return "Cook \(name.lowercased()) fully until the center mashes easily, then add moisture if the starchy flesh is dry or dense."
            case .fibrousSpecialty:
                return "Use only the properly trimmed edible portion, follow its food-specific full-cooking requirement, and remove any section that remains tough or fibrous."
            }
        case .grain:
            switch SolidsReferenceCatalog.grainPreparationForm(name: name) {
            case .bread:
                return "Use soft or lightly toasted \(name.lowercased()) that tears easily. Moisten it when needed and do not compress it into a dense gummy ball."
            case .pasta:
                return "Cook past firm until tender, shorten long strands or modify large shapes, and add enough sauce or liquid to keep the pasta moist."
            case .puffedCereal:
                return "For a new eater, crush and moisten the cereal. For finger-food practice, use only a piece that dissolves readily when tested and offer one at a time."
            case .softGrain:
                return "Cook with enough liquid for every grain to become soft, then serve as a moist mash or scoopable clump without hard kernels or a dense sticky mass."
            }
        case .beanAndPlantProtein:
            switch SolidsReferenceCatalog.plantProteinPreparationForm(name: name) {
            case .wholePulse:
                return "Cook until the center mashes easily, then mash or flatten each whole bean or pea and add moisture if the result is dry."
            case .softTofu:
                return "Keep \(name.lowercased()) scoopable or cut it into soft pieces, checking that there are no firm add-ins or rubbery surfaces."
            case .firmTofu:
                return "Cook as needed and use moist strips, crumbles, or soft pieces that compress and break apart easily rather than forming rubbery cubes."
            case .fermentedCake:
                return "Cook as directed and keep \(name.lowercased()) moist. Crumble, slice thinly, or form a tender patty rather than serving a tough or elastic chunk."
            case .spread:
                return "Thin \(name.lowercased()) when it is dense, then stir it into moist food or use a thin layer without a sticky mound."
            case .seasoning:
                return "Measure a small amount and mix it evenly through a larger dish. This concentrated seasoning is not a stand-alone serving."
            case .sprout:
                return "Cook \(name.lowercased()) thoroughly until steaming hot, then cool and chop across the stems before serving. Rinsing alone is not sufficient."
            }
        case .meat:
            switch SolidsReferenceCatalog.meatPreparationForm(name: name) {
            case .organ:
                return "Cook \(name.lowercased()) fully, remove membrane, tough ducts, or connective tissue, and mince or mash it with moisture."
            case .ground:
                return "Cook \(name.lowercased()) fully and keep patties, meatballs, or crumbles moist. Break apart hard crusts or rubbery pieces before serving."
            case .boneIn:
                return "Cook fully, take all meat off the bone, and inspect it again for loose bone, cartilage, gristle, and tough skin before shredding or mincing it with moisture."
            case .tenderCut:
                return "Cook fully without creating a hard crust. Use a boneless portion; if the cut was cooked on the bone, take the meat off and inspect it again. Remove any gristle or tough connective tissue, then shred across the grain or mince it with moisture."
            }
        case .seafood:
            switch SolidsReferenceCatalog.seafoodPreparationForm(name: name) {
            case .crustacean:
                return "Cook fully, remove the entire shell and tail, check for fragments, then mince or flatten firm curved flesh."
            case .bivalve:
                return "Cook fully, use only the flesh, remove every shell fragment, and mince the chewy flesh finely."
            case .cephalopod:
                return "Cook fully until tender, remove inedible internal material, and mince very finely. Do not serve rings, tentacles, or rubbery chunks."
            case .smallFish:
                return "Cook as appropriate, check sodium and current advice for the exact fish, and inspect every portion carefully for bones before mashing or flaking it."
            case .fillet:
                return "Cook fully, follow current advice for the exact species, and inspect the cooked flesh carefully for fine bones before separating it into moist flakes."
            }
        case .dairy:
            if normalizedName.contains("in food") {
                return "Mix the pasteurized dairy into cooked food as an ingredient and cool the dish before serving. It should not become the child's main milk drink before 12 months."
            }
            if SolidsReferenceCatalog.scoopablePreparationKind(name: name, category: category) == .smoothDairy {
                return "Keep the pasteurized dairy scoopable and choose an unsweetened product when available. Do not add hard toppings, and loosen a thick or pasty product with another familiar food if needed."
            }
            return "Use pasteurized \(name.lowercased()) and adapt its actual firmness by crumbling, finely grating, melting, or slicing it thinly. Do not serve a firm cube or rubbery slab."
        case .egg:
            return normalizedName == "egg yolk"
                ? "Cook the yolk fully, then mash it with moisture so it is not dry or crumbly. Egg is a major food allergen even when only yolk is being served."
                : "Cook the egg fully, but keep it tender rather than rubbery or hard-edged. Mash it with moisture or cut a soft omelet into pieces that tear easily."
        case .nutAndSeed:
            if normalizedName.contains("butter") || normalizedName == "tahini" {
                return "Loosen the smooth spread with warm water or another familiar food, then stir until there are no thick gluey ridges or crunchy pieces."
            }
            if normalizedName.contains("ground") {
                return "Mix the fine meal completely into moist food and inspect it for hard pieces, coarse fragments, or dry powder pockets."
            }
            return "Grind \(name.lowercased()) finely and mix it completely into moist food, or fully soften an appropriate seed. Do not offer whole or chopped hard pieces."
        case .herbAndFlavor:
            switch SolidsReferenceCatalog.flavorPreparationForm(name: name) {
            case .bayLeaf:
                return "Use the whole leaf only to infuse a cooked dish, then find and remove it completely before plating the child's portion."
            case .fibrousAromatic:
                return "Finely grate, pound, or infuse a small amount into moist food, removing every woody or stringy piece before serving."
            case .leafyHerb:
                return "Remove firm stems, finely chop the leaves across their fibers, and mix a small culinary amount through moist food."
            case .groundSpice:
                return "Mix a small pinch evenly through moist food. Do not leave loose powder or whole hard spice pieces in the serving."
            }
        case .preparedFood:
            switch SolidsReferenceCatalog.preparedFoodPreparationForm(name: name) {
            case .soupOrStew:
                return "Cook every component fully, keep the mixture thick enough to stay together on a spoon, and modify each firm, round, or chewy ingredient actually present."
            case .patty:
                return "Cook through without creating a hard crust, then make sure the patty is moist and breaks apart easily rather than bending like rubber."
            case .spoonable:
                return "Keep the mixture thick enough to stay on a tilted spoon but loose enough to release easily. Modify every topping or mix-in separately."
            case .handheld:
                return "Keep the wrapper or bread soft enough to tear, soften or separate every filling, and avoid hard toasted edges or an overfilled bite."
            case .pastaOrRice:
                return "Cook the grain or pasta until soft, keep it moist, and adapt each meat, vegetable, cheese, bean, or other component separately."
            case .mixedDish:
                return "Cook each component safely, then adapt the firmest, roundest, stickiest, or chewiest ingredient actually present instead of relying on the dish name."
            case .sweetener:
                return "Only after the first birthday, measure a small amount into another food rather than offering it directly from a spoon or container."
            }
        }
    }

    private func shapeActionDetail(
        visual: SolidsServingVisual,
        stage: SolidsPreparationStage
    ) -> String {
        let ageContext = stage.title.lowercased()
        switch visual {
        case .mashed:
            return "For \(ageContext), mash \(name.lowercased()) until no firm lump remains. Leave only the amount of soft texture the child can already manage, and loosen any dense or sticky mash before it reaches the spoon."
        case .spear:
            return "For \(ageContext), make a long, broad piece that is easy to grasp and too large to disappear into the mouth whole. It must bend or squash easily; remove any inedible or tough part identified in this food's specific safety guidance."
        case .flattened:
            return "For \(ageContext), press each small round or dense piece until it loses its three-dimensional airway shape. If it springs back, stays firm, or splits into a hard fragment, cook it longer or mash it instead."
        case .shredded:
            return "For \(ageContext), shred or mince \(name.lowercased()) across its fibers into short tender strands. Mix dry shreds with moisture and separate any long stringy bundle before plating."
        case .thinSpread:
            return "For \(ageContext), spread only a translucent-to-thin layer across soft food, or stir it fully into a moist dish. There should be no thick ridge or spoonful that can stick as one mass."
        case .softPieces:
            return "For \(ageContext), cut pieces the child can pick up or move with a utensil without creating a whole round, hard, or rubbery shape. Test the thickest piece and keep slippery pieces from becoming overlarge mouthfuls."
        case .flakes:
            return "For \(ageContext), separate \(name.lowercased()) along its natural seams into moist flakes. Press each flake between your fingers and repeat the food-specific bone or shell check described in the caution below."
        case .spoon:
            return "For \(ageContext), aim for a thick scoopable texture that stays on a tilted spoon but releases easily in the mouth. Break up lumps, loosen sticky mixtures, and use a shallow preloaded spoon for self-feeding practice."
        }
    }

    private func textureCheckDetail(visual: SolidsServingVisual) -> String {
        let technique: String
        switch visual {
        case .mashed, .spoon:
            technique = "Drag a spoon through the food, then press any lump between thumb and forefinger. The mixture should separate easily without a hard center or sticky ball."
        case .spear, .softPieces, .flattened:
            technique = "Press the thickest piece between thumb and forefinger. It should squash, bend, or tear with light pressure and should not stay round, snap hard, or rebound like rubber."
        case .shredded, .flakes:
            technique = "Pinch a small bundle. The strands or flakes should separate easily, stay moist, and contain none of the hard, tough, or inedible hazards named in the food-specific guidance."
        case .thinSpread:
            technique = "Tilt and scrape the prepared food. The layer should be thin, without a dense ridge, dry powder pocket, crunchy piece, or paste that holds together like glue."
        }
        return "\(technique) Then scan the entire portion using this food-specific caution: \(chokingGuidance)"
    }

    private var servingActionDetail: String {
        let allergenText: String
        let confirmed = allergenIDs.compactMap { SolidsAllergen(rawValue: $0)?.displayName }
        let possible = possibleAllergenIDs.compactMap { SolidsAllergen(rawValue: $0)?.displayName }
        if !confirmed.isEmpty {
            allergenText = "This serving contains \(confirmed.joined(separator: ", ")). For a first introduction, offer a small amount in the family's planned safe setting and avoid combining it with several other new allergens."
        } else if !possible.isEmpty {
            allergenText = "The recipe may contain \(possible.joined(separator: ", ")); verify the actual package or recipe before logging what was served."
        } else {
            allergenText = "If \(name.lowercased()) is new, begin with a small amount and increase over later meals if tolerated."
        }
        return "Seat the child upright and alert, place one manageable serving at a time, and stay within arm's reach. \(allergenText) Discard food left in the child's bowl rather than returning it to storage."
    }
}

enum SolidsFoodTypeFilter: String, CaseIterable, Identifiable, Hashable {
    case condiment
    case dairy
    case drink
    case egg
    case fish
    case flower
    case fruit
    case grain
    case herbSpice
    case legume
    case meat
    case prepared
    case pseudoGrain
    case seed
    case shellfish
    case sweetener
    case treeNut
    case vegan
    case vegetable
    case vegetarian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .condiment: "Condiment"
        case .dairy: "Dairy"
        case .drink: "Drink"
        case .egg: "Egg"
        case .fish: "Fish"
        case .flower: "Flower"
        case .fruit: "Fruit"
        case .grain: "Grain"
        case .herbSpice: "Herb or spice"
        case .legume: "Legume"
        case .meat: "Meat"
        case .prepared: "Prepared food"
        case .pseudoGrain: "Pseudograin"
        case .seed: "Seed"
        case .shellfish: "Shellfish"
        case .sweetener: "Sweetener"
        case .treeNut: "Tree nut"
        case .vegan: "Vegan"
        case .vegetable: "Vegetable"
        case .vegetarian: "Vegetarian"
        }
    }

    func matches(_ food: SolidsReferenceFood) -> Bool {
        let key = SolidFoodSelection.normalizedName(food.name)
        let shellfishTerms = ["clam", "crab", "crayfish", "langoustine", "lobster", "mussel", "octopus", "oyster", "prawn", "scallop", "shrimp", "squid"]
        let seedTerms = ["chia", "flax", "hemp", "poppy", "pumpkin seed", "sesame", "sunflower seed"]
        let condimentTerms = ["bean dip", "hummus", "miso", "peanut sauce", "tahini"]
        let drinkTerms = ["buttermilk", "kefir", "milk in food", "smoothie"]
        let flowerTerms = ["artichoke", "broccoli", "broccoli rabe", "cauliflower"]
        let pseudoGrains = ["amaranth", "buckwheat", "quinoa"]
        let animalPreparedFoodTerms = ["beef", "chicken", "egg", "fish", "french toast", "meat", "quesadilla", "salmon", "shepherd", "turkey", "yogurt"]

        switch self {
        case .condiment:
            return condimentTerms.contains(where: key.contains)
        case .dairy:
            return food.category == .dairy
        case .drink:
            return drinkTerms.contains(where: key.contains)
        case .egg:
            return food.category == .egg
        case .fish:
            return food.category == .seafood && !shellfishTerms.contains(where: key.contains)
        case .flower:
            return flowerTerms.contains(where: key.contains)
        case .fruit:
            return food.category == .fruit
        case .grain:
            return food.category == .grain
        case .herbSpice:
            return food.category == .herbAndFlavor
        case .legume:
            return food.category == .beanAndPlantProtein || key == "peanut" || key == "peanut butter"
        case .meat:
            return food.category == .meat
        case .prepared:
            return food.category == .preparedFood
        case .pseudoGrain:
            return pseudoGrains.contains(key)
        case .seed:
            return seedTerms.contains(where: key.contains)
        case .shellfish:
            return food.category == .seafood && shellfishTerms.contains(where: key.contains)
        case .sweetener:
            return key == "honey"
        case .treeNut:
            return food.allergenIDs.contains(SolidsAllergen.treeNuts.rawValue)
        case .vegan:
            if [.fruit, .vegetable, .grain, .beanAndPlantProtein, .nutAndSeed, .herbAndFlavor].contains(food.category) {
                return true
            }
            guard food.category == .preparedFood else { return false }
            return food.allergenIDs.allSatisfy {
                ![SolidsAllergen.milk.rawValue, SolidsAllergen.egg.rawValue, SolidsAllergen.fish.rawValue, SolidsAllergen.crustaceanShellfish.rawValue].contains($0)
            } && !animalPreparedFoodTerms.contains(where: key.contains)
        case .vegetable:
            return food.category == .vegetable
        case .vegetarian:
            if food.category == .meat || food.category == .seafood { return false }
            if food.category != .preparedFood { return true }
            return !animalPreparedFoodTerms.contains(where: key.contains)
        }
    }
}

enum SolidsIronFilter: String, CaseIterable, Identifiable, Hashable {
    case any
    case ironRich
    case notIronRich

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .any: "Any"
        case .ironRich: "Iron-rich"
        case .notIronRich: "Not iron-rich"
        }
    }
}

enum SolidsDatabaseTrackingFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case notTried
    case wantToTry
    case tried
    case favorites

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .all: "Any status"
        case .notTried: "Not tried"
        case .wantToTry: "Want to try"
        case .tried: "Tried"
        case .favorites: "Favorites"
        }
    }
}

struct SolidsFoodProgressFilterValue: Equatable {
    var status: SolidsFoodStatus
    var isFavorite: Bool
}

struct SolidsFoodDatabaseFilters: Equatable {
    var ageMonths: Int?
    var selectedTypes = Set<SolidsFoodTypeFilter>()
    var excludedAllergenIDs = Set<String>()
    var ironFilter: SolidsIronFilter = .any
    var trackingFilter: SolidsDatabaseTrackingFilter = .all

    static let empty = SolidsFoodDatabaseFilters()

    var isEmpty: Bool { self == .empty }

    var activeCount: Int {
        (ageMonths == nil ? 0 : 1)
            + selectedTypes.count
            + excludedAllergenIDs.count
            + (ironFilter == .any ? 0 : 1)
            + (trackingFilter == .all ? 0 : 1)
    }

    func matches(
        _ food: SolidsReferenceFood,
        progress: SolidsFoodProgressFilterValue?
    ) -> Bool {
        if let ageMonths, food.minimumAgeMonths > ageMonths { return false }
        if !selectedTypes.isEmpty && !selectedTypes.contains(where: { $0.matches(food) }) { return false }
        if !excludedAllergenIDs.isDisjoint(with: food.allergenIDs) { return false }
        if !excludedAllergenIDs.isDisjoint(with: food.possibleAllergenIDs) { return false }

        switch ironFilter {
        case .any: break
        case .ironRich where !food.isIronRich: return false
        case .notIronRich where food.isIronRich: return false
        default: break
        }

        switch trackingFilter {
        case .all:
            return true
        case .notTried:
            return (progress?.status ?? .notTried) == .notTried
        case .wantToTry:
            return progress?.status == .wantToTry
        case .tried:
            return progress?.status == .tried
        case .favorites:
            return progress?.isFavorite == true
        }
    }
}

/// A compact, bundled visual vocabulary for the full food library. Emoji give
/// uncommon foods a recognizable family-level visual without requiring a
/// separate image asset for every catalog entry.
enum SolidsFoodVisual {
    static func emoji(for name: String, category: SolidsFoodCategory? = nil) -> String {
        let value = normalized(name)

        if let exact = exactEmoji[value] ?? starterEmoji[value] {
            return exact
        }

        switch category {
        case .fruit:
            return fruitEmoji(value)
        case .vegetable:
            return vegetableEmoji(value)
        case .grain:
            return grainEmoji(value)
        case .beanAndPlantProtein:
            return plantProteinEmoji(value)
        case .meat:
            return meatEmoji(value)
        case .seafood:
            return seafoodEmoji(value)
        case .dairy:
            return dairyEmoji(value)
        case .egg:
            return "🥚"
        case .nutAndSeed:
            return nutAndSeedEmoji(value)
        case .herbAndFlavor:
            return herbEmoji(value)
        case .preparedFood:
            return preparedFoodEmoji(value)
        case nil:
            return inferredEmoji(value) ?? "🍽️"
        }
    }

    private static let exactEmoji: [String: String] = [
        "acai": "🫐",
        "applesauce": "🍎",
        "atemoya": "🍈",
        "breadfruit": "🍈",
        "cactus pear": "🌵",
        "cape gooseberry": "🫐",
        "cherimoya": "🍈",
        "cloudberry": "🫐",
        "coconut flesh": "🥥",
        "crab apple": "🍎",
        "date": "🌴",
        "dragon fruit": "🐉",
        "durian": "🍈",
        "jackfruit": "🍈",
        "passion fruit": "🍈",
        "pawpaw": "🍈",
        "prickly pear": "🌵",
        "star fruit": "⭐️"
    ]

    private static let starterEmoji: [String: String] = Dictionary(
        uniqueKeysWithValues: SolidFoodIdeaCatalog.foods.map {
            (normalized($0.name), $0.emoji)
        }
    )

    private static func fruitEmoji(_ value: String) -> String {
        if contains(value, ["watermelon"]) { return "🍉" }
        if contains(value, ["cantaloupe", "honeydew", "melon"]) { return "🍈" }
        if contains(value, ["cherry"]) { return "🍒" }
        if contains(value, ["strawberry", "raspberry"]) { return "🍓" }
        if contains(value, ["berry", "currant", "grape"]) {
            return value.contains("grape") ? "🍇" : "🫐"
        }
        if contains(value, ["clementine", "grapefruit", "kumquat", "mandarin", "orange", "pomelo", "satsuma", "tangerine", "ugli fruit"]) { return "🍊" }
        if contains(value, ["lemon", "lime"]) { return "🍋" }
        if contains(value, ["apple", "quince", "pomegranate"]) { return "🍎" }
        if contains(value, ["pear"]) { return "🍐" }
        if contains(value, ["apricot", "nectarine", "peach"]) { return "🍑" }
        if contains(value, ["banana", "plantain"]) { return "🍌" }
        if contains(value, ["coconut"]) { return "🥥" }
        if contains(value, ["kiwi"]) { return "🥝" }
        if contains(value, ["mango"]) { return "🥭" }
        if contains(value, ["pineapple"]) { return "🍍" }
        if contains(value, ["avocado"]) { return "🥑" }
        if contains(value, ["fig", "plum", "prune"]) { return "🟣" }
        return SolidsFoodCategory.fruit.fallbackEmoji
    }

    private static func vegetableEmoji(_ value: String) -> String {
        if contains(value, ["bell pepper"]) { return "🫑" }
        if contains(value, ["bitter melon", "chili", "pepper"]) { return "🌶️" }
        if contains(value, ["broccoli", "cauliflower"]) { return "🥦" }
        if contains(value, ["cucumber", "zucchini"]) { return "🥒" }
        if contains(value, ["eggplant"]) { return "🍆" }
        if contains(value, ["tomatillo", "tomato"]) { return "🍅" }
        if contains(value, ["corn"]) { return "🌽" }
        if contains(value, ["garlic"]) { return "🧄" }
        if contains(value, ["onion", "scallion", "shallot"]) { return "🧅" }
        if contains(value, ["pea", "bean", "okra"]) { return "🫛" }
        if contains(value, ["potato"]) { return value.contains("sweet") ? "🍠" : "🥔" }
        if contains(value, ["yam", "taro", "cassava", "malanga", "yucca"]) { return "🍠" }
        if contains(value, ["pumpkin", "squash"]) { return "🎃" }
        if contains(value, ["cactus", "nopales"]) { return "🌵" }
        if contains(value, ["arugula", "bok choy", "cabbage", "chard", "collard", "endive", "greens", "kale", "lettuce", "radicchio", "spinach", "watercress"]) { return "🥬" }
        if contains(value, ["artichoke", "asparagus", "bamboo", "celery", "fennel", "leek"]) { return "🌱" }
        if contains(value, ["beet", "carrot", "daikon", "jicama", "parsnip", "radish", "rutabaga", "turnip"]) { return "🥕" }
        return SolidsFoodCategory.vegetable.fallbackEmoji
    }

    private static func grainEmoji(_ value: String) -> String {
        if contains(value, ["pasta", "noodle", "orzo", "udon"]) { return "🍝" }
        if contains(value, ["rice"]) { return "🍚" }
        if contains(value, ["bread", "toast", "tortilla"]) { return "🍞" }
        if contains(value, ["cereal", "cream of", "farina", "grits", "oat", "polenta", "porridge"]) { return "🥣" }
        if contains(value, ["corn", "hominy"]) { return "🌽" }
        return SolidsFoodCategory.grain.fallbackEmoji
    }

    private static func plantProteinEmoji(_ value: String) -> String {
        if contains(value, ["hummus"]) { return "🧆" }
        if contains(value, ["tofu", "tempeh"]) { return "🍱" }
        if contains(value, ["miso"]) { return "🍲" }
        if contains(value, ["patty"]) { return "🍔" }
        if contains(value, ["edamame", "pea", "sprout"]) { return "🫛" }
        return SolidsFoodCategory.beanAndPlantProtein.fallbackEmoji
    }

    private static func meatEmoji(_ value: String) -> String {
        if contains(value, ["chicken", "cornish hen", "duck", "quail", "turkey"]) { return "🍗" }
        if contains(value, ["beef", "bison", "moose", "veal", "venison"]) { return "🥩" }
        if contains(value, ["pork"]) { return "🥓" }
        if contains(value, ["meatball"]) { return "🍝" }
        return SolidsFoodCategory.meat.fallbackEmoji
    }

    private static func seafoodEmoji(_ value: String) -> String {
        if contains(value, ["crab"]) { return "🦀" }
        if contains(value, ["lobster"]) { return "🦞" }
        if contains(value, ["crayfish", "langoustine", "prawn", "shrimp"]) { return "🍤" }
        if contains(value, ["clam", "mussel", "oyster", "scallop"]) { return "🦪" }
        if contains(value, ["octopus"]) { return "🐙" }
        if contains(value, ["squid"]) { return "🦑" }
        return SolidsFoodCategory.seafood.fallbackEmoji
    }

    private static func dairyEmoji(_ value: String) -> String {
        if contains(value, ["cheese", "paneer", "queso", "ricotta"]) { return "🧀" }
        if contains(value, ["cream", "labneh", "skyr", "yogurt"]) { return "🥣" }
        if contains(value, ["butter"]) { return "🧈" }
        return SolidsFoodCategory.dairy.fallbackEmoji
    }

    private static func nutAndSeedEmoji(_ value: String) -> String {
        if contains(value, ["coconut"]) { return "🥥" }
        if contains(value, ["chestnut", "hazelnut"]) { return "🌰" }
        if contains(value, ["seed", "tahini"]) { return "🌻" }
        return SolidsFoodCategory.nutAndSeed.fallbackEmoji
    }

    private static func herbEmoji(_ value: String) -> String {
        if contains(value, ["pepper", "paprika"]) { return "🌶️" }
        if contains(value, ["garlic"]) { return "🧄" }
        if contains(value, ["ginger", "galangal"]) { return "🫚" }
        if contains(value, ["cinnamon"]) { return "🪵" }
        if contains(value, ["saffron"]) { return "🌸" }
        return SolidsFoodCategory.herbAndFlavor.fallbackEmoji
    }

    private static func preparedFoodEmoji(_ value: String) -> String {
        if contains(value, ["pancake", "waffle"]) { return "🥞" }
        if contains(value, ["burger"]) { return "🍔" }
        if contains(value, ["falafel"]) { return "🧆" }
        if contains(value, ["french toast", "toast"]) { return "🍞" }
        if contains(value, ["pasta", "gnocchi", "macaroni"]) { return "🍝" }
        if contains(value, ["porridge", "pudding", "smoothie", "yogurt parfait"]) { return "🥣" }
        if contains(value, ["rice"]) { return "🍚" }
        if contains(value, ["quesadilla", "taco"]) { return "🌮" }
        if contains(value, ["honey"]) { return "🍯" }
        if contains(value, ["potato"]) { return "🥔" }
        if contains(value, ["salmon", "fish"]) { return "🐟" }
        if contains(value, ["meat loaf"]) { return "🥩" }
        if contains(value, ["soup", "stew", "chili", "curry", "dal", "minestrone"]) { return "🍲" }
        return SolidsFoodCategory.preparedFood.fallbackEmoji
    }

    private static func inferredEmoji(_ value: String) -> String? {
        let rules: [(SolidsFoodCategory, (String) -> String)] = [
            (.fruit, fruitEmoji),
            (.vegetable, vegetableEmoji),
            (.grain, grainEmoji),
            (.beanAndPlantProtein, plantProteinEmoji),
            (.meat, meatEmoji),
            (.seafood, seafoodEmoji),
            (.dairy, dairyEmoji),
            (.nutAndSeed, nutAndSeedEmoji),
            (.herbAndFlavor, herbEmoji),
            (.preparedFood, preparedFoodEmoji)
        ]
        for (category, resolver) in rules {
            let resolved = resolver(value)
            if resolved != category.fallbackEmoji { return resolved }
        }
        return nil
    }

    private static func contains(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        SolidFoodSelection.normalizedName(value)
    }
}

enum SolidsMealType: String, CaseIterable, Identifiable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum SolidsGuidedStage: Int, CaseIterable, Identifiable, Hashable {
    case firstBites
    case graspAndMouth
    case textureExplorer
    case pincerPractice
    case familyTable

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .firstBites: "First bites"
        case .graspAndMouth: "Grasp and mouth"
        case .textureExplorer: "Texture explorer"
        case .pincerPractice: "Pincer practice"
        case .familyTable: "Family table"
        }
    }

    var skill: String {
        switch self {
        case .firstBites: "Bring food to the mouth and manage soft textures"
        case .graspAndMouth: "Hold graspable pieces and take controlled bites"
        case .textureExplorer: "Move between mashed, lumpy, shredded, and soft pieces"
        case .pincerPractice: "Pick up small soft pieces and begin utensil practice"
        case .familyTable: "Join adaptable family meals with varied textures"
        }
    }

    var range: Range<Int> {
        switch self {
        case .firstBites: 0..<10
        case .graspAndMouth: 10..<25
        case .textureExplorer: 25..<50
        case .pincerPractice: 50..<75
        case .familyTable: 75..<101
        }
    }

    static func stage(forTriedCount count: Int) -> SolidsGuidedStage {
        allCases.first(where: { $0.range.contains(count) }) ?? .familyTable
    }
}

struct SolidsGuidedMealSuggestion: Identifiable, Hashable, @unchecked Sendable {
    var dayOffset: Int
    var scheduledAt: Date
    var foods: [SolidsReferenceFood]
    var recipe: SolidsReferenceRecipe?
    var stage: SolidsGuidedStage
    var kind: SolidsGuidedMealKind = .firstTaste
    var allergenID: String?
    var allergenIntroductionStep: Int? = nil
    var allergenServingGuidance: String? = nil
    var preparationNotes: String = ""

    var id: String {
        "\(dayOffset)-\(foods.map(\.id).joined(separator: "-"))"
    }

    var primaryDestination: SolidsGuidedMealDestination? {
        if let recipe {
            return .recipe(recipe.id)
        }
        return foods.first.map { .food($0.id) }
    }

    var primaryDestinationTitle: String? {
        recipe?.title ?? foods.first?.name
    }
}

enum SolidsGuidedMealKind: String, Hashable, Sendable {
    case firstTaste
    case familiarRepeat
    case recipe

    var displayName: String {
        switch self {
        case .firstTaste: "First taste"
        case .familiarRepeat: "Familiar repeat"
        case .recipe: "Recipe"
        }
    }

    var systemImage: String {
        switch self {
        case .firstTaste: "sparkles"
        case .familiarRepeat: "arrow.triangle.2.circlepath"
        case .recipe: "fork.knife"
        }
    }
}

enum SolidsGuidedMealDestination: Equatable {
    case recipe(String)
    case food(String)
}

enum SolidsDietaryTag: String, CaseIterable, Identifiable, Hashable {
    case vegetarian
    case vegan
    case dairyFree
    case eggFree
    case wheatFree
    case ironRich

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .dairyFree: "Dairy-free"
        case .eggFree: "Egg-free"
        case .wheatFree: "Wheat-free"
        case .ironRich: "Iron-rich"
        }
    }
}

struct SolidsRecipeIngredient: Identifiable, Hashable {
    var foodName: String
    var quantity: String
    var substitutionNames: [String] = []
    var id: String { SolidFoodSelection.normalizedName(foodName) }
}

struct SolidsReferenceRecipe: Identifiable, Hashable {
    var id: String
    var title: String
    var ingredients: [SolidsRecipeIngredient]
    var minimumAgeMonths: Int
    var instructions: String
    var allergenIDs: [String]
    var mealType: SolidsMealType
    var dietaryTags: [SolidsDietaryTag]
    var servings: Int

    var foodNames: [String] { ingredients.map(\.foodName) }
}

enum SolidsSourceLibrary {
    static let foodDataCentral = URL(string: "https://fdc.nal.usda.gov/api-guide/")!
    static let cdcIntroduction = URL(string: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/when-what-and-how-to-introduce-solid-foods.html")!
    static let cdcChoking = URL(string: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/choking-hazards.html")!
    static let fdaAllergens = URL(string: "https://www.fda.gov/industry/fda-basics-industry/what-major-food-allergen")!
    static let fdaFishAdvice = URL(string: "https://www.fda.gov/food/consumers/advice-about-eating-fish")!
    static let fdaProduceSafety = URL(string: "https://www.fda.gov/food/buy-store-serve-safe-food/selecting-and-serving-produce-safely")!
    static let nhsFoodSafety = URL(string: "https://www.nhs.uk/best-start-in-life/baby/weaning/safe-weaning/preparing-food-safely/")!
    static let aapFruitJuice = URL(string: "https://www.healthychildren.org/English/healthy-living/nutrition/Pages/Where-We-Stand-Fruit-Juice.aspx")!
    static let nccihAcai = URL(string: "https://www.nccih.nih.gov/health/acai")!
    static let datePalmFruitAllergy = URL(string: "https://doi.org/10.1034/j.1398-9995.1999.00116.x")!
    static let heartOfPalmAnaphylaxis = URL(string: "https://doi.org/10.1111/j.1398-9995.2006.01051.x")!
    static let whoComplementaryFeeding = URL(string: "https://www.who.int/publications/i/item/9789240081864")!
    static let espghanSugarPosition = URL(string: "https://doi.org/10.1097/MPG.0000000000001733")!
    static let aapStartingSolids = URL(string: "https://www.healthychildren.org/English/ages-stages/baby/feeding-nutrition/Pages/Starting-Solid-Foods.aspx")!
    static let aapAllergenIntroduction = URL(string: "https://www.healthychildren.org/English/healthy-living/nutrition/Pages/when-to-introduce-egg-peanut-butter-and-other-common-food-allergens-to-your-baby-food-allergy-prevention-tips.aspx")!
    static let niaidPeanutGuidance = URL(string: "https://www.niaid.nih.gov/sites/default/files/peanut-allergy-prevention-guidelines-parent-summary.pdf")!

    static func displayName(for url: URL) -> String {
        let source = url.absoluteString.lowercased()
        if url == cdcIntroduction { return "CDC — Starting solid foods" }
        if url == cdcChoking { return "CDC — Choking prevention" }
        if url == aapFruitJuice { return "AAP — Fruit juice guidance" }
        if url == aapStartingSolids { return "AAP — Starting solids and portions" }
        if url == aapAllergenIntroduction { return "AAP — Allergen introduction guidance" }
        if url == fdaProduceSafety { return "FDA — Produce and sprout safety" }
        if url.host?.contains("healthychildren") == true { return "American Academy of Pediatrics" }
        if url.host?.contains("nccih") == true { return "NIH NCCIH — Açaí safety" }
        if source.contains("10.1034/j.1398-9995.1999.00116.x") {
            return "Kwaasi et al. — Date-fruit allergy"
        }
        if source.contains("10.1111/j.1398-9995.2006.01051.x") {
            return "Mayoral et al. — Heart-of-palm allergy"
        }
        if url.host?.contains("who.int") == true { return "WHO complementary feeding guideline" }
        if source.contains("10.1097/mpg.0000000000001733") {
            return "ESPGHAN sugar position paper"
        }
        if url.host?.contains("usda") == true { return "USDA FoodData Central" }
        if url.path.contains("advice-about-eating-fish") { return "FDA/EPA fish advice" }
        if url.host?.contains("fda") == true { return "FDA major allergens" }
        if url.host?.contains("niaid") == true { return "NIAID peanut introduction guidance" }
        if url.host?.contains("nhs") == true { return "NHS food preparation safety" }
        return "Reference source"
    }
}

enum SolidsReferenceCatalog {
    static let version = 8

    /// Builds the generated catalog indexes away from the UI thread. The home
    /// screen calls this after its first frame so opening search-heavy screens
    /// does not pay the one-time 400+ item setup cost during navigation.
    static func warmCaches() {
        _ = foodSearchEntries.count
        _ = foodsByCategory.count
        _ = recipeSearchEntries.count
        _ = recipesByFoodID.count
        _ = recipesByAllergenID.count
        _ = guidedCandidateFoods.count
    }

    private struct FoodSearchEntry {
        var food: SolidsReferenceFood
        var normalizedTerms: [String]
    }

    private struct RecipeSearchEntry {
        var recipe: SolidsReferenceRecipe
        var normalizedText: String
    }

    static let foods: [SolidsReferenceFood] = {
        let groups: [(SolidsFoodCategory, String)] = [
            (.fruit, fruitNames),
            (.vegetable, vegetableNames),
            (.grain, grainNames),
            (.beanAndPlantProtein, plantProteinNames),
            (.meat, meatNames),
            (.seafood, seafoodNames),
            (.dairy, dairyNames),
            (.egg, eggNames),
            (.nutAndSeed, nutAndSeedNames),
            (.herbAndFlavor, herbAndFlavorNames),
            (.preparedFood, preparedFoodNames)
        ]

        var seen = Set<String>()
        return groups.flatMap { category, value in
            names(in: value).compactMap { name -> SolidsReferenceFood? in
                let id = slug(name)
                guard seen.insert(id).inserted else { return nil }
                return makeFood(id: id, name: name, category: category)
            }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    private static let foodsByID: [String: SolidsReferenceFood] =
        Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })

    private static let foodsByLookupName: [String: SolidsReferenceFood] = {
        var result: [String: SolidsReferenceFood] = [:]
        for food in foods {
            let nameKey = normalized(food.name)
            if result[nameKey] == nil { result[nameKey] = food }
            for alias in food.aliases where result[normalized(alias)] == nil {
                result[normalized(alias)] = food
            }
        }
        return result
    }()

    private static let foodSearchEntries: [FoodSearchEntry] = foods.map { food in
        FoodSearchEntry(
            food: food,
            normalizedTerms: ([food.name] + food.aliases).map(normalized)
        )
    }

    private static let foodsByCategory = Dictionary(grouping: foods, by: \SolidsReferenceFood.category)

    private static let coreRecipes: [SolidsReferenceRecipe] = [
        recipe("avocado-bean-mash", "Avocado bean mash", ["Avocado", "Black bean"], 6, "Mash the cooked beans and ripe avocado until smooth enough for the child's current eating skills."),
        recipe("apple-oatmeal", "Apple oatmeal", ["Apple", "Oatmeal"], 6, "Cook the oatmeal until soft. Stir in finely grated or cooked mashed apple and cool before serving."),
        recipe("banana-yogurt", "Banana yogurt", ["Banana", "Plain whole-milk yogurt"], 6, "Mash ripe banana into pasteurized plain yogurt.", allergens: ["milk"]),
        recipe("lentil-sweet-potato", "Lentil sweet potato mash", ["Lentil", "Sweet potato"], 6, "Cook both ingredients until very soft, then mash together with water as needed."),
        recipe("salmon-potato-cakes", "Soft salmon potato cakes", ["Salmon", "Potato"], 9, "Combine fully cooked flaked salmon and mashed potato. Form soft patties and cook through.", allergens: ["fish"]),
        recipe("egg-broccoli", "Egg and broccoli strips", ["Egg", "Broccoli"], 9, "Cook the egg completely with finely chopped, very soft broccoli. Cut into easy-to-hold strips.", allergens: ["egg"]),
        recipe("tofu-mango", "Tofu with mango", ["Tofu", "Mango"], 9, "Serve soft tofu strips with ripe, soft mango pieces sized for current eating skills.", allergens: ["soy"]),
        recipe("chicken-pea-pasta", "Chicken and pea pasta", ["Chicken", "Pea", "Pasta"], 12, "Cook pasta, peas, and chicken until tender. Chop to a manageable size and moisten before serving.", allergens: ["wheat"]),
        recipe("beef-tomato-rice", "Beef tomato rice", ["Beef", "Tomato", "Rice"], 12, "Cook ground beef fully, simmer with tomato, and combine with soft rice."),
        recipe("chickpea-tahini", "Chickpea tahini spread", ["Chickpea", "Tahini"], 9, "Blend cooked chickpeas, tahini, and water into a smooth spread.", allergens: ["sesame"]),
        recipe("pear-ricotta-toast", "Pear ricotta toast", ["Pear", "Ricotta", "Whole-wheat toast"], 9, "Spread pasteurized ricotta thinly on lightly toasted bread and top with very soft pear.", allergens: ["milk", "wheat"]),
        recipe("pumpkin-quinoa", "Pumpkin quinoa bowl", ["Pumpkin", "Quinoa"], 6, "Combine well-cooked quinoa with smooth cooked pumpkin and thin as needed."),
        recipe("turkey-zucchini", "Turkey zucchini patties", ["Turkey", "Zucchini"], 9, "Cook ground turkey fully with grated zucchini in small, soft patties."),
        recipe("cod-cauliflower", "Cod cauliflower mash", ["Cod", "Cauliflower"], 6, "Cook cod completely, check carefully for bones, and mash with very soft cauliflower.", allergens: ["fish"]),
        recipe("peanut-banana-oats", "Peanut banana oats", ["Peanut butter", "Banana", "Oatmeal"], 6, "Thin smooth peanut butter into soft oatmeal, then stir in mashed banana.", allergens: ["peanuts"]),
        recipe("sesame-noodles", "Soft sesame noodles", ["Wheat noodle", "Tahini"], 12, "Cook noodles until soft and cut as needed. Toss with thinned tahini.", allergens: ["wheat", "sesame"]),
        recipe("yogurt-berry", "Berry yogurt", ["Blueberry", "Plain whole-milk yogurt"], 6, "Cook or crush berries, then mix into pasteurized plain yogurt.", allergens: ["milk"]),
        recipe("polenta-spinach", "Creamy spinach polenta", ["Polenta", "Spinach"], 6, "Cook polenta until soft and stir in finely chopped cooked spinach."),
        recipe("lamb-carrot", "Lamb carrot stew", ["Lamb", "Carrot"], 9, "Cook lamb thoroughly with carrot until everything is tender; shred or chop for current skills."),
        recipe("edamame-avocado", "Edamame avocado mash", ["Edamame", "Avocado"], 9, "Cook shelled edamame until soft and blend thoroughly with ripe avocado.", allergens: ["soy"]),
        recipe("cottage-cheese-peach", "Peach cottage cheese", ["Peach", "Cottage cheese"], 9, "Finely chop very soft peach and mix with pasteurized cottage cheese.", allergens: ["milk"]),
        recipe("black-bean-quesadilla", "Black bean quesadilla", ["Black bean", "Corn tortilla", "Cheddar cheese"], 12, "Mash cooked beans onto a tortilla with pasteurized cheese. Heat through and cut into manageable pieces.", allergens: ["milk"]),
        recipe("shrimp-grits", "Shrimp and grits", ["Shrimp", "Grits"], 12, "Cook shrimp thoroughly, mince finely, and stir into soft grits.", allergens: ["crustaceanShellfish"]),
        recipe("tempeh-broccoli-rice", "Tempeh broccoli rice", ["Tempeh", "Broccoli", "Brown rice"], 12, "Cook tempeh and broccoli until tender. Chop and serve with soft rice.", allergens: ["soy"]),
        recipe("shrimp-sweet-potato-mash", "Shrimp sweet potato mash", ["Shrimp", "Sweet potato"], 6, "Cook shrimp completely, remove the shell and tail, and mince very finely. Mix through soft mashed sweet potato in a texture suited to current skills.", allergens: ["crustaceanShellfish"]),
        recipe("almond-pear-oats", "Almond pear oats", ["Almond butter", "Pear", "Oatmeal"], 6, "Cook oatmeal and pear until soft. Thin smooth almond butter well, then mix it evenly through the oats; never serve a thick spoonful.", allergens: ["treeNuts"])
    ]

    static let recipes: [SolidsReferenceRecipe] = {
        var results = coreRecipes
        var seen = Set(results.map(\.id))
        let proteins = ["Lentil", "Black bean", "Chickpea", "Chicken", "Turkey", "Beef", "Salmon", "Egg", "Tofu", "Plain whole-milk yogurt", "Ricotta", "Cod"]
        let produce = ["Sweet potato", "Avocado", "Broccoli", "Carrot", "Zucchini", "Pear", "Apple", "Pea", "Spinach", "Cauliflower", "Pumpkin", "Mango"]
        let bases = ["Oatmeal", "Quinoa", "Rice", "Polenta", "Pasta", "Couscous", "Potato", "Corn tortilla"]

        outer: for (proteinIndex, protein) in proteins.enumerated() {
            for (produceIndex, fruitOrVegetable) in produce.enumerated() {
                for (baseIndex, base) in bases.enumerated() {
                    let id = "meal-\(slug(protein))-\(slug(fruitOrVegetable))-\(slug(base))"
                    guard seen.insert(id).inserted else { continue }
                    let index = proteinIndex + produceIndex + baseIndex
                    let age = base == "Pasta" || base == "Couscous" || base == "Corn tortilla" ? 9 : 6
                    let mealType = SolidsMealType.allCases[index % SolidsMealType.allCases.count]
                    results.append(recipe(
                        id,
                        generatedRecipeTitle(
                            protein: protein,
                            produce: fruitOrVegetable,
                            base: base,
                            styleIndex: index
                        ),
                        [protein, fruitOrVegetable, base],
                        age,
                        generatedRecipeInstructions(
                            protein: protein,
                            produce: fruitOrVegetable,
                            base: base,
                            age: age,
                            styleIndex: index
                        ),
                        mealType: mealType
                    ))
                    if results.count >= 424 { break outer }
                }
            }
        }
        return results
    }()

    private static let recipesByID: [String: SolidsReferenceRecipe] =
        Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

    private static let recipesByFoodID: [String: [SolidsReferenceRecipe]] = {
        var result: [String: [SolidsReferenceRecipe]] = [:]
        for recipe in recipes {
            var includedFoodIDs = Set<String>()
            for name in recipe.foodNames {
                guard let foodID = food(named: name)?.id,
                      includedFoodIDs.insert(foodID).inserted else { continue }
                result[foodID, default: []].append(recipe)
            }
        }
        return result
    }()

    private static let recipesByAllergenID: [String: [SolidsReferenceRecipe]] = {
        var result: [String: [SolidsReferenceRecipe]] = [:]
        for recipe in recipes {
            for allergenID in recipe.allergenIDs {
                result[allergenID, default: []].append(recipe)
            }
        }
        return result
    }()

    private static let recipeSearchEntries: [RecipeSearchEntry] = recipes.map { recipe in
        RecipeSearchEntry(
            recipe: recipe,
            normalizedText: normalized(([recipe.title] + recipe.foodNames).joined(separator: " "))
        )
    }

    private static func generatedRecipeTitle(
        protein: String,
        produce: String,
        base: String,
        styleIndex: Int
    ) -> String {
        switch styleIndex % 6 {
        case 0: return "Creamy \(protein) and \(produce) \(base) bowl"
        case 1: return "Soft \(protein), \(produce) and \(base) patties"
        case 2: return "\(produce) \(base) with tender \(protein)"
        case 3: return "One-pot \(protein) and \(produce) \(base)"
        case 4: return "Scoopable \(protein), \(produce) and \(base) mash"
        default: return "Family-style \(protein) with \(produce) and \(base)"
        }
    }

    private static func generatedRecipeInstructions(
        protein: String,
        produce: String,
        base: String,
        age: Int,
        styleIndex: Int
    ) -> String {
        let finish = age < 9
            ? "Mash or load onto a spoon; offer a soft graspable piece only when it squishes easily."
            : "Keep it moist and serve as soft pieces, a scoopable mixture, or a tender patty for current skills."
        switch styleIndex % 6 {
        case 0:
            return "Cook \(base.lowercased()) until very soft. Prepare \(protein.lowercased()) fully and cook \(produce.lowercased()) until tender. Stir together with water as needed for a creamy bowl. \(finish)"
        case 1:
            return "Cook \(protein.lowercased()), \(produce.lowercased()), and \(base.lowercased()) until fully done. Mash, shape into soft patties, and cook until the center is set without forming a hard crust. \(finish)"
        case 2:
            return "Make \(base.lowercased()) soft and moist. Fold in tender \(produce.lowercased()), then add fully cooked \(protein.lowercased()) in a texture appropriate for the child. \(finish)"
        case 3:
            return "Simmer \(protein.lowercased()) and \(produce.lowercased()) with \(base.lowercased()) until every component is soft and fully cooked. Add water during cooking so the mixture does not become dry or sticky. \(finish)"
        case 4:
            return "Prepare \(protein.lowercased()) safely, cook \(produce.lowercased()) until it crushes easily, and soften \(base.lowercased()). Mash together but leave gradually more texture as skills develop. \(finish)"
        default:
            return "Cook \(protein.lowercased()) completely and prepare \(produce.lowercased()) and \(base.lowercased()) without added salt. Set aside the child's portion, then modify its shape and texture before seasoning the family meal. \(finish)"
        }
    }

    static let guidedFoods: [SolidsReferenceFood] = {
        let preferredNames = [
            "Avocado", "Oatmeal", "Lentil", "Banana", "Egg", "Sweet potato", "Plain whole-milk yogurt",
            "Broccoli", "Peanut butter", "Chicken", "Pear", "Tofu", "Salmon", "Apple", "Tahini",
            "Black bean", "Mango", "Ricotta", "Quinoa", "Carrot", "Shrimp", "Beef", "Pea", "Cod"
        ]
        var selected = preferredNames.compactMap(food(named:))
        var seen = Set(selected.map(\.id))
        let remainder = foods.filter(\.isEligibleForGuidedPath).sorted { lhs, rhs in
            let lhsScore = (lhs.isIronRich ? 3 : 0) + (!lhs.allergenIDs.isEmpty ? 2 : 0)
            let rhsScore = (rhs.isIronRich ? 3 : 0) + (!rhs.allergenIDs.isEmpty ? 2 : 0)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        for food in remainder where selected.count < 100 && seen.insert(food.id).inserted {
            selected.append(food)
        }
        return selected
    }()

    static let guidedCandidateFoods: [SolidsReferenceFood] = {
        let preferredIDs = Set(guidedFoods.map(\.id))
        return guidedFoods + foods.filter { !preferredIDs.contains($0.id) }
    }()

    static func allergenGuidance(_ allergen: SolidsAllergen) -> SolidsAllergenGuidance {
        let form: String
        let portion: String
        switch allergen {
        case .milk:
            form = "Pasteurized plain yogurt or another dairy food already appropriate for the child's skills; not cow's milk as the main drink before 12 months."
            portion = "Example routine portion after tolerance: about 2 tablespoons plain yogurt."
        case .egg:
            form = "Egg cooked until the white and yolk are firm, mashed or cut for current skills."
            portion = "Example routine portion after tolerance: about one-third of a well-cooked egg."
        case .fish:
            form = "Fully cooked, carefully deboned fish served as moist flakes or a soft patty."
            portion = "Example routine portion after tolerance: about 2 tablespoons cooked flakes."
        case .crustaceanShellfish:
            form = "Fully cooked shellfish, shell and tail removed, then minced finely into a familiar food."
            portion = "Example routine portion after tolerance: about 1–2 tablespoons minced shellfish."
        case .treeNuts:
            form = "Smooth tree-nut butter thinned into a familiar food, or nuts ground to a fine powder—never whole nuts."
            portion = "Example routine portion after tolerance: up to 2 teaspoons smooth nut butter, well thinned."
        case .peanuts:
            form = "Smooth peanut butter thinned with warm water or mixed into a familiar soft food—never whole peanuts or thick spoonfuls."
            portion = "NIAID example: 2 teaspoons smooth peanut butter provides about 2 g peanut protein; thin before serving."
        case .wheat:
            form = "A soft wheat food such as well-cooked pasta, wheat cereal, or lightly toasted bread modified for current skills."
            portion = "Example routine portion after tolerance: about 2 tablespoons cooked wheat cereal or pasta."
        case .soy:
            form = "Soft tofu, mashed edamame, or another cooked soy food modified for current skills."
            portion = "Example routine portion after tolerance: about 2 tablespoons soft tofu or mashed soy food."
        case .sesame:
            form = "Tahini thinned into a familiar soft food—never a thick spoonful."
            portion = "Example routine portion after tolerance: up to 2 teaspoons tahini, well thinned."
        }
        return SolidsAllergenGuidance(
            allergen: allergen,
            safeForm: form,
            exampleServing: portion,
            steps: [
                SolidsAllergenIntroductionStep(number: 1, title: "Choose one allergen", detail: "Offer it when the child is well, earlier in the day, in an infant-safe form. Use a familiar food alongside it."),
                SolidsAllergenIntroductionStep(number: 2, title: "Start with a small taste", detail: "Offer a small taste, pause for about 10 minutes, and watch closely. Stop if a possible reaction appears."),
                SolidsAllergenIntroductionStep(number: 3, title: "Build the serving", detail: "If no reaction appears, gradually offer more of the prepared portion during the meal without pressuring the child to finish."),
                SolidsAllergenIntroductionStep(number: 4, title: "Keep it in rotation", detail: "After it is tolerated, continue offering an age-appropriate form as a normal part of the weekly meal rotation.")
            ],
            sourceURLs: allergen == .peanuts
                ? [SolidsSourceLibrary.aapAllergenIntroduction, SolidsSourceLibrary.niaidPeanutGuidance]
                : [SolidsSourceLibrary.aapAllergenIntroduction, SolidsSourceLibrary.fdaAllergens]
        )
    }

    static func introductionServingGuidance(
        for allergen: SolidsAllergen,
        step: Int
    ) -> String {
        let guidance = allergenGuidance(allergen)
        if step <= 1 {
            return "Start with a small taste, pause for about 10 minutes, then gradually offer more of the prepared portion if no possible reaction appears. \(guidance.exampleServing)"
        }
        return "Repeat \(guidance.safeForm) \(guidance.exampleServing) The child never has to finish the example portion."
    }

    static func food(id: String) -> SolidsReferenceFood? {
        foodsByID[id]
    }

    static func food(named name: String) -> SolidsReferenceFood? {
        foodsByLookupName[normalized(name)]
    }

    static func recipe(id: String) -> SolidsReferenceRecipe? {
        recipesByID[id]
    }

    static func search(_ query: String, category: SolidsFoodCategory? = nil) -> [SolidsReferenceFood] {
        let key = normalized(query)
        return foodSearchEntries.compactMap { entry in
            guard category == nil || entry.food.category == category,
                  key.isEmpty || entry.normalizedTerms.contains(where: { $0.contains(key) }) else {
                return nil
            }
            return entry.food
        }
    }

    static func recipes(containingFoodID foodID: String) -> [SolidsReferenceRecipe] {
        recipesByFoodID[foodID] ?? []
    }

    static func recipes(containingAllergenID allergenID: String) -> [SolidsReferenceRecipe] {
        recipesByAllergenID[allergenID] ?? []
    }

    static func searchRecipes(_ query: String) -> [SolidsReferenceRecipe] {
        let key = normalized(query)
        guard !key.isEmpty else { return recipes }
        return recipeSearchEntries.compactMap { entry in
            entry.normalizedText.contains(key) ? entry.recipe : nil
        }
    }

    private static func recipe(
        _ id: String,
        _ title: String,
        _ foodNames: [String],
        _ age: Int,
        _ instructions: String,
        allergens: [String] = [],
        mealType: SolidsMealType = .breakfast
    ) -> SolidsReferenceRecipe {
        let references = foodNames.compactMap(food(named:))
        let resolvedAllergens = Set(allergens + references.flatMap(\.allergenIDs))
        let categories = Set(references.map(\.category))
        var tags = [SolidsDietaryTag]()
        if categories.isDisjoint(with: [.meat, .seafood]) { tags.append(.vegetarian) }
        if categories.isDisjoint(with: [.meat, .seafood, .dairy, .egg]) { tags.append(.vegan) }
        if !resolvedAllergens.contains(SolidsAllergen.milk.rawValue) { tags.append(.dairyFree) }
        if !resolvedAllergens.contains(SolidsAllergen.egg.rawValue) { tags.append(.eggFree) }
        if !resolvedAllergens.contains(SolidsAllergen.wheat.rawValue) { tags.append(.wheatFree) }
        if references.contains(where: \.isIronRich) { tags.append(.ironRich) }
        return SolidsReferenceRecipe(
            id: id,
            title: title,
            ingredients: foodNames.map { name in
                SolidsRecipeIngredient(
                    foodName: name,
                    quantity: ingredientQuantity(for: name),
                    substitutionNames: substitutions(for: name)
                )
            },
            minimumAgeMonths: age,
            instructions: instructions,
            allergenIDs: Array(resolvedAllergens).sorted(),
            mealType: mealType,
            dietaryTags: tags,
            servings: 1
        )
    }

    private static func makeFood(
        id: String,
        name: String,
        category: SolidsFoodCategory
    ) -> SolidsReferenceFood {
        let allergens = allergenIDs(name: name, category: category)
        let possibleAllergens = possibleAllergenIDs(name: name, category: category)
        let minimumAge = normalized(name) == "honey" ? 12 : 6
        let isIronRich = ironRichStatus(name: name, category: category)
        let highlights = nutritionHighlights(name: name, category: category)
        let visuals = servingVisuals(name: name, category: category)
        let preparationStages = preparations(name: name, category: category, minimumAge: minimumAge)
            .enumerated()
            .map { index, stage in
                var stage = stage
                let visual = visuals.indices.contains(index) ? visuals[index] : (visuals.last ?? .spoon)
                stage.servingAmount = servingAmountGuidance(
                    name: name,
                    category: category,
                    ageMonths: stage.minimumAgeMonths,
                    visual: visual
                )
                return stage
            }
        return SolidsReferenceFood(
            id: id,
            name: name,
            category: category,
            aliases: aliases(for: name),
            minimumAgeMonths: minimumAge,
            isIronRich: isIronRich,
            allergenIDs: allergens,
            possibleAllergenIDs: possibleAllergens,
            details: foodDetails(
                name: name,
                category: category,
                minimumAge: minimumAge,
                isIronRich: isIronRich,
                allergens: allergens,
                possibleAllergens: possibleAllergens,
                nutritionHighlights: highlights,
                preparations: preparationStages
            ),
            safetyNote: safetyNote(name: name, category: category),
            chokingGuidance: chokingGuidance(name: name, category: category),
            nutritionHighlights: highlights,
            preparations: preparationStages,
            servingVisuals: visuals,
            sourceURLs: sourceURLs(
                name: name,
                category: category,
                hasAllergens: !allergens.isEmpty || !possibleAllergens.isEmpty
            )
        )
    }

    private static func foodDetails(
        name: String,
        category: SolidsFoodCategory,
        minimumAge: Int,
        isIronRich: Bool,
        allergens: [String],
        possibleAllergens: [String],
        nutritionHighlights: [String],
        preparations: [SolidsPreparationStage]
    ) -> SolidsFoodDetails {
        let key = normalized(name)
        if key == "acai" {
            return SolidsFoodDetails(
                introductionSummary: "Açaí can be offered once a child is developmentally ready for solids, generally around 6 months. Use commercially prepared seedless pulp, purée, or powder rather than a fresh seeded berry.",
                backgroundSummary: "Açaí is a deep-purple palm fruit native to the Amazon region of South America. Outside growing regions, it is usually sold as frozen deseeded pulp, purée packets, or powder rather than as fresh berries.",
                nutritionSummary: "Açaí contributes fiber and plant pigments called anthocyanins, along with varying amounts of calcium, iron, zinc, and vitamin B6. Research in people is too limited to support many of the health claims used to market açaí products. Choose food products rather than supplements or energy blends, which may contain caffeine or other ingredients intended for adults.",
                allergenSummary: "Açaí is not one of the nine major U.S. food allergens, although any food can cause a reaction. Published reports document allergy to date fruit and a rare anaphylactic reaction to heart of palm, but they do not establish that someone with either allergy will react to açaí. If the child has a known allergy to another palm-family food, discuss introduction with their clinician; otherwise start with a small amount and increase over later meals if tolerated.",
                choosingGuidance: "Look for an unsweetened frozen deseeded pulp or purée, or a plain powder with a short ingredient list. Check bowls and blends for honey, caffeine-containing supplements, added sugar, granola, whole nuts, large seeds, or other ingredients that need separate modification.",
                storageGuidance: "Keep frozen pulp frozen until needed and follow the package's thawing and refrigeration directions. Use thawed product promptly, keep prepared food cold, and discard food left in the child's bowl after the meal.",
                questions: [
                    SolidsFoodQuestion(
                        question: "Can babies have an açaí bowl?",
                        answer: "Yes, if every ingredient is appropriate for the child. Before 12 months, exclude honey. Remove or modify granola, whole nuts, whole grapes, large seeds, and other choking hazards. A smooth bowl can be useful for preloaded-spoon practice."
                    ),
                    SolidsFoodQuestion(
                        question: "When can a child have açaí juice?",
                        answer: "Do not offer fruit juice before 12 months. After the first birthday, an occasional small serving of pasteurized juice can be offered, but whole or puréed fruit is usually more useful because it retains fiber. WHO guidance recommends limiting 100% fruit juice during complementary feeding, and raw açaí fruit or juice has a documented contamination risk, so avoid unpasteurized products."
                    )
                ]
            )
        }

        let introductionSummary = ingredientIntroduction(
            name: name,
            category: category,
            minimumAge: minimumAge
        )

        let allergenNames = allergens.compactMap { SolidsAllergen(rawValue: $0)?.displayName }
        let possibleAllergenNames = possibleAllergens.compactMap { SolidsAllergen(rawValue: $0)?.displayName }
        let allergenSummary: String
        if !allergenNames.isEmpty {
            allergenSummary = "\(name) contains \(readableList(allergenNames)), which \(allergenNames.count == 1 ? "is a major food allergen" : "are major food allergens"). When first introducing it, use a developmentally appropriate form, start with a small amount, and avoid combining it with several other new allergens in the same meal."
        } else if !possibleAllergenNames.isEmpty {
            allergenSummary = "\(name) is a prepared food whose recipe may contain \(readableList(possibleAllergenNames)). Check the actual recipe or package label because allergen content varies. Any food can cause an individual reaction even when it is not one of the nine major allergens."
        } else {
            allergenSummary = "\(name) is not one of the nine major U.S. food allergens. An individual reaction is still possible with any food, so begin with a small amount and increase over later meals if it is tolerated."
        }

        let nutrients = readableList(nutritionHighlights.map { $0.lowercased() })
        let ironSentence = isIronRich
            ? " This food can help vary iron sources, though the amount depends on the cut, species, product, and preparation."
            : ""
        let nutritionSummary = "\(name) can contribute \(nutrients).\(ironSentence) The useful amount changes with variety, processing, and serving size, so pair it with a varied diet rather than treating it as a supplement or cure."

        let handling = ingredientHandling(name: name, category: category)

        return SolidsFoodDetails(
            introductionSummary: introductionSummary,
            backgroundSummary: ingredientBackground(name: name, category: category),
            nutritionSummary: nutritionSummary,
            allergenSummary: allergenSummary,
            choosingGuidance: handling.choosing,
            storageGuidance: handling.storage,
            questions: ingredientQuestions(
                name: name,
                category: category,
                firstPreparation: preparations.first?.instructions
            )
        )
    }

    private static func readableList(_ values: [String]) -> String {
        switch values.count {
        case 0: return ""
        case 1: return values[0]
        case 2: return "\(values[0]) and \(values[1])"
        default: return "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }

    private static func ingredientIntroduction(
        name: String,
        category: SolidsFoodCategory,
        minimumAge: Int
    ) -> String {
        let key = normalized(name)
        if key == "honey" {
            return "Do not offer honey in any form before 12 months because it can contain spores that cause infant botulism. After the first birthday, use only a small amount and remember that honey is an added sugar."
        }
        if key == "swordfish" {
            return "Swordfish is not recommended for young children because it is among the fish highest in mercury. Choose a lower-mercury fish from current FDA/EPA advice instead."
        }
        if ["cactus pear", "prickly pear"].contains(key) {
            return "\(name) can generally be introduced once a child shows developmental readiness for solids, usually around 6 months. Use only fruit with every spine and hair-like glochid removed, peel away the outer skin, and serve the ripe soft flesh in a mash or another manageable form."
        }
        if key.contains("milk in food") || key == "buttermilk in food" {
            return "Pasteurized \(name.lowercased()) can be used as an ingredient once a child is ready for solids, generally around 6 months. Cow's milk should not replace breast milk or infant formula as the main drink before 12 months."
        }
        if category == .nutAndSeed {
            if key.contains("butter") || key == "tahini" {
                let riskGuidance = key == "peanut butter"
                    ? " If the child has severe eczema or an egg allergy, ask their clinician how and where to introduce peanut."
                    : ""
                return "\(name) can generally be introduced once a child is developmentally ready for solids, usually around 6 months. Use a smooth version thinned into a familiar soft food or spread in a very thin layer; never offer a thick spoonful.\(riskGuidance)"
            }
            return "\(name) can generally be introduced once a child is developmentally ready for solids, usually around 6 months. Offer it finely ground into moist food or in a smooth, well-thinned butter; whole nuts and hard seed pieces are choking hazards."
        }
        if category == .herbAndFlavor {
            return "\(name) can season food from the start of solids in a finely prepared culinary amount. Mix it through moist food and keep whole pods, sticks, hard seeds, woody stems, and loose powder out of the serving."
        }
        if category == .preparedFood {
            return "\(name) can be adapted once every ingredient is appropriate for the child, generally from around 6 months unless noted otherwise. Check the recipe's allergens, sodium, added sugar, cooking, and the shape of each component rather than judging the dish by its name alone."
        }
        if minimumAge >= 12 {
            return "\(name) should not be offered before \(minimumAge) months. When it is introduced, use the ingredient-specific preparation and safety guidance below."
        }

        let lead = "\(name) can generally be introduced once a child shows developmental readiness for solids, usually around 6 months. "
        let guidance: String
        switch category {
        case .fruit:
            switch fruitPreparationForm(name: name) {
            case .sauce:
                guidance = "Choose an unsweetened, spoonable sauce and check the ingredient list for honey or added sugar."
            case .smallRoundBerry:
                guidance = "Cook if firm, then mash or flatten every berry so it no longer keeps a small round shape."
            case .aggregateBerry:
                guidance = "Use very ripe fruit and mash, flatten, or tear it when a firm core or berry size makes that necessary."
            case .roundOrSlipperyFruit:
                guidance = "Remove any pit, large seed, husk, or inedible peel, then mash or cut the ripe flesh lengthwise so it is not served whole and round."
            case .citrus:
                guidance = "Remove peel, seeds, tough membrane, and excess pith, then offer the juicy pulp in a manageable soft form."
            case .firmFruit:
                guidance = "Cook or finely grate the fruit until it is no longer a hard raw chunk, and remove the core and seeds."
            case .stoneFruit:
                guidance = "Remove the pit and use very ripe, soft flesh; cook it first when the fruit is still firm."
            case .melon:
                guidance = "Remove rind and hard seeds, then offer soft flesh without forming small slippery balls."
            case .softFruit:
                guidance = "Use fully ripe flesh and remove only the stem, core, tough peel, or hard seed that this fruit actually has."
            case .seededPulp:
                guidance = "Scoop the soft pulp from the rind and serve it by spoon, removing any large or unexpectedly hard seed."
            case .arils:
                guidance = "Crush or flatten the arils rather than offering a handful of intact firm, round pieces."
            case .driedStickyFruit:
                guidance = "Remove the pit, soften the dried fruit thoroughly, and mash or mince it into moist food so it cannot form a dense sticky mouthful."
            case .gratedFlesh:
                guidance = "Use finely grated flesh or a smooth coconut product mixed into moist food, not hard chunks or chewy dry strips."
            case .cookBeforeServing:
                guidance = "Peel and trim it as applicable, cook it thoroughly, and serve only when the flesh is soft throughout."
            }
        case .vegetable:
            switch vegetablePreparationForm(name: name) {
            case .leafy:
                guidance = "Cook the leaves and stems until tender, chop across the fibers, and mix them into moist food rather than offering a wad of leaves."
            case .flower:
                guidance = "Cook the thickest stem and florets until they crush easily, then mash or offer a large soft floret."
            case .compactBud:
                guidance = "Cook through the dense center and halve, quarter, mash, or flatten the round bud rather than serving it whole."
            case .squash:
                guidance = "Remove hard rind and seeds, cook the flesh until it crushes easily, and avoid firm cubes."
            case .roundKernel:
                guidance = "Cook until soft, then mash or flatten the kernels or peas so they do not remain small and round."
            case .pod:
                guidance = "Trim strings and seams, cook the pod until soft, and split or chop it rather than serving a firm intact pod."
            case .stalk:
                guidance = "Trim woody or stringy sections, cook until tender, and cut across the fibers."
            case .bulb:
                guidance = "Cook it until soft and use it within a moist dish rather than offering firm raw chunks or slippery layers."
            case .softFlesh:
                guidance = "Use ripe or cooked soft flesh, remove the stem and any tough peel or hard seed, and avoid small slippery cubes."
            case .root:
                guidance = "Cook until the center crushes easily, or use a specifically recommended fine-grated preparation instead of hard raw pieces."
            case .tuber:
                guidance = "Cook it fully and keep the starchy flesh moist rather than serving a dry, dense mouthful."
            case .fibrousSpecialty:
                guidance = "Use only the properly trimmed edible portion and cook it thoroughly before adapting its texture."
            }
        case .grain:
            switch grainPreparationForm(name: name) {
            case .bread:
                guidance = "Use a soft or lightly toasted piece that tears easily, and avoid dense gummy balls or hard crusts."
            case .pasta:
                guidance = "Cook it past firm until tender, shorten long strands or modify large shapes, and keep it moist."
            case .puffedCereal:
                guidance = "Use only a product that dissolves readily, testing the exact puff before serving and avoiding dry handfuls."
            case .softGrain:
                guidance = "Cook it with enough liquid to make a moist mash or scoopable cereal without hard kernels or sticky clumps."
            }
        case .beanAndPlantProtein:
            switch plantProteinPreparationForm(name: name) {
            case .wholePulse:
                guidance = "Cook until the center mashes easily, then mash or flatten whole beans and peas for an early eater."
            case .softTofu:
                guidance = "Offer the soft curd by spoon or in soft scoops, checking that it has no rubbery surface or firm add-ins."
            case .firmTofu:
                guidance = "Use moist strips, crumbles, or soft pieces that compress and break apart easily."
            case .fermentedCake:
                guidance = "Cook as needed and serve it moist, thin, crumbled, or in a tender patty rather than as a tough or elastic chunk."
            case .spread:
                guidance = "Thin the spread when it is dense and serve it by spoon or in a thin layer, checking its sodium and allergen ingredients."
            case .seasoning:
                guidance = "Use only a small amount mixed through a larger dish because this is a concentrated, often salty seasoning rather than a stand-alone serving."
            case .sprout:
                guidance = "Cook sprouts thoroughly, then chop across their length and mix them into moist food."
            }
        case .meat:
            switch meatPreparationForm(name: name) {
            case .organ:
                guidance = "Cook it fully, keep it moist, and remove membrane, tough ducts, or connective tissue before mashing or mincing it."
            case .ground:
                guidance = "Cook it fully and keep crumbles, a patty, or a meatball tender and moist rather than dry or rubbery."
            case .boneIn:
                guidance = "Cook it fully until tender, take all meat off the bone, and remove loose bone, cartilage, gristle, and tough skin before serving."
            case .tenderCut:
                guidance = "Cook it fully with a moisture-retaining method and use a boneless portion. If the cut was cooked on the bone, take the meat off and inspect it again; remove any gristle or tough connective tissue, then shred across the grain or mince it with sauce."
            }
        case .seafood:
            switch seafoodPreparationForm(name: name) {
            case .crustacean:
                guidance = "Cook it fully, remove shell and tail, and mince or flatten the flesh rather than serving a whole curled piece."
            case .bivalve:
                guidance = "Cook it fully, remove every shell fragment, and mince the chewy flesh finely into moist food."
            case .cephalopod:
                guidance = "Cook until tender and mince very finely; rings, tentacles, and rubbery chunks are not appropriate early forms."
            case .smallFish, .fillet:
                guidance = "Choose the species using current fish advice, cook it fully, check the portion carefully for bones, and serve moist flakes."
            }
        case .dairy:
            if case .smoothDairy = scoopablePreparationKind(name: name, category: category) {
                guidance = "Choose a pasteurized, unsweetened product and offer it by spoon or mixed into food."
            } else {
                guidance = "Choose pasteurized cheese and adapt its actual firmness by crumbling, grating, melting, or slicing it thinly rather than serving a firm cube."
            }
        case .egg:
            guidance = key == "egg yolk"
                ? "Cook the yolk fully, then mash it with moisture so it is soft rather than dry and crumbly."
                : "Cook the egg fully while keeping it soft, then mash it or cut it into a shape suited to the child's skills."
        case .nutAndSeed, .herbAndFlavor, .preparedFood:
            guidance = "Follow the food-specific preparation and safety guidance below."
        }
        return lead + guidance
    }

    private static func ingredientBackground(
        name: String,
        category: SolidsFoodCategory
    ) -> String {
        let key = normalized(name)
        if ["cactus pear", "prickly pear"].contains(key) {
            return "\(name) is the fruit of a cactus. The ripe interior can be soft and juicy, but the outer skin may carry obvious spines and tiny hair-like glochids that must be completely removed before the fruit enters the child's food-preparation area."
        }
        switch category {
        case .fruit:
            switch fruitPreparationForm(name: name) {
            case .sauce:
                return "\(name) is cooked fruit processed into a spoonable sauce. The ingredient list and thickness vary by product, so an unsweetened, scoopable version is more useful than a squeeze pouch for learning to self-feed."
            case .smallRoundBerry:
                return "\(name) is a small berry whose skin and firmness vary with ripeness and variety. Its intact round form matters more for serving safety than its small overall size."
            case .aggregateBerry:
                return "\(name) is a delicate berry made of clustered sections. Ripe fruit usually collapses easily, while an underripe berry or firm core needs additional flattening or cutting."
            case .roundOrSlipperyFruit:
                return "\(name) has a round or slippery edible portion and may also contain a pit, large seed, or tough skin. Those features must be removed or changed before it is served."
            case .citrus:
                return "\(name) is a citrus fruit with juicy pulp enclosed by peel, pith, and membrane. Seeds and tough membrane are the parts that most often need removal for a new eater."
            case .firmFruit:
                return "\(name) is a firm-fleshed fruit with a core or seeds. Raw pieces can stay hard and break into airway-sized chunks, while cooking or fine grating changes that texture."
            case .stoneFruit:
                return "\(name) is a fleshy fruit with a large central pit. Ripeness strongly affects texture: ripe flesh can be soft and slippery, while underripe flesh can remain too firm."
            case .melon:
                return "\(name) is a high-water fruit with a rind and, depending on variety, seeds. The flesh can be slippery, so remove the rind and use broad soft pieces or appropriately cut portions."
            case .softFruit:
                return "\(name) is a soft-fleshed fruit when fully ripe, but its skin, core, and seeds vary by variety. Check the actual piece rather than assuming all ripe-looking fruit has the same texture."
            case .seededPulp:
                return "\(name) is eaten mainly for the soft pulp inside its rind. It is a spoon food rather than a food that naturally progresses to slices, and any large or unexpectedly hard seed should be removed."
            case .arils:
                return "\(name) is eaten as juice-filled arils separated from a tough rind and membrane. Intact arils can remain firm and round, so crushing or flattening is part of early preparation."
            case .driedStickyFruit:
                return "\(name) is commonly sold dried, which concentrates sweetness and creates a dense, sticky texture. Softening and dispersing it through moist food is different from serving the whole dried fruit."
            case .gratedFlesh:
                return "\(name) is the firm edible flesh of a coconut. Fresh chunks and dry strips can be hard or chewy, while finely grated flesh, smooth coconut butter, and coconut milk behave differently in a meal."
            case .cookBeforeServing:
                return "\(name) is a starchy, firm, or otherwise unsuitable raw fruit that is normally cooked before eating. Thorough cooking changes both flavor and texture and is part of safe preparation."
            }
        case .vegetable:
            switch vegetablePreparationForm(name: name) {
            case .leafy:
                return "\(name) is a leafy vegetable with thin leaves and potentially fibrous stems. Cooking, chopping across fibers, and mixing it into moist food prevents a stringy or loose mouthful."
            case .flower:
                return "\(name) is an edible flower or flower head with branching florets and a denser stem. Both parts can be served when cooked until they crush easily, but loose firm florets need additional chopping."
            case .compactBud:
                return "\(name) is a compact round bud made of tightly layered leaves. Its round shape and dense center both need modification even after the outside looks cooked."
            case .squash:
                return "\(name) is a squash with edible flesh protected by skin and, in many varieties, a seed cavity. Remove hard rind and seeds and judge doneness by whether the flesh crushes easily."
            case .roundKernel:
                return "\(name) forms small round kernels or peas. Even when cooked, each piece should be mashed or flattened for early eaters so it does not retain an airway-sized shape."
            case .pod:
                return "\(name) is a pod vegetable that can contain strings, seams, or small round seeds. Cook it soft, trim fibrous parts, and split or chop it rather than serving a firm intact pod."
            case .stalk:
                return "\(name) is a stalk or stem vegetable with fibers that run lengthwise. Thorough cooking and trimming or chopping across those fibers makes it easier to manage."
            case .bulb:
                return "\(name) is an aromatic bulb or allium used to build flavor. Cooking softens its layers and mellows its intensity; large slippery layers or firm raw chunks are not useful first shapes."
            case .softFlesh:
                return "\(name) is a tender-fleshed vegetable or culinary fruit once ripe and cooked. Remove tough skin, stem, seeds, or core as needed and avoid small slippery cubes."
            case .root:
                return "\(name) is a firm root vegetable. Raw pieces can be hard, so it should be cooked until a piece crushes easily or finely grated when an appropriate raw preparation is specifically used."
            case .tuber:
                return "\(name) is a starchy underground vegetable that must be cooked before serving. Keep the cooked flesh moist because a dry, dense mouthful can be difficult to manage."
            case .fibrousSpecialty:
                return "\(name) has a specialized edible portion surrounded by fibrous, tough, or inedible material. Use only the properly trimmed, fully cooked tender portion and discard hard leaves, skin, spines, or fibers."
            }
        case .grain:
            switch grainPreparationForm(name: name) {
            case .bread:
                return "\(name) is a baked or griddled grain food whose texture depends on moisture, density, and toasting. Dense bread can become gummy, so preparation matters more than whether it is labeled soft."
            case .pasta:
                return "\(name) is a shaped grain product that becomes manageable only after thorough cooking. Size, strand length, chewiness, and moisture all affect how it should be served."
            case .puffedCereal:
                return "\(name) is an expanded dry cereal. Some puffs dissolve quickly while others remain hard, so test the exact product and avoid dry handfuls."
            case .softGrain:
                return "\(name) is a grain, pseudograin, or grain cereal generally served cooked. Water and cooking time determine whether it becomes a moist scoopable food or a dry, sticky mouthful."
            }
        case .beanAndPlantProtein:
            switch plantProteinPreparationForm(name: name) {
            case .wholePulse:
                return "\(name) is a pulse or legume that is served cooked. Its skin and round shape can persist after cooking, so softness plus mashing or flattening are important for early eaters."
            case .softTofu:
                return "\(name) is a soft soybean curd with a custard-like texture. It is naturally scoopable and should not be described or served like a firm strip of tofu."
            case .firmTofu:
                return "\(name) is a firmer soybean curd that can be cut into graspable strips, crumbled, or cooked into soft pieces. Firmness varies substantially by brand and style."
            case .fermentedCake:
                return "\(name) is a dense plant-protein food formed into a cake, patty, or elastic mass. It needs cooking and moist, thin, or crumbled preparation so it does not become tough or rubbery."
            case .spread:
                return "\(name) is a mashed or blended plant-protein spread. It remains a spoonable or thinly spread food as skills grow rather than progressing to chunks of the spread itself."
            case .seasoning:
                return "\(name) is a concentrated fermented seasoning rather than a stand-alone protein portion. Its sodium level makes a small amount mixed through a larger dish the practical serving form."
            case .sprout:
                return "\(name) is a sprouted legume with a crisp stem and small seed head. It should be cooked thoroughly for a young child, then chopped to remove stringy, slippery lengths."
            }
        case .meat:
            switch meatPreparationForm(name: name) {
            case .organ:
                return "\(name) is organ meat with a soft texture when cooked gently and a concentrated micronutrient profile. Use modest portions and avoid drying it into firm, crumbly chunks."
            case .ground:
                return "\(name) is minced meat or a ground-meat preparation. Moist patties, crumbles, or sauce-bound pieces are easier to manage than dry, rubbery balls."
            case .boneIn:
                return "\(name) is a bone-in cut. The meat may become tender with slow cooking, but every loose bone, cartilage fragment, tough skin, and piece of gristle must be removed before serving."
            case .tenderCut:
                return "\(name) is a muscle-meat cut whose tenderness depends on cooking method and direction of the grain. Use a boneless portion for the child's serving, and choose moist shredding or mincing rather than dry cubes."
            }
        case .seafood:
            switch seafoodPreparationForm(name: name) {
            case .crustacean:
                return "\(name) is a crustacean shellfish with firm curved flesh inside a shell. Remove all shell and tail, cook fully, and mince or flatten the flesh because a whole curled piece can be rubbery."
            case .bivalve:
                return "\(name) is a mollusk with chewy flesh enclosed by a shell. Use only fully cooked flesh, discard every shell fragment, and mince finely into moist food."
            case .cephalopod:
                return "\(name) is a cephalopod whose flesh can become rubbery. Cook it fully until tender and mince very finely rather than offering rings, tentacles, or chewy chunks."
            case .smallFish:
                return "\(name) is a small oily fish often sold whole, canned, cured, or packed in oil. Product sodium varies, and bones still require careful checking even when some small bones soften during processing."
            case .fillet:
                return "\(name) is a finfish generally served as a fillet. Species-specific mercury guidance matters, and every serving needs a careful bone check before the cooked flesh is flaked."
            }
        case .dairy:
            if normalized(name).contains("in food") {
                return "\(name) is dairy used as a recipe ingredient rather than offered as an infant's primary beverage. Pasteurization, the larger dish's texture, and the distinction between food and a main milk drink are central to serving it."
            }
            if case .smoothDairy = scoopablePreparationKind(name: name, category: category) {
                return "\(name) is a cultured, spoonable, or pourable dairy food. Choose a pasteurized product and keep it scoopable or mixed into food rather than inventing a sliced progression."
            }
            return "\(name) is a cheese whose moisture, salt, and firmness vary by style. Pasteurization and the actual texture determine whether it should be crumbled, grated, melted, or offered in a paper-thin slice."
        case .egg:
            return normalized(name) == "egg yolk"
                ? "\(name) is the yolk portion of an egg. Egg is a major allergen, and the yolk should be cooked fully and moistened rather than served as a dry, crumbly ball."
                : "\(name) is an egg or cooked egg preparation. Egg is a major allergen, and the finished food should be cooked through while staying soft rather than rubbery."
        case .nutAndSeed:
            if normalized(name).contains("butter") || normalized(name) == "tahini" {
                return "\(name) is a concentrated nut or seed paste. It is introduced thinned into food or spread very thinly; a thick spoonful remains sticky regardless of age."
            }
            if normalized(name).contains("ground") {
                return "\(name) is already milled, but it can still form a dry mouthful. Mix the fine meal thoroughly into moist food and verify that no hard pieces remain."
            }
            return "\(name) is a whole nut or seed in its retail form. For babies and young toddlers it must be transformed into a finely ground, fully softened, or safely thinned preparation rather than served whole."
        case .herbAndFlavor:
            switch flavorPreparationForm(name: name) {
            case .bayLeaf:
                return "\(name) is used to infuse a dish and is removed before eating. The stiff leaf itself is not an edible serving shape for a child."
            case .fibrousAromatic:
                return "\(name) is a fibrous aromatic used for flavor. Finely grate, pound, or infuse it and remove woody strands or chunks before serving."
            case .leafyHerb:
                return "\(name) is a leafy culinary herb. A small amount adds aroma and flavor, while chopping and removing firm stems prevents a loose or stringy mouthful."
            case .groundSpice:
                return "\(name) is used as a spice or seasoning, not as a stand-alone portion. Use a small culinary amount in ground form and keep whole hard pieces and loose powder out of the serving."
            }
        case .preparedFood:
            switch preparedFoodPreparationForm(name: name) {
            case .soupOrStew:
                return "\(name) is a mixed spoon dish. Its safety depends on every component being fully cooked and modified, plus a thick enough texture and safe serving temperature."
            case .patty:
                return "\(name) is a formed cake, fritter, pancake, or patty. A soft center and tender exterior are more useful than a crisp crust, and each binding ingredient must be checked for allergens."
            case .spoonable:
                return "\(name) is a scoopable prepared food. It should remain moist and spoonable as skills develop; toppings and mix-ins need their own shape and allergen review."
            case .handheld:
                return "\(name) is a handheld mixed food. Separate or soften fillings, avoid tough or gummy wrappers, and cut the assembled food to match current biting skills."
            case .pastaOrRice:
                return "\(name) is a grain-based mixed dish. Cook the grain past firm, keep the mixture moist, and modify every meat, vegetable, cheese, or sauce component separately."
            case .mixedDish:
                return "\(name) is a composed family dish whose recipe can change substantially. The ingredient list, cooking method, sodium, allergens, and hardest component determine how it should be adapted."
            case .sweetener:
                return "\(name) is a sweetener, not a food needed for infant nutrition. It is specifically excluded before 12 months and should remain a small optional ingredient afterward."
            }
        }
    }

    private static func ingredientHandling(
        name: String,
        category: SolidsFoodCategory
    ) -> (choosing: String, storage: String) {
        let key = normalized(name)
        switch category {
        case .fruit:
            if ["cactus pear", "prickly pear"].contains(key) {
                return (
                    "Choose commercially de-spined \(name.lowercased()) when possible. The fruit should be intact and free of mold, and every visible or hair-like spine must be treated as still present until the peel is removed safely.",
                    "Store the intact fruit according to normal produce guidance without letting it contact ready-to-eat food. Refrigerate peeled or cut flesh promptly and discard the child's served portion."
                )
            }
            switch fruitPreparationForm(name: name) {
            case .sauce:
                return (
                    "Choose unsweetened \(name.lowercased()) with a short ingredient list and no honey for a child under 12 months. A jar or cup makes thickness easier to assess than a pouch.",
                    "Refrigerate opened \(name.lowercased()) promptly, follow the product's use-after-opening directions, and portion it into a clean bowl rather than feeding from and saving the same container."
                )
            case .driedStickyFruit:
                return (
                    "Choose pitted \(name.lowercased()) without a hard, sugar-crusted exterior. Check for sulfites or added sugar when buying packaged dried fruit.",
                    "Keep dried \(name.lowercased()) sealed and dry. Refrigerate rehydrated or cooked portions promptly and discard the child's served leftovers."
                )
            case .smallRoundBerry, .aggregateBerry:
                return (
                    "Choose \(name.lowercased()) without mold or leaking packages. Fresh or frozen fruit is usable; thaw or cook firm frozen berries and assess every berry's softness before serving.",
                    "Refrigerate fresh \(name.lowercased()), wash shortly before use, and refrigerate cut, thawed, or cooked portions promptly."
                )
            case .citrus:
                return (
                    "Choose \(name.lowercased()) that feels heavy for its size and has no mold or deep soft spots. Seedless does not guarantee every segment is seed-free, so inspect after peeling.",
                    "Whole \(name.lowercased()) can be kept according to normal citrus storage; refrigerate peeled segments and discard pieces left in the child's bowl."
                )
            default:
                return (
                    "Choose \(name.lowercased()) without mold, leaking damage, or major bruising. Ripeness and firmness are safety variables, so select fruit that can reach the texture in the preparation guide and wash it before cutting.",
                    "Store whole \(name.lowercased()) according to its normal room-temperature or refrigeration needs. Refrigerate cut, cooked, or thawed portions promptly and discard food left in the child's bowl."
                )
            }
        case .vegetable:
            let form = vegetablePreparationForm(name: name)
            if form == .leafy {
                return (
                    "Choose crisp \(name.lowercased()) without slime or yellowed, damaged leaves. Wash between leaves and trim thick or woody stems before cooking.",
                    "Refrigerate fresh \(name.lowercased()) dry and loosely covered. Chill cooked portions promptly and use a clean utensil when taking out the child's portion."
                )
            }
            if form == .tuber || form == .root {
                return (
                    "Choose firm \(name.lowercased()) without mold, deep cuts, or extensive soft spots. Peel when the skin is tough or damaged and cook the center until fully tender.",
                    "Store whole \(name.lowercased()) according to the vegetable's normal cool, dry, or refrigerated needs. Refrigerate cooked portions promptly; do not leave a foil-wrapped baked vegetable at room temperature."
                )
            }
            return (
                "Choose \(name.lowercased()) without mold, slime, or major damage. Fresh, frozen, or no-salt-added canned forms can work when they can be prepared to the texture described below.",
                "Refrigerate fresh, cut, or cooked \(name.lowercased()) as appropriate. Chill leftovers promptly and discard the portion already served to the child."
            )
        case .grain:
            let isInfantCereal = key.contains("infant")
            let selection: String
            switch grainPreparationForm(name: name) {
            case .bread:
                selection = "Choose plain \(name.lowercased()) with modest sodium that tears easily. Review allergens and avoid a dense loaf, hard crust, whole nuts, or hard seeds."
            case .pasta:
                selection = "Choose plain \(name.lowercased()) with a clear allergen label and a shape that can be cooked very tender, shortened, or otherwise adapted."
            case .puffedCereal:
                selection = "Choose an unsweetened, lower-sodium \(name.lowercased()), check allergens and hard clusters, and test that the exact puff dissolves readily."
            case .softGrain:
                selection = isInfantCereal
                    ? "Choose an iron-fortified infant cereal without added sugar. Rotate grain types rather than relying only on rice cereal, and check the label for milk, soy, or wheat ingredients."
                    : "Choose plain \(name.lowercased()) with little or no added sugar and review its allergen label. Sort whole dry grains for debris when applicable."
            }
            return (
                selection,
                "Keep dry \(name.lowercased()) sealed and dry. Refrigerate cooked portions promptly, cool rice and other grains without leaving them at room temperature, and reheat only the portion being served."
            )
        case .beanAndPlantProtein:
            let form = plantProteinPreparationForm(name: name)
            switch form {
            case .wholePulse:
                return (
                    "Choose dried, frozen, or no-salt-added \(name.lowercased()) when practical. Drain and rinse canned versions, remove debris from dried pulses, and cook until the center mashes easily.",
                    "Refrigerate cooked or opened \(name.lowercased()) promptly. Store dry pulses sealed and dry, and discard any portion that has contacted the child's mouth or spoon."
                )
            case .sprout:
                return (
                    "Choose refrigerated \(name.lowercased()) from intact packaging by its use-by date. Young children should not eat raw or lightly cooked sprouts, and washing does not remove that risk.",
                    "Keep \(name.lowercased()) refrigerated and separate from ready-to-eat food, cook thoroughly until steaming hot, and discard served leftovers."
                )
            case .softTofu, .firmTofu:
                return (
                    "Choose plain refrigerated \(name.lowercased()) from an intact package and check sodium plus the soy allergen label. Match the stated firmness to the preparation guide.",
                    "Keep unopened and opened \(name.lowercased()) refrigerated according to the package. Use a clean utensil, chill cooked portions promptly, and discard the child's served portion."
                )
            case .fermentedCake:
                return (
                    "Choose plain \(name.lowercased()) with modest sodium and check soy, wheat, or other allergen ingredients. Avoid a product that can only be prepared with a hard crust or rubbery texture.",
                    "Follow package refrigeration directions, cook the portion fully when required, chill leftovers promptly, and discard the child's served portion."
                )
            case .spread:
                return (
                    "Choose \(name.lowercased()) with modest sodium and review the complete allergen list. Check that it can be thinned when dense and contains no hard toppings or pieces.",
                    "Keep \(name.lowercased()) refrigerated after opening as directed. Portion with a clean utensil and discard thinned spread or food left in the child's bowl."
                )
            case .seasoning:
                return (
                    "Choose pasteurized or commercially packaged \(name.lowercased()) with a clear allergen label and compare sodium, since only a small amount belongs in a larger dish.",
                    "Follow package refrigeration directions after opening, use a clean utensil, and do not save food from the child's bowl."
                )
            }
        case .meat:
            let selectionDetail: String
            switch meatPreparationForm(name: name) {
            case .organ:
                selectionDetail = "Choose a small fresh or properly frozen portion and plan to trim membrane, tough ducts, or connective tissue after cooking."
            case .ground:
                selectionDetail = "For ground or formed products, check sodium, seasoning, and allergen ingredients and choose a form that can stay tender and moist."
            case .boneIn:
                selectionDetail = "Choose a cut that can be cooked tender and plan to remove all meat from the bone before the child's portion is prepared."
            case .tenderCut:
                selectionDetail = "Choose an unseasoned cut that can be cooked tender. Use a boneless portion for the child, or plan to remove the cooked meat from the bone and inspect it again before serving."
            }
            return (
                "Choose fresh or properly frozen \(name.lowercased()) from intact packaging. Unseasoned products make sodium and allergens easier to control. \(selectionDetail)",
                "Keep raw \(name.lowercased()) cold and separate from ready-to-eat food. Cook to a safe internal temperature, refrigerate leftovers promptly, and never return the child's served portion to the main container."
            )
        case .seafood:
            let finalCheck: String
            switch seafoodPreparationForm(name: name) {
            case .crustacean:
                finalCheck = "Remove the full shell and tail after cooking and check for fragments."
            case .bivalve:
                finalCheck = "Use only fully cooked flesh and inspect it for shell fragments."
            case .cephalopod:
                finalCheck = "Use only fully cooked tender flesh and discard rubbery or inedible sections."
            case .smallFish, .fillet:
                finalCheck = "Inspect the cooked portion carefully for bones."
            }
            return (
                "Choose fresh or properly frozen \(name.lowercased()) from a reliable source and check current FDA/EPA mercury advice for the exact species. Avoid leaking packages or a strong off odor and inspect processed seafood for sodium and added allergens.",
                "Keep raw \(name.lowercased()) cold and separate, cook it fully, and refrigerate leftovers promptly. \(finalCheck) Discard served leftovers."
            )
        case .dairy:
            let selection: String
            if key.contains("in food") {
                selection = "Choose pasteurized \(name.lowercased()) and review the milk-allergen label. Use it as a recipe ingredient rather than the main milk drink before 12 months."
            } else if scoopablePreparationKind(name: name, category: category) == .smoothDairy {
                selection = "Choose pasteurized \(name.lowercased()), preferably unsweetened, and review sodium, added sugar, and any mix-ins or hard toppings."
            } else {
                selection = "Choose pasteurized \(name.lowercased()), review sodium and ingredients, and assess its actual moisture and firmness before deciding whether to crumble, grate, melt, or slice it thinly."
            }
            return (
                selection,
                "Keep \(name.lowercased()) refrigerated, follow its package date and use-after-opening directions, and discard portions that have been in the child's bowl."
            )
        case .egg:
            return (
                "Choose clean, uncracked eggs or a pasteurized egg product for \(name.lowercased()). Prepared versions may add milk, wheat, soy, or other allergens, so check the full recipe.",
                "Keep eggs refrigerated, cook \(name.lowercased()) until safely done, chill cooked egg promptly, and discard the child's served leftovers."
            )
        case .nutAndSeed:
            let selection: String
            if key.contains("butter") || key == "tahini" {
                selection = "Choose a smooth, unsalted, unsweetened spread without crunchy pieces and confirm the exact nut or seed allergen on the label."
            } else if key.contains("ground") {
                selection = "Choose a finely milled, unsalted product and inspect it for coarse fragments or hard pieces before mixing it into moist food."
            } else {
                selection = "Choose an unsalted product that will be finely ground or otherwise prepared in the food-specific safe form; whole or chopped hard pieces are not served to a young child."
            }
            return (
                selection,
                "Seal \(name.lowercased()) tightly and follow the package's room-temperature or refrigeration directions. Discard any thinned or mixed portion left in the child's bowl."
            )
        case .herbAndFlavor:
            let selection: String
            switch flavorPreparationForm(name: name) {
            case .bayLeaf:
                selection = "Choose a whole culinary bay leaf for infusion and count how many go into the dish so every stiff leaf can be removed before serving."
            case .fibrousAromatic:
                selection = "Choose a fresh, firm aromatic without mold or slime and use only the section that can be finely grated, pounded, or infused."
            case .leafyHerb:
                selection = "Choose fresh leaves without slime or major wilting, wash them, and remove firm stems before finely chopping."
            case .groundSpice:
                selection = "Choose a single culinary spice without added salt, sugar, stimulant ingredients, or whole hard decorative pieces."
            }
            return (
                selection,
                "Keep dried \(name.lowercased()) sealed, cool, and dry. Refrigerate fresh herbs or cut aromatics as appropriate and discard prepared food left in the child's bowl."
            )
        case .preparedFood:
            return (
                "Review every ingredient in \(name.lowercased()) and its allergen label. Prefer modest sodium and added sugar, then identify the hardest, roundest, stickiest, or chewiest component and modify it separately.",
                "Follow the recipe or package directions for \(name.lowercased()), keep perishable ingredients cold, refrigerate leftovers promptly, and discard the child's served portion."
            )
        }
    }

    private static func ingredientQuestions(
        name: String,
        category: SolidsFoodCategory,
        firstPreparation: String?
    ) -> [SolidsFoodQuestion] {
        let firstStage = firstPreparation
            ?? chokingGuidance(name: name, category: category)
        let progression = SolidsFoodQuestion(
            question: "What is the safest first preparation of \(name.lowercased())?",
            answer: firstStage
        )
        let practical: SolidsFoodQuestion
        switch category {
        case .fruit:
            if ["cactus pear", "prickly pear"].contains(normalized(name)) {
                practical = SolidsFoodQuestion(
                    question: "How do I prepare \(name.lowercased()) without leaving spines?",
                    answer: "Choose commercially de-spined fruit when possible. Otherwise protect your hands, remove every visible spine and hair-like glochid, wash the fruit, cut off the ends, peel away the whole outer skin, and clean the work area before preparing the soft flesh."
                )
            } else {
                switch fruitPreparationForm(name: name) {
                case .sauce:
                    practical = SolidsFoodQuestion(
                        question: "What should I check when buying \(name.lowercased())?",
                        answer: "Choose unsweetened \(name.lowercased()) with a short ingredient list and no honey before 12 months. Serve it from a bowl or preloaded spoon so its thickness can be assessed; a squeeze pouch hides the texture and does not build the same spoon skills."
                    )
                case .driedStickyFruit:
                    practical = SolidsFoodQuestion(
                        question: "Can I serve \(name.lowercased()) straight from the package?",
                        answer: "Not as a whole dense, sticky dried fruit for a baby or young toddler. Confirm the pit is removed, soften it with liquid, and mash or mince it into moist food. Check packaged fruit for added sugar and sulfites."
                    )
                case .seededPulp:
                    practical = SolidsFoodQuestion(
                        question: "How should I serve the pulp from \(name.lowercased())?",
                        answer: "Scoop the pulp away from the rind and offer it by spoon or mixed into another soft food. Remove any large or unexpectedly hard seed; do not turn it into juice for an infant."
                    )
                case .gratedFlesh:
                    practical = SolidsFoodQuestion(
                        question: "Which forms of \(name.lowercased()) work for a young child?",
                        answer: "Use unsweetened finely grated flesh mixed into moist food, smooth coconut butter in a thin layer, or coconut milk as a recipe ingredient. Hard fresh chunks and dry chewy strips are not appropriate early forms."
                    )
                default:
                    practical = SolidsFoodQuestion(
                        question: "Can I use frozen or canned \(name.lowercased())?",
                        answer: "Yes, when the product has no honey before 12 months, little or no added sugar, and can be prepared to the same food-specific shape and texture. Thaw or cook firm frozen fruit and drain canned fruit as needed. Do not offer fruit juice before 12 months."
                    )
                }
            }
        case .vegetable:
            practical = SolidsFoodQuestion(
                question: "Can \(name.lowercased()) be served raw?",
                answer: vegetableRawAnswer(name: name)
            )
        case .grain:
            let texture: String
            switch grainPreparationForm(name: name) {
            case .bread:
                texture = "It should tear easily without forming a dense gummy ball. Light toasting can reduce gumminess, but avoid hard crusts, whole seeds, nut pieces, and thick sticky toppings."
            case .pasta:
                texture = "Cook it past al dente until it squashes easily. Shorten long strands, cut or mash large shapes, and add moisture if the surface becomes sticky or dry."
            case .puffedCereal:
                texture = "Test the exact product with saliva or warm water: it should dissolve readily rather than staying hard. Offer a few pieces at a time while the child is seated, not a dry handful."
            case .softGrain:
                texture = "Cook it until no hard center remains, then keep it moist and separate dense clumps. Whole kernels need mashing or another modification until the child can manage them reliably."
            }
            practical = SolidsFoodQuestion(
                question: "How should \(name.lowercased()) feel before serving?",
                answer: "\(texture) Check the package for wheat and other major allergens."
            )
        case .beanAndPlantProtein:
            let packagedGuidance: String
            switch plantProteinPreparationForm(name: name) {
            case .wholePulse:
                packagedGuidance = "Canned or frozen versions can work. Choose no-salt-added or lower-sodium products when practical, drain and rinse canned pulses, cook until the center mashes easily, and flatten whole beans or peas."
            case .softTofu, .firmTofu:
                packagedGuidance = "Choose plain tofu, check the soy allergen label and sodium, and follow refrigeration directions. Adapt the actual firmness: scoop soft tofu, or use moist strips, crumbles, or pieces of firmer tofu."
            case .fermentedCake:
                packagedGuidance = "Review sodium and the complete allergen list, cook the product as directed, and keep the served form moist and easy to break apart rather than rubbery or crusted."
            case .spread:
                packagedGuidance = "Review sodium and all allergens, especially sesame in hummus. Thin a dense spread and serve it by spoon or in a thin layer rather than as a sticky scoop."
            case .seasoning:
                packagedGuidance = "Use only a small amount mixed through a larger dish. Check sodium and soy or other allergens; this concentrated seasoning is not a stand-alone protein serving."
            case .sprout:
                packagedGuidance = "Do not rely on rinsing to make raw sprouts safe. Cook them thoroughly until steaming hot, cool them, then chop across the stems before serving."
            }
            practical = SolidsFoodQuestion(
                question: "What should I check when preparing \(name.lowercased())?",
                answer: packagedGuidance
            )
        case .meat:
            let tenderness: String
            switch meatPreparationForm(name: name) {
            case .organ:
                tenderness = "Cook it fully but gently so it stays soft, remove membrane or tough ducts, and mash or mince it with moisture. Keep portions modest because liver is concentrated in preformed vitamin A."
            case .ground:
                tenderness = "Cook it fully and keep patties, meatballs, or crumbles moist. Break apart any rubbery or browned crust and verify that no hard fragment remains."
            case .boneIn:
                tenderness = "Cook until the meat is tender, take it completely off the bone, then check again for loose bone, cartilage, gristle, and tough skin before shredding or mincing."
            case .tenderCut:
                tenderness = "Cook it fully with a moisture-retaining method and use a boneless portion. If the cut was cooked on the bone, take the meat off and inspect it again; remove any gristle or tough connective tissue, then shred across the grain or mince it with sauce rather than serving dry cubes."
            }
            practical = SolidsFoodQuestion(
                question: "How do I keep \(name.lowercased()) tender enough?",
                answer: tenderness
            )
        case .seafood:
            let finalCheck: String
            switch seafoodPreparationForm(name: name) {
            case .crustacean:
                finalCheck = "Cook it fully, remove the entire shell and tail, then mince or flatten the curved flesh and discard rubbery sections."
            case .bivalve:
                finalCheck = "Use only fully cooked flesh, remove every shell fragment, and mince the chewy meat finely into moist food."
            case .cephalopod:
                finalCheck = "Cook it fully until tender and mince very finely. Do not offer rings, tentacles, or pieces that remain rubbery."
            case .smallFish:
                finalCheck = "Check the exact product for sodium and the current fish advice. Cook as needed and inspect every portion for bones, even when processing has softened some small bones."
            case .fillet:
                finalCheck = "Confirm the exact species against current fish advice, cook it fully, and inspect the cooked flesh carefully for fine bones before serving moist flakes."
            }
            practical = SolidsFoodQuestion(
                question: "What should I check before serving \(name.lowercased())?",
                answer: finalCheck
            )
        case .dairy:
            let dairyUse: String
            if normalized(name).contains("in food") {
                dairyUse = "Use pasteurized \(name.lowercased()) only as an ingredient before 12 months; it should not replace breast milk or infant formula as the main drink. Check that the complete dish has an appropriate texture."
            } else if case .smoothDairy = scoopablePreparationKind(name: name, category: category) {
                dairyUse = "Choose a pasteurized, unsweetened product and offer it by spoon or mixed into food. It is part of complementary feeding, not a replacement for breast milk or infant formula before 12 months."
            } else {
                dairyUse = "Use pasteurized cheese as food, adapting its firmness by crumbling, grating, melting, or using a very thin slice. Do not offer firm cheese cubes, and do not use cheese to replace breast milk or formula."
            }
            practical = SolidsFoodQuestion(
                question: "How does \(name.lowercased()) fit into infant feeding?",
                answer: dairyUse
            )
        case .egg:
            practical = SolidsFoodQuestion(
                question: "Does \(name.lowercased()) need to be fully cooked?",
                answer: normalized(name) == "egg yolk"
                    ? "Yes. Cook the yolk until safely done, then mash it with moisture so it is not dry or crumbly. Egg is a major allergen even when only the yolk is being served."
                    : "Yes. Cook the egg until safely done while keeping it soft rather than rubbery. Egg is a major allergen, so start with a small amount in an appropriate form."
            )
        case .nutAndSeed:
            let nutGuidance: String
            if normalized(name).contains("butter") || normalized(name) == "tahini" {
                nutGuidance = "Choose a smooth product, thin it into familiar moist food or spread it in a very thin layer, and never offer a thick spoonful. Confirm the exact nut or seed allergen on the label."
            } else if normalized(name).contains("ground") {
                nutGuidance = "Mix the fine meal thoroughly into moist food and check that no hard piece or dry pocket remains. Confirm the exact nut allergen on the label."
            } else {
                nutGuidance = "Do not serve it whole or chopped to a baby or young toddler. Grind it to a fine meal and mix it into moist food, fully soften an appropriate seed, or use a smooth well-thinned butter."
            }
            practical = SolidsFoodQuestion(
                question: "What is the safe form of \(name.lowercased())?",
                answer: nutGuidance
            )
        case .herbAndFlavor:
            let flavorGuidance: String
            switch flavorPreparationForm(name: name) {
            case .bayLeaf:
                flavorGuidance = "Use the leaf to infuse a dish, then remove it before serving. The stiff leaf is not an edible portion."
            case .fibrousAromatic:
                flavorGuidance = "Use a small amount finely grated, pounded, or infused into moist food, removing woody strands or infusion pieces."
            case .leafyHerb:
                flavorGuidance = "Finely chop a small amount, remove firm stems, and mix it through moist food so it does not form a loose leafy clump."
            case .groundSpice:
                flavorGuidance = "Use a small pinch distributed through moist food. Do not offer loose powder or whole hard spice pieces, and check blends for salt and allergens."
            }
            practical = SolidsFoodQuestion(
                question: "How much \(name.lowercased()) should I use?",
                answer: flavorGuidance
            )
        case .preparedFood:
            let dishGuidance: String
            switch preparedFoodPreparationForm(name: name) {
            case .soupOrStew:
                dishGuidance = "Cook every component fully, remove any inedible or tough part actually present, and make the broth-and-solids mixture thick enough to stay together on a spoon. Check sodium and allergens."
            case .patty:
                dishGuidance = "Cook the center fully while keeping the patty tender, avoid a hard crust, and verify every binder and topping for major allergens."
            case .spoonable:
                dishGuidance = "Keep it thick enough to stay on a spoon, modify every topping or mix-in separately, and check the complete recipe for allergens, honey, added sugar, and sodium."
            case .handheld:
                dishGuidance = "Soften or separate the fillings, avoid tough or gummy wrappers, and cut the assembled food for current biting skills. Check every ingredient for allergens."
            case .pastaOrRice:
                dishGuidance = "Cook the grain until soft, keep the dish moist, and modify each meat, vegetable, or cheese component separately. Check sodium and major allergens in the complete recipe."
            case .mixedDish:
                dishGuidance = "Verify every ingredient and allergen, cook each component safely, and adapt the firmest, roundest, or stickiest component rather than relying on the dish's name."
            case .sweetener:
                dishGuidance = "Do not offer honey before 12 months. After the first birthday, use only a small optional amount mixed into food."
            }
            practical = SolidsFoodQuestion(
                question: "What makes \(name.lowercased()) appropriate for a baby?",
                answer: dishGuidance
            )
        }
        return [progression, practical]
    }

    fileprivate enum VegetablePreparationForm: Equatable {
        case leafy
        case flower
        case compactBud
        case squash
        case roundKernel
        case pod
        case stalk
        case bulb
        case softFlesh
        case root
        case tuber
        case fibrousSpecialty
    }

    fileprivate static func vegetablePreparationForm(name: String) -> VegetablePreparationForm {
        let key = normalized(name)
        if ["arugula", "beet greens", "bok choy", "cabbage", "collard greens", "endive", "green cabbage", "kale", "lettuce", "mustard greens", "napa cabbage", "pea shoot", "purple cabbage", "radicchio", "savoy cabbage", "spinach", "swiss chard", "turnip greens", "watercress"].contains(key) { return .leafy }
        if ["broccoli", "broccoli rabe", "cauliflower"].contains(key) { return .flower }
        if key == "brussels sprouts" { return .compactBud }
        if key.contains("squash") || ["pumpkin", "winter melon"].contains(key) { return .squash }
        if ["corn", "pea", "green pea"].contains(key) { return .roundKernel }
        if ["french bean", "green bean", "okra", "snap pea", "wax bean"].contains(key) { return .pod }
        if ["asparagus", "celery", "fennel bulb", "green onion", "kohlrabi", "leek", "scallion"].contains(key) { return .stalk }
        if ["garlic", "onion", "red onion", "shallot"].contains(key) { return .bulb }
        if ["bell pepper", "bitter melon", "chayote", "cucumber", "eggplant", "red bell pepper", "tomatillo", "tomato", "yellow squash", "zucchini"].contains(key) { return .softFlesh }
        if ["cassava", "malanga", "potato", "sweet potato", "taro", "yam", "yucca root"].contains(key) { return .tuber }
        if ["artichoke", "bamboo shoot", "cactus pad", "edible fern", "fiddlehead fern", "hearts of palm", "lotus root", "nopales", "water chestnut"].contains(key) { return .fibrousSpecialty }
        return .root
    }

    fileprivate enum PlantProteinPreparationForm: Equatable {
        case wholePulse
        case softTofu
        case firmTofu
        case fermentedCake
        case spread
        case seasoning
        case sprout
    }

    fileprivate static func plantProteinPreparationForm(name: String) -> PlantProteinPreparationForm {
        let key = normalized(name)
        if key == "miso" || key == "fermented tofu" { return .seasoning }
        if key.contains("sprout") { return .sprout }
        if key == "silken tofu" { return .softTofu }
        if key.contains("tofu") { return .firmTofu }
        if key.contains("hummus") || key.contains("refried") { return .spread }
        if key.contains("tempeh") || key.contains("seitan") || key.contains("patty") { return .fermentedCake }
        return .wholePulse
    }

    fileprivate enum MeatPreparationForm: Equatable {
        case organ
        case ground
        case boneIn
        case tenderCut
    }

    fileprivate static func meatPreparationForm(name: String) -> MeatPreparationForm {
        let key = normalized(name)
        if key.contains("liver") { return .organ }
        if key.contains("ground") || key.contains("meatball") { return .ground }
        if ["chop", "rib", "shank", "drumstick", "leg", "oxtail", "cornish hen", "quail"].contains(where: key.contains) { return .boneIn }
        return .tenderCut
    }

    fileprivate enum SeafoodPreparationForm: Equatable {
        case crustacean
        case bivalve
        case cephalopod
        case smallFish
        case fillet
    }

    fileprivate static func seafoodPreparationForm(name: String) -> SeafoodPreparationForm {
        let key = normalized(name)
        if ["crab", "crayfish", "langoustine", "lobster", "prawn", "shrimp"].contains(where: key.contains) { return .crustacean }
        if ["clam", "mussel", "oyster", "scallop"].contains(where: key.contains) { return .bivalve }
        if ["octopus", "squid"].contains(where: key.contains) { return .cephalopod }
        if ["anchovy", "herring", "sardine", "smelt"].contains(where: key.contains) { return .smallFish }
        return .fillet
    }

    fileprivate enum PreparedFoodPreparationForm: Equatable {
        case soupOrStew
        case patty
        case spoonable
        case handheld
        case pastaOrRice
        case mixedDish
        case sweetener
    }

    fileprivate static func preparedFoodPreparationForm(name: String) -> PreparedFoodPreparationForm {
        let key = normalized(name)
        if key == "honey" { return .sweetener }
        if ["soup", "stew", "chili", "curry", "minestrone", "mung dal"].contains(where: key.contains) { return .soupOrStew }
        if ["fritter", "cake", "pancake", "waffle", "burger", "falafel", "meat loaf"].contains(where: key.contains) { return .patty }
        if ["porridge", "pudding", "mashed", "smoothie", "parfait", "dip", "sauce"].contains(where: key.contains) { return .spoonable }
        if ["toast", "quesadilla", "taco", "french toast"].contains(where: key.contains) { return .handheld }
        if ["pasta", "rice", "risotto", "macaroni", "gnocchi"].contains(where: key.contains) { return .pastaOrRice }
        return .mixedDish
    }

    private static func vegetableRawAnswer(name: String) -> String {
        let form = vegetablePreparationForm(name: name)
        switch form {
        case .softFlesh:
            return "Some ripe \(name.lowercased()) can be served raw after its stem and any tough peel or hard seed are removed. Use a soft slice or manageable piece rather than small slippery cubes, and cook it first if the flesh does not squash easily."
        case .leafy:
            return "Cook \(name.lowercased()) for a new eater, then chop across leaves and stems and mix it into moist food. Large raw leaves and fibrous stems can be difficult to manage."
        case .tuber, .fibrousSpecialty:
            return "No. \(name) requires proper trimming and thorough cooking before it is served to a young child. Do not rely on cutting a raw piece smaller to make a hard or naturally irritating food safe."
        case .bulb:
            return "Cook \(name.lowercased()) until soft for an early eater and mix it into moist food. Firm raw chunks or large slippery layers are difficult to manage and can have an intense flavor."
        case .pod:
            return "Cook \(name.lowercased()) until soft, remove strings or tough seams, and split or chop it. A firm intact raw pod is not an appropriate early shape."
        case .roundKernel, .compactBud:
            return "Cook \(name.lowercased()) until soft, then mash, flatten, halve, or quarter it so it does not retain a small round shape."
        case .stalk:
            return "Cook \(name.lowercased()) until tender, trim woody ends and strings, and cut across the fibers. Raw fibrous sections can remain difficult to break down."
        case .flower, .squash, .root:
            return "Cook \(name.lowercased()) until the thickest part crushes easily for an early eater. Do not serve a hard raw chunk; use a specifically recommended fine-grated preparation only when the ingredient guidance calls for it."
        }
    }

    private static func preparations(
        name: String,
        category: SolidsFoodCategory,
        minimumAge: Int
    ) -> [SolidsPreparationStage] {
        if minimumAge >= 12 {
            return [
                SolidsPreparationStage(minimumAgeMonths: 12, title: "12+ months", instructions: "\(name): use only after 12 months. Mix a small amount into food rather than serving from a spoon or container."),
                SolidsPreparationStage(minimumAgeMonths: 18, title: "18+ months", instructions: "Serve a small amount of \(name.lowercased()) as part of a balanced meal and continue normal tooth-brushing routines.")
            ]
        }

        if normalized(name) == "acai" {
            return preparationStages(
                name: name,
                six: "Use unsweetened commercially prepared frozen pulp or powder rather than a fresh whole berry. Thaw pulp and offer the smooth purée on a preloaded spoon, or stir pulp or powder into porridge or plain yogurt.",
                nine: "Keep serving it as pulp or purée as eating skills develop. Offer a thicker scoopable mixture on a preloaded spoon so the child can practice self-feeding.",
                twelve: "Serve the pulp or purée in a scoopable bowl with a child-size spoon. Skip honey and hard or chewy bowl toppings, and continue to avoid whole fresh açaí berries and their large seeds.",
                eighteen: "Offer pulp or purée in a bowl, frozen into a pop, or blended into a smoothie. Choose unsweetened products and keep toppings soft and appropriately cut."
            )
        }

        if category == .fruit {
            return fruitPreparations(name: name)
        }

        if category == .preparedFood {
            return preparedFoodPreparations(name: name)
        }

        if category == .dairy && normalized(name).contains("in food") {
            return milkIngredientPreparations(name: name)
        }

        if let scoopable = scoopablePreparations(name: name, category: category) {
            return scoopable
        }

        switch category {
        case .fruit:
            return fruitPreparations(name: name)
        case .vegetable:
            return vegetablePreparations(name: name)
        case .grain:
            return grainPreparations(name: name)
        case .beanAndPlantProtein:
            return plantProteinPreparations(name: name)
        case .meat:
            return meatPreparations(name: name)
        case .seafood:
            return seafoodPreparations(name: name)
        case .dairy:
            return cheesePreparations(name: name)
        case .egg:
            return eggPreparations(name: name)
        case .nutAndSeed:
            return nutAndSeedPreparations(name: name)
        case .herbAndFlavor:
            return flavorPreparations(name: name)
        case .preparedFood:
            return preparedFoodPreparations(name: name)
        }
    }

    private static func preparationStages(
        name: String,
        six: String,
        nine: String,
        twelve: String,
        eighteen: String
    ) -> [SolidsPreparationStage] {
        [
            SolidsPreparationStage(minimumAgeMonths: 6, title: "Around 6 months", instructions: "\(name): \(six)"),
            SolidsPreparationStage(minimumAgeMonths: 9, title: "Around 9 months", instructions: "\(name): \(nine)"),
            SolidsPreparationStage(minimumAgeMonths: 12, title: "12+ months", instructions: "\(name): \(twelve)"),
            SolidsPreparationStage(minimumAgeMonths: 18, title: "18+ months", instructions: "\(name): \(eighteen)")
        ]
    }

    fileprivate enum FruitPreparationForm: Equatable {
        case sauce
        case smallRoundBerry
        case aggregateBerry
        case roundOrSlipperyFruit
        case citrus
        case firmFruit
        case stoneFruit
        case melon
        case softFruit
        case seededPulp
        case arils
        case driedStickyFruit
        case gratedFlesh
        case cookBeforeServing
    }

    private static func fruitPreparations(name: String) -> [SolidsPreparationStage] {
        if ["cactus pear", "prickly pear"].contains(normalized(name)) {
            return preparationStages(
                name: name,
                six: "Use commercially de-spined fruit when possible. Remove every spine and hair-like glochid, peel away the entire outer skin, then mash the ripe soft flesh and remove any unexpectedly hard seed.",
                nine: "After complete de-spining and peeling, offer ripe flesh in soft small pieces or mashed on a preloaded spoon. Check the work surface and fruit again for hair-like glochids.",
                twelve: "Serve peeled ripe flesh in soft bite-size pieces or by spoon only after every spine and glochid is removed. A fork can help with slippery pieces.",
                eighteen: "Continue removing every spine, glochid, and the full outer skin before offering ripe soft flesh in pieces suited to chewing skill."
            )
        }
        switch fruitPreparationForm(name: name) {
        case .sauce:
            return preparationStages(
                name: name,
                six: "Choose an unsweetened smooth sauce. Offer it on a preloaded spoon or stir it into porridge; it should be thick enough to stay on the spoon.",
                nine: "Offer a thicker, slightly textured sauce on a preloaded spoon and let the child practice scooping. This remains a spoon food rather than becoming slices or wedges.",
                twelve: "Serve in a small bowl for independent spoon practice. Check the ingredient list for added sugar and keep the texture moist.",
                eighteen: "Offer by spoon, use as a soft dip, or mix into another food. Keep portions scoopable rather than using squeeze pouches as the usual way to eat it."
            )
        case .smallRoundBerry:
            return preparationStages(
                name: name,
                six: "Wash and remove stems. Cook if firm, then crush each berry completely so it no longer holds a small round shape; mix the mash into a scoopable food if helpful.",
                nine: "Flatten each ripe berry firmly between your fingers or quarter larger berries lengthwise. Do not serve firm berries whole and round.",
                twelve: "Continue flattening or quartering until chewing skills are reliable. Very soft berries can be offered with a child-size fork or spoon.",
                eighteen: "Serve ripe berries flattened or cut when their round shape or firmness could still block the airway. Progress based on chewing skill, not age alone."
            )
        case .aggregateBerry:
            return preparationStages(
                name: name,
                six: "Choose a very ripe berry, remove any stem, and mash or gently flatten it. Tear a large berry into soft sections if needed; discard any firm seed or core.",
                nine: "Offer ripe berries flattened or torn into small soft sections for pincer-grasp practice. Check that no firm core remains.",
                twelve: "Serve ripe whole berries only when they are soft and collapse easily; otherwise flatten or cut them. A child-size fork can help with slippery fruit.",
                eighteen: "Offer ripe berries whole or cut to match their size and firmness, continuing to remove stems and any hard core."
            )
        case .roundOrSlipperyFruit:
            return preparationStages(
                name: name,
                six: "Remove the pit, large seed, skin, and stem as applicable. Mash the ripe flesh or cut it lengthwise into quarters so no whole round shape remains.",
                nine: "Remove every pit or large seed, then quarter the fruit lengthwise or cut the slippery flesh into small soft pieces. Never serve it whole and round.",
                twelve: "Continue quartering lengthwise and removing pits, seeds, and tough skin. Use a fork for slippery pieces if helpful.",
                eighteen: "Cut lengthwise into narrow quarters or smaller pieces until the child can safely manage the fruit's round, slippery form."
            )
        case .citrus:
            return preparationStages(
                name: name,
                six: "Peel the fruit, remove seeds and the tough membrane, and offer a large juicy segment or mash the pulp. Check carefully for membrane strands before serving.",
                nine: "Remove peel, seeds, and tough membrane, then cut juicy segments into small soft pieces. A preloaded fork can make slippery pulp easier to manage.",
                twelve: "Offer membrane-free segments or small pieces and model biting and chewing. Continue removing seeds and any tough center pith.",
                eighteen: "Serve peeled segments or bite-size pieces, removing seeds and tough membrane when the child cannot yet manage them."
            )
        case .firmFruit:
            return preparationStages(
                name: name,
                six: "Peel if the skin is tough, remove the core and seeds, then steam or bake until the fruit collapses under gentle finger pressure. Mash, finely grate, or offer a large cooked section.",
                nine: "Continue cooking until tender, then offer thin slices or small soft pieces. Raw chunks remain too hard; finely grated raw fruit may be mixed into a moist food.",
                twelve: "Offer thin slices of ripe fruit or cooked bite-size pieces. If the fruit is still crisp or hard, cook or grate it rather than serving chunks.",
                eighteen: "Adjust between thin raw slices, grated fruit, and cooked pieces according to firmness and the child's chewing skills; remove core and seeds."
            )
        case .stoneFruit:
            return preparationStages(
                name: name,
                six: "Remove the pit and peel away tough or slippery skin as needed. Offer very ripe flesh mashed or as a large soft wedge that squishes easily.",
                nine: "Remove the pit, then cut ripe flesh into thin soft slices or small pieces. Roll slippery pieces in finely ground food if a little grip is needed.",
                twelve: "Serve ripe slices or bite-size pieces after removing the pit. Cook the fruit first if the flesh is still firm.",
                eighteen: "Offer ripe slices or pieces and continue removing the pit and any tough skin."
            )
        case .melon:
            return preparationStages(
                name: name,
                six: "Remove rind and seeds, then offer a broad, soft slab or mash. The flesh should yield easily; avoid small hard cubes.",
                nine: "Remove rind and seeds and cut the soft flesh into thin sticks or small pieces for pincer-grasp practice.",
                twelve: "Offer bite-size soft pieces or thin slices with no rind or seeds. Use a fork if the fruit is very slippery.",
                eighteen: "Serve soft pieces or slices, continuing to remove rind and hard seeds."
            )
        case .softFruit:
            return preparationStages(
                name: name,
                six: "Remove inedible skin, hard seeds, core, or stem. Offer very ripe flesh mashed or as a large soft section that squishes easily between two fingers.",
                nine: "Serve ripe flesh in small soft pieces or thin slices, removing hard seeds and tough skin. Add grip to slippery fruit when helpful.",
                twelve: "Offer ripe bite-size pieces with a child-size fork or fingers. Cook first if the flesh is still firm.",
                eighteen: "Serve ripe pieces or slices sized to the child's chewing skills, with hard seeds, core, and tough skin removed."
            )
        case .seededPulp:
            return preparationStages(
                name: name,
                six: "Open the fruit and scoop out the soft pulp. Mash it and offer a small amount by spoon or stir it into plain yogurt or porridge; remove any hard rind or large firm seed.",
                nine: "Serve the soft pulp on a preloaded spoon or mixed into a scoopable food. This is a pulp food, not a sliced finger food.",
                twelve: "Offer the pulp in a bowl with a child-size spoon. Keep the rind out of reach and remove any large, hard, or unexpectedly firm seed.",
                eighteen: "Serve the pulp by spoon, as a soft topping, or mixed into another food; discard the rind and any hard seed."
            )
        case .arils:
            return preparationStages(
                name: name,
                six: "Remove the arils from the rind and membrane, then crush them thoroughly to release the juice. Stir the crushed fruit into a scoopable food; do not offer intact arils.",
                nine: "Flatten or crush every aril before serving, or press the fruit through a strainer and mix the pulp and juice into food.",
                twelve: "Continue crushing or flattening arils until the child can manage their firm, round shape. Offer with a spoon rather than by the handful.",
                eighteen: "Offer arils only when their firmness has been modified for the child's chewing skills; supervise and avoid large mouthfuls."
            )
        case .driedStickyFruit:
            return preparationStages(
                name: name,
                six: "Remove the pit, then simmer or soak until very soft. Purée with liquid and offer by spoon or spread a thin layer on soft food; never serve it whole and sticky.",
                nine: "Remove the pit and soften well, then mash or finely mince and mix into a moist food. Avoid dense sticky lumps.",
                twelve: "Serve softened fruit finely chopped in a moist dish or as a thin spread. Continue avoiding whole sticky fruit.",
                eighteen: "Remove the pit and cut softened fruit into small pieces, separating sticky pieces so they cannot form a large mouthful."
            )
        case .gratedFlesh:
            return preparationStages(
                name: name,
                six: "Use unsweetened finely grated or ground flesh mixed into a moist food, or use smooth coconut milk in cooking. Do not offer a hard chunk of fresh flesh.",
                nine: "Finely grate or mince the flesh and stir it into a moist food. Avoid dry flakes and hard, chewy strips.",
                twelve: "Offer finely grated flesh in a moist dish or use coconut milk in cooking; hard chunks remain difficult to chew.",
                eighteen: "Serve finely grated or very thin soft pieces according to chewing skill, avoiding hard chunks and dry mouthfuls."
            )
        case .cookBeforeServing:
            return preparationStages(
                name: name,
                six: "Peel and remove seeds or core as needed, then cook thoroughly until the flesh is very soft. Mash or offer a large soft section; do not serve it raw and firm.",
                nine: "Cook until tender, then offer soft strips or small pieces. Remove tough skin, core, and hard seeds.",
                twelve: "Serve fully cooked bite-size pieces or mash into a dish. Check each piece for firmness before offering.",
                eighteen: "Use fully cooked pieces suited to the child's chewing skills and continue removing tough skin, core, and hard seeds."
            )
        }
    }

    fileprivate static func fruitPreparationForm(name: String) -> FruitPreparationForm {
        let key = normalized(name)
        if key == "applesauce" { return .sauce }
        if key == "coconut flesh" { return .gratedFlesh }
        if key == "pomegranate" { return .arils }
        if ["passion fruit", "finger lime"].contains(key) { return .seededPulp }
        if ["date", "prune"].contains(key) { return .driedStickyFruit }
        if ["breadfruit", "plantain", "elderberry", "quince"].contains(key) { return .cookBeforeServing }
        if ["grape", "cherry", "sour cherry", "longan", "lychee", "rambutan", "cape gooseberry"].contains(key) {
            return .roundOrSlipperyFruit
        }
        if ["blueberry", "cranberry", "currant", "blackcurrant", "redcurrant", "white currant", "gooseberry", "huckleberry", "cloudberry"].contains(key) {
            return .smallRoundBerry
        }
        if ["black raspberry", "blackberry", "boysenberry", "loganberry", "marionberry", "mulberry", "raspberry", "strawberry"].contains(key) {
            return .aggregateBerry
        }
        if ["blood orange", "clementine", "grapefruit", "kumquat", "lemon", "lime", "mandarin", "orange", "pomelo", "satsuma", "tangerine", "ugli fruit"].contains(key) {
            return .citrus
        }
        if ["apple", "asian pear", "crab apple", "jujube", "pear"].contains(key) { return .firmFruit }
        if ["apricot", "avocado", "mango", "nectarine", "peach", "plum"].contains(key) { return .stoneFruit }
        if key.contains("melon") || ["cantaloupe", "watermelon"].contains(key) { return .melon }
        return .softFruit
    }

    private static func vegetablePreparations(name: String) -> [SolidsPreparationStage] {
        switch vegetablePreparationForm(name: name) {
        case .leafy:
            return preparationStages(
                name: name,
                six: "Wash thoroughly, remove tough stems, and cook until the leaves collapse. Mince across the fibers and mix into a moist scoopable food; do not offer a wad of loose leaves.",
                nine: "Cook until tender, chop leaves and stems finely across the grain, and mix into a soft dish or omelet. Separate any stringy clump.",
                twelve: "Offer finely chopped cooked leaves in moist food or on a child-size fork. Raw leaves should be very tender, finely cut, and introduced according to chewing skill.",
                eighteen: "Add chopped leaves to family meals, continuing to cook or finely cut thick stems and any leaf that remains fibrous."
            )
        case .flower:
            return preparationStages(
                name: name,
                six: "Steam or roast until the thickest stem crushes easily. Offer a large soft floret with a long handle, or mash the tender flower and stem; remove any woody outer leaf.",
                nine: "Cook until very soft and offer small florets or chopped tender stem. Press firm round flower buds flat and avoid dry crumbly mouthfuls.",
                twelve: "Serve bite-size soft florets and thin pieces of tender stem with a fork. Cook longer if the branch points remain firm.",
                eighteen: "Offer tender florets and stems in family dishes, checking that crisp or roasted edges have not become hard."
            )
        case .compactBud:
            return preparationStages(
                name: name,
                six: "Steam or braise until the dense center crushes easily, then halve or quarter lengthwise and mash or flatten the rounded layers. Do not serve a whole bud.",
                nine: "Cook until very soft and quarter lengthwise into small pieces, pressing each piece so no firm round center remains.",
                twelve: "Offer bite-size soft quarters or chopped leaves with a fork. Continue checking the center, which can stay firm after outer leaves soften.",
                eighteen: "Serve tender halves, quarters, or chopped pieces, avoiding whole round buds and hard roasted outer leaves."
            )
        case .squash:
            return preparationStages(
                name: name,
                six: "Remove hard rind, stem, and seeds, then roast or steam until the flesh collapses under finger pressure. Offer a thick soft crescent or mash on a preloaded spoon.",
                nine: "Serve peeled, fully cooked strips or small soft pieces. Check that no hard rind or flat seed remains and add moisture if the flesh is dry.",
                twelve: "Offer bite-size cooked pieces or mash with a fork. Thin tender skin may be left only when the child can manage it; discard hard rind.",
                eighteen: "Serve soft cooked pieces in family meals, continuing to remove hard rind, stem, and seeds and to moisten dry varieties."
            )
        case .roundKernel:
            return preparationStages(
                name: name,
                six: "Cook until very soft, then mash every kernel or pea so no intact round shape remains. Mix the mash into another moist food or load it onto a spoon.",
                nine: "Cook until soft and flatten each kernel or pea before offering for pincer practice. For corn, a short tender cob section can be used for supervised mouthing while loose kernels stay mashed.",
                twelve: "Serve soft kernels or peas after pressing them flat, or mix them through a moist dish. Avoid hard, dry, or frozen pieces.",
                eighteen: "Progress toward soft whole pieces only as chewing skills become reliable; continue flattening any firm, round kernel or pea."
            )
        case .pod:
            return preparationStages(
                name: name,
                six: "Trim the stem, strings, and pointed end, split the pod lengthwise, and cook until it folds and crushes easily. Offer a long soft half or mash the pod and seeds.",
                nine: "Cook until tender, remove strings, and cut lengthwise into narrow soft strips or small pieces. Flatten any round seed inside.",
                twelve: "Offer tender chopped pod pieces with a fork, continuing to split thick pods and remove tough seams or strings.",
                eighteen: "Serve fully cooked pod pieces in family meals; avoid firm raw pods and continue trimming strings and hard ends."
            )
        case .stalk:
            return preparationStages(
                name: name,
                six: "Trim the woody base and strings, then cook until the thickest part squashes easily. Offer a long soft stalk or mince across the fibers into moist food.",
                nine: "Cook until tender and cut lengthwise or across the fibers into small soft pieces. Peel or discard any tough outer layer.",
                twelve: "Serve tender bite-size pieces with a fork. Raw versions should wait until the child can manage the ingredient's fibers and firmness.",
                eighteen: "Offer cooked or appropriately thin pieces, continuing to remove woody ends, strings, and tough outer layers."
            )
        case .bulb:
            return preparationStages(
                name: name,
                six: "Peel and cook until the layers are completely soft, then finely mince or mash a small amount into another food. Avoid a slippery intact layer or firm raw chunk.",
                nine: "Cook until tender and chop across the layers into small pieces, mixing them through a moist dish rather than offering a loose mouthful.",
                twelve: "Use soft cooked pieces to flavor family food. Very thin raw mince can be explored when tolerated, but large raw pieces remain firm and intense.",
                eighteen: "Serve cooked pieces in family meals and cut raw forms finely according to chewing skill and tolerance."
            )
        case .softFlesh:
            return preparationStages(
                name: name,
                six: "Remove the stem, tough skin, core, and hard seeds as needed. Cook until soft, then offer a broad spear that squishes easily or mash the flesh; avoid small slippery cubes.",
                nine: "Serve ripe or cooked flesh in thin strips or small soft pieces. Flatten round sections and peel away any skin that separates into a tough sheet.",
                twelve: "Offer bite-size soft pieces with a fork or fingers, continuing to remove hard seeds, stem, and tough skin.",
                eighteen: "Serve raw or cooked pieces according to actual firmness, modifying round shapes and removing any tough peel, stem, or seed."
            )
        case .root:
            return preparationStages(
                name: name,
                six: "Peel if the skin is tough, then steam, roast, or boil until the center crushes easily. Offer a thick soft spear, mash, or finely grate an appropriate raw preparation; never offer a hard raw chunk.",
                nine: "Cook until tender and cut into narrow sticks or small soft pieces. Finely grated raw root can be mixed into moist food when the particular root is eaten raw.",
                twelve: "Serve bite-size cooked pieces or very thin shreds. Continue cooking any crisp variety and avoid firm coin shapes.",
                eighteen: "Progress to thin raw or cooked pieces based on the root's actual hardness and the child's chewing skills, never by age alone."
            )
        case .tuber:
            let extra = tuberSafetyDetail(name: name)
            return preparationStages(
                name: name,
                six: "Peel as needed and cook all the way through until the center is soft and no raw firmness remains. \(extra) Mash with moisture or offer a thick soft spear without crisp edges.",
                nine: "Serve fully cooked small soft pieces, strips, or a moist mash. Break up dense sticky clumps and remove tough peel.",
                twelve: "Offer bite-size cooked pieces or a fork-mashed portion. Avoid undercooked centers, dry mouthfuls, and hard fried crusts.",
                eighteen: "Serve fully cooked pieces in family meals, keeping dense flesh moist and following the ingredient's specific peeling and cooking requirements."
            )
        case .fibrousSpecialty:
            return fibrousSpecialtyPreparations(name: name)
        }
    }

    private static func fibrousSpecialtyPreparations(name: String) -> [SolidsPreparationStage] {
        let key = normalized(name)
        if key == "artichoke" {
            return preparationStages(
                name: name,
                six: "Cook until the heart is completely tender, remove the choke and every tough outer leaf, then mash the heart with moisture. If using a leaf for flavor exploration, offer only the soft scraped pulp—not the fibrous leaf itself.",
                nine: "Finely chop or mash the fully cooked heart into moist food. Keep the choke, stem fibers, and whole leaves out of the serving.",
                twelve: "Offer small tender pieces of cooked heart with a fork. Continue removing the fuzzy choke and every tough leaf or stem fiber.",
                eighteen: "Serve tender chopped heart or model scraping soft pulp from a leaf while directly supervising; the fibrous leaf is discarded rather than swallowed."
            )
        }
        if ["bamboo shoot", "lotus root", "water chestnut"].contains(key) {
            return preparationStages(
                name: name,
                six: "Use a properly prepared product, cook thoroughly, then finely grate, purée, or mince it across the fibers into moist food. Do not offer a crisp slice or chunk.",
                nine: "Cook fully and continue grating or mincing into very small pieces mixed through a soft dish; this ingredient may stay crisp even after cooking.",
                twelve: "Offer finely chopped cooked pieces in a moist meal only when each piece is manageable. Avoid round slices and any piece that still snaps or resists chewing.",
                eighteen: "Progress cautiously to very thin, finely cut cooked pieces according to chewing skill; continue avoiding crisp rounds and chunks."
            )
        }
        if key.contains("fern") {
            return preparationStages(
                name: name,
                six: "Clean and cook thoroughly according to fern food-safety guidance, discard the cooking water, then finely mince the tender shoot into moist food. Never serve it raw or lightly cooked.",
                nine: "After thorough cooking, chop across the curled shoot and stem into small soft pieces and recheck for fibrous sections.",
                twelve: "Offer fully cooked finely chopped pieces in a moist dish. Continue excluding raw, pickled-only, or undercooked shoots.",
                eighteen: "Serve thoroughly cooked chopped pieces as part of a meal, removing any stem section that remains fibrous."
            )
        }
        return preparationStages(
            name: name,
            six: "Trim away every spine, hard skin, woody layer, or string and cook the edible portion until tender. Mash or offer a long soft strip that bends and crushes easily.",
            nine: "Cook fully and cut the tender interior across its fibers into thin strips or small soft pieces. Recheck for hard fragments before serving.",
            twelve: "Offer finely chopped tender pieces in a moist dish, grating or mincing any section that remains stringy.",
            eighteen: "Serve only the fully cooked tender portion, continuing to discard peel, spines, woody fibers, and firm ends."
        )
    }

    private static func tuberSafetyDetail(name: String) -> String {
        switch normalized(name) {
        case "cassava", "yucca root":
            return "Never serve it raw; peel and cook it properly because raw or improperly processed cassava contains naturally occurring cyanogenic compounds."
        case "taro":
            return "Never serve it raw; thorough cooking reduces naturally occurring calcium oxalate crystals that can irritate the mouth and throat."
        default:
            return "Do not taste or serve the tuber raw."
        }
    }

    private static func plantProteinPreparations(name: String) -> [SolidsPreparationStage] {
        switch plantProteinPreparationForm(name: name) {
        case .wholePulse:
            return preparationStages(
                name: name,
                six: "Cook until the center mashes easily, remove any debris, then mash or blend with liquid. Crush every bean or pea so it no longer retains a firm round shape.",
                nine: "Offer soft beans or pulses flattened one by one, mashed on a preloaded spoon, or formed into a tender patty. Remove any skin that separates and stays tough.",
                twelve: "Serve very soft pieces in a moist dish, flattening larger or firmer beans. Avoid dry handfuls and undercooked centers.",
                eighteen: "Progress toward soft whole pulses according to chewing skill, continuing to mash or flatten any firm round piece and keeping the dish moist."
            )
        case .softTofu:
            return preparationStages(
                name: name,
                six: "Use a plain pasteurized product, scoop it directly onto a preloaded spoon, or mash it into another food. Its custard texture does not need to become a strip.",
                nine: "Offer soft spoonfuls or small scoopable pieces for finger and utensil practice. Drain excess liquid but do not make the tofu dry.",
                twelve: "Serve by spoon or as very soft bite-size scoops mixed into a meal. Check sauces and seasonings for sodium and allergens.",
                eighteen: "Use as a spoon food, dip base, or soft component of family meals, keeping the product refrigerated and plainly seasoned."
            )
        case .firmTofu:
            return preparationStages(
                name: name,
                six: "Choose a plain soft or firm block that compresses easily. Cut into a wide strip for grasping or crumble and moisten it; avoid a browned rubbery crust.",
                nine: "Offer small soft pieces, crumbles, or narrow strips. Cooked tofu should remain tender enough to mash between fingers.",
                twelve: "Serve bite-size tender pieces with a fork or fingers, cutting away any tough fried edge and checking added sauce for sodium.",
                eighteen: "Offer tender cubes, strips, or crumbles in family meals; adjust any chewy skin or dense baked piece."
            )
        case .fermentedCake:
            return preparationStages(
                name: name,
                six: "Cook fully, cut across the grain, and crumble or offer a wide thin piece that remains moist and easy to tear. Avoid a tough crust or rubbery strip.",
                nine: "Serve tender crumbles, thin strips, or a soft patty with sauce. Test that the center breaks apart easily rather than stretching or resisting.",
                twelve: "Offer small moist pieces with a fork or fingers, checking marinades and packaged versions for sodium and allergens.",
                eighteen: "Use tender pieces in family meals, cutting across fibers and softening any browned or chewy edge."
            )
        case .spread:
            return preparationStages(
                name: name,
                six: "Thin with water or mix a small amount into a moist familiar food. Offer on a preloaded spoon; do not serve a dense sticky spoonful.",
                nine: "Spread a thin layer on soft food or serve as a loose dip. Check for sesame, soy, and other allergens in the recipe.",
                twelve: "Use as a thin spread, dip, or sauce while avoiding a dry clump and keeping sodium modest.",
                eighteen: "Continue serving as a spread or dip with a texture that does not form a sticky mouthful."
            )
        case .seasoning:
            return preparationStages(
                name: name,
                six: "Dissolve a very small amount through a larger moist dish for flavor; do not offer a spoonful because this fermented paste is concentrated in sodium.",
                nine: "Use sparingly in soup, sauce, or another dish and avoid additional salty ingredients in the child's portion.",
                twelve: "Season family food lightly, setting aside the child's lower-sodium portion and checking the product for soy or other allergens.",
                eighteen: "Continue using as a seasoning rather than a stand-alone serving and balance it with unsalted ingredients."
            )
        case .sprout:
            return preparationStages(
                name: name,
                six: "Cook thoroughly until the stem is tender, then mince across its length and mix into moist food. Do not serve raw sprouts to a young child.",
                nine: "Cook fully and chop into short soft pieces so no long stringy stem or firm seed head remains.",
                twelve: "Offer fully cooked chopped sprouts in a moist dish, continuing to avoid raw or lightly cooked sprouts.",
                eighteen: "Use thoroughly cooked sprouts cut into manageable lengths in family meals."
            )
        }
    }

    private static func meatPreparations(name: String) -> [SolidsPreparationStage] {
        switch meatPreparationForm(name: name) {
        case .organ:
            return preparationStages(
                name: name,
                six: "Cook fully while keeping the center tender, then purée or finely mince a small portion with liquid. Remove membrane, ducts, and any firm connective tissue.",
                nine: "Serve finely chopped tender pieces mixed into moist food or spread a thin layer of cooked mince. Avoid dry crumbly chunks.",
                twelve: "Offer small soft pieces as one component of a varied meal. Keep portions modest because organ meat has concentrated nutrients.",
                eighteen: "Serve tender chopped pieces occasionally as part of family meals, continuing to remove membrane and tough tissue."
            )
        case .ground:
            return preparationStages(
                name: name,
                six: "Cook completely, then form a wide soft patty or mix fine crumbles with sauce so they hold moisture. Avoid a dry, rubbery meatball.",
                nine: "Offer moist crumbles, a tender strip of patty, or a very soft meatball broken into small pieces. Check the center and remove any hard crust.",
                twelve: "Serve small moist pieces with a fork or fingers. Packaged ground products may add sodium or allergens, so review the recipe.",
                eighteen: "Use tender patties, crumbles, or small pieces in family meals, adding moisture whenever the meat becomes dry."
            )
        case .boneIn:
            return preparationStages(
                name: name,
                six: "Cook slowly until the meat shreds with little pressure. Remove every loose bone, bone chip, skin, cartilage, and gristle, then offer moist shreds or a large tender strip of meat only.",
                nine: "Serve soft shreds or small tender pieces cut across the grain. Recheck the plated portion for bone and hard connective tissue.",
                twelve: "Offer bite-size moist meat with a fork. Do not hand over a small, splintering, or brittle bone as a teether.",
                eighteen: "Serve tender meat removed from the bone, continuing to exclude bone fragments, tough skin, cartilage, and gristle."
            )
        case .tenderCut:
            return preparationStages(
                name: name,
                six: "Cook completely with a moist method and use a boneless portion. If the cut was cooked on the bone, take the meat off and inspect it again. Finely mince with liquid or offer a large tender strip cut across the grain, removing any gristle or tough connective tissue.",
                nine: "Serve moist shreds, thin tender strips, or small pieces cut across the grain. Recheck any meat cooked on the bone before plating, and add sauce if the meat begins to dry out.",
                twelve: "Offer small tender pieces with a fork or fingers. Avoid dry cubes and browned hard edges.",
                eighteen: "Adapt the family portion into moist pieces the child can chew, continuing to cut across the grain and remove tough tissue."
            )
        }
    }

    private static func seafoodPreparations(name: String) -> [SolidsPreparationStage] {
        switch seafoodPreparationForm(name: name) {
        case .crustacean:
            return preparationStages(
                name: name,
                six: "Cook fully, remove every shell, tail, and vein as applicable, then mince the flesh very finely into moist food. Do not serve a whole curled piece.",
                nine: "Serve finely minced or flattened tender flesh in a soft patty or sauce. Recheck for shell and avoid rubbery chunks.",
                twelve: "Offer small thin pieces that tear easily, with every shell and tail removed. Crustacean shellfish is a major allergen.",
                eighteen: "Serve tender chopped pieces in family meals, continuing to remove shell and modify any firm curled or rubbery shape."
            )
        case .bivalve:
            return preparationStages(
                name: name,
                six: "Cook fully until safely done, remove the flesh from its shell, inspect for shell fragments, and mince very finely into a moist food.",
                nine: "Serve finely chopped cooked flesh mixed through a soft dish. Do not offer a whole chewy mollusk.",
                twelve: "Offer tiny tender pieces in a moist meal, checking every serving for grit, shell, and rubbery texture.",
                eighteen: "Serve fully cooked chopped flesh, continuing to discard shell and cut any chewy piece smaller across its fibers."
            )
        case .cephalopod:
            return preparationStages(
                name: name,
                six: "Cook fully until tender, remove beak or other inedible parts, and mince extremely finely into moist food. Rings and tentacle pieces are not early serving shapes.",
                nine: "Finely mince tender cooked flesh across the fibers and mix it into a soft dish. Avoid rubbery rings or long tentacles.",
                twelve: "Offer very small tender chopped pieces with sauce, checking that each piece tears easily.",
                eighteen: "Serve thoroughly cooked pieces cut across the fibers, continuing to avoid chewy rings and oversized tentacles."
            )
        case .smallFish:
            return preparationStages(
                name: name,
                six: "Cook fully or choose an appropriate cooked canned product, then open each fish and inspect closely for bones. Mash the flesh and moisten it; check cured products for high sodium.",
                nine: "Offer soft flakes or a tender patty after another careful bone check. Break up skin if it forms a tough sheet.",
                twelve: "Serve small moist flakes with a fork or fingers, checking canned or cured versions for sodium and every portion for bones.",
                eighteen: "Use soft flakes in family meals and keep inspecting small whole fish for bones even when processing has softened them."
            )
        case .fillet:
            let mercury = normalized(name) == "swordfish"
                ? "Do not serve; choose a lower-mercury fish instead."
                : "Check current FDA/EPA advice for the exact species."
            return preparationStages(
                name: name,
                six: "\(mercury) Cook fully, separate the fillet into soft moist flakes, and inspect each flake carefully for bones before mashing or offering a soft patty.",
                nine: "Serve soft flakes or small pieces that separate with light pressure. Recheck for pin bones and remove skin if it is tough.",
                twelve: "Offer bite-size moist flakes with a fork or fingers, continuing to check every portion for bones and species-specific fish advice.",
                eighteen: "Serve tender cooked pieces in family meals, removing bones and tough skin and avoiding dry or heavily salted preparations."
            )
        }
    }

    private static func eggPreparations(name: String) -> [SolidsPreparationStage] {
        if normalized(name) == "egg yolk" {
            return preparationStages(
                name: name,
                six: "Cook the yolk fully, then mash it with water, breast milk, formula, or another familiar moist food so it is not dry or crumbly. Offer it on a preloaded spoon.",
                nine: "Mash or finely crumble the fully cooked yolk into a moist food. Keep the mixture soft and avoid a dry ball of yolk.",
                twelve: "Mix fully cooked yolk into a moist family dish or offer it mashed by spoon. Check the complete dish for other allergens.",
                eighteen: "Serve fully cooked yolk within family meals, keeping it moist and following the family's established egg-allergen plan."
            )
        }
        return preparationStages(
            name: name,
            six: "Cook the white and yolk until safely done while keeping the texture tender. Mash with water or yogurt, grate a hard-cooked egg into food, or cut a soft omelet into two-finger-wide strips.",
            nine: "Serve fully cooked soft strips, grated egg, or small tender pieces. Add moisture if the yolk is dry and avoid rubbery browned edges.",
            twelve: "Offer chopped fully cooked egg or soft fork-size pieces. Check mixed egg dishes for milk, wheat, soy, or other allergens.",
            eighteen: "Serve fully cooked egg in family meals, keeping pieces tender and continuing the family's established allergen plan."
        )
    }

    private static func preparedFoodPreparations(name: String) -> [SolidsPreparationStage] {
        switch preparedFoodPreparationForm(name: name) {
        case .soupOrStew:
            return preparationStages(
                name: name,
                six: "Cook every ingredient until very soft, remove any inedible or tough part actually present, then mash to a thick scoopable consistency. Offer on a preloaded spoon rather than as thin hot broth.",
                nine: "Serve thick and lukewarm with each component mashed or cut small. Press round beans or peas flat and shred meat across the grain.",
                twelve: "Offer from a shallow bowl with a child-size spoon. Keep pieces soft, check temperature, and choose a lower-sodium child's portion.",
                eighteen: "Adapt the family pot by modifying each hard, round, chewy, or oversized component before serving."
            )
        case .patty:
            return preparationStages(
                name: name,
                six: "Cook through without creating a hard crust, then offer a wide soft strip that compresses easily or mash the tender center. Check binders for egg, milk, wheat, or sesame.",
                nine: "Cut the soft patty into narrow strips or small tender pieces for pincer grasp. Add sauce if it is dry and discard crisp edges.",
                twelve: "Offer bite-size soft pieces with a fork or fingers, verifying that vegetables, beans, fish, or meat inside are fully cooked and modified.",
                eighteen: "Serve a tender family portion cut to chewing skill, continuing to avoid hard crusts and reviewing the recipe's allergens and sodium."
            )
        case .spoonable:
            return preparationStages(
                name: name,
                six: "Prepare a smooth or softly textured scoopable version with every ingredient safely cooked. Offer on a preloaded spoon and remove hard toppings, whole nuts, large seeds, and honey.",
                nine: "Serve a thicker scoopable texture for spoon practice. Keep mix-ins soft and flatten any berry, pea, or other round component.",
                twelve: "Offer in a small bowl with a child-size spoon. Review added sugar, sodium, and every topping or mix-in separately.",
                eighteen: "Use as a dip, bowl, or spoon food while keeping hard, sticky, or chewy additions modified for the child's skills."
            )
        case .handheld:
            return preparationStages(
                name: name,
                six: "Use a soft wrapper or bread that is not gummy, keep fillings moist, and cut a wide strip. Remove raw hard vegetables, chewy meat, and thick sticky spreads.",
                nine: "Cut into narrow strips or small soft pieces, keeping fillings from forming hard round or dry clumps. Check every layer for allergens.",
                twelve: "Offer manageable handheld pieces and model taking bites. Avoid tough toasted edges and overfilled pieces that fall apart into hazards.",
                eighteen: "Serve a child-size family version with soft fillings, modest sodium, and each component cut for current chewing skills."
            )
        case .pastaOrRice:
            return preparationStages(
                name: name,
                six: "Cook grains or pasta until very soft and keep the dish moist. Mash or press it into a scoopable clump and modify every meat, vegetable, or cheese component.",
                nine: "Serve soft moist clumps or small pasta pieces for hand or spoon practice. Cut long strands and flatten round beans or peas.",
                twelve: "Offer with a child-size spoon or fork, breaking up sticky dense clumps and checking sauce, cheese, and mixed ingredients for allergens and sodium.",
                eighteen: "Adapt the family dish by keeping grains tender, cutting long or chewy pieces, and modifying each mixed-in component."
            )
        case .mixedDish:
            return preparationStages(
                name: name,
                six: "Cook every component fully and identify the hardest or chewiest ingredient. Mash into a moist texture or offer one broad soft component at a time after checking the full allergen list.",
                nine: "Offer small soft pieces or a scoopable mixture, adapting each round, firm, sticky, stringy, or otherwise difficult ingredient actually present in the recipe.",
                twelve: "Serve a child-size portion with utensils or fingers after checking sodium, added sugar, allergens, temperature, and the texture of every component.",
                eighteen: "Adapt the family version rather than assuming the dish name guarantees a safe texture; continue changing the hardest component first."
            )
        case .sweetener:
            return [
                SolidsPreparationStage(minimumAgeMonths: 12, title: "12+ months", instructions: "\(name): only after the first birthday, mix a small amount into food rather than offering it from a spoon or container."),
                SolidsPreparationStage(minimumAgeMonths: 18, title: "18+ months", instructions: "\(name): use sparingly as an added sweetener within a balanced meal and continue normal tooth-brushing routines.")
            ]
        }
    }

    fileprivate enum ScoopablePreparationKind: Equatable {
        case porridge
        case smoothDairy
        case spread
    }

    fileprivate static func scoopablePreparationKind(
        name: String,
        category: SolidsFoodCategory
    ) -> ScoopablePreparationKind? {
        let key = normalized(name)
        if ["cereal", "porridge", "oatmeal", "grits", "polenta", "cream of rice", "farina"].contains(where: key.contains) {
            return .porridge
        }
        if key.hasSuffix(" butter") || key == "cream cheese" || key.contains("tahini") || key.contains("hummus") || key.contains("bean dip") || key.contains("refried bean") || key.contains("peanut sauce") {
            return .spread
        }
        if category == .dairy && (!key.contains("cheese") || key == "cottage cheese") && key != "paneer" {
            return .smoothDairy
        }
        return nil
    }

    private static func scoopablePreparations(
        name: String,
        category: SolidsFoodCategory
    ) -> [SolidsPreparationStage]? {
        switch scoopablePreparationKind(name: name, category: category) {
        case .porridge:
            return preparationStages(
                name: name,
                six: "Cook until very soft and moist, thinning dry or sticky cereal as needed. Offer a thick scoopable texture on a preloaded spoon rather than a dry mouthful.",
                nine: "Serve as a thick, soft cereal and let the child practice with a preloaded spoon. Break up firm lumps and add moisture before serving.",
                twelve: "Offer in a small bowl for spoon practice. Keep it moist and check temperature carefully before serving.",
                eighteen: "Serve as a spoonable cereal with soft mix-ins. Avoid hard toppings and dense sticky spoonfuls."
            )
        case .smoothDairy:
            return preparationStages(
                name: name,
                six: "Use a pasteurized, unsweetened product and offer it on a preloaded spoon or stir it into another food. This remains a scoopable food, not a sliced food.",
                nine: "Offer a thicker scoopable portion on a preloaded spoon and let the child practice bringing it to the mouth.",
                twelve: "Serve in a small bowl with a child-size spoon. Check added sugar and keep cow's milk as a drink separate from guidance for dairy used in food.",
                eighteen: "Offer by spoon, as a soft dip, or mixed into meals. Continue choosing pasteurized products."
            )
        case .spread:
            return preparationStages(
                name: name,
                six: "Thin it with warm water or mix a small amount into a familiar moist food. Never offer a thick sticky spoonful.",
                nine: "Spread a very thin layer on soft food or stir it into a scoopable dish. Keep the texture loose, not gluey or clumped.",
                twelve: "Use as a thin spread, sauce, or stirred-in ingredient. Avoid a dense spoonful or a sticky lump.",
                eighteen: "Continue serving as a thin spread or sauce and adjust thickness so it does not form a sticky mouthful."
            )
        case nil:
            return nil
        }
    }

    fileprivate enum GrainPreparationForm {
        case bread
        case pasta
        case puffedCereal
        case softGrain
    }

    fileprivate static func grainPreparationForm(name: String) -> GrainPreparationForm {
        let key = normalized(name)
        if key.contains("bread") || key.contains("toast") || key.contains("tortilla") || key == "cornbread" {
            return .bread
        }
        if key.contains("pasta") || key.contains("noodle") || key == "orzo" { return .pasta }
        if key.contains("puffed") { return .puffedCereal }
        return .softGrain
    }

    private static func grainPreparations(name: String) -> [SolidsPreparationStage] {
        switch grainPreparationForm(name: name) {
        case .bread:
            return preparationStages(
                name: name,
                six: "Use a soft, low-sodium option and lightly toast or moisten it so it does not form a gummy ball. Cut into a wide two-finger strip and add only a thin moist topping.",
                nine: "Cut into narrow strips or small bite-size pieces and keep the texture moist. Avoid dense compressed bread and thick sticky toppings.",
                twelve: "Offer manageable pieces for biting and chewing, with a soft topping when helpful. Watch for bread that becomes gummy in the mouth.",
                eighteen: "Serve strips, small pieces, or a soft sandwich cut to the child's chewing skills. Avoid dense balls of bread and hard crusts."
            )
        case .pasta:
            return preparationStages(
                name: name,
                six: "Cook past al dente until very soft. Offer a large easy-to-hold shape or cut long strands, coating lightly with sauce or oil so the pasta stays moist.",
                nine: "Cook until soft, then cut long strands or large shapes into small manageable pieces for pincer grasp. Keep pieces slippery-soft rather than chewy.",
                twelve: "Offer soft bite-size shapes or short-cut strands with a child-size fork. Avoid firm, undercooked, or very chewy pasta.",
                eighteen: "Serve soft family pasta with long strands cut as needed and any hard, round, or tough add-ins modified separately."
            )
        case .puffedCereal:
            return preparationStages(
                name: name,
                six: "Crush and moisten the cereal into a soft spoonable texture. Do not offer dry hard pieces to a new eater.",
                nine: "Choose an unsweetened puff that dissolves easily, test it yourself, and offer one piece at a time while the child is seated upright.",
                twelve: "Offer a small amount of easily dissolving cereal for finger-food practice, avoiding hard clusters and large dry mouthfuls.",
                eighteen: "Serve an unsweetened easily dissolving cereal in a seated meal or snack, not while the child is moving."
            )
        case .softGrain:
            return preparationStages(
                name: name,
                six: "Cook in plenty of liquid until each grain is very soft. Mash or press into a moist scoopable clump and offer on a preloaded spoon; do not serve loose, dry grains.",
                nine: "Serve very soft grains as moist clumps that can be picked up or scooped. Add sauce or another soft food if the grains are dry or separate.",
                twelve: "Offer soft moist grains with a child-size spoon or fork. Break up sticky dense clumps and avoid dry mouthfuls.",
                eighteen: "Serve soft grains as part of family meals, adding moisture and separating any dense sticky clump before serving."
            )
        }
    }

    private static func cheesePreparations(name: String) -> [SolidsPreparationStage] {
        let key = normalized(name)
        let isSoftOrCrumbly = ["feta", "goat cheese", "queso fresco"].contains(where: key.contains)

        if key == "paneer" {
            return preparationStages(
                name: name,
                six: "Use pasteurized paneer and cook it until tender, then finely crumble or mash it into a moist food. Paneer does not melt like many cheeses, so do not offer a firm cube.",
                nine: "Cook until soft and offer fine crumbles or a thin tender strip that mashes easily between fingers. Add sauce if it is dry.",
                twelve: "Serve small soft crumbles or very thin tender pieces in a moist dish, continuing to avoid dense cubes.",
                eighteen: "Offer soft crumbles or thin pieces sized to chewing skill and moisten any paneer that becomes dry or rubbery."
            )
        }

        if isSoftOrCrumbly {
            return preparationStages(
                name: name,
                six: "Use a pasteurized product. Mash or finely crumble a small amount into a moist food; check sodium and avoid a dry, pasty mouthful.",
                nine: "Offer finely crumbled pasteurized cheese mixed into food or pressed onto a soft finger food. Do not serve a firm cube.",
                twelve: "Serve small soft crumbles or a thin smear as part of a meal, checking sodium and keeping the texture moist.",
                eighteen: "Offer soft crumbles or thin pieces and continue avoiding firm cubes that are difficult to chew."
            )
        }

        return preparationStages(
            name: name,
            six: "Use pasteurized cheese and finely grate or melt a small amount into another food. Do not offer a firm cube or thick rubbery piece.",
            nine: "Finely grate, shred, melt, or cut into very thin slices. Avoid cubes and thick pieces that can remain firm in the mouth.",
            twelve: "Offer finely shredded cheese or paper-thin slices for biting practice. Continue avoiding firm cubes.",
            eighteen: "Serve grated cheese or thin, narrow slices sized to chewing skill; firm cubes can remain a choking hazard."
        )
    }

    private static func milkIngredientPreparations(name: String) -> [SolidsPreparationStage] {
        preparationStages(
            name: name,
            six: "Use only a pasteurized product as a small ingredient in cooked food, porridge, or another spoonable dish. Do not offer it as the main drink before 12 months.",
            nine: "Continue mixing a modest amount into food or using it in cooking. Keep breast milk or infant formula as the main milk source before the first birthday.",
            twelve: "After 12 months, it can remain an ingredient; discuss the child's overall milk choice with their clinician and avoid letting dairy drinks displace varied food.",
            eighteen: "Use in family cooking and meals, choosing pasteurized products and keeping added sugar modest."
        )
    }

    private static func nutAndSeedPreparations(name: String) -> [SolidsPreparationStage] {
        let key = normalized(name)
        let isSmallSeed = ["chia", "flax", "hemp", "poppy", "pumpkin seed", "sesame", "sunflower seed"].contains(where: key.contains)

        if key.contains("ground") {
            return preparationStages(
                name: name,
                six: "Inspect the meal for hard or coarse pieces, then mix a small amount completely into moist food. Do not offer a dry spoonful.",
                nine: "Stir the fine meal into a scoopable food or press it onto a moist surface, checking again for hard fragments and dry pockets.",
                twelve: "Use the fine meal in moist meals or baking. Keep it dispersed rather than serving a dry, dense mound.",
                eighteen: "Continue mixing the finely ground product into food and check every batch for hard pieces."
            )
        }

        if isSmallSeed {
            return preparationStages(
                name: name,
                six: "Finely grind the seeds, or soak them until fully softened when appropriate, then stir a small amount into a moist familiar food. Do not offer a dry spoonful or loose hard seeds.",
                nine: "Mix finely ground or fully softened seeds into a scoopable food or use as a very thin coating. Avoid loose dry seeds and dense clumps.",
                twelve: "Use finely ground seeds in moist meals or baked foods. Continue modifying any seed that stays hard or forms a dry mouthful.",
                eighteen: "Serve ground or fully softened seeds mixed into food; avoid handfuls of loose hard seeds."
            )
        }

        return preparationStages(
            name: name,
            six: "Grind to a fine powder and stir a small amount into moist food. Never offer a whole nut, nut pieces, or a dry spoonful of ground nut.",
            nine: "Continue serving finely ground and mixed into a moist food or pressed onto a soft surface. Do not offer whole nuts or nut pieces.",
            twelve: "Use finely ground nuts in moist meals or baking. Whole nuts and hard nut pieces remain choking hazards.",
            eighteen: "Continue using a finely ground form; do not offer whole nuts or hard nut pieces to a young toddler."
        )
    }

    fileprivate enum FlavorPreparationForm {
        case leafyHerb
        case fibrousAromatic
        case groundSpice
        case bayLeaf
    }

    fileprivate static func flavorPreparationForm(name: String) -> FlavorPreparationForm {
        let key = normalized(name)
        if key == "bay leaf flavor" {
            return .bayLeaf
        }
        if ["galangal", "ginger", "lemongrass"].contains(key) { return .fibrousAromatic }
        if ["basil", "celery leaf", "chervil", "chive", "cilantro", "curry leaf", "dill", "fennel frond", "lemon balm", "marjoram", "mint", "oregano", "parsley", "rosemary", "sage", "spearmint", "tarragon", "thyme"].contains(key) { return .leafyHerb }
        return .groundSpice
    }

    private static func flavorPreparations(name: String) -> [SolidsPreparationStage] {
        switch flavorPreparationForm(name: name) {
        case .bayLeaf:
            return preparationStages(
                name: name,
                six: "Use a whole bay leaf only to infuse a cooked dish, then find and remove it before serving. Never mince or serve the stiff leaf to the child.",
                nine: "Infuse family food with the leaf and remove it completely before plating the child's portion.",
                twelve: "Continue using only as an infusion and always remove the whole leaf before serving.",
                eighteen: "Use to flavor cooking, then remove the stiff leaf before the meal reaches the child."
            )
        case .fibrousAromatic:
            return preparationStages(
                name: name,
                six: "Peel or trim as needed, then finely grate, pound, or infuse a small amount into a cooked moist food. Remove any woody or stringy piece before serving.",
                nine: "Cook finely grated or pounded aromatic into food, or remove it after infusing. Do not leave fibrous coins, stems, or chunks.",
                twelve: "Use finely grated in cooking or as an infusion, removing tough fibers before serving.",
                eighteen: "Flavor family food with a finely grated amount or infusion and keep woody, stringy pieces out of the child's portion."
            )
        case .leafyHerb:
            return preparationStages(
                name: name,
                six: "Wash well, remove hard stems, mince the leaves finely, and mix a small amount through a moist food rather than offering a loose mouthful.",
                nine: "Finely chop across stems and leaves and mix into soft food. Cook woody herbs and remove any firm stem.",
                twelve: "Use finely chopped leaves to flavor meals, keeping hard stems and large loose leaves out of the child's portion.",
                eighteen: "Add chopped leaves to family food while continuing to remove woody stems and large tough leaves."
            )
        case .groundSpice:
            return preparationStages(
                name: name,
                six: "Use only a small pinch in a finely ground form and mix it thoroughly into moist food. Do not offer whole spices or a loose spoonful of powder.",
                nine: "Stir a small amount of finely ground spice through a moist dish. Keep whole seeds, pods, sticks, and hard fragments out of the serving.",
                twelve: "Season family food lightly with the ground spice, avoiding whole hard spices and excess salt or sugar.",
                eighteen: "Use the ground spice in family meals and remove any whole pod, stick, seed cluster, or hard fragment before serving."
            )
        }
    }

    private static func sourceURLs(
        name: String,
        category: SolidsFoodCategory,
        hasAllergens: Bool
    ) -> [URL] {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let usda = URL(string: "https://fdc.nal.usda.gov/fdc-app.html#/food-search?query=\(query)")
            ?? SolidsSourceLibrary.foodDataCentral
        var sources = [
            usda,
            SolidsSourceLibrary.cdcIntroduction,
            SolidsSourceLibrary.cdcChoking,
            SolidsSourceLibrary.aapStartingSolids,
            SolidsSourceLibrary.nhsFoodSafety
        ]
        if normalized(name) == "acai" {
            sources.insert(contentsOf: [
                SolidsSourceLibrary.nccihAcai,
                SolidsSourceLibrary.datePalmFruitAllergy,
                SolidsSourceLibrary.heartOfPalmAnaphylaxis,
                SolidsSourceLibrary.whoComplementaryFeeding,
                SolidsSourceLibrary.espghanSugarPosition,
                SolidsSourceLibrary.aapFruitJuice
            ], at: 0)
        }
        if category == .fruit { sources.append(SolidsSourceLibrary.aapFruitJuice) }
        if category == .fruit || category == .vegetable || normalized(name).contains("sprout") {
            sources.append(SolidsSourceLibrary.fdaProduceSafety)
        }
        if hasAllergens {
            sources += [SolidsSourceLibrary.fdaAllergens, SolidsSourceLibrary.aapAllergenIntroduction]
        }
        if category == .seafood {
            sources.append(SolidsSourceLibrary.fdaFishAdvice)
        }
        var seen = Set<URL>()
        return sources.filter { seen.insert($0).inserted }
    }

    private static func chokingGuidance(name: String, category: SolidsFoodCategory) -> String {
        let key = normalized(name)
        if key == "acai" {
            return "Fresh açaí berries are small and round and contain a large hard seed. Use unsweetened prepared pulp, purée, or powder mixed into a moist food instead of serving a whole fresh berry."
        }
        if ["cactus pear", "prickly pear"].contains(key) {
            return "Spines and hair-like glochids can remain on the outer skin. Remove them and the entire peel before preparing the ripe flesh, then mash or cut it into a soft manageable form and remove any unexpectedly hard seed."
        }
        if key.contains("sausage") || key.contains("hot dog") {
            return "Cut \(name.lowercased()) lengthwise into thin strips and then into small pieces; never serve coin-shaped rounds. Check sodium and casing texture."
        }
        if key.contains("popcorn") {
            return "Popcorn is a hard, irregular choking hazard and is not appropriate for babies or young toddlers. Choose soft cooked corn in a modified shape instead."
        }
        switch category {
        case .fruit:
            switch fruitPreparationForm(name: name) {
            case .sauce:
                return "Keep \(name.lowercased()) scoopable rather than watery, and serve it from a bowl or spoon with the pouch cap out of reach."
            case .smallRoundBerry:
                return "A firm whole \(name.lowercased()) can keep a small round airway shape. Cook if needed, then crush or flatten every berry."
            case .aggregateBerry:
                return "Use ripe \(name.lowercased()) that collapses easily; flatten, tear, or remove a firm core when the berry does not break down readily."
            case .roundOrSlipperyFruit:
                return "Do not serve \(name.lowercased()) whole and round. Remove its pit, large seed, husk, or inedible peel as applicable, then mash or cut the ripe flesh lengthwise."
            case .citrus:
                return "Tough citrus membrane and seeds can be difficult to manage. Remove them and serve the soft juicy pulp rather than an intact membrane-wrapped segment."
            case .firmFruit:
                return "Hard raw \(name.lowercased()) pieces can break into airway-sized chunks. Cook until soft or grate finely after removing the core and seeds."
            case .stoneFruit:
                return "Remove the entire pit from \(name.lowercased()) and use ripe flesh that squashes easily; cook it when firm and avoid slippery round pieces."
            case .melon:
                return "Remove rind and hard seeds from \(name.lowercased()). Use a broad soft piece or appropriately cut portion, not a melon ball or small slippery cube."
            case .softFruit:
                return "Use fully ripe \(name.lowercased()) that squashes easily and remove the specific hard seed, core, stem, or inedible peel it contains."
            case .seededPulp:
                return "Serve only the soft pulp of \(name.lowercased()) by spoon and remove any large or unexpectedly hard seed; keep the rind out of reach."
            case .arils:
                return "Intact \(name.lowercased()) arils can remain firm and round. Crush or flatten them rather than offering a handful."
            case .driedStickyFruit:
                return "Whole dried \(name.lowercased()) can form a dense sticky mouthful. Remove the pit, soften thoroughly, and mash or mince it into moist food."
            case .gratedFlesh:
                return "Hard coconut chunks and dry strips can be difficult to chew. Use finely grated flesh or a smooth coconut product mixed into moist food."
            case .cookBeforeServing:
                return "Raw or undercooked \(name.lowercased()) can remain firm or otherwise unsuitable. Cook it thoroughly and serve only the soft edible portion."
            }
        case .vegetable, .grain, .beanAndPlantProtein, .meat, .seafood, .dairy, .egg, .herbAndFlavor, .preparedFood:
            return safetyNote(name: name, category: category)
        case .nutAndSeed:
            if key.contains("butter") || key == "tahini" {
                return "A thick spoonful of \(name.lowercased()) can stick as one mass. Thin it into moist food or spread only a very thin layer."
            }
            if key.contains("ground") {
                return "Mix \(name.lowercased()) fully into moist food so no hard piece, dry pocket, or dense clump remains."
            }
            return "Whole or chopped \(name.lowercased()) is a choking hazard for babies and young toddlers. Grind it finely into moist food or use a smooth, well-thinned butter."
        }
    }

    private static func nutritionHighlights(name: String, category: SolidsFoodCategory) -> [String] {
        let key = normalized(name)
        switch category {
        case .fruit:
            if key == "acai" { return ["Fiber", "Anthocyanins", "Unsaturated fats vary by product"] }
            if key == "avocado" { return ["Unsaturated fats", "Fiber", "Folate"] }
            if key == "coconut flesh" { return ["Fiber", "Fat", "Manganese"] }
            if ["banana", "plantain"].contains(key) { return ["Carbohydrate", "Potassium", "Vitamin B6"] }
            if ["date", "prune", "fig"].contains(key) { return ["Fiber", "Potassium", "Concentrated carbohydrate when dried"] }
            if fruitPreparationForm(name: name) == .citrus { return ["Vitamin C", "Water", "Fiber in the pulp"] }
            if [.smallRoundBerry, .aggregateBerry].contains(fruitPreparationForm(name: name)) { return ["Vitamin C varies by berry", "Fiber", "Colorful plant compounds"] }
            if ["cantaloupe", "papaya", "mango", "persimmon"].contains(key) { return ["Vitamin A carotenoids", "Vitamin C", "Fiber"] }
            if ["kiwi", "guava", "pineapple", "strawberry"].contains(key) { return ["Vitamin C", "Fiber", "Potassium"] }
            if ["watermelon", "honeydew melon"].contains(key) { return ["Water", "Vitamin C", "Carotenoids vary by color"] }
            return ["Fiber", "Carbohydrate", "Vitamin and mineral content specific to the fruit"]
        case .vegetable:
            let form = vegetablePreparationForm(name: name)
            if form == .leafy { return ["Folate", "Vitamin K", "Vitamin A carotenoids"] }
            if form == .flower { return ["Vitamin C", "Folate", "Fiber"] }
            if ["carrot", "pumpkin", "sweet potato", "butternut squash", "kabocha squash"].contains(key) { return ["Vitamin A carotenoids", "Fiber", "Potassium"] }
            if ["potato", "yam", "cassava", "taro", "malanga", "yucca root"].contains(key) { return ["Carbohydrate", "Potassium varies by tuber", "Vitamin C varies with cooking"] }
            if ["bell pepper", "red bell pepper", "tomato", "tomatillo"].contains(key) { return ["Vitamin C", "Carotenoids", "Water"] }
            if form == .roundKernel || form == .pod { return ["Fiber", "Folate", "Plant protein varies by vegetable"] }
            return ["Fiber", "Potassium", "Vitamin content specific to the vegetable"]
        case .grain:
            if key.contains("infant") || key.contains("fortified") { return ["Fortified iron", "Carbohydrate", "B vitamins vary by product"] }
            if key.contains("oat") || key.contains("barley") { return ["Carbohydrate", "Soluble fiber", "B vitamins"] }
            if ["amaranth", "quinoa", "buckwheat", "teff"].contains(key) { return ["Carbohydrate", "Plant protein", "Iron and magnesium"] }
            if ["brown rice", "black rice", "red rice", "wild rice", "whole-grain pasta", "whole-wheat bread", "whole-wheat couscous", "whole-wheat toast", "wheat berries"].contains(key) { return ["Carbohydrate", "Fiber", "B vitamins"] }
            return ["Carbohydrate", "B vitamins vary by enrichment", "Fiber varies by processing"]
        case .beanAndPlantProtein:
            switch plantProteinPreparationForm(name: name) {
            case .wholePulse: return ["Plant protein", "Iron", "Fiber"]
            case .softTofu, .firmTofu: return ["Plant protein", "Iron", "Calcium varies by coagulant"]
            case .fermentedCake: return ["Plant protein", "Iron", "Fiber varies by product"]
            case .spread: return ["Plant protein", "Fiber", "Iron"]
            case .seasoning: return ["Fermented soy", "Sodium is concentrated", "Protein in a small serving is limited"]
            case .sprout: return ["Vitamin C", "Folate", "Plant protein"]
            }
        case .meat:
            if key.contains("liver") { return ["Iron", "Vitamin B12", "Vitamin A is highly concentrated"] }
            if ["beef", "bison", "lamb", "goat", "moose", "veal", "venison"].contains(where: key.contains) { return ["Protein", "Heme iron", "Zinc"] }
            if key.contains("pork") { return ["Protein", "Thiamin", "Zinc"] }
            return ["Protein", "Iron", "Vitamin B12"]
        case .seafood:
            let form = seafoodPreparationForm(name: name)
            if ["salmon", "sardine", "trout", "arctic char", "mackerel", "herring", "anchovy"].contains(where: key.contains) { return ["Protein", "Omega-3 fats", "Vitamin D varies by species"] }
            if form == .bivalve { return ["Protein", "Iron", "Vitamin B12"] }
            if form == .crustacean { return ["Protein", "Iodine", "Zinc"] }
            return ["Protein", "Iodine varies by species", "Omega-3 fats vary by species"]
        case .dairy:
            if key.contains("buttermilk") || key.contains("kefir") || key.contains("yogurt") || key == "skyr" || key == "labneh" { return ["Protein", "Calcium", "Live cultures vary by product"] }
            if key.contains("milk in food") { return ["Protein", "Calcium", "Vitamin D when fortified"] }
            if ["cream cheese", "mascarpone", "sour cream"].contains(key) { return ["Fat", "Calcium varies by product", "Protein is limited in a small serving"] }
            return ["Protein", "Calcium", "Vitamin B12"]
        case .egg:
            return ["Protein", "Choline", "Vitamin B12"]
        case .nutAndSeed:
            if key == "coconut butter" { return ["Fat is mostly saturated", "Fiber varies by product", "Manganese"] }
            if key == "chestnut" { return ["Carbohydrate", "Fiber", "Fat is lower than in most nuts"] }
            if key.contains("walnut") || key.contains("chia") || key.contains("flax") || key.contains("hemp") { return ["Unsaturated fats", "Plant omega-3 fats", "Protein"] }
            if key.contains("brazil") { return ["Unsaturated fats", "Selenium is highly concentrated", "Protein"] }
            if key.contains("sesame") || key == "tahini" { return ["Unsaturated fats", "Calcium varies by product", "Protein"] }
            if key.contains("pumpkin") { return ["Unsaturated fats", "Iron", "Zinc"] }
            return ["Unsaturated fats", "Protein", "Vitamin and mineral content specific to the nut or seed"]
        case .herbAndFlavor:
            if ["cinnamon", "clove", "cardamom", "cumin", "paprika", "turmeric"].contains(key) { return ["Flavor exposure", "Colorful plant compounds", "Serving amounts are small"] }
            return ["Flavor exposure", "Aromatic plant compounds", "Serving amounts are small"]
        case .preparedFood:
            if key == "honey" { return ["Added sugar", "No meaningful iron", "Not for infants under 12 months"] }
            if ["beef", "chicken", "turkey", "meat", "fish", "salmon", "bean", "lentil", "tofu", "egg"].contains(where: key.contains) { return ["Protein depends on the recipe", "Iron depends on the main ingredient", "Sodium varies widely"] }
            if ["oat", "millet", "corn", "rice", "pasta", "gnocchi", "bread", "toast", "waffle", "pancake"].contains(where: key.contains) { return ["Carbohydrate", "Protein depends on the recipe", "Iron varies with fortification and ingredients"] }
            return ["Nutrition depends on the exact recipe", "Sodium and added sugar vary", "Review every ingredient"]
        }
    }

    private static func ironRichStatus(name: String, category: SolidsFoodCategory) -> Bool {
        let key = normalized(name)
        switch category {
        case .meat, .egg:
            return true
        case .beanAndPlantProtein:
            return ![.seasoning, .sprout].contains(plantProteinPreparationForm(name: name))
        case .seafood:
            return seafoodPreparationForm(name: name) == .bivalve
                || ["sardine", "anchovy", "smelt"].contains(where: key.contains)
        case .grain:
            return key.contains("infant") || key.contains("fortified")
        case .nutAndSeed:
            return ["pumpkin seed", "sesame", "tahini"].contains(where: key.contains)
        case .preparedFood:
            return ["beef", "meat", "bean", "lentil", "tofu"].contains(where: key.contains)
        default:
            return false
        }
    }

    private static func servingVisuals(name: String, category: SolidsFoodCategory) -> [SolidsServingVisual] {
        let key = normalized(name)
        if key == "acai" || key == "applesauce" { return [.spoon, .spoon, .spoon, .spoon] }
        if key == "egg yolk" { return [.spoon, .spoon, .spoon, .spoon] }
        if category == .fruit {
            switch fruitPreparationForm(name: name) {
            case .sauce, .seededPulp:
                return [.spoon, .spoon, .spoon, .spoon]
            case .smallRoundBerry, .aggregateBerry, .roundOrSlipperyFruit, .arils:
                return [.mashed, .flattened, .softPieces, .softPieces]
            case .firmFruit:
                return [.mashed, .shredded, .softPieces, .softPieces]
            case .driedStickyFruit:
                return [.mashed, .thinSpread, .softPieces, .softPieces]
            case .gratedFlesh:
                return [.shredded, .shredded, .shredded, .softPieces]
            case .citrus, .stoneFruit, .melon, .softFruit, .cookBeforeServing:
                return [.mashed, .spear, .softPieces, .softPieces]
            }
        }
        switch scoopablePreparationKind(name: name, category: category) {
        case .porridge, .smoothDairy:
            return [.spoon, .spoon, .spoon, .spoon]
        case .spread:
            return [.spoon, .thinSpread, .thinSpread, .thinSpread]
        case nil:
            break
        }
        if category == .grain {
            if key.contains("bread") || key.contains("toast") || key.contains("tortilla") || key == "cornbread" {
                return [.spear, .softPieces, .softPieces, .softPieces]
            }
            if key.contains("pasta") || key.contains("noodle") || key == "orzo" {
                return [.spear, .softPieces, .softPieces, .softPieces]
            }
            if key.contains("puffed") { return [.mashed, .softPieces, .softPieces, .softPieces] }
            return [.spoon, .spoon, .spoon, .spoon]
        }
        if category == .vegetable {
            switch vegetablePreparationForm(name: name) {
            case .leafy, .bulb, .fibrousSpecialty:
                return [.mashed, .shredded, .softPieces, .softPieces]
            case .roundKernel, .compactBud:
                return [.mashed, .flattened, .softPieces, .softPieces]
            case .flower, .squash, .pod, .stalk, .softFlesh, .root, .tuber:
                return [.mashed, .spear, .softPieces, .softPieces]
            }
        }
        if category == .beanAndPlantProtein {
            switch plantProteinPreparationForm(name: name) {
            case .wholePulse: return [.mashed, .flattened, .softPieces, .softPieces]
            case .softTofu, .spread, .seasoning: return [.spoon, .spoon, .spoon, .spoon]
            case .firmTofu, .fermentedCake: return [.spear, .softPieces, .softPieces, .softPieces]
            case .sprout: return [.shredded, .shredded, .softPieces, .softPieces]
            }
        }
        if category == .dairy { return [.shredded, .shredded, .softPieces, .softPieces] }
        if category == .egg { return [.mashed, .spear, .softPieces, .softPieces] }
        if category == .nutAndSeed || category == .herbAndFlavor { return [.spoon, .spoon, .spoon, .spoon] }
        if category == .seafood { return [.flakes, .softPieces, .softPieces, .softPieces] }
        if category == .meat { return [.shredded, .spear, .softPieces, .softPieces] }
        if category == .preparedFood {
            switch preparedFoodPreparationForm(name: name) {
            case .soupOrStew, .spoonable, .pastaOrRice, .sweetener:
                return [.spoon, .spoon, .spoon, .spoon]
            case .patty:
                return [.flattened, .softPieces, .softPieces, .softPieces]
            case .handheld:
                return [.spear, .softPieces, .softPieces, .softPieces]
            case .mixedDish:
                return [.mashed, .softPieces, .softPieces, .softPieces]
            }
        }
        if ["grape", "blueberry", "cherry"].contains(where: key.contains) {
            return [.mashed, .flattened, .softPieces, .softPieces]
        }
        return [.mashed, .spear, .softPieces, .softPieces]
    }

    private static func safetyNote(name: String, category: SolidsFoodCategory) -> String {
        let key = normalized(name)
        if key == "acai" {
            return "Use unsweetened commercially prepared pulp, purée, or powder. Do not serve fresh whole açaí berries or hard bowl toppings, and do not add honey before 12 months."
        }
        if key == "honey" {
            return "Do not offer honey before 12 months because of infant botulism risk."
        }
        if key == "swordfish" {
            return "FDA/EPA list swordfish as a choice to avoid for young children because it has among the highest mercury levels. Choose a lower-mercury fish instead."
        }
        if key == "tuna" {
            return "Mercury guidance varies by tuna species. Canned light tuna is a lower-mercury choice; avoid bigeye tuna and check FDA/EPA fish advice for other types."
        }
        if key == "mackerel" {
            return "Mercury guidance varies by mackerel species. Do not use king mackerel for a young child; confirm the exact species against current FDA/EPA fish advice before serving another type."
        }
        if ["cactus pear", "prickly pear"].contains(key) {
            return "Use only fruit with every spine and hair-like glochid removed. Peel away the entire outer skin, clean the work area, and serve only the ripe soft flesh with any unexpectedly hard seed removed."
        }
        if key == "cassava" || key == "yucca root" {
            return "Never serve cassava raw. Peel and cook it properly because raw or improperly processed cassava contains naturally occurring cyanogenic compounds; discard bitter-tasting cassava and its cooking water."
        }
        if key == "taro" {
            return "Never serve taro raw. Peel and cook it thoroughly because raw or undercooked taro contains calcium oxalate crystals that can irritate the mouth and throat."
        }
        if key == "fiddlehead fern" || key == "edible fern" {
            return "Do not serve raw or lightly cooked fern shoots. Clean them carefully and boil or steam them thoroughly according to food-safety guidance before changing the texture for the child."
        }
        if key.contains("sprout") {
            return "Raw and lightly cooked sprouts can carry harmful bacteria. Cook thoroughly until steaming hot, then cool and chop before serving."
        }
        if key.contains("liver") {
            return "Cook liver fully, remove membrane and tough tissue, and serve a modest amount. Liver is concentrated in preformed vitamin A, so it should not be treated as an everyday large portion."
        }
        switch category {
        case .fruit:
            switch fruitPreparationForm(name: name) {
            case .sauce:
                return "Choose unsweetened \(name.lowercased()) with no honey before 12 months, and serve it from a bowl or spoon rather than letting the child handle a pouch cap."
            case .smallRoundBerry, .aggregateBerry:
                return "Wash the fruit, remove its stem or firm core when present, and mash, flatten, or cut any berry that remains firm or round."
            case .roundOrSlipperyFruit:
                return "Remove the fruit's pit, large seed, husk, or inedible peel as applicable, and never serve it whole and round."
            case .citrus:
                return "Remove peel, seeds, and tough membrane. Offer the pulp rather than a firm membrane-wrapped segment."
            case .firmFruit:
                return "Remove the core and seeds, then cook or finely grate the fruit instead of offering hard raw chunks."
            case .stoneFruit:
                return "Remove the entire pit and use only ripe soft flesh, peeling tough skin or cooking firm fruit when needed."
            case .melon:
                return "Remove rind and hard seeds and avoid melon balls or small slippery cubes."
            case .softFruit:
                return "Use fully ripe soft flesh and remove the specific stem, hard seed, core, or inedible peel the fruit contains."
            case .seededPulp:
                return "Keep the rind out of the serving and remove any large or unexpectedly hard seed from the soft pulp."
            case .arils:
                return "Remove rind and membrane, then crush or flatten every firm aril for an early eater."
            case .driedStickyFruit:
                return "Confirm the pit is removed, soften the fruit thoroughly, and do not serve a whole dense, sticky piece."
            case .gratedFlesh:
                return "Use finely grated flesh or a smooth coconut product in moist food; avoid hard chunks and dry chewy strips."
            case .cookBeforeServing:
                return "Cook \(name.lowercased()) thoroughly and use only the properly peeled, trimmed, soft edible portion."
            }
        case .vegetable:
            switch vegetablePreparationForm(name: name) {
            case .leafy:
                return "Wash well, cook until tender, remove tough stems, and chop across fibers so the leaves do not form a stringy clump."
            case .flower:
                return "Cook until the thickest stem and florets crush easily; trim woody leaves and avoid firm loose buds."
            case .compactBud, .roundKernel:
                return "Cook until soft and mash, flatten, halve, or quarter the round piece rather than serving it intact."
            case .squash:
                return "Remove hard rind and seeds and cook the flesh until it crushes easily."
            case .pod:
                return "Remove strings and tough seams, cook the pod until soft, and split or chop it."
            case .stalk:
                return "Trim woody ends and strings, cook until tender, and cut across the fibers."
            case .bulb:
                return "Cook until soft and avoid firm raw chunks or large slippery layers."
            case .softFlesh:
                return "Remove the stem and any tough peel or hard seed, use soft flesh, and avoid small slippery cubes."
            case .root:
                return "Cook until the center crushes easily or follow a specifically recommended fine-grated preparation; do not serve hard raw chunks."
            case .tuber:
                return "Cook fully through the center and keep the starchy flesh moist."
            case .fibrousSpecialty:
                return "Use only the properly trimmed edible portion, discard tough or irritating material, and cook thoroughly."
            }
        case .grain:
            switch grainPreparationForm(name: name) {
            case .bread:
                return "Avoid hard crusts, whole seeds or nuts, and compressed gummy mouthfuls; use a piece that tears easily."
            case .pasta:
                return "Cook past firm, shorten strands or modify large shapes, and keep the pasta moist rather than sticky or rubbery."
            case .puffedCereal:
                return "Use only puffs that dissolve readily and offer a few at a time while the child is seated and supervised."
            case .softGrain:
                return "Cook until no hard center remains, add enough moisture, and break up dense clumps or whole kernels."
            }
        case .beanAndPlantProtein:
            switch plantProteinPreparationForm(name: name) {
            case .wholePulse:
                return "Cook until the center mashes easily, then mash or flatten whole beans and peas for an early eater."
            case .softTofu:
                return "Keep the tofu scoopable and check for firm add-ins or a rubbery surface."
            case .firmTofu:
                return "Use moist strips, crumbles, or soft pieces that compress and break apart easily."
            case .fermentedCake:
                return "Cook as directed and avoid a hard crust, thick elastic chunk, or dry rubbery piece."
            case .spread:
                return "Thin a dense spread and avoid a thick sticky spoonful."
            case .seasoning:
                return "Use only a small amount mixed through a larger dish; check sodium and the complete allergen label."
            case .sprout:
                return "Cook sprouts thoroughly until steaming hot, cool them, and chop across the stems before serving."
            }
        case .meat:
            switch meatPreparationForm(name: name) {
            case .organ:
                return "Cook fully, remove membrane and tough ducts, and keep the finished texture soft and moist."
            case .ground:
                return "Cook fully and keep patties, meatballs, or crumbles moist; break apart hard crusts and rubbery pieces."
            case .boneIn:
                return "Cook fully, remove the meat from the bone, and inspect again for loose bone, cartilage, gristle, and tough skin."
            case .tenderCut:
                return "Cook fully and use a boneless portion. If the cut was cooked on the bone, remove the meat and inspect it again; discard any gristle or tough connective tissue, then shred across the grain or mince with moisture."
            }
        case .seafood:
            switch seafoodPreparationForm(name: name) {
            case .crustacean:
                return "Cook fully, remove the entire shell and tail, and mince or flatten any firm curved flesh."
            case .bivalve:
                return "Cook fully, remove every shell fragment, and mince the chewy flesh finely."
            case .cephalopod:
                return "Cook fully until tender and mince very finely; do not serve rings, tentacles, or rubbery chunks."
            case .smallFish:
                return "Check sodium and current fish advice, cook as needed, and inspect every portion carefully for bones."
            case .fillet:
                return "Cook fully, follow current advice for the exact species, and inspect the cooked flakes carefully for fine bones."
            }
        case .dairy:
            if key.contains("in food") {
                return "Use pasteurized dairy only as a recipe ingredient before 12 months, not as the main milk drink."
            }
            if case .smoothDairy = scoopablePreparationKind(name: name, category: category) {
                return "Choose a pasteurized, unsweetened product and keep it scoopable rather than adding hard toppings."
            }
            return "Use pasteurized cheese and grate, crumble, melt, or slice it thinly instead of serving firm cubes."
        case .egg:
            return key == "egg yolk"
                ? "Cook the yolk fully and add moisture so it is not dry or crumbly. Egg is a major food allergen."
                : "Cook the egg fully while keeping it soft rather than rubbery. Egg is a major food allergen."
        case .nutAndSeed:
            if key.contains("butter") || key == "tahini" {
                return "Use a smooth product thinned into moist food or spread very thinly; never serve a thick spoonful."
            }
            if key.contains("ground") {
                return "Mix the fine meal into moist food and verify that no hard piece or dry pocket remains."
            }
            return "Do not serve whole or chopped nuts or hard seeds. Grind finely into moist food or use a smooth, well-thinned butter."
        case .herbAndFlavor:
            switch flavorPreparationForm(name: name) {
            case .bayLeaf:
                return "Use the leaf only to infuse flavor and remove it before serving."
            case .fibrousAromatic:
                return "Finely grate, pound, or infuse a small amount and remove woody strands or chunks."
            case .leafyHerb:
                return "Remove firm stems, chop finely, and mix a small amount through moist food."
            case .groundSpice:
                return "Use a small pinch mixed through food; do not offer loose powder or whole hard spice pieces."
            }
        case .preparedFood:
            switch preparedFoodPreparationForm(name: name) {
            case .soupOrStew:
                return "Cook every component fully, remove hazards actually present in the recipe, and keep the mixture thick enough to stay together on a spoon."
            case .patty:
                return "Cook the center fully, keep the patty tender, avoid a hard crust, and check all binders for allergens."
            case .spoonable:
                return "Keep the dish scoopable and modify every topping or mix-in; check the complete recipe for allergens, honey, added sugar, and sodium."
            case .handheld:
                return "Soften fillings, avoid tough or gummy wrappers, and cut the assembled food for the child's biting skills."
            case .pastaOrRice:
                return "Cook the grain until soft, keep the dish moist, and adapt each meat, vegetable, or cheese component separately."
            case .mixedDish:
                return "Check every ingredient and adapt the firmest, roundest, or stickiest component in the actual recipe."
            case .sweetener:
                return "Do not offer honey before 12 months because of infant botulism risk."
            }
        }
    }

    private static func allergenIDs(name: String, category: SolidsFoodCategory) -> [String] {
        let key = normalized(name)
        var values: [SolidsAllergen] = []
        if category == .dairy { values.append(.milk) }
        if category == .egg || (category == .preparedFood && key.contains("egg")) { values.append(.egg) }
        if category == .seafood {
            let shellfish = ["shrimp", "prawn", "crab", "lobster", "crayfish", "langoustine"]
            let mollusks = ["clam", "mussel", "oyster", "scallop", "octopus", "squid"]
            if shellfish.contains(where: key.contains) {
                values.append(.crustaceanShellfish)
            } else if !mollusks.contains(where: key.contains) {
                values.append(.fish)
            }
        }
        if key.contains("peanut") { values.append(.peanuts) }
        if category == .nutAndSeed && !key.contains("peanut") && !key.contains("sesame") && !key.contains("sunflower") && !key.contains("pumpkin") && !key.contains("chia") && !key.contains("flax") && !key.contains("hemp") && !key.contains("poppy") && !key.contains("coconut") { values.append(.treeNuts) }
        if key.contains("wheat") || key.contains("bread") || key.contains("toast") || key.contains("pasta") || key.contains("couscous") || key.contains("bulgur") || key.contains("seitan") || key.contains("cracker") || key.contains("noodle") { values.append(.wheat) }
        if key.contains("soy") || key.contains("tofu") || key.contains("tempeh") || key.contains("edamame") || key.contains("miso") { values.append(.soy) }
        if key.contains("sesame") || key.contains("tahini") { values.append(.sesame) }
        return Array(Set(values.map(\.rawValue))).sorted()
    }

    private static func possibleAllergenIDs(name: String, category: SolidsFoodCategory) -> [String] {
        let key = normalized(name)
        var values = [SolidsAllergen]()
        if category == .beanAndPlantProtein && key == "hummus" { values += [.sesame] }
        if category == .herbAndFlavor && key.contains("za'atar") { values += [.sesame] }
        if category == .preparedFood {
            if ["waffle", "pancake", "fritter", "french toast", "fish cake", "salmon cake", "meat loaf", "gnocchi"].contains(where: key.contains) {
                values += [.milk, .egg, .wheat]
            }
            if ["bean burger", "broccoli fritter", "soft taco", "spinach pancake", "sweet potato fritter"].contains(where: key.contains) {
                values += [.egg, .wheat]
            }
            if key.contains("quesadilla") || key.contains("macaroni and cheese") { values += [.milk, .wheat] }
            if key.contains("smoothie") || key.contains("yogurt parfait") || key.contains("rice pudding") { values += [.milk] }
            if key.contains("risotto") || key.contains("shepherd's pie") || key.contains("mashed potato") { values += [.milk] }
            if key.contains("falafel") || key.contains("bean dip") { values += [.sesame] }
        }
        return Array(Set(values.map(\.rawValue)).subtracting(allergenIDs(name: name, category: category))).sorted()
    }

    private static func servingAmountGuidance(
        name: String,
        category: SolidsFoodCategory,
        ageMonths: Int,
        visual: SolidsServingVisual
    ) -> SolidsServingAmountGuidance {
        let key = normalized(name)

        if key == "peanut butter" {
            return SolidsServingAmountGuidance(
                firstServing: "1 tsp smooth peanut butter, thinned into a familiar food. Offer a small taste first, pause about 10 minutes, then continue the prepared amount if no reaction appears.",
                routineServing: "About 2 tsp smooth peanut butter, thinned or spread very thinly. The child does not need to finish it."
            )
        }

        if category == .nutAndSeed {
            let safeForm: String
            if key.contains("butter") || key == "tahini" {
                safeForm = "smooth \(name.lowercased()), well thinned"
            } else if key.contains("ground") {
                safeForm = "\(name.lowercased()) mixed completely into moist food"
            } else if ["chia", "flax", "hemp", "poppy", "pumpkin seed", "sesame", "sunflower seed"].contains(where: key.contains) {
                safeForm = "\(name.lowercased()), finely ground or fully softened as appropriate and mixed into moist food"
            } else {
                safeForm = "\(name.lowercased()), finely ground into moist food"
            }
            return SolidsServingAmountGuidance(
                firstServing: "1 tsp \(safeForm); begin with a small taste.",
                routineServing: "Up to 2 tsp \(safeForm), after it is tolerated."
            )
        }

        if category == .herbAndFlavor {
            if flavorPreparationForm(name: name) == .bayLeaf {
                return SolidsServingAmountGuidance(
                    firstServing: "No leaf in the serving. Infuse the family dish with 1 whole leaf, then remove it before plating the child's portion.",
                    routineServing: "No leaf in the serving. Use only the flavor infused into the food and remove every leaf before serving."
                )
            }
            return SolidsServingAmountGuidance(
                firstServing: "A small pinch mixed evenly through a familiar food.",
                routineServing: "A pinch to ⅛ tsp mixed through the meal, adjusting for flavor."
            )
        }

        if key == "honey" {
            return SolidsServingAmountGuidance(
                firstServing: "After 12 months only: a small drizzle mixed into food.",
                routineServing: "Up to 1 tsp as an occasional added sweetener."
            )
        }

        if category == .egg {
            if key == "egg yolk" {
                return SolidsServingAmountGuidance(
                    firstServing: "1–2 tsp fully cooked yolk mashed into moist food; begin with a small taste.",
                    routineServing: "Up to 1 fully cooked yolk kept moist, after egg is tolerated. The child does not need to finish it."
                )
            }
            return SolidsServingAmountGuidance(
                firstServing: "1–2 tsp fully cooked egg; begin with a small taste.",
                routineServing: "About one-third of a fully cooked egg, after it is tolerated."
            )
        }

        let routineVolume = ageMonths < 9 ? "1–2 tbsp" : "2–4 tbsp"
        let firstServing: String
        let routineServing: String
        switch visual {
        case .spear:
            firstServing = "1 soft prepared piece."
            routineServing = "1–2 soft prepared pieces, or about \(routineVolume) when mashed or chopped."
        case .flattened:
            firstServing = "1 soft flattened piece."
            routineServing = "2–4 soft flattened pieces, or about \(routineVolume) prepared."
        case .softPieces:
            firstServing = "1–2 soft prepared pieces."
            routineServing = "About \(routineVolume) of prepared pieces."
        case .thinSpread:
            firstServing = "1 tsp in a very thin layer; begin with a small taste."
            routineServing = "Up to 2 tsp spread very thinly, after it is tolerated."
        case .mashed, .shredded, .flakes, .spoon:
            firstServing = "1–2 tsp prepared food."
            routineServing = "About \(routineVolume) prepared."
        }

        return SolidsServingAmountGuidance(
            firstServing: firstServing,
            routineServing: routineServing
        )
    }

    private static func ingredientQuantity(for name: String) -> String {
        guard let food = food(named: name) else { return "As needed" }
        switch food.category {
        case .herbAndFlavor:
            return flavorPreparationForm(name: name) == .bayLeaf
                ? "1 leaf for infusion; remove"
                : "Pinch"
        case .nutAndSeed:
            let key = normalized(name)
            return key.contains("butter") || key == "tahini"
                ? "1–2 tsp, thinned"
                : "1–2 tsp, finely ground into moist food"
        case .meat, .seafood, .egg, .beanAndPlantProtein: return "2 tbsp prepared"
        case .dairy: return "2 tbsp"
        default: return "2–4 tbsp prepared"
        }
    }

    private static func substitutions(for name: String) -> [String] {
        guard let food = food(named: name) else { return [] }
        return (foodsByCategory[food.category] ?? []).filter { candidate in
            candidate.category == food.category
                && candidate.id != food.id
                && candidate.minimumAgeMonths <= food.minimumAgeMonths
        }.prefix(3).map(\.name)
    }

    private static func aliases(for name: String) -> [String] {
        switch name {
        case "Garbanzo bean": ["Chickpea"]
        case "Cilantro": ["Coriander leaf"]
        case "Eggplant": ["Aubergine"]
        case "Zucchini": ["Courgette"]
        case "Bell pepper": ["Sweet pepper"]
        case "Arugula": ["Rocket"]
        case "Corn": ["Maize"]
        case "Pollock": ["Pollack"]
        case "Plain whole-milk yogurt": ["Plain full-fat yogurt"]
        default: []
        }
    }

    private static func names(in value: String) -> [String] {
        value.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private static func slug(_ value: String) -> String {
        normalized(value)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let fruitNames = """
    Açaí; Apple; Applesauce; Apricot; Asian pear; Atemoya; Avocado; Banana; Black raspberry; Blackberry; Blackcurrant; Blood orange; Blueberry; Boysenberry; Breadfruit; Cactus pear; Cantaloupe; Cape gooseberry; Cherimoya; Cherry; Clementine; Cloudberry; Coconut flesh; Crab apple; Cranberry; Currant; Date; Dragon fruit; Durian; Elderberry; Feijoa; Fig; Finger lime; Gooseberry; Grape; Grapefruit; Guava; Honeydew melon; Huckleberry; Jackfruit; Jujube; Kiwi; Kumquat; Lemon; Lime; Loganberry; Longan; Loquat; Lychee; Mandarin; Mango; Mangosteen; Marionberry; Mulberry; Nectarine; Orange; Papaya; Passion fruit; Pawpaw; Peach; Pear; Persimmon; Pineapple; Plantain; Plum; Pomegranate; Pomelo; Prickly pear; Prune; Quince; Rambutan; Raspberry; Redcurrant; Sapodilla; Satsuma; Sour cherry; Star fruit; Strawberry; Tamarillo; Tangerine; Ugli fruit; Watermelon; White currant
    """

    private static let vegetableNames = """
    Acorn squash; Artichoke; Arugula; Asparagus; Bamboo shoot; Beet; Beet greens; Bell pepper; Bitter melon; Bok choy; Broccoli; Broccoli rabe; Brussels sprouts; Butternut squash; Cabbage; Cactus pad; Carrot; Cassava; Cauliflower; Celeriac; Celery; Chayote; Collard greens; Corn; Cucumber; Daikon; Delicata squash; Edible fern; Eggplant; Endive; Fennel bulb; Fiddlehead fern; French bean; Garlic; Green bean; Green cabbage; Green onion; Hearts of palm; Hubbard squash; Jicama; Kale; Kabocha squash; Kohlrabi; Leek; Lettuce; Lotus root; Malanga; Mustard greens; Napa cabbage; Nopales; Okra; Onion; Parsnip; Pea; Pea shoot; Potato; Pumpkin; Purple cabbage; Radicchio; Radish; Red bell pepper; Red onion; Rutabaga; Savoy cabbage; Scallion; Shallot; Snap pea; Spaghetti squash; Spinach; Sweet potato; Swiss chard; Taro; Tomatillo; Tomato; Turnip; Turnip greens; Water chestnut; Watercress; Wax bean; Winter melon; Yam; Yellow squash; Yucca root; Zucchini
    """

    private static let grainNames = """
    Amaranth; Angel hair pasta; Arborio rice; Barley; Barley cereal; Basmati rice; Black rice; Bran cereal; Bread; Brown rice; Buckwheat; Buckwheat noodle; Bulgur; Cassava flour porridge; Corn tortilla; Cornbread; Cornmeal; Couscous; Cream of rice; Einkorn; Farina; Farro; Fonio; Freekeh; Grits; Hominy; Infant barley cereal; Infant multigrain cereal; Infant oatmeal; Infant rice cereal; Jasmine rice; Kamut; Kasha; Millet; Multigrain bread; Oat bran; Oatmeal; Orzo; Pasta; Pearl barley; Polenta; Puffed rice cereal; Quinoa; Red rice; Rice; Rice noodle; Rice porridge; Rye; Rye bread; Semolina; Sorghum; Spelt; Steel-cut oats; Teff; Toast; Udon noodle; Wheat berries; Wheat cereal; Wheat noodle; White rice; Whole-grain pasta; Whole-wheat bread; Whole-wheat couscous; Whole-wheat toast; Wild rice
    """

    private static let plantProteinNames = """
    Adzuki bean; Black bean; Black-eyed pea; Borlotti bean; Broad bean; Butter bean; Cannellini bean; Chickpea; Cranberry bean; Edamame; Fava bean; Fermented tofu; Firm tofu; French lentil; Garbanzo bean; Great northern bean; Green lentil; Green pea; Hummus; Kidney bean; Lentil; Lima bean; Lupini bean; Miso; Moth bean; Mung bean; Mung bean sprout; Navy bean; Pea protein patty; Pigeon pea; Pink bean; Pinto bean; Red bean; Red lentil; Refried bean; Seitan; Silken tofu; Soybean; Split pea; Sprouted lentil; Tempeh; Tofu; White bean; Yellow lentil; Yellow split pea
    """

    private static let meatNames = """
    Beef; Beef brisket; Beef cheek; Beef liver; Beef meatball; Beef short rib; Bison; Chicken; Chicken breast; Chicken drumstick; Chicken liver; Chicken meatball; Chicken thigh; Cornish hen; Duck; Duck breast; Duck leg; Goat; Ground beef; Ground chicken; Ground lamb; Ground pork; Ground turkey; Lamb; Lamb chop; Lamb liver; Lamb meatball; Lamb shank; Moose; Oxtail; Pork; Pork chop; Pork loin; Pork meatball; Pork shoulder; Quail; Rabbit; Roast beef; Turkey; Turkey breast; Turkey leg; Turkey meatball; Veal; Venison
    """

    private static let seafoodNames = """
    Anchovy; Arctic char; Barramundi; Bass; Black cod; Bluefish; Branzino; Catfish; Clam; Cod; Crab; Crayfish; Croaker; Flounder; Grouper; Haddock; Hake; Halibut; Herring; Langoustine; Lobster; Mackerel; Mahi-mahi; Milkfish; Monkfish; Mullet; Mussel; Ocean perch; Octopus; Oyster; Perch; Pike; Pollock; Pompano; Prawn; Rainbow trout; Red snapper; Rockfish; Salmon; Sardine; Scallop; Sea bass; Shrimp; Smelt; Sole; Squid; Steelhead trout; Swordfish; Tilapia; Trout; Tuna; Turbot; Walleye; Whitefish; Whiting
    """

    private static let dairyNames = """
    Buttermilk in food; Cheddar cheese; Colby cheese; Cottage cheese; Cream cheese; Feta cheese; Fontina cheese; Goat cheese; Gouda cheese; Greek yogurt; Gruyère cheese; Havarti cheese; Kefir; Labneh; Mascarpone; Monterey Jack cheese; Mozzarella cheese; Paneer; Parmesan cheese; Pasteurized milk in food; Plain whole-milk yogurt; Provolone cheese; Queso fresco; Ricotta; Romano cheese; Skyr; Sour cream; Swiss cheese; Whole-milk yogurt
    """

    private static let eggNames = """
    Chicken egg; Duck egg; Egg; Egg omelet; Egg yolk; Goose egg; Hard-boiled egg; Quail egg; Scrambled egg; Turkey egg
    """

    private static let nutAndSeedNames = """
    Almond; Almond butter; Brazil nut; Cashew; Cashew butter; Chestnut; Chia seed; Coconut butter; Flaxseed; Ground almond; Ground cashew; Ground hazelnut; Ground pecan; Ground pistachio; Ground walnut; Hazelnut; Hazelnut butter; Hemp seed; Macadamia nut; Macadamia nut butter; Peanut; Peanut butter; Pecan; Pecan butter; Pine nut; Pistachio; Pistachio butter; Poppy seed; Pumpkin seed; Sesame seed; Sunflower seed; Sunflower seed butter; Tahini; Walnut; Walnut butter
    """

    private static let herbAndFlavorNames = """
    Allspice; Anise; Basil; Bay leaf flavor; Black pepper; Caraway; Cardamom; Celery leaf; Chervil; Chive; Cilantro; Cinnamon; Clove; Coriander; Cumin; Curry leaf; Dill; Fennel frond; Fenugreek; Galangal; Garlic powder; Ginger; Lemon balm; Lemongrass; Marjoram; Mint; Nutmeg; Oregano; Paprika; Parsley; Rosemary; Sage; Saffron; Spearmint; Tarragon; Thyme; Turmeric; Vanilla; Za'atar herb blend
    """

    private static let preparedFoodNames = """
    Apple oatmeal; Avocado toast; Baked potato; Bean burger; Bean dip; Beef stew; Broccoli fritter; Chicken soup; Chicken vegetable stew; Chickpea pasta; Corn porridge; Egg fried rice; Falafel; Fish cake; French toast; Fruit smoothie bowl; Gnocchi; Green pea soup; Honey; Lentil soup; Macaroni and cheese; Mashed potato; Meat loaf; Millet porridge; Minestrone; Mung dal; Oat pancake; Pasta with tomato sauce; Peanut sauce; Pumpkin soup; Quesadilla; Rice and beans; Rice pudding; Risotto; Salmon cake; Shepherd's pie; Soft taco; Spinach pancake; Sweet potato fritter; Tofu scramble; Tomato soup; Turkey chili; Vegetable curry; Vegetable soup; Waffle; Yogurt parfait
    """
}
