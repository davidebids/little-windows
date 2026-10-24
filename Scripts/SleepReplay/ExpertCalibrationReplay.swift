import Foundation

#if !RAW_SLEEP_COMBINATION_REPLAY
@main
#endif
enum ExpertCalibrationReplay {
    struct Row: Decodable {
        var context: PortableSleepCalibration.Context
        var values: [Double?]
        var lastNight: Bool
        var napsToday: Double
        var availableAt: Double?
        var actual: Double?
        var baseline: Double?
    }
    struct Input: Decodable {
        var rows: [Row]
        var revealOnlyWhenAvailable: Bool
        var referenceForest: Bool?
        var retainRawFromWake: Double?
        var fitBaseline: Bool?
    }
    struct Output: Encodable {
        var experts: [[Double]]
        var predictions: [[Double]]
        var specialistFitCounts: [Int]
        var specialistTrainingCounts: [Int]
        var baselineTrainingCount: Int
    }
    struct Pending {
        var row: Row
        var raw: [Double]
        var adjusted: [[Double]]
    }

    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let output = try run(input)
        try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }

    static func run(_ input: Input) throws -> Output {
        var specialists = PortableSleepSpecialists(reference: input.referenceForest ?? false)
        var baselineLearner = PortableSleepBaseline()
        var learners = [PortableSleepCalibration(expertCount: 4),
            PortableSleepCalibration(expertCount: 4, policy: .best),
            PortableSleepCalibration(expertCount: 4, calibrate: false),
            PortableSleepCalibration(expertCount: 4, local: false),
            PortableSleepCalibration(expertCount: 4, policy: .median)]
        var experts = [[Double]](), predictions = [[Double]](), pending = [Pending]()
        for row in input.rows {
            if input.revealOnlyWhenAvailable {
                for entry in pending where entry.row.availableAt.map({ $0 <= row.context.wake }) ?? false {
                    guard let available = entry.row.availableAt, let actual = entry.row.actual else { continue }
                    try specialists.resolve(wake: entry.row.context.wake, availableAt: available, actual: actual)
                    if input.fitBaseline ?? false {
                        try baselineLearner.resolve(wake: entry.row.context.wake, availableAt: available, actual: actual)
                    }
                    for k in learners.indices where !entry.adjusted.isEmpty {
                        try learners[k].record(context: entry.row.context, availableAt: available,
                            actual: actual, raw: entry.raw, adjusted: entry.adjusted[k])
                    }
                }
                pending.removeAll { $0.row.availableAt.map { $0 <= row.context.wake } ?? false }
            }
            let frame = PortableSleepSpecialists.Frame(context: row.context, values: row.values.map { $0 ?? .nan },
                lastNight: row.lastNight, napsToday: row.napsToday,
                actual: input.revealOnlyWhenAvailable ? nil : row.actual,
                availableAt: input.revealOnlyWhenAvailable ? nil : row.availableAt)
            let evaluate = row.context.wake >= (input.retainRawFromWake ?? -.infinity)
            let baseline: Double
            if input.fitBaseline ?? false {
                baseline = try baselineLearner.forecast(frame, fallback: row.baseline, evaluate: evaluate)
            } else {
                guard let point = row.baseline else { throw PortableSleepSpecialists.InputError.invalidInput }
                baseline = point
            }
            let raw = [baseline] + (try specialists.forecast(frame, baseline: baseline, evaluate: evaluate))
            if !evaluate {
                if input.revealOnlyWhenAvailable { pending.append(Pending(row: row, raw: raw, adjusted: [])) }
                experts.append(raw)
                predictions.append(Array(repeating: baseline, count: learners.count))
                continue
            }
            var current = [Double](), adjusted = [[Double]]()
            for k in learners.indices {
                let forecast = try learners[k].forecast(context: row.context, raw: raw)
                current.append(forecast.minutes)
                adjusted.append(forecast.adjusted)
                if !input.revealOnlyWhenAvailable, let available = row.availableAt, let actual = row.actual {
                    try learners[k].record(context: row.context, availableAt: available,
                        actual: actual, raw: raw, adjusted: forecast.adjusted)
                }
            }
            if input.revealOnlyWhenAvailable { pending.append(Pending(row: row, raw: raw, adjusted: adjusted)) }
            experts.append(raw)
            predictions.append(current)
        }
        return Output(experts: experts, predictions: predictions, specialistFitCounts: specialists.fitCounts,
            specialistTrainingCounts: specialists.trainingCounts, baselineTrainingCount: baselineLearner.trainingCount)
    }
}
