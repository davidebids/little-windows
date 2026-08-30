import Combine
import RealityKit
import SwiftUI
import UIKit

private let anatomySceneScale: Float = 2.55

private final class AnatomyWeakScrollViewReference {
    weak var value: UIScrollView?

    init(_ value: UIScrollView) {
        self.value = value
    }
}

private let anatomyBodyScanProfile: [(height: Float, radius: SIMD2<Float>)] = [
    (-0.92, SIMD2(0.23, 0.18)),
    (-0.80, SIMD2(0.20, 0.16)),
    (-0.64, SIMD2(0.19, 0.16)),
    (-0.52, SIMD2(0.21, 0.17)),
    (-0.34, SIMD2(0.23, 0.19)),
    (-0.23, SIMD2(0.27, 0.21)),
    (-0.16, SIMD2(0.35, 0.23)),
    (-0.11, SIMD2(0.48, 0.245)),
    (-0.06, SIMD2(0.58, 0.25)),
    (0.04, SIMD2(0.60, 0.25)),
    (0.13, SIMD2(0.56, 0.25)),
    (0.23, SIMD2(0.48, 0.25)),
    (0.34, SIMD2(0.41, 0.245)),
    (0.44, SIMD2(0.37, 0.235)),
    (0.51, SIMD2(0.33, 0.215)),
    (0.56, SIMD2(0.26, 0.19)),
    (0.61, SIMD2(0.20, 0.16)),
    (0.70, SIMD2(0.18, 0.17)),
    (0.84, SIMD2(0.15, 0.14))
]

struct BodyVisualizationView: UIViewRepresentable {
    let variant: BodyModelVariant
    let activeLayer: BodyAnatomyLayer
    let regionFilter: BodyRegionFilter
    let handDetailFocus: BodyHandDetailFocus
    let footDetailFocus: BodyFootDetailFocus
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
        // At this card size, 1.75x still resolves the mesh at roughly one rendered
        // pixel per visible display pixel on 3x phones, while cutting another 23%
        // of the color/depth target area. Native 2x devices retain their full scale.
        let displayScale = UIScreen.main.scale
        view.contentScaleFactor = displayScale > 2 ? 1.75 : displayScale
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        view.renderOptions.formUnion([
            .disableCameraGrain,
            .disableDepthOfField,
            .disableGroundingShadows,
            .disableMotionBlur,
            .disableHDR,
            .disableAREnvironmentLighting,
            .disablePersonOcclusion,
            .disableFaceMesh
        ])
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(in: uiView)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.releaseSceneResources()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BodyVisualizationView

        private weak var arView: ARView?
        private weak var modelPanGestureRecognizer: UIPanGestureRecognizer?
        private weak var modelPinchGestureRecognizer: UIPinchGestureRecognizer?
        private var prioritizedScrollViews: [AnatomyWeakScrollViewReference] = []
        private var activeManipulationRecognizers: Set<ObjectIdentifier> = []
        private var suspendedScrollViewStates: [ObjectIdentifier: Bool] = [:]
        private weak var faceFillLight: PointLight?
        private var animationDisplayLink: CADisplayLink?
        private var lastAnimationTimestamp: CFTimeInterval?
        private var memoryWarningSubscription: Cancellable?
        private var applicationStateSubscription: Cancellable?
        private var performanceStateSubscription: Cancellable?
        private var interactionRoot = Entity()
        private var breathingRoot = Entity()
        private var selectionProxyRoot = Entity()
        private var surfaceRoot = Entity()
        private var ghostRoot = Entity()
        private var muscleRoot = Entity()
        private var skeletonRoot = Entity()
        private var nerveRoot = Entity()
        private var circulationRoot = Entity()
        private var organRoot = Entity()
        private var organSelectionProxyRoot = Entity()
        private var handDetailRoot = Entity()
        private var handDetailSelectionProxyRoot = Entity()
        private var footDetailRoot = Entity()
        private var footDetailSelectionProxyRoot = Entity()
        private var markerRoot = Entity()
        private var atmosphereRoot = Entity()
        private var scanRoot = Entity()
        private var scanCoreEntity: ModelEntity?
        private var scanHaloEntity: ModelEntity?
        private var scanEchoEntities: [ModelEntity] = []
        private var smoothedScanEnvelope: SIMD2<Float>?
        private var entitiesByStructureID: [String: [Entity]] = [:]
        private var specificationsByStructureID: [String: AnatomyAssetSpecification] = [:]
        private var restPosesByEntity: [ObjectIdentifier: AnatomyRestPose] = [:]
        private var markerPositions: [String: SIMD3<Float>] = [:]
        private var nervePulseTracks: [AnatomyPulseTrack] = []
        private var arterialPulseTargets: [Entity] = []
        private var lastArterialPulseStep = -1
        private var atmosphereMotes: [AnatomyMote] = []
        private var loadedLayers: Set<BodyAnatomyLayer> = []
        private var loadedLayerOrder: [BodyAnatomyLayer] = []
        private var loadedHandDetailLayer: BodyAnatomyLayer?
        private var loadedFootDetailLayer: BodyAnatomyLayer?
        private var loadedFootDetailOrientation: BodyViewOrientation?
        private var sphereMeshes: [Int: MeshResource] = [:]

        private var currentVariant: BodyModelVariant?
        private var currentLayer: BodyAnatomyLayer?
        private var currentRegion: BodyRegionFilter?
        private var currentHandDetailFocus: BodyHandDetailFocus?
        private var currentFootDetailFocus: BodyFootDetailFocus?
        private var currentOrientation: BodyViewOrientation?
        private var currentSelectionIDs: Set<String> = []
        private var currentResetToken: UUID?
        private var currentReduceMotion: Bool?

