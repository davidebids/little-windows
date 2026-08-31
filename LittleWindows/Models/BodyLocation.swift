import Foundation

enum BodyAnatomyLayer: String, Codable, CaseIterable, Identifiable {
    case bodyAreas
    case muscles
    case joints
    case nerves
    case organs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyAreas: "Body Areas"
        case .muscles: "Muscles"
        case .joints: "Bones & Joints"
        case .nerves: "Nerves"
        case .organs: "Organs"
        }
    }

    var systemImage: String {
        switch self {
        case .bodyAreas: "figure.stand"
        case .muscles: "figure.strengthtraining.traditional"
        case .joints: "figure.walk.motion"
        case .nerves: "bolt.horizontal.circle"
        case .organs: "heart.fill"
        }
    }
}

enum BodyRegionFilter: String, Codable, CaseIterable, Identifiable {
    case all
    case headAndNeck
    case torso
    case armsAndHands
    case legsAndFeet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "Full Body"
        case .headAndNeck: "Head & Neck"
        case .torso: "Torso"
        case .armsAndHands: "Arms & Hands"
        case .legsAndFeet: "Legs & Feet"
        }
    }
}

enum BodyLocationPattern: String, Codable, CaseIterable, Identifiable {
    case spot
    case multiple
    case radiating
    case diffuse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spot: "Spot"
        case .multiple: "Multiple"
        case .radiating: "Radiates"
        case .diffuse: "Diffuse"
        }
    }

    var instruction: String {
        switch self {
        case .spot: "Choose the single area that best matches."
        case .multiple: "Choose up to four separate areas."
        case .radiating: "Choose the starting point, then add the path in order."
        case .diffuse: "Choose the broader area where it feels widespread."
        }
    }
}

enum BodySide: String, Codable, Hashable {
    case center
    case left
    case right
    case bilateral
}

enum BodyModelVariant: String, Codable, Hashable {
    case male
    case female
    case neutral

    init(profileSex: ProfileSex) {
        switch profileSex {
        case .male: self = .male
        case .female: self = .female
        case .unknown: self = .neutral
        }
    }

    var displayName: String {
        switch self {
        case .male: "Male anatomy"
        case .female: "Female anatomy"
        case .neutral: "Common anatomy"
        }
    }
}

struct BodyAnatomyStructure: Identifiable, Hashable {
    let id: String
    let displayName: String
    let layer: BodyAnatomyLayer
    let region: BodyRegionFilter
    let side: BodySide
    let supportedVariants: Set<BodyModelVariant>

    init(
        id: String,
        displayName: String,
        layer: BodyAnatomyLayer,
        region: BodyRegionFilter,
        side: BodySide = .center,
        supportedVariants: Set<BodyModelVariant> = [.male, .female, .neutral]
    ) {
        self.id = id
        self.displayName = displayName
        self.layer = layer
        self.region = region
        self.side = side
        self.supportedVariants = supportedVariants
    }

    func isAvailable(for variant: BodyModelVariant) -> Bool {
        supportedVariants.contains(variant)
    }
}

