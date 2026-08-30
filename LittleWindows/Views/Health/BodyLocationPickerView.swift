import Combine
import RealityKit
import SwiftUI
import UIKit

struct BodyLocationEditorButton: View {
    let title: String
    let summary: String?
    let selectionCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(summary ?? "Not selected")
        .accessibilityHint("Opens the interactive body location picker")
    }

    private var buttonContent: some View {
        HStack(spacing: 13) {
            bodyIcon
            buttonLabels
            Spacer(minLength: 8)
            selectionBadge
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var bodyIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.9), .cyan.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "figure.stand")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    private var buttonLabels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summary ?? "Tap the 3D body to choose")
                .font(.caption)
                .foregroundStyle(summary == nil ? Color.secondary : Color.indigo)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if selectionCount > 0 {
            Text("\(selectionCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.indigo, in: Circle())
        }
    }
}

struct BodyLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let profileSex: ProfileSex
    let onSave: (BodyLocationRecord) -> Void

    @State private var record: BodyLocationRecord
    @State private var activeLayer: BodyAnatomyLayer
    @State private var regionFilter: BodyRegionFilter = .all
    @State private var handDetailFocus: BodyHandDetailFocus = .both
    @State private var footDetailFocus: BodyFootDetailFocus = .both
    @State private var orientation: BodyViewOrientation = .front
    @State private var resetToken = UUID()
    @State private var searchText = ""
    @State private var isBrowseExpanded = false
    @State private var showingSelectionLimit = false

    init(
        profileSex: ProfileSex,
        initialRecord: BodyLocationRecord,
        initialLayer: BodyAnatomyLayer? = nil,
        onSave: @escaping (BodyLocationRecord) -> Void
    ) {
        self.profileSex = profileSex
        self.onSave = onSave
        var startingRecord = initialRecord
        startingRecord.adoptProfileSex(profileSex)
        _record = State(initialValue: startingRecord)
        _activeLayer = State(
            initialValue: initialLayer ?? startingRecord.selections.first?.layer ?? .bodyAreas
        )
        let initialStructure = startingRecord.selections.first.flatMap {
            BodyAnatomyCatalog.structure(id: $0.structureID)
        }
        _orientation = State(
            initialValue: initialStructure.map(Self.preferredOrientation(for:)) ?? .front
        )
    }

    private var availableStructures: [BodyAnatomyStructure] {
        BodyAnatomyCatalog.structures(
            layer: activeLayer,
            region: regionFilter,
            variant: record.modelVariant,
            searchText: searchText
        )
    }

    private var availableRegions: [BodyRegionFilter] {
        [.all] + BodyRegionFilter.allCases.filter { region in
            region != .all && !BodyAnatomyCatalog.structures(
                layer: activeLayer,
                region: region,
                variant: record.modelVariant
            ).isEmpty
        }
    }

    private var selectedIDs: Set<String> {
        Set(record.selections.map(\.structureID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    patternPicker
                    layerPicker
                    regionPicker
                    visualizationCard
                    selectionSection
                    browseSection
                    customTextSection
                    trackingFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Where is it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        record.normalizeForPattern()
                        onSave(record)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("body-location.done")
                }
            }
            .alert("Four locations maximum", isPresented: $showingSelectionLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Remove a location before choosing another one.")
            }
        }
    }

    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How does it feel distributed?")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BodyLocationPattern.allCases) { pattern in
                        filterChip(
                            title: pattern.displayName,
                            systemImage: patternSystemImage(pattern),
                            selected: record.pattern == pattern,
                            tint: .indigo
                        ) {
                            withAnimation(.snappy) {
                                record.pattern = pattern
                            }
                        }
                        .accessibilityIdentifier("body-location.pattern.\(pattern.rawValue)")
                    }
                }
            }
            .accessibilityIdentifier("body-location.region-scroll")
            Text(record.pattern.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Anatomy layer")
                    .font(.headline)
                Spacer()
                Text(record.modelVariant.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BodyAnatomyLayer.allCases) { layer in
                        filterChip(
                            title: layer.displayName,
                            systemImage: layer.systemImage,
                            selected: activeLayer == layer,
                            tint: layer.tint
                        ) {
                            withAnimation(.snappy) {
                                selectLayer(layer)
                            }
                        }
                        .accessibilityIdentifier("body-location.layer.\(layer.rawValue)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableRegions) { region in
                        filterChip(
                            title: region.displayName,
                            systemImage: nil,
                            selected: regionFilter == region,
                            tint: activeLayer.tint
                        ) {
                            withAnimation(.snappy) {
                                regionFilter = region
                                if region != .armsAndHands {
                                    handDetailFocus = .both
                                }
                                if region != .legsAndFeet {
                                    footDetailFocus = .both
                                }
                            }
                        }
                        .accessibilityIdentifier("body-location.region.\(region.rawValue)")
                    }
                }
            }
            if regionFilter == .armsAndHands {
                Picker("Hand detail", selection: $handDetailFocus) {
                    ForEach(BodyHandDetailFocus.allCases) { focus in
                        Text(focus.displayName).tag(focus)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("body-location.hand-focus")
            } else if regionFilter == .legsAndFeet {
                Picker("Foot detail", selection: $footDetailFocus) {
                    ForEach(BodyFootDetailFocus.allCases) { focus in
                        Text(focus.displayName).tag(focus)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("body-location.foot-focus")
            }
        }
    }

    private var visualizationCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.012, green: 0.02, blue: 0.065),
                            Color(red: 0.035, green: 0.035, blue: 0.13),
                            activeLayer.tint.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            scienceBackdrop

            BodyVisualizationView(
                variant: record.modelVariant,
                activeLayer: activeLayer,
                regionFilter: regionFilter,
                handDetailFocus: handDetailFocus,
                footDetailFocus: footDetailFocus,
                orientation: orientation,
                selectedStructureIDs: selectedIDs,
                resetToken: resetToken,
                reduceMotion: reduceMotion,
                onSelect: { structureID in
                    selectStructure(id: structureID, updateOrientation: false)
                }
            )
            .accessibilityElement()
            .accessibilityLabel("Interactive 3D body")
            .accessibilityHint("Tap a body region, or use the anatomy list below")
            .accessibilityIdentifier("body-location.visualization")

            VStack {
                HStack {
                    orientationControl
                    Spacer()
                    Button {
                        resetToken = UUID()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.3), in: Circle())
                    }
                    .accessibilityLabel("Reset body view")
                    .accessibilityIdentifier("body-location.reset-view")
                }
                Spacer()
                HStack {
                    Label("Drag to rotate", systemImage: "rotate.3d")
                    Spacer()
                    Label("Pinch to zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
            }
            .padding(14)
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: activeLayer.tint.opacity(0.18), radius: 22, y: 10)
    }

    private var scienceBackdrop: some View {
        ZStack {
            Circle()
                .fill(activeLayer.tint.opacity(0.2))
                .frame(width: 210, height: 210)
                .blur(radius: 70)
                .offset(x: 120, y: 155)
            Circle()
                .fill(Color.indigo.opacity(0.2))
                .frame(width: 190, height: 190)
                .blur(radius: 72)
                .offset(x: -125, y: -155)
            Circle()
                .fill(Color.white.opacity(0.055))
                .frame(width: 115, height: 115)
                .blur(radius: 42)

            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index.isMultiple(of: 3) ? 0.32 : 0.16))
                    .frame(
                        width: index.isMultiple(of: 4) ? 2.5 : 1.5,
                        height: index.isMultiple(of: 4) ? 2.5 : 1.5
                    )
                    .offset(
                        x: CGFloat((index * 67) % 290) - 145,
                        y: CGFloat((index * 97) % 360) - 180
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var orientationControl: some View {
        HStack(spacing: 3) {
            ForEach(BodyViewOrientation.allCases) { value in
                Button(orientationLabel(for: value)) {
                    orientation = value
                }
                .font(.caption.weight(.bold))
                // The selected pill is always white, so semantic `.primary`
                // becomes white-on-white in dark mode. Keep its contrast tied
                // to the pill instead of the surrounding color scheme.
                .foregroundStyle(orientation == value ? Color.black.opacity(0.88) : .white.opacity(0.78))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    orientation == value ? Color.white : Color.clear,
                    in: Capsule()
                )
                .buttonStyle(.plain)
                .accessibilityIdentifier("body-location.orientation.\(value.rawValue)")
                .accessibilityValue(
                    orientation == value ? "Selected" : "Not selected"
                )
            }
        }
        .padding(3)
        .background(.black.opacity(0.28), in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func orientationLabel(for value: BodyViewOrientation) -> String {
        guard regionFilter == .legsAndFeet, footDetailFocus != .both else {
            return value.displayName
        }
        return value == .front ? "Side" : "Sole"
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.pattern == .radiating ? "Path order" : "Selected locations")
                    .font(.headline)
                Spacer()
                if record.hasValue {
                    Button("Clear") {
                        withAnimation { record.clear() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if record.selections.isEmpty {
                Label("No body location selected", systemImage: "hand.tap")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(record.selections.enumerated()), id: \.element.id) { index, selection in
                        HStack(spacing: 11) {
                            Button {
                                focus(on: selection)
                            } label: {
                                HStack(spacing: 11) {
                                    if record.pattern == .radiating {
                                        Text("\(index + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 25, height: 25)
                                            .background(selection.layer.tint, in: Circle())
                                    } else {
                                        Image(systemName: selection.layer.systemImage)
                                            .foregroundStyle(selection.layer.tint)
                                            .frame(width: 25)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selection.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(selection.layer.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Show \(selection.displayName) on the body")
                            Button {
                                withAnimation { record.remove(selectionID: selection.id) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(selection.displayName)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(selection.layer.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityIdentifier("body-location.selection.\(selection.structureID)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var browseSection: some View {
        DisclosureGroup(isExpanded: $isBrowseExpanded) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search \(activeLayer.displayName.lowercased())", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if availableStructures.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(minHeight: 110)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(availableStructures) { structure in
                            let isSelected = selectedIDs.contains(structure.id)
                            Button {
                                selectStructure(id: structure.id)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? activeLayer.tint : .secondary)
                                    Text(structure.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if structure.side != .center {
                                        Text(structure.side == .left ? "L" : structure.side == .right ? "R" : "L/R")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 8)
                                .frame(minHeight: 42)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                            .accessibilityIdentifier("body-location.structure.\(structure.id)")
                        }
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Browse \(activeLayer.displayName)", systemImage: "list.bullet")
                .font(.headline)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var customTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional detail")
                .font(.headline)
            TextField(
                "Type a location or clarification",
                text: Binding(
                    get: { record.customText ?? "" },
                    set: { record.customText = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("body-location.custom-detail")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackingFooter: some View {
        Label(
            "Anatomy layers help describe a recorded location. They are not a diagnostic tool and do not determine what caused a symptom or pain.",
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterChip(
        title: String,
        systemImage: String?,
        selected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(selected ? tint : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                if !selected {
                    Capsule().stroke(.secondary.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func patternSystemImage(_ pattern: BodyLocationPattern) -> String {
        switch pattern {
        case .spot: "dot.circle"
        case .multiple: "circle.grid.2x2"
        case .radiating: "arrow.triangle.branch"
        case .diffuse: "circle.dotted"
        }
    }

    private func selectStructure(
        id: String,
        updateOrientation: Bool = true
    ) {
        guard let structure = BodyAnatomyCatalog.structure(id: id),
              structure.isAvailable(for: record.modelVariant) else { return }
        let result = record.toggle(structure)
        if result == .limitReached {
            showingSelectionLimit = true
        } else if updateOrientation, result == .added || result == .replaced {
            orientation = Self.preferredOrientation(for: structure)
        }
    }

    private func selectLayer(_ layer: BodyAnatomyLayer) {
        activeLayer = layer
        searchText = ""
        let regionIsAvailable = regionFilter == .all || !BodyAnatomyCatalog.structures(
            layer: layer,
            region: regionFilter,
            variant: record.modelVariant
        ).isEmpty
        if !regionIsAvailable {
            regionFilter = .all
        }
    }

    private func focus(on selection: BodyLocationSelection) {
        guard let structure = BodyAnatomyCatalog.structure(id: selection.structureID) else {
            return
        }
        withAnimation(.snappy) {
            activeLayer = structure.layer
            regionFilter = structure.region
            if Self.prefersFootDetail(structure) {
                footDetailFocus = structure.side == .left ? .left : .right
            }
            if Self.prefersHandDetail(structure) {
                handDetailFocus = structure.side == .left ? .left : .right
            }
            orientation = Self.preferredOrientation(for: structure)
            searchText = ""
        }
    }

    private static func preferredOrientation(
        for structure: BodyAnatomyStructure
    ) -> BodyViewOrientation {
        let backFacingIDs = [
            "body.upperBack", "body.lowerBack", "body.buttock", "body.posteriorThigh",
            "body.calf", "muscle.trapezius", "muscle.lowerBack", "muscle.triceps",
            "muscle.gluteal", "muscle.hamstrings", "muscle.calf", "joint.cervicalSpine",
            "joint.lumbarSpine", "joint.sacroiliac", "nerve.ulnar", "nerve.lumbar",
            "nerve.sciatic", "body.sole", "body.arch", "body.ballOfFoot",
            "nerve.plantar"
        ]
        return backFacingIDs.contains { structure.id.hasPrefix($0) } ? .back : .front
    }

    private static func prefersHandDetail(_ structure: BodyAnatomyStructure) -> Bool {
        guard structure.region == .armsAndHands,
              structure.side == .left || structure.side == .right else { return false }
        return ["hand", "wrist", "thumb", "finger", "median", "ulnar"].contains {
            structure.id.localizedCaseInsensitiveContains($0)
        }
    }

    private static func prefersFootDetail(_ structure: BodyAnatomyStructure) -> Bool {
        guard structure.region == .legsAndFeet,
              structure.side == .left || structure.side == .right else { return false }
        return [
            "ankle", "foot", "heel", "sole", "arch", "toe", "achilles",
            "midfoot", "tibial", "fibular", "plantar"
        ].contains { structure.id.localizedCaseInsensitiveContains($0) }
    }
}

enum BodyViewOrientation: String, CaseIterable, Identifiable {
    case front
    case back

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BodyHandDetailFocus: String, CaseIterable, Identifiable {
    case both
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both: "Both arms"
        case .left: "Left hand"
        case .right: "Right hand"
        }
    }
}

enum BodyFootDetailFocus: String, CaseIterable, Identifiable {
    case both
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both: "Both legs"
        case .left: "Left foot"
        case .right: "Right foot"
        }
    }
}

private extension BodyAnatomyLayer {
    var tint: Color {
        switch self {
        case .bodyAreas: .cyan
        case .muscles: .pink
        case .joints: .mint
        case .nerves: .yellow
        case .organs: .purple
        }
    }

    var uiColor: UIColor {
        switch self {
        case .bodyAreas: UIColor(red: 0.38, green: 0.78, blue: 1.0, alpha: 1)
        case .muscles: UIColor(red: 1.0, green: 0.31, blue: 0.48, alpha: 1)
        case .joints: UIColor(red: 0.57, green: 1.0, blue: 0.78, alpha: 1)
        case .nerves: UIColor(red: 1.0, green: 0.82, blue: 0.23, alpha: 1)
        case .organs: UIColor(red: 0.72, green: 0.43, blue: 1.0, alpha: 1)
        }
    }
}

#if false
private struct ProceduralBodyVisualizationView: UIViewRepresentable {
    let variant: BodyModelVariant
    let activeLayer: BodyAnatomyLayer
    let regionFilter: BodyRegionFilter
    let orientation: BodyViewOrientation
    let selectedStructureIDs: Set<String>
    let resetToken: UUID
    let reduceMotion: Bool
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(in: uiView)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BodyVisualizationView

        private weak var arView: ARView?
        private var animationSubscription: Cancellable?
        private var interactionRoot = Entity()
        private var breathingRoot = Entity()
        private var surfaceRoot = Entity()
        private var ghostRoot = Entity()
        private var layerRoots: [BodyAnatomyLayer: Entity] = [:]
        private var entitiesByStructureID: [String: [ModelEntity]] = [:]
        private var baseScales: [ObjectIdentifier: SIMD3<Float>] = [:]
        private var particles: [(entity: ModelEntity, phase: Float, origin: SIMD3<Float>)] = []

        private var currentVariant: BodyModelVariant?
        private var currentLayer: BodyAnatomyLayer?
        private var currentRegion: BodyRegionFilter?
        private var currentOrientation: BodyViewOrientation?
        private var currentSelectionIDs: Set<String> = []
        private var currentResetToken: UUID?

        private var yaw: Float = 0
        private var pitch: Float = 0
        private var zoom: Float = 1
        private var gestureStartYaw: Float = 0
        private var gestureStartPitch: Float = 0
        private var gestureStartZoom: Float = 1
        private var elapsed: Float = 0

        init(parent: BodyVisualizationView) {
            self.parent = parent
        }

        func install(in view: ARView) {
            arView = view
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            tap.delegate = self
            pan.delegate = self
            pinch.delegate = self
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            rebuildScene(in: view)
            synchronize(in: view)
        }

        func stop() {
            animationSubscription?.cancel()
            animationSubscription = nil
        }

        func synchronize(in view: ARView) {
            if currentVariant != parent.variant {
                rebuildScene(in: view)
            }

            if currentLayer != parent.activeLayer {
                currentLayer = parent.activeLayer
                updateLayerVisibility()
                updateMaterials()
            }
            if currentSelectionIDs != parent.selectedStructureIDs {
                currentSelectionIDs = parent.selectedStructureIDs
                updateMaterials()
            }
            if currentOrientation != parent.orientation {
                currentOrientation = parent.orientation
                yaw = parent.orientation == .front ? 0 : .pi
                applyInteractionTransform(animated: true)
            }
            if currentRegion != parent.regionFilter {
                currentRegion = parent.regionFilter
                updateRegionVisibility()
                applyInteractionTransform(animated: true)
            }
            if currentResetToken != parent.resetToken {
                currentResetToken = parent.resetToken
                yaw = parent.orientation == .front ? 0 : .pi
                pitch = 0
                zoom = 1
                applyInteractionTransform(animated: true)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = arView,
                  let entity = view.entity(at: recognizer.location(in: view)),
                  let structureID = structureID(for: entity) else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            parent.onSelect(structureID)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = arView else { return }
            switch recognizer.state {
            case .began:
                gestureStartYaw = yaw
                gestureStartPitch = pitch
            case .changed:
                let translation = recognizer.translation(in: view)
                yaw = gestureStartYaw + Float(translation.x) * 0.008
                pitch = min(0.32, max(-0.32, gestureStartPitch + Float(translation.y) * 0.0035))
                applyInteractionTransform(animated: false)
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                gestureStartZoom = zoom
            case .changed:
                zoom = min(1.65, max(0.78, gestureStartZoom * Float(recognizer.scale)))
                applyInteractionTransform(animated: false)
            default:
                break
            }
        }

        private func structureID(for entity: Entity?) -> String? {
            var candidate = entity
            while let value = candidate {
                if value.name.hasPrefix("anatomy:") {
                    return String(value.name.dropFirst("anatomy:".count))
                }
                candidate = value.parent
            }
            return nil
        }

        private func rebuildScene(in view: ARView) {
            stop()
            view.scene.anchors.removeAll()
            entitiesByStructureID = [:]
            baseScales = [:]
            particles = []
            layerRoots = [:]

            currentVariant = parent.variant
            currentLayer = nil
            currentRegion = nil
            currentOrientation = nil
            currentSelectionIDs = []

            let anchor = AnchorEntity(world: SIMD3(0, -0.24, -5.15))
            interactionRoot = Entity()
            breathingRoot = Entity()
            surfaceRoot = Entity()
            ghostRoot = Entity()
            interactionRoot.addChild(breathingRoot)
            breathingRoot.addChild(surfaceRoot)
            breathingRoot.addChild(ghostRoot)

            for layer in BodyAnatomyLayer.allCases where layer != .bodyAreas {
                let root = Entity()
                layerRoots[layer] = root
                breathingRoot.addChild(root)
            }

            addParts(
                BodyVisualCatalog.surfaceParts(variant: parent.variant),
                to: surfaceRoot,
                interactive: true,
                ghost: false
            )
            addParts(
                BodyVisualCatalog.surfaceParts(variant: parent.variant),
                to: ghostRoot,
                interactive: false,
                ghost: true
            )
            addParts(BodyVisualCatalog.muscleParts, to: layerRoots[.muscles], interactive: true)
            addParts(BodyVisualCatalog.jointParts, to: layerRoots[.joints], interactive: true)
            addParts(BodyVisualCatalog.nerveParts, to: layerRoots[.nerves], interactive: true)
            addParts(
                BodyVisualCatalog.organParts(variant: parent.variant),
                to: layerRoots[.organs],
                interactive: true
            )

            addFloor(to: anchor)
            addLights(to: anchor)
            addParticles(to: anchor)
            anchor.addChild(interactionRoot)
            view.scene.anchors.append(anchor)

            animationSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.updateAnimation(deltaTime: Float(event.deltaTime))
            }
            updateLayerVisibility()
            updateRegionVisibility()
            updateMaterials()
            applyInteractionTransform(animated: false)
        }

        private func addParts(
            _ parts: [BodyVisualPart],
            to root: Entity?,
            interactive: Bool,
            ghost: Bool = false
        ) {
            guard let root else { return }
            for part in parts {
                guard BodyAnatomyCatalog.structure(id: part.structureID)?.isAvailable(
                    for: parent.variant
                ) == true else { continue }
                let material = makeMaterial(
                    layer: part.layer,
                    structureID: part.structureID,
                    selected: false,
                    ghost: ghost
                )
                let model = ModelEntity(
                    mesh: .generateSphere(radius: 0.5),
                    materials: [material]
                )
                model.name = interactive ? "anatomy:\(part.structureID)" : ""
                model.position = part.center
                model.scale = part.size
                model.orientation = part.rotation
                if interactive {
                    model.generateCollisionShapes(recursive: false)
                    entitiesByStructureID[part.structureID, default: []].append(model)
                    baseScales[ObjectIdentifier(model)] = part.size
                }
                root.addChild(model)
            }
        }

        private func addFloor(to anchor: AnchorEntity) {
            let material = UnlitMaterial(color: UIColor(
                red: 0.28,
                green: 0.52,
                blue: 1,
                alpha: 0.12
            ))
            let floor = ModelEntity(
                mesh: .generatePlane(width: 2.25, depth: 2.25, cornerRadius: 1.1),
                materials: [material]
            )
            floor.position = SIMD3(0, -2.18, 0)
            anchor.addChild(floor)
        }

        private func addLights(to anchor: AnchorEntity) {
            let key = DirectionalLight()
            key.light.intensity = 2_100
            key.orientation = simd_quatf(angle: -0.55, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: -0.6, axis: SIMD3(0, 1, 0))
            anchor.addChild(key)

            let fill = PointLight()
            fill.light.intensity = 1_000
            fill.position = SIMD3(-1.8, 1.5, 2.0)
            anchor.addChild(fill)
        }

        private func addParticles(to anchor: AnchorEntity) {
            let material = UnlitMaterial(color: UIColor(
                red: 0.52,
                green: 0.82,
                blue: 1,
                alpha: 0.72
            ))
            for index in 0..<12 {
                let angle = Float(index) / 12 * .pi * 2
                let origin = SIMD3<Float>(
                    cos(angle) * (1.0 + Float(index % 3) * 0.16),
                    -1.5 + Float(index % 6) * 0.58,
                    sin(angle) * 0.42
                )
                let particle = ModelEntity(
                    mesh: .generateSphere(radius: index.isMultiple(of: 3) ? 0.025 : 0.014),
                    materials: [material]
                )
                particle.position = origin
                anchor.addChild(particle)
                particles.append((particle, angle, origin))
            }
        }

        private func updateLayerVisibility() {
            let layer = parent.activeLayer
            surfaceRoot.isEnabled = layer == .bodyAreas
            ghostRoot.isEnabled = layer != .bodyAreas
            for (candidate, root) in layerRoots {
                root.isEnabled = candidate == layer
            }
        }

        private func updateRegionVisibility() {
            for (structureID, models) in entitiesByStructureID {
                guard let structure = BodyAnatomyCatalog.structure(id: structureID) else { continue }
                let isVisible = parent.regionFilter == .all
                    || structure.region == parent.regionFilter
                for model in models {
                    model.isEnabled = isVisible
                }
            }
        }

        private func updateMaterials() {
            for (structureID, models) in entitiesByStructureID {
                guard let structure = BodyAnatomyCatalog.structure(id: structureID) else { continue }
                let selected = parent.selectedStructureIDs.contains(structureID)
                let material = makeMaterial(
                    layer: structure.layer,
                    structureID: structureID,
                    selected: selected,
                    ghost: false
                )
                for model in models {
                    guard var component = model.model else { continue }
                    component.materials = [material]
                    model.model = component
                }
            }
        }

        private func makeMaterial(
            layer: BodyAnatomyLayer,
            structureID: String,
            selected: Bool,
            ghost: Bool
        ) -> SimpleMaterial {
            let color: UIColor
            let metallic: Bool
            if selected {
                color = UIColor(red: 1, green: 0.2, blue: 0.54, alpha: 1)
                metallic = true
            } else if ghost {
                color = UIColor(red: 0.45, green: 0.78, blue: 1, alpha: 0.075)
                metallic = true
            } else if layer == .organs {
                color = organColor(structureID)
                metallic = false
            } else {
                color = layer.uiColor.withAlphaComponent(layer == .bodyAreas ? 0.9 : 0.94)
                metallic = layer == .joints || layer == .nerves
            }
            return SimpleMaterial(color: color, roughness: 0.32, isMetallic: metallic)
        }

        private func organColor(_ structureID: String) -> UIColor {
            if structureID.contains("heart") { return UIColor(red: 1, green: 0.21, blue: 0.36, alpha: 0.96) }
            if structureID.contains("lung") { return UIColor(red: 0.32, green: 0.82, blue: 0.95, alpha: 0.9) }
            if structureID.contains("liver") { return UIColor(red: 0.62, green: 0.22, blue: 0.4, alpha: 0.96) }
            if structureID.contains("kidney") { return UIColor(red: 0.75, green: 0.28, blue: 0.42, alpha: 0.96) }
            if structureID.contains("brain") { return UIColor(red: 0.94, green: 0.55, blue: 0.76, alpha: 0.96) }
            return UIColor(red: 0.68, green: 0.38, blue: 1, alpha: 0.94)
        }

        private func applyInteractionTransform(animated: Bool) {
            let focus = focusTransform(parent.regionFilter)
            let scale = focus.scale * zoom
            let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
            let transform = Transform(
                scale: SIMD3(repeating: scale),
                rotation: rotation,
                translation: SIMD3(0, focus.verticalOffset, 0)
            )
            if animated, !parent.reduceMotion, let parentEntity = interactionRoot.parent {
                interactionRoot.move(
                    to: transform,
                    relativeTo: parentEntity,
                    duration: 0.38,
                    timingFunction: .easeInOut
                )
            } else {
                interactionRoot.transform = transform
            }
        }

        private func focusTransform(_ region: BodyRegionFilter) -> (scale: Float, verticalOffset: Float) {
            switch region {
            case .all: (1, 0.22)
            case .headAndNeck: (1.62, -1.38)
            case .torso: (1.34, -0.3)
            case .armsAndHands: (1.14, -0.1)
            case .legsAndFeet: (1.18, 0.92)
            }
        }

        private func updateAnimation(deltaTime: Float) {
            elapsed += min(deltaTime, 0.05)
            let motionScale: Float = parent.reduceMotion ? 0 : 1
            let breathing = 1 + sin(elapsed * 1.55) * 0.008 * motionScale
            breathingRoot.scale = SIMD3(1, breathing, 1)

            let pulse = 1 + sin(elapsed * 4.2) * 0.045 * motionScale
            for (structureID, models) in entitiesByStructureID {
                let selected = parent.selectedStructureIDs.contains(structureID)
                for model in models {
                    guard let base = baseScales[ObjectIdentifier(model)] else { continue }
                    model.scale = base * (selected ? pulse : 1)
                }
            }

            for (index, particle) in particles.enumerated() {
                let drift = sin(elapsed * 0.7 + particle.phase) * 0.09 * motionScale
                let orbit = cos(elapsed * 0.45 + particle.phase) * 0.04 * motionScale
                particle.entity.position = particle.origin + SIMD3(orbit, drift, Float(index % 2) * orbit)
            }
        }
    }
}

private struct BodyVisualPart {
    let structureID: String
    let layer: BodyAnatomyLayer
    let center: SIMD3<Float>
    let size: SIMD3<Float>
    let rotation: simd_quatf

    init(
        _ structureID: String,
        _ layer: BodyAnatomyLayer,
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        rotation: simd_quatf = simd_quatf()
    ) {
        self.structureID = structureID
        self.layer = layer
        self.center = center
        self.size = size
        self.rotation = rotation
    }
}

private enum BodyVisualCatalog {
    private static let left: Float = 1
    private static let right: Float = -1

    static func surfaceParts(variant: BodyModelVariant) -> [BodyVisualPart] {
        let chestWidth: Float = variant == .male ? 0.94 : variant == .female ? 0.84 : 0.89
        let shoulderX: Float = variant == .male ? 0.59 : 0.54
        let pelvisWidth: Float = variant == .female ? 0.84 : variant == .male ? 0.72 : 0.78
        var parts: [BodyVisualPart] = [
            part("body.head", .bodyAreas, 0, 1.54, 0, 0.55, 0.67, 0.51),
            part("body.face", .bodyAreas, 0, 1.52, 0.24, 0.41, 0.43, 0.12),
            part("body.neck", .bodyAreas, 0, 1.12, 0, 0.28, 0.28, 0.28),
            part("body.chest", .bodyAreas, 0, 0.7, 0.05, chestWidth, 0.76, 0.44),
            part("body.upperBack", .bodyAreas, 0, 0.7, -0.24, chestWidth * 0.84, 0.62, 0.15),
            part("body.abdomen", .bodyAreas, 0, 0.13, 0.05, 0.69, 0.55, 0.39),
            part("body.lowerBack", .bodyAreas, 0, 0.12, -0.22, 0.62, 0.43, 0.14),
            part("body.pelvis", .bodyAreas, 0, -0.28, 0, pelvisWidth, 0.46, 0.44)
        ]

        for (sideName, sign) in [("left", left), ("right", right)] {
            parts += [
                part("body.shoulder.\(sideName)", .bodyAreas, sign * shoulderX, 0.86, 0, 0.34, 0.34, 0.34),
                segment("body.upperArm.\(sideName)", .bodyAreas, from: v(sign * 0.62, 0.7, 0), to: v(sign * 0.72, 0.17, 0), width: 0.24),
                part("body.elbow.\(sideName)", .bodyAreas, sign * 0.73, 0.08, 0, 0.25, 0.25, 0.25),
                segment("body.forearm.\(sideName)", .bodyAreas, from: v(sign * 0.73, -0.03, 0), to: v(sign * 0.79, -0.49, 0.02), width: 0.2),
                part("body.wrist.\(sideName)", .bodyAreas, sign * 0.8, -0.56, 0.02, 0.18, 0.19, 0.18),
                part("body.hand.\(sideName)", .bodyAreas, sign * 0.82, -0.75, 0.05, 0.22, 0.34, 0.14),
                part("body.hip.\(sideName)", .bodyAreas, sign * pelvisWidth * 0.38, -0.37, 0.03, 0.34, 0.36, 0.34),
                part("body.buttock.\(sideName)", .bodyAreas, sign * 0.22, -0.42, -0.24, 0.38, 0.42, 0.24),
                segment("body.thigh.\(sideName)", .bodyAreas, from: v(sign * 0.25, -0.5, 0.05), to: v(sign * 0.23, -1.17, 0.04), width: 0.35),
                segment("body.posteriorThigh.\(sideName)", .bodyAreas, from: v(sign * 0.25, -0.57, -0.2), to: v(sign * 0.23, -1.13, -0.17), width: 0.24),
                part("body.knee.\(sideName)", .bodyAreas, sign * 0.22, -1.28, 0.04, 0.31, 0.3, 0.31),
                segment("body.lowerLeg.\(sideName)", .bodyAreas, from: v(sign * 0.22, -1.4, 0.02), to: v(sign * 0.19, -1.88, 0.01), width: 0.25),
                segment("body.calf.\(sideName)", .bodyAreas, from: v(sign * 0.22, -1.42, -0.16), to: v(sign * 0.19, -1.82, -0.13), width: 0.18),
                part("body.ankle.\(sideName)", .bodyAreas, sign * 0.19, -1.98, 0.02, 0.22, 0.23, 0.22),
                part("body.foot.\(sideName)", .bodyAreas, sign * 0.2, -2.1, 0.16, 0.3, 0.2, 0.52)
            ]
        }
        return parts
    }

    static let muscleParts: [BodyVisualPart] = {
        var parts: [BodyVisualPart] = [
            part("muscle.trapezius", .muscles, 0, 0.87, -0.19, 0.68, 0.4, 0.16),
            part("muscle.pectorals", .muscles, 0, 0.76, 0.22, 0.7, 0.38, 0.17),
            part("muscle.abdominals", .muscles, 0, 0.2, 0.21, 0.43, 0.55, 0.14),
            part("muscle.lowerBack", .muscles, 0, 0.16, -0.24, 0.45, 0.5, 0.13)
        ]
        for (sideName, sign) in [("left", left), ("right", right)] {
            parts += [
                part("muscle.deltoid.\(sideName)", .muscles, sign * 0.57, 0.82, 0.03, 0.3, 0.3, 0.3),
                segment("muscle.biceps.\(sideName)", .muscles, from: v(sign * 0.65, 0.62, 0.13), to: v(sign * 0.7, 0.2, 0.12), width: 0.17),
                segment("muscle.triceps.\(sideName)", .muscles, from: v(sign * 0.65, 0.62, -0.13), to: v(sign * 0.7, 0.2, -0.12), width: 0.16),
                segment("muscle.forearm.\(sideName)", .muscles, from: v(sign * 0.73, 0, 0.05), to: v(sign * 0.78, -0.45, 0.05), width: 0.13),
                part("muscle.gluteal.\(sideName)", .muscles, sign * 0.22, -0.38, -0.26, 0.34, 0.37, 0.18),
                segment("muscle.quadriceps.\(sideName)", .muscles, from: v(sign * 0.24, -0.55, 0.19), to: v(sign * 0.22, -1.12, 0.17), width: 0.23),
                segment("muscle.hamstrings.\(sideName)", .muscles, from: v(sign * 0.24, -0.55, -0.21), to: v(sign * 0.22, -1.12, -0.18), width: 0.21),
                segment("muscle.calf.\(sideName)", .muscles, from: v(sign * 0.21, -1.45, -0.13), to: v(sign * 0.19, -1.84, -0.1), width: 0.16)
            ]
        }
        return parts
    }()

    static let jointParts: [BodyVisualPart] = {
        var parts: [BodyVisualPart] = [
            segment("joint.cervicalSpine", .joints, from: v(0, 1.02, -0.05), to: v(0, 1.33, -0.06), width: 0.11),
            part("joint.ribCage", .joints, 0, 0.68, 0, 0.7, 0.64, 0.35),
            segment("joint.lumbarSpine", .joints, from: v(0, -0.02, -0.08), to: v(0, 0.42, -0.08), width: 0.12)
        ]
        for (sideName, sign) in [("left", left), ("right", right)] {
            parts += [
                part("joint.shoulder.\(sideName)", .joints, sign * 0.54, 0.82, 0, 0.22, 0.22, 0.22),
                part("joint.elbow.\(sideName)", .joints, sign * 0.7, 0.08, 0, 0.19, 0.19, 0.19),
                part("joint.wrist.\(sideName)", .joints, sign * 0.78, -0.52, 0, 0.15, 0.15, 0.15),
                part("joint.sacroiliac.\(sideName)", .joints, sign * 0.13, -0.2, -0.14, 0.15, 0.23, 0.13),
                part("joint.hip.\(sideName)", .joints, sign * 0.23, -0.39, 0, 0.25, 0.25, 0.25),
                part("joint.knee.\(sideName)", .joints, sign * 0.22, -1.28, 0, 0.25, 0.25, 0.25),
                part("joint.ankle.\(sideName)", .joints, sign * 0.19, -1.98, 0, 0.17, 0.17, 0.17)
            ]
        }
        return parts
    }()

    static let nerveParts: [BodyVisualPart] = {
        var parts: [BodyVisualPart] = []
        for (sideName, sign) in [("left", left), ("right", right)] {
            parts += [
                part("nerve.trigeminal.\(sideName)", .nerves, sign * 0.14, 1.53, 0.28, 0.12, 0.18, 0.08),
                segment("nerve.median.\(sideName)", .nerves, from: v(sign * 0.57, 0.72, 0.06), to: v(sign * 0.77, -0.52, 0.08), width: 0.055),
                segment("nerve.ulnar.\(sideName)", .nerves, from: v(sign * 0.59, 0.7, -0.06), to: v(sign * 0.79, -0.5, -0.04), width: 0.05),
                segment("nerve.lumbar.\(sideName)", .nerves, from: v(0, 0.18, -0.05), to: v(sign * 0.28, -0.18, -0.1), width: 0.07),
                segment("nerve.femoral.\(sideName)", .nerves, from: v(sign * 0.18, -0.18, 0.12), to: v(sign * 0.22, -1.18, 0.17), width: 0.065),
                segment("nerve.sciatic.\(sideName)", .nerves, from: v(sign * 0.12, 0.03, -0.16), to: v(sign * 0.23, -0.5, -0.25), width: 0.08),
                segment("nerve.sciatic.\(sideName)", .nerves, from: v(sign * 0.23, -0.5, -0.25), to: v(sign * 0.23, -1.22, -0.2), width: 0.075),
                segment("nerve.sciatic.\(sideName)", .nerves, from: v(sign * 0.23, -1.22, -0.2), to: v(sign * 0.19, -1.9, -0.11), width: 0.055)
            ]
        }
        return parts
    }()

    static func organParts(variant: BodyModelVariant) -> [BodyVisualPart] {
        var parts: [BodyVisualPart] = [
            part("organ.brain", .organs, 0, 1.57, 0, 0.4, 0.48, 0.39),
            part("organ.lung.left", .organs, 0.2, 0.72, 0.03, 0.28, 0.51, 0.25),
            part("organ.lung.right", .organs, -0.2, 0.72, 0.03, 0.28, 0.51, 0.25),
            part("organ.heart", .organs, 0.09, 0.57, 0.17, 0.26, 0.33, 0.22, angle: -0.18),
            part("organ.liver", .organs, -0.2, 0.25, 0.1, 0.45, 0.25, 0.28, angle: 0.08),
            part("organ.stomach", .organs, 0.18, 0.19, 0.12, 0.25, 0.33, 0.2, angle: -0.25),
            part("organ.kidney.left", .organs, 0.23, 0.13, -0.14, 0.16, 0.27, 0.14, angle: -0.12),
            part("organ.kidney.right", .organs, -0.23, 0.13, -0.14, 0.16, 0.27, 0.14, angle: 0.12),
            part("organ.intestines", .organs, 0, -0.1, 0.08, 0.45, 0.45, 0.25),
            part("organ.bladder", .organs, 0, -0.36, 0.1, 0.18, 0.21, 0.17)
        ]
        if variant == .female {
            parts += [
                part("organ.uterus", .organs, 0, -0.32, 0.04, 0.18, 0.23, 0.15),
                part("organ.ovary.left", .organs, 0.17, -0.27, 0.03, 0.11, 0.1, 0.09),
                part("organ.ovary.right", .organs, -0.17, -0.27, 0.03, 0.11, 0.1, 0.09)
            ]
        } else if variant == .male {
            parts.append(part("organ.prostate", .organs, 0, -0.42, 0.04, 0.14, 0.12, 0.12))
        }
        return parts
    }

    private static func part(
        _ id: String,
        _ layer: BodyAnatomyLayer,
        _ x: Float,
        _ y: Float,
        _ z: Float,
        _ width: Float,
        _ height: Float,
        _ depth: Float,
        angle: Float = 0
    ) -> BodyVisualPart {
        BodyVisualPart(
            id,
            layer,
            center: v(x, y, z),
            size: v(width, height, depth),
            rotation: simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))
        )
    }

    private static func segment(
        _ id: String,
        _ layer: BodyAnatomyLayer,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        width: Float
    ) -> BodyVisualPart {
        let vector = end - start
        let length = simd_length(vector)
        let rotation = length > 0
            ? simd_quatf(from: SIMD3(0, 1, 0), to: vector / length)
            : simd_quatf()
        return BodyVisualPart(
            id,
            layer,
            center: (start + end) / 2,
            size: v(width, length, width),
            rotation: rotation
        )
    }

    private static func v(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
#endif
