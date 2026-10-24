import Foundation

/// Private feature matrices are supplied externally and never bundled.
@main
enum RegimeReplay {
    struct Input: Decodable {
        var x: [[Double?]]
        var y: [Double]
        var wakes: [Double]
        var available: [Double]
        var groups: [Int]
        var fallback: [Double]
        var lookbackDays: Double
        var refitEvery: Int
    }

    struct Output: Encodable {
        var predictions: [Double]
        var trainingCounts: [Int]
    }

    enum InputError: Error { case invalid }

    static func run(_ input: Input) throws -> Output {
        let n = input.y.count
        guard input.lookbackDays > 0, input.refitEvery > 0,
              [input.x.count, input.wakes.count, input.available.count, input.groups.count,
               input.fallback.count].allSatisfy({ $0 == n }),
              zip(input.wakes, input.wakes.dropFirst()).allSatisfy({ $0 <= $1 }),
              input.y.allSatisfy(\.isFinite), input.fallback.allSatisfy(\.isFinite) else { throw InputError.invalid }
        let x = input.x.map { $0.map { $0 ?? .nan } }
        var predictions = input.fallback
        var counts = Array(repeating: 0, count: n)
        var models = [Int: PortableSleepForest](), fittedAt = [Int: Int]()
        for i in 0..<n {
            let now = input.wakes[i], group = input.groups[i]
            let training = (0..<i).filter {
                input.available[$0] <= now && input.wakes[$0] >= now - input.lookbackDays * 86_400 &&
                input.groups[$0] == group
            }
            if training.count >= 40, i - (fittedAt[group] ?? -input.refitEvery) >= input.refitEvery {
                var forest = PortableSleepForest(trees: 80, minimumLeaf: 5)
                try forest.fit(training.map { x[$0] }, targets: training.map { input.y[$0] })
                models[group] = forest
                fittedAt[group] = i
                counts[i] = training.count
            }
            if let model = models[group] { predictions[i] = try model.predict([x[i]])[0] }
        }
        return Output(predictions: predictions, trainingCounts: counts)
    }

    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let output = try run(input)
        try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
