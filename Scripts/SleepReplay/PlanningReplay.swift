import Foundation

/// Offline parity runner. Private inputs remain outside the app and repository.
@main
enum PlanningReplay {
    struct Input: Decodable {
        var x: [[Double?]]
        var y: [Double]
        var wakes: [Double]
        var knownAt: [Double]
        var eligible: [Bool]
        var fallback: [Double]
    }
    struct Output: Encodable { var predictions: [Double]; var refits: Int }
    enum InputError: Error { case invalid }
    static func run(_ input: Input) throws -> Output {
        let n = input.y.count
        guard [input.x.count, input.wakes.count, input.knownAt.count,
               input.eligible.count, input.fallback.count].allSatisfy({ $0 == n }),
              input.y.allSatisfy({ $0.isFinite && $0 > 0 }),
              input.fallback.allSatisfy({ $0.isFinite && $0 > 0 }),
              input.wakes.allSatisfy(\.isFinite), input.knownAt.allSatisfy(\.isFinite),
              zip(input.wakes, input.wakes.dropFirst()).allSatisfy({ $0 < $1 }) else { throw InputError.invalid }
        let x = input.x.map { $0.map { $0 ?? .nan } }
        var predictions = input.fallback
        var model: ReferenceSleepForest?
        var fitted = -24, refits = 0
        for i in 0..<n {
            let now = input.wakes[i]
            let training = (0..<i).filter {
                input.eligible[$0] && input.knownAt[$0] <= now &&
                input.wakes[$0] >= now - 60 * 86_400
            }
            if training.count >= 40, i - fitted >= 24 {
                var next = ReferenceSleepForest(trees: 80)
                try next.fit(training.map { x[$0] }, targets: training.map { input.y[$0] })
                model = next; fitted = i; refits += 1
            }
            if let model { predictions[i] = min(480, max(1, try model.predict([x[i]])[0])) }
        }
        return Output(predictions: predictions, refits: refits)
    }
    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        try JSONEncoder().encode(run(input)).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
