#if APP_SLEEP_FALLBACKS
import Foundation

/// Replays the actual uncombined app rules only through the last sparse query.
/// Its records describe virtual v6 forecasts, never later combined forecasts.
/// Storage-free adapters keep this research path independent of app storage.
enum AppSleepFallbackReplay {
    struct Care {
        var start: Double
        var end: Double
        var nursing: Bool
    }
    enum ReplayError: Error { case missingPrediction }

    static func points(sleeps: [PortableSleepObservation], care: [Care], birth: Double,
                       calendar: Calendar, requested: Set<Int>) throws -> [Int: Double] {
        guard let lastRequested = requested.max() else { return [:] }
        let profile = CareProfile(birthDate: Date(timeIntervalSince1970: birth))
        let events = sleeps.map {
            CareEvent(startDate: Date(timeIntervalSince1970: $0.start), endDate: Date(timeIntervalSince1970: $0.end),
                kind: $0.night ? .nightSleep : .nap)
        }
        let feeds = care.map { row -> CareEvent in
            let event = CareEvent(startDate: Date(timeIntervalSince1970: row.start),
                endDate: Date(timeIntervalSince1970: row.end), kind: .nap)
            event.type = row.nursing ? .nursing : .feed
            return event
        }
        var records = [SleepPredictionRecord](), points = [Int: Double]()
        var maximumEnd = -Double.infinity
        for i in events.indices where i <= lastRequested {
            let wake = sleeps[i].end
            maximumEnd = max(maximumEnd, wake)
            guard maximumEnd <= wake,
                  i + 1 >= sleeps.count || sleeps[i + 1].start > wake else { continue }
            let now = Date(timeIntervalSince1970: wake)
            let history = Array(events[...i]).filter { $0.endDate! <= now } + feeds.filter { $0.endDate! <= now }
            let known = records.filter { $0.generatedAt <= now && ($0.actualSleepStart ?? now) <= now }
            guard let prediction = SleepPredictionEngine.predictUncombined(profile: profile, events: history,
                records: known, now: now, calendar: calendar) else { throw ReplayError.missingPrediction }
            if requested.contains(i) { points[i] = prediction.predictedStart.timeIntervalSince(now) / 60 }
            if i + 1 < events.count {
                records.append(SleepPredictionRecord(prediction: prediction, actual: events[i + 1], generatedAt: now))
            }
        }
        guard Set(points.keys) == requested else { throw ReplayError.missingPrediction }
        return points
    }
}
#endif
