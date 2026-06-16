import SwiftUI

struct NightLightFullScreenView: View {
    @ObservedObject var viewModel: NightLightViewModel
    @State private var gestureScale = 1.0
    @State private var gestureOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        lightSurface(size: proxy.size, time: time)
                        NightLightAmbientEffect(
                            mode: viewModel.settings.glowMode,
                            color: viewModel.settings.resolvedColor,
                            intensity: viewModel.effectiveBrightness,
                            time: time
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(canvasTapGesture)
                }

                controls
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.revealControls()
        }
        .onDisappear {
            if viewModel.isActive {
                viewModel.stop()
            }
        }
        .onChange(of: viewModel.isActive) { _, active in
            if !active { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.stop()
            }
        }
    }

    private func lightSurface(size: CGSize, time: TimeInterval) -> some View {
        let color = viewModel.settings.resolvedColor
        let breathing = breathingValues(at: time)
        let intensity = viewModel.effectiveBrightness * breathing.brightness

        return ZStack {
            RadialGradient(
                colors: [
                    color.opacity(min(1, intensity * 1.72)),
                    color.opacity(min(1, intensity * 0.9)),
                    color.opacity(min(1, intensity * 0.26)),
                    .black
                ],
                center: .center,
                startRadius: 8,
                endRadius: max(size.width, size.height)
                    * CGFloat(0.66 + breathing.progress * 0.07)
            )
            .ignoresSafeArea()

            if viewModel.settings.glowMode.displaysSelectedShape,
               viewModel.settings.selectedShape != .fullScreenGlow {
                NightLightShapeView(
                    shape: viewModel.settings.selectedShape,
                    color: color.opacity(min(1, 0.58 + intensity)),
                    softness: viewModel.settings.softness
                )
                .frame(
                    width: min(size.width, size.height) * 0.52,
                    height: min(size.width, size.height) * 0.52
                )
                .scaleEffect(
                    viewModel.settings.shapeScale
                        * gestureScale
                        * breathing.scale
                )
                .offset(
                    x: viewModel.settings.shapeOffsetX + gestureOffset.width,
                    y: viewModel.settings.shapeOffsetY + gestureOffset.height
                )
                .gesture(shapeGestures)
            }
        }
        .opacity(viewModel.lightEnabled ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: viewModel.lightEnabled)
    }

    private var controls: some View {
        VStack {
            HStack {
                if viewModel.timerService.isRunning {
                    Label(
                        viewModel.timerService.remainingText,
                        systemImage: "timer"
                    )
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.35), in: Capsule())
                }
                Spacer()
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.38), in: Circle())
                }
                .accessibilityLabel("Stop Night Light")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer()

            NightLightControlsView(viewModel: viewModel, compact: true)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.28))
                        .frame(width: 34, height: 4)
                        .padding(.top, 8)
                }
                .padding(16)
        }
        .opacity(viewModel.controlsVisible ? 1 : 0)
        .allowsHitTesting(viewModel.controlsVisible)
        .animation(.easeOut(duration: 0.3), value: viewModel.controlsVisible)
    }

    private var canvasTapGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2)
                .onEnded {
                    gestureScale = 1
                    gestureOffset = .zero
                    viewModel.resetShapeTransform()
                },
            TapGesture()
                .onEnded {
                    viewModel.toggleControls()
                }
        )
    }

    private var shapeGestures: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { gestureScale = $0 }
                .onEnded { value in
                    viewModel.settings.shapeScale = min(
                        2.6,
                        max(0.45, viewModel.settings.shapeScale * value)
                    )
                    gestureScale = 1
                    viewModel.settingsDidChange()
                },
            DragGesture()
                .onChanged { gestureOffset = $0.translation }
                .onEnded { value in
                    viewModel.settings.shapeOffsetX += value.translation.width
                    viewModel.settings.shapeOffsetY += value.translation.height
                    gestureOffset = .zero
                    viewModel.settingsDidChange()
                }
        )
    }

    private func breathingValues(
        at time: TimeInterval
    ) -> (scale: Double, brightness: Double, progress: Double) {
        guard viewModel.settings.breathingAnimationEnabled else {
            return (1, 1, 0.5)
        }

        let angle = (time / viewModel.settings.breathingSpeed.duration) * 2 * Double.pi
        let wave = sin(angle)
        let progress = (wave + 1) / 2
        return (
            1 + wave * Double(viewModel.settings.breathingIntensity.scaleRange),
            1 + wave * viewModel.settings.breathingIntensity.brightnessRange,
            progress
        )
    }
}