enum BodyAnatomyCatalog {
    static let structures: [BodyAnatomyStructure] = [
        structure("body.head", "Head", .bodyAreas, .headAndNeck),
        structure("body.face", "Face", .bodyAreas, .headAndNeck),
        structure("body.neck", "Neck", .bodyAreas, .headAndNeck),
        structure("body.chest", "Chest", .bodyAreas, .torso),
        structure("body.upperBack", "Upper back", .bodyAreas, .torso),
        structure("body.abdomen", "Abdomen", .bodyAreas, .torso),
        structure("body.lowerBack", "Lower back", .bodyAreas, .torso),
        structure("body.pelvis", "Pelvis", .bodyAreas, .torso),
        paired("body.shoulder", "Shoulder", .bodyAreas, .armsAndHands),
        paired("body.upperArm", "Upper arm", .bodyAreas, .armsAndHands),
        paired("body.elbow", "Elbow", .bodyAreas, .armsAndHands),
        paired("body.forearm", "Forearm", .bodyAreas, .armsAndHands),
        paired("body.wrist", "Wrist", .bodyAreas, .armsAndHands),
        paired("body.hand", "Hand", .bodyAreas, .armsAndHands),
        paired("body.thumb", "Thumb", .bodyAreas, .armsAndHands),
        paired("body.indexFinger", "Index finger", .bodyAreas, .armsAndHands),
        paired("body.middleFinger", "Middle finger", .bodyAreas, .armsAndHands),
        paired("body.ringFinger", "Ring finger", .bodyAreas, .armsAndHands),
        paired("body.littleFinger", "Little finger", .bodyAreas, .armsAndHands),
        paired("body.hip", "Hip", .bodyAreas, .legsAndFeet),
        paired("body.buttock", "Buttock", .bodyAreas, .legsAndFeet),
        paired("body.thigh", "Thigh", .bodyAreas, .legsAndFeet),
        paired("body.posteriorThigh", "Back of thigh", .bodyAreas, .legsAndFeet),
        paired("body.knee", "Knee", .bodyAreas, .legsAndFeet),
        paired("body.lowerLeg", "Lower leg", .bodyAreas, .legsAndFeet),
        paired("body.calf", "Calf", .bodyAreas, .legsAndFeet),
        paired("body.ankle", "Ankle", .bodyAreas, .legsAndFeet),
        paired("body.foot", "Foot", .bodyAreas, .legsAndFeet),
        paired("body.heel", "Heel", .bodyAreas, .legsAndFeet),
        paired("body.topOfFoot", "Top of foot", .bodyAreas, .legsAndFeet),
        paired("body.sole", "Sole", .bodyAreas, .legsAndFeet),
        paired("body.arch", "Arch", .bodyAreas, .legsAndFeet),
        paired("body.ballOfFoot", "Ball of foot", .bodyAreas, .legsAndFeet),
        paired("body.greatToe", "Big toe", .bodyAreas, .legsAndFeet),
        paired("body.secondToe", "Second toe", .bodyAreas, .legsAndFeet),
        paired("body.middleToe", "Middle toe", .bodyAreas, .legsAndFeet),
        paired("body.fourthToe", "Fourth toe", .bodyAreas, .legsAndFeet),
        paired("body.littleToe", "Little toe", .bodyAreas, .legsAndFeet),

        structure("muscle.trapezius", "Trapezius", .muscles, .torso, side: .bilateral),
        structure("muscle.pectorals", "Pectoral muscles", .muscles, .torso, side: .bilateral),
        structure("muscle.abdominals", "Abdominal muscles", .muscles, .torso, side: .bilateral),
        structure("muscle.lowerBack", "Lower-back muscles", .muscles, .torso, side: .bilateral),
        paired("muscle.deltoid", "Deltoid", .muscles, .armsAndHands),
        paired("muscle.biceps", "Biceps", .muscles, .armsAndHands),
        paired("muscle.triceps", "Triceps", .muscles, .armsAndHands),
        paired("muscle.forearm", "Forearm muscles", .muscles, .armsAndHands),
        paired("muscle.hand", "Hand muscles and tendons", .muscles, .armsAndHands),
        paired("muscle.gluteal", "Gluteal muscles", .muscles, .legsAndFeet),
        paired("muscle.quadriceps", "Quadriceps", .muscles, .legsAndFeet),
        paired("muscle.hamstrings", "Hamstrings", .muscles, .legsAndFeet),
        paired("muscle.calf", "Calf muscles", .muscles, .legsAndFeet),
        paired("muscle.achilles", "Achilles tendon", .muscles, .legsAndFeet),
        paired("muscle.foot", "Foot muscles and tendons", .muscles, .legsAndFeet),

        structure("joint.cervicalSpine", "Cervical spine", .joints, .headAndNeck),
        structure("joint.ribCage", "Rib cage", .joints, .torso),
        structure("joint.lumbarSpine", "Lumbar spine", .joints, .torso),
        paired("joint.shoulder", "Shoulder joint", .joints, .armsAndHands),
        paired("joint.elbow", "Elbow joint", .joints, .armsAndHands),
        paired("joint.wrist", "Wrist joint", .joints, .armsAndHands),
        paired("joint.thumb", "Thumb bones and joints", .joints, .armsAndHands),
        paired("joint.indexFinger", "Index-finger bones and joints", .joints, .armsAndHands),
        paired("joint.middleFinger", "Middle-finger bones and joints", .joints, .armsAndHands),
        paired("joint.ringFinger", "Ring-finger bones and joints", .joints, .armsAndHands),
        paired("joint.littleFinger", "Little-finger bones and joints", .joints, .armsAndHands),
        paired("joint.sacroiliac", "Sacroiliac joint", .joints, .torso),
        paired("joint.hip", "Hip joint", .joints, .legsAndFeet),
        paired("joint.femur", "Femur (thigh bone)", .joints, .legsAndFeet),
        paired("joint.knee", "Knee joint", .joints, .legsAndFeet),
        paired("joint.shin", "Shin bones (tibia and fibula)", .joints, .legsAndFeet),
        paired("joint.ankle", "Ankle joint", .joints, .legsAndFeet),
        paired("joint.heel", "Heel bone", .joints, .legsAndFeet),
        paired("joint.midfoot", "Midfoot bones and joints", .joints, .legsAndFeet),
        paired("joint.greatToe", "Big-toe bones and joints", .joints, .legsAndFeet),
        paired("joint.secondToe", "Second-toe bones and joints", .joints, .legsAndFeet),
        paired("joint.middleToe", "Middle-toe bones and joints", .joints, .legsAndFeet),
        paired("joint.fourthToe", "Fourth-toe bones and joints", .joints, .legsAndFeet),
        paired("joint.littleToe", "Little-toe bones and joints", .joints, .legsAndFeet),

        paired("nerve.trigeminal", "Trigeminal nerve", .nerves, .headAndNeck),
        paired("nerve.median", "Median nerve", .nerves, .armsAndHands),
        paired("nerve.ulnar", "Ulnar nerve", .nerves, .armsAndHands),
        paired("nerve.lumbar", "Lumbar nerves", .nerves, .torso),
        paired("nerve.femoral", "Femoral nerve", .nerves, .legsAndFeet),
        paired("nerve.sciatic", "Sciatic nerve", .nerves, .legsAndFeet),
        paired("nerve.tibial", "Tibial nerve", .nerves, .legsAndFeet),
        paired("nerve.fibular", "Fibular nerve", .nerves, .legsAndFeet),
        paired("nerve.plantar", "Plantar nerves", .nerves, .legsAndFeet),

        structure("organ.brain", "Brain", .organs, .headAndNeck),
        paired("organ.lung", "Lung", .organs, .torso),
        structure("organ.heart", "Heart", .organs, .torso),
        structure("organ.liver", "Liver", .organs, .torso),
        structure("organ.stomach", "Stomach", .organs, .torso),
        paired("organ.kidney", "Kidney", .organs, .torso),
        structure("organ.intestines", "Intestines", .organs, .torso),
        structure("organ.bladder", "Bladder", .organs, .torso),
        structure(
            "organ.uterus",
            "Uterus",
            .organs,
            .torso,
            supportedVariants: [.female]
        ),
        paired(
            "organ.ovary",
            "Ovary",
            .organs,
            .torso,
            supportedVariants: [.female]
        ),
        structure(
            "organ.prostate",
            "Prostate",
            .organs,
            .torso,
            supportedVariants: [.male]
        )
    ].flatMap { $0 }

