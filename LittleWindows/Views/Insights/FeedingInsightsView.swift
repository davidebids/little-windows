import Charts
import SwiftUI

struct FeedingInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.feedingMetrics)
            InsightObservationsCard(trends: snapshot.feedingTrends)

            InsightChartCard(
                title: "Bottle ounces per day",
                subtitle: "Logged bottle volume",
                isEmpty: snapshot.dailyFeeding.allSatisfy { $0.bottleOunces == 0 }
            ) {
                Chart(snapshot.dailyFeeding) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Ounces", point.bottleOunces)
                    )
                    .foregroundStyle(.orange.gradient)
                    .cornerRadius(4)
                }
            }

            InsightChartCard(
                title: "Care sessions per day",
                subtitle: "Feed and grouped nursing sessions",
                isEmpty: snapshot.dailyFeeding.allSatisfy { $0.careSessions == 0 }
            ) {
                Chart(snapshot.dailyFeeding) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Sessions", point.careSessions)
                    )
                    .foregroundStyle(.pink.gradient)
                    .cornerRadius(4)
                }
            }

            InsightChartCard(
                title: "Nursing Left vs Right",
                subtitle: "Total minutes by side",
                isEmpty: snapshot.nursingSideMinutes.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.nursingSideMinutes) { item in
                    BarMark(
                        x: .value("Side", item.category),
                        y: .value("Minutes", item.value)
                    )
                    .foregroundStyle(by: .value("Side", item.category))
                    .cornerRadius(6)
                }
                .chartForegroundStyleScale(["Left": Color.pink, "Right": Color.purple])
            }

            InsightChartCard(
                title: "Care-to-sleep interval",
                subtitle: "How soon sleep began after care",
                isEmpty: snapshot.feedToSleepBuckets.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.feedToSleepBuckets) { item in
                    BarMark(
                        x: .value("Interval", item.category),
                        y: .value("Sleeps", item.value)
                    )
                    .foregroundStyle(.indigo.gradient)
                    .cornerRadius(5)
                }
            }

            InsightChartCard(
                title: "Care by time of day",
                subtitle: "Grouped feed and nursing sessions",
                isEmpty: snapshot.feedingHourBuckets.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.feedingHourBuckets) { item in
                    BarMark(
                        x: .value("Time", item.category),
                        y: .value("Sessions", item.value)
                    )
                    .foregroundStyle(.teal.gradient)
                    .cornerRadius(5)
                }
            }
        }
    }
}
