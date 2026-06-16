import SwiftUI

struct PredictionExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let prediction: SleepPrediction?

    var body: some View {
        List {
            if let prediction {
                Section("Prediction") {
                    LabeledContent("Likely time", value: DateFormatting.time.string(from: prediction.predictedStart))
                    LabeledContent(
                        "Window",
                        value: DateFormatting.window(
                            start: prediction.predictedWindowStart,
                            end: prediction.predictedWindowEnd
                        )
                    )
                    LabeledContent(
                        "Confidence",
                        value: "\(prediction.confidenceLabel.displayName) - \(Int(prediction.confidence * 100))%"
                    )
                }
                Section("Why") {
                    ForEach(Array(prediction.explanation.enumerated()), id: \.offset) { _, explanation in
                        Text(explanation)
                    }
                }
                if !prediction.contributingFactors.isEmpty {
                    Section("Contributing factors") {
                        ForEach(prediction.contributingFactors) { factor in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(factor.name).font(.headline)
                                    Spacer()
                                    if abs(factor.impactMinutes) >= 1 {
                                        Text("\(factor.impactMinutes > 0 ? "+" : "")\(Int(factor.impactMinutes.rounded()))m")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(factor.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No prediction yet",
                    systemImage: "moon.zzz",
                    description: Text("A completed sleep event is needed first.")
                )
            }
        }
        .navigationTitle("Prediction details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
