import Foundation
import SwiftData

@Model
final class SleepPredictionRecord {
    var id: UUID = UUID()
    var profileID: UUID?
    var generatedAt: Date = Date()
    var basedOnLastSleepEventID: UUID?
    var predictedStart: Date = Date()
    var predictedWindowStart: Date = Date()
    var predictedWindowEnd: Date = Date()
    var predictionKindRawValue: String = PredictionKind.nap.rawValue
    var confidence: Double = 0
    var confidenceLabelRawValue: String = ConfidenceLabel.low.rawValue
    var explanationSnapshot: String = ""
    var factorsData: Data?
    var napIndex: Int = 1
    var algorithmVersion: String = SleepPredictionEngine.algorithmVersion
    var actualSleepEventID: UUID?
    var actualSleepStart: Date?
    var errorMinutes: Double?
    var wasInsidePredictedWindow: Bool?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        prediction: SleepPrediction,
        basedOnLastSleepEventID: UUID?,
        profileID: UUID? = nil,
        settings: PredictionSettings = .default
    ) {
        id = UUID()
        self.profileID = profileID
        generatedAt = Date()
        self.basedOnLastSleepEventID = basedOnLastSleepEventID
        predictedStart = prediction.predictedStart
        predictedWindowStart = prediction.predictedWindowStart
        predictedWindowEnd = prediction.predictedWindowEnd
        predictionKindRawValue = prediction.predictionKind.rawValue
        confidence = prediction.confidence
        confidenceLabelRawValue = prediction.confidenceLabel.rawValue
        explanationSnapshot = prediction.explanation.joined(separator: "\n")
        factorsData = try? JSONEncoder().encode(prediction.contributingFactors)
        napIndex = prediction.napIndex
        algorithmVersion = SleepPredictionEngine.cacheVersion(settings: settings)
        createdAt = Date()
        updatedAt = Date()
    }

    var predictionKind: PredictionKind {
        get { PredictionKind(rawValue: predictionKindRawValue) ?? .nap }
        set { predictionKindRawValue = newValue.rawValue }
    }

    var confidenceLabel: ConfidenceLabel {
        get { ConfidenceLabel(rawValue: confidenceLabelRawValue) ?? .low }
        set { confidenceLabelRawValue = newValue.rawValue }
    }

    var explanations: [String] {
        explanationSnapshot
            .split(separator: "\n")
            .map(String.init)
    }

    var factors: [PredictionFactorValue] {
        guard let factorsData else { return [] }
        return (try? JSONDecoder().decode([PredictionFactorValue].self, from: factorsData)) ?? []
    }

    var prediction: SleepPrediction {
        SleepPrediction(
            predictedStart: predictedStart,
            predictedWindowStart: predictedWindowStart,
            predictedWindowEnd: predictedWindowEnd,
            predictionKind: predictionKind,
            confidence: confidence,
            confidenceLabel: confidenceLabel,
            explanation: explanations,
            contributingFactors: factors,
            napIndex: napIndex
        )
    }
}
