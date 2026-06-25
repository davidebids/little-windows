import Foundation

struct DailySleepSummary: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var daytimeMinutes: Double
    var nightMinutes: Double
    var napCount: Int
    var averageNapMinutes: Double
    var totalMinutes: Double { daytimeMinutes + nightMinutes }
}

struct WakeWindowSummary: Identifiable, Hashable {
    var id: String { "\(date.timeIntervalSinceReferenceDate)-\(napIndex)" }
    var date: Date
    var napIndex: Int
    var minutes: Double

    var label: String { napIndex == 5 ? "Pre-bed" : "Nap \(napIndex)" }
}

struct SleepPressureSummary: Identifiable, Hashable {
    var id: String { eventID.uuidString }
    var eventID: UUID
    var date: Date
    var score: Double
    var band: SleepPressureBand
    var sleepKind: SleepKind?
    var napIndex: Int
}

struct DailyFeedingSummary: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var careSessions: Int
    var nursingSessions: Int
    var bottleOunces: Double
}

struct DailyDiaperSummary: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var wet: Int
    var dirty: Int
    var both: Int
    var total: Int { wet + dirty + both }
}

struct DailyActivitySummary: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var tummyMinutes: Double
    var readingMinutes: Double
    var indoorMinutes: Double
    var outdoorMinutes: Double
    var screenMinutes: Double
    var baths: Int
    var brushTeeth: Int
    var medicine: Int
    var custom: Int
}

struct GrowthMeasurementSummary: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var weightPounds: Double?
    var heightInches: Double?
    var headCircumferenceInches: Double?
}

struct TemperatureMeasurementSummary: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var fahrenheit: Double
    var method: String?
}

struct PredictionErrorSummary: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var errorMinutes: Double
    var napIndex: Int
    var confidence: String
    var insideWindow: Bool
    var predictedStart: Date
    var actualStart: Date
}

struct NightSleepScoreSummary: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var score: Int
    var totalSleepMinutes: Double
    var wakeEventCount: Int
    var totalWakeMinutes: Double
    var longestStretchMinutes: Double
    var sleepWindowMinutes: Double
    var firstSleepStart: Date
    var finalWake: Date
    var wakeDurationsMinutes: [Double]
    var segmentCount: Int

    var sleepEfficiencyPercent: Double {
        guard sleepWindowMinutes > 0 else { return 0 }
        return min(100, max(0, totalSleepMinutes / sleepWindowMinutes * 100))
    }

    var label: String {
        switch score {
        case 90...100: "Excellent"
        case 80..<90: "Strong"
        case 65..<80: "Mixed"
        default: "Tough"
        }
    }
}

struct CategoryValue: Identifiable, Hashable {
    var id: String { category }
    var category: String
    var value: Double
}

struct InsightsSnapshot {
    var profileName: String
    var periodStart: Date
    var periodEnd: Date
    var comparisonLabel: String?
    var overviewMetrics: [InsightMetric]
    var sleepMetrics: [InsightMetric]
    var wakeMetrics: [InsightMetric]
    var feedingMetrics: [InsightMetric]
    var diaperMetrics: [InsightMetric]
    var activityMetrics: [InsightMetric]
    var predictionMetrics: [InsightMetric]
    var overviewTrends: [InsightTrend]
    var sleepTrends: [InsightTrend]
    var wakeTrends: [InsightTrend]
    var feedingTrends: [InsightTrend]
    var diaperTrends: [InsightTrend]
    var activityTrends: [InsightTrend]
    var predictionTrends: [InsightTrend]
    var dailySleep: [DailySleepSummary]
    var wakeWindows: [WakeWindowSummary]
    var sleepPressureBeforeSleep: [SleepPressureSummary]
    var sleepPressureBandCounts: [CategoryValue]
    var sleepPressureAverages: [CategoryValue]
    var dailyFeeding: [DailyFeedingSummary]
    var dailyDiapers: [DailyDiaperSummary]
    var dailyActivities: [DailyActivitySummary]
    var predictionErrors: [PredictionErrorSummary]
    var napDurationBuckets: [CategoryValue]
    var feedToSleepBuckets: [CategoryValue]
    var feedingHourBuckets: [CategoryValue]
    var diaperHourBuckets: [CategoryValue]
    var nursingSideMinutes: [CategoryValue]
    var activityMix: [CategoryValue]
    var wakeAverages: [CategoryValue]
    var wakeVariability: [CategoryValue]
    var diaperTypeShare: [CategoryValue]
    var predictionByNap: [CategoryValue]
    var predictionByConfidence: [CategoryValue]
    var bedtimes: [ChartDataPoint]
    var morningWakes: [ChartDataPoint]
    var sleepScores: [NightSleepScoreSummary]
    var sleepBlocks: [BabyEvent]
    var medicineNames: [String]
    var growthMetrics: [InsightMetric] = []
    var temperatureMetrics: [InsightMetric] = []
    var medicineMetrics: [InsightMetric] = []
    var growthMeasurements: [GrowthMeasurementSummary] = []
    var temperatureMeasurements: [TemperatureMeasurementSummary] = []
    var medicineEvents: [BabyEvent] = []
    var pooColorShare: [CategoryValue] = []
    var peeAmountShare: [CategoryValue] = []
    var pooAmountShare: [CategoryValue] = []

    static let empty = InsightsSnapshot(
        profileName: "Baby",
        periodStart: Date(),
        periodEnd: Date(),
        comparisonLabel: nil,
        overviewMetrics: [],
        sleepMetrics: [],
        wakeMetrics: [],
        feedingMetrics: [],
        diaperMetrics: [],
        activityMetrics: [],
        predictionMetrics: [],
        overviewTrends: [],
        sleepTrends: [],
        wakeTrends: [],
        feedingTrends: [],
        diaperTrends: [],
        activityTrends: [],
        predictionTrends: [],
        dailySleep: [],
        wakeWindows: [],
        sleepPressureBeforeSleep: [],
        sleepPressureBandCounts: [],
        sleepPressureAverages: [],
        dailyFeeding: [],
        dailyDiapers: [],
        dailyActivities: [],
        predictionErrors: [],
        napDurationBuckets: [],
        feedToSleepBuckets: [],
        feedingHourBuckets: [],
        diaperHourBuckets: [],
        nursingSideMinutes: [],
        activityMix: [],
        wakeAverages: [],
        wakeVariability: [],
        diaperTypeShare: [],
        predictionByNap: [],
        predictionByConfidence: [],
        bedtimes: [],
        morningWakes: [],
        sleepScores: [],
        sleepBlocks: [],
        medicineNames: []
    )
}

