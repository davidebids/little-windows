import SwiftUI

struct PlanDayArcView: View {
    let plan: BackwardsSleepPlan

    var body: some View {
        TimelineView(.animation) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let model = PlanDayArcModel(plan: plan, now: now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Wake to bedtime")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.94))
                Spacer(minLength: 8)
            }

            GeometryReader { proxy in
                ZStack {
                    PlanDayArcCanvas(model: model)

                    ForEach(model.endpointLabels) { label in
                        PlanDayArcEndpointMarker(label: label)
                            .position(label.markerPosition(in: proxy.size, model: model))
                            .accessibilityHidden(true)
                    }

                    ForEach(model.endpointLabels) { label in
                        PlanDayArcEndpointTimeLabel(label: label)
                            .position(label.timePosition(in: proxy.size, model: model))
                            .accessibilityHidden(true)
                    }

                    ForEach(model.napIcons) { icon in
                        PlanDayArcNapIcon(icon: icon)
                            .position(icon.position(in: proxy.size))
                            .accessibilityHidden(true)
                    }

                    PlanDayArcCenterSummary(model: model)
                        .position(model.centerSummaryPosition(in: proxy.size))
                        .accessibilityHidden(true)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 270)
        }
        .padding(16)
        .background {
            PlanDayArcSkyBackground()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilitySummary)
    }
}

private enum PlanDayArcStyle {
    static let skyTop = Color(red: 0.06, green: 0.06, blue: 0.17)
    static let skyBottom = Color(red: 0.10, green: 0.08, blue: 0.25)
    static let ring = Color(red: 0.48, green: 0.47, blue: 0.98)
    static let label = Color(red: 0.77, green: 0.75, blue: 1.00)
    static let nap = Color(red: 0.61, green: 0.57, blue: 0.98)
    static let awake = Color(red: 0.95, green: 0.64, blue: 0.35)
    static let bedtime = Color(red: 0.92, green: 0.52, blue: 0.34)
    static let progress = Color(red: 0.70, green: 0.67, blue: 1.00)
}

private struct PlanDayArcSkyBackground: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 18),
                with: .linearGradient(
                    Gradient(colors: [PlanDayArcStyle.skyTop, PlanDayArcStyle.skyBottom]),
                    startPoint: CGPoint(x: size.width * 0.5, y: 0),
                    endPoint: CGPoint(x: size.width * 0.5, y: size.height)
                )
            )

            for index in 0..<34 {
                let x = CGFloat((index * 47) % 101) / 100 * size.width
                let y = CGFloat((index * 29 + 13) % 101) / 100 * size.height
                let radius = CGFloat((index % 3) + 1) * 0.55
                var star = Path()
                star.addEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
                context.fill(star, with: .color(.white.opacity(index % 5 == 0 ? 0.40 : 0.18)))
            }

            let glowRect = CGRect(
                x: size.width * 0.18,
                y: size.height * 0.16,
                width: size.width * 0.64,
                height: size.height * 0.70
            )
            var glow = Path()
            glow.addEllipse(in: glowRect)
            context.fill(glow, with: .color(PlanDayArcStyle.ring.opacity(0.07)))
        }
    }
}

private struct PlanDayArcCanvas: View {
    let model: PlanDayArcModel

