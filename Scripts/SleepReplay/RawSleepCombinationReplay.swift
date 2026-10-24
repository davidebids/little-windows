import Foundation

/// Raw value-history frontend for the research chain, outside the app target.
@main
enum RawSleepCombinationReplay {
    struct Fallback: Decodable { var index: Int; var minutes: Double }
    struct Care: Decodable {
        var start: Double
        var end: Double
        var nursing: Bool?
    }
    struct Input: Decodable {
        var birth: Double
        var zone: String
        var sleeps: [PortableSleepObservation]
        var care: [Care]
        var fallback: [Fallback]
        // A current query contains only completed sleeps through this index.
        // Its following timer start is absent, rather than a supplied label.
        var throughSleepIndex: Int?
        var boundedHistory: Bool
        var useSession: Bool?
    }
    struct SessionOutput: Encodable {
        var predictions: [Double]
        var baselineTrainingCount: Int
        var specialistTrainingCounts: [Int]
    }
    struct Output: Encodable {
        var indices: [Int]
        var wakes: [Double]
        var targets: [Double?]
        var names: [String]
        var features: [[Double?]]
        var chain: ExpertCalibrationReplay.Output
        var preparationSeconds: Double
        var sparseFallbackCount: Int
        var externalSparseFallbacks: Bool
        var session: SessionOutput?
    }
    enum InputError: Error { case invalidInput }

    static func main() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard input.birth.isFinite, let zone = TimeZone(identifier: input.zone),
              input.sleeps.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }),
              input.care.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end >= $0.start }) else {
            throw InputError.invalidInput
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let ordered = input.sleeps.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        let sleeps: [PortableSleepObservation]
        if let index = input.throughSleepIndex {
            guard ordered.indices.contains(index) else { throw InputError.invalidInput }
            sleeps = Array(ordered[...index])
        } else {
            sleeps = ordered
        }
        guard Set(input.fallback.map(\.index)).count == input.fallback.count else { throw InputError.invalidInput }
        let started = Date()
        let care = input.care.map { PortableFeedObservation(start: $0.start, end: $0.end) }
        let rows = PortableSleepFeatures.rows(sleeps: sleeps, feeds: care, birth: input.birth, calendar: calendar)
            .filter { input.throughSleepIndex != nil || $0.target != nil }
        guard let last = rows.last else { throw InputError.invalidInput }
        let cutoff = input.boundedHistory ? last.wake - 60 * 86_400 : -Double.infinity
        let sparse = rows.indices.filter { i in
            rows[i].wake >= cutoff && rows[..<i].filter {
                $0.wake >= rows[i].wake - 60 * 86_400 && ($0.availableAt.map { $0 <= rows[i].wake } ?? false)
            }.count < 40
        }.map { rows[$0].index }
        let fallback: [Int: Double]
        let externalSparseFallbacks: Bool
        #if APP_SLEEP_FALLBACKS
        guard input.fallback.isEmpty else { throw InputError.invalidInput }
        fallback = try AppSleepFallbackReplay.points(sleeps: sleeps,
            care: input.care.map { .init(start: $0.start, end: $0.end, nursing: $0.nursing ?? false) },
            birth: input.birth, calendar: calendar, requested: Set(sparse))
        externalSparseFallbacks = false
        #else
        fallback = Dictionary(uniqueKeysWithValues: input.fallback.map { ($0.index, $0.minutes) })
        externalSparseFallbacks = true
        #endif
        let fields = PortableSleepFeatures.names
        let duration = fields.firstIndex(of: "lastDuration")!
        let night = fields.firstIndex(of: "lastNight")!
        let naps = fields.firstIndex(of: "napsToday")!
        let frames = rows.map { row -> ExpertCalibrationReplay.Row in
            let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: row.wake))
            let clock = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            return ExpertCalibrationReplay.Row(context: .init(wake: row.wake, clockMinute: clock,
                sleepMinutes: row.values[duration]), values: row.values.map { $0.isFinite ? $0 : nil },
                lastNight: row.values[night] > 0.5, napsToday: row.values[naps],
                availableAt: row.availableAt, actual: row.target, baseline: fallback[row.index])
        }
        let chain = try ExpertCalibrationReplay.run(.init(rows: frames, revealOnlyWhenAvailable: true,
            referenceForest: true, retainRawFromWake: input.boundedHistory ? cutoff : nil,
            fitBaseline: true))
        var sessionOutput: SessionOutput?
        if input.useSession ?? false {
            var session = PersonalizedSleepSession()
            var points = [Double]()
            for i in frames.indices {
                let row = frames[i]
                if i > 0, let available = frames[i - 1].availableAt, let actual = frames[i - 1].actual {
                    try session.resolve(wake: frames[i - 1].context.wake, availableAt: available, actual: actual)
                }
                // No current target enters the production session. Resolve its
                // issued forecast only on the next wake, then advance it.
                let frame = PersonalizedSleepSession.Frame(context: row.context, values: row.values.map { $0 ?? .nan },
                    lastNight: row.lastNight, napsToday: row.napsToday, actual: nil, availableAt: nil)
                points.append(try session.forecast(frame, fallback: row.baseline,
                    evaluate: row.context.wake >= cutoff).minutes)
            }
            sessionOutput = SessionOutput(predictions: points, baselineTrainingCount: session.baselineTrainingCount,
                specialistTrainingCounts: session.specialistTrainingCounts)
        }
        let output = Output(indices: rows.map(\.index), wakes: rows.map(\.wake), targets: rows.map(\.target),
            names: fields, features: frames.map(\.values), chain: chain,
            preparationSeconds: Date().timeIntervalSince(started), sparseFallbackCount: sparse.count,
            externalSparseFallbacks: externalSparseFallbacks, session: sessionOutput)
        try JSONEncoder().encode(output).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
