import Charts
import SwiftUI

struct SleepInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            sleepScoreSection
            InsightMetricGrid(metrics: snapshot.sleepMetrics)
            InsightObservationsCard(trends: snapshot.sleepTrends)

            InsightChartCard(
                title: "Sleep score trend",
                subtitle: "Night sleep only, scored 0-100",
                isEmpty: snapshot.sleepScores.isEmpty
            ) {
                Chart(snapshot.sleepScores) { score in
                    AreaMark(
                        x: .value("Night", score.date, unit: .day),
                        y: .value("Score", score.score)
                    )
                    .foregroundStyle(.indigo.opacity(0.12))
                    LineMark(
                        x: .value("Night", score.date, unit: .day),
                        y: .value("Score", score.score)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.indigo)
                    PointMark(
                        x: .value("Night", score.date, unit: .day),
                        y: .value("Score", score.score)
                    )
                    .foregroundStyle(scoreColor(score.score))
                }
                .chartYScale(domain: 0...100)
            }

            InsightChartCard(
                title: "Total sleep trend",
                subtitle: "Daily total in hours",
                isEmpty: snapshot.dailySleep.allSatisfy { $0.totalMinutes == 0 }
            ) {
                Chart(snapshot.dailySleep) { point in
                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Hours", point.totalMinutes / 60)
                    )
                    .foregroundStyle(.indigo.opacity(0.15))
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Hours", point.totalMinutes / 60)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.indigo)
                }
            }

            InsightChartCard(
                title: "Day vs night sleep",
                subtitle: "Stacked hours by sleep type",
                isEmpty: snapshot.dailySleep.allSatisfy { $0.totalMinutes == 0 }
            ) {
                Chart(snapshot.dailySleep) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Hours", point.daytimeMinutes / 60)
                    )
                    .foregroundStyle(by: .value("Type", "Day"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Hours", point.nightMinutes / 60)
                    )
                    .foregroundStyle(by: .value("Type", "Night"))
                }
                .chartForegroundStyleScale(["Day": Color.orange, "Night": Color.indigo])
            }

            InsightChartCard(
                title: "Nap duration distribution",
                subtitle: "Number of naps in each duration bucket",
                isEmpty: snapshot.napDurationBuckets.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.napDurationBuckets) { item in
                    BarMark(
                        x: .value("Duration", item.category),
                        y: .value("Naps", item.value)
                    )
                    .foregroundStyle(.purple.gradient)
                    .cornerRadius(5)
                }
            }

            InsightChartCard(
                title: "Bedtime trend",
                subtitle: "Evening night-sleep onset",
                isEmpty: snapshot.bedtimes.isEmpty
            ) {
                Chart(snapshot.bedtimes) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Time", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.indigo)
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Time", point.value)
                    )
                    .foregroundStyle(.indigo)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(InsightsChartFormatting.clock(minutes: minutes))
                            }
                        }
                    }
                }
            }

            InsightChartCard(
                title: "Morning wake trend",
                subtitle: "Final overnight wake by day",
                isEmpty: snapshot.morningWakes.isEmpty
            ) {
                Chart(snapshot.morningWakes) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Time", point.value)
                    )
                    .foregroundStyle(.orange)
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Time", point.value)
                    )
                    .foregroundStyle(.orange)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(InsightsChartFormatting.clock(minutes: minutes))
                            }
                        }
                    }
                }
            }

            dailySleepBlocks
        }
    }

    private var sleepScoreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let latest = snapshot.sleepScores.last {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(scoreColor(latest.score).opacity(0.14))
                                .frame(width: 84, height: 84)
                            Circle()
                                .stroke(scoreColor(latest.score).opacity(0.24), lineWidth: 8)
                                .frame(width: 84, height: 84)
                            Text("\(latest.score)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor(latest.score))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Latest sleep score")
                                .font(.headline)
                            Text(latest.label)
                                .font(.title3.bold())
                            Text("\(DateFormatting.day.string(from: latest.date)) night · \(DateFormatting.window(start: latest.firstSleepStart, end: latest.finalWake))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("A log-based score for night sleep only, not a medical rating.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        SleepScoreMetricCell(
                            title: "Slept",
                            value: duration(latest.totalSleepMinutes),
                            icon: "moon.zzz.fill",
                            color: .indigo
                        )
                        SleepScoreMetricCell(
                            title: "Wakes",
                            value: "\(latest.wakeEventCount)",
                            icon: "bell.fill",
                            color: .orange
                        )
                        SleepScoreMetricCell(
                            title: "Awake",
                            value: duration(latest.totalWakeMinutes),
                            icon: "eye.fill",
                            color: .pink
                        )
                        SleepScoreMetricCell(
                            title: "Longest stretch",
                            value: duration(latest.longestStretchMinutes),
                            icon: "arrow.left.and.right",
                            color: .blue
                        )
                    }

                    if !latest.wakeDurationsMinutes.isEmpty {
                        Text("Wake lengths: \(latest.wakeDurationsMinutes.map(duration).joined(separator: ", "))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Sleep score", systemImage: "moon.stars.circle.fill")
                        .font(.headline)
                    Text("Log completed night sleep to see an overnight score.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .appSurface()
    }

    private var dailySleepBlocks: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recent sleep blocks")
                    .font(.headline)
                Text("A simplified timeline of completed sleeps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshot.sleepBlocks.isEmpty {
                Text("Log completed sleep to see the daily timeline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.sleepBlocks.prefix(12))) { event in
                    HStack(spacing: 12) {
                        Image(systemName: event.sleepKind == .nap ? "sun.haze.fill" : "moon.fill")
                            .foregroundStyle(event.sleepKind == .nap ? .orange : .indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.sleepKind?.displayName ?? "Sleep")
                                .font(.subheadline.weight(.semibold))
                            Text("\(DateFormatting.day.string(from: event.startDate)) · \(DateFormatting.window(start: event.startDate, end: event.endDate ?? event.startDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(DurationFormatting.string(seconds: event.duration ?? 0))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .padding(18)
        .appSurface()
    }

    private func duration(_ minutes: Double) -> String {
        DurationFormatting.string(seconds: minutes * 60)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: .green
        case 80..<90: .teal
        case 65..<80: .orange
        default: .pink
        }
    }
}

private struct SleepScoreMetricCell: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}