    private static let structuresByID = Dictionary(
        uniqueKeysWithValues: structures.map { ($0.id, $0) }
    )

    static func structure(id: String) -> BodyAnatomyStructure? {
        structuresByID[id]
    }

    static func structures(
        layer: BodyAnatomyLayer,
        region: BodyRegionFilter,
        variant: BodyModelVariant,
        searchText: String = ""
    ) -> [BodyAnatomyStructure] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return structures.filter { structure in
            structure.layer == layer
                && (region == .all || structure.region == region)
                && structure.isAvailable(for: variant)
                && (query.isEmpty || structure.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    private static func structure(
        _ id: String,
        _ name: String,
        _ layer: BodyAnatomyLayer,
        _ region: BodyRegionFilter,
        side: BodySide = .center,
        supportedVariants: Set<BodyModelVariant> = [.male, .female, .neutral]
    ) -> [BodyAnatomyStructure] {
        [BodyAnatomyStructure(
            id: id,
            displayName: name,
            layer: layer,
            region: region,
            side: side,
            supportedVariants: supportedVariants
        )]
    }

    private static func paired(
        _ id: String,
        _ name: String,
        _ layer: BodyAnatomyLayer,
        _ region: BodyRegionFilter,
        supportedVariants: Set<BodyModelVariant> = [.male, .female, .neutral]
    ) -> [BodyAnatomyStructure] {
        [
            BodyAnatomyStructure(
                id: "\(id).left",
                displayName: "Left \(name.lowercased())",
                layer: layer,
                region: region,
                side: .left,
                supportedVariants: supportedVariants
            ),
            BodyAnatomyStructure(
                id: "\(id).right",
                displayName: "Right \(name.lowercased())",
                layer: layer,
                region: region,
                side: .right,
                supportedVariants: supportedVariants
            )
        ]
    }
}

struct BodyLocationSelection: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var structureID: String
    var layerRawValue: String
    var sideRawValue: String
    var displayNameSnapshot: String

    init(
        id: UUID = UUID(),
        structure: BodyAnatomyStructure
    ) {
        self.id = id
        structureID = structure.id
        layerRawValue = structure.layer.rawValue
        sideRawValue = structure.side.rawValue
        displayNameSnapshot = structure.displayName
    }

    init(
        id: UUID = UUID(),
        structureID: String,
        layerRawValue: String,
        sideRawValue: String = BodySide.center.rawValue,
        displayNameSnapshot: String
    ) {
        self.id = id
        self.structureID = structureID
        self.layerRawValue = layerRawValue
        self.sideRawValue = sideRawValue
        self.displayNameSnapshot = displayNameSnapshot
    }

    var layer: BodyAnatomyLayer {
        BodyAnatomyLayer(rawValue: layerRawValue) ?? .bodyAreas
    }

    var side: BodySide {
        BodySide(rawValue: sideRawValue) ?? .center
    }

    var displayName: String {
        if let current = BodyAnatomyCatalog.structure(id: structureID) {
            return current.displayName
        }
        let snapshot = displayNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.isEmpty ? structureID : snapshot
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case structureID
        case layerRawValue
        case sideRawValue
        case displayNameSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        structureID = try container.decode(String.self, forKey: .structureID)
        layerRawValue = try container.decodeIfPresent(String.self, forKey: .layerRawValue)
            ?? BodyAnatomyLayer.bodyAreas.rawValue
        sideRawValue = try container.decodeIfPresent(String.self, forKey: .sideRawValue)
            ?? BodySide.center.rawValue
        displayNameSnapshot = try container.decodeIfPresent(
            String.self,
            forKey: .displayNameSnapshot
        ) ?? structureID
    }
}

enum BodyLocationToggleResult: Equatable {
    case added
    case removed
    case replaced
    case limitReached
}

struct BodyLocationRecord: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maximumSelections = 4

