import SwiftUI

enum WeatherMotionKind: Equatable {
    case rain, snow, wind, clouds, sun, night, fog, storm
    init(symbol: String, windKPH: Double) {
        if symbol.contains("bolt") { self = .storm }
        else if symbol.contains("snow") || symbol.contains("sleet") || symbol.contains("hail") { self = .snow }
        else if symbol.contains("rain") || symbol.contains("drizzle") { self = .rain }
        else if symbol.contains("fog") || symbol.contains("haze") || symbol.contains("smoke") || symbol.contains("dust") { self = .fog }
        else if symbol.contains("wind") || symbol.contains("tornado") { self = .wind }
        else if symbol.contains("cloud") { self = .clouds }
        else if symbol.contains("moon") { self = .night }
        else if symbol.contains("sun") { self = .sun }
        else if windKPH.isFinite && windKPH >= 25 { self = .wind }
        else { self = .sun }
    }
}

struct WeatherSceneConfiguration: Equatable {
    let kind: WeatherMotionKind
    let night: Bool
    let partlyCloudy: Bool
    let wind: Double
    init(symbol: String, windKPH: Double) {
        kind = WeatherMotionKind(symbol: symbol, windKPH: windKPH)
        night = symbol.contains("moon") || symbol.contains("stars")
        partlyCloudy = symbol.contains("sun") || symbol.contains("moon")
        wind = windKPH.isFinite ? min(1, max(0, windKPH / 60)) : 0
    }
    var tint: Color {
        if night { return Color(red: 0.38, green: 0.40, blue: 0.83) }
        switch kind {
        case .sun: return .orange
        case .snow: return .cyan
        case .wind: return .teal
        case .storm, .rain: return .indigo
        default: return .blue
        }
    }
}

/// A decorative, bounded drawing surface. Only this subtree receives frames;
/// its artwork is also used unchanged for the reduced-motion/static appearance.
struct WeatherAtmosphere: View {
    let symbol: String
    let windKPH: Double
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var powerLimited = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalLimited = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    private var animates: Bool { enabled && visible && !reduceMotion && scenePhase == .active && !powerLimited && !thermalLimited }
    var body: some View {
        let configuration = WeatherSceneConfiguration(symbol: symbol, windKPH: windKPH)
        Group {
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    scene(configuration, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else { scene(configuration, time: 4) }
        }
        .clipped().accessibilityHidden(true).allowsHitTesting(false)
        .onAppear { visible = true; updatePowerLimits() }.onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in updatePowerLimits() }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in updatePowerLimits() }
    }
    private func scene(_ configuration: WeatherSceneConfiguration, time: Double) -> some View {
        let _ = InteractionPerformanceAudit.count("weather.scene.frame")
        return WeatherAtmosphereArtwork(configuration: configuration, time: time)
    }
    private func updatePowerLimits() {
        powerLimited = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalLimited = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }
}