        private var yaw: Float = 0
        private var pitch: Float = 0
        private var zoom: Float = 1
        private var gestureStartYaw: Float = 0
        private var gestureStartPitch: Float = 0
        private var gestureStartZoom: Float = 1
        private var elapsed: Float = 0
        private var configuredAnimationFrameRate = 0
        private var isApplicationActive = true
        private var isPerformanceConstrained = false

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
            pan.cancelsTouchesInView = true
            modelPanGestureRecognizer = pan
            modelPinchGestureRecognizer = pinch
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            rebuildScene(in: view)
            synchronize(in: view)
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.prioritizeModelDrag(in: view)
            }
        }

        func stop() {
            activeManipulationRecognizers.removeAll()
            restoreAncestorScrolling()
            animationDisplayLink?.invalidate()
            animationDisplayLink = nil
            lastAnimationTimestamp = nil
            memoryWarningSubscription?.cancel()
            memoryWarningSubscription = nil
            applicationStateSubscription?.cancel()
            applicationStateSubscription = nil
            performanceStateSubscription?.cancel()
            performanceStateSubscription = nil
        }

        func releaseSceneResources() {
            stop()
            arView?.scene.anchors.removeAll()
            interactionRoot.children.removeAll()
            atmosphereRoot.children.removeAll()
            entitiesByStructureID.removeAll()
            specificationsByStructureID.removeAll()
            restPosesByEntity.removeAll()
            markerPositions.removeAll()
            nervePulseTracks.removeAll()
            arterialPulseTargets.removeAll()
            atmosphereMotes.removeAll()
            sphereMeshes.removeAll()
            scanCoreEntity = nil
            scanHaloEntity = nil
            scanEchoEntities.removeAll()
            faceFillLight = nil
            prioritizedScrollViews.removeAll()
            modelPanGestureRecognizer = nil
            modelPinchGestureRecognizer = nil
            arView = nil
        }

        func synchronize(in view: ARView) {
            prioritizeModelDrag(in: view)
            if currentVariant != parent.variant {
                rebuildScene(in: view)
            }
            if currentLayer != parent.activeLayer {
                prepareForLayerTransition(
                    from: currentLayer,
                    to: parent.activeLayer
                )
                currentLayer = parent.activeLayer
                if isShowingExtremityDetail {
                    synchronizeExtremityDetailAssets()
                } else {
                    ensureLayerLoaded(parent.activeLayer)
                }
                updateLayerVisibility()
                updateRegionVisibility()
                updateMaterials()
                updateSelectionMarkers()
            }
            if currentSelectionIDs != parent.selectedStructureIDs {
                currentSelectionIDs = parent.selectedStructureIDs
                updateMaterials()
                updateSelectionMarkers()
            }
            if currentOrientation != parent.orientation {
                currentOrientation = parent.orientation
                if isShowingFootDetail {
                    yaw = defaultYaw
                    pitch = defaultPitch
                    synchronizeFootDetailAssets()
                } else {
                    yaw = parent.orientation == .front ? 0 : .pi
                }
                applyInteractionTransform(animated: true)
            }
            if currentRegion != parent.regionFilter {
                currentRegion = parent.regionFilter
                synchronizeExtremityDetailAssets()
                updateLayerVisibility()
                updateRegionVisibility()
                updateSelectionMarkers()
                applyInteractionTransform(animated: true)
            }
            if currentHandDetailFocus != parent.handDetailFocus {
                currentHandDetailFocus = parent.handDetailFocus
                synchronizeExtremityDetailAssets()
                updateLayerVisibility()
                updateSelectionMarkers()
                applyInteractionTransform(animated: true)
            }
            if currentFootDetailFocus != parent.footDetailFocus {
                currentFootDetailFocus = parent.footDetailFocus
                // Left and right feet have independent registered meshes. Force a
                // reload when the focused side changes instead of retaining the
                // previously loaded side for the active anatomy layer.
                footDetailRoot.children.removeAll()
                loadedFootDetailLayer = nil
                loadedFootDetailOrientation = nil
                yaw = isShowingFootDetail
                    ? defaultYaw
                    : (parent.orientation == .front ? 0 : .pi)
                pitch = defaultPitch
                synchronizeExtremityDetailAssets()
                updateLayerVisibility()
                updateSelectionMarkers()
                applyInteractionTransform(animated: true)
            }
            if currentResetToken != parent.resetToken {
                currentResetToken = parent.resetToken
                yaw = isShowingFootDetail
                    ? defaultYaw
                    : (parent.orientation == .front ? 0 : .pi)
                pitch = defaultPitch
                zoom = 1
                applyInteractionTransform(animated: true)
            }
            if currentReduceMotion != parent.reduceMotion {
                currentReduceMotion = parent.reduceMotion
                if parent.reduceMotion {
                    resetAnimationState()
                }
            }
            refreshAnimationLoop()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            !isScrollViewPan(gestureRecognizer) && !isScrollViewPan(otherGestureRecognizer)
        }

        private func prioritizeModelDrag(in view: UIView) {
            guard let modelPanGestureRecognizer else { return }

            prioritizedScrollViews.removeAll { $0.value == nil }
            var knownScrollViewIDs = Set(
                prioritizedScrollViews.compactMap { reference in
                    reference.value.map(ObjectIdentifier.init)
                }
            )
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    let identifier = ObjectIdentifier(scrollView)
                    if knownScrollViewIDs.insert(identifier).inserted {
                        scrollView.panGestureRecognizer.require(
                            toFail: modelPanGestureRecognizer
                        )
                        if let modelPinchGestureRecognizer {
                            scrollView.panGestureRecognizer.require(
                                toFail: modelPinchGestureRecognizer
                            )
                        }
                        prioritizedScrollViews.append(
                            AnatomyWeakScrollViewReference(scrollView)
                        )
                    }
                }
                ancestor = current.superview
            }
        }

        private func beginExclusiveManipulation(_ recognizer: UIGestureRecognizer) {
            let identifier = ObjectIdentifier(recognizer)
            guard activeManipulationRecognizers.insert(identifier).inserted else { return }
            guard activeManipulationRecognizers.count == 1 else { return }

            if let arView {
                prioritizeModelDrag(in: arView)
            }
            for reference in prioritizedScrollViews {
                guard let scrollView = reference.value else { continue }
                let scrollViewID = ObjectIdentifier(scrollView)
                if suspendedScrollViewStates[scrollViewID] == nil {
                    suspendedScrollViewStates[scrollViewID] = scrollView.isScrollEnabled
                }
                // Requiring failure establishes initial gesture priority. This
                // active lock also cancels any parent pan that UIKit already
                // began during the same physical drag.
                scrollView.isScrollEnabled = false
            }
        }

        private func endExclusiveManipulation(_ recognizer: UIGestureRecognizer) {
            activeManipulationRecognizers.remove(ObjectIdentifier(recognizer))
            guard activeManipulationRecognizers.isEmpty else { return }
            restoreAncestorScrolling()
        }

        private func restoreAncestorScrolling() {
            for reference in prioritizedScrollViews {
                guard let scrollView = reference.value else { continue }
                let identifier = ObjectIdentifier(scrollView)
                guard let wasEnabled = suspendedScrollViewStates[identifier] else { continue }
                scrollView.isScrollEnabled = wasEnabled
            }
            suspendedScrollViewStates.removeAll()
        }

        private func isScrollViewPan(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView = recognizer.view as? UIScrollView else { return false }
            return recognizer === scrollView.panGestureRecognizer
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = arView else { return }
            let location = recognizer.location(in: view)
            for hit in view.hitTest(location) {
                // Collision proxies are intentionally siblings of the breathing
                // hierarchy. Keeping them still prevents the physics broad phase
                // from being rebuilt for every subtle idle-animation frame.
                let localPosition = interactionRoot.convert(position: hit.position, from: nil)
                let semanticName = semanticName(for: hit.entity)
                guard let structureID = resolvedStructureID(
                    for: semanticName,
                    at: localPosition
                ),
                let structure = BodyAnatomyCatalog.structure(id: structureID),
                structure.layer == parent.activeLayer,
                structure.isAvailable(for: parent.variant),
                parent.regionFilter == .all || structure.region == parent.regionFilter
                else { continue }

                markerPositions[structureID] = selectionMarkerPosition(
                    for: structureID,
                    rawHitPosition: localPosition
                )
                UISelectionFeedbackGenerator().selectionChanged()
                parent.onSelect(structureID)
                return
            }
        }

        private func selectionMarkerPosition(
            for structureID: String,
            rawHitPosition: SIMD3<Float>
        ) -> SIMD3<Float> {
            if isShowingFootDetail,
               let marker = FootDetailStructureMapper.markerPosition(
                   for: structureID,
                   focus: parent.footDetailFocus,
                   variant: parent.variant,
                   soleView: parent.orientation == .back
               ) {
                return marker
            }
            if isShowingHandDetail, parent.activeLayer == .joints {
                return HandDetailStructureMapper.markerPosition(
                    for: structureID,
                    focus: parent.handDetailFocus,
                    variant: parent.variant
                ) ?? rawHitPosition
            }

            if parent.activeLayer == .joints {
                return BodySurfaceMapper.markerPosition(
                    for: structureID,
                    variant: parent.variant
                )
            }

            if parent.activeLayer == .organs,
               let entity = entitiesByStructureID[structureID]?.first {
                return entity.visualBounds(relativeTo: breathingRoot).center
            }

            return rawHitPosition
        }

        private func cameraFacingMarkerPosition(
            from anatomicalPosition: SIMD3<Float>,
            canonicalDepth: Float
        ) -> SIMD3<Float> {
            let rotation = interactionRotation
            let towardCamera = rotation.inverse.act(SIMD3<Float>(0, 0, 1))
            return anatomicalPosition
                + towardCamera * canonicalDepth * anatomySceneScale
        }

        private func resolvedStructureID(
            for semanticName: String,
            at localPosition: SIMD3<Float>
        ) -> String? {
            if semanticName.hasPrefix("system:foot-"), isShowingFootDetail {
                return FootDetailStructureMapper.structureID(
                    layer: parent.activeLayer,
                    focus: parent.footDetailFocus,
                    at: localPosition / anatomySceneScale,
                    variant: parent.variant,
                    soleView: parent.orientation == .back
                )
            }
            if semanticName.hasPrefix("system:hand-"), isShowingHandDetail {
                return HandDetailStructureMapper.structureID(
                    layer: parent.activeLayer,
                    focus: parent.handDetailFocus,
                    at: localPosition / anatomySceneScale
                )
            }
            if semanticName.hasPrefix("anatomy:"), parent.activeLayer == .organs {
                return String(semanticName.dropFirst("anatomy:".count))
            }
            if semanticName == "system:selectionProxy", parent.activeLayer == .bodyAreas {
                return BodySurfaceMapper.structureID(
                    at: localPosition,
                    variant: parent.variant
                )
            }
            if semanticName == "system:selectionProxy", parent.activeLayer == .muscles {
                return BodySurfaceMapper.muscleID(
                    at: localPosition,
                    variant: parent.variant
                )
            }
            if semanticName == "system:selectionProxy", parent.activeLayer == .joints {
                return BodySurfaceMapper.jointID(
                    at: localPosition,
                    variant: parent.variant
                )
            }
            if semanticName == "system:selectionProxy", parent.activeLayer == .nerves {
                return BodySurfaceMapper.nerveID(
                    at: localPosition,
                    variant: parent.variant
                )
            }
            return nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = arView else { return }
            switch recognizer.state {
            case .began:
                beginExclusiveManipulation(recognizer)
                gestureStartYaw = yaw
                gestureStartPitch = pitch
            case .changed:
                let translation = recognizer.translation(in: view)
                yaw = gestureStartYaw + Float(translation.x) * 0.008
                let pitchLimit: Float = isShowingFootDetail ? 1.42 : 0.36
                pitch = min(
                    pitchLimit,
                    max(-pitchLimit, gestureStartPitch + Float(translation.y) * 0.0035)
                )
                applyInteractionTransform(animated: false)
            case .ended, .cancelled, .failed:
                endExclusiveManipulation(recognizer)
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                beginExclusiveManipulation(recognizer)
                gestureStartZoom = zoom
            case .changed:
                zoom = min(1.7, max(0.76, gestureStartZoom * Float(recognizer.scale)))
                applyInteractionTransform(animated: false)
            case .ended, .cancelled, .failed:
                endExclusiveManipulation(recognizer)
            default:
                break
            }
        }

        private func semanticName(for entity: Entity) -> String {
            var candidate: Entity? = entity
            while let value = candidate {
                if value.name.hasPrefix("anatomy:") || value.name.hasPrefix("system:") {
                    return value.name
                }
                candidate = value.parent
            }
            return ""
        }

        private func rebuildScene(in view: ARView) {
            stop()
            view.scene.anchors.removeAll()
            entitiesByStructureID = [:]
            specificationsByStructureID = [:]
            restPosesByEntity = [:]
            markerPositions = [:]
            nervePulseTracks = []
            arterialPulseTargets = []
            lastArterialPulseStep = -1
            atmosphereMotes = []
            loadedLayers = []
            loadedLayerOrder = []
            loadedHandDetailLayer = nil
            loadedFootDetailLayer = nil
            loadedFootDetailOrientation = nil
            sphereMeshes = [:]
            configuredAnimationFrameRate = 0

            currentVariant = parent.variant
            currentLayer = nil
            currentRegion = nil
            currentHandDetailFocus = nil
            currentFootDetailFocus = nil
            currentOrientation = nil
            currentSelectionIDs = []
            currentReduceMotion = nil

            let anchor = AnchorEntity(world: SIMD3(0, -0.03, -2.65))
            interactionRoot = Entity()
            breathingRoot = Entity()
            selectionProxyRoot = Entity()
            surfaceRoot = Entity()
            ghostRoot = Entity()
            muscleRoot = Entity()
            skeletonRoot = Entity()
            nerveRoot = Entity()
            circulationRoot = Entity()
            circulationRoot.scale = SIMD3(repeating: anatomySceneScale)
            organRoot = Entity()
            organSelectionProxyRoot = Entity()
            handDetailRoot = Entity()
            handDetailSelectionProxyRoot = Entity()
            footDetailRoot = Entity()
            footDetailSelectionProxyRoot = Entity()
            markerRoot = Entity()
            atmosphereRoot = Entity()
            scanRoot = Entity()
            scanRoot.scale = SIMD3(repeating: anatomySceneScale)
            scanCoreEntity = nil
            scanHaloEntity = nil
            scanEchoEntities = []
            smoothedScanEnvelope = nil
            interactionRoot.addChild(selectionProxyRoot)
            interactionRoot.addChild(organSelectionProxyRoot)
            interactionRoot.addChild(handDetailSelectionProxyRoot)
            interactionRoot.addChild(footDetailSelectionProxyRoot)
            interactionRoot.addChild(breathingRoot)
            breathingRoot.addChild(surfaceRoot)
            breathingRoot.addChild(ghostRoot)
            breathingRoot.addChild(muscleRoot)
            breathingRoot.addChild(skeletonRoot)
            breathingRoot.addChild(nerveRoot)
            breathingRoot.addChild(circulationRoot)
            breathingRoot.addChild(organRoot)
            breathingRoot.addChild(handDetailRoot)
            breathingRoot.addChild(footDetailRoot)
            breathingRoot.addChild(markerRoot)
            breathingRoot.addChild(scanRoot)

            if parent.activeLayer == .bodyAreas {
                ensureSurfaceLoaded()
            } else {
                ensureGhostLoaded()
            }
            addSelectionProxy()
            loadedLayers.insert(.bodyAreas)
            ensureLayerLoaded(parent.activeLayer)
            synchronizeExtremityDetailAssets()
            addAtmosphere(to: atmosphereRoot)
            addBodyScan(to: scanRoot)

            addLights(to: anchor)
            anchor.addChild(atmosphereRoot)
            anchor.addChild(interactionRoot)
            view.scene.anchors.append(anchor)

            startAnimationLoop()
            memoryWarningSubscription = NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            ).sink { [weak self] _ in
                self?.purgeInactiveResources()
            }
            isApplicationActive = UIApplication.shared.applicationState == .active
            applicationStateSubscription = Publishers.Merge(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                ).map { _ in true },
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                ).map { _ in false }
            ).sink { [weak self] isActive in
                self?.isApplicationActive = isActive
                self?.refreshAnimationLoop()
            }
            refreshPerformanceConstraint()
            performanceStateSubscription = Publishers.Merge(
                NotificationCenter.default.publisher(
                    for: Notification.Name.NSProcessInfoPowerStateDidChange
                ),
                NotificationCenter.default.publisher(
                    for: ProcessInfo.thermalStateDidChangeNotification
                )
            ).sink { [weak self] _ in
                self?.refreshPerformanceConstraint()
            }
            updateLayerVisibility()
            updateRegionVisibility()
            updateMaterials()
            updateSelectionMarkers()
            applyInteractionTransform(animated: false)
        }

        private func ensureSurfaceLoaded() {
            guard surfaceRoot.children.isEmpty else { return }
            let fileNames = AnatomyAssetCatalog.skinFileNames(for: parent.variant)
            guard let loaded = loadEntity(fileNames.surface) else { return }
            loaded.name = "system:skin"
            setMaterial(AnatomyMaterial.skin(selected: false), on: loaded)
            surfaceRoot.addChild(loaded)
        }

        private func ensureGhostLoaded() {
            guard ghostRoot.children.isEmpty else { return }
            let fileNames = AnatomyAssetCatalog.skinFileNames(for: parent.variant)
            guard let ghost = loadEntity(fileNames.ghost) else { return }
            ghost.name = "system:ghost"
            setMaterial(AnatomyMaterial.ghostSkin(opacity: 0.095), on: ghost)
            ghostRoot.addChild(ghost)
        }

        private func ensureLayerLoaded(_ layer: BodyAnatomyLayer) {
            if layer == .bodyAreas {
                ensureSurfaceLoaded()
                for loadedLayer in loadedLayerOrder {
                    unloadLayer(loadedLayer)
                }
                loadedLayerOrder.removeAll()
                return
            }
            ensureGhostLoaded()
            if loadedLayers.contains(layer) {
                markLayerRecentlyUsed(layer)
                return
            }
            switch layer {
            case .bodyAreas: break
            case .muscles:
                loadSystemAssets(
                    AnatomyAssetCatalog.muscleSystemSpecifications(for: parent.variant),
                    into: muscleRoot
                )
            case .joints:
                loadSystemAssets(
                    [
                        AnatomyAssetCatalog.skeletonSystemSpecification(for: parent.variant),
                        AnatomyAssetCatalog.jointSystemSpecification(for: parent.variant),
                        AnatomyAssetCatalog.handSkeletonSystemSpecification(for: parent.variant),
                        AnatomyAssetCatalog.handJointSystemSpecification(for: parent.variant)
                    ],
                    into: skeletonRoot
                )
            case .nerves:
                addNervousSystem()
            case .organs:
                loadAssets(
                    AnatomyAssetCatalog.organSpecifications(for: parent.variant),
                    into: organRoot
                )
                addCirculation()
            }
            loadedLayers.insert(layer)
            markLayerRecentlyUsed(layer)
            evictUnusedLayers()
        }

        private var isShowingHandDetail: Bool {
            parent.regionFilter == .armsAndHands && parent.handDetailFocus != .both
        }

        private var isShowingFootDetail: Bool {
            parent.regionFilter == .legsAndFeet && parent.footDetailFocus != .both
        }

        private var isShowingExtremityDetail: Bool {
            isShowingHandDetail || isShowingFootDetail
        }

        private var defaultPitch: Float {
            guard isShowingFootDetail else { return 0 }
            return parent.orientation == .front ? 0.04 : -.pi / 2
        }

        private var defaultYaw: Float {
            guard isShowingFootDetail else {
                return parent.orientation == .front ? 0 : .pi
            }
            guard parent.orientation == .front else { return 0 }
            return parent.footDetailFocus == .right ? .pi / 2 : -.pi / 2
        }

        private func prepareForLayerTransition(
            from previousLayer: BodyAnatomyLayer?,
            to nextLayer: BodyAnatomyLayer
        ) {
            guard previousLayer != nextLayer else { return }

            if let previousLayer,
               previousLayer != .bodyAreas,
               loadedLayers.contains(previousLayer) {
                unloadLayer(previousLayer)
                loadedLayerOrder.removeAll { $0 == previousLayer }
            }

            if nextLayer == .bodyAreas {
                ghostRoot.children.removeAll()
            } else {
                surfaceRoot.children.removeAll()
            }
        }

        private func synchronizeExtremityDetailAssets() {
            if isShowingHandDetail {
                footDetailRoot.children.removeAll()
                footDetailSelectionProxyRoot.children.removeAll()
                loadedFootDetailLayer = nil
                loadedFootDetailOrientation = nil
                synchronizeHandDetailAssets()
                return
            }
            if isShowingFootDetail {
                handDetailRoot.children.removeAll()
                handDetailSelectionProxyRoot.children.removeAll()
                loadedHandDetailLayer = nil
                synchronizeFootDetailAssets()
                return
            }

            handDetailRoot.children.removeAll()
            handDetailSelectionProxyRoot.children.removeAll()
            footDetailRoot.children.removeAll()
            footDetailSelectionProxyRoot.children.removeAll()
            loadedHandDetailLayer = nil
            loadedFootDetailLayer = nil
            loadedFootDetailOrientation = nil
            ensureLayerLoaded(parent.activeLayer)
        }

        private func synchronizeHandDetailAssets() {
            guard isShowingHandDetail else { return }

            if parent.activeLayer != .bodyAreas, loadedLayers.contains(parent.activeLayer) {
                unloadLayer(parent.activeLayer)
                loadedLayerOrder.removeAll { $0 == parent.activeLayer }
            }
            surfaceRoot.children.removeAll()
            ghostRoot.children.removeAll()
            ensureHandDetailLoaded()
            handDetailRoot.scale = SIMD3(
                parent.handDetailFocus == .right ? -1 : 1,
                1,
                1
            )
            addHandDetailSelectionProxy()
        }

        private func synchronizeFootDetailAssets() {
            guard isShowingFootDetail else { return }

            if parent.activeLayer != .bodyAreas, loadedLayers.contains(parent.activeLayer) {
                unloadLayer(parent.activeLayer)
                loadedLayerOrder.removeAll { $0 == parent.activeLayer }
            }
            surfaceRoot.children.removeAll()
            ghostRoot.children.removeAll()
            ensureFootDetailLoaded()
        }

        private func ensureFootDetailLoaded() {
            guard loadedFootDetailLayer != parent.activeLayer
                    || loadedFootDetailOrientation != parent.orientation
                    || footDetailRoot.children.isEmpty
            else { return }

            footDetailRoot.children.removeAll()
            footDetailSelectionProxyRoot.children.removeAll()
            loadedFootDetailLayer = parent.activeLayer
            loadedFootDetailOrientation = parent.orientation

            if let surface = loadEntity(
                AnatomyAssetCatalog.footDetailFileName(
                    system: .surface,
                    variant: parent.variant,
                    focus: parent.footDetailFocus,
                    soleView: parent.orientation == .back,
                    internalLayer: parent.activeLayer != .bodyAreas
                )
            ) {
                surface.name = "system:foot-surface"
                let material: PhysicallyBasedMaterial
                if parent.activeLayer == .bodyAreas {
                    material = AnatomyMaterial.skin(selected: false)
                } else {
                    let opacity: CGFloat = switch parent.activeLayer {
                    case .muscles: 0.035
                    case .joints: 0.055
                    case .nerves: 0.075
                    case .organs: 0.04
                    case .bodyAreas: 1
                    }
                    material = AnatomyMaterial.ghostSkin(opacity: opacity)
                }
                setMaterial(material, on: surface)
                footDetailRoot.addChild(surface)
            }
            addFootDetailSelectionProxy()

            switch parent.activeLayer {
            case .bodyAreas:
                break
            case .organs:
                break
            case .muscles:
                loadFootDetailSystem(.muscles, material: AnatomyMaterial.muscle)
                if parent.orientation == .back {
                    loadFootDetailSystem(.tendons, material: AnatomyMaterial.tendon)
                }
            case .joints:
                loadFootDetailSystem(.skeleton, material: AnatomyMaterial.footBone)
                loadFootDetailSystem(.joints, material: AnatomyMaterial.footJoint)
            case .nerves:
                loadFootDetailSystem(
                    .nerveSheaths,
                    material: AnatomyMaterial.handNeuralSheath
                )
                loadFootDetailSystem(.nerves, material: AnatomyMaterial.handNeuralCore)
            }
        }

        private func loadFootDetailSystem(
            _ system: AnatomyFootDetailSystem,
            material: PhysicallyBasedMaterial
        ) {
            guard let entity = loadEntity(
                AnatomyAssetCatalog.footDetailFileName(
                    system: system,
                    variant: parent.variant,
                    focus: parent.footDetailFocus,
                    soleView: parent.orientation == .back
                )
            ) else { return }
            entity.name = "system:foot-\(system.rawValue)"
            setMaterial(material, on: entity)
            footDetailRoot.addChild(entity)
        }

        private func addFootDetailSelectionProxy() {
            footDetailSelectionProxyRoot.children.removeAll()
            guard isShowingFootDetail else { return }
            let proxy = Entity()
            proxy.name = "system:foot-selection-proxy"
            proxy.components.set(CollisionComponent(shapes: FootDetailStructureMapper
                .selectionProxyShapes(
                    focus: parent.footDetailFocus,
                    variant: parent.variant,
                    soleView: parent.orientation == .back
                )))
            footDetailSelectionProxyRoot.addChild(proxy)
        }

        private func ensureHandDetailLoaded() {
            guard loadedHandDetailLayer != parent.activeLayer || handDetailRoot.children.isEmpty
            else { return }

            handDetailRoot.children.removeAll()
            loadedHandDetailLayer = parent.activeLayer

            if let surface = loadEntity(
                AnatomyAssetCatalog.handDetailFileName(
                    system: .surface,
                    variant: parent.variant
                )
            ) {
                surface.name = "system:hand-surface"
                let material: PhysicallyBasedMaterial
                if parent.activeLayer == .bodyAreas {
                    material = AnatomyMaterial.skin(selected: false)
                } else {
                    let opacity: CGFloat = switch parent.activeLayer {
                    case .muscles: 0.035
                    case .joints: 0.055
                    case .nerves: 0.075
                    case .organs: 0.04
                    case .bodyAreas: 1
                    }
                    material = AnatomyMaterial.ghostSkin(opacity: opacity)
                }
                setMaterial(material, on: surface)
                handDetailRoot.addChild(surface)
            }

            switch parent.activeLayer {
            case .bodyAreas, .organs:
                break
            case .muscles:
                loadHandDetailSystem(.muscles, material: AnatomyMaterial.muscle)
                loadHandDetailSystem(.tendons, material: AnatomyMaterial.tendon)
            case .joints:
                loadHandDetailSystem(.skeleton, material: AnatomyMaterial.bone)
                loadHandDetailSystem(.joints, material: AnatomyMaterial.handJoint)
            case .nerves:
                loadHandDetailSystem(
                    .nerveSheaths,
                    material: AnatomyMaterial.handNeuralSheath
                )
                loadHandDetailSystem(.nerves, material: AnatomyMaterial.handNeuralCore)
            }
        }

        private func addHandDetailSelectionProxy() {
            handDetailSelectionProxyRoot.children.removeAll()
            guard isShowingHandDetail else { return }

            let mirror: Float = parent.handDetailFocus == .right ? -1 : 1
            let variantScale: SIMD3<Float> = parent.variant == .female
                ? SIMD3(1, 1, 1)
                : SIMD3(1.08, 1.03, 1.08)
            let boxes: [(center: SIMD3<Float>, size: SIMD3<Float>)] = [
                (SIMD3(0, -0.255, 0), SIMD3(0.18, 0.13, 0.17)),
                (SIMD3(0, -0.13, 0), SIMD3(0.27, 0.18, 0.19))
            ]
            var shapes = boxes.map { value in
                let center = SIMD3(value.center.x * mirror, value.center.y, value.center.z)
                    * variantScale * anatomySceneScale
                let size = value.size * variantScale * anatomySceneScale
                return ShapeResource.generateBox(size: size).offsetBy(translation: center)
            }

            let digits: [(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float)] = [
                (SIMD3(0.075, -0.09, 0), SIMD3(0.16, 0.12, 0.015), 0.035),
                (SIMD3(0.07, -0.06, 0), SIMD3(0.075, 0.27, 0), 0.028),
                (SIMD3(0.015, -0.055, 0), SIMD3(0.015, 0.305, 0), 0.029),
                (SIMD3(-0.055, -0.06, 0), SIMD3(-0.055, 0.285, 0), 0.027),
                (SIMD3(-0.115, -0.065, 0), SIMD3(-0.115, 0.245, 0), 0.026)
            ]
            shapes.append(contentsOf: digits.compactMap { value in
                handDetailSelectionCapsule(
                    from: value.start,
                    to: value.end,
                    radius: value.radius,
                    mirror: mirror,
                    variantScale: variantScale
                )
            })

            let proxy = Entity()
            proxy.name = "system:hand-selection-proxy"
            proxy.components.set(CollisionComponent(shapes: shapes))
            handDetailSelectionProxyRoot.addChild(proxy)
        }

        private func handDetailSelectionCapsule(
            from canonicalStart: SIMD3<Float>,
            to canonicalEnd: SIMD3<Float>,
            radius: Float,
            mirror: Float,
            variantScale: SIMD3<Float>
        ) -> ShapeResource? {
            let start = SIMD3(canonicalStart.x * mirror, canonicalStart.y, canonicalStart.z)
                * variantScale * anatomySceneScale
            let end = SIMD3(canonicalEnd.x * mirror, canonicalEnd.y, canonicalEnd.z)
                * variantScale * anatomySceneScale
            let vector = end - start
            let length = simd_length(vector)
            guard length > 0 else { return nil }
            let radiusScale = max(variantScale.x, variantScale.z)
            return ShapeResource.generateCapsule(
                height: length,
                radius: radius * radiusScale * anatomySceneScale
            ).offsetBy(
                rotation: simd_quatf(from: SIMD3(0, 1, 0), to: vector / length),
                translation: (start + end) / 2
            )
        }

        private func loadHandDetailSystem(
            _ system: AnatomyHandDetailSystem,
            material: PhysicallyBasedMaterial
        ) {
            guard let entity = loadEntity(
                AnatomyAssetCatalog.handDetailFileName(
                    system: system,
                    variant: parent.variant
                )
            ) else { return }
            entity.name = "system:hand-\(system.rawValue)"
            setMaterial(material, on: entity)
            handDetailRoot.addChild(entity)
        }

        private func markLayerRecentlyUsed(_ layer: BodyAnatomyLayer) {
            loadedLayerOrder.removeAll { $0 == layer }
            loadedLayerOrder.append(layer)
        }

        private func evictUnusedLayers() {
            let retainedInternalLayerCount = 1
            while loadedLayerOrder.count > retainedInternalLayerCount {
                let layer = loadedLayerOrder.removeFirst()
                guard layer != parent.activeLayer else {
                    loadedLayerOrder.append(layer)
                    continue
                }
                unloadLayer(layer)
            }
        }

        private func purgeInactiveResources() {
            let inactiveLayers = loadedLayerOrder.filter { $0 != parent.activeLayer }
            for layer in inactiveLayers {
                unloadLayer(layer)
            }
            loadedLayerOrder.removeAll { $0 != parent.activeLayer }

            if parent.activeLayer == .bodyAreas {
                ghostRoot.children.removeAll()
            } else {
                surfaceRoot.children.removeAll()
            }

            if !isShowingHandDetail {
                handDetailRoot.children.removeAll()
                handDetailSelectionProxyRoot.children.removeAll()
                loadedHandDetailLayer = nil
            }
            if !isShowingFootDetail {
                footDetailRoot.children.removeAll()
                footDetailSelectionProxyRoot.children.removeAll()
                loadedFootDetailLayer = nil
                loadedFootDetailOrientation = nil
            }
        }

        private func unloadLayer(_ layer: BodyAnatomyLayer) {
            switch layer {
            case .bodyAreas:
                return
            case .muscles:
                muscleRoot.children.removeAll()
            case .joints:
                skeletonRoot.children.removeAll()
            case .nerves:
                nerveRoot.children.removeAll()
                nervePulseTracks = []
            case .organs:
                organRoot.children.removeAll()
                organSelectionProxyRoot.children.removeAll()
                circulationRoot.children.removeAll()
                arterialPulseTargets = []
                lastArterialPulseStep = -1
                let organIDs = Set(
                    AnatomyAssetCatalog.organSpecifications(for: parent.variant).map(\.structureID)
                )
                for entities in entitiesByStructureID.values {
                    for entity in entities {
                        restPosesByEntity.removeValue(forKey: ObjectIdentifier(entity))
                    }
                }
                entitiesByStructureID = entitiesByStructureID.filter { !organIDs.contains($0.key) }
                specificationsByStructureID = specificationsByStructureID.filter {
                    !organIDs.contains($0.key)
                }
            }
            loadedLayers.remove(layer)
        }

        private func addSelectionProxy() {
            selectionProxyRoot.name = "system:selectionProxy"
            let capsules: [(SIMD3<Float>, SIMD3<Float>, Float)] = [
                (SIMD3(0, 0.69, 0), SIMD3(0, 0.82, 0), 0.115),
                (SIMD3(0, 0.57, 0), SIMD3(0, 0.69, 0), 0.075),
                (SIMD3(0, 0.27, 0), SIMD3(0, 0.56, 0), 0.205),
                (SIMD3(0, -0.09, 0), SIMD3(0, 0.28, 0), 0.185),
                (SIMD3(-0.2, 0.51, 0), SIMD3(-0.34, 0.25, 0), 0.072),
                (SIMD3(-0.34, 0.25, 0), SIMD3(-0.49, 0.02, 0), 0.055),
                (SIMD3(-0.49, 0.02, 0.015), SIMD3(-0.53, -0.08, 0.03), 0.065),
                (SIMD3(0.2, 0.51, 0), SIMD3(0.34, 0.25, 0), 0.072),
                (SIMD3(0.34, 0.25, 0), SIMD3(0.49, 0.02, 0), 0.055),
                (SIMD3(0.49, 0.02, 0.015), SIMD3(0.53, -0.08, 0.03), 0.065),
                (SIMD3(-0.1, -0.08, 0), SIMD3(-0.12, -0.5, 0), 0.102),
                (SIMD3(-0.12, -0.5, 0), SIMD3(-0.1, -0.84, 0), 0.068),
                (SIMD3(-0.1, -0.84, 0.02), SIMD3(-0.1, -0.91, 0.1), 0.073),
                (SIMD3(0.1, -0.08, 0), SIMD3(0.12, -0.5, 0), 0.102),
                (SIMD3(0.12, -0.5, 0), SIMD3(0.1, -0.84, 0), 0.068),
                (SIMD3(0.1, -0.84, 0.02), SIMD3(0.1, -0.91, 0.1), 0.073)
            ]
            let shapes = capsules.compactMap { start, end, radius in
                selectionCapsule(from: start, to: end, radius: radius)
            }
            selectionProxyRoot.components.set(CollisionComponent(shapes: shapes))
        }

        private func selectionCapsule(
            from canonicalStart: SIMD3<Float>,
            to canonicalEnd: SIMD3<Float>,
            radius canonicalRadius: Float
        ) -> ShapeResource? {
            let start = selectionProxyPoint(canonicalStart)
            let end = selectionProxyPoint(canonicalEnd)
            let vector = end - start
            let length = simd_length(vector)
            guard length > 0 else { return nil }
            let radiusScale: Float = parent.variant == .female ? 1 : 1.06
            return ShapeResource.generateCapsule(
                height: length,
                radius: canonicalRadius * anatomySceneScale * radiusScale
            ).offsetBy(
                rotation: simd_quatf(from: SIMD3(0, 1, 0), to: vector / length),
                translation: (start + end) / 2
            )
        }

        private func selectionProxyPoint(_ canonicalPoint: SIMD3<Float>) -> SIMD3<Float> {
            let point: SIMD3<Float>
            if parent.variant == .female {
                point = canonicalPoint
            } else {
                point = SIMD3(
                    canonicalPoint.x / 0.935,
                    (canonicalPoint.y - 0.039) / 0.911,
                    canonicalPoint.z
                )
            }
            return point * anatomySceneScale
        }

        private func loadAssets(_ specifications: [AnatomyAssetSpecification], into root: Entity) {
            for specification in specifications {
                guard BodyAnatomyCatalog.structure(id: specification.structureID)?.isAvailable(
                    for: parent.variant
                ) == true,
                let loaded = loadEntity(specification.fileName)
                else { continue }
                loaded.name = "anatomy:\(specification.structureID)"
                setMaterial(AnatomyMaterial.material(for: specification, selected: false), on: loaded)
                root.addChild(loaded)
                restPosesByEntity[ObjectIdentifier(loaded)] = AnatomyRestPose(
                    center: loaded.visualBounds(relativeTo: root).center,
                    position: loaded.position,
                    scale: loaded.scale
                )
                addOrganSelectionProxy(for: loaded, structureID: specification.structureID)
                entitiesByStructureID[specification.structureID, default: []].append(loaded)
                specificationsByStructureID[specification.structureID] = specification
            }
        }

        private func addOrganSelectionProxy(for entity: Entity, structureID: String) {
            let bounds = entity.visualBounds(relativeTo: organRoot)
            let minimumSize: Float = structureID.contains("ovary") ? 0.055 : 0.075
            let size = SIMD3(
                max(bounds.extents.x, minimumSize),
                max(bounds.extents.y, minimumSize),
                max(bounds.extents.z, minimumSize)
            )
            let proxy = Entity()
            proxy.name = "anatomy:\(structureID)"
            proxy.position = bounds.center
            proxy.components.set(CollisionComponent(shapes: [
                .generateBox(size: size)
            ]))
            organSelectionProxyRoot.addChild(proxy)
        }

        private func loadSystemAssets(_ specifications: [SystemAssetSpecification], into root: Entity) {
            for specification in specifications {
                guard let loaded = loadEntity(specification.fileName) else { continue }
                loaded.name = specification.semanticName
                setMaterial(specification.material, on: loaded)
                root.addChild(loaded)
            }
        }

        private func addNervousSystem() {
            let fileName = AnatomyAssetCatalog.nervousSystemFileName(for: parent.variant)
            if let nervousSystem = loadEntity(fileName) {
                nervousSystem.name = "system:nerves"
                setMaterial(AnatomyMaterial.neuralCore, on: nervousSystem)
                nerveRoot.addChild(nervousSystem)
            }
            if let handSheaths = loadEntity(
                AnatomyAssetCatalog.handNerveSheathSystemFileName(for: parent.variant)
            ) {
                handSheaths.name = "system:hand-nerve-sheaths-lod"
                setMaterial(AnatomyMaterial.handNeuralSheath, on: handSheaths)
                nerveRoot.addChild(handSheaths)
            }
            if let handNerves = loadEntity(
                AnatomyAssetCatalog.handNervousSystemFileName(for: parent.variant)
            ) {
                handNerves.name = "system:hand-nerves-lod"
                setMaterial(AnatomyMaterial.handNeuralCore, on: handNerves)
                nerveRoot.addChild(handNerves)
            }

            let paths = AnatomyNervePulseCatalog.paths(for: parent.variant)

            for (_, rawPoints) in paths {
                let points = smoothedPath(
                    rawPoints.map { $0 * anatomySceneScale },
                    samplesPerSegment: 5
                )
                let pulse = pulseEntity(
                    radius: 0.0042,
                    coreMaterial: AnatomyMaterial.nervePulse,
                    haloMaterial: AnatomyMaterial.nervePulseHalo
                )
                pulse.name = "effect:nerve-pulse"
                nerveRoot.addChild(pulse)
                nervePulseTracks.append(AnatomyPulseTrack(
                    entity: pulse,
                    points: points,
                    phase: 0,
                    speed: 0.27
                ))
            }
        }

        private func addCirculation() {
            for kind in AnatomyVascularKind.allCases {
                if let vessels = loadEntity(
                    AnatomyAssetCatalog.vascularSystemFileName(
                        kind: kind,
                        variant: parent.variant
                    )
                ) {
                    vessels.scale = .one
                    vessels.name = "system:vascular-\(kind)"
                    setMaterial(AnatomyMaterial.vascularCore(kind), on: vessels)
                    circulationRoot.addChild(vessels)
                    if kind == .arterial {
                        arterialPulseTargets.append(vessels)
                    }
                }
            }
        }

        private func vascularMesh(
            for branches: [AnatomyVascularBranch],
            radiusMultiplier: Float
        ) -> MeshResource? {
            let radialSegments = 7
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []

            for branch in branches where branch.points.count > 1 {
                let vertexStart = UInt32(positions.count)
                for pointIndex in branch.points.indices {
                    let previous = branch.points[max(0, pointIndex - 1)]
                    let next = branch.points[min(branch.points.count - 1, pointIndex + 1)]
                    let tangent = simd_normalize(next - previous)
                    let reference = abs(simd_dot(tangent, SIMD3(0, 1, 0))) > 0.92
                        ? SIMD3<Float>(1, 0, 0)
                        : SIMD3<Float>(0, 1, 0)
                    let normal = simd_normalize(simd_cross(tangent, reference))
                    let binormal = simd_normalize(simd_cross(tangent, normal))
                    let progress = Float(pointIndex) / Float(max(1, branch.points.count - 1))
                    let taper = 1 - progress * 0.24
                    let radius = branch.radius * radiusMultiplier * taper

                    for side in 0..<radialSegments {
                        let angle = Float(side) / Float(radialSegments) * .pi * 2
                        let radialNormal = normal * cos(angle) + binormal * sin(angle)
                        positions.append(branch.points[pointIndex] + radialNormal * radius)
                        normals.append(radialNormal)
                    }
                }

                for ring in 0..<(branch.points.count - 1) {
                    let ringStart = vertexStart + UInt32(ring * radialSegments)
                    let nextRingStart = ringStart + UInt32(radialSegments)
                    for side in 0..<radialSegments {
                        let nextSide = (side + 1) % radialSegments
                        let a = ringStart + UInt32(side)
                        let b = ringStart + UInt32(nextSide)
                        let c = nextRingStart + UInt32(side)
                        let d = nextRingStart + UInt32(nextSide)
                        indices.append(contentsOf: [a, c, b, b, c, d])
                    }
                }
            }

            guard !indices.isEmpty else { return nil }
            var descriptor = MeshDescriptor(name: "Anatomical vascular network")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }

        private func pulseEntity(
            radius: Float,
            coreMaterial: any RealityKit.Material,
            haloMaterial: any RealityKit.Material
        ) -> Entity {
            let root = Entity()
            let halo = ModelEntity(
                mesh: sphereMesh(radius: radius * 2.15),
                materials: [haloMaterial]
            )
            let core = ModelEntity(
                mesh: sphereMesh(radius: radius),
                materials: [coreMaterial]
            )
            root.addChild(halo)
            root.addChild(core)
            return root
        }

        private func sphereMesh(radius: Float) -> MeshResource {
            let key = Int((radius * 100_000).rounded())
            if let cached = sphereMeshes[key] { return cached }
            let mesh = MeshResource.generateSphere(radius: radius)
            sphereMeshes[key] = mesh
            return mesh
        }

        private func smoothedPath(
            _ points: [SIMD3<Float>],
            samplesPerSegment: Int
        ) -> [SIMD3<Float>] {
            guard points.count > 2 else { return points }
            var result: [SIMD3<Float>] = []
            for index in 0..<(points.count - 1) {
                let p0 = points[max(0, index - 1)]
                let p1 = points[index]
                let p2 = points[index + 1]
                let p3 = points[min(points.count - 1, index + 2)]
                for sample in 0..<samplesPerSegment {
                    let t = Float(sample) / Float(samplesPerSegment)
                    result.append(SIMD3(
                        catmullRom(p0.x, p1.x, p2.x, p3.x, t),
                        catmullRom(p0.y, p1.y, p2.y, p3.y, t),
                        catmullRom(p0.z, p1.z, p2.z, p3.z, t)
                    ))
                }
            }
            if let last = points.last { result.append(last) }
            return result
        }

        private func catmullRom(
            _ p0: Float,
            _ p1: Float,
            _ p2: Float,
            _ p3: Float,
            _ t: Float
        ) -> Float {
            let t2 = t * t
            let t3 = t2 * t
            return 0.5 * (
                2 * p1 +
                (p2 - p0) * t +
                (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                (-p0 + 3 * p1 - 3 * p2 + p3) * t3
            )
        }

        private func addAtmosphere(to root: Entity) {
            let positions: [SIMD3<Float>] = [
                SIMD3(-1.1, 1.55, -0.1), SIMD3(1.18, 1.15, 0.08),
                SIMD3(-1.32, 0.4, 0.18), SIMD3(1.28, -0.25, -0.12),
                SIMD3(-1.05, -1.15, 0.02), SIMD3(1.06, -1.45, 0.1),
                SIMD3(-0.72, 1.9, 0.2), SIMD3(0.82, 1.72, -0.18)
            ]
            for clusterIndex in 0..<2 {
                let indexedPositions = positions.enumerated().filter {
                    $0.offset.isMultiple(of: 2) == clusterIndex.isMultiple(of: 2)
                }
                let center = indexedPositions.reduce(SIMD3<Float>.zero) {
                    $0 + $1.element
                } / Float(indexedPositions.count)
                let points = indexedPositions.map { value in
                    (
                        position: value.element - center,
                        radius: value.offset.isMultiple(of: 3) ? Float(0.014) : Float(0.008)
                    )
                }
                guard let mesh = atmosphereClusterMesh(points) else { continue }
                let cluster = ModelEntity(
                    mesh: mesh,
                    materials: [AnatomyMaterial.atmosphereMote]
                )
                cluster.position = center
                root.addChild(cluster)
                atmosphereMotes.append(AnatomyMote(
                    entity: cluster,
                    basePosition: center,
                    phase: Float(clusterIndex) * 2.15
                ))
            }
        }

        private func atmosphereClusterMesh(
            _ points: [(position: SIMD3<Float>, radius: Float)]
        ) -> MeshResource? {
            var positions: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            positions.reserveCapacity(points.count * 6)
            indices.reserveCapacity(points.count * 24)

            for point in points {
                let start = UInt32(positions.count)
                let radius = point.radius
                positions.append(contentsOf: [
                    point.position + SIMD3(radius, 0, 0),
                    point.position + SIMD3(-radius, 0, 0),
                    point.position + SIMD3(0, radius, 0),
                    point.position + SIMD3(0, -radius, 0),
                    point.position + SIMD3(0, 0, radius),
                    point.position + SIMD3(0, 0, -radius)
                ])
                indices.append(contentsOf: [
                    start, start + 2, start + 4,
                    start + 2, start + 1, start + 4,
                    start + 1, start + 3, start + 4,
                    start + 3, start, start + 4,
                    start + 2, start, start + 5,
                    start + 1, start + 2, start + 5,
                    start + 3, start + 1, start + 5,
                    start, start + 3, start + 5
                ])
            }

            var descriptor = MeshDescriptor(name: "Anatomy atmosphere clusters")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }

        private func addBodyScan(to root: Entity) {
            guard let coreMesh = bodyScanRingMesh(tubeRadius: 0.0022),
                  let haloMesh = bodyScanRingMesh(tubeRadius: 0.0065)
            else { return }

            let halo = ModelEntity(
                mesh: haloMesh,
                materials: [AnatomyMaterial.scanHalo]
            )
            halo.name = "effect:body-scan-halo"
            root.addChild(halo)
            scanHaloEntity = halo

            let core = ModelEntity(
                mesh: coreMesh,
                materials: [AnatomyMaterial.scanCore]
            )
            core.name = "effect:body-scan-core"
            root.addChild(core)
            scanCoreEntity = core

            for index in 0..<2 {
                let echo = ModelEntity(
                    mesh: coreMesh,
                    materials: [AnatomyMaterial.scanEcho(index: index)]
                )
                echo.name = "effect:body-scan-echo-\(index)"
                root.addChild(echo)
                scanEchoEntities.append(echo)
            }
        }

        private func bodyScanRingMesh(tubeRadius: Float) -> MeshResource? {
            let pathSegments = 72
            let radialSegments = 10
            let horizontalRadius: Float = 0.34
            let depthRadius: Float = 0.20
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []

            for pathIndex in 0..<pathSegments {
                let angle = Float(pathIndex) / Float(pathSegments) * .pi * 2
                let center = SIMD3(
                    cos(angle) * horizontalRadius,
                    0,
                    sin(angle) * depthRadius
                )
                let outward = simd_normalize(SIMD3(
                    cos(angle) / horizontalRadius,
                    0,
                    sin(angle) / depthRadius
                ))
                for radialIndex in 0..<radialSegments {
                    let radialAngle = Float(radialIndex) / Float(radialSegments) * .pi * 2
                    let normal = outward * cos(radialAngle)
                        + SIMD3<Float>(0, 1, 0) * sin(radialAngle)
                    positions.append(center + normal * tubeRadius)
                    normals.append(normal)
                }
            }

            for pathIndex in 0..<pathSegments {
                let nextPath = (pathIndex + 1) % pathSegments
                for radialIndex in 0..<radialSegments {
                    let nextRadial = (radialIndex + 1) % radialSegments
                    let a = UInt32(pathIndex * radialSegments + radialIndex)
                    let b = UInt32(pathIndex * radialSegments + nextRadial)
                    let c = UInt32(nextPath * radialSegments + radialIndex)
                    let d = UInt32(nextPath * radialSegments + nextRadial)
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }

            var descriptor = MeshDescriptor(name: "Body-area anatomical scan ring")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }

        private func bodyScanEnvelope(at height: Float) -> SIMD2<Float> {
            let profile = anatomyBodyScanProfile
            guard height > profile[0].height else { return profile[0].radius }
            guard height < profile[profile.count - 1].height else {
                return profile[profile.count - 1].radius
            }
            for index in 0..<(profile.count - 1) {
                let lower = profile[index]
                let upper = profile[index + 1]
                guard height <= upper.height else { continue }
                let previous = profile[max(0, index - 1)]
                let next = profile[min(profile.count - 1, index + 2)]
                let span = upper.height - lower.height
                let progress = (height - lower.height) / span
                let lowerSlope = (upper.radius - previous.radius)
                    / (upper.height - previous.height)
                let upperSlope = (next.radius - lower.radius)
                    / (next.height - lower.height)
                let progressSquared = progress * progress
                let progressCubed = progressSquared * progress
                let lowerWeight = 2 * progressCubed - 3 * progressSquared + 1
                let lowerSlopeWeight = progressCubed - 2 * progressSquared + progress
                let upperWeight = -2 * progressCubed + 3 * progressSquared
                let upperSlopeWeight = progressCubed - progressSquared
                let lowerValue = lower.radius * lowerWeight
                    + lowerSlope * (span * lowerSlopeWeight)
                let upperValue = upper.radius * upperWeight
                    + upperSlope * (span * upperSlopeWeight)
                let value = lowerValue + upperValue
                let minimum = simd_min(lower.radius, upper.radius)
                let maximum = simd_max(lower.radius, upper.radius)
                return simd_clamp(value, minimum, maximum)
            }
            return profile[profile.count - 1].radius
        }

        private func loadEntity(_ fileName: String) -> Entity? {
            guard let url = Bundle.main.url(
                forResource: fileName,
                withExtension: "usdc",
                subdirectory: "BodyAnatomy"
            ) else { return nil }
            if let model = try? ModelEntity.loadModel(contentsOf: url) {
                // Normalize Model I/O's imported USD units to the meter-scale scene used
                // by the camera, selection map, and generated nerve paths.
                model.scale = SIMD3(repeating: anatomySceneScale)
                return model
            }
            guard let entity = try? Entity.load(contentsOf: url) else { return nil }
            entity.scale = SIMD3(repeating: anatomySceneScale)
            return entity
        }

        private func setMaterial(_ material: any RealityKit.Material, on entity: Entity) {
            if var component = entity.components[ModelComponent.self] {
                component.materials = Array(
                    repeating: material,
                    count: max(1, component.materials.count)
                )
                entity.components.set(component)
            }
            for child in entity.children {
                setMaterial(material, on: child)
            }
        }

        private func addLights(to anchor: AnchorEntity) {
            let key = DirectionalLight()
            key.light.intensity = 4_400
            key.light.color = UIColor(red: 0.78, green: 0.91, blue: 1, alpha: 1)
            key.orientation = simd_quatf(angle: -0.48, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: -0.72, axis: SIMD3(0, 1, 0))
            anchor.addChild(key)

            let rim = PointLight()
            rim.light.intensity = 2_600
            rim.light.attenuationRadius = 4.5
            rim.light.color = UIColor(red: 0.12, green: 0.72, blue: 1, alpha: 1)
            rim.position = SIMD3(-1.4, 0.9, 0.3)
            anchor.addChild(rim)

            let front = PointLight()
            front.light.intensity = 4_000
            front.light.attenuationRadius = 5.2
            front.light.color = UIColor(red: 0.82, green: 0.96, blue: 1, alpha: 1)
            front.position = SIMD3(0, 0.25, 2.15)
            anchor.addChild(front)

            let faceFill = PointLight()
            faceFill.light.intensity = 850
            faceFill.light.attenuationRadius = 2.2
            faceFill.light.color = UIColor(
                red: 0.94,
                green: 0.82,
                blue: 0.76,
                alpha: 1
            )
            faceFill.position = SIMD3(0, 1.12, 1.35)
            faceFill.isEnabled = parent.activeLayer == .bodyAreas
            anchor.addChild(faceFill)
            faceFillLight = faceFill
        }

        private func updateLayerVisibility() {
            faceFillLight?.isEnabled = parent.activeLayer == .bodyAreas
                && !isShowingHandDetail
                && !isShowingFootDetail
            if isShowingHandDetail {
                handDetailRoot.isEnabled = true
                handDetailSelectionProxyRoot.isEnabled = true
                footDetailRoot.isEnabled = false
                footDetailSelectionProxyRoot.isEnabled = false
                surfaceRoot.isEnabled = false
                selectionProxyRoot.isEnabled = false
                ghostRoot.isEnabled = false
                muscleRoot.isEnabled = false
                skeletonRoot.isEnabled = false
                nerveRoot.isEnabled = false
                circulationRoot.isEnabled = false
                organRoot.isEnabled = false
                organSelectionProxyRoot.isEnabled = false
                scanRoot.isEnabled = false
                return
            }

            if isShowingFootDetail {
                handDetailRoot.isEnabled = false
                handDetailSelectionProxyRoot.isEnabled = false
                footDetailRoot.isEnabled = true
                footDetailSelectionProxyRoot.isEnabled = true
                surfaceRoot.isEnabled = false
                selectionProxyRoot.isEnabled = false
                ghostRoot.isEnabled = false
                muscleRoot.isEnabled = false
                skeletonRoot.isEnabled = false
                nerveRoot.isEnabled = false
                circulationRoot.isEnabled = false
                organRoot.isEnabled = false
                organSelectionProxyRoot.isEnabled = false
                scanRoot.isEnabled = false
                return
            }

            handDetailRoot.isEnabled = false
            handDetailSelectionProxyRoot.isEnabled = false
            footDetailRoot.isEnabled = false
            footDetailSelectionProxyRoot.isEnabled = false
            if parent.activeLayer == .bodyAreas {
                ensureSurfaceLoaded()
                ghostRoot.children.removeAll()
            } else {
                ensureGhostLoaded()
                surfaceRoot.children.removeAll()
            }
            surfaceRoot.isEnabled = parent.activeLayer == .bodyAreas
            selectionProxyRoot.isEnabled = parent.activeLayer != .organs
            ghostRoot.isEnabled = parent.activeLayer != .bodyAreas
            let ghostOpacity: CGFloat = switch parent.activeLayer {
            case .organs: 0.07
            case .nerves: 0.05
            case .muscles, .joints: 0.025
            case .bodyAreas: 0
            }
            setMaterial(AnatomyMaterial.ghostSkin(opacity: ghostOpacity), on: ghostRoot)
            muscleRoot.isEnabled = parent.activeLayer == .muscles
            skeletonRoot.isEnabled = parent.activeLayer == .joints
            nerveRoot.isEnabled = parent.activeLayer == .nerves
            circulationRoot.isEnabled = parent.activeLayer == .organs
            organRoot.isEnabled = parent.activeLayer == .organs
            organSelectionProxyRoot.isEnabled = parent.activeLayer == .organs
            scanRoot.isEnabled = parent.activeLayer == .bodyAreas
        }

        private func updateRegionVisibility() {
            for (structureID, entities) in entitiesByStructureID {
                guard let structure = BodyAnatomyCatalog.structure(id: structureID) else { continue }
                let visible = parent.regionFilter == .all || structure.region == parent.regionFilter
                for entity in entities {
                    entity.isEnabled = visible
                }
            }
        }

        private func updateMaterials() {
            for (structureID, entities) in entitiesByStructureID {
                guard let specification = specificationsByStructureID[structureID] else { continue }
                let selected = parent.selectedStructureIDs.contains(structureID)
                let material = AnatomyMaterial.material(for: specification, selected: selected)
                for entity in entities {
                    setMaterial(material, on: entity)
                }
            }
        }

        private func updateSelectionMarkers() {
            markerRoot.children.removeAll()
            for structureID in parent.selectedStructureIDs {
                guard let structure = BodyAnatomyCatalog.structure(id: structureID),
                      structure.layer == parent.activeLayer,
                      parent.regionFilter == .all || structure.region == parent.regionFilter
                else { continue }
                let position = markerPositions[structureID]
                    ?? selectionMarkerPosition(
                        for: structureID,
                        rawHitPosition: BodySurfaceMapper.markerPosition(
                            for: structureID,
                            variant: parent.variant
                        )
                    )
                addMarker(at: position, structureID: structureID)
            }
        }

        private func addMarker(at position: SIMD3<Float>, structureID: String) {
            let root = Entity()
            root.position = displayedMarkerPosition(from: position)
            root.name = "marker:\(structureID)"

            let core = ModelEntity(
                mesh: sphereMesh(radius: 0.022),
                materials: [AnatomyMaterial.selectionCore]
            )
            let halo = ModelEntity(
                mesh: sphereMesh(radius: 0.044),
                materials: [AnatomyMaterial.selectionHalo]
            )
            root.addChild(halo)
            root.addChild(core)
            markerRoot.addChild(root)
        }

        private func displayedMarkerPosition(
            from anatomicalPosition: SIMD3<Float>
        ) -> SIMD3<Float> {
            guard parent.activeLayer == .joints else { return anatomicalPosition }
            return cameraFacingMarkerPosition(
                from: anatomicalPosition,
                canonicalDepth: isShowingExtremityDetail ? 0.055 : 0.14
            )
        }

        private func refreshJointMarkerDepthOffsets() {
            guard parent.activeLayer == .joints else { return }
            for marker in markerRoot.children {
                guard marker.name.hasPrefix("marker:") else { continue }
                let structureID = String(marker.name.dropFirst("marker:".count))
                let anchor = markerPositions[structureID]
                    ?? selectionMarkerPosition(
                        for: structureID,
                        rawHitPosition: BodySurfaceMapper.markerPosition(
                            for: structureID,
                            variant: parent.variant
                        )
                    )
                marker.position = displayedMarkerPosition(from: anchor)
            }
        }

        private func applyInteractionTransform(animated: Bool) {
            let focus = focusTransform(
                parent.regionFilter,
                handDetailFocus: parent.handDetailFocus,
                footDetailFocus: parent.footDetailFocus
            )
            let scale = focus.scale * zoom
            let rotation = interactionRotation
            let translation = rotation.act(-focus.pivot * scale)
            let transform = Transform(
                scale: SIMD3(repeating: scale),
                rotation: rotation,
                translation: translation
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
            refreshJointMarkerDepthOffsets()
        }

        private var interactionRotation: simd_quatf {
            let pitchRotation = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
            let yawRotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            return yawRotation * pitchRotation
        }

        private func focusTransform(
            _ region: BodyRegionFilter,
            handDetailFocus: BodyHandDetailFocus,
            footDetailFocus: BodyFootDetailFocus
        ) -> (scale: Float, pivot: SIMD3<Float>) {
            switch region {
            // Leave enough vertical headroom for the taller male atlas when
            // the user pitches the model at side and oblique angles.
            case .all:
                (0.98, .zero)
            case .headAndNeck:
                (2.15, SIMD3(0, 0.688 * anatomySceneScale, 0))
            case .torso:
                (1.72, SIMD3(0, 0.244 * anatomySceneScale, 0))
            case .armsAndHands:
                switch handDetailFocus {
                case .both:
                    (1.4, SIMD3(0, 0.229 * anatomySceneScale, 0))
                case .left, .right:
                    (2.15, .zero)
                }
            case .legsAndFeet:
                switch footDetailFocus {
                case .both:
                    (1.48, SIMD3(0, -0.486 * anatomySceneScale, 0))
                case .left, .right:
                    (
                        4.8,
                        FootDetailStructureMapper.focusPivot(
                            focus: footDetailFocus,
                            variant: parent.variant
                        ) * anatomySceneScale
                    )
                }
            }
        }

        private func startAnimationLoop() {
            animationDisplayLink?.invalidate()
            lastAnimationTimestamp = nil
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(handleAnimationFrame(_:))
            )
            animationDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
            refreshAnimationLoop()
        }

        private func refreshAnimationLoop() {
            guard let animationDisplayLink else { return }
            let frameRate: Int
            if isPerformanceConstrained {
                frameRate = 15
            } else if isShowingExtremityDetail
                        || parent.activeLayer == .muscles
                        || parent.activeLayer == .joints {
                // Focused extremities and static tissue layers only carry slow
                // ambient motion, which remains smooth without a 30 Hz scene tick.
                frameRate = 20
            } else {
                frameRate = 30
            }
            if configuredAnimationFrameRate != frameRate {
                configuredAnimationFrameRate = frameRate
                animationDisplayLink.preferredFramesPerSecond = frameRate
                lastAnimationTimestamp = nil
            }
            let shouldPause = !isApplicationActive || parent.reduceMotion
            if animationDisplayLink.isPaused != shouldPause {
                animationDisplayLink.isPaused = shouldPause
                lastAnimationTimestamp = nil
            }
        }

        @objc private func handleAnimationFrame(_ displayLink: CADisplayLink) {
            guard arView?.window != nil,
                  isApplicationActive,
                  !parent.reduceMotion
            else {
                lastAnimationTimestamp = nil
                return
            }
            let timestamp = displayLink.timestamp
            let deltaTime = lastAnimationTimestamp.map { timestamp - $0 }
                ?? displayLink.duration
            lastAnimationTimestamp = timestamp
            updateAnimation(deltaTime: Float(deltaTime))
        }

        private func updateAnimation(deltaTime: Float) {
            let frameDelta = min(deltaTime, 0.1)
            elapsed += frameDelta
            let motionScale: Float = 1
            let breath = sin(elapsed * 1.18) * motionScale
            breathingRoot.scale = SIMD3(1, 1 + breath * 0.0018, 1 + breath * 0.0065)
            breathingRoot.position.y = sin(elapsed * 0.64) * 0.008 * motionScale

            if parent.activeLayer == .bodyAreas {
                animateBodyScan(motionScale: motionScale, deltaTime: frameDelta)
            }

            for mote in atmosphereMotes {
                mote.entity.position = mote.basePosition + SIMD3(
                    sin(elapsed * 0.42 + mote.phase) * 0.045,
                    sin(elapsed * 0.31 + mote.phase) * 0.07,
                    cos(elapsed * 0.37 + mote.phase) * 0.035
                ) * motionScale
                mote.entity.orientation = simd_quatf(
                    angle: sin(elapsed * 0.16 + mote.phase) * 0.035 * motionScale,
                    axis: SIMD3(0, 0, 1)
                )
            }

            if parent.activeLayer == .nerves {
                animatePulseTracks(nervePulseTracks, motionScale: motionScale)
            } else if parent.activeLayer == .organs {
                animateCardiovascularSystem(motionScale: motionScale)
            }

            if parent.activeLayer == .organs {
                let phase = cardiacPhase
                let systole = gaussianPulse(phase: phase, center: 0.075, width: 0.034)
                let rebound = gaussianPulse(phase: phase, center: 0.17, width: 0.05)
                let contraction = systole * motionScale
                let recovery = rebound * motionScale
                let radialScale = 1 + contraction * 0.006 - recovery * 0.002
                let longitudinalScale = 1 - contraction * 0.016 + recovery * 0.0055
                for entity in entitiesByStructureID["organ.heart"] ?? [] {
                    applyCenteredScale(
                        SIMD3(radialScale, longitudinalScale, radialScale),
                        to: entity
                    )
                }
                let lungScale = 1 + breath * 0.012
                for structureID in ["organ.lung.left", "organ.lung.right"] {
                    for entity in entitiesByStructureID[structureID] ?? [] {
                        applyCenteredScale(
                            SIMD3(1, lungScale, lungScale),
                            to: entity
                        )
                    }
                }
            }

            if !markerRoot.children.isEmpty {
                let markerPulse = 1 + sin(elapsed * 4.4) * 0.09 * motionScale
                for marker in markerRoot.children {
                    marker.scale = SIMD3(repeating: markerPulse)
                }
            }
        }

        private func resetAnimationState() {
            breathingRoot.scale = .one
            breathingRoot.position = .zero

            for mote in atmosphereMotes {
                mote.entity.position = mote.basePosition
                mote.entity.orientation = simd_quatf(
                    angle: 0,
                    axis: SIMD3(0, 1, 0)
                )
            }

            if parent.activeLayer == .bodyAreas {
                smoothedScanEnvelope = nil
                animateBodyScan(motionScale: 0, deltaTime: 1)
            } else if parent.activeLayer == .nerves {
                animatePulseTracks(nervePulseTracks, motionScale: 0)
            } else if parent.activeLayer == .organs {
                lastArterialPulseStep = -1
                animateCardiovascularSystem(motionScale: 0)
                for structureID in [
                    "organ.heart",
                    "organ.lung.left",
                    "organ.lung.right"
                ] {
                    for entity in entitiesByStructureID[structureID] ?? [] {
                        applyCenteredScale(.one, to: entity)
                    }
                }
            }

            for marker in markerRoot.children {
                marker.scale = .one
            }
            refreshJointMarkerDepthOffsets()
        }

        private func refreshPerformanceConstraint() {
            let processInfo = ProcessInfo.processInfo
            let isThermallyConstrained: Bool = switch processInfo.thermalState {
            case .serious, .critical: true
            default: false
            }
            isPerformanceConstrained = processInfo.isLowPowerModeEnabled
                || isThermallyConstrained
            refreshAnimationLoop()
        }

        private func animateBodyScan(motionScale: Float, deltaTime: Float) {
            let phase = elapsed * 0.48
            let travelWave = motionScale == 0
                ? Float.zero
                : sin(phase) + sin(phase * 3) * 0.035
            let progress = (travelWave + 1) * 0.5
            let canonicalHeight = -0.88 + progress * 1.72
            let targetEnvelope = bodyScanEnvelope(at: canonicalHeight)
            let envelope: SIMD2<Float>
            if let currentEnvelope = smoothedScanEnvelope {
                let response = 1 - exp(-deltaTime * 11)
                envelope = currentEnvelope + (targetEnvelope - currentEnvelope) * response
            } else {
                envelope = targetEnvelope
            }
            smoothedScanEnvelope = envelope
            let variantWidth: Float = parent.variant == .female ? 1 : 1.055

            scanRoot.position.y = canonicalHeight * anatomySceneScale
            scanRoot.scale = SIMD3(
                anatomySceneScale * envelope.x / 0.34 * variantWidth,
                anatomySceneScale,
                anatomySceneScale * envelope.y / 0.20
            )
            scanRoot.orientation = simd_quatf(
                angle: sin(elapsed * 0.31) * 0.035 * motionScale,
                axis: SIMD3(1, 0, 0)
            ) * simd_quatf(
                angle: elapsed * 0.055 * motionScale,
                axis: SIMD3(0, 1, 0)
            )

            let shimmer = sin(elapsed * 2.1) * 0.018 * motionScale
            scanCoreEntity?.scale = SIMD3(repeating: 1 + shimmer)
            scanHaloEntity?.scale = SIMD3(repeating: 1.035 + shimmer * 1.4)

            let verticalVelocity = cos(phase) + cos(phase * 3) * 0.105
            let direction = tanh(verticalVelocity * 3.2) * motionScale
            for (index, echo) in scanEchoEntities.enumerated() {
                let distance = Float(index + 1)
                echo.position.y = -direction * distance * 0.014
                let echoScale = 1 + distance * 0.018 + shimmer * 0.7
                echo.scale = SIMD3(repeating: echoScale)
            }
        }

        private func animatePulseTracks(
            _ tracks: [AnatomyPulseTrack],
            motionScale: Float
        ) {
            for track in tracks {
                let progress: Float
                if motionScale == 0 {
                    progress = track.phase.truncatingRemainder(dividingBy: 1)
                } else {
                    let raw = elapsed * track.speed + track.phase
                    progress = raw - floor(raw)
                }
                let sample = sample(along: track, progress: progress)
                track.entity.position = sample.position
                track.entity.orientation = simd_quatf(
                    from: SIMD3(0, 1, 0),
                    to: sample.tangent
                )
                let flash = 0.82 + sin(progress * .pi) * 0.42 * motionScale
                track.entity.scale = SIMD3(flash, flash * track.stretch, flash)
            }
        }

        private var cardiacPhase: Float {
            let period: Float = 1.05
            let raw = elapsed / period
            return raw - floor(raw)
        }

        private func gaussianPulse(phase: Float, center: Float, width: Float) -> Float {
            let distance = (phase - center) / width
            return exp(-(distance * distance))
        }

        private func animateCardiovascularSystem(motionScale: Float) {
            let phase = cardiacPhase
            let pressure = max(
                gaussianPulse(phase: phase, center: 0.145, width: 0.07),
                gaussianPulse(phase: phase, center: 0.31, width: 0.075) * 0.16
            ) * motionScale
            let pulseStep = Int((pressure * 12).rounded())
            guard pulseStep != lastArterialPulseStep else { return }
            lastArterialPulseStep = pulseStep
            let material = AnatomyMaterial.arterialPulseFrames[pulseStep]
            for entity in arterialPulseTargets {
                setMaterial(material, on: entity)
            }
        }

        private func applyCenteredScale(
            _ relativeScale: SIMD3<Float>,
            to entity: Entity
        ) {
            guard let restPose = restPosesByEntity[ObjectIdentifier(entity)] else { return }
            entity.scale = restPose.scale * relativeScale
            entity.position = restPose.position
                + (restPose.center - restPose.position)
                * (SIMD3(repeating: 1) - relativeScale)
        }

        private func sample(
            along track: AnatomyPulseTrack,
            progress: Float
        ) -> (position: SIMD3<Float>, tangent: SIMD3<Float>) {
            sample(
                points: track.points,
                cumulativeDistances: track.cumulativeDistances,
                totalLength: track.totalLength,
                progress: progress
            )
        }

        private func sample(
            points: [SIMD3<Float>],
            cumulativeDistances: [Float],
            totalLength: Float,
            progress: Float
        ) -> (position: SIMD3<Float>, tangent: SIMD3<Float>) {
            guard let first = points.first, points.count > 1 else {
                return (points.first ?? .zero, SIMD3(0, 1, 0))
            }
            guard totalLength > 0 else { return (first, SIMD3(0, 1, 0)) }
            let distance = progress * totalLength
            var lowerBound = 1
            var upperBound = cumulativeDistances.count - 1
            while lowerBound < upperBound {
                let midpoint = (lowerBound + upperBound) / 2
                if cumulativeDistances[midpoint] < distance {
                    lowerBound = midpoint + 1
                } else {
                    upperBound = midpoint
                }
            }
            let endIndex = min(lowerBound, points.count - 1)
            let startIndex = max(0, endIndex - 1)
            let segmentStart = cumulativeDistances[startIndex]
            let segmentLength = max(
                cumulativeDistances[endIndex] - segmentStart,
                .leastNonzeroMagnitude
            )
            let amount = min(1, max(0, (distance - segmentStart) / segmentLength))
            let tangent = simd_normalize(points[endIndex] - points[startIndex])
            return (simd_mix(
                points[startIndex],
                points[endIndex],
                SIMD3(repeating: amount)
            ), tangent)
        }
    }
}

