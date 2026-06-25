import Charts
import SwiftUI

struct WakeWindowInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.wakeMetrics)
            InsightObservationsCard(trends: snapshot.wakeTrends)

            InsightChartCard(
                title: "Wake windows by nap",
                subtitle: "Average minutes by sleep index",
                isEmpty: snapshot.wakeAverages.isEmpty,
                emptyMessage: "Log at least three days of sleep to compare wake windows."
            ) {
                Chart(snapshot.wakeAverages) { item in
                    BarMark(
                        x: .value("Sleep", item.category),
                        y: .value("Minutes", item.value)
                    )
                    .foregroundStyle(.teal.gradient)
                    .cornerRadius(5)
                }
            }

            InsightChartCard(
                title: "Sleep starts by pressure",
                subtitle: "Completed sleeps grouped by readiness band",
                isEmpty: snapshot.sleepPressureBandCounts.isEmpty,
                emptyMessage: "Pressure history appears for child profiles over 4 months after enough completed sleep logs."
            ) {
                Chart(snapshot.sleepPressureBandCounts) { item in
                    BarMark(
                        x: .value("Band", item.category),
                        y: .value("Sleeps", item.value)
                    )
                    .foregroundStyle(by: .value("Band", item.category))
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(Int(item.value.rounded()))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartForegroundStyleScale(pressureBandStyleScale)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let count = value.as(Double.self) {
                                Text("\(Int(count.rounded()))")
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
            }

            InsightChartCard(
                title: "Pressure by sleep order",
                subtitle: "Average score before each nap or bedtime",
                isEmpty: snapshot.sleepPressureAverages.isEmpty,
                emptyMessage: "More completed sleeps are needed to compare pressure by sleep order."
            ) {
                Chart {
                    RuleMark(y: .value("Ready", 65))
                        .foregroundStyle(Color.green.opacity(0.30))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("High", 88))
                        .foregroundStyle(Color.orange.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(snapshot.sleepPressureAverages) { item in
                        BarMark(
                            x: .value("Sleep", item.category),
                            y: .value("Score", item.value)
                        )
                        .foregroundStyle(pressureColor(for: item.value).gradient)
                        .cornerRadius(5)
                        .annotation(position: .top) {
                            Text("\(Int(item.value.rounded()))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 30, 65, 88, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text(score == 65 ? "Ready" : score == 88 ? "High" : "\(score)")
                            }
                        }
                    }
                }
            }

            InsightChartCard(
                title: "Pressure timeline",
                subtitle: "Each point is one completed sleep start",
                isEmpty: snapshot.sleepPressureBeforeSleep.isEmpty,
                emptyMessage: "Pressure history appears for child profiles over 4 months after enough completed sleep logs."
            ) {
                Chart {
                    RuleMark(y: .value("Ready", 65))
                        .foregroundStyle(Color.green.opacity(0.30))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("High", 88))
                        .foregroundStyle(Color.orange.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(snapshot.sleepPressureBeforeSleep) { point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Pressure", point.score)
                        )
                        .symbolSize(point.band == .high ? 78 : 54)
                        .foregroundStyle(by: .value("Band", point.band.displayName))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 30, 65, 88, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text(score == 65 ? "Ready" : score == 88 ? "High" : "\(score)")
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(pressureBandStyleScale)
                .chartLegend(position: .bottom, spacing: 8)
            }

            InsightChartCard(
                title: "Wake-window trend",
                subtitle: "Each line follows one nap index",
                isEmpty: snapshot.wakeWindows.isEmpty
            ) {
                Chart(snapshot.wakeWindows) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", point.minutes),
                        series: .value("Nap", point.label)
                    )
                    .foregroundStyle(by: .value("Nap", point.label))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(by: .value("Nap", point.label))
                }
                .chartLegend(position: .bottom, spacing: 8)
            }

            InsightChartCard(
                title: "Wake-window consistency",
                subtitle: "Standard deviation in minutes; lower is steadier",
                isEmpty: snapshot.wakeVariability.isEmpty
            ) {
                Chart(snapshot.wakeVariability) { item in
                    BarMark(
                        x: .value("Nap", item.category),
                        y: .value("Variation", item.value)
                    )
                    .foregroundStyle(.indigo.gradient)
                    .cornerRadius(5)
                }
            }
        }
    }

    private var pressureBandStyleScale: KeyValuePairs<String, Color> {
        [
            SleepPressureBand.low.displayName: Color.cyan,
            SleepPressureBand.building.displayName: Color.teal,
            SleepPressureBand.ready.displayName: Color.green,
            SleepPressureBand.high.displayName: Color.orange
        ]
    }

    private func pressureColor(for score: Double) -> Color {
        switch score {
        case 88...: .orange
        case 65..<88: .green
        case 30..<65: .teal
        default: .cyan
        }
    }
}