    var schemaVersion: Int
    var modelVariantRawValue: String
    var patternRawValue: String
    var selections: [BodyLocationSelection]
    var customText: String?

    init(
        profileSex: ProfileSex,
        pattern: BodyLocationPattern = .spot,
        selections: [BodyLocationSelection] = [],
        customText: String? = nil
    ) {
        self.init(
            modelVariant: BodyModelVariant(profileSex: profileSex),
            pattern: pattern,
            selections: selections,
            customText: customText
        )
    }

    init(
        modelVariant: BodyModelVariant,
        pattern: BodyLocationPattern = .spot,
        selections: [BodyLocationSelection] = [],
        customText: String? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        modelVariantRawValue = modelVariant.rawValue
        patternRawValue = pattern.rawValue
        self.selections = Array(selections.prefix(Self.maximumSelections))
        self.customText = Self.cleaned(customText)
        normalizeForPattern()
    }

    var modelVariant: BodyModelVariant {
        get { BodyModelVariant(rawValue: modelVariantRawValue) ?? .neutral }
        set { modelVariantRawValue = newValue.rawValue }
    }

    var pattern: BodyLocationPattern {
        get { BodyLocationPattern(rawValue: patternRawValue) ?? .spot }
        set {
            patternRawValue = newValue.rawValue
            normalizeForPattern()
        }
    }