private struct AnatomyPulseTrack {
    let entity: Entity
    let points: [SIMD3<Float>]
    let phase: Float
    let speed: Float
    let stretch: Float
    let cumulativeDistances: [Float]
    let totalLength: Float

    init(
        entity: Entity,
        points: [SIMD3<Float>],
        phase: Float,
        speed: Float,
        stretch: Float = 1
    ) {
        self.entity = entity
        self.points = points
        self.phase = phase
        self.speed = speed
        self.stretch = stretch
        var distances: [Float] = [0]
        distances.reserveCapacity(points.count)
        for (start, end) in zip(points, points.dropFirst()) {
            distances.append(distances[distances.count - 1] + simd_length(end - start))
        }
        cumulativeDistances = distances
        totalLength = distances.last ?? 0
    }
}

private struct AnatomyMote {
    let entity: Entity
    let basePosition: SIMD3<Float>
    let phase: Float
}

private struct AnatomyRestPose {
    let center: SIMD3<Float>
    let position: SIMD3<Float>
    let scale: SIMD3<Float>
}

private enum AnatomyVascularKind: CaseIterable {
    case arterial
    case venous

    var color: UIColor {
        switch self {
        case .arterial:
            UIColor(red: 0.95, green: 0.045, blue: 0.15, alpha: 1)
        case .venous:
            UIColor(red: 0.055, green: 0.38, blue: 0.9, alpha: 1)
        }
    }
}

