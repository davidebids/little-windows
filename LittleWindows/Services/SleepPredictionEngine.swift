import Foundation

struct SleepPrediction: Hashable {
    var predictedStart: Date
    var predictedWindowStart: Date
    var predictedWindowEnd: Date
    var predictionKind: PredictionKind
    var confidence: Double
    var confidenceLabel: ConfidenceLabel
    var explanation: [String]
    var contributingFactors: [PredictionFactorValue]
    var napIndex: Int
}

struct WakeWindowSample: Hashable {
    var minutes: Double
    var napIndex: Int
    var date: Date
    var weight: Double
}

struct WeightedValue: Hashable {
    var value: Double
    var weight: Double
}

struct WakeWindowStatistics: Hashable {
    var weightedMean: Double
    var weightedMedian: Double
    var upperQuartile: Double
    var standardDeviation: Double
    var interquartileRange: Double?
    var trendMinutes: Double
    var sampleCount: Int
    var effectiveSampleCount: Double
}

struct PredictionSettings {
    var feedAdjustmentEnabled: Bool
    var nursingAdjustmentEnabled: Bool
    var bedtimePredictionEnabled: Bool
    var customBaselineMinimum: Double?
    var customBaselineMaximum: Double?

    static let `default` = PredictionSettings(
        feedAdjustmentEnabled: true,
        nursingAdjustmentEnabled: true,
        bedtimePredictionEnabled: true,
        customBaselineMinimum: nil,
        customBaselineMaximum: nil
    )
}

enum SleepPredictionEngine {
    static let algorithmVersion = "LittleWindowsSleep-v3"

