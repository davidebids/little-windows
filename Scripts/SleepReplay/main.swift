import Foundation

struct Input: Decodable {
    struct Sleep: Decodable { var start: Double; var end: Double; var night: Bool }
    struct Care: Decodable { var start: Double; var end: Double; var nursing: Bool }
    var birth: Double
    var zone: String
    var totalSleeps: Int
    var sleeps: [Sleep]
    var care: [Care]
}
let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: input.zone)!
let profile = CareProfile(birthDate: Date(timeIntervalSince1970: input.birth))
let events = input.sleeps.map {
    CareEvent(startDate: Date(timeIntervalSince1970: $0.start), endDate: Date(timeIntervalSince1970: $0.end), kind: $0.night ? .nightSleep : .nap)
}
let care = input.care.map { value -> CareEvent in
    let event = CareEvent(startDate: Date(timeIntervalSince1970: value.start), endDate: Date(timeIntervalSince1970: value.end), kind: .nap)
    event.type = value.nursing ? .nursing : .feed
    return event
}
var outcomes = [[String: Any]]()
var records = [SleepPredictionRecord]()
var skipped = [String: Int]()
for i in 0..<max(0, events.count - 1) {
    let previous = events[i], actual = events[i + 1]
    let now = previous.endDate!
    let gap = actual.startDate.timeIntervalSince(now) / 60
    guard gap > 0 else { skipped["overlapOrDuplicate", default: 0] += 1; continue }
    guard !events[...i].contains(where: { $0.endDate! > now }) else {
        skipped["overlappingActiveSleep", default: 0] += 1
        continue
    }
    // All positive transitions are scored, including overnight re-settling and long gaps.
    let history = Array(events[...i]).filter { $0.endDate! <= now } + care.filter { $0.endDate! <= now }
    let knownRecords = records.filter { $0.generatedAt <= now && ($0.actualSleepStart ?? now) <= now }
    #if !UNCOMBINED_SLEEP_REPLAY && !LEGACY_SLEEP_REPLAY
    if let snapshot = SleepLearningCoordinator.snapshot(profile: profile, events: history, now: now, calendar: calendar, settings: .default) {
        guard await SleepLearningCoordinator.warm(snapshot) != nil else { fatalError("Could not prepare the history query") }
    }
    #endif
    #if UNCOMBINED_SLEEP_REPLAY
    guard let prediction = SleepPredictionEngine.predictUncombined(profile: profile, events: history, records: knownRecords, now: now, calendar: calendar) else {
        skipped["noPrediction", default: 0] += 1
        continue
    }
    #else
    guard let prediction = SleepPredictionEngine.predict(profile: profile, events: history, records: knownRecords, now: now, calendar: calendar) else {
        skipped["noPrediction", default: 0] += 1
        continue
    }
    #endif
    let error = prediction.predictedStart.timeIntervalSince(actual.startDate) / 60
    let segment = i < input.totalSleeps * 60 / 100 ? "development" : (i < input.totalSleeps * 80 / 100 ? "validation" : "holdout")
    let hour = calendar.component(.hour, from: now)
    let context = hour < 6 || hour >= 21 ? "overnight" : "daytime"
    outcomes.append([
        "index": i, "segment": segment, "context": context,
        "actualKind": actual.sleepKind == .nap ? "nap" : "night",
        "predictedKind": prediction.predictionKind.rawValue,
        "month": calendar.component(.month, from: now),
        "wakeMinutes": gap, "error": error,
        "inside": prediction.predictedWindowStart <= actual.startDate && actual.startDate <= prediction.predictedWindowEnd,
        "halfWindow": prediction.predictedWindowEnd.timeIntervalSince(prediction.predictedStart) / 60,
        "confidence": prediction.confidence,
        "prediction": prediction.predictedStart.timeIntervalSince1970,
        "actual": actual.startDate.timeIntervalSince1970
    ])
    // The error becomes available only after that next sleep actually starts.
    records.append(SleepPredictionRecord(prediction: prediction, actual: actual, generatedAt: now))
}
func metrics(_ rows: [[String: Any]]) -> [String: Any] {
    guard !rows.isEmpty else { return ["count": 0] }
    let errors = rows.map { $0["error"] as! Double }
    let absolute = errors.map(abs).sorted()
    return [
        "count": rows.count,
        "mae": absolute.reduce(0, +) / Double(rows.count),
        "median": absolute[absolute.count / 2],
        "p90": absolute[min(absolute.count - 1, Int(Double(absolute.count) * 0.9))],
        "biasLatePositive": errors.reduce(0, +) / Double(rows.count),
        "within15": Double(absolute.filter { $0 <= 15 }.count) / Double(rows.count) * 100,
        "within30": Double(absolute.filter { $0 <= 30 }.count) / Double(rows.count) * 100,
        "windowCoverage": Double(rows.filter { $0["inside"] as! Bool }.count) / Double(rows.count) * 100,
        "meanHalfWindow": rows.map { $0["halfWindow"] as! Double }.reduce(0, +) / Double(rows.count)
    ]
}
var groups = [String: Any]()
groups["all"] = metrics(outcomes)
for key in ["segment", "context", "actualKind", "month"] {
    for value in Set(outcomes.map { String(describing: $0[key]!) }) {
        groups["\(key):\(value)"] = metrics(outcomes.filter { String(describing: $0[key]!) == value })
    }
}
for segment in ["development", "validation", "holdout"] {
    groups["\(segment):daytime"] = metrics(outcomes.filter { $0["segment"] as! String == segment && $0["context"] as! String == "daytime" })
}
#if UNCOMBINED_SLEEP_REPLAY
let algorithm = "LittleWindowsSleep-v6"
#else
let algorithm = SleepPredictionEngine.algorithmVersion
#endif
let output: [String: Any] = ["algorithm": algorithm, "metrics": groups, "skipped": skipped, "events": outcomes]
try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