/// Shaded vector artwork: fixed paths, at most 36 precipitation particles, no
/// image decoding, blur passes, physics simulation, data reads, or random state.
struct WeatherAtmosphereArtwork: View {
    let configuration: WeatherSceneConfiguration
    let time: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            var drawing = context
            let scale = min(size.width, size.height) / 180
            drawing.translateBy(x: (size.width - 180 * scale) / 2, y: (size.height - 180 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            draw(in: drawing)
        }
        .clipped().accessibilityHidden(true).allowsHitTesting(false)
    }
    private var dark: Bool { scheme == .dark }
    private var kind: WeatherMotionKind { configuration.kind }
    private func draw(in context: GraphicsContext) {
        let drift = sin(time * 0.32) * 3
        glow(in: context, center: CGPoint(x: 100, y: 87), radius: 84,
             color: configuration.tint.opacity(dark ? 0.22 : 0.1))
        if configuration.night { stars(in: context) }
        switch kind {
        case .sun:
            sun(in: context, center: CGPoint(x: 94, y: 86), radius: 31)
        case .night:
            moon(in: context, center: CGPoint(x: 99, y: 82), radius: 31)
        case .clouds, .rain, .snow, .storm, .fog, .wind:
            if configuration.partlyCloudy {
                if configuration.night { moon(in: context, center: CGPoint(x: 122, y: 56), radius: 23) }
                else { sun(in: context, center: CGPoint(x: 119, y: 56), radius: 25) }
            }
            if kind == .rain || kind == .storm { rain(in: context) }
            if kind == .snow { snow(in: context) }
            // Two separately shaded silhouettes create depth without a 3D scene.
            cloud(in: context, center: CGPoint(x: 109 - drift * 0.6, y: 73), scale: 0.71, rear: true)
            cloud(in: context, center: CGPoint(x: 83 + drift, y: kind == .fog ? 76 : 91), scale: 0.96, rear: false)
            if kind == .wind { gusts(in: context) }
            if kind == .fog { mist(in: context) }
            if kind == .storm { lightning(in: context) }
        }
    }
    private func glow(in context: GraphicsContext, center: CGPoint, radius: Double, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
    }
    private func sun(in context: GraphicsContext, center: CGPoint, radius: Double) {
        glow(in: context, center: center, radius: radius * 2.3, color: .orange.opacity(dark ? 0.25 : 0.18))
        for index in 0..<12 {
            let angle = Double(index) * .pi / 6 + time * 0.025
            let inner = radius + 9, outer = inner + 5 + sin(time * 0.6 + Double(index)) * 2
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            ray.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.stroke(ray, with: .color(.orange.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        let disk = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disk, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.38), Color(red: 1, green: 0.64, blue: 0.12), Color(red: 0.98, green: 0.4, blue: 0.12)]),
                     startPoint: CGPoint(x: center.x - radius, y: center.y - radius), endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
        var light = context; light.clip(to: disk)
        glow(in: light, center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.48), radius: radius * 1.15, color: Color(red: 1, green: 0.99, blue: 0.83).opacity(0.9))
        context.stroke(disk, with: .color(.yellow.opacity(0.5)), lineWidth: 0.6)
    }
    private func moon(in context: GraphicsContext, center: CGPoint, radius: Double) {
        glow(in: context, center: center, radius: radius * 2.2, color: .indigo.opacity(0.16))
        var crescent = Path()
        crescent.move(to: CGPoint(x: center.x + radius * 0.4, y: center.y - radius * 0.92))
        crescent.addCurve(to: CGPoint(x: center.x + radius * 0.5, y: center.y + radius * 0.87),
                          control1: CGPoint(x: center.x - radius * 1.5, y: center.y - radius * 1.2),
                          control2: CGPoint(x: center.x - radius * 1.5, y: center.y + radius * 1.3))
        crescent.addCurve(to: CGPoint(x: center.x + radius * 0.4, y: center.y - radius * 0.92),
                          control1: CGPoint(x: center.x - radius * 0.55, y: center.y + radius * 0.45),
                          control2: CGPoint(x: center.x - radius * 0.55, y: center.y - radius * 0.55))
        crescent.closeSubpath()
        context.fill(crescent, with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.98, blue: 1), Color(red: 0.68, green: 0.79, blue: 0.98)]),
                     startPoint: CGPoint(x: center.x - radius, y: center.y - radius), endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
    }
    private func stars(in context: GraphicsContext) {
        for index in 0..<8 {
            let x = 24 + seed(index, 7) * 132, y = 22 + seed(index, 19) * 90
            let radius = index % 3 == 0 ? 2.6 : 1.3
            let opacity = 0.35 + 0.35 * (sin(time * 0.45 + Double(index)) + 1) / 2
            var star = Path(); star.move(to: CGPoint(x: x, y: y - radius * 1.5))
            star.addQuadCurve(to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y + radius * 1.5), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x - radius, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y - radius * 1.5), control: CGPoint(x: x, y: y)); star.closeSubpath()
            context.fill(star, with: .color((dark ? Color.white : Color.indigo).opacity(opacity)))
        }
    }
    private static let cloudPath: Path = {
        var p = Path(); p.move(to: CGPoint(x: -47, y: 19))
        p.addCurve(to: CGPoint(x: -47, y: -20), control1: CGPoint(x: -76, y: 18), control2: CGPoint(x: -77, y: -17))
        p.addCurve(to: CGPoint(x: -17, y: -33), control1: CGPoint(x: -42, y: -37), control2: CGPoint(x: -30, y: -39))
        p.addCurve(to: CGPoint(x: 29, y: -23), control1: CGPoint(x: 1, y: -57), control2: CGPoint(x: 32, y: -48))
        p.addCurve(to: CGPoint(x: 51, y: 18), control1: CGPoint(x: 63, y: -29), control2: CGPoint(x: 78, y: 13))
        p.addCurve(to: CGPoint(x: -47, y: 19), control1: CGPoint(x: 33, y: 23), control2: CGPoint(x: -24, y: 23))
        p.closeSubpath(); return p
    }()
    private func cloud(in context: GraphicsContext, center: CGPoint, scale: Double, rear: Bool) {
        var cloud = context; cloud.translateBy(x: center.x, y: center.y + sin(time * 0.41 + (rear ? 1 : 0)) * 1.4)
        cloud.scaleBy(x: scale, y: scale)
        let storm = kind == .storm || kind == .rain
        let top = storm ? Color(red: 0.78, green: 0.84, blue: 0.95) : Color(red: 0.99, green: 1, blue: 1)
        let base = storm ? Color(red: 0.33, green: 0.43, blue: 0.64) : Color(red: 0.59, green: 0.71, blue: 0.88)
        cloud.opacity = rear ? 0.7 : 1
        // A soft gradient shadow and clipped light lobes suggest a rounded volume.
        glow(in: cloud, center: CGPoint(x: 1, y: 24), radius: 58, color: .indigo.opacity(rear ? 0.05 : 0.12))
        cloud.fill(Self.cloudPath, with: .linearGradient(Gradient(colors: [top, top.opacity(0.96), base]), startPoint: CGPoint(x: -12, y: -44), endPoint: CGPoint(x: 5, y: 29)))
        var highlights = cloud; highlights.clip(to: Self.cloudPath)
        for (x, y, r) in [(-44.0, -12.0, 24.0), (-22, -25, 24), (9, -32, 31), (43, -6, 25)] {
            glow(in: highlights, center: CGPoint(x: x - 6, y: y - 7), radius: r, color: .white.opacity(storm ? 0.23 : 0.65))
        }
        cloud.stroke(Self.cloudPath, with: .color(.white.opacity(storm ? 0.14 : 0.45)), lineWidth: 0.65)
    }
    private func rain(in context: GraphicsContext) {
        for index in 0..<36 {
            let depth = 0.4 + seed(index, 13) * 0.6
            let progress = phase(time * (0.65 + depth * 0.45) + seed(index, 31))
            let fade = min(1, progress * 7) * min(1, (1 - progress) * 5)
            let x = 32 + seed(index, 3) * 119 - progress * (8 + configuration.wind * 22)
            let y = 95 + progress * 76
            let length = 7 + depth * 8
            var drop = Path(); drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - length * (0.2 + configuration.wind * 0.45), y: y + length))
            context.stroke(drop, with: .linearGradient(Gradient(colors: [.cyan.opacity(0), Color(red: dark ? 0.42 : 0.25, green: dark ? 0.77 : 0.62, blue: 0.95).opacity(fade * depth * (dark ? 0.85 : 0.65))]),
                           startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + length)), style: StrokeStyle(lineWidth: 0.7 + depth * 0.9, lineCap: .round))
        }
    }
    private func snow(in context: GraphicsContext) {
        for index in 0..<26 {
            let depth = 0.35 + seed(index, 23) * 0.65
            let progress = phase(time * (0.09 + depth * 0.08) + seed(index, 17))
            let x = 26 + seed(index, 29) * 128 + sin(time * 0.6 + Double(index)) * (4 + depth * 6)
            let y = 91 + progress * 80, radius = 0.9 + depth * 1.6
            let fade = min(1, progress * 8) * min(1, (1 - progress) * 5)
            let color = (dark ? Color.white : Color(red: 0.36, green: 0.62, blue: 0.83)).opacity(fade * depth * 0.8)
            if index % 6 == 0 {
                var flake = Path()
                for arm in 0..<3 {
                    let angle = Double(arm) * .pi / 3 + time * 0.1
                    flake.move(to: CGPoint(x: x - cos(angle) * radius * 1.7, y: y - sin(angle) * radius * 1.7))
                    flake.addLine(to: CGPoint(x: x + cos(angle) * radius * 1.7, y: y + sin(angle) * radius * 1.7))
                }
                context.stroke(flake, with: .color(color), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            } else { context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(color)) }
        }
    }
    private func gusts(in context: GraphicsContext) {
        for index in 0..<5 {
            let progress = phase(time * (0.19 + configuration.wind * 0.08) + Double(index) / 5)
            let x = progress * 260 - 60, y = 101 + Double(index) * 12 + sin(time * 0.7 + Double(index)) * 3
            let fade = sin(progress * .pi)
            var gust = Path(); gust.move(to: CGPoint(x: x, y: y))
            gust.addCurve(to: CGPoint(x: x + 51, y: y - 4), control1: CGPoint(x: x + 16, y: y - 10), control2: CGPoint(x: x + 39, y: y + 5))
            context.stroke(gust, with: .linearGradient(Gradient(colors: [.teal.opacity(0), .teal.opacity(fade * 0.6), .cyan.opacity(0)]),
                           startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + 51, y: y)), style: StrokeStyle(lineWidth: index % 2 == 0 ? 2 : 1, lineCap: .round))
        }
        for index in 0..<2 {
            let progress = phase(time * 0.17 + Double(index) * 0.5)
            var leaf = context; leaf.opacity = sin(progress * .pi) * 0.75
            leaf.translateBy(x: progress * 215 - 18, y: 122 + sin(progress * .pi * 2 + Double(index)) * 15)
            leaf.rotate(by: .radians(sin(time * 0.8 + Double(index)) * 0.6))
            var path = Path(); path.move(to: CGPoint(x: -5, y: 0))
            path.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: 0, y: -7))
            path.addQuadCurve(to: CGPoint(x: -5, y: 0), control: CGPoint(x: 0, y: 5))
            leaf.fill(path, with: .color(.orange.opacity(0.75)))
        }
    }
    private func mist(in context: GraphicsContext) {
        for index in 0..<5 {
            let x = 22 + sin(time * 0.24 + Double(index)) * 8, y = 99 + Double(index) * 11
            let width = 123 - Double(index % 2) * 20
            let band = Path(roundedRect: CGRect(x: x, y: y, width: width, height: 5), cornerRadius: 3)
            context.fill(band, with: .linearGradient(Gradient(colors: [.blue.opacity(0), .blue.opacity(dark ? 0.3 : 0.18), .blue.opacity(0)]), startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + width, y: y)))
        }
    }
    private func lightning(in context: GraphicsContext) {
        var bolt = Path(); bolt.move(to: CGPoint(x: 91, y: 102))
        for point in [CGPoint(x: 77, y: 125), CGPoint(x: 89, y: 124), CGPoint(x: 80, y: 146), CGPoint(x: 108, y: 115), CGPoint(x: 95, y: 116), CGPoint(x: 104, y: 102)] { bolt.addLine(to: point) }
        bolt.closeSubpath()
        context.fill(bolt, with: .linearGradient(Gradient(colors: [.yellow, .orange]), startPoint: CGPoint(x: 92, y: 102), endPoint: CGPoint(x: 90, y: 146)))
    }
    private func seed(_ index: Int, _ salt: Int) -> Double {
        // Independent hashed channels avoid diagonal rows of rain/snow particles.
        var value = UInt64(index + 1) &* 0x9E3779B97F4A7C15 ^ UInt64(salt) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) & 0xFFFFFF) / 0x1000000
    }
    private func phase(_ value: Double) -> Double { value - floor(value) }
}