    var body: some View {
        Canvas { context, size in
            let geometry = PlanDayArcGeometry(size: size)
            let lineWidth = geometry.lineWidth

            context.stroke(
                geometry.arcPath(from: 0, to: 1),
                with: .color(PlanDayArcStyle.ring.opacity(0.12)),
                style: StrokeStyle(lineWidth: lineWidth * 1.06, lineCap: .round)
            )

            for segment in model.awakeSegments {
                context.stroke(
                    geometry.arcPath(
                        from: model.fraction(for: segment.startDate),
                        to: model.fraction(for: segment.endDate)
                    ),
                    with: .color(PlanDayArcStyle.awake.opacity(0.11)),
                    style: StrokeStyle(lineWidth: lineWidth * 0.64, lineCap: .round)
                )
            }

            drawProgress(geometry: geometry, context: context)

            for nap in model.napSegments {
                let startFraction = model.fraction(for: nap.startDate)
                let endFraction = model.fraction(for: nap.endDate)
                let phase = model.phase(for: nap)
                let outerLineWidth = lineWidth * 0.96
                let innerLineWidth = lineWidth * 0.58
                let outerRange = geometry.capAdjustedRange(
                    from: startFraction,
                    to: endFraction,
                    lineWidth: outerLineWidth
                )
                let innerRange = geometry.capAdjustedRange(
                    from: startFraction,
                    to: endFraction,
                    lineWidth: innerLineWidth
                )
                context.stroke(
                    geometry.arcPath(from: outerRange.lowerBound, to: outerRange.upperBound),
                    with: .color(phase.napColor.opacity(phase.glowOpacity)),
                    style: StrokeStyle(lineWidth: outerLineWidth * 1.38, lineCap: .round)
                )
                context.stroke(
                    geometry.arcPath(from: outerRange.lowerBound, to: outerRange.upperBound),
                    with: .color(phase.napColor.opacity(phase.outerOpacity)),
                    style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .round)
                )
                context.stroke(
                    geometry.arcPath(from: innerRange.lowerBound, to: innerRange.upperBound),
                    with: .color(phase.napColor.opacity(phase.innerOpacity)),
                    style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round)
                )
            }