    static func predict(
        profile: BabyProfile,
        events: [BabyEvent],
        records: [SleepPredictionRecord] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        settings: PredictionSettings = .default
    ) -> SleepPrediction? {
        if events.contains(where: { $0.type == .sleep && $0.isTimerRunning }) {
            return nil
        }
        let events = events.filter { !$0.isTimerDraft }
        let completedSleeps = events
            .filter { $0.type == .sleep && $0.endDate != nil && $0.startDate <= now }
            .sorted { $0.startDate < $1.startDate }
        guard let lastSleep = completedSleeps.last, let lastSleepEnd = lastSleep.endDate else {
            return nil
        }

        let napIndex = nextNapIndex(events: events, date: now, calendar: calendar)
        let allSamples = wakeWindowSamples(from: completedSleeps, now: now, calendar: calendar)
            .filter { $0.napIndex == napIndex }
        let samples = preferredPredictionSamples(allSamples, now: now, calendar: calendar)
        let clipped = clipOutliers(samples)
        let stats = statistics(for: clipped)
        let baseline = ageBaselineMinutes(
            birthDate: profile.birthDate,
            date: now,
            customMinimum: settings.customBaselineMinimum,
            customMaximum: settings.customBaselineMaximum,
            calendar: calendar
        )
        let baselineCenter = (baseline.lowerBound + baseline.upperBound) / 2

        let personalCenter = stats.map(planningWakeWindowMinutes) ?? baselineCenter
        let effectiveSampleCount = stats?.effectiveSampleCount ?? 0
        let personalWeight: Double
        switch effectiveSampleCount {
        case ..<3: personalWeight = 0.20
        case 3..<10: personalWeight = 0.45
        default: personalWeight = 0.65
        }

        var predictedWakeMinutes = baselineCenter * (1 - personalWeight) + personalCenter * personalWeight
        var confidence = confidenceScore(
            sampleCount: Int(effectiveSampleCount.rounded(.down)),
            variability: stats?.standardDeviation
        )
        var explanations = [String]()
        var factors = [PredictionFactorValue]()

        if let stats {
            explanations.append(
                "\(profile.name)'s recent wake-window median for nap \(napIndex) is \(minutesText(stats.weightedMedian)); the planning target is \(minutesText(personalCenter))."
            )
            factors.append(PredictionFactorValue(
                name: "Personal history",
                valueDescription: "\(stats.sampleCount) matching samples",
                impactMinutes: personalCenter - baselineCenter,
                confidenceImpact: min(0.24, stats.effectiveSampleCount * 0.02),
                explanation: "Recent matching wake windows are weighted more heavily than older developmental stages."
            ))
            if personalCenter > stats.weightedMedian + 2 {
                factors.append(PredictionFactorValue(
                    name: "Later-side buffer",
                    valueDescription: "P75 \(minutesText(stats.upperQuartile))",
                    impactMinutes: personalCenter - stats.weightedMedian,
                    confidenceImpact: 0,
                    explanation: "When recent wake windows vary, the prediction leans toward the later side instead of the earliest reasonable time."
                ))
            }
            if stats.standardDeviation >= 25 {
                explanations.append(
                    "Recent matching wake windows varied by about \(Int(stats.standardDeviation.rounded())) minutes, so the window is wider."
                )
            }
            if stats.sampleCount >= 6 {
                let trendAdjustment = min(12, max(-12, stats.trendMinutes * 0.3))
                if abs(trendAdjustment) >= 2 {
                    predictedWakeMinutes += trendAdjustment
                    explanations.append(
                        "Recent wake windows are trending \(trendAdjustment < 0 ? "shorter" : "longer"), adding a cautious \(Int(abs(trendAdjustment).rounded()))-minute adjustment."
                    )
                    factors.append(PredictionFactorValue(
                        name: "Developmental trend",
                        valueDescription: "\(Int(abs(stats.trendMinutes).rounded())) min recent shift",
                        impactMinutes: trendAdjustment,
                        confidenceImpact: 0,
                        explanation: "Only a small portion of the recent trend is applied to avoid chasing day-to-day noise."
                    ))
                }
            }
        } else {
            explanations.append(
                "There is not enough matching history yet, so this leans on the editable age-based baseline."
            )
        }

        let recentNapCutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let recentNapDurations = completedSleeps
            .filter { $0.sleepKind == .nap && $0.startDate >= recentNapCutoff }
            .compactMap(\.duration)
            .map { $0 / 60 }
        if let lastDuration = lastSleep.duration.map({ $0 / 60 }), lastSleep.sleepKind == .nap {
            let adjustment = napDurationAdjustment(
                lastNapMinutes: lastDuration,
                recentNapMinutes: recentNapDurations
            )
            predictedWakeMinutes += adjustment
            if abs(adjustment) >= 1 {
                let direction = adjustment < 0 ? "earlier" : "later"
                explanations.append(
                    "The last nap was \(minutesText(lastDuration)); the next window moved \(Int(abs(adjustment).rounded())) minutes \(direction)."
                )
                factors.append(PredictionFactorValue(
                    name: "Last nap",
                    valueDescription: minutesText(lastDuration),
                    impactMinutes: adjustment,
                    confidenceImpact: -0.02,
                    explanation: "The previous nap length changes near-term sleep pressure."
                ))
            }
        }

        let bias = PredictionTuningService.conservativeBiasCorrection(
            records: records,
            napIndex: napIndex
        )
        predictedWakeMinutes += bias
        if abs(bias) >= 2 {
            explanations.append(
                "Recent accuracy moved this nap \(Int(abs(bias).rounded())) minutes \(bias < 0 ? "earlier" : "later")."
            )
            factors.append(PredictionFactorValue(
                name: "Accuracy tuning",
                valueDescription: "Conservative recent bias",
                impactMinutes: bias,
                confidenceImpact: 0,
                explanation: "Past early or late errors are corrected gradually to avoid overfitting."
            ))
        }

        let provisionalStart = lastSleepEnd.addingTimeInterval(predictedWakeMinutes * 60)
        let typicalBedtimes = completedSleeps
            .filter {
                $0.sleepKind == .nightSleep &&
                calendar.component(.hour, from: $0.startDate) >= 17
            }
            .suffix(14)
            .map(\.startDate)
        let bedtimeDate = circularTypicalTime(for: typicalBedtimes, on: now, calendar: calendar)
        let napsToday = events.filter {
            $0.type == .sleep &&
            $0.sleepKind == .nap &&
            calendar.isDate($0.startDate, inSameDayAs: now)
        }.count
        let typicalNapCount = typicalDailyNapCount(events: completedSleeps, now: now, calendar: calendar)
        var kind: PredictionKind = .nap
        var finalStart = provisionalStart

        if settings.bedtimePredictionEnabled,
           let bedtimeDate,
           provisionalStart >= bedtimeDate.addingTimeInterval(-45 * 60),
           Double(napsToday) >= max(1, typicalNapCount - 0.5) {
            kind = .bedtime
            finalStart = max(provisionalStart, bedtimeDate.addingTimeInterval(-30 * 60))
            explanations.append(
                "Today already has \(napsToday) naps, and this falls near \(profile.name)'s usual bedtime, so it looks more like bedtime."
            )
            factors.append(PredictionFactorValue(
                name: "Bedtime pattern",
                valueDescription: DateFormatting.time.string(from: bedtimeDate),
                impactMinutes: finalStart.timeIntervalSince(provisionalStart) / 60,
                confidenceImpact: typicalBedtimes.count >= 5 ? 0.08 : 0,
                explanation: "Recent night-sleep starts help distinguish a late nap from bedtime."
            ))
        }

        let recentCareEvent = events
            .filter {
                ($0.type == .feed && settings.feedAdjustmentEnabled) ||
                ($0.type == .nursing && settings.nursingAdjustmentEnabled)
            }
            .filter { $0.startDate <= now && $0.startDate >= now.addingTimeInterval(-90 * 60) }
            .max { $0.startDate < $1.startDate }
        if let recentCareEvent {
            confidence += 0.03
            explanations.append(
                "A recent \(recentCareEvent.type.displayName.lowercased()) log slightly increased confidence; it did not set the sleep time."
            )
            factors.append(PredictionFactorValue(
                name: "Recent care timing",
                valueDescription: recentCareEvent.type.displayName,
                impactMinutes: 0,
                confidenceImpact: 0.03,
                explanation: "Feed and nursing timing are soft confidence signals only."
            ))
        }

        if finalStart < now.addingTimeInterval(-15 * 60) {
            confidence -= 0.18
            explanations.append("The expected time has already passed, which lowers confidence.")
        }

        confidence = min(0.95, max(0.15, confidence))
        let label = confidenceLabel(for: confidence)
        let variability = stats?.standardDeviation ?? 35
        let halfWindow = windowHalfWidthMinutes(confidence: confidence, variability: variability)

        if effectiveSampleCount < 5 {
            explanations.append(
                "Confidence is low-to-medium because there are only \(Int(effectiveSampleCount.rounded())) effective recent samples."
            )
        }
        explanations.append("This is a planning aid based on local logs, not medical advice.")

        return SleepPrediction(
            predictedStart: finalStart,
            predictedWindowStart: finalStart.addingTimeInterval(-halfWindow * 60),
            predictedWindowEnd: finalStart.addingTimeInterval(halfWindow * 60),
            predictionKind: kind,
            confidence: confidence,
            confidenceLabel: label,
            explanation: explanations,
            contributingFactors: factors,
            napIndex: napIndex
        )
    }

