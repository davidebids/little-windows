import Foundation

struct PredictionAccuracy: Hashable {
    var sampleCount: Int
    var meanAbsoluteErrorMinutes: Double?
    var insideWindowPercentage: Double?
    var averageBiasMinutes: Double?
}

struct AccuracyBreakdown: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var accuracy: PredictionAccuracy
}

enum PredictionTuningService {
    static func resolveLatestPrediction(
        with sleepEvent: BabyEvent,
        records: [SleepPredictionRecord]
    ) {
        guard sleepEvent.type == .sleep else { return }
        let linkedRecord = records.first { $0.actualSleepEventID == sleepEvent.id }
        let candidate = linkedRecord ?? records
            .filter {
                $0.actualSleepEventID == nil &&
                $0.generatedAt <= sleepEvent.startDate &&
                sleepEvent.startDate.timeIntervalSince($0.generatedAt) <= 18 * 60 * 60
            }
            .max { $0.generatedAt < $1.generatedAt }
        guard let candidate else { return }
        candidate.actualSleepEventID = sleepEvent.id
        candidate.actualSleepStart = sleepEvent.startDate
        candidate.errorMinutes = sleepEvent.startDate.timeIntervalSince(candidate.predictedStart) / 60
        candidate.wasInsidePredictedWindow = (
            candidate.predictedWindowStart...candidate.predictedWindowEnd
        ).contains(sleepEvent.startDate)
        candidate.updatedAt = Date()
    }

    static func accuracy(
        records: [SleepPredictionRecord],
        last count: Int? = nil
    ) -> PredictionAccuracy {
        let resolved = records
            .filter { $0.errorMinutes != nil }
            .sorted { $0.generatedAt > $1.generatedAt }
        let selected = count.map { Array(resolved.prefix($0)) } ?? resolved
        guard !selected.isEmpty else {
            return PredictionAccuracy(
                sampleCount: 0,
                meanAbsoluteErrorMinutes: nil,
                insideWindowPercentage: nil,
                averageBiasMinutes: nil
            )
        }
        let errors = selected.compactMap(\.errorMinutes)
        let insideCount = selected.filter { $0.wasInsidePredictedWindow == true }.count
        return PredictionAccuracy(
            sampleCount: errors.count,
            meanAbsoluteErrorMinutes: errors.map(abs).reduce(0, +) / Double(errors.count),
            insideWindowPercentage: Double(insideCount) / Double(selected.count) * 100,
            averageBiasMinutes: errors.reduce(0, +) / Double(errors.count)
        )
    }

    static func accuracyByNapIndex(records: [SleepPredictionRecord]) -> [AccuracyBreakdown] {
        Dictionary(grouping: records.filter { $0.errorMinutes != nil }, by: \.napIndex)
            .map { index, values in
                AccuracyBreakdown(label: index == 5 ? "Bedtime" : "Nap \(index)", accuracy: accuracy(records: values))
            }
            .sorted { $0.label < $1.label }
    }

    static func accuracyByConfidence(records: [SleepPredictionRecord]) -> [AccuracyBreakdown] {
        Dictionary(grouping: records.filter { $0.errorMinutes != nil }, by: \.confidenceLabelRawValue)
            .map { label, values in
                AccuracyBreakdown(label: label.capitalized, accuracy: accuracy(records: values))
            }
            .sorted { $0.label < $1.label }
    }

    static func conservativeBiasCorrection(
        records: [SleepPredictionRecord],
        napIndex: Int
    ) -> Double {
        let matching = records
            .filter { $0.napIndex == napIndex && $0.errorMinutes != nil }
            .sorted { $0.generatedAt > $1.generatedAt }
            .prefix(10)
            .compactMap(\.errorMinutes)
        guard matching.count >= 3 else { return 0 }
        let averageBias = matching.reduce(0, +) / Double(matching.count)
        return min(12, max(-12, averageBias * 0.25))
    }
}