private struct AnatomyVascularBranch {
    let points: [SIMD3<Float>]
    let radius: Float
}

private enum HandDetailStructureMapper {
    static func structureID(
        layer: BodyAnatomyLayer,
        focus: BodyHandDetailFocus,
        at renderedPoint: SIMD3<Float>
    ) -> String? {
        guard focus != .both else { return nil }
        let side = focus == .left ? "left" : "right"
        let point = SIMD3(
            focus == .right ? -renderedPoint.x : renderedPoint.x,
            renderedPoint.y,
            renderedPoint.z
        )

        switch layer {
        case .bodyAreas:
            if point.y < -0.205 { return "body.wrist.\(side)" }
            if point.y < -0.105 { return "body.hand.\(side)" }
            return "body.\(digitID(at: point)).\(side)"
        case .muscles:
            return "muscle.hand.\(side)"
        case .joints:
            if point.y < -0.105 { return "joint.wrist.\(side)" }
            return "joint.\(digitID(at: point)).\(side)"
        case .nerves:
            return point.x < -0.04
                ? "nerve.ulnar.\(side)"
                : "nerve.median.\(side)"
        case .organs:
            return nil
        }
    }

    static func markerPosition(
        for structureID: String,
        focus: BodyHandDetailFocus,
        variant: BodyModelVariant
    ) -> SIMD3<Float>? {
        guard focus != .both else { return nil }

        let canonical: SIMD3<Float>
        if structureID.contains("wrist") {
            canonical = SIMD3(0, -0.255, 0.055)
        } else if structureID.contains("thumb") {
            canonical = SIMD3(0.125, 0.055, 0.055)
        } else if structureID.contains("indexFinger") {
            canonical = SIMD3(0.073, 0.135, 0.05)
        } else if structureID.contains("middleFinger") {
            canonical = SIMD3(0.015, 0.155, 0.05)
        } else if structureID.contains("ringFinger") {
            canonical = SIMD3(-0.055, 0.145, 0.05)
        } else if structureID.contains("littleFinger") {
            canonical = SIMD3(-0.115, 0.12, 0.05)
        } else if structureID.contains("ulnar") {
            canonical = SIMD3(-0.075, -0.04, 0.045)
        } else if structureID.contains("median") {
            canonical = SIMD3(0.035, -0.025, 0.045)
        } else {
            canonical = SIMD3(0, -0.105, 0.065)
        }

        let mirror: Float = focus == .right ? -1 : 1
        let variantScale: SIMD3<Float> = variant == .female
            ? SIMD3(1, 1, 1)
            : SIMD3(1.08, 1.03, 1.08)
        return SIMD3(canonical.x * mirror, canonical.y, canonical.z)
            * variantScale * anatomySceneScale
    }

