import Foundation

@main
enum ReferenceForestReplay {
    struct Input: Decodable {
        var x: [[Double?]]
        var y: [Double]
        var query: [[Double?]]
        var trees: Int
    }
    struct Output: Encodable {
        var trees: [[ReferenceSleepForest.Node]]
        var leaves: [[Int]]
        var predictions: [Double]
        var seeds: [UInt32]
    }
    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard input.trees > 0 else { throw ReferenceSleepForest.InputError.invalidInput }
        var model = ReferenceSleepForest(trees: input.trees)
        try model.fit(input.x.map { $0.map { $0 ?? .nan } }, targets: input.y)
        let query = input.query.map { $0.map { $0 ?? .nan } }
        var random = ReferenceSleepForest.MT19937(seed: 42)
        let seeds = (0..<input.trees).map { _ in random.seed31() }
        let output = Output(trees: model.trees, leaves: try query.map { try model.leaves($0) },
                            predictions: try model.predict(query), seeds: seeds)
        try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