    var hasStructuredSelections: Bool {
        !selections.isEmpty
    }

    var hasValue: Bool {
        hasStructuredSelections || pattern == .diffuse || Self.cleaned(customText) != nil
    }

    var summary: String? {
        let names = selections.map(\.displayName)
        let structuredSummary: String?
        switch pattern {
        case .spot:
            structuredSummary = names.first
        case .multiple:
            structuredSummary = names.isEmpty ? nil : names.joined(separator: " · ")
        case .radiating:
            structuredSummary = names.isEmpty
                ? nil
                : "Radiates: \(names.joined(separator: " → "))"
        case .diffuse:
            structuredSummary = names.isEmpty ? "Diffuse" : "Diffuse: \(names.joined(separator: " · "))"
        }

        let note = Self.cleaned(customText)
        switch (structuredSummary, note) {
        case let (summary?, note?): return "\(summary) · \(note)"
        case let (summary?, nil): return summary
        case let (nil, note?): return note
        case (nil, nil): return nil
        }
    }

    mutating func toggle(_ structure: BodyAnatomyStructure) -> BodyLocationToggleResult {
        if let index = selections.firstIndex(where: { $0.structureID == structure.id }) {
            selections.remove(at: index)
            return .removed
        }

        let selection = BodyLocationSelection(structure: structure)
        if pattern == .spot {
            let result: BodyLocationToggleResult = selections.isEmpty ? .added : .replaced
            selections = [selection]
            return result
        }
        guard selections.count < Self.maximumSelections else {
            return .limitReached
        }
        selections.append(selection)
        return .added
    }

    mutating func remove(selectionID: UUID) {
        selections.removeAll { $0.id == selectionID }
    }

    mutating func clear() {
        selections = []
        customText = nil
        patternRawValue = BodyLocationPattern.spot.rawValue
    }

    mutating func adoptProfileSex(_ profileSex: ProfileSex) {
        let updatedVariant = BodyModelVariant(profileSex: profileSex)
        modelVariant = updatedVariant
        selections.removeAll { selection in
            guard let structure = BodyAnatomyCatalog.structure(id: selection.structureID) else {
                return false
            }
            return !structure.isAvailable(for: updatedVariant)
        }
    }

    mutating func normalizeForPattern() {
        selections = Array(selections.prefix(Self.maximumSelections))
        if pattern == .spot, selections.count > 1 {
            selections = Array(selections.prefix(1))
        }
        customText = Self.cleaned(customText)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case modelVariantRawValue
        case patternRawValue
        case selections
        case customText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        modelVariantRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .modelVariantRawValue
        ) ?? BodyModelVariant.neutral.rawValue
        patternRawValue = try container.decodeIfPresent(String.self, forKey: .patternRawValue)
            ?? BodyLocationPattern.spot.rawValue
        selections = Array(
            (try container.decodeIfPresent([BodyLocationSelection].self, forKey: .selections) ?? [])
                .prefix(Self.maximumSelections)
        )
        customText = Self.cleaned(try container.decodeIfPresent(String.self, forKey: .customText))
        normalizeForPattern()
    }
}
