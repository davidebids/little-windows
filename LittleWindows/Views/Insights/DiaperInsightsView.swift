import Charts
import SwiftUI

struct DiaperInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.diaperMetrics)
            InsightObservationsCard(trends: snapshot.diaperTrends)

            InsightChartCard(
                title: "Diaper counts by day",
                subtitle: "Pee-only, poo-only, and mixed",
                isEmpty: snapshot.dailyDiapers.allSatisfy { $0.total == 0 }
            ) {
                Chart(snapshot.dailyDiapers) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Count", point.wet)
                    )
                    .foregroundStyle(by: .value("Type", "Pee"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Count", point.dirty)
                    )
                    .foregroundStyle(by: .value("Type", "Poo"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Count", point.both)
                    )
                    .foregroundStyle(by: .value("Type", "Mixed"))
                }
                .chartForegroundStyleScale([
                    "Pee": Color.cyan,
                    "Poo": Color.orange,
                    "Mixed": Color.teal
                ])
            }

            InsightChartCard(
                title: "Diaper type share",
                subtitle: "Mix across the selected period",
                isEmpty: snapshot.diaperTypeShare.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.diaperTypeShare) { item in
                    SectorMark(
                        angle: .value("Count", item.value),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Type", item.category))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale([
                    "Pee only": Color.cyan,
                    "Poo only": Color.orange,
                    "Mixed": Color.teal
                ])
            }

            InsightChartCard(
                title: "Diapers by time of day",
                subtitle: "Logged changes in four time blocks",
                isEmpty: snapshot.diaperHourBuckets.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.diaperHourBuckets) { item in
                    BarMark(
                        x: .value("Time", item.category),
                        y: .value("Changes", item.value)
                    )
                    .foregroundStyle(.teal.gradient)
                    .cornerRadius(5)
                }
            }

            if snapshot.pooColorShare.reduce(0, { $0 + $1.value }) >= 2 {
                distributionChart(title: "Poo color details", values: snapshot.pooColorShare)
            }
            if snapshot.peeAmountShare.reduce(0, { $0 + $1.value }) >= 2 {
                distributionChart(title: "Pee amount details", values: snapshot.peeAmountShare)
            }
            if snapshot.pooAmountShare.reduce(0, { $0 + $1.value }) >= 2 {
                distributionChart(title: "Poo amount details", values: snapshot.pooAmountShare)
            }
        }
    }

    private func distributionChart(title: String, values: [CategoryValue]) -> some View {
        InsightChartCard(
            title: title,
            subtitle: "Optional details from logged changes",
            isEmpty: values.isEmpty
        ) {
            Chart(values) { item in
                BarMark(
                    x: .value("Detail", item.category),
                    y: .value("Count", item.value)
                )
                .foregroundStyle(.teal.gradient)
                .cornerRadius(4)
            }
        }
    }
}
