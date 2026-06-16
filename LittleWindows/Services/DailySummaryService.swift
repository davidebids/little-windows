import Foundation

struct DailySummary {
    var totalSleep: TimeInterval = 0
    var daytimeSleep: TimeInterval = 0
    var nightSleep: TimeInterval = 0
    var napCount: Int = 0
    var averageNap: TimeInterval = 0
    var feedCount: Int = 0
    var bottleOunces: Double = 0
    var nursingTotal: TimeInterval = 0
    var nursingLeft: TimeInterval = 0
    var nursingRight: TimeInterval = 0
    var wetDiapers: Int = 0
    var dirtyDiapers: Int = 0
    var bothDiapers: Int = 0
    var tummyTime: TimeInterval = 0
    var readingTime: TimeInterval = 0
    var medicineNames: [String] = []
    var bathCount: Int = 0
}

enum DailySummaryService {
    static func summary(for events: [BabyEvent]) -> DailySummary {
        var result = DailySummary()
        var napDurations = [TimeInterval]()
        for event in events {
            switch event.type {
            case .sleep:
                let duration = event.duration ?? 0
                result.totalSleep += duration
                if event.sleepKind == .nap {
                    result.daytimeSleep += duration
                    result.napCount += 1
                    napDurations.append(duration)
                } else {
                    result.nightSleep += duration
                }
            case .feed:
                result.feedCount += 1
                if event.feedKind == .bottle { result.bottleOunces += event.amountOz ?? 0 }
            case .nursing:
                result.nursingLeft += event.leftDurationSeconds ?? 0
                result.nursingRight += event.rightDurationSeconds ?? 0
                result.nursingTotal += event.totalNursingDurationSeconds > 0
                    ? event.totalNursingDurationSeconds
                    : event.duration ?? 0
            case .diaper:
                switch event.diaperKind {
                case .wet: result.wetDiapers += 1
                case .dirty: result.dirtyDiapers += 1
                case .both: result.bothDiapers += 1
                case .none: break
                }
            case .medicine:
                result.medicineNames.append(event.medicineName ?? "Medicine")
            case .activity:
                switch event.activityType {
                case .tummyTime: result.tummyTime += event.duration ?? 0
                case .storyTime: result.readingTime += event.duration ?? 0
                case .bath: result.bathCount += 1
                default: break
                }
            case .food, .water, .treat, .potty, .walk, .rest, .training, .grooming, .symptom, .vaccine, .glucose, .growth, .temperature, .custom:
                break
            }
        }
        if !napDurations.isEmpty {
            result.averageNap = napDurations.reduce(0, +) / Double(napDurations.count)
        }
        return result
    }
}
