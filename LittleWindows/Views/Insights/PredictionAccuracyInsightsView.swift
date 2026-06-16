import Charts
import SwiftUI

struct PredictionAccuracyInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.predictionMetrics)
            InsightObservationsCard(trends: snapshot.predictionTrends)

            InsightChartCard(
                title: "Prediction error over time",
                subtitle: "Negative is early; positive is late",
                isEmpty: snapshot.predictionErrors.isEmpty,
                emptyMessage: "Accuracy appears after a prediction is followed by an actual sleep log."
            ) {
                Chart(snapshot.predictionErrors) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Error", point.errorMinutes)
                    )
                    .foregroundStyle(.indigo)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Error", point.errorMinutes)
                    )
                    .foregroundStyle(point.insideWindow ? .green : .orange)
                    RuleMark(y: .value("On time", 0))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }

            InsightChartCard(
                title: "Absolute error",
                subtitle: "Miss in minutes regardless of direction",
                isEmpty: snapshot.predictionErrors.isEmpty
            ) {
                Chart(snapshot.predictionErrors) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", abs(point.errorMinutes))
                    )
                    .foregroundStyle(.purple.opacity(0.15))
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Minutes", abs(point.errorMinutes))
                    )
                    .foregroundStyle(.purple)
                }
            }

            InsightChartCard(
                title: "Accuracy by nap index",
                subtitle: "Mean absolute error; lower is better",
                isEmpty: snapshot.predictionByNap.isEmpty
            ) {
                Chart(snapshot.predictionByNap) { item in
                    BarMark(
                        x: .value("Nap", item.category),
                        y: .value("Minutes", item.value)
                    )
                    .foregroundStyle(.orange.gradient)
                    .cornerRadius(5)
                }
            }

            InsightChartCard(
                title: "Accuracy by confidence",
                subtitle: "Percent inside the predicted window",
                isEmpty: snapshot.predictionByConfidence.isEmpty
            ) {
                Chart(snapshot.predictionByConfidence) { item in
                    BarMark(
                        x: .value("Confidence", item.category),
                        y: .value("Inside", item.value)
                    )
                    .foregroundStyle(.teal.gradient)
                    .cornerRadius(5)
                }
                .chartYScale(domain: 0...100)
            }

            pairedStarts
        }
    }

    private var pairedStarts: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Predicted vs actual")
                    .font(.headline)
                Text("Most recently evaluated sleep starts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshot.predictionErrors.isEmpty {
                Text("No resolved predictions in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.predictionErrors.suffix(8).reversed())) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(InsightsChartFormatting.napLabel(item.napIndex))
                                .font(.subheadline.weight(.semibold))
                            Text(DateFormatting.day.string(from: item.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(DateFormatting.time.string(from: item.predictedStart)) → \(DateFormatting.time.string(from: item.actualStart))")
                                .font(.subheadline.monospacedDigit())
                            Text("\(item.errorMinutes >= 0 ? "+" : "")\(Int(item.errorMinutes.rounded())) min")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.insideWindow ? .green : .orange)
                        }
                    }
                }
            }
        }
        .padding(18)
        .appSurface()
    }
}