    private static func digitID(at point: SIMD3<Float>) -> String {
        if point.x > 0.105 || (point.x > 0.07 && point.y < 0.115) {
            return "thumb"
        }
        if point.x > 0.05 { return "indexFinger" }
        if point.x > -0.03 { return "middleFinger" }
        if point.x > -0.095 { return "ringFinger" }
        return "littleFinger"
    }
}

private enum FootDetailStructureMapper {
    static func structureID(
        layer: BodyAnatomyLayer,
        focus: BodyFootDetailFocus,
        at point: SIMD3<Float>,
        variant: BodyModelVariant,
        soleView: Bool = false
    ) -> String? {
        guard focus != .both else { return nil }
        let frame = frame(focus: focus, variant: variant)
        let side = focus == .left ? "left" : "right"
        let point = soleView ? SIMD3(point.x, point.y, -point.z) : point
        let lateral = (point.x - frame.centerX) * frame.sideSign / frame.halfWidth

        switch layer {
        case .bodyAreas:
            if point.y > frame.ankleBoundaryY, point.z > -0.065 {
                return "body.ankle.\(side)"
            }
            if point.z > frame.heelBoundaryZ { return "body.heel.\(side)" }
            if point.z < frame.toeBoundaryZ {
                return "body.\(toeID(lateral: lateral)).\(side)"
            }
            if point.y <= frame.soleBoundaryY {
                if point.z < -0.035 { return "body.ballOfFoot.\(side)" }
                if lateral < -0.08 { return "body.arch.\(side)" }
                return "body.sole.\(side)"
            }
            return "body.topOfFoot.\(side)"
        case .muscles:
            if point.z > 0.045, point.y > frame.soleBoundaryY {
                return "muscle.achilles.\(side)"
            }
            return "muscle.foot.\(side)"
        case .joints:
            if point.y > frame.ankleBoundaryY, point.z > -0.065 {
                return "joint.ankle.\(side)"
            }
            if point.z > frame.heelBoundaryZ { return "joint.heel.\(side)" }
            if point.z < frame.toeBoundaryZ {
                return "joint.\(toeID(lateral: lateral)).\(side)"
            }
            return "joint.midfoot.\(side)"
        case .nerves:
            if point.y <= frame.soleBoundaryY {
                return "nerve.plantar.\(side)"
            }
            return lateral > 0.12
                ? "nerve.fibular.\(side)"
                : "nerve.tibial.\(side)"
        case .organs:
            return nil
        }
    }

