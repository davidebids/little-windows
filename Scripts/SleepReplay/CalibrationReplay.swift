import Foundation

@main
enum CalibrationReplay {
    struct Row: Codable {
        var context: PortableSleepCalibration.Context
        var availableAt: Double
        var actual: Double
        var raw: [Double]
    }
    struct Input: Codable {
        var rows: [Row]
        var policy: String
        var calibrate: Bool
        var local: Bool
    }
    struct Output: Codable {
        var predictions: [Double]
    }
    enum InputError: Error { case invalidInput }

    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard let policy = PortableSleepCalibration.Policy(rawValue: input.policy),
              let first = input.rows.first, !first.raw.isEmpty,
              zip(input.rows, input.rows.dropFirst()).allSatisfy({ $0.context.wake < $1.context.wake }) else { throw InputError.invalidInput }
        var learner = PortableSleepCalibration(expertCount: first.raw.count, policy: policy,
            calibrate: input.calibrate, local: input.local)
        var predictions = [Double]()
        for row in input.rows {
            let forecast = try learner.forecast(context: row.context, raw: row.raw)
            predictions.append(forecast.minutes)
            try learner.record(context: row.context, availableAt: row.availableAt, actual: row.actual,
                raw: row.raw, adjusted: forecast.adjusted)
        }
        try JSONEncoder().encode(Output(predictions: predictions)).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
