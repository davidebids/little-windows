import Foundation

struct DailySummary {
    var totalSleep: TimeInterval = 0
    var daytimeSleep: TimeInterval = 0
    var nightSleep: TimeInterval = 0
    var napCount: Int = 0
    var averageNap: TimeInterval = 0
    var feedCount: Int = 0
    var bottleFeedCount: Int = 0
    var solidFeedCount: Int = 0
    var solidAllergenExposures: Int = 0
    var solidSensitivityObservations: Int = 0
    var bottleOunces: Double = 0
    var nursingTotal: TimeInterval = 0
    var nursingLeft: TimeInterval = 0
    var nursingRight: TimeInterval = 0
    var pumpingSessions: Int = 0
    var pumpingOunces: Double = 0
    var pumpingTotal: TimeInterval = 0
    var wetDiapers: Int = 0
    var dirtyDiapers: Int = 0
    var bothDiapers: Int = 0
    var childPottyCount: Int = 0
    var childPottyPeeCount: Int = 0
    var childPottyPooCount: Int = 0
    var childPottyAccidents: Int = 0
    var activityCount: Int = 0
    var tummyTime: TimeInterval = 0
    var readingTime: TimeInterval = 0
    var medicineNames: [String] = []
    var bathCount: Int = 0
    var growthCount: Int = 0
    var temperatureCount: Int = 0
    var customCount: Int = 0
    var dogFoodCount: Int = 0
    var waterCount: Int = 0
    var treatCount: Int = 0
    var pottyCount: Int = 0
    var pottyAccidents: Int = 0
    var walkTime: TimeInterval = 0
    var restTime: TimeInterval = 0
    var trainingTime: TimeInterval = 0
    var groomingTime: TimeInterval = 0
    var symptomCount: Int = 0
    var vaccineCount: Int = 0
    var glucoseCount: Int = 0
    var bloodPressureCount: Int = 0
    var heartRateCount: Int = 0
    var oxygenSaturationCount: Int = 0
    var respiratoryRateCount: Int = 0
    var painCount: Int = 0
}

enum DailySummaryService {
    static func summary(for events: [CareEvent]) -> DailySummary {
        var result = DailySummary()
        var napDurations = [TimeInterval]()
        for event in events {
            switch event.type {
            case .sleep:
                guard event.sleepKind != .nightWaking else { continue }
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
                if event.feedKind == .bottle {
                    result.bottleFeedCount += 1
                    result.bottleOunces += event.amountOz ?? 0
                }
                if event.feedKind == .solid {
                    result.solidFeedCount += 1
                    if event.solidAllergenExposure == true {
                        result.solidAllergenExposures += 1
                    }
                    if event.solidSensitivityObserved == true || event.solidReaction == .sensitivity {
                        result.solidSensitivityObservations += 1
                    }
                }
            case .nursing:
                result.nursingLeft += event.leftDurationSeconds ?? 0
                result.nursingRight += event.rightDurationSeconds ?? 0
                result.nursingTotal += event.totalNursingDurationSeconds > 0
                    ? event.totalNursingDurationSeconds
                    : event.duration ?? 0
            case .pumping:
                result.pumpingSessions += 1
                result.pumpingOunces += event.amountOz ?? 0
                result.pumpingTotal += event.duration ?? 0
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
                result.activityCount += 1
                switch event.activityType {
                case .tummyTime: result.tummyTime += event.duration ?? 0
                case .storyTime: result.readingTime += event.duration ?? 0
                case .bath: result.bathCount += 1
                default: break
                }
            case .food:
                result.dogFoodCount += 1
            case .water:
                result.waterCount += 1
            case .treat:
                result.treatCount += 1
            case .potty:
                result.pottyCount += 1
                let dogDetails = event.dogDetails
                let isDogPotty = event.profileTypeSnapshot == .dog
                    || dogDetails.pottyTypeRawValue != nil
                    || dogDetails.pottyLocationRawValue != nil
                    || dogDetails.accident != nil
                if !isDogPotty {
                    result.childPottyCount += 1
                    switch event.childPottyKind {
                    case .pee:
                        result.childPottyPeeCount += 1
                    case .poo:
                        result.childPottyPooCount += 1
                    case .both:
                        result.childPottyPeeCount += 1
                        result.childPottyPooCount += 1
                    case .none:
                        break
                    }
                    if event.childPottyAccident == true {
                        result.childPottyAccidents += 1
                    }
                }
                if event.dogDetails.accident == true || event.childPottyAccident == true {
                    result.pottyAccidents += 1
                }
            case .walk:
                result.walkTime += event.duration ?? 0
            case .rest:
                result.restTime += event.duration ?? 0
            case .training:
                result.trainingTime += event.duration ?? 0
            case .grooming:
                result.groomingTime += event.duration ?? 0
            case .symptom:
                result.symptomCount += 1
            case .vaccine:
                result.vaccineCount += 1
            case .glucose:
                result.glucoseCount += 1
            case .bloodPressure:
                result.bloodPressureCount += 1
            case .heartRate:
                result.heartRateCount += 1
            case .oxygenSaturation:
                result.oxygenSaturationCount += 1
            case .respiratoryRate:
                result.respiratoryRateCount += 1
            case .pain:
                result.painCount += 1
            case .growth:
                result.growthCount += 1
            case .temperature:
                result.temperatureCount += 1
            case .custom:
                result.customCount += 1
            }
        }
        if !napDurations.isEmpty {
            result.averageNap = napDurations.reduce(0, +) / Double(napDurations.count)
        }
        return result
    }
}