    static func markerPosition(
        for structureID: String,
        focus: BodyFootDetailFocus,
        variant: BodyModelVariant,
        soleView: Bool = false
    ) -> SIMD3<Float>? {
        guard focus != .both else { return nil }
        let frame = frame(focus: focus, variant: variant)
        let point: SIMD3<Float>

        if structureID.contains("ankle") {
            point = frame.ankle
        } else if structureID.contains("achilles") {
            point = SIMD3(frame.centerX, frame.topY + 0.018, 0.062)
        } else if structureID.contains("heel") {
            point = SIMD3(frame.centerX, frame.soleY + 0.012, 0.074)
        } else if structureID.contains("topOfFoot") {
            point = SIMD3(frame.centerX, frame.topY, -0.005)
        } else if structureID.contains("sole") {
            point = SIMD3(frame.centerX, frame.soleY, -0.018)
        } else if structureID.contains("arch") {
            point = SIMD3(
                frame.centerX - frame.sideSign * frame.halfWidth * 0.36,
                frame.soleY,
                -0.012
            )
        } else if structureID.contains("ballOfFoot") {
            point = SIMD3(frame.centerX, frame.soleY + 0.004, -0.052)
        } else if structureID.contains("greatToe") {
            point = toeMarker(frame: frame, lateral: -0.70, z: frame.toeTipZ)
        } else if structureID.contains("secondToe") {
            point = toeMarker(frame: frame, lateral: -0.34, z: frame.toeTipZ + 0.010)
        } else if structureID.contains("middleToe") {
            point = toeMarker(frame: frame, lateral: 0, z: frame.toeTipZ + 0.018)
        } else if structureID.contains("fourthToe") {
            point = toeMarker(frame: frame, lateral: 0.34, z: frame.toeTipZ + 0.028)
        } else if structureID.contains("littleToe") {
            point = toeMarker(frame: frame, lateral: 0.70, z: frame.toeTipZ + 0.038)
        } else if structureID.contains("midfoot") || structureID.contains("foot") {
            point = SIMD3(frame.centerX, frame.topY, -0.012)
        } else if structureID.contains("plantar") {
            point = SIMD3(frame.centerX, frame.soleY, -0.020)
        } else if structureID.contains("fibular") {
            point = SIMD3(
                frame.centerX + frame.sideSign * frame.halfWidth * 0.38,
                frame.topY,
                -0.01
            )
        } else if structureID.contains("tibial") {
            point = SIMD3(
                frame.centerX - frame.sideSign * frame.halfWidth * 0.20,
                frame.topY + 0.015,
                0.036
            )
        } else {
            return nil
        }

        let orientedPoint = soleView
            ? SIMD3(point.x, point.y, -point.z)
            : point
        return orientedPoint * anatomySceneScale
    }

    static func focusPivot(
        focus: BodyFootDetailFocus,
        variant: BodyModelVariant
    ) -> SIMD3<Float> {
        let frame = frame(focus: focus, variant: variant)
        return SIMD3(frame.centerX, frame.focusY, -0.025)
    }

    static func selectionProxyShapes(
        focus: BodyFootDetailFocus,
        variant: BodyModelVariant,
        soleView: Bool
    ) -> [ShapeResource] {
        guard focus != .both else { return [] }
        let frame = frame(focus: focus, variant: variant)
        let scale = SIMD3<Float>(repeating: anatomySceneScale)

        func oriented(_ point: SIMD3<Float>) -> SIMD3<Float> {
            soleView ? SIMD3(point.x, point.y, -point.z) : point
        }

        func box(center: SIMD3<Float>, size: SIMD3<Float>) -> ShapeResource {
            ShapeResource.generateBox(size: size * scale).offsetBy(
                translation: oriented(center) * scale
            )
        }

        let footBottom = frame.soleY - 0.006
        let footTop = frame.topY + 0.012
        let footWidth = frame.halfWidth * 2.45
        let mainToe = frame.toeBoundaryZ - 0.014
        let mainHeel = frame.heelBoundaryZ + 0.018
        let ankleTop = frame.ankleBoundaryY
            + (variant == .female ? 0.13 : 0.15)
        let ankleBottom = frame.topY - 0.012

        return [
            box(
                center: SIMD3(
                    frame.centerX,
                    (footBottom + footTop) / 2,
                    (mainToe + mainHeel) / 2
                ),
                size: SIMD3(
                    footWidth,
                    footTop - footBottom,
                    mainHeel - mainToe
                )
            ),
            box(
                center: SIMD3(
                    frame.centerX,
                    (footBottom + footTop) / 2,
                    (frame.toeTipZ + frame.toeBoundaryZ) / 2
                ),
                size: SIMD3(
                    footWidth * 1.02,
                    footTop - footBottom,
                    frame.toeBoundaryZ - frame.toeTipZ + 0.014
                )
            ),
            box(
                center: SIMD3(
                    frame.centerX,
                    (footBottom + footTop) / 2,
                    frame.heelBoundaryZ + 0.034
                ),
                size: SIMD3(
                    footWidth * 0.82,
                    footTop - footBottom + 0.012,
                    0.092
                )
            ),
            box(
                center: SIMD3(
                    frame.centerX,
                    (ankleBottom + ankleTop) / 2,
                    -0.018
                ),
                size: SIMD3(
                    footWidth * 0.68,
                    ankleTop - ankleBottom,
                    0.09
                )
            )
        ]
    }

    private static func toeID(lateral: Float) -> String {
        if lateral < -0.44 { return "greatToe" }
        if lateral < -0.12 { return "secondToe" }
        if lateral < 0.18 { return "middleToe" }
        if lateral < 0.48 { return "fourthToe" }
        return "littleToe"
    }

    private static func toeMarker(
        frame: FootDetailFrame,
        lateral: Float,
        z: Float
    ) -> SIMD3<Float> {
        SIMD3(
            frame.centerX + frame.sideSign * frame.halfWidth * lateral,
            frame.topY - 0.012,
            z
        )
    }

    private static func frame(
        focus: BodyFootDetailFocus,
        variant: BodyModelVariant
    ) -> FootDetailFrame {
        let isLeft = focus == .left
        if variant == .female {
            return FootDetailFrame(
                sideSign: isLeft ? 1 : -1,
                centerX: isLeft ? 0.141 : -0.160,
                halfWidth: 0.043,
                soleY: -0.790,
                topY: -0.747,
                focusY: -0.735,
                ankleBoundaryY: -0.716,
                soleBoundaryY: -0.775,
                toeBoundaryZ: -0.082,
                toeTipZ: -0.151,
                heelBoundaryZ: 0.053,
                ankle: isLeft
                    ? SIMD3(0.143649, -0.774522, -0.020298)
                    : SIMD3(-0.162165, -0.776210, -0.011443)
            )
        }
        return FootDetailFrame(
            sideSign: isLeft ? 1 : -1,
            centerX: isLeft ? 0.214 : -0.214,
            halfWidth: 0.057,
            soleY: -0.909,
            topY: -0.874,
            focusY: -0.842,
            ankleBoundaryY: -0.825,
            soleBoundaryY: -0.895,
            toeBoundaryZ: -0.078,
            toeTipZ: -0.146,
            heelBoundaryZ: 0.049,
            ankle: isLeft
                ? SIMD3(0.209669, -0.883374, -0.039116)
                : SIMD3(-0.210147, -0.883491, -0.038887)
        )
    }
}

private struct FootDetailFrame {
    let sideSign: Float
    let centerX: Float
    let halfWidth: Float
    let soleY: Float
    let topY: Float
    let focusY: Float
    let ankleBoundaryY: Float
    let soleBoundaryY: Float
    let toeBoundaryZ: Float
    let toeTipZ: Float
    let heelBoundaryZ: Float
    let ankle: SIMD3<Float>
}

private struct AnatomyAssetSpecification {
    let fileName: String
    let structureID: String
    let color: UIColor
}

private struct SystemAssetSpecification {
    let fileName: String
    let semanticName: String
    let material: PhysicallyBasedMaterial
}

private enum AnatomyHandDetailSystem: String {
    case surface = "surface"
    case muscles = "muscles"
    case tendons = "tendons"
    case skeleton = "skeleton"
    case joints = "joints"
    case nerveSheaths = "nerveSheaths"
    case nerves = "nerves"

    var assetPrefix: String {
        switch self {
        case .surface: "HandSurface"
        case .muscles: "HandMuscularSystem"
        case .tendons: "HandTendonSystem"
        case .skeleton: "HandSkeletonSystem"
        case .joints: "HandJointSystem"
        case .nerveSheaths: "HandNerveSheathSystem"
        case .nerves: "HandNervousSystem"
        }
    }
}

private enum AnatomyFootDetailSystem: String {
    case surface
    case muscles
    case tendons
    case skeleton
    case joints
    case nerveSheaths
    case nerves

    var assetPrefix: String {
        switch self {
        case .surface: "FootSurface"
        case .muscles: "FootMuscularSystem"
        case .tendons: "FootTendonSystem"
        case .skeleton: "FootSkeletonSystem"
        case .joints: "FootJointSystem"
        case .nerveSheaths: "FootNerveSheathSystem"
        case .nerves: "FootNervousSystem"
        }
    }
}

private enum AnatomyAssetCatalog {
    static func skinFileNames(
        for variant: BodyModelVariant
    ) -> (surface: String, ghost: String) {
        let suffix = sexSuffix(for: variant)
        return ("BodySkin\(suffix)Medium", "BodySkin\(suffix)Low")
    }

    static func muscleSystemSpecifications(
        for variant: BodyModelVariant
    ) -> [SystemAssetSpecification] {
        let suffix = sexSuffix(for: variant)
        return [
            SystemAssetSpecification(
                fileName: "MuscularSystem\(suffix)FullBodyLOD",
                semanticName: "system:muscles",
                material: AnatomyMaterial.muscle
            ),
            SystemAssetSpecification(
                fileName: "HandMuscularSystem\(suffix)FullBodyLOD",
                semanticName: "system:hand-muscles-lod",
                material: AnatomyMaterial.muscle
            ),
            SystemAssetSpecification(
                fileName: "HandTendonSystem\(suffix)FullBodyLOD",
                semanticName: "system:hand-tendons-lod",
                material: AnatomyMaterial.fullBodyTendon
            )
        ]
    }

    static func skeletonSystemSpecification(
        for variant: BodyModelVariant
    ) -> SystemAssetSpecification {
        SystemAssetSpecification(
            fileName: "SkeletonSystem\(sexSuffix(for: variant))FullBodyLOD",
            semanticName: "system:skeleton",
            material: AnatomyMaterial.bone
        )
    }

    static func jointSystemSpecification(
        for variant: BodyModelVariant
    ) -> SystemAssetSpecification {
        SystemAssetSpecification(
            fileName: "JointSystem\(sexSuffix(for: variant))FullBodyLOD",
            semanticName: "system:joints",
            material: AnatomyMaterial.joint
        )
    }

    static func handSkeletonSystemSpecification(
        for variant: BodyModelVariant
    ) -> SystemAssetSpecification {
        SystemAssetSpecification(
            fileName: "HandSkeletonSystem\(sexSuffix(for: variant))FullBodyLOD",
            semanticName: "system:hand-skeleton-lod",
            material: AnatomyMaterial.bone
        )
    }

    static func handJointSystemSpecification(
        for variant: BodyModelVariant
    ) -> SystemAssetSpecification {
        SystemAssetSpecification(
            fileName: "HandJointSystem\(sexSuffix(for: variant))FullBodyLOD",
            semanticName: "system:hand-joints-lod",
            material: AnatomyMaterial.handJoint
        )
    }

    static func nervousSystemFileName(for variant: BodyModelVariant) -> String {
        "NervousSystem\(sexSuffix(for: variant))FullBodyLOD"
    }

    static func handNervousSystemFileName(for variant: BodyModelVariant) -> String {
        "HandNervousSystem\(sexSuffix(for: variant))FullBodyLOD"
    }

    static func handNerveSheathSystemFileName(for variant: BodyModelVariant) -> String {
        "HandNerveSheathSystem\(sexSuffix(for: variant))FullBodyLOD"
    }

    static func handDetailFileName(
        system: AnatomyHandDetailSystem,
        variant: BodyModelVariant
    ) -> String {
        "\(system.assetPrefix)\(sexSuffix(for: variant))"
    }