            drawNapTimeLabels(geometry: geometry, context: context)
        }
    }

    private func drawNapTimeLabels(
        geometry: PlanDayArcGeometry,
        context: GraphicsContext
    ) {
        for label in model.napLabels {
            drawCurvedLabel(label, geometry: geometry, context: context)
        }
    }

    private func drawCurvedLabel(
        _ label: PlanDayArcTimeLabelModel,
        geometry: PlanDayArcGeometry,
        context: GraphicsContext
    ) {
        let characters = Array(label.text)
        let radiusOffset = geometry.lineWidth * (label.isDense ? 0.80 : 0.84)
        let advance: CGFloat = label.isDense ? 4.0 : 4.35
        let midpoint = CGFloat(max(0, characters.count - 1)) / 2
        let labelHalfWidth = midpoint * advance
        let capGap: CGFloat = label.isDense ? 3 : 4
        let signedDistance = (labelHalfWidth + capGap) * label.side.distanceSign
        let anchorFraction = min(
            1,
            max(
                0,
                label.fraction
                    + geometry.fractionOffset(forArcDistance: signedDistance, radiusOffset: radiusOffset)
            )
        )

        for index in characters.indices {
            let distance = (CGFloat(index) - midpoint) * advance
            let characterFraction = min(
                1,
                max(
                    0,
                    anchorFraction
                        + geometry.fractionOffset(forArcDistance: distance, radiusOffset: radiusOffset)
                )
            )
            let point = geometry.point(for: characterFraction, radiusOffset: radiusOffset)
            let tangent = geometry.tangentVector(for: characterFraction)
            let rotation = Angle.radians(Double(atan2(tangent.dy, tangent.dx)))
            let text = Text(String(characters[index]))
                .font(.system(size: label.fontSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(label.phase.labelColor.opacity(label.phase.labelOpacity))

            var glyphContext = context
            glyphContext.translateBy(x: point.x, y: point.y)
            glyphContext.rotate(by: rotation)
            glyphContext.draw(text, at: .zero, anchor: .center)
        }
    }

    private func drawProgress(
        geometry: PlanDayArcGeometry,
        context: GraphicsContext
    ) {
        let fraction = model.currentProgressFraction
        guard fraction > 0 else { return }

        context.stroke(
            geometry.arcPath(from: 0, to: fraction, radiusOffset: geometry.lineWidth * 0.05),
            with: .color(PlanDayArcStyle.progress.opacity(0.18)),
            style: StrokeStyle(lineWidth: geometry.lineWidth * 0.08, lineCap: .round)
        )

        let point = geometry.point(for: fraction, radiusOffset: geometry.lineWidth * 0.05)
        let pulse = model.currentTimePulse
        let dotRadius = max(4, geometry.lineWidth * (0.10 + (0.018 * pulse)))
        let haloScale = 1.48 + (0.34 * pulse)
        var halo = Path()
        halo.addEllipse(
            in: CGRect(
                x: point.x - dotRadius * haloScale,
                y: point.y - dotRadius * haloScale,
                width: dotRadius * haloScale * 2,
                height: dotRadius * haloScale * 2
            )
        )
        context.fill(halo, with: .color(PlanDayArcStyle.progress.opacity(0.05 + (0.07 * pulse))))

        var dot = Path()
        dot.addEllipse(
            in: CGRect(
                x: point.x - dotRadius,
                y: point.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
        )
        context.fill(dot, with: .color(PlanDayArcStyle.progress.opacity(0.54)))
        context.stroke(dot, with: .color(.white.opacity(0.24)), lineWidth: 0.8)
    }

}

private struct PlanDayArcEndpointMarker: View {
    let label: PlanDayArcEndpointLabelModel

    var body: some View {
        ZStack {
            Circle()
                .fill(PlanDayArcStyle.skyTop.opacity(0.72))
            Circle()
                .fill(label.color.opacity(label.phase.endpointFillOpacity))
            Circle()
                .stroke(label.color.opacity(label.phase.endpointStrokeOpacity), lineWidth: 1.2)
            Image(systemName: label.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(label.color.opacity(label.phase.endpointIconOpacity))
        }
        .frame(width: 29, height: 29)
        .shadow(color: label.color.opacity(label.phase.endpointGlowOpacity), radius: 8, y: 2)
    }
}

private struct PlanDayArcEndpointTimeLabel: View {
    let label: PlanDayArcEndpointLabelModel

    var body: some View {
        Text(label.text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(label.color.opacity(label.phase.endpointTimeOpacity))
            .lineLimit(1)
            .shadow(color: label.color.opacity(label.phase.endpointGlowOpacity * 0.65), radius: 5, y: 1)
    }
}

private struct PlanDayArcNapIcon: View {
    let icon: PlanDayArcNapIconModel

    var body: some View {
        Image(systemName: "cloud.moon.fill")
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                .white.opacity(icon.phase.iconPrimaryOpacity),
                icon.phase.napColor.opacity(icon.phase.iconTintOpacity)
            )
            .shadow(color: icon.phase.napColor.opacity(icon.phase.iconGlowOpacity), radius: 5, y: 1)
    }
}

private struct PlanDayArcCenterSummary: View {
    let model: PlanDayArcModel

    var body: some View {
        VStack(spacing: 3) {
            Text(model.centerSummaryTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(PlanDayArcStyle.label.opacity(0.78))
            Text(model.centerSummaryValue)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.94))
        }
        .multilineTextAlignment(.center)
        .shadow(color: PlanDayArcStyle.skyTop.opacity(0.95), radius: 5, y: 2)
    }
}

private struct PlanDayArcModel {
    let plan: BackwardsSleepPlan
    let now: Date

    var startDate: Date {
        plan.segments.first { $0.kind != .bedtime }?.startDate
            ?? plan.targetBedtime.addingTimeInterval(-12 * 3_600)
    }

    var endDate: Date {
        plan.targetBedtime
    }

    var awakeSegments: [BackwardsSleepPlanSegment] {
        plan.segments.filter { $0.kind == .wakeWindow && $0.endDate > $0.startDate }
    }

    var napSegments: [BackwardsSleepPlanSegment] {
        plan.segments.filter { $0.kind == .nap && $0.endDate > $0.startDate }
    }

    var currentProgressFraction: Double {
        fraction(for: now)
    }

    var currentTimePulse: Double {
        let duration: TimeInterval = 2.4
        let progress = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        return (sin(progress * .pi * 2 - (.pi / 2)) + 1) / 2
    }

    var summaryText: String {
        if napSegments.isEmpty {
            return "No naps are planned before the target bedtime."
        }
        return "\(napSegments.count) planned nap\(napSegments.count == 1 ? "" : "s") before bedtime."
    }

    var centerSummaryTitle: String {
        napSegments.isEmpty ? "No naps planned" : "Planned naps"
    }

    var centerSummaryValue: String {
        napSegments.isEmpty ? "0" : "\(napSegments.count)"
    }

    var accessibilitySummary: String {
        var pieces = ["Plan from \(DateFormatting.time.string(from: startDate)) to \(DateFormatting.time.string(from: endDate))."]
        if now >= startDate, now <= endDate {
            pieces.append("Current time is \(DateFormatting.time.string(from: now)).")
        }
        if !napSegments.isEmpty {
            pieces.append(summaryText)
        }
        return pieces.joined(separator: " ")
    }

    var endpointLabels: [PlanDayArcEndpointLabelModel] {
        [
            PlanDayArcEndpointLabelModel(
                fraction: 0,
                text: DateFormatting.time.string(from: startDate),
                systemImage: "sun.max.fill",
                color: PlanDayArcStyle.awake,
                phase: endpointPhase(for: startDate)
            ),
            PlanDayArcEndpointLabelModel(
                fraction: 1,
                text: DateFormatting.time.string(from: endDate),
                systemImage: "bed.double.fill",
                color: PlanDayArcStyle.bedtime,
                phase: endpointPhase(for: endDate)
            )
        ]
    }

    var napLabels: [PlanDayArcTimeLabelModel] {
        let isDense = napSegments.count >= 4
        return napSegments.flatMap { segment in
            let startFraction = fraction(for: segment.startDate)
            let endFraction = fraction(for: segment.endDate)
            let phase = phase(for: segment)
            return [
                PlanDayArcTimeLabelModel(
                    fraction: startFraction,
                    text: PlanDayArcTimeFormatting.arcTime.string(from: segment.startDate),
                    side: .leading,
                    isDense: isDense,
                    phase: phase
                ),
                PlanDayArcTimeLabelModel(
                    fraction: endFraction,
                    text: PlanDayArcTimeFormatting.arcTime.string(from: segment.endDate),
                    side: .trailing,
                    isDense: isDense,
                    phase: phase
                )
            ]
        }
    }

    var napIcons: [PlanDayArcNapIconModel] {
        napSegments.map { segment in
            PlanDayArcNapIconModel(fraction: midpointFraction(for: segment), phase: phase(for: segment))
        }
    }

    func fraction(for date: Date) -> Double {
        let duration = max(60, endDate.timeIntervalSince(startDate))
        return min(1, max(0, date.timeIntervalSince(startDate) / duration))
    }

    func centerSummaryPosition(in size: CGSize) -> CGPoint {
        let geometry = PlanDayArcGeometry(size: size)
        let point = geometry.centerPoint
        return CGPoint(x: point.x, y: point.y - 10)
    }

    private func midpointFraction(for segment: BackwardsSleepPlanSegment) -> Double {
        let duration = segment.endDate.timeIntervalSince(segment.startDate)
        return fraction(for: segment.startDate.addingTimeInterval(duration / 2))
    }

    func phase(for segment: BackwardsSleepPlanSegment) -> PlanDayArcItemPhase {
        if now >= segment.endDate {
            return .past
        }
        if now >= segment.startDate {
            return .current
        }
        return .future
    }

    private func endpointPhase(for date: Date) -> PlanDayArcItemPhase {
        now >= date ? .past : .future
    }

}

private struct PlanDayArcEndpointLabelModel: Identifiable {
    let id = UUID()
    let fraction: Double
    let text: String
    let systemImage: String
    let color: Color
    let phase: PlanDayArcItemPhase

    func markerPosition(in size: CGSize, model: PlanDayArcModel) -> CGPoint {
        let geometry = PlanDayArcGeometry(size: size)
        return geometry.point(for: fraction, radiusOffset: 0)
    }

    func timePosition(in size: CGSize, model: PlanDayArcModel) -> CGPoint {
        let geometry = PlanDayArcGeometry(size: size)
        let point = geometry.point(for: fraction, radiusOffset: 0)
        return CGPoint(
            x: point.x,
            y: min(point.y + 36, size.height - 14)
        )
    }
}

private struct PlanDayArcTimeLabelModel: Identifiable {
    let id = UUID()
    let fraction: Double
    let text: String
    let side: PlanDayArcLabelSide
    let isDense: Bool
    let phase: PlanDayArcItemPhase

    var fontSize: CGFloat {
        isDense ? 6.7 : 7.2
    }
}

private struct PlanDayArcNapIconModel: Identifiable {
    let id = UUID()
    let fraction: Double
    let phase: PlanDayArcItemPhase

    func position(in size: CGSize) -> CGPoint {
        let geometry = PlanDayArcGeometry(size: size)
        return geometry.point(for: fraction, radiusOffset: 0)
    }
}

private enum PlanDayArcItemPhase {
    case past
    case current
    case future

    var napColor: Color {
        switch self {
        case .past:
            return Color(red: 0.66, green: 0.67, blue: 0.76)
        case .current, .future:
            return PlanDayArcStyle.nap
        }
    }

    var labelColor: Color {
        switch self {
        case .past:
            return Color(red: 0.70, green: 0.70, blue: 0.78)
        case .current, .future:
            return PlanDayArcStyle.label
        }
    }

    var outerOpacity: Double {
        switch self {
        case .past:
            return 0.16
        case .current:
            return 0.30
        case .future:
            return 0.22
        }
    }

    var innerOpacity: Double {
        switch self {
        case .past:
            return 0.23
        case .current:
            return 0.56
        case .future:
            return 0.42
        }
    }

    var glowOpacity: Double {
        switch self {
        case .past:
            return 0.035
        case .current:
            return 0.13
        case .future:
            return 0.07
        }
    }

    var labelOpacity: Double {
        switch self {
        case .past:
            return 0.58
        case .current:
            return 0.92
        case .future:
            return 0.82
        }
    }

    var iconPrimaryOpacity: Double {
        switch self {
        case .past:
            return 0.58
        case .current:
            return 0.96
        case .future:
            return 0.86
        }
    }

    var iconTintOpacity: Double {
        switch self {
        case .past:
            return 0.42
        case .current:
            return 0.88
        case .future:
            return 0.76
        }
    }

    var iconGlowOpacity: Double {
        switch self {
        case .past:
            return 0.06
        case .current:
            return 0.22
        case .future:
            return 0.10
        }
    }

    var endpointFillOpacity: Double {
        switch self {
        case .past:
            return 0.08
        case .current:
            return 0.16
        case .future:
            return 0.14
        }
    }

    var endpointStrokeOpacity: Double {
        switch self {
        case .past:
            return 0.36
        case .current:
            return 0.78
        case .future:
            return 0.68
        }
    }

    var endpointIconOpacity: Double {
        switch self {
        case .past:
            return 0.54
        case .current:
            return 0.96
        case .future:
            return 0.90
        }
    }

    var endpointGlowOpacity: Double {
        switch self {
        case .past:
            return 0.06
        case .current:
            return 0.26
        case .future:
            return 0.22
        }
    }

    var endpointTimeOpacity: Double {
        switch self {
        case .past:
            return 0.58
        case .current:
            return 0.88
        case .future:
            return 0.82
        }
    }
}

private enum PlanDayArcLabelSide {
    case leading
    case trailing

    var distanceSign: CGFloat {
        switch self {
        case .leading:
            return -1
        case .trailing:
            return 1
        }
    }
}

private enum PlanDayArcTimeFormatting {
    static let arcTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()
}

private struct PlanDayArcGeometry {
    let size: CGSize

    var lineWidth: CGFloat {
        max(18, min(size.width, size.height) * 0.11)
    }

    private var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.55)
    }

    var centerPoint: CGPoint {
        center
    }

    private var radius: CGFloat {
        min(size.width * 0.40, size.height * 0.37)
    }

    private var arcLength: CGFloat {
        radius * CGFloat(abs(endAngle - startAngle))
    }

    private var startAngle: Double {
        Double.pi + (Double.pi * 0.31)
    }

    private var endAngle: Double {
        -(Double.pi * 0.31)
    }

    func arcPath(
        from startFraction: Double,
        to endFraction: Double,
        radiusOffset: CGFloat = 0
    ) -> Path {
        var path = Path()
        let start = min(max(startFraction, 0), 1)
        let end = min(max(endFraction, start), 1)
        let steps = max(4, Int((end - start) * 72))

        for step in 0...steps {
            let fraction = start + (end - start) * (Double(step) / Double(steps))
            let point = point(for: fraction, radiusOffset: radiusOffset)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    func capAdjustedRange(
        from startFraction: Double,
        to endFraction: Double,
        lineWidth: CGFloat
    ) -> ClosedRange<Double> {
        let start = min(max(startFraction, 0), 1)
        let end = min(max(endFraction, start), 1)
        let span = end - start
        guard span > 0 else { return start...end }

        let capFraction = Double((lineWidth / 2) / max(1, arcLength))
        let inset = min(capFraction * 0.48, span * 0.28)
        return (start + inset)...(end - inset)
    }

    func fractionOffset(forArcDistance distance: CGFloat, radiusOffset: CGFloat) -> Double {
        let adjustedRadius = max(1, radius + radiusOffset)
        let adjustedArcLength = adjustedRadius * CGFloat(abs(endAngle - startAngle))
        return Double(distance / adjustedArcLength)
    }

    func point(for fraction: Double, radiusOffset: CGFloat) -> CGPoint {
        let clamped = min(max(fraction, 0), 1)
        let angle = angle(for: clamped)
        let adjustedRadius = radius + radiusOffset
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * adjustedRadius,
            y: center.y - CGFloat(sin(angle)) * adjustedRadius
        )
    }

    func tangentVector(for fraction: Double) -> CGVector {
        let angle = angle(for: min(max(fraction, 0), 1))
        return CGVector(dx: CGFloat(sin(angle)), dy: CGFloat(cos(angle)))
    }

    func outwardNormalVector(for fraction: Double) -> CGVector {
        let angle = angle(for: min(max(fraction, 0), 1))
        return CGVector(dx: CGFloat(cos(angle)), dy: -CGFloat(sin(angle)))
    }

    private func angle(for fraction: Double) -> Double {
        startAngle + ((endAngle - startAngle) * fraction)
    }
}

#Preview("Plan day arc") {
    let now = Date()
    let calendar = Calendar.current
    let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
    let bedtime = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: now) ?? now
    let segments = [
        BackwardsSleepPlanSegment(kind: .wakeWindow, napIndex: 1, startDate: start, endDate: start.addingTimeInterval(2.5 * 3_600), durationMinutes: 150),
        BackwardsSleepPlanSegment(kind: .nap, napIndex: 1, startDate: start.addingTimeInterval(2.5 * 3_600), endDate: start.addingTimeInterval(3.75 * 3_600), durationMinutes: 75),
        BackwardsSleepPlanSegment(kind: .wakeWindow, napIndex: 2, startDate: start.addingTimeInterval(3.75 * 3_600), endDate: start.addingTimeInterval(7 * 3_600), durationMinutes: 195),
        BackwardsSleepPlanSegment(kind: .nap, napIndex: 2, startDate: start.addingTimeInterval(7 * 3_600), endDate: start.addingTimeInterval(8 * 3_600), durationMinutes: 60),
        BackwardsSleepPlanSegment(kind: .wakeWindow, napIndex: nil, startDate: start.addingTimeInterval(8 * 3_600), endDate: bedtime, durationMinutes: 270),
        BackwardsSleepPlanSegment(kind: .bedtime, napIndex: nil, startDate: bedtime, endDate: bedtime, durationMinutes: 0)
    ]
    return PlanDayArcView(
        plan: BackwardsSleepPlan(
            targetBedtime: bedtime,
            generatedAt: now,
            historyRange: .sevenDays,
            targetNapCount: nil,
            plannedNapCount: 2,
            typicalNapCount: 2,
            sourceDayCount: 7,
            confidence: 0.72,
            confidenceLabel: .medium,
            segments: segments,
            explanation: []
        )
    )
    .padding()
    .background(AppTheme.background)
}
