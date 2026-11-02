import Accessibility
import SwiftUI

struct WeatherPlotPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }

    static func nearest(to x: CGFloat, width: CGFloat, in points: [Self]) -> Self? {
        guard width.isFinite, width > 0, x.isFinite, !points.isEmpty else { return nil }
        let fraction = min(1, max(0, x / width))
        let index = min(points.count - 1, Int(fraction * CGFloat(points.count)))
        return points[index].value.isFinite ? points[index] : nil
    }
}

/// Axis labels occupy their own column, outside the plotting and hit-test area.
struct WeatherPlotAxis: View {
    let range: ClosedRange<Double>
    let unit: String
    @ScaledMetric(relativeTo: .caption2) private var labelHeight = 18
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label(range.upperBound))
            Spacer(minLength: 0)
            Text(label((range.lowerBound + range.upperBound) / 2))
            Spacer(minLength: 0)
            Text(label(range.lowerBound))
        }
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 110 + labelHeight)
        .accessibilityHidden(true)
    }
    private func label(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)))
        return number + (unit == "%" || unit.hasPrefix("°") ? unit : "")
    }
}

/// One drawing pass per plot; selection is local and does not refresh weather.
struct WeatherForecastPlot: View {
    let points: [WeatherPlotPoint]
    let range: ClosedRange<Double>
    let title: String
    let unit: String
    let timeZone: TimeZone
    var bars = false
    var showsYAxis = true
    var showsTimeAxis = true
    @Binding var selection: Date?
    var allowsSelection = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var labelHeight = 18

    init(points: [WeatherPlotPoint], range: ClosedRange<Double>, title: String, unit: String,
         timeZone: TimeZone, bars: Bool = false,
         showsYAxis: Bool = true, showsTimeAxis: Bool = true,
         selection: Binding<Date?> = .constant(nil), allowsSelection: Bool = false) {
        self.points = points; self.range = range; self.title = title; self.unit = unit
        self.timeZone = timeZone; self.bars = bars
        self.showsYAxis = showsYAxis; self.showsTimeAxis = showsTimeAxis
        self._selection = selection; self.allowsSelection = allowsSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsYAxis {
                Text("\(title) · \(unit)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                if showsYAxis { WeatherPlotAxis(range: range, unit: unit) }
                VStack(spacing: 4) {
                    Canvas { context, size in
                        let span = max(0.001, range.upperBound - range.lowerBound)
                        for fraction in [0.0, 0.5, 1.0] {
                            var rule = Path(); rule.move(to: CGPoint(x: 0, y: size.height * fraction))
                            rule.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                            context.stroke(rule, with: .color(.primary.opacity(0.1)), lineWidth: 0.5)
                        }
                        guard !points.isEmpty else { return }
                        let step = size.width / CGFloat(points.count)
                        func position(_ index: Int) -> CGPoint {
                            let fraction = min(1, max(0, (points[index].value - range.lowerBound) / span))
                            return CGPoint(x: (CGFloat(index) + 0.5) * step, y: size.height * (1 - fraction))
                        }
                        if bars {
                            var path = Path()
                            for index in points.indices where points[index].value.isFinite {
                                let point = position(index)
                                path.addRoundedRect(in: CGRect(x: point.x - step * 0.32, y: point.y,
                                    width: max(1, step * 0.64), height: size.height - point.y), cornerSize: CGSize(width: min(3, step * 0.2), height: 3))
                            }
                            context.fill(path, with: .linearGradient(Gradient(colors: [AppTheme.accent.opacity(0.65), AppTheme.accent]),
                                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                        } else {
                            var index = 0
                            while index < points.count {
                                guard points[index].value.isFinite else { index += 1; continue }
                                let first = position(index)
                                var line = Path(); line.move(to: first)
                                var area = Path(); area.move(to: CGPoint(x: first.x, y: size.height)); area.addLine(to: first)
                                var last = first
                                index += 1
                                while index < points.count && points[index].value.isFinite {
                                    last = position(index); line.addLine(to: last); area.addLine(to: last); index += 1
                                }
                                area.addLine(to: CGPoint(x: last.x, y: size.height)); area.closeSubpath()
                                context.fill(area, with: .linearGradient(Gradient(colors: [AppTheme.accent.opacity(0.2), AppTheme.accent.opacity(0.01)]),
                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                                context.stroke(line, with: .color(AppTheme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            }
                        }
                        if let index = points.firstIndex(where: { $0.date == selection && $0.value.isFinite }) {
                            let point = position(index)
                            var rule = Path(); rule.move(to: CGPoint(x: point.x, y: 0)); rule.addLine(to: CGPoint(x: point.x, y: size.height))
                            context.stroke(rule, with: .color(AppTheme.accent.opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                            context.fill(Path(ellipseIn: dot), with: .color(AppTheme.accent))
                        }
                    }
                    .frame(height: 110)
                    .overlay {
                        if allowsSelection {
                            GeometryReader { geometry in
                                Color.clear.contentShape(Rectangle())
                                    .gesture(SpatialTapGesture().onEnded { event in
                                        selection = WeatherPlotPoint.nearest(to: event.location.x, width: geometry.size.width, in: points)?.date
                                    })
                            }
                        }
                    }
                    .padding(.vertical, labelHeight / 2)
                    if showsTimeAxis {
                        GeometryReader { geometry in
                            let count = min(points.count, max(2, Int(geometry.size.width / max(90, labelHeight * 5))))
                            HStack(spacing: 0) {
                                ForEach(0..<count, id: \.self) { tick in
                                    let index = count > 1 ? tick * (points.count - 1) / (count - 1) : 0
                                    Text(minuteLabel(points[index].date)).font(.caption2).lineLimit(2)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: tick == 0 ? .leading : tick == count - 1 ? .trailing : .center)
                                }
                            }
                        }.frame(height: labelHeight * 2)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityChartDescriptor(WeatherPlotAccessibility(points: points, range: range, title: title, unit: unit, timeZone: timeZone, bars: bars))
    }
    private func minuteLabel(_ date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(points.first?.date ?? date) / 60))
        if minutes == 0 { return "Now" }
        return typeSize.isAccessibilitySize ? "+\(minutes)\nmin" : "+\(minutes)m"
    }
}

struct WeatherPlotAccessibility: AXChartDescriptorRepresentable {
    let points: [WeatherPlotPoint]
    let range: ClosedRange<Double>
    let title: String
    let unit: String
    let timeZone: TimeZone
    let bars: Bool
    func makeChartDescriptor() -> AXChartDescriptor {
        let start = points.first?.date.timeIntervalSince1970 ?? 0
        let end = max(start + 1, points.last?.date.timeIntervalSince1970 ?? start)
        let zone = timeZone
        let x = AXNumericDataAxisDescriptor(title: "Time", range: start...end, gridlinePositions: []) { value in
            var format = Date.FormatStyle(date: .abbreviated, time: .shortened); format.timeZone = zone
            return Date(timeIntervalSince1970: value).formatted(format)
        }
        let units = unit
        let y = AXNumericDataAxisDescriptor(title: title, range: range, gridlinePositions: [range.lowerBound, range.upperBound]) { value in
            "\(value.formatted(.number.precision(.fractionLength(0...3)))) \(units)"
        }
        return AXChartDescriptor(title: title, xAxis: x, yAxis: y, series: [
            AXDataSeriesDescriptor(name: title, isContinuous: !bars, dataPoints: points.filter { $0.value.isFinite }.map {
                AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value)
            })
        ])
    }
}