    static func footDetailFileName(
        system: AnatomyFootDetailSystem,
        variant: BodyModelVariant,
        focus: BodyFootDetailFocus,
        soleView: Bool = false,
        internalLayer: Bool = false
    ) -> String {
        let side = focus == .left ? "Left" : "Right"
        let prefix: String
        if soleView {
            prefix = switch system {
            case .surface: internalLayer
                ? "FootInternalSoleSurface"
                : "FootSoleSurface"
            case .muscles: "FootSoleMuscularSystem"
            case .tendons: "FootSoleTendonSystem"
            case .skeleton: "FootSoleSkeletonSystem"
            case .joints: "FootSoleJointSystem"
            case .nerveSheaths: "FootSoleNerveSheathSystem"
            case .nerves: "FootSoleNervousSystem"
            }
        } else {
            prefix = system.assetPrefix
        }
        return "\(prefix)\(sexSuffix(for: variant))\(side)"
    }

    static func vascularSystemFileName(
        kind: AnatomyVascularKind,
        variant: BodyModelVariant
    ) -> String {
        let system = kind == .arterial ? "Arterial" : "Venous"
        return "Vascular\(system)\(sexSuffix(for: variant))FullBodyLOD"
    }

    private static func sexSuffix(for variant: BodyModelVariant) -> String {
        variant == .female ? "Female" : "Male"
    }

    static func organSpecifications(for variant: BodyModelVariant) -> [AnatomyAssetSpecification] {
        let suffix = variant == .female ? "Female" : "Male"
        var values = [
            organ("OrganBrain\(suffix)", "organ.brain", .brain),
            organ("OrganLungLeft\(suffix)", "organ.lung.left", .lung),
            organ("OrganLungRight\(suffix)", "organ.lung.right", .lung),
            organ("OrganHeart\(suffix)", "organ.heart", .heart),
            organ("OrganLiver\(suffix)", "organ.liver", .liver),
            organ("OrganKidneyLeft\(suffix)", "organ.kidney.left", .kidney),
            organ("OrganKidneyRight\(suffix)", "organ.kidney.right", .kidney),
            organ("OrganSmallIntestine\(suffix)", "organ.intestines", .intestine),
            organ("OrganLargeIntestine\(suffix)", "organ.intestines", .intestine),
            organ("OrganBladder\(suffix)", "organ.bladder", .bladder)
        ]
        if variant == .female {
            values += [
                organ("OrganUterusFemale", "organ.uterus", .uterus),
                organ("OrganOvaryLeftFemale", "organ.ovary.left", .ovary),
                organ("OrganOvaryRightFemale", "organ.ovary.right", .ovary)
            ]
        } else if variant == .male {
            values.append(organ("OrganProstateMale", "organ.prostate", .prostate))
        }
        return values
    }

    private static func muscle(_ fileName: String, _ structureID: String) -> AnatomyAssetSpecification {
        AnatomyAssetSpecification(
            fileName: fileName,
            structureID: structureID,
            color: UIColor(red: 0.91, green: 0.22, blue: 0.36, alpha: 1)
        )
    }

    private static func organ(
        _ fileName: String,
        _ structureID: String,
        _ palette: OrganPalette
    ) -> AnatomyAssetSpecification {
        AnatomyAssetSpecification(fileName: fileName, structureID: structureID, color: palette.color)
    }
}

private enum AnatomyNervePulseCatalog {
    static func paths(for variant: BodyModelVariant) -> [(String, [SIMD3<Float>])] {
        let leftPaths: [(String, [SIMD3<Float>])] = if variant == .female {
            [
                ("trigeminal", [
                    SIMD3(0.01407, 0.73975, 0.02727),
                    SIMD3(0.04006, 0.71152, 0.02772),
                    SIMD3(0.03949, 0.70283, 0.02966)
                ]),
                ("median", [
                    SIMD3(0.20047, 0.51394, -0.07342),
                    SIMD3(0.18714, 0.37912, -0.04980),
                    SIMD3(0.29194, 0.24233, -0.02842),
                    SIMD3(0.38843, 0.11073, -0.02458),
                    SIMD3(0.45073, -0.02866, -0.00041)
                ]),
                ("ulnar", [
                    SIMD3(0.21646, 0.52953, -0.08169),
                    SIMD3(0.23282, 0.40050, -0.07523),
                    SIMD3(0.26405, 0.26191, -0.04912),
                    SIMD3(0.37327, 0.12247, -0.03978),
                    SIMD3(0.43667, -0.01777, -0.01439)
                ]),
                ("lumbar", [
                    SIMD3(-0.00353, 0.24847, -0.09122),
                    SIMD3(0.03244, 0.11286, -0.10016),
                    SIMD3(0.09333, -0.09558, -0.15378)
                ]),
                ("femoral", [
                    SIMD3(0.08367, -0.09677, -0.01807),
                    SIMD3(0.14811, -0.27680, -0.01467),
                    SIMD3(0.15482, -0.51658, -0.10286),
                    SIMD3(0.11869, -0.72539, -0.02192)
                ]),
                ("sciatic", [
                    SIMD3(0.08763, -0.09926, -0.15094),
                    SIMD3(0.12743, -0.20064, -0.10625),
                    SIMD3(0.13025, -0.47496, -0.12074),
                    SIMD3(0.14739, -0.63247, -0.09978),
                    SIMD3(0.16391, -0.75695, -0.03081)
                ])
            ]
        } else {
            [
                ("trigeminal", [
                    SIMD3(0.01821, 0.77451, 0.09458),
                    SIMD3(0.04229, 0.76698, 0.08602),
                    SIMD3(0.04760, 0.73964, 0.08330)
                ]),
                ("median", [
                    SIMD3(0.16907, 0.57571, 0.04607),
                    SIMD3(0.20350, 0.39898, 0.02047),
                    SIMD3(0.31734, 0.26192, 0.01362),
                    SIMD3(0.42082, 0.12535, 0.00591),
                    SIMD3(0.49012, -0.04110, 0.04436)
                ]),
                ("ulnar", [
                    SIMD3(0.22210, 0.56734, -0.00783),
                    SIMD3(0.25776, 0.42704, -0.00815),
                    SIMD3(0.30149, 0.28380, -0.00262),
                    SIMD3(0.41206, 0.12899, -0.00384),
                    SIMD3(0.48293, -0.03264, 0.03544)
                ]),
                ("lumbar", [
                    SIMD3(0.00256, 0.26821, -0.02923),
                    SIMD3(0.03638, 0.12277, -0.02399),
                    SIMD3(0.10748, -0.12506, -0.07333)
                ]),
                ("femoral", [
                    SIMD3(0.09988, -0.12517, 0.06342),
                    SIMD3(0.10717, -0.35397, 0.05022),
                    SIMD3(0.15986, -0.64277, -0.04029),
                    SIMD3(0.19197, -0.84361, -0.02530)
                ]),
                ("sciatic", [
                    SIMD3(0.10424, -0.13278, -0.07082),
                    SIMD3(0.14464, -0.24951, -0.04203),
                    SIMD3(0.18272, -0.58523, -0.09773),
                    SIMD3(0.21524, -0.73871, -0.08436),
                    SIMD3(0.24488, -0.86679, -0.04276)
                ])
            ]
        }

        return leftPaths.flatMap { path in
            let (name, points) = path
            return [
                ("nerve.\(name).left", points),
                ("nerve.\(name).right", points.map { SIMD3(-$0.x, $0.y, $0.z) })
            ]
        }
    }
}

private enum OrganPalette {
    case brain, lung, heart, liver, kidney, intestine, bladder, uterus, ovary, prostate

    var color: UIColor {
        switch self {
        case .brain: UIColor(red: 0.95, green: 0.55, blue: 0.7, alpha: 1)
        case .lung: UIColor(red: 0.36, green: 0.72, blue: 0.9, alpha: 1)
        case .heart: UIColor(red: 0.91, green: 0.12, blue: 0.26, alpha: 1)
        case .liver: UIColor(red: 0.56, green: 0.16, blue: 0.24, alpha: 1)
        case .kidney: UIColor(red: 0.65, green: 0.18, blue: 0.31, alpha: 1)
        case .intestine: UIColor(red: 0.82, green: 0.46, blue: 0.58, alpha: 1)
        case .bladder: UIColor(red: 0.88, green: 0.68, blue: 0.33, alpha: 1)
        case .uterus: UIColor(red: 0.94, green: 0.35, blue: 0.5, alpha: 1)
        case .ovary: UIColor(red: 0.94, green: 0.69, blue: 0.36, alpha: 1)
        case .prostate: UIColor(red: 0.71, green: 0.44, blue: 0.82, alpha: 1)
        }
    }
}

private enum AnatomyMaterial {
    static func skin(selected: Bool) -> PhysicallyBasedMaterial {
        let color = selected
            ? UIColor(red: 1, green: 0.16, blue: 0.5, alpha: 1)
            : UIColor(red: 0.31, green: 0.64, blue: 0.69, alpha: 1)
        var material = premiumMaterial(
            color: color,
            roughness: selected ? 0.42 : 0.56,
            metallic: 0,
            clearcoat: selected ? 0.28 : 0.12,
            sheen: selected
                ? UIColor(red: 1, green: 0.66, blue: 0.82, alpha: 1)
                : UIColor(red: 0.72, green: 0.95, blue: 0.93, alpha: 1)
        )
        material.specular = .init(floatLiteral: selected ? 0.2 : 0.13)
        let glow = selected
            ? UIColor(red: 1, green: 0.04, blue: 0.42, alpha: 1)
            : UIColor(red: 0.015, green: 0.19, blue: 0.24, alpha: 1)
        material.emissiveColor = .init(color: glow)
        material.emissiveIntensity = selected ? 0.65 : 0.15
        return material
    }

    static func ghostSkin(opacity: CGFloat) -> PhysicallyBasedMaterial {
        var material = premiumMaterial(
            color: UIColor(red: 0.22, green: 0.62, blue: 0.9, alpha: 1),
            roughness: 0.18,
            metallic: 0.04,
            clearcoat: 0.78,
            sheen: UIColor(red: 0.36, green: 0.84, blue: 1, alpha: 1)
        )
        material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
        return material
    }

    static let bone: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.96, green: 0.93, blue: 0.79, alpha: 1),
            roughness: 0.4,
            metallic: 0,
            clearcoat: 0.26,
            sheen: UIColor(red: 1, green: 0.98, blue: 0.87, alpha: 1)
        )
        material.emissiveColor = .init(
            color: UIColor(red: 0.18, green: 0.16, blue: 0.1, alpha: 1)
        )
        material.emissiveIntensity = 0.08
        return material
    }()

    static let footBone: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.96, green: 0.94, blue: 0.84, alpha: 1),
            roughness: 0.5,
            metallic: 0,
            clearcoat: 0.16,
            sheen: UIColor(red: 1, green: 0.99, blue: 0.91, alpha: 1)
        )
        material.emissiveColor = .init(
            color: UIColor(red: 0.11, green: 0.1, blue: 0.065, alpha: 1)
        )
        material.emissiveIntensity = 0.045
        return material
    }()

    static let joint: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.18, green: 0.82, blue: 0.88, alpha: 1),
            roughness: 0.3,
            metallic: 0,
            clearcoat: 0.5,
            sheen: UIColor(red: 0.48, green: 1, blue: 0.96, alpha: 1)
        )
        material.emissiveColor = .init(
            color: UIColor(red: 0.015, green: 0.28, blue: 0.34, alpha: 1)
        )
        material.emissiveIntensity = 0.22
        return material
    }()

    static let handJoint: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.18, green: 0.86, blue: 0.9, alpha: 1),
            roughness: 0.27,
            metallic: 0,
            clearcoat: 0.56,
            sheen: UIColor(red: 0.54, green: 1, blue: 0.97, alpha: 1)
        )
        material.blending = .transparent(opacity: 0.38)
        material.emissiveColor = .init(
            color: UIColor(red: 0.012, green: 0.24, blue: 0.29, alpha: 1)
        )
        material.emissiveIntensity = 0.16
        return material
    }()

    static let footJoint: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.18, green: 0.8, blue: 0.86, alpha: 1),
            roughness: 0.4,
            metallic: 0,
            clearcoat: 0.3,
            sheen: UIColor(red: 0.48, green: 0.94, blue: 0.94, alpha: 1)
        )
        material.blending = .transparent(opacity: 0.23)
        material.emissiveColor = .init(
            color: UIColor(red: 0.01, green: 0.15, blue: 0.18, alpha: 1)
        )
        material.emissiveIntensity = 0.08
        return material
    }()

    static let muscle = premiumMaterial(
        color: UIColor(red: 0.91, green: 0.19, blue: 0.32, alpha: 1),
        roughness: 0.34,
        metallic: 0.01,
        clearcoat: 0.42,
        sheen: UIColor(red: 1, green: 0.42, blue: 0.5, alpha: 1)
    )

    static let tendon = premiumMaterial(
        color: UIColor(red: 0.94, green: 0.82, blue: 0.68, alpha: 1),
        roughness: 0.4,
        metallic: 0,
        clearcoat: 0.3,
        sheen: UIColor(red: 1, green: 0.91, blue: 0.78, alpha: 1)
    )

    static let fullBodyTendon = premiumMaterial(
        color: UIColor(red: 0.9, green: 0.48, blue: 0.4, alpha: 1),
        roughness: 0.62,
        metallic: 0,
        clearcoat: 0.08,
        sheen: UIColor(red: 1, green: 0.62, blue: 0.54, alpha: 1)
    )

    static let neuralCore: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.96, green: 0.77, blue: 0.34, alpha: 1),
            roughness: 0.43,
            metallic: 0,
            clearcoat: 0.32,
            sheen: UIColor(red: 1, green: 0.91, blue: 0.58, alpha: 1)
        )
        material.emissiveColor = .init(
            color: UIColor(red: 0.52, green: 0.27, blue: 0.025, alpha: 1)
        )
        material.emissiveIntensity = 0.34
        return material
    }()

    static let handNeuralCore: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 1, green: 0.79, blue: 0.29, alpha: 1),
            roughness: 0.3,
            metallic: 0,
            clearcoat: 0.54,
            sheen: UIColor(red: 1, green: 0.94, blue: 0.62, alpha: 1)
        )
        material.emissiveColor = .init(
            color: UIColor(red: 0.35, green: 0.16, blue: 0.01, alpha: 1)
        )
        material.emissiveIntensity = 0.2
        return material
    }()

    static let handNeuralSheath: PhysicallyBasedMaterial = {
        var material = premiumMaterial(
            color: UIColor(red: 0.96, green: 0.62, blue: 0.12, alpha: 1),
            roughness: 0.38,
            metallic: 0,
            clearcoat: 0.36,
            sheen: UIColor(red: 1, green: 0.82, blue: 0.35, alpha: 1)
        )
        material.blending = .transparent(opacity: 0.38)
        material.emissiveColor = .init(
            color: UIColor(red: 0.19, green: 0.08, blue: 0.005, alpha: 1)
        )
        material.emissiveIntensity = 0.1
        return material
    }()

    static var nervePulse: UnlitMaterial {
        UnlitMaterial(color: UIColor(red: 1, green: 0.97, blue: 0.7, alpha: 1))
    }

    static var nervePulseHalo: UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(red: 1, green: 0.72, blue: 0.12, alpha: 1))
        material.blending = .transparent(opacity: 0.2)
        return material
    }

    static func vascularCore(
        _ kind: AnatomyVascularKind,
        pressure: Float = 0
    ) -> PhysicallyBasedMaterial {
        let pressure = min(1, max(0, pressure))
        let color = kind == .arterial
            ? UIColor(
                red: 0.95 + CGFloat(pressure) * 0.05,
                green: 0.045 + CGFloat(pressure) * 0.035,
                blue: 0.15 + CGFloat(pressure) * 0.02,
                alpha: 1
            )
            : kind.color
        var material = premiumMaterial(
            color: color,
            roughness: 0.28,
            metallic: 0,
            clearcoat: 0.52,
            sheen: color
        )
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = kind == .arterial
            ? 0.28 + pressure * 0.26
            : 0.2
        return material
    }

    // Building a new PBR material forces RealityKit to resolve material assets
    // and shader parameters. Reuse the small set of quantized heartbeat frames
    // instead of rebuilding that pipeline throughout every beat.
    static let arterialPulseFrames: [PhysicallyBasedMaterial] = {
        let baseMaterial = vascularCore(.arterial)
        return (0...12).map { step in
            let pressure = Float(step) / 12
            let color = UIColor(
                red: 0.95 + CGFloat(pressure) * 0.05,
                green: 0.045 + CGFloat(pressure) * 0.035,
                blue: 0.15 + CGFloat(pressure) * 0.02,
                alpha: 1
            )
            var material = baseMaterial
            material.baseColor = .init(tint: color)
            material.sheen = .init(tint: color)
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = 0.28 + pressure * 0.26
            return material
        }
    }()

    static var atmosphereMote: UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(
            red: 0.5,
            green: 0.9,
            blue: 1,
            alpha: 1
        ))
        material.blending = .transparent(opacity: 0.48)
        return material
    }

    static var scanCore: UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(
            red: 0.68,
            green: 0.99,
            blue: 1,
            alpha: 1
        ))
        material.blending = .transparent(opacity: 0.88)
        return material
    }

    static var scanHalo: UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(
            red: 0.15,
            green: 0.84,
            blue: 1,
            alpha: 1
        ))
        material.blending = .transparent(opacity: 0.16)
        return material
    }

    static func scanEcho(index: Int) -> UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(
            red: 0.34,
            green: 0.91,
            blue: 1,
            alpha: 1
        ))
        material.blending = .transparent(opacity: index == 0 ? 0.24 : 0.1)
        return material
    }

    static let selectionCore = emissiveMaterial(
        color: UIColor(red: 1, green: 0.08, blue: 0.52, alpha: 1),
        intensity: 2.6,
        roughness: 0.1
    )

    static var selectionHalo: UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(
            red: 1,
            green: 0.16,
            blue: 0.58,
            alpha: 1
        ))
        material.blending = .transparent(opacity: 0.2)
        return material
    }

    static func material(
        for specification: AnatomyAssetSpecification,
        selected: Bool
    ) -> PhysicallyBasedMaterial {
        premiumMaterial(
            color: selected
                ? UIColor(red: 1, green: 0.12, blue: 0.48, alpha: 1)
                : specification.color,
            roughness: selected ? 0.14 : 0.31,
            metallic: selected ? 0.18 : 0.02,
            clearcoat: selected ? 0.92 : 0.48,
            sheen: selected
                ? UIColor(red: 1, green: 0.42, blue: 0.72, alpha: 1)
                : specification.color
        )
    }

    private static func premiumMaterial(
        color: UIColor,
        roughness: Float,
        metallic: Float,
        clearcoat: Float,
        sheen: UIColor
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.specular = .init(floatLiteral: 0.68)
        material.clearcoat = .init(floatLiteral: clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: 0.16)
        material.sheen = .init(tint: sheen)
        return material
    }

    private static func emissiveMaterial(
        color: UIColor,
        intensity: Float,
        roughness: Float
    ) -> PhysicallyBasedMaterial {
        var material = premiumMaterial(
            color: color,
            roughness: roughness,
            metallic: 0.12,
            clearcoat: 0.72,
            sheen: color
        )
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = intensity
        return material
    }
}

