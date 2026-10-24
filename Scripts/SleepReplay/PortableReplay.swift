// Standalone research executable; not part of the app target.
import Foundation

@main
struct PortableReplay {
    struct Fallback: Decodable { var index: Int; var minutes: Double }
    struct Input: Decodable {
        var birth: Double
        var zone: String
        var sleeps: [PortableSleepObservation]
        var care: [PortableFeedObservation]
        var fallback: [Fallback]
        var trees: Int
        var minimumLeaf: Int
        var refitEvery: Int
    }
    struct Output: Encodable {
        var indices: [Int]
        var names: [String]
        var features: [[Double?]]
        var targets: [Double]
        var predictions: [Double]
        var trainingMilliseconds: [Double]
        var prefixChecks: Int
        var maximumPrefixFeatureDifference: Double
    }
    enum CheckError: Error { case invalidTimeZone, missingFallback, prefixChanged }

    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard let zone = TimeZone(identifier: input.zone) else { throw CheckError.invalidTimeZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let rows = PortableSleepFeatures.rows(sleeps: input.sleeps, feeds: input.care, birth: input.birth, calendar: calendar)
            .filter { $0.target != nil }
        let fallback = Dictionary(uniqueKeysWithValues: input.fallback.map { ($0.index, $0.minutes) })
        var forest = PortableSleepForest(trees: input.trees, minimumLeaf: input.minimumLeaf)
        var trained = false, lastFit = -input.refitEvery
        var predictions = [Double](), elapsed = [Double]()
        for i in rows.indices {
            let now = rows[i].wake
            let known = rows[..<i].filter { $0.availableAt! <= now && $0.wake >= now - 60 * 86400 }
            if known.count >= 40 && i - lastFit >= input.refitEvery {
                let start = Date()
                try forest.fit(known.map(\.values), targets: known.map { $0.target! })
                elapsed.append(Date().timeIntervalSince(start) * 1000)
                trained = true
                lastFit = i
            }
            if trained {
                predictions.append(max(1, min(480, try forest.predict([rows[i].values])[0])))
            } else {
                guard let minutes = fallback[rows[i].index] else { throw CheckError.missingFallback }
                predictions.append(minutes)
            }
        }
        let positions = Set([0, 1, 40, rows.count / 2, rows.count - 1]).filter { rows.indices.contains($0) }.sorted()
        var maximumDifference = 0.0
        for position in positions {
            let expected = rows[position]
            let knownFeeds = input.care.filter { $0.start <= expected.wake && $0.end <= expected.wake }
            let prefix = PortableSleepFeatures.rows(sleeps: Array(input.sleeps[...expected.index]), feeds: knownFeeds,
                                                   birth: input.birth, calendar: calendar)
            guard let query = prefix.last, query.index == expected.index, query.target == nil else { throw CheckError.prefixChanged }
            for (actual, original) in zip(query.values, expected.values) {
                if actual.isNaN && original.isNaN { continue }
                guard actual.isFinite, original.isFinite else { throw CheckError.prefixChanged }
                maximumDifference = max(maximumDifference, abs(actual - original))
                guard abs(actual - original) <= 1e-9 else { throw CheckError.prefixChanged }
            }
        }
        let output = Output(indices: rows.map(\.index), names: PortableSleepFeatures.names,
                            features: rows.map { $0.values.map { $0.isFinite ? $0 : nil } },
                            targets: rows.map { $0.target! }, predictions: predictions,
                            trainingMilliseconds: elapsed, prefixChecks: positions.count,
                            maximumPrefixFeatureDifference: maximumDifference)
        try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