    static func wakeWindowSamples(
        from sleeps: [BabyEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WakeWindowSample] {
        let sorted = sleeps
            .filter { $0.type == .sleep && $0.endDate != nil }
            .sorted { $0.startDate < $1.startDate }
        guard sorted.count >= 2 else { return [] }

        var napCountsByDay = [Date: Int]()
        var napIndexesByID = [UUID: Int]()
        for sleep in sorted where sleep.sleepKind == .nap {
            let day = calendar.startOfDay(for: sleep.startDate)
            let napIndex = min(4, napCountsByDay[day, default: 0] + 1)
            napCountsByDay[day] = napIndex
            napIndexesByID[sleep.id] = napIndex
        }

        return zip(sorted, sorted.dropFirst()).compactMap { previous, next in
            guard let previousEnd = previous.endDate, next.startDate > previousEnd else { return nil }
            let minutes = next.startDate.timeIntervalSince(previousEnd) / 60
            guard (20...480).contains(minutes) else { return nil }
            let ageDays = max(0, calendar.dateComponents([.day], from: next.startDate, to: now).day ?? 0)
            let weight: Double
            switch ageDays {
            case 0...3: weight = 1.0
            case 4...7: weight = 0.80
            case 8...14: weight = 0.60
            case 15...30: weight = 0.30
            case 31...60: weight = 0.12
            default: weight = 0.04
            }
            let index = next.sleepKind == .nightSleep
                ? 5
                : napIndexesByID[next.id, default: 1]
            return WakeWindowSample(minutes: minutes, napIndex: index, date: next.startDate, weight: weight)
        }
    }

    static func napIndex(for sleep: BabyEvent, among sleeps: [BabyEvent], calendar: Calendar = .current) -> Int {
        guard sleep.sleepKind != .nightSleep else { return 5 }
        let earlierNaps = sleeps.filter {
            $0.id != sleep.id &&
            $0.sleepKind == .nap &&
            $0.startDate < sleep.startDate &&
            calendar.isDate($0.startDate, inSameDayAs: sleep.startDate)
        }.count
        return min(4, earlierNaps + 1)
    }

    static func nextNapIndex(events: [BabyEvent], date: Date, calendar: Calendar = .current) -> Int {
        min(4, events.filter {
            $0.type == .sleep &&
            $0.sleepKind == .nap &&
            $0.startDate < date &&
            calendar.isDate($0.startDate, inSameDayAs: date)
        }.count + 1)
    }

    static func weightedMean(_ values: [WeightedValue]) -> Double? {
        let denominator = values.reduce(0) { $0 + max(0, $1.weight) }
        guard denominator > 0 else { return nil }
        return values.reduce(0) { $0 + $1.value * max(0, $1.weight) } / denominator
    }

    static func weightedMedian(_ values: [WeightedValue]) -> Double? {
        let sorted = values.filter { $0.weight > 0 }.sorted { $0.value < $1.value }
        let totalWeight = sorted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        var cumulative = 0.0
        for item in sorted {
            cumulative += item.weight
            if cumulative >= totalWeight / 2 { return item.value }
        }
        return sorted.last?.value
    }

    static func clipOutliers(_ samples: [WakeWindowSample]) -> [WakeWindowSample] {
        guard samples.count >= 4 else { return samples }
        let values = samples.map(\.minutes).sorted()
        let q1 = percentile(values, 0.25)
        let q3 = percentile(values, 0.75)
        let iqr = q3 - q1
        let lower = q1 - 1.5 * iqr
        let upper = q3 + 1.5 * iqr
        return samples.filter { (lower...upper).contains($0.minutes) }
    }

    static func preferredPredictionSamples(
        _ samples: [WakeWindowSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WakeWindowSample] {
        let cutoff = calendar.date(byAdding: .day, value: -45, to: now) ?? .distantPast
        let recent = samples.filter { $0.date >= cutoff }
        return recent.count >= 5 ? recent : samples
    }

    static func statistics(for samples: [WakeWindowSample]) -> WakeWindowStatistics? {
        guard !samples.isEmpty else { return nil }
        let weighted = samples.map { WeightedValue(value: $0.minutes, weight: $0.weight) }
        guard let mean = weightedMean(weighted), let median = weightedMedian(weighted) else { return nil }
        let effectiveSampleCount = samples.reduce(0) { $0 + max(0, $1.weight) }
        let variance = samples.reduce(0) {
            $0 + pow($1.minutes - mean, 2) * max(0, $1.weight)
        } / max(effectiveSampleCount, 0.001)
        let sorted = samples.map(\.minutes).sorted()
        let lowerQuartile = samples.count >= 4 ? percentile(sorted, 0.25) : mean
        let upperQuartile = samples.count >= 4 ? percentile(sorted, 0.75) : max(mean, median)
        let iqr = samples.count >= 4 ? upperQuartile - lowerQuartile : nil
        let chronological = samples.sorted { $0.date < $1.date }
        let split = max(1, chronological.count / 2)
        let older = chronological.prefix(split).map {
            WeightedValue(value: $0.minutes, weight: $0.weight)
        }
        let newer = chronological.suffix(from: split).map {
            WeightedValue(value: $0.minutes, weight: $0.weight)
        }
        let oldMean = weightedMean(older) ?? mean
        let newMean = weightedMean(newer) ?? oldMean
        return WakeWindowStatistics(
            weightedMean: mean,
            weightedMedian: median,
            upperQuartile: upperQuartile,
            standardDeviation: sqrt(variance),
            interquartileRange: iqr,
            trendMinutes: newMean - oldMean,
            sampleCount: samples.count,
            effectiveSampleCount: effectiveSampleCount
        )
    }

    static func planningWakeWindowMinutes(_ stats: WakeWindowStatistics) -> Double {
        let laterSideGap = max(0, stats.upperQuartile - stats.weightedMedian)
        let variabilityBuffer = min(24, max(laterSideGap * 0.75, stats.standardDeviation * 0.22))
        return stats.weightedMedian + variabilityBuffer
    }

    static func confidenceScore(sampleCount: Int, variability: Double?) -> Double {
        let sampleScore: Double
        switch sampleCount {
        case 0: sampleScore = 0.30
        case 1...4: sampleScore = 0.42 + Double(sampleCount) * 0.035
        case 5...14: sampleScore = 0.60 + Double(sampleCount - 5) * 0.018
        default: sampleScore = 0.80
        }
        let variabilityPenalty = min(0.25, max(0, ((variability ?? 35) - 12) / 120))
        return min(0.92, max(0.15, sampleScore - variabilityPenalty))
    }

    static func napDurationAdjustment(lastNapMinutes: Double, recentNapMinutes: [Double]) -> Double {
        if recentNapMinutes.count >= 5 {
            let sorted = recentNapMinutes.sorted()
            let q1 = percentile(sorted, 0.25)
            let q3 = percentile(sorted, 0.75)
            if lastNapMinutes < q1 { return max(-20, -(q1 - lastNapMinutes) * 0.35) }
            if lastNapMinutes > q3 { return min(15, (lastNapMinutes - q3) * 0.25) }
            return 0
        }
        switch lastNapMinutes {
        case ..<30: return -15
        case 30..<45: return -8
        case 90...: return 10
        default: return 0
        }
    }

    static func ageBaselineMinutes(
        birthDate: Date,
        date: Date,
        customMinimum: Double?,
        customMaximum: Double?,
        calendar: Calendar = .current
    ) -> ClosedRange<Double> {
        if let customMinimum, let customMaximum, customMinimum < customMaximum {
            return customMinimum...customMaximum
        }
        let days = max(0, calendar.dateComponents([.day], from: birthDate, to: date).day ?? 0)
        let months = Double(days) / 30.4375
        switch months {
        case ..<3: return 45...90
        case ..<4: return 75...120
        case ..<5: return 105...165
        case ..<7: return 120...180
        case ..<10: return 150...210
        default: return 180...240
        }
    }

    static func confidenceLabel(for confidence: Double) -> ConfidenceLabel {
        if confidence >= 0.75 { return .high }
        if confidence >= 0.50 { return .medium }
        return .low
    }

    private static func windowHalfWidthMinutes(confidence: Double, variability: Double) -> Double {
        let base: Double = confidence >= 0.75 ? 15 : (confidence >= 0.50 ? 25 : 40)
        return min(50, max(base, variability * 0.8))
    }

    private static func typicalDailyNapCount(
        events: [BabyEvent],
        now: Date,
        calendar: Calendar
    ) -> Double {
        let start = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let naps = events.filter { $0.sleepKind == .nap && $0.startDate >= start }
        let grouped = Dictionary(grouping: naps) { calendar.startOfDay(for: $0.startDate) }
        guard !grouped.isEmpty else { return 3 }
        return Double(grouped.values.reduce(0) { $0 + $1.count }) / Double(grouped.count)
    }

    private static func circularTypicalTime(
        for dates: [Date],
        on targetDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard !dates.isEmpty else { return nil }
        let minutes = dates.map {
            Double((calendar.component(.hour, from: $0) * 60) + calendar.component(.minute, from: $0))
        }
        let shifted = minutes.map { $0 < 12 * 60 ? $0 + 24 * 60 : $0 }
        let average = shifted.reduce(0, +) / Double(shifted.count)
        let normalized = Int(average.rounded()) % (24 * 60)
        return calendar.date(
            bySettingHour: normalized / 60,
            minute: normalized % 60,
            second: 0,
            of: targetDate
        )
    }

    private static func percentile(_ sortedValues: [Double], _ percentile: Double) -> Double {
        guard let first = sortedValues.first else { return 0 }
        guard sortedValues.count > 1 else { return first }
        let position = percentile * Double(sortedValues.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sortedValues[lower] }
        let fraction = position - Double(lower)
        return sortedValues[lower] * (1 - fraction) + sortedValues[upper] * fraction
    }

    private static func minutesText(_ minutes: Double) -> String {
        DurationFormatting.string(seconds: minutes * 60)
    }
}