enum BodySurfaceMapper {
    static func structureID(at point: SIMD3<Float>, variant: BodyModelVariant) -> String? {
        let point = canonicalPoint(point / anatomySceneScale, variant: variant)
        let side = point.x >= 0 ? "left" : "right"
        let front = point.z > 0
        let x = abs(point.x)
        let y = point.y

        if x > 0.25, y > -0.18 {
            if x > 0.46 || y < 0.02 { return "body.hand.\(side)" }
            if x > 0.41 { return "body.wrist.\(side)" }
            if x > 0.32 { return "body.forearm.\(side)" }
            if x > 0.27, y > 0.22 { return "body.elbow.\(side)" }
            if y > 0.49 { return "body.shoulder.\(side)" }
            return "body.upperArm.\(side)"
        }
        if y > 0.68 { return front ? "body.face" : "body.head" }
        if y > 0.59 { return "body.neck" }
        if y > 0.32 { return front ? "body.chest" : "body.upperBack" }
        if y > 0.04 { return front ? "body.abdomen" : "body.lowerBack" }
        if y > -0.12 {
            if x > 0.11 { return front ? "body.hip.\(side)" : "body.buttock.\(side)" }
            return "body.pelvis"
        }
        if y > -0.43 { return front ? "body.thigh.\(side)" : "body.posteriorThigh.\(side)" }
        if y > -0.53 { return "body.knee.\(side)" }
        if y > -0.79 { return front ? "body.lowerLeg.\(side)" : "body.calf.\(side)" }
        if y > -0.87 { return "body.ankle.\(side)" }
        return "body.foot.\(side)"
    }

    static func jointID(at point: SIMD3<Float>, variant: BodyModelVariant) -> String? {
        let point = point / anatomySceneScale
        let side = point.x >= 0 ? "left" : "right"
        let landmarks = jointLandmarks(for: variant, side: side)
        return landmarks.min { lhs, rhs in
            jointDistance(from: point, to: lhs.position)
                < jointDistance(from: point, to: rhs.position)
        }?.id
    }

    private static func jointLandmarks(
        for variant: BodyModelVariant,
        side: String
    ) -> [(id: String, position: SIMD3<Float>)] {
        let isLeft = side == "left"
        if variant == .female {
            return [
                ("joint.cervicalSpine", SIMD3(0, 0.619399, -0.073056)),
                ("joint.shoulder.\(side)", isLeft
                    ? SIMD3(0.179571, 0.555438, -0.093060)
                    : SIMD3(-0.183758, 0.553980, -0.092698)),
                ("joint.elbow.\(side)", isLeft
                    ? SIMD3(0.258655, 0.272200, -0.073242)
                    : SIMD3(-0.270386, 0.272200, -0.073066)),
                ("joint.wrist.\(side)", isLeft
                    ? SIMD3(0.403088, 0.000933, -0.022779)
                    : SIMD3(-0.412916, 0.001213, -0.023516)),
                ("joint.ribCage", SIMD3(0, 0.405271, 0.028564)),
                ("joint.lumbarSpine", SIMD3(0, 0.235638, -0.100161)),
                ("joint.sacroiliac.\(side)", isLeft
                    ? SIMD3(0.079394, -0.079748, -0.090582)
                    : SIMD3(-0.072632, -0.081043, -0.092335)),
                ("joint.hip.\(side)", isLeft
                    ? SIMD3(0.137619, -0.046887, -0.083725)
                    : SIMD3(-0.144295, -0.046583, -0.083695)),
                ("joint.knee.\(side)", isLeft
                    ? SIMD3(0.105798, -0.463827, -0.095274)
                    : SIMD3(-0.124583, -0.463974, -0.088036)),
                ("joint.ankle.\(side)", isLeft
                    ? SIMD3(0.143649, -0.774522, -0.020298)
                    : SIMD3(-0.162165, -0.776210, -0.011443))
            ]
        }

        return [
            ("joint.cervicalSpine", SIMD3(0, 0.578286, -0.063137)),
            ("joint.shoulder.\(side)", isLeft
                ? SIMD3(0.185177, 0.599301, -0.018616)
                : SIMD3(-0.186491, 0.598207, -0.016049)),
            ("joint.elbow.\(side)", isLeft
                ? SIMD3(0.285847, 0.292300, -0.025975)
                : SIMD3(-0.286185, 0.292300, -0.025833)),
            ("joint.wrist.\(side)", isLeft
                ? SIMD3(0.446993, -0.007955, 0.024395)
                : SIMD3(-0.446791, -0.008029, 0.024357)),
            ("joint.ribCage", SIMD3(0, 0.392301, 0.102309)),
            ("joint.lumbarSpine", SIMD3(0, 0.272030, -0.046266)),
            ("joint.sacroiliac.\(side)", isLeft
                ? SIMD3(0.070272, -0.088014, -0.030179)
                : SIMD3(-0.069506, -0.088854, -0.027496)),
            ("joint.hip.\(side)", isLeft
                ? SIMD3(0.149709, -0.062284, -0.007297)
                : SIMD3(-0.149586, -0.062373, -0.005856)),
            ("joint.knee.\(side)", isLeft
                ? SIMD3(0.136038, -0.562694, -0.077240)
                : SIMD3(-0.135456, -0.562811, -0.076872)),
            ("joint.ankle.\(side)", isLeft
                ? SIMD3(0.209669, -0.883374, -0.039116)
                : SIMD3(-0.210147, -0.883491, -0.038887))
        ]
    }

    private static func jointDistance(
        from point: SIMD3<Float>,
        to landmark: SIMD3<Float>
    ) -> Float {
        let delta = point - landmark
        return delta.x * delta.x + delta.y * delta.y + delta.z * delta.z * 0.28
    }

    static func muscleID(at point: SIMD3<Float>, variant: BodyModelVariant) -> String? {
        let point = canonicalPoint(point / anatomySceneScale, variant: variant)
        let side = point.x >= 0 ? "left" : "right"
        let front = point.z > 0
        let x = abs(point.x)
        let y = point.y

        if x > 0.23, y > -0.16 {
            if y > 0.46 { return "muscle.deltoid.\(side)" }
            if y > 0.20 {
                return front ? "muscle.biceps.\(side)" : "muscle.triceps.\(side)"
            }
            return "muscle.forearm.\(side)"
        }
        if y > 0.54 { return "muscle.trapezius" }
        if y > 0.32 { return front ? "muscle.pectorals" : "muscle.trapezius" }
        if y > 0.03 { return front ? "muscle.abdominals" : "muscle.lowerBack" }
        if y > -0.18 { return "muscle.gluteal.\(side)" }
        if y > -0.52 {
            return front ? "muscle.quadriceps.\(side)" : "muscle.hamstrings.\(side)"
        }
        return "muscle.calf.\(side)"
    }

    static func nerveID(at point: SIMD3<Float>, variant: BodyModelVariant) -> String? {
        let point = canonicalPoint(point / anatomySceneScale, variant: variant)
        let side = point.x >= 0 ? "left" : "right"
        let x = abs(point.x)
        let y = point.y
        if y > 0.67 { return "nerve.trigeminal.\(side)" }
        if x > 0.25 { return point.z < 0 ? "nerve.ulnar.\(side)" : "nerve.median.\(side)" }
        if y > -0.06 { return "nerve.lumbar.\(side)" }
        if point.z < -0.035 { return "nerve.sciatic.\(side)" }
        return "nerve.femoral.\(side)"
    }

    private static func canonicalPoint(
        _ point: SIMD3<Float>,
        variant: BodyModelVariant
    ) -> SIMD3<Float> {
        guard variant != .female else { return point }
        return SIMD3(
            point.x * 0.935,
            point.y * 0.911 + 0.039,
            point.z
        )
    }

    static func markerPosition(
        for structureID: String,
        variant: BodyModelVariant
    ) -> SIMD3<Float> {
        let footFocus: BodyFootDetailFocus = structureID.hasSuffix(".right") ? .right : .left
        if let footMarker = FootDetailStructureMapper.markerPosition(
            for: structureID,
            focus: footFocus,
            variant: variant
        ) {
            return footMarker
        }
        if structureID.hasPrefix("joint.") {
            let side = structureID.hasSuffix(".right") ? "right" : "left"
            if let landmark = jointLandmarks(for: variant, side: side).first(
                where: { $0.id == structureID }
            ) {
                return landmark.position * anatomySceneScale
            }
        }

        let canonical = defaultPosition(for: structureID, variant: variant)
        let rendered: SIMD3<Float>
        if variant == .female {
            rendered = canonical
        } else {
            rendered = SIMD3(
                canonical.x / 0.935,
                (canonical.y - 0.039) / 0.911,
                canonical.z
            )
        }
        return rendered * anatomySceneScale
    }

    static func defaultPosition(for structureID: String, variant: BodyModelVariant) -> SIMD3<Float> {
        let side: Float = structureID.hasSuffix(".left") ? 1 : structureID.hasSuffix(".right") ? -1 : 0
        let front: Float = 0.16
        if structureID == "joint.cervicalSpine" { return SIMD3(0, 0.625, -0.035) }
        if structureID == "joint.ribCage" { return SIMD3(0, 0.405, 0.015) }
        if structureID == "joint.lumbarSpine" { return SIMD3(0, 0.13, -0.055) }
        if structureID.hasPrefix("joint.shoulder.") {
            return SIMD3(side * 0.205, 0.505, 0)
        }
        if structureID.hasPrefix("joint.elbow.") {
            return SIMD3(side * 0.34, 0.25, 0)
        }
        if structureID.hasPrefix("joint.wrist.") {
            return SIMD3(side * 0.49, 0.02, 0.015)
        }
        if structureID.hasPrefix("joint.sacroiliac.") {
            return SIMD3(side * 0.07, -0.055, -0.045)
        }
        if structureID.hasPrefix("joint.hip.") {
            return SIMD3(side * 0.12, -0.145, 0)
        }
        if structureID.hasPrefix("joint.knee.") {
            return SIMD3(side * 0.12, -0.50, 0.01)
        }
        if structureID.hasPrefix("joint.ankle.") {
            return SIMD3(side * 0.10, -0.84, 0.015)
        }
        if structureID.contains("head") || structureID.contains("face") || structureID.contains("brain") || structureID.contains("trigeminal") {
            return SIMD3(side * 0.055, 0.79, front)
        }
        if structureID.contains("neck") || structureID.contains("cervical") {
            return SIMD3(side * 0.045, 0.625, -0.035)
        }
        if structureID.contains("shoulder") || structureID.contains("deltoid") {
            return SIMD3(side * 0.205, 0.505, 0.015)
        }
        if structureID.contains("upperArm") || structureID.contains("biceps") || structureID.contains("triceps") {
            return SIMD3(side * 0.275, 0.38, structureID.contains("triceps") ? -0.07 : 0.05)
        }
        if structureID.contains("elbow") { return SIMD3(side * 0.34, 0.25, 0.015) }
        if structureID.contains("forearm") || structureID.contains("median") || structureID.contains("ulnar") {
            return SIMD3(side * 0.415, 0.135, structureID.contains("ulnar") ? -0.04 : 0.04)
        }
        if structureID.contains("wrist") || structureID.contains("hand") {
            return structureID.contains("wrist")
                ? SIMD3(side * 0.49, 0.02, 0.025)
                : SIMD3(side * 0.52, -0.055, front * 0.4)
        }
        if structureID.contains("chest") || structureID.contains("pector") || structureID.contains("heart") || structureID.contains("lung") || structureID.contains("ribCage") {
            return SIMD3(side * 0.08, 0.46, front * 0.72)
        }
        if structureID.contains("upperBack") || structureID.contains("trapezius") {
            return SIMD3(side * 0.08, 0.49, -front * 0.65)
        }
        if structureID.contains("abdomen") || structureID.contains("liver") || structureID.contains("kidney") || structureID.contains("intestine") || structureID.contains("stomach") {
            return SIMD3(side * 0.09, 0.18, front * 0.55)
        }
        if structureID.contains("lowerBack") || structureID.contains("lumbar") {
            return SIMD3(side * 0.07, 0.15, -front * 0.62)
        }
        if structureID.contains("pelvis") || structureID.contains("bladder") || structureID.contains("uterus") || structureID.contains("ovary") || structureID.contains("prostate") || structureID.contains("sacroiliac") {
            return SIMD3(side * 0.09, -0.05, 0)
        }
        if structureID.contains("hip") || structureID.contains("gluteal") || structureID.contains("buttock") {
            return SIMD3(side * 0.14, -0.13, structureID.contains("gluteal") || structureID.contains("buttock") ? -0.1 : 0)
        }
        if structureID.contains("thigh") || structureID.contains("quadriceps") || structureID.contains("hamstrings") || structureID.contains("sciatic") || structureID.contains("femoral") {
            return SIMD3(side * 0.13, -0.34, structureID.contains("hamstrings") || structureID.contains("sciatic") ? -0.08 : 0.06)
        }
        if structureID.contains("knee") { return SIMD3(side * 0.12, -0.5, 0.04) }
        if structureID.contains("lowerLeg") || structureID.contains("calf") {
            return SIMD3(side * 0.11, -0.68, structureID.contains("calf") ? -0.06 : 0.04)
        }
        if structureID.contains("ankle") { return SIMD3(side * 0.1, -0.84, 0) }
        if structureID.contains("foot") { return SIMD3(side * 0.1, -0.9, front * 0.45) }
        return SIMD3(0, 0.2, front)
    }
}