enum InsightsAnalyticsService {
    static func snapshot(
        profileName: String,
        profile: BabyProfile? = nil,
        events: [BabyEvent],
        records: [SleepPredictionRecord],
        periodStart: Date,
        periodEnd: Date,
        now: Date = Date(),
        compareToPrevious: Bool = true,
        calendar: Calendar = .current
    ) -> InsightsSnapshot {
        let start = calendar.startOfDay(for: min(periodStart, periodEnd))
        let selectedEndDay = calendar.startOfDay(for: max(periodStart, periodEnd))
        let end = calendar.startOfNextDay(for: selectedEndDay)
        let days = max(
            1,
            (calendar.dateComponents([.day], from: start, to: selectedEndDay).day ?? 0) + 1
        )
        let previousStart = calendar.date(byAdding: .day, value: -days, to: start) ?? start
        let currentRange = start..<end
        let previousRange = previousStart..<start
        let completed = events.filter { $0.endDate != nil }

        let dailySleep = dailySleepTotals(events: completed, range: currentRange, calendar: calendar)
        let previousSleep = dailySleepTotals(events: completed, range: previousRange, calendar: calendar)
        let wakeWindows = wakeWindowCalculations(events: completed, range: currentRange, calendar: calendar)
        let previousWake = wakeWindowCalculations(events: completed, range: previousRange, calendar: calendar)
        let sleepPressureBeforeSleep = sleepPressureBeforeSleepCalculations(
            profile: profile,
            events: completed,
            records: records,
            range: currentRange,
            calendar: calendar
        )
        let previousSleepPressureBeforeSleep = sleepPressureBeforeSleepCalculations(
            profile: profile,
            events: completed,
            records: records,
            range: previousRange,
            calendar: calendar
        )
        let dailyFeeding = feedingAggregation(events: events, range: currentRange, calendar: calendar)
        let previousFeeding = feedingAggregation(events: events, range: previousRange, calendar: calendar)
        let dailyDiapers = diaperAggregation(events: events, range: currentRange, calendar: calendar)
        let previousDiapers = diaperAggregation(events: events, range: previousRange, calendar: calendar)
        let dailyActivities = activityAggregation(events: events, range: currentRange, calendar: calendar)
        let previousActivities = activityAggregation(events: events, range: previousRange, calendar: calendar)
        let predictionErrors = predictionAccuracy(records: records, range: currentRange)
        let previousPredictions = predictionAccuracy(records: records, range: previousRange)

        let currentNaps = completed.filter {
            $0.type == .sleep && $0.sleepKind == .nap && currentRange.contains($0.startDate)
        }
        let previousNaps = completed.filter {
            $0.type == .sleep && $0.sleepKind == .nap && previousRange.contains($0.startDate)
        }
        let bedtimes = bedtimeExtraction(events: completed, range: currentRange, calendar: calendar)
        let previousBedtimes = bedtimeExtraction(events: completed, range: previousRange, calendar: calendar)
        let morningWakes = morningWakeExtraction(events: completed, range: currentRange, calendar: calendar)
        let currentCare = careSessions(events: events, range: currentRange)
        let currentDiaperEvents = events.filter { $0.type == .diaper && currentRange.contains($0.startDate) }
        let currentActivityEvents = events.filter { currentRange.contains($0.startDate) }

        let totalSleepAverage = average(dailySleep.map(\.totalMinutes))
        let previousTotalSleepAverage = average(previousSleep.map(\.totalMinutes))
        let daytimeAverage = average(dailySleep.map(\.daytimeMinutes))
        let previousDaytimeAverage = average(previousSleep.map(\.daytimeMinutes))
        let nightAverage = average(dailySleep.map(\.nightMinutes))
        let previousNightAverage = average(previousSleep.map(\.nightMinutes))
        let napAverage = average(currentNaps.compactMap(\.duration).map { $0 / 60 })
        let previousNapAverage = average(previousNaps.compactMap(\.duration).map { $0 / 60 })
        let wakeAverage = average(wakeWindows.map(\.minutes))
        let previousWakeAverage = average(previousWake.map(\.minutes))
        let bedtimeAverage = circularTimeAverage(bedtimes.map(\.value))
        let previousBedtimeAverage = circularTimeAverage(previousBedtimes.map(\.value))
        let bedtimeSD = standardDeviation(bedtimes.map(\.value))
        let previousBedtimeSD = standardDeviation(previousBedtimes.map(\.value))
        let sleepScores = nightSleepScores(events: completed, range: currentRange, calendar: calendar)
        let previousSleepScores = nightSleepScores(events: completed, range: previousRange, calendar: calendar)
        let latestSleepScore = sleepScores.last
        let averageSleepScore = average(sleepScores.map { Double($0.score) })
        let previousAverageSleepScore = average(previousSleepScores.map { Double($0.score) })
        let averageNightWakes = average(sleepScores.map { Double($0.wakeEventCount) })
        let previousAverageNightWakes = average(previousSleepScores.map { Double($0.wakeEventCount) })
        let averageNightAwake = average(sleepScores.map(\.totalWakeMinutes))
        let previousAverageNightAwake = average(previousSleepScores.map(\.totalWakeMinutes))
        let averageLongestNightStretch = average(sleepScores.map(\.longestStretchMinutes))
        let previousLongestNightStretch = average(previousSleepScores.map(\.longestStretchMinutes))
        let latestDaySleep = dailySleep.first {
            calendar.isDate($0.date, inSameDayAs: selectedEndDay)
        }?.totalMinutes ?? 0
        let latestDayCare = dailyFeeding.first {
            calendar.isDate($0.date, inSameDayAs: selectedEndDay)
        }?.careSessions ?? 0
        let latestDayDiapers = dailyDiapers.first {
            calendar.isDate($0.date, inSameDayAs: selectedEndDay)
        }?.total ?? 0
        let latestDayLabel = calendar.isDate(selectedEndDay, inSameDayAs: now)
            ? "Today"
            : "Final day"
        let tummyTotal = dailyActivities.reduce(0) { $0 + $1.tummyMinutes }
        let previousTummy = previousActivities.reduce(0) { $0 + $1.tummyMinutes }
        let readingTotal = dailyActivities.reduce(0) { $0 + $1.readingMinutes }
        let previousReading = previousActivities.reduce(0) { $0 + $1.readingMinutes }
        let indoorTotal = dailyActivities.reduce(0) { $0 + $1.indoorMinutes }
        let outdoorTotal = dailyActivities.reduce(0) { $0 + $1.outdoorMinutes }
        let screenTotal = dailyActivities.reduce(0) { $0 + $1.screenMinutes }
        let accuracy = accuracyValues(predictionErrors)
        let previousAccuracy = accuracyValues(previousPredictions)

        let comparison: (Double?, Double?) -> String? = { current, previous in
            guard compareToPrevious, let current, let previous else { return nil }
            guard let change = percentageChange(current: current, previous: previous) else { return "No prior baseline" }
            return "\(change >= 0 ? "+" : "")\(Int(change.rounded()))%"
        }

        let overviewMetrics = [
            metric("\(latestDayLabel) total sleep", latestDaySleep, nil, format: duration, icon: "moon.stars.fill", interpretation: "Day and night sleep logged on the final selected day."),
            metric("\(days)-day average sleep", totalSleepAverage, previousTotalSleepAverage, compare: compareToPrevious, format: duration, icon: "chart.line.uptrend.xyaxis", interpretation: "Average total sleep per logged day."),
            metric("Average nap", napAverage, previousNapAverage, compare: compareToPrevious, format: duration, icon: "bed.double.fill", interpretation: "Typical nap length in this period."),
            metric("Average wake window", wakeAverage, previousWakeAverage, compare: compareToPrevious, format: duration, icon: "timer", interpretation: "Time awake between completed sleeps."),
            metric("Typical bedtime", bedtimeAverage, previousBedtimeAverage, compare: compareToPrevious, format: clock, icon: "moon.fill", interpretation: "Average evening night-sleep start."),
            metric("Prediction accuracy", accuracy.inside, previousAccuracy.inside, compare: compareToPrevious, format: percent, icon: "scope", interpretation: "Resolved predictions inside their window."),
            InsightMetric(title: "Care sessions \(latestDayLabel.lowercased())", value: "\(latestDayCare)", interpretation: "Feed and nursing sessions, with split sides combined.", systemImage: "waterbottle.fill"),
            InsightMetric(title: "Diapers \(latestDayLabel.lowercased())", value: "\(latestDayDiapers)", interpretation: "All wet, dirty, and both changes.", systemImage: "drop.fill"),
            metric("Tummy time", tummyTotal, previousTummy, compare: compareToPrevious, format: duration, icon: "figure.play", interpretation: "Total in the selected period."),
            metric("Reading time", readingTotal, previousReading, compare: compareToPrevious, format: duration, icon: "book.fill", interpretation: "Total in the selected period.")
        ]

        let longestNap = currentNaps.compactMap(\.duration).max().map { $0 / 60 }
        let shortestNap = currentNaps.compactMap(\.duration).min().map { $0 / 60 }
        let longestNight = completed.filter {
            $0.type == .sleep && $0.sleepKind == .nightSleep && currentRange.contains($0.startDate)
        }.compactMap(\.duration).max().map { $0 / 60 }
        let napCountAverage = average(dailySleep.map { Double($0.napCount) })
        let morningAverage = circularTimeAverage(morningWakes.map(\.value), rollsAfterMidnight: false)
        let sleepMetrics = [
            InsightMetric(
                title: "Latest sleep score",
                value: latestSleepScore.map { "\($0.score)" } ?? "-",
                interpretation: latestSleepScore.map {
                    "\($0.label): based on night sleep only, using total sleep, wake count, awake time, efficiency, and longest stretch."
                } ?? "Log completed night sleep to calculate a score.",
                systemImage: "moon.stars.circle.fill"
            ),
            metric("Average sleep score", averageSleepScore, previousAverageSleepScore, compare: compareToPrevious, format: whole, icon: "gauge.with.dots.needle.bottom.50percent", interpretation: "0-100 log-based overnight score; not a medical or developmental rating."),
            metric("Total sleep / day", totalSleepAverage, previousTotalSleepAverage, compare: compareToPrevious, format: duration, icon: "moon.stars.fill", interpretation: "Average across the selected days."),
            metric("Daytime sleep / day", daytimeAverage, previousDaytimeAverage, compare: compareToPrevious, format: duration, icon: "sun.haze.fill", interpretation: "Average sleep logged as naps."),
            metric("Night sleep / day", nightAverage, previousNightAverage, compare: compareToPrevious, format: duration, icon: "moon.zzz.fill", interpretation: "Overnight segments grouped to the prior evening."),
            metric("Night wakes / night", averageNightWakes, previousAverageNightWakes, compare: compareToPrevious, format: oneDecimal, icon: "bell.fill", interpretation: "Gaps between night-sleep segments within the same overnight bucket."),
            metric("Awake overnight", averageNightAwake, previousAverageNightAwake, compare: compareToPrevious, format: duration, icon: "eye.fill", interpretation: "Average total time awake between night-sleep segments."),
            metric("Longest night stretch", averageLongestNightStretch, previousLongestNightStretch, compare: compareToPrevious, format: duration, icon: "arrow.left.and.right", interpretation: "Average longest uninterrupted night sleep segment."),
            metric("Naps / day", napCountAverage, average(previousSleep.map { Double($0.napCount) }), compare: compareToPrevious, format: oneDecimal, icon: "number", interpretation: "Average nap count."),
            metric("Average nap", napAverage, previousNapAverage, compare: compareToPrevious, format: duration, icon: "bed.double.fill", interpretation: "Mean completed nap duration."),
            metric("Longest nap", longestNap, nil, format: duration, icon: "arrow.up.to.line", interpretation: "Longest nap in this period."),
            metric("Shortest nap", shortestNap, nil, format: duration, icon: "arrow.down.to.line", interpretation: "Shortest nap in this period."),
            metric("Typical bedtime", bedtimeAverage, previousBedtimeAverage, compare: compareToPrevious, format: clock, icon: "moon.fill", interpretation: "Average evening sleep onset."),
            metric("Bedtime variability", bedtimeSD, previousBedtimeSD, compare: compareToPrevious, format: duration, icon: "waveform.path", interpretation: "Lower means bedtime is more consistent."),
            metric("Morning wake", morningAverage, nil, format: clock, icon: "sunrise.fill", interpretation: "Average final overnight wake time."),
            metric("Single longest stretch", longestNight, nil, format: duration, icon: "arrow.up.to.line", interpretation: "Longest uninterrupted night segment.")
        ]

        let wakeGrouped = Dictionary(grouping: wakeWindows, by: \.napIndex)
        let readyPressureStarts = sleepPressureBeforeSleep.filter {
            $0.band == .ready || $0.band == .high
        }
        let previousReadyPressureStarts = previousSleepPressureBeforeSleep.filter {
            $0.band == .ready || $0.band == .high
        }
        let highPressureStarts = sleepPressureBeforeSleep.filter { $0.band == .high }
        let previousHighPressureStarts = previousSleepPressureBeforeSleep.filter { $0.band == .high }
        let pressureAverage = average(sleepPressureBeforeSleep.map(\.score))
        let previousPressureAverage = average(previousSleepPressureBeforeSleep.map(\.score))
        let readyPressureShare = sleepPressureBeforeSleep.isEmpty
            ? nil
            : Double(readyPressureStarts.count) / Double(sleepPressureBeforeSleep.count)
        let previousReadyPressureShare = previousSleepPressureBeforeSleep.isEmpty
            ? nil
            : Double(previousReadyPressureStarts.count) / Double(previousSleepPressureBeforeSleep.count)
        let highPressureShare = sleepPressureBeforeSleep.isEmpty
            ? nil
            : Double(highPressureStarts.count) / Double(sleepPressureBeforeSleep.count)
        let previousHighPressureShare = previousSleepPressureBeforeSleep.isEmpty
            ? nil
            : Double(previousHighPressureStarts.count) / Double(previousSleepPressureBeforeSleep.count)
        let wakeAverages = (1...5).compactMap { index -> CategoryValue? in
            guard let values = wakeGrouped[index], !values.isEmpty else { return nil }
            return CategoryValue(category: napLabel(index), value: average(values.map(\.minutes)) ?? 0)
        }
        let wakeVariability = (1...5).compactMap { index -> CategoryValue? in
            guard let values = wakeGrouped[index], !values.isEmpty else { return nil }
            return CategoryValue(category: napLabel(index), value: standardDeviation(values.map(\.minutes)) ?? 0)
        }
        let pressureBySleepOrder = Dictionary(grouping: sleepPressureBeforeSleep, by: \.napIndex)
        let sleepPressureAverages = (1...5).compactMap { index -> CategoryValue? in
            guard let values = pressureBySleepOrder[index], !values.isEmpty else { return nil }
            return CategoryValue(category: napLabel(index), value: average(values.map(\.score)) ?? 0)
        }
        let sleepPressureBandCounts = [
            SleepPressureBand.low,
            SleepPressureBand.building,
            SleepPressureBand.ready,
            SleepPressureBand.high
        ].compactMap { band -> CategoryValue? in
            let count = sleepPressureBeforeSleep.filter { $0.band == band }.count
            return count > 0 ? CategoryValue(category: band.displayName, value: Double(count)) : nil
        }
        let mostPredictable = wakeVariability.min { $0.value < $1.value }
        let leastPredictable = wakeVariability.max { $0.value < $1.value }
        var wakeMetrics = [
            metric("Overall wake window", wakeAverage, previousWakeAverage, compare: compareToPrevious, format: duration, icon: "timer", interpretation: "Average between completed sleeps.")
        ]
        wakeMetrics += wakeAverages.map {
            InsightMetric(title: "Average \($0.category.lowercased())", value: duration($0.value), interpretation: "For \(profileName)'s recent pattern.", systemImage: "clock")
        }
        wakeMetrics += [
            metric("Wake variability", standardDeviation(wakeWindows.map(\.minutes)), standardDeviation(previousWake.map(\.minutes)), compare: compareToPrevious, format: duration, icon: "waveform.path", interpretation: "Spread across recent wake windows."),
            metric("Pressure before sleep", pressureAverage, previousPressureAverage, compare: compareToPrevious, format: whole, icon: "gauge.with.dots.needle.50percent", interpretation: "Average sleep-pressure score immediately before completed sleep starts."),
            metric("Ready/high starts", readyPressureShare, previousReadyPressureShare, compare: compareToPrevious, format: percent, icon: "checkmark.seal.fill", interpretation: "Share of completed sleeps that began in the ready or high pressure band."),
            metric("High-pressure starts", highPressureShare, previousHighPressureShare, compare: compareToPrevious, format: percent, icon: "exclamationmark.triangle.fill", interpretation: "Share of completed sleeps that began after pressure moved above the usual ready range."),
            InsightMetric(title: "Most predictable", value: mostPredictable?.category ?? "-", interpretation: mostPredictable.map { "\(duration($0.value)) typical variation." } ?? "More sleep logs are needed.", systemImage: "checkmark.circle.fill"),
            InsightMetric(title: "Least predictable", value: leastPredictable?.category ?? "-", interpretation: leastPredictable.map { "\(duration($0.value)) typical variation." } ?? "More sleep logs are needed.", systemImage: "questionmark.circle")
        ]

        let nursingEvents = events.filter {
            $0.type == .nursing && currentRange.contains($0.startDate)
        }
        let previousNursing = events.filter {
            $0.type == .nursing && previousRange.contains($0.startDate)
        }
        let leftMinutes = nursingEvents.filter { $0.nursingSide == .left }.compactMap(\.duration).reduce(0, +) / 60
        let rightMinutes = nursingEvents.filter { $0.nursingSide == .right }.compactMap(\.duration).reduce(0, +) / 60
        let nursingTotal = leftMinutes + rightMinutes
        let previousNursingTotal = previousNursing.compactMap(\.duration).reduce(0, +) / 60
        let bottleEvents = events.filter {
            $0.type == .feed && $0.feedKind == .bottle && currentRange.contains($0.startDate)
        }
        let previousBottles = events.filter {
            $0.type == .feed && $0.feedKind == .bottle && previousRange.contains($0.startDate)
        }
        let bottleOunces = bottleEvents.compactMap(\.amountOz).reduce(0, +)
        let previousBottleOunces = previousBottles.compactMap(\.amountOz).reduce(0, +)
        let careIntervals = zip(currentCare, currentCare.dropFirst()).map { $1.timeIntervalSince($0) / 60 }
        let feedSleepIntervals = feedToSleepIntervals(events: events, range: currentRange)
        let beforeSleepCount = feedSleepIntervals.filter { $0 <= 30 }.count
        let feedingMetrics = [
            metric("Care sessions / day", average(dailyFeeding.map { Double($0.careSessions) }), average(previousFeeding.map { Double($0.careSessions) }), compare: compareToPrevious, format: oneDecimal, icon: "fork.knife", interpretation: "Bottle, solids, and grouped nursing sessions."),
            metric("Bottle ounces", bottleOunces, previousBottleOunces, compare: compareToPrevious, format: ounces, icon: "waterbottle.fill", interpretation: "Logged bottle volume in this period."),
            metric("Average bottle", average(bottleEvents.compactMap(\.amountOz)), average(previousBottles.compactMap(\.amountOz)), compare: compareToPrevious, format: ounces, icon: "waterbottle", interpretation: "Average amount per bottle log."),
            metric("Nursing sessions / day", average(dailyFeeding.map { Double($0.nursingSessions) }), average(previousFeeding.map { Double($0.nursingSessions) }), compare: compareToPrevious, format: oneDecimal, icon: "figure.and.child.holdinghands", interpretation: "Split Left/Right logs are combined into sessions."),
            metric("Nursing time", nursingTotal, previousNursingTotal, compare: compareToPrevious, format: duration, icon: "timer", interpretation: "Total logged nursing duration."),
            InsightMetric(title: "Left nursing", value: duration(leftMinutes), interpretation: "Logged Left-side time.", systemImage: "l.circle.fill"),
            InsightMetric(title: "Right nursing", value: duration(rightMinutes), interpretation: "Logged Right-side time.", systemImage: "r.circle.fill"),
            metric("Time between care", median(careIntervals), nil, format: duration, icon: "arrow.left.and.right", interpretation: "Median interval between grouped care sessions."),
            InsightMetric(title: "Within 30m of sleep", value: "\(beforeSleepCount)", interpretation: "Sleep starts following care in this period.", systemImage: "moon.circle.fill")
        ]

        let totalDiapers = dailyDiapers.reduce(0) { $0 + $1.total }
        let previousTotalDiapers = previousDiapers.reduce(0) { $0 + $1.total }
        let wet = dailyDiapers.reduce(0) { $0 + $1.wet }
        let dirty = dailyDiapers.reduce(0) { $0 + $1.dirty }
        let both = dailyDiapers.reduce(0) { $0 + $1.both }
        let peeCount = wet + both
        let pooCount = dirty + both
        let diaperIntervals = zip(currentDiaperEvents, currentDiaperEvents.dropFirst()).map {
            $1.startDate.timeIntervalSince($0.startDate) / 60
        }
        let diaperMetrics = [
            InsightMetric(title: "Pee diapers", value: "\(peeCount)", interpretation: "Changes with pee selected, including mixed.", systemImage: "drop.fill"),
            InsightMetric(title: "Poo diapers", value: "\(pooCount)", interpretation: "Changes with poo selected, including mixed.", systemImage: "circle.bottomhalf.filled"),
            InsightMetric(title: "Mixed", value: "\(both)", interpretation: "Changes with both pee and poo.", systemImage: "circle.lefthalf.filled"),
            InsightMetric(title: "Total changes", value: "\(totalDiapers)", change: comparison(Double(totalDiapers), Double(previousTotalDiapers)), direction: trendDirection(current: Double(totalDiapers), previous: Double(previousTotalDiapers)), interpretation: "For \(profileName)'s logged recent pattern.", systemImage: "number"),
            metric("Changes / day", average(dailyDiapers.map { Double($0.total) }), average(previousDiapers.map { Double($0.total) }), compare: compareToPrevious, format: oneDecimal, icon: "calendar", interpretation: "Average across the selected days."),
            metric("Time between changes", median(diaperIntervals), nil, format: duration, icon: "clock", interpretation: "Median interval between diaper logs.")
        ]

        let tummySessions = currentActivityEvents.filter {
            $0.type == .activity && $0.activityType == .tummyTime
        }
        let readingSessions = currentActivityEvents.filter {
            $0.type == .activity && $0.activityType == .storyTime
        }
        let bathEvents = currentActivityEvents.filter {
            $0.type == .activity && $0.activityType == .bath
        }
        let bathCount = bathEvents.count
        let medicineEvents = currentActivityEvents.filter { $0.type == .medicine }
        let customCount = currentActivityEvents.filter { $0.type == .custom }.count
        let brushTeethCount = dailyActivities.reduce(0) { $0 + $1.brushTeeth }
        let activityMetrics = [
            metric("Tummy time", tummyTotal, previousTummy, compare: compareToPrevious, format: duration, icon: "figure.play", interpretation: "Total in the selected period."),
            metric("Tummy / day", average(dailyActivities.map(\.tummyMinutes)), average(previousActivities.map(\.tummyMinutes)), compare: compareToPrevious, format: duration, icon: "calendar", interpretation: "Daily average."),
            metric("Average tummy session", average(tummySessions.compactMap(\.duration).map { $0 / 60 }), nil, format: duration, icon: "timer", interpretation: "Mean completed session."),
            metric("Reading time", readingTotal, previousReading, compare: compareToPrevious, format: duration, icon: "book.fill", interpretation: "Total logged reading duration."),
            InsightMetric(title: "Reading sessions", value: "\(readingSessions.count)", interpretation: "Logged sessions in this period.", systemImage: "books.vertical.fill"),
            InsightMetric(title: "Indoor play", value: duration(indoorTotal), interpretation: "Total timed indoor play.", systemImage: "house.fill"),
            InsightMetric(title: "Outdoor play", value: duration(outdoorTotal), interpretation: "Total timed outdoor play.", systemImage: "sun.max.fill"),
            InsightMetric(title: "Screen time", value: duration(screenTotal), interpretation: "Total logged screen time.", systemImage: "tv.fill"),
            InsightMetric(title: "Baths", value: "\(bathCount)", interpretation: "Bath logs in this period.", systemImage: "bathtub.fill"),
            InsightMetric(title: "Brush teeth", value: "\(brushTeethCount)", interpretation: "Logged tooth-brushing activities.", systemImage: "mouth.fill"),
            InsightMetric(title: "Custom events", value: "\(customCount)", interpretation: "Other custom logs in this period.", systemImage: "sparkles")
        ]

        let growthEvents = currentActivityEvents
            .filter { $0.type == .growth }
            .sorted { $0.startDate < $1.startDate }
        let growthMeasurements = growthEvents.map {
            GrowthMeasurementSummary(
                id: $0.id,
                date: $0.startDate,
                weightPounds: $0.totalWeightOunces.map { $0 / 16 },
                heightInches: $0.totalHeightInches,
                headCircumferenceInches: $0.canonicalHeadCircumferenceCentimeters.map {
                    $0 / GrowthUnitConversion.centimetersPerInch
                }
            )
        }
        let latestGrowth = growthMeasurements.last
        let previousGrowth = growthMeasurements.dropLast().last
        let growthMetrics = [
            InsightMetric(
                title: "Latest weight",
                value: latestGrowth?.weightPounds.map { "\($0.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "-",
                change: measurementChange(latestGrowth?.weightPounds, previousGrowth?.weightPounds, unit: "lb"),
                interpretation: "Personal measurement trend only; no percentile comparison.",
                systemImage: "scalemass.fill"
            ),
            InsightMetric(
                title: "Latest height",
                value: latestGrowth?.heightInches.map { "\($0.formatted(.number.precision(.fractionLength(1)))) in" } ?? "-",
                change: measurementChange(latestGrowth?.heightInches, previousGrowth?.heightInches, unit: "in"),
                interpretation: "Most recent logged height.",
                systemImage: "ruler.fill"
            ),
            InsightMetric(
                title: "Latest head circumference",
                value: latestGrowth?.headCircumferenceInches.map { "\($0.formatted(.number.precision(.fractionLength(1)))) in" } ?? "-",
                change: measurementChange(
                    latestGrowth?.headCircumferenceInches,
                    previousGrowth?.headCircumferenceInches,
                    unit: "in"
                ),
                interpretation: "Most recent logged head circumference.",
                systemImage: "circle.dashed"
            )
        ]

        let temperatureEvents = currentActivityEvents
            .filter { $0.type == .temperature && $0.temperatureCelsius != nil }
            .sorted { $0.startDate < $1.startDate }
        let temperatureMeasurements = temperatureEvents.compactMap { event -> TemperatureMeasurementSummary? in
            guard let fahrenheit = event.temperatureValue(in: .fahrenheit) else { return nil }
            return TemperatureMeasurementSummary(
                id: event.id,
                date: event.startDate,
                fahrenheit: fahrenheit,
                method: event.temperatureMethod?.displayName
            )
        }
        let temperatureValues = temperatureMeasurements.map(\.fahrenheit)
        let temperatureMetrics = [
            InsightMetric(
                title: "Latest temperature",
                value: temperatureMeasurements.last.map {
                    "\($0.fahrenheit.formatted(.number.precision(.fractionLength(1))))°F"
                } ?? "-",
                interpretation: "Most recent logged measurement.",
                systemImage: "thermometer.medium"
            ),
            InsightMetric(
                title: "High",
                value: temperatureValues.max().map {
                    "\($0.formatted(.number.precision(.fractionLength(1))))°F"
                } ?? "-",
                interpretation: "Highest logged value. Check with your pediatrician if you are concerned.",
                systemImage: "arrow.up"
            ),
            InsightMetric(
                title: "Low",
                value: temperatureValues.min().map {
                    "\($0.formatted(.number.precision(.fractionLength(1))))°F"
                } ?? "-",
                interpretation: "Lowest logged value in this period.",
                systemImage: "arrow.down"
            )
        ]

        let sortedMedicineEvents = medicineEvents.sorted { $0.startDate > $1.startDate }
        let medicineCounts = Dictionary(grouping: medicineEvents) {
            let name = $0.medicineName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Medicine" : name
        }
        let medicineMetrics = [
            InsightMetric(
                title: "Administrations",
                value: "\(medicineEvents.count)",
                interpretation: "Logged administrations only; no dosing guidance.",
                systemImage: "cross.case.fill"
            ),
            InsightMetric(
                title: "Medicine types",
                value: "\(medicineCounts.count)",
                interpretation: "Distinct medicine names in this period.",
                systemImage: "list.bullet"
            ),
            InsightMetric(
                title: "Most recent",
                value: sortedMedicineEvents.first?.medicineName ?? "-",
                interpretation: sortedMedicineEvents.first.map {
                    $0.startDate.formatted(date: .abbreviated, time: .shortened)
                } ?? "No medicine logged in this period.",
                systemImage: "clock.fill"
            )
        ]

        let pooColorShare = PooColor.allCases.compactMap { color -> CategoryValue? in
            guard color != .unknown else { return nil }
            let count = currentDiaperEvents.filter { $0.pooColor == color }.count
            return count > 0 ? CategoryValue(category: color.displayName, value: Double(count)) : nil
        }
        let peeAmountShare = DiaperAmount.allCases.compactMap { amount -> CategoryValue? in
            guard amount != .unknown else { return nil }
            let count = currentDiaperEvents.filter { $0.peeAmount == amount }.count
            return count > 0 ? CategoryValue(category: amount.displayName, value: Double(count)) : nil
        }
        let pooAmountShare = DiaperAmount.allCases.compactMap { amount -> CategoryValue? in
            guard amount != .unknown else { return nil }
            let count = currentDiaperEvents.filter { $0.pooAmount == amount }.count
            return count > 0 ? CategoryValue(category: amount.displayName, value: Double(count)) : nil
        }

        let napAccuracy = groupedAccuracy(predictionErrors, key: { napLabel($0.napIndex) })
        let confidenceAccuracy = groupedInsidePercentage(predictionErrors, key: \.confidence)
        let bestNap = napAccuracy.min { $0.value < $1.value }
        let worstNap = napAccuracy.max { $0.value < $1.value }
        let predictionMetrics = [
            InsightMetric(title: "Predictions evaluated", value: "\(accuracy.count)", interpretation: "Resolved predictions in this period.", systemImage: "checkmark.circle.fill"),
            metric("Inside predicted window", accuracy.inside, previousAccuracy.inside, compare: compareToPrevious, format: percent, icon: "scope", interpretation: "Share of resolved predictions inside the shown range."),
            metric("Mean absolute error", accuracy.meanAbsolute, previousAccuracy.meanAbsolute, compare: compareToPrevious, format: duration, icon: "plus.forwardslash.minus", interpretation: "Average absolute miss."),
            metric("Median absolute error", accuracy.medianAbsolute, previousAccuracy.medianAbsolute, compare: compareToPrevious, format: duration, icon: "chart.bar.xaxis", interpretation: "Typical absolute miss, less affected by outliers."),
            metric("Timing bias", accuracy.bias, previousAccuracy.bias, compare: compareToPrevious, format: signedMinutes, icon: "arrow.left.and.right", interpretation: "Negative is early; positive is late."),
            InsightMetric(title: "Best nap index", value: bestNap?.category ?? "-", interpretation: bestNap.map { "\(duration($0.value)) mean absolute error." } ?? "More resolved predictions are needed.", systemImage: "hand.thumbsup.fill"),
            InsightMetric(title: "Hardest nap index", value: worstNap?.category ?? "-", interpretation: worstNap.map { "\(duration($0.value)) mean absolute error." } ?? "More resolved predictions are needed.", systemImage: "wand.and.stars"),
            InsightMetric(
                title: "Algorithm",
                value: SleepPredictionEngine.displayAlgorithmVersion(records.first?.algorithmVersion),
                interpretation: "Version recorded with predictions.",
                systemImage: "cpu"
            )
        ]

        return InsightsSnapshot(
            profileName: profileName,
            periodStart: start,
            periodEnd: end,
            comparisonLabel: compareToPrevious ? "Compared with the previous \(days) days" : nil,
            overviewMetrics: overviewMetrics,
            sleepMetrics: sleepMetrics,
            wakeMetrics: wakeMetrics,
            feedingMetrics: feedingMetrics,
            diaperMetrics: diaperMetrics,
            activityMetrics: activityMetrics,
            predictionMetrics: predictionMetrics,
            overviewTrends: compactTrends([
                makeTrend(name: "Total sleep", current: totalSleepAverage, previous: previousTotalSleepAverage, format: duration, subject: "\(profileName)'s average total sleep"),
                makeTrend(name: "Daytime sleep", current: daytimeAverage, previous: previousDaytimeAverage, format: duration, subject: "\(profileName)'s daytime sleep"),
                makeTrend(name: "Wake windows", current: wakeAverage, previous: previousWakeAverage, format: duration, subject: "Average wake windows"),
                makeTrend(name: "Care rhythm", current: average(dailyFeeding.map { Double($0.careSessions) }), previous: average(previousFeeding.map { Double($0.careSessions) }), format: oneDecimal, subject: "Daily care sessions")
            ]),
            sleepTrends: compactTrends([
                makeTrend(name: "Sleep score", current: averageSleepScore, previous: previousAverageSleepScore, format: whole, subject: "Average overnight score"),
                makeTrend(name: "Night wakes", current: averageNightWakes, previous: previousAverageNightWakes, format: oneDecimal, subject: "Overnight wake events"),
                makeTrend(name: "Daytime sleep", current: daytimeAverage, previous: previousDaytimeAverage, format: duration, subject: "Daytime sleep"),
                makeTrend(name: "Nap length", current: napAverage, previous: previousNapAverage, format: duration, subject: "Average nap length"),
                makeTrend(name: "Bedtime", current: bedtimeAverage, previous: previousBedtimeAverage, format: clock, subject: "Typical bedtime", differenceUnit: "minutes"),
                makeTrend(name: "Bedtime consistency", current: bedtimeSD, previous: previousBedtimeSD, format: duration, subject: "Bedtime variability")
            ]),
            wakeTrends: wakeObservations(profileName: profileName, current: wakeWindows, previous: previousWake),
            feedingTrends: compactTrends([
                makeTrend(name: "Care sessions", current: average(dailyFeeding.map { Double($0.careSessions) }), previous: average(previousFeeding.map { Double($0.careSessions) }), format: oneDecimal, subject: "Daily feed and nursing sessions"),
                makeTrend(name: "Bottle intake", current: bottleOunces, previous: previousBottleOunces, format: ounces, subject: "Logged bottle intake"),
                sideBalanceTrend(profileName: profileName, left: leftMinutes, right: rightMinutes),
                feedSleepTrend(profileName: profileName, intervals: feedSleepIntervals)
            ]),
            diaperTrends: compactTrends([
                makeTrend(name: "Diaper changes", current: Double(totalDiapers), previous: Double(previousTotalDiapers), format: whole, subject: "Logged diaper changes"),
                diaperTimeTrend(profileName: profileName, events: currentDiaperEvents, calendar: calendar)
            ]),
            activityTrends: compactTrends([
                makeTrend(name: "Tummy time", current: tummyTotal, previous: previousTummy, format: duration, subject: "Tummy time"),
                makeTrend(name: "Reading", current: readingTotal, previous: previousReading, format: duration, subject: "Reading time"),
                readingDaysTrend(profileName: profileName, activities: dailyActivities),
                bathTimeTrend(profileName: profileName, events: bathEvents, calendar: calendar)
            ]),
            predictionTrends: predictionObservations(profileName: profileName, current: predictionErrors, previous: previousPredictions),
            dailySleep: dailySleep,
            wakeWindows: wakeWindows,
            sleepPressureBeforeSleep: sleepPressureBeforeSleep,
            sleepPressureBandCounts: sleepPressureBandCounts,
            sleepPressureAverages: sleepPressureAverages,
            dailyFeeding: dailyFeeding,
            dailyDiapers: dailyDiapers,
            dailyActivities: dailyActivities,
            predictionErrors: predictionErrors,
            napDurationBuckets: durationBuckets(currentNaps.compactMap(\.duration).map { $0 / 60 }),
            feedToSleepBuckets: intervalBuckets(feedSleepIntervals),
            feedingHourBuckets: hourBuckets(events: currentCare.map {
                BabyEvent(type: .custom, startDate: $0, endDate: $0)
            }, calendar: calendar),
            diaperHourBuckets: hourBuckets(events: currentDiaperEvents, calendar: calendar),
            nursingSideMinutes: [
                CategoryValue(category: "Left", value: leftMinutes),
                CategoryValue(category: "Right", value: rightMinutes)
            ],
            activityMix: [
                CategoryValue(category: "Tummy", value: tummyTotal),
                CategoryValue(category: "Story", value: readingTotal),
                CategoryValue(category: "Indoor", value: indoorTotal),
                CategoryValue(category: "Outdoor", value: outdoorTotal),
                CategoryValue(category: "Screen", value: screenTotal),
                CategoryValue(category: "Bath", value: Double(bathCount)),
                CategoryValue(category: "Brush", value: Double(brushTeethCount)),
                CategoryValue(category: "Custom", value: Double(customCount))
            ],
            wakeAverages: wakeAverages,
            wakeVariability: wakeVariability,
            diaperTypeShare: [
                CategoryValue(category: "Pee only", value: Double(wet)),
                CategoryValue(category: "Poo only", value: Double(dirty)),
                CategoryValue(category: "Mixed", value: Double(both))
            ],
            predictionByNap: napAccuracy,
            predictionByConfidence: confidenceAccuracy,
            bedtimes: bedtimes,
            morningWakes: morningWakes,
            sleepScores: sleepScores,
            sleepBlocks: completed.filter {
                $0.type == .sleep && currentRange.contains(sleepBucketDate(for: $0, calendar: calendar))
            }.sorted { $0.startDate > $1.startDate },
            medicineNames: Array(Set(medicineEvents.compactMap(\.medicineName))).sorted(),
            growthMetrics: growthMetrics,
            temperatureMetrics: temperatureMetrics,
            medicineMetrics: medicineMetrics,
            growthMeasurements: growthMeasurements,
            temperatureMeasurements: temperatureMeasurements,
            medicineEvents: sortedMedicineEvents,
            pooColorShare: pooColorShare,
            peeAmountShare: peeAmountShare,
            pooAmountShare: pooAmountShare
        )
    }

    static func dailySleepTotals(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [DailySleepSummary] {
        let days = dates(in: range, calendar: calendar)
        let sleepEvents = events.filter { $0.type == .sleep && $0.endDate != nil }
        let grouped = Dictionary(grouping: sleepEvents) { sleepBucketDate(for: $0, calendar: calendar) }
        return days.map { day in
            let values = grouped[day] ?? []
            let naps = values.filter { $0.sleepKind == .nap }
            let daytime = naps.compactMap(\.duration).reduce(0, +) / 60
            let night = values.filter { $0.sleepKind == .nightSleep }.compactMap(\.duration).reduce(0, +) / 60
            return DailySleepSummary(
                date: day,
                daytimeMinutes: daytime,
                nightMinutes: night,
                napCount: naps.count,
                averageNapMinutes: average(naps.compactMap(\.duration).map { $0 / 60 }) ?? 0
            )
        }
    }

    static func wakeWindowCalculations(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [WakeWindowSummary] {
        let sleeps = events.filter { $0.type == .sleep && $0.endDate != nil }
        return SleepPredictionEngine.wakeWindowSamples(from: sleeps, now: range.upperBound, calendar: calendar)
            .filter { range.contains($0.date) }
            .map {
                WakeWindowSummary(
                    date: $0.date,
                    napIndex: $0.napIndex,
                    minutes: $0.minutes
                )
            }
    }

    static func sleepPressureBeforeSleepCalculations(
        profile: BabyProfile?,
        events: [BabyEvent],
        records: [SleepPredictionRecord] = [],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [SleepPressureSummary] {
        guard let profile, profile.profileType == .child else { return [] }
        let sleeps = events
            .filter { $0.type == .sleep && $0.endDate != nil }
            .sorted { $0.startDate < $1.startDate }

        return sleeps.compactMap { sleep -> SleepPressureSummary? in
            guard range.contains(sleep.startDate) else { return nil }
            let priorEvents = events.filter {
                $0.id != sleep.id && $0.startDate < sleep.startDate
            }
            guard let pressure = SleepPredictionEngine.sleepPressure(
                profile: profile,
                events: priorEvents,
                records: records.filter { $0.generatedAt <= sleep.startDate },
                now: sleep.startDate,
                calendar: calendar
            ),
                  let score = pressure.score else {
                return nil
            }
            return SleepPressureSummary(
                eventID: sleep.id,
                date: sleep.startDate,
                score: score,
                band: pressure.band,
                sleepKind: sleep.sleepKind,
                napIndex: SleepPredictionEngine.napIndex(
                    for: sleep,
                    among: sleeps,
                    calendar: calendar
                )
            )
        }
    }

    static func bedtimeExtraction(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [ChartDataPoint] {
        events.filter {
            $0.type == .sleep &&
            $0.sleepKind == .nightSleep &&
            range.contains(sleepBucketDate(for: $0, calendar: calendar)) &&
            calendar.component(.hour, from: $0.startDate) >= 17
        }.map {
            let hour = calendar.component(.hour, from: $0.startDate)
            let minute = calendar.component(.minute, from: $0.startDate)
            return ChartDataPoint(
                date: sleepBucketDate(for: $0, calendar: calendar),
                value: Double(hour * 60 + minute),
                category: "Bedtime"
            )
        }.sorted { $0.date < $1.date }
    }

    static func morningWakeExtraction(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [ChartDataPoint] {
        let night = events.filter {
            guard $0.type == .sleep, $0.sleepKind == .nightSleep, let end = $0.endDate else { return false }
            return range.contains(calendar.startOfDay(for: end)) && calendar.component(.hour, from: end) < 12
        }
        return Dictionary(grouping: night) { event in
            calendar.startOfDay(for: event.endDate ?? event.startDate)
        }.compactMap { day, values in
            guard let wake = values.compactMap(\.endDate).max() else { return nil }
            let minutes = calendar.component(.hour, from: wake) * 60 + calendar.component(.minute, from: wake)
            return ChartDataPoint(date: day, value: Double(minutes), category: "Morning wake")
        }.sorted { $0.date < $1.date }
    }

    static func nightSleepScores(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [NightSleepScoreSummary] {
        let nightEvents = events.filter {
            $0.type == .sleep &&
            $0.sleepKind == .nightSleep &&
            $0.endDate != nil &&
            range.contains(sleepBucketDate(for: $0, calendar: calendar))
        }
        let grouped = Dictionary(grouping: nightEvents) {
            sleepBucketDate(for: $0, calendar: calendar)
        }

        return grouped.compactMap { day, events -> NightSleepScoreSummary? in
            let segments = events
                .filter { ($0.duration ?? 0) > 0 }
                .sorted { $0.startDate < $1.startDate }
            guard let first = segments.first,
                  let lastEnd = segments.compactMap(\.endDate).max() else {
                return nil
            }

            let durations = segments.compactMap(\.duration).map { $0 / 60 }
            let totalSleep = durations.reduce(0, +)
            let wakeDurations = zip(segments, segments.dropFirst()).compactMap { previous, next -> Double? in
                guard let previousEnd = previous.endDate else { return nil }
                let gap = next.startDate.timeIntervalSince(previousEnd) / 60
                return gap >= 3 ? gap : nil
            }
            let totalWake = wakeDurations.reduce(0, +)
            let sleepWindow = max(1, lastEnd.timeIntervalSince(first.startDate) / 60)
            let longestStretch = durations.max() ?? totalSleep
            let score = nightSleepScore(
                totalSleepMinutes: totalSleep,
                wakeEventCount: wakeDurations.count,
                totalWakeMinutes: totalWake,
                longestStretchMinutes: longestStretch,
                sleepWindowMinutes: sleepWindow
            )

            return NightSleepScoreSummary(
                date: day,
                score: score,
                totalSleepMinutes: totalSleep,
                wakeEventCount: wakeDurations.count,
                totalWakeMinutes: totalWake,
                longestStretchMinutes: longestStretch,
                sleepWindowMinutes: sleepWindow,
                firstSleepStart: first.startDate,
                finalWake: lastEnd,
                wakeDurationsMinutes: wakeDurations,
                segmentCount: segments.count
            )
        }.sorted { $0.date < $1.date }
    }

    static func feedingAggregation(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [DailyFeedingSummary] {
        let sessions = careSessions(events: events, range: range)
        let nursing = groupedNursingSessions(events: events, range: range)
        let bottles = events.filter {
            $0.type == .feed && $0.feedKind == .bottle && range.contains($0.startDate)
        }
        return dates(in: range, calendar: calendar).map { day in
            DailyFeedingSummary(
                date: day,
                careSessions: sessions.filter { calendar.isDate($0, inSameDayAs: day) }.count,
                nursingSessions: nursing.filter { calendar.isDate($0, inSameDayAs: day) }.count,
                bottleOunces: bottles.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
                    .compactMap(\.amountOz).reduce(0, +)
            )
        }
    }

    static func diaperAggregation(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [DailyDiaperSummary] {
        let diapers = events.filter { $0.type == .diaper && range.contains($0.startDate) }
        return dates(in: range, calendar: calendar).map { day in
            let values = diapers.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            return DailyDiaperSummary(
                date: day,
                wet: values.filter { $0.diaperKind == .wet }.count,
                dirty: values.filter { $0.diaperKind == .dirty }.count,
                both: values.filter { $0.diaperKind == .both }.count
            )
        }
    }

    static func activityAggregation(
        events: [BabyEvent],
        range: Range<Date>,
        calendar: Calendar = .current
    ) -> [DailyActivitySummary] {
        let values = events.filter { range.contains($0.startDate) }
        return dates(in: range, calendar: calendar).map { day in
            let daily = values.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            return DailyActivitySummary(
                date: day,
                tummyMinutes: daily.filter {
                    $0.type == .activity && $0.activityType == .tummyTime
                }.compactMap(\.duration).reduce(0, +) / 60,
                readingMinutes: daily.filter {
                    $0.type == .activity && $0.activityType == .storyTime
                }.compactMap(\.duration).reduce(0, +) / 60,
                indoorMinutes: daily.filter {
                    $0.type == .activity && $0.activityType == .indoorPlay
                }.compactMap(\.duration).reduce(0, +) / 60,
                outdoorMinutes: daily.filter {
                    $0.type == .activity && $0.activityType == .outdoorPlay
                }.compactMap(\.duration).reduce(0, +) / 60,
                screenMinutes: daily.filter {
                    $0.type == .activity && $0.activityType == .screenTime
                }.compactMap(\.duration).reduce(0, +) / 60,
                baths: daily.filter {
                    $0.type == .activity && $0.activityType == .bath
                }.count,
                brushTeeth: daily.filter {
                    $0.type == .activity && $0.activityType == .brushTeeth
                }.count,
                medicine: daily.filter { $0.type == .medicine }.count,
                custom: daily.filter { $0.type == .custom }.count
            )
        }
    }

    static func predictionAccuracy(
        records: [SleepPredictionRecord],
        range: Range<Date>
    ) -> [PredictionErrorSummary] {
        records.compactMap { record in
            guard let error = record.errorMinutes,
                  let actual = record.actualSleepStart,
                  range.contains(actual) else { return nil }
            return PredictionErrorSummary(
                id: record.id,
                date: actual,
                errorMinutes: -error,
                napIndex: record.napIndex,
                confidence: record.confidenceLabel.displayName,
                insideWindow: record.wasInsidePredictedWindow == true,
                predictedStart: record.predictedStart,
                actualStart: actual
            )
        }.sorted { $0.date < $1.date }
    }

    static func feedToSleepIntervals(
        events: [BabyEvent],
        range: Range<Date>
    ) -> [Double] {
        let sessions = careSessions(events: events, range: range)
        let sleeps = events.filter {
            $0.type == .sleep && range.contains($0.startDate)
        }.sorted { $0.startDate < $1.startDate }
        return sleeps.compactMap { sleep in
            guard let care = sessions.last(where: { $0 <= sleep.startDate }) else { return nil }
            let minutes = sleep.startDate.timeIntervalSince(care) / 60
            return (0...240).contains(minutes) ? minutes : nil
        }
    }

    static func percentageChange(current: Double, previous: Double) -> Double? {
        guard previous != 0 else { return current == 0 ? 0 : nil }
        return (current - previous) / abs(previous) * 100
    }

    static func trendDirection(
        current: Double,
        previous: Double,
        flatThresholdPercent: Double = 5
    ) -> InsightTrendDirection {
        guard let change = percentageChange(current: current, previous: previous) else { return .unknown }
        if abs(change) < flatThresholdPercent { return .flat }
        return change > 0 ? .up : .down
    }

    static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let mean = average(values) else { return nil }
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
    }

    static func interquartileRange(_ values: [Double]) -> Double? {
        guard values.count >= 4 else { return nil }
        let sorted = values.sorted()
        return percentile(sorted, 0.75) - percentile(sorted, 0.25)
    }

    private static func dates(in range: Range<Date>, calendar: Calendar) -> [Date] {
        var dates = [Date]()
        var day = calendar.startOfDay(for: range.lowerBound)
        while day < range.upperBound {
            dates.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? range.upperBound
        }
        return dates
    }

    private static func sleepBucketDate(for event: BabyEvent, calendar: Calendar) -> Date {
        guard event.sleepKind == .nightSleep else { return calendar.startOfDay(for: event.startDate) }
        let hour = calendar.component(.hour, from: event.startDate)
        let date = hour < 12
            ? calendar.date(byAdding: .day, value: -1, to: event.startDate) ?? event.startDate
            : event.startDate
        return calendar.startOfDay(for: date)
    }

    private static func careSessions(events: [BabyEvent], range: Range<Date>) -> [Date] {
        let dates = events.filter {
            ($0.type == .feed || $0.type == .nursing) && range.contains($0.startDate)
        }.map(\.startDate).sorted()
        var sessions = [Date]()
        for date in dates {
            if let previous = sessions.last, date.timeIntervalSince(previous) < 45 * 60 {
                continue
            }
            sessions.append(date)
        }
        return sessions
    }

    private static func groupedNursingSessions(events: [BabyEvent], range: Range<Date>) -> [Date] {
        let dates = events.filter {
            $0.type == .nursing && range.contains($0.startDate)
        }.map(\.startDate).sorted()
        var sessions = [Date]()
        for date in dates {
            if let previous = sessions.last, date.timeIntervalSince(previous) < 45 * 60 {
                continue
            }
            sessions.append(date)
        }
        return sessions
    }

    private static func nightSleepScore(
        totalSleepMinutes: Double,
        wakeEventCount: Int,
        totalWakeMinutes: Double,
        longestStretchMinutes: Double,
        sleepWindowMinutes: Double
    ) -> Int {
        let durationScore: Double
        if totalSleepMinutes < 9 * 60 {
            durationScore = 45 * clamped(totalSleepMinutes / (9 * 60))
        } else if totalSleepMinutes <= 12 * 60 {
            durationScore = 45
        } else {
            durationScore = max(30, 45 - ((totalSleepMinutes - 12 * 60) / 60) * 3)
        }

        let wakeCountScore = max(0, 20 - Double(wakeEventCount) * 5)
        let awakeTimeScore = max(0, 15 - totalWakeMinutes / 4)
        let efficiency = sleepWindowMinutes > 0 ? totalSleepMinutes / sleepWindowMinutes : 0
        let efficiencyScore = 10 * clamped((efficiency - 0.7) / 0.25)
        let stretchScore = 10 * clamped(longestStretchMinutes / (6 * 60))
        let total = durationScore + wakeCountScore + awakeTimeScore + efficiencyScore + stretchScore
        return Int(clamped(total, lower: 0, upper: 100).rounded())
    }

    private static func clamped(
        _ value: Double,
        lower: Double = 0,
        upper: Double = 1
    ) -> Double {
        min(upper, max(lower, value))
    }

    private static func durationBuckets(_ values: [Double]) -> [CategoryValue] {
        [
            CategoryValue(category: "<30m", value: Double(values.filter { $0 < 30 }.count)),
            CategoryValue(category: "30-45m", value: Double(values.filter { (30..<45).contains($0) }.count)),
            CategoryValue(category: "45-60m", value: Double(values.filter { (45..<60).contains($0) }.count)),
            CategoryValue(category: "60-90m", value: Double(values.filter { (60..<90).contains($0) }.count)),
            CategoryValue(category: "90m+", value: Double(values.filter { $0 >= 90 }.count))
        ]
    }

    private static func intervalBuckets(_ values: [Double]) -> [CategoryValue] {
        [
            CategoryValue(category: "0-15m", value: Double(values.filter { $0 < 15 }.count)),
            CategoryValue(category: "15-30m", value: Double(values.filter { (15..<30).contains($0) }.count)),
            CategoryValue(category: "30-60m", value: Double(values.filter { (30..<60).contains($0) }.count)),
            CategoryValue(category: "60m+", value: Double(values.filter { $0 >= 60 }.count))
        ]
    }

    private static func hourBuckets(events: [BabyEvent], calendar: Calendar) -> [CategoryValue] {
        let ranges = [(0, 6, "12-6a"), (6, 12, "6a-12p"), (12, 18, "12-6p"), (18, 24, "6p-12a")]
        return ranges.map { lower, upper, label in
            CategoryValue(
                category: label,
                value: Double(events.filter {
                    (lower..<upper).contains(calendar.component(.hour, from: $0.startDate))
                }.count)
            )
        }
    }

    private static func circularTimeAverage(
        _ minutes: [Double],
        rollsAfterMidnight: Bool = true
    ) -> Double? {
        guard !minutes.isEmpty else { return nil }
        let adjusted = rollsAfterMidnight ? minutes.map { $0 < 12 * 60 ? $0 + 24 * 60 : $0 } : minutes
        guard let mean = average(adjusted) else { return nil }
        return mean.truncatingRemainder(dividingBy: 24 * 60)
    }

    private static func accuracyValues(_ errors: [PredictionErrorSummary]) -> (
        count: Int,
        inside: Double?,
        meanAbsolute: Double?,
        medianAbsolute: Double?,
        bias: Double?
    ) {
        guard !errors.isEmpty else { return (0, nil, nil, nil, nil) }
        let values = errors.map(\.errorMinutes)
        return (
            errors.count,
            Double(errors.filter(\.insideWindow).count) / Double(errors.count) * 100,
            average(values.map(abs)),
            median(values.map(abs)),
            average(values)
        )
    }

    private static func groupedAccuracy(
        _ values: [PredictionErrorSummary],
        key: (PredictionErrorSummary) -> String
    ) -> [CategoryValue] {
        Dictionary(grouping: values, by: key).map { label, items in
            CategoryValue(category: label, value: average(items.map { abs($0.errorMinutes) }) ?? 0)
        }.sorted { $0.category < $1.category }
    }

    private static func groupedInsidePercentage(
        _ values: [PredictionErrorSummary],
        key: (PredictionErrorSummary) -> String
    ) -> [CategoryValue] {
        Dictionary(grouping: values, by: key).map { label, items in
            CategoryValue(
                category: label,
                value: Double(items.filter(\.insideWindow).count) / Double(items.count) * 100
            )
        }.sorted { $0.category < $1.category }
    }

    private static func metric(
        _ title: String,
        _ current: Double?,
        _ previous: Double?,
        compare: Bool = false,
        format: (Double) -> String,
        icon: String,
        interpretation: String
    ) -> InsightMetric {
        let change: String?
        let direction: InsightTrendDirection
        if compare, let current, let previous, let percent = percentageChange(current: current, previous: previous) {
            change = "\(percent >= 0 ? "+" : "")\(Int(percent.rounded()))%"
            direction = trendDirection(current: current, previous: previous)
        } else {
            change = nil
            direction = .unknown
        }
        return InsightMetric(
            title: title,
            value: current.map(format) ?? "-",
            change: change,
            direction: direction,
            interpretation: interpretation,
            systemImage: icon
        )
    }

    private static func makeTrend(
        name: String,
        current: Double?,
        previous: Double?,
        format: (Double) -> String,
        subject: String,
        differenceUnit: String? = nil
    ) -> InsightTrend? {
        guard let current, let previous else { return nil }
        let direction = trendDirection(current: current, previous: previous)
        let percent = percentageChange(current: current, previous: previous)
        let difference = current - previous
        let wording: String
        if direction == .flat {
            wording = "\(subject) is similar to the previous period."
        } else if let differenceUnit {
            wording = "\(subject) shifted about \(Int(abs(difference).rounded())) \(differenceUnit) \(difference > 0 ? "later" : "earlier")."
        } else {
            wording = "\(subject) is \(percent.map { "\(Int(abs($0).rounded()))% " } ?? "")\(difference > 0 ? "higher" : "lower") than the previous period."
        }
        return InsightTrend(
            metricName: name,
            currentValueDescription: format(current),
            previousValueDescription: format(previous),
            percentChange: percent,
            direction: direction,
            interpretation: wording,
            significance: significance(percent)
        )
    }

    private static func wakeObservations(
        profileName: String,
        current: [WakeWindowSummary],
        previous: [WakeWindowSummary]
    ) -> [InsightTrend] {
        let grouped = Dictionary(grouping: current, by: \.napIndex)
        let variability = grouped.compactMap { index, values -> (Int, Double)? in
            standardDeviation(values.map(\.minutes)).map { (index, $0) }
        }
        var results = compactTrends([
            makeTrend(
                name: "Wake-window trend",
                current: average(current.map(\.minutes)),
                previous: average(previous.map(\.minutes)),
                format: duration,
                subject: "Average wake windows"
            )
        ])
        if let most = variability.min(by: { $0.1 < $1.1 }),
           let mean = average(grouped[most.0, default: []].map(\.minutes)) {
            results.append(InsightTrend(
                metricName: "Most consistent",
                currentValueDescription: duration(mean),
                direction: .flat,
                interpretation: "\(profileName)'s \(wakeWindowLabel(most.0)) is the most consistent at about \(duration(mean)).",
                significance: .medium
            ))
        }
        if let first = average(grouped[1, default: []].map(\.minutes)),
           let later = average(grouped.filter { (2...4).contains($0.key) }.flatMap(\.value).map(\.minutes)) {
            results.append(InsightTrend(
                metricName: "First vs later windows",
                currentValueDescription: duration(first),
                direction: first < later ? .down : .up,
                interpretation: "First wake windows are usually \(first < later ? "shorter" : "longer") than later daytime windows.",
                significance: .medium
            ))
        }
        return Array(results.prefix(4))
    }

    private static func sideBalanceTrend(profileName: String, left: Double, right: Double) -> InsightTrend? {
        guard left + right > 0 else { return nil }
        let difference = abs(left - right) / (left + right)
        let balanced = difference < 0.15
        return InsightTrend(
            metricName: "Nursing balance",
            currentValueDescription: "\(duration(left)) left / \(duration(right)) right",
            direction: balanced ? .flat : (right > left ? .up : .down),
            interpretation: balanced
                ? "Left and right nursing time is balanced for \(profileName)'s recent pattern."
                : "\(right > left ? "Right" : "Left") side has been used more often recently.",
            significance: balanced ? .low : .medium
        )
    }

    private static func feedSleepTrend(profileName: String, intervals: [Double]) -> InsightTrend? {
        guard !intervals.isEmpty else { return nil }
        let buckets = intervalBuckets(intervals)
        guard let common = buckets.max(by: { $0.value < $1.value }) else { return nil }
        return InsightTrend(
            metricName: "Care before sleep",
            currentValueDescription: common.category,
            direction: .flat,
            interpretation: "\(profileName) most often falls asleep \(common.category) after a feed or nursing session in this period.",
            significance: .medium
        )
    }

    private static func diaperTimeTrend(
        profileName: String,
        events: [BabyEvent],
        calendar: Calendar
    ) -> InsightTrend? {
        let dirty = events.filter { $0.diaperKind == .dirty || $0.diaperKind == .both }
        guard !dirty.isEmpty else { return nil }
        let morning = dirty.filter { calendar.component(.hour, from: $0.startDate) < 12 }.count
        let wording = morning * 2 >= dirty.count ? "morning" : "afternoon or evening"
        return InsightTrend(
            metricName: "Dirty diaper timing",
            currentValueDescription: "\(dirty.count) logs",
            direction: .flat,
            interpretation: "\(profileName)'s dirty diaper logs were more common in the \(wording) during this period.",
            significance: .low
        )
    }

    private static func readingDaysTrend(
        profileName: String,
        activities: [DailyActivitySummary]
    ) -> InsightTrend? {
        guard !activities.isEmpty else { return nil }
        let days = activities.filter { $0.readingMinutes > 0 }.count
        return InsightTrend(
            metricName: "Reading days",
            currentValueDescription: "\(days) of \(activities.count) days",
            direction: .flat,
            interpretation: "Reading was logged on \(days) of the last \(activities.count) days for \(profileName).",
            significance: .low
        )
    }

    private static func bathTimeTrend(
        profileName: String,
        events: [BabyEvent],
        calendar: Calendar
    ) -> InsightTrend? {
        guard !events.isEmpty else { return nil }
        let evening = events.filter { calendar.component(.hour, from: $0.startDate) >= 17 }.count
        return InsightTrend(
            metricName: "Bath timing",
            currentValueDescription: "\(events.count) baths",
            direction: .flat,
            interpretation: evening * 2 >= events.count
                ? "Baths usually happened in the evening for \(profileName)."
                : "Bath timing was spread across the day for \(profileName).",
            significance: .low
        )
    }

    private static func predictionObservations(
        profileName: String,
        current: [PredictionErrorSummary],
        previous: [PredictionErrorSummary]
    ) -> [InsightTrend] {
        let values = accuracyValues(current)
        let previousValues = accuracyValues(previous)
        var results = compactTrends([
            makeTrend(
                name: "Inside prediction window",
                current: values.inside,
                previous: previousValues.inside,
                format: percent,
                subject: "Prediction window accuracy"
            ),
            makeTrend(
                name: "Prediction error",
                current: values.meanAbsolute,
                previous: previousValues.meanAbsolute,
                format: duration,
                subject: "Mean absolute prediction error"
            )
        ])
        if let bias = values.bias {
            results.append(InsightTrend(
                metricName: "Timing bias",
                currentValueDescription: signedMinutes(bias),
                direction: bias < -2 ? .down : (bias > 2 ? .up : .flat),
                interpretation: abs(bias) < 2
                    ? "Predictions are balanced between early and late."
                    : "The model is predicting sleep about \(Int(abs(bias).rounded())) minutes \(bias < 0 ? "early" : "late") on average.",
                significance: abs(bias) >= 10 ? .high : .medium
            ))
        }
        let byNap = groupedAccuracy(current, key: { napLabel($0.napIndex) })
        if let hardest = byNap.max(by: { $0.value < $1.value }) {
            results.append(InsightTrend(
                metricName: "Hardest nap",
                currentValueDescription: hardest.category,
                direction: .unknown,
                interpretation: "\(hardest.category) is the hardest to predict right now for \(profileName), with \(duration(hardest.value)) mean absolute error.",
                significance: .medium
            ))
        }
        return Array(results.prefix(4))
    }

    private static func compactTrends(_ values: [InsightTrend?]) -> [InsightTrend] {
        values.compactMap { $0 }
    }

    private static func significance(_ percent: Double?) -> InsightSignificance {
        guard let percent else { return .low }
        return switch abs(percent) {
        case 20...: .high
        case 8..<20: .medium
        default: .low
        }
    }

    private static func napLabel(_ index: Int) -> String {
        index == 5 ? "Pre-bed" : "Nap \(index)"
    }

    private static func wakeWindowLabel(_ index: Int) -> String {
        switch index {
        case 1:
            "wake window before the first nap"
        case 2:
            "wake window before the second nap"
        case 3:
            "wake window before the third nap"
        case 4:
            "wake window before the fourth nap"
        case 5:
            "pre-bed wake window"
        default:
            "wake window before nap \(index)"
        }
    }

    private static func duration(_ minutes: Double) -> String {
        DurationFormatting.string(seconds: minutes * 60)
    }

    private static func clock(_ minutes: Double) -> String {
        let value = Int(minutes.rounded()).positiveModulo(24 * 60)
        let date = Calendar.current.date(
            from: DateComponents(hour: value / 60, minute: value % 60)
        ) ?? Date()
        return DateFormatting.time.string(from: date)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func ounces(_ value: Double) -> String {
        String(format: "%.1f oz", value)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func whole(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private static func signedMinutes(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(Int(value.rounded()))m"
    }

    private static func measurementChange(
        _ current: Double?,
        _ previous: Double?,
        unit: String
    ) -> String? {
        guard let current, let previous else { return nil }
        let difference = current - previous
        return "\(difference >= 0 ? "+" : "")\(difference.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = percentile * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
