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
}