struct NightLightAmbientEffect: View {
    let mode: NightLightGlowMode
    let color: Color
    let intensity: Double
    let time: TimeInterval

    var body: some View {
        ZStack {
            switch mode {
            case .steady:
                EmptyView()
            case .fireplace:
                fireplaceScene
            case .candle:
                candleScene
            case .shimmer:
                shimmerScene
            case .rainyWindow:
                rainyWindowScene
            case .starryNight:
                starryNightScene
            }
        }
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var sceneStrength: Double {
        min(1, max(0.28, 0.34 + intensity * 1.4))
    }

    private var fireplaceScene: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 1, green: 0.38, blue: 0.06)
                        .opacity(0.19 * sceneStrength),
                    Color(red: 0.58, green: 0.07, blue: 0.015)
                        .opacity(0.09 * sceneStrength),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.92),
                startRadius: 8,
                endRadius: 430
            )
            .blendMode(.screen)

            Canvas { context, size in
                let baseY = size.height * 0.93

                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 26))
                    for index in 0..<7 {
                        let seed = Double(index) + 30
                        let width = size.width * CGFloat(0.16 + hash(seed) * 0.18)
                        let height = size.height * CGFloat(0.08 + hash(seed + 1) * 0.12)
                        let x = size.width * CGFloat(0.14 + hash(seed + 2) * 0.72)
                        let pulse = 0.76 + naturalWave(seed: seed, speed: 3.1) * 0.24
                        glow.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: x - width / 2,
                                    y: baseY - height,
                                    width: width,
                                    height: height
                                )
                            ),
                            with: .color(
                                Color.orange.opacity(
                                    0.13 * pulse * sceneStrength
                                )
                            )
                        )
                    }
                }

                drawFireLogs(in: &context, size: size, baseY: baseY)

                for index in 0..<11 {
                    let seed = Double(index) + 1
                    let lane = (Double(index) + 0.5) / 11
                    let x = size.width * CGFloat(
                        0.13 + lane * 0.74
                            + (hash(seed * 8.7) - 0.5) * 0.055
                    )
                    let width = size.width * CGFloat(0.055 + hash(seed + 2) * 0.065)
                    let height = size.height * CGFloat(0.10 + hash(seed + 4) * 0.14)
                    let sway = CGFloat(
                        (naturalWave(seed: seed, speed: 2.8) - 0.5)
                            * Double(width) * 0.65
                    )
                    let pulse = 0.82 + naturalWave(seed: seed + 7, speed: 4.6) * 0.28

                    let outer = flamePath(
                        centerX: x,
                        baseY: baseY,
                        width: width,
                        height: height * CGFloat(pulse),
                        sway: sway
                    )
                    context.fill(
                        outer,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(
                                    color: Color.yellow.opacity(0.5 * sceneStrength),
                                    location: 0
                                ),
                                .init(
                                    color: Color.orange.opacity(0.78 * sceneStrength),
                                    location: 0.48
                                ),
                                .init(
                                    color: Color.red.opacity(0.22 * sceneStrength),
                                    location: 1
                                )
                            ]),
                            startPoint: CGPoint(x: x, y: baseY - height),
                            endPoint: CGPoint(x: x, y: baseY)
                        )
                    )

                    let inner = flamePath(
                        centerX: x - sway * 0.08,
                        baseY: baseY,
                        width: width * 0.48,
                        height: height * CGFloat(pulse) * 0.68,
                        sway: sway * 0.48
                    )
                    context.fill(
                        inner,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.white.opacity(0.68 * sceneStrength),
                                Color.yellow.opacity(0.74 * sceneStrength),
                                Color.orange.opacity(0.1)
                            ]),
                            startPoint: CGPoint(x: x, y: baseY - height * 0.7),
                            endPoint: CGPoint(x: x, y: baseY)
                        )
                    )
                }

                drawEmbers(in: &context, size: size, baseY: baseY)
            }
        }
        .ignoresSafeArea()
    }

    private var candleScene: some View {
        Canvas { context, size in
            let centerX = size.width * 0.5
            let candleTop = size.height * 0.78
            let flicker = naturalWave(seed: 71, speed: 4.1)
            let sway = CGFloat(sin(time * 2.35) * 4 + sin(time * 7.7) * 1.6)
            let flameHeight = min(
                size.height * CGFloat(0.075 + flicker * 0.012),
                92
            )
            let flameCenterY = candleTop - flameHeight * 0.55

            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 52))
                glow.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: centerX - size.width * 0.30,
                            y: flameCenterY - size.width * 0.30,
                            width: size.width * 0.60,
                            height: size.width * 0.60
                        )
                    ),
                    with: .color(
                        Color(red: 1, green: 0.43, blue: 0.08)
                            .opacity((0.10 + flicker * 0.045) * sceneStrength)
                    )
                )
            }

            let candleWidth = min(size.width * 0.28, 128)
            let candleHeight = size.height - candleTop + 36
            let bodyRect = CGRect(
                x: centerX - candleWidth / 2,
                y: candleTop,
                width: candleWidth,
                height: candleHeight
            )
            context.fill(
                Path(roundedRect: bodyRect, cornerRadius: candleWidth * 0.08),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(
                            color: Color(red: 0.42, green: 0.18, blue: 0.08)
                                .opacity(0.74 * sceneStrength),
                            location: 0
                        ),
                        .init(
                            color: Color(red: 0.96, green: 0.66, blue: 0.34)
                                .opacity(0.82 * sceneStrength),
                            location: 0.34
                        ),
                        .init(
                            color: Color(red: 0.62, green: 0.28, blue: 0.12)
                                .opacity(0.72 * sceneStrength),
                            location: 0.72
                        ),
                        .init(
                            color: Color(red: 0.24, green: 0.08, blue: 0.035)
                                .opacity(0.8 * sceneStrength),
                            location: 1
                        )
                    ]),
                    startPoint: CGPoint(x: bodyRect.minX, y: bodyRect.midY),
                    endPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.midY)
                )
            )

            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: bodyRect.minX,
                        y: bodyRect.minY - candleWidth * 0.11,
                        width: candleWidth,
                        height: candleWidth * 0.22
                    )
                ),
                with: .color(
                    Color(red: 1, green: 0.82, blue: 0.55)
                        .opacity(0.62 * sceneStrength)
                )
            )

            let waxPool = CGRect(
                x: centerX - candleWidth * 0.34,
                y: candleTop - candleWidth * 0.055,
                width: candleWidth * 0.68,
                height: candleWidth * 0.11
            )
            context.fill(
                Path(ellipseIn: waxPool),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.20, green: 0.07, blue: 0.025)
                            .opacity(0.66),
                        Color.orange.opacity(0.20 * sceneStrength),
                        .clear
                    ]),
                    center: CGPoint(x: waxPool.midX, y: waxPool.midY),
                    startRadius: 0,
                    endRadius: waxPool.width * 0.55
                )
            )

            for index in 0..<3 {
                let offset = CGFloat(index - 1) * candleWidth * 0.28
                let dripHeight = candleWidth * CGFloat(0.13 + Double(index) * 0.045)
                let dripRect = CGRect(
                    x: centerX + offset - candleWidth * 0.045,
                    y: candleTop - 2,
                    width: candleWidth * 0.09,
                    height: dripHeight
                )
                context.fill(
                    Path(roundedRect: dripRect, cornerRadius: dripRect.width / 2),
                    with: .color(
                        Color(red: 0.95, green: 0.62, blue: 0.31)
                            .opacity(0.42 * sceneStrength)
                    )
                )
            }

            var wick = Path()
            wick.move(to: CGPoint(x: centerX, y: candleTop + 1))
            wick.addQuadCurve(
                to: CGPoint(x: centerX + sway * 0.13, y: candleTop - 14),
                control: CGPoint(x: centerX - 2, y: candleTop - 7)
            )
            context.stroke(
                wick,
                with: .color(.black.opacity(0.62)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )

            let outer = flamePath(
                centerX: centerX,
                baseY: candleTop - 13,
                width: candleWidth * 0.28,
                height: flameHeight,
                sway: sway
            )
            context.drawLayer { bloom in
                bloom.addFilter(.blur(radius: 8))
                bloom.fill(
                    outer,
                    with: .color(
                        Color.orange.opacity(0.52 * sceneStrength)
                    )
                )
            }
            context.fill(
                outer,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.96), location: 0),
                        .init(color: .yellow.opacity(0.94), location: 0.40),
                        .init(color: .orange.opacity(0.80), location: 0.82),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: CGPoint(
                        x: centerX + sway,
                        y: candleTop - flameHeight
                    ),
                    endPoint: CGPoint(x: centerX, y: candleTop - 8)
                )
            )

            let blueBase = flamePath(
                centerX: centerX,
                baseY: candleTop - 11,
                width: candleWidth * 0.13,
                height: 25,
                sway: sway * 0.12
            )
            context.fill(
                blueBase,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.62 * sceneStrength),
                        Color.cyan.opacity(0.42 * sceneStrength),
                        Color.blue.opacity(0.08)
                    ]),
                    startPoint: CGPoint(x: centerX, y: candleTop - 35),
                    endPoint: CGPoint(x: centerX, y: candleTop - 9)
                )
            )
        }
        .ignoresSafeArea()
    }

    private var shimmerScene: some View {
        Canvas { context, size in
            context.blendMode = .screen

            context.drawLayer { haze in
                haze.addFilter(.blur(radius: 24))
                for index in 0..<6 {
                    let seed = Double(index) + 90
                    let phase = time * (0.08 + hash(seed) * 0.05) + seed
                    var ribbon = Path()
                    let startY = size.height * CGFloat(0.14 + hash(seed + 1) * 0.72)
                    ribbon.move(to: CGPoint(x: -size.width * 0.15, y: startY))
                    for step in 1...6 {
                        let progress = CGFloat(step) / 6
                        let x = size.width * (progress * 1.3 - 0.15)
                        let wave = sin(phase + Double(step) * 0.85)
                        let y = startY + CGFloat(wave) * size.height * 0.09
                        ribbon.addLine(to: CGPoint(x: x, y: y))
                    }
                    haze.stroke(
                        ribbon,
                        with: .color(
                            color.opacity(
                                (0.045 + hash(seed + 2) * 0.045)
                                    * sceneStrength
                            )
                        ),
                        style: StrokeStyle(
                            lineWidth: 24 + CGFloat(hash(seed + 3) * 34),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }

            for index in 0..<16 {
                let seed = Double(index) + 120
                let orbit = time * (0.12 + hash(seed) * 0.12) + seed
                let x = size.width * CGFloat(
                    0.5 + cos(orbit) * (0.18 + hash(seed + 1) * 0.42)
                )
                let y = size.height * CGFloat(
                    0.5 + sin(orbit * 0.73) * (0.16 + hash(seed + 2) * 0.38)
                )
                let pulse = naturalWave(seed: seed, speed: 1.2)
                let radius = CGFloat(1.2 + pulse * 2.5)
                drawGlint(
                    in: &context,
                    at: CGPoint(x: x, y: y),
                    radius: radius,
                    opacity: (0.08 + pulse * 0.22) * sceneStrength
                )
            }
        }
        .blendMode(.screen)
        .ignoresSafeArea()
    }

    private var rainyWindowScene: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.06, blue: 0.13)
                        .opacity(0.44 * sceneStrength),
                    Color(red: 0.05, green: 0.08, blue: 0.18)
                        .opacity(0.25 * sceneStrength),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                context.drawLayer { city in
                    city.addFilter(.blur(radius: 18))
                    for index in 0..<18 {
                        let seed = Double(index) + 160
                        let x = size.width * CGFloat(0.04 + hash(seed) * 0.92)
                        let y = size.height * CGFloat(0.25 + hash(seed + 1) * 0.62)
                        let radius = CGFloat(8 + hash(seed + 2) * 25)
                        let palette: [Color] = [
                            .orange, .yellow, .cyan, .blue, color
                        ]
                        city.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: x - radius,
                                    y: y - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                )
                            ),
                            with: .color(
                                palette[index % palette.count]
                                    .opacity(
                                        (0.035 + hash(seed + 3) * 0.07)
                                            * sceneStrength
                                    )
                            )
                        )
                    }
                }

                var reflection = Path()
                reflection.move(to: CGPoint(x: size.width * 0.04, y: 0))
                reflection.addLine(
                    to: CGPoint(x: size.width * 0.42, y: size.height)
                )
                context.stroke(
                    reflection,
                    with: .color(.white.opacity(0.025 * sceneStrength)),
                    style: StrokeStyle(lineWidth: size.width * 0.08)
                )

                for index in 0..<44 {
                    let seed = Double(index) + 200
                    let x = size.width * CGFloat(0.025 + hash(seed) * 0.95)
                    let speed = 0.035 + hash(seed + 1) * 0.075
                    let travel = fract(time * speed + hash(seed + 2))
                    let y = size.height * CGFloat(travel * 1.22 - 0.11)
                    let length = CGFloat(10 + hash(seed + 3) * 68)
                    let width = CGFloat(0.8 + hash(seed + 4) * 1.7)
                    let drift = CGFloat(sin(time * 0.55 + seed) * 2.5)
                    let opacity = (0.08 + hash(seed + 5) * 0.16) * sceneStrength
                    var drop = Path()
                    drop.move(to: CGPoint(x: x + drift, y: y - length))
                    drop.addQuadCurve(
                        to: CGPoint(x: x, y: y),
                        control: CGPoint(
                            x: x + drift * 1.8,
                            y: y - length * 0.42
                        )
                    )
                    context.stroke(
                        drop,
                        with: .linearGradient(
                            Gradient(colors: [
                                .clear,
                                .white.opacity(opacity * 0.45),
                                .white.opacity(opacity)
                            ]),
                            startPoint: CGPoint(x: x, y: y - length),
                            endPoint: CGPoint(x: x, y: y)
                        ),
                        style: StrokeStyle(lineWidth: width, lineCap: .round)
                    )
                    let beadRadius = width * 1.65
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: x - beadRadius,
                                y: y - beadRadius,
                                width: beadRadius * 2,
                                height: beadRadius * 2.3
                            )
                        ),
                        with: .radialGradient(
                            Gradient(colors: [
                                .white.opacity(opacity * 0.9),
                                .white.opacity(opacity * 0.08),
                                .clear
                            ]),
                            center: CGPoint(
                                x: x - beadRadius * 0.3,
                                y: y - beadRadius * 0.45
                            ),
                            startRadius: 0,
                            endRadius: beadRadius * 1.4
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    private var starryNightScene: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.10)
                        .opacity(0.52 * sceneStrength),
                    Color(red: 0.045, green: 0.04, blue: 0.16)
                        .opacity(0.32 * sceneStrength),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                context.drawLayer { haze in
                    haze.addFilter(.blur(radius: 36))
                    var band = Path()
                    band.move(
                        to: CGPoint(x: -size.width * 0.15, y: size.height * 0.72)
                    )
                    band.addCurve(
                        to: CGPoint(
                            x: size.width * 1.15,
                            y: size.height * 0.18
                        ),
                        control1: CGPoint(
                            x: size.width * 0.28,
                            y: size.height * 0.54
                        ),
                        control2: CGPoint(
                            x: size.width * 0.76,
                            y: size.height * 0.38
                        )
                    )
                    haze.stroke(
                        band,
                        with: .color(
                            Color.indigo.opacity(0.055 * sceneStrength)
                        ),
                        style: StrokeStyle(
                            lineWidth: size.width * 0.22,
                            lineCap: .round
                        )
                    )
                }

                for index in 0..<84 {
                    let seed = Double(index) + 300
                    let x = size.width * CGFloat(hash(seed))
                    let y = size.height * CGFloat(hash(seed + 1) * 0.93)
                    let depth = hash(seed + 2)
                    let twinkle = naturalWave(
                        seed: seed,
                        speed: 0.45 + depth * 1.2
                    )
                    let radius = CGFloat(0.45 + depth * 1.65)
                    let opacity = (
                        0.07 + depth * 0.18 + twinkle * depth * 0.28
                    ) * sceneStrength
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: x - radius,
                                y: y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        ),
                        with: .color(.white.opacity(opacity))
                    )
                    if depth > 0.89 {
                        drawGlint(
                            in: &context,
                            at: CGPoint(x: x, y: y),
                            radius: radius * 2.8,
                            opacity: opacity * 0.62
                        )
                    }
                }

                let meteorCycle = fract(time / 11)
                if meteorCycle < 0.12 {
                    let progress = meteorCycle / 0.12
                    let head = CGPoint(
                        x: size.width * CGFloat(0.18 + progress * 0.55),
                        y: size.height * CGFloat(0.15 + progress * 0.17)
                    )
                    var trail = Path()
                    trail.move(
                        to: CGPoint(
                            x: head.x - size.width * 0.18,
                            y: head.y - size.height * 0.055
                        )
                    )
                    trail.addLine(to: head)
                    context.stroke(
                        trail,
                        with: .linearGradient(
                            Gradient(colors: [
                                .clear,
                                .white.opacity(0.42 * sceneStrength)
                            ]),
                            startPoint: CGPoint(
                                x: head.x - size.width * 0.18,
                                y: head.y
                            ),
                            endPoint: head
                        ),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawFireLogs(
        in context: inout GraphicsContext,
        size: CGSize,
        baseY: CGFloat
    ) {
        for index in 0..<3 {
            let offset = CGFloat(index - 1) * size.width * 0.09
            let angleOffset = CGFloat(index % 2 == 0 ? -1 : 1)
            var log = Path()
            log.move(
                to: CGPoint(
                    x: size.width * 0.29 + offset,
                    y: baseY + angleOffset * 8
                )
            )
            log.addLine(
                to: CGPoint(
                    x: size.width * 0.71 + offset,
                    y: baseY - angleOffset * 8
                )
            )
            context.stroke(
                log,
                with: .color(
                    Color(red: 0.16, green: 0.055, blue: 0.025)
                        .opacity(0.9 * sceneStrength)
                ),
                style: StrokeStyle(
                    lineWidth: 18,
                    lineCap: .round
                )
            )
            context.stroke(
                log,
                with: .color(
                    Color.orange.opacity(0.11 * sceneStrength)
                ),
                style: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    dash: [11, 8]
                )
            )
        }
    }

    private func drawEmbers(
        in context: inout GraphicsContext,
        size: CGSize,
        baseY: CGFloat
    ) {
        context.blendMode = .screen
        for index in 0..<28 {
            let seed = Double(index) + 400
            let speed = 0.06 + hash(seed + 1) * 0.11
            let travel = fract(time * speed + hash(seed + 2))
            let x = size.width * CGFloat(
                0.18 + hash(seed) * 0.64
                    + sin(time * 0.8 + seed) * 0.035
            )
            let y = baseY - size.height * CGFloat(travel * 0.34)
            let radius = CGFloat(0.7 + hash(seed + 3) * 2.3)
            let life = sin(Double.pi * travel)
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                ),
                with: .color(
                    Color.orange.opacity(
                        life * (0.18 + hash(seed + 4) * 0.48)
                            * sceneStrength
                    )
                )
            )
        }
    }

    private func flamePath(
        centerX: CGFloat,
        baseY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        sway: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centerX - width / 2, y: baseY))
        path.addCurve(
            to: CGPoint(x: centerX + sway, y: baseY - height),
            control1: CGPoint(
                x: centerX - width * 0.58,
                y: baseY - height * 0.30
            ),
            control2: CGPoint(
                x: centerX + sway - width * 0.23,
                y: baseY - height * 0.72
            )
        )
        path.addCurve(
            to: CGPoint(x: centerX + width / 2, y: baseY),
            control1: CGPoint(
                x: centerX + sway + width * 0.32,
                y: baseY - height * 0.62
            ),
            control2: CGPoint(
                x: centerX + width * 0.62,
                y: baseY - height * 0.23
            )
        )
        path.addQuadCurve(
            to: CGPoint(x: centerX - width / 2, y: baseY),
            control: CGPoint(x: centerX, y: baseY - height * 0.08)
        )
        path.closeSubpath()
        return path
    }

    private func drawGlint(
        in context: inout GraphicsContext,
        at point: CGPoint,
        radius: CGFloat,
        opacity: Double
    ) {
        var glint = Path()
        glint.move(to: CGPoint(x: point.x - radius, y: point.y))
        glint.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        glint.move(to: CGPoint(x: point.x, y: point.y - radius))
        glint.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        context.stroke(
            glint,
            with: .color(.white.opacity(opacity)),
            style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
        )
    }

    private func naturalWave(seed: Double, speed: Double) -> Double {
        let slow = sin(time * speed + seed * 1.73)
        let medium = sin(time * speed * 2.37 + seed * 3.11)
        let fast = sin(time * speed * 5.17 + seed * 5.03)
        return (slow * 0.52 + medium * 0.31 + fast * 0.17 + 1) / 2
    }

    private func hash(_ seed: Double) -> Double {
        fract(sin(seed * 12.9898) * 43_758.5453)
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}
