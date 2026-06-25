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

enum SleepPressureBand: String, Hashable, CaseIterable {
    case learning
    case low
    case building
    case ready
    case high

    var displayName: String {
        switch self {
        case .learning: "Learning"
        case .low: "Low"
        case .building: "Building"
        case .ready: "Ready"
        case .high: "High"
        }
    }

    var systemImage: String {
        switch self {
        case .learning: "sparkle.magnifyingglass"
        case .low: "cloud.sun.fill"
        case .building: "timer"
        case .ready: "checkmark.seal.fill"
        case .high: "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch self {
        case .learning: "Learning rhythm"
        case .low: "Pressure is low"
        case .building: "Pressure is building"
        case .ready: "Ready for sleep soon"
        case .high: "Sleep pressure is high"
        }
    }
}

struct SleepPressure: Hashable {
    var score: Double?
    var band: SleepPressureBand
    var confidence: Double
    var confidenceLabel: ConfidenceLabel
    var awakeMinutes: Double?
    var targetMinutes: Double?
    var readyAt: Date?
    var highAt: Date?
    var nextThresholdDate: Date?
    var explanation: [String]
    var contributingFactors: [PredictionFactorValue]

    var isActionable: Bool {
        score != nil && band != .learning
    }
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

enum BackwardsSleepPlanSegmentKind: String, Codable, Hashable {
    case wakeWindow
    case nap
    case bedtime
}

struct BackwardsSleepPlanSegment: Hashable, Identifiable {
    var kind: BackwardsSleepPlanSegmentKind
    var napIndex: Int?
    var startDate: Date
    var endDate: Date
    var durationMinutes: Double

    var id: String {
        [
            kind.rawValue,
            napIndex.map(String.init) ?? "none",
        ].joined(separator: "-")
    }
}

struct BackwardsSleepPlanAdjustment: Codable, Hashable, Identifiable {
    var kind: BackwardsSleepPlanSegmentKind
    var napIndex: Int?
    var startDate: Date
    var endDate: Date

    var id: String {
        [
            kind.rawValue,
            napIndex.map(String.init) ?? "none"
        ].joined(separator: "-")
    }

    init(
        kind: BackwardsSleepPlanSegmentKind,
        napIndex: Int?,
        startDate: Date,
        endDate: Date
    ) {
        self.kind = kind
        self.napIndex = napIndex
        self.startDate = startDate
        self.endDate = endDate
    }

    init(segment: BackwardsSleepPlanSegment) {
        self.init(
            kind: segment.kind,
            napIndex: segment.napIndex,
            startDate: segment.startDate,
            endDate: segment.endDate
        )
    }

    func matches(_ segment: BackwardsSleepPlanSegment) -> Bool {
        kind == segment.kind && napIndex == segment.napIndex
    }
}

struct BackwardsSleepPlan: Hashable {
    var targetBedtime: Date
    var generatedAt: Date
    var historyRange: BackwardsSleepPlanHistoryRange
    var plannedNapCount: Int
    var typicalNapCount: Int
    var sourceDayCount: Int
    var confidence: Double
    var confidenceLabel: ConfidenceLabel
    var segments: [BackwardsSleepPlanSegment]
    var segmentAdjustments: [BackwardsSleepPlanAdjustment] = []
    var explanation: [String]
}

struct ActiveSleepPlan: Codable, Equatable {
    var profileID: UUID
    var targetBedtime: Date
    var historyRangeRawValue: String
    var activatedAt: Date
    var generatedAt: Date
    var segmentAdjustments: [BackwardsSleepPlanAdjustment]

    var historyRange: BackwardsSleepPlanHistoryRange {
        BackwardsSleepPlanHistoryRange(rawValue: historyRangeRawValue) ?? .sevenDays
    }

    init(
        profileID: UUID,
        targetBedtime: Date,
        historyRangeRawValue: String,
        activatedAt: Date,
        generatedAt: Date,
        segmentAdjustments: [BackwardsSleepPlanAdjustment] = []
    ) {
        self.profileID = profileID
        self.targetBedtime = targetBedtime
        self.historyRangeRawValue = historyRangeRawValue
        self.activatedAt = activatedAt
        self.generatedAt = generatedAt
        self.segmentAdjustments = segmentAdjustments
    }

    private enum CodingKeys: String, CodingKey {
        case profileID
        case targetBedtime
        case historyRangeRawValue
        case activatedAt
        case generatedAt
        case segmentAdjustments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        targetBedtime = try container.decode(Date.self, forKey: .targetBedtime)
        historyRangeRawValue = try container.decode(String.self, forKey: .historyRangeRawValue)
        activatedAt = try container.decode(Date.self, forKey: .activatedAt)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        segmentAdjustments = try container.decodeIfPresent(
            [BackwardsSleepPlanAdjustment].self,
            forKey: .segmentAdjustments
        ) ?? []
    }
}

struct ActiveSleepPlanWakeAlert: Equatable {
    var profileID: UUID
    var activeSleepEventID: UUID
    var wakeByDate: Date
    var targetBedtime: Date

    var isPastDue: Bool {
        wakeByDate <= Date()
    }
}

enum BackwardsSleepPlanHistoryRange: String, CaseIterable, Identifiable, Hashable {
    case sevenDays
    case fourteenDays
    case thirtyDays
    case allAvailable

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .fourteenDays: 14
        case .thirtyDays: 30
        case .allAvailable: nil
        }
    }

    var displayName: String {
        switch self {
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .thirtyDays: "30 days"
        case .allAvailable: "All"
        }
    }

    var explanationText: String {
        switch self {
        case .sevenDays: "the last 7 days"
        case .fourteenDays: "the last 14 days"
        case .thirtyDays: "the last 30 days"
        case .allAvailable: "all available history"
        }
    }
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

    var cacheKey: String {
        [
            "feed:\(feedAdjustmentEnabled ? 1 : 0)",
            "nursing:\(nursingAdjustmentEnabled ? 1 : 0)",
            "bedtime:\(bedtimePredictionEnabled ? 1 : 0)",
            "min:\(Self.cacheValue(customBaselineMinimum))",
            "max:\(Self.cacheValue(customBaselineMaximum))"
        ].joined(separator: "|")
    }

    private static func cacheValue(_ value: Double?) -> String {
        guard let value else { return "auto" }
        return String(format: "%.1f", value)
    }
}

enum ActiveSleepPlanService {
    private static let defaultsKey = "activeSleepPlan"

    static func activate(
        plan: BackwardsSleepPlan,
        profileID: UUID,
        defaults: UserDefaults = .standard
    ) -> ActiveSleepPlan {
        let activePlan = ActiveSleepPlan(
            profileID: profileID,
            targetBedtime: plan.targetBedtime,
            historyRangeRawValue: plan.historyRange.rawValue,
            activatedAt: Date(),
            generatedAt: plan.generatedAt,
            segmentAdjustments: plan.segmentAdjustments
        )
        save(activePlan, defaults: defaults)
        return activePlan
    }

    static func activePlan(
        for profileID: UUID?,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> ActiveSleepPlan? {
        guard let profileID,
              let data = defaults.data(forKey: defaultsKey),
              let plan = try? JSONDecoder().decode(ActiveSleepPlan.self, from: data),
              plan.profileID == profileID,
              calendar.isDate(plan.targetBedtime, inSameDayAs: now) else {
            return nil
        }
        return plan
    }

    static func clear(
        profileID: UUID? = nil,
        defaults: UserDefaults = .standard
    ) {
        guard let profileID else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        guard let data = defaults.data(forKey: defaultsKey),
              let plan = try? JSONDecoder().decode(ActiveSleepPlan.self, from: data),
              plan.profileID == profileID else {
            return
        }
        defaults.removeObject(forKey: defaultsKey)
    }

    static func wakeAlert(
        for activePlan: ActiveSleepPlan?,
        profile: BabyProfile?,
        events: [BabyEvent],
        activeSleep: BabyEvent?,
        now: Date = Date(),
        calendar: Calendar = .current,
        settings: PredictionSettings = .default
    ) -> ActiveSleepPlanWakeAlert? {
        guard let activePlan,
              let profile,
              profile.id == activePlan.profileID,
              let activeSleep,
              activeSleep.type == .sleep,
              activeSleep.isTimerRunning,
              activeSleep.sleepKind != .nightSleep,
              calendar.isDate(activePlan.targetBedtime, inSameDayAs: now) else {
            return nil
        }

        let plan = SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: activePlan.targetBedtime,
            now: now,
            calendar: calendar,
            historyRange: activePlan.historyRange,
            settings: settings,
            adjustments: activePlan.segmentAdjustments
        )
        let napIndex = SleepPredictionEngine.napIndex(
            for: activeSleep,
            among: events,
            calendar: calendar
        )
        let plannedNapWakeBy = plan.segments.first {
            $0.kind == .nap && $0.napIndex == napIndex
        }?.endDate
        let bedtimeWakeBy = SleepPredictionEngine.latestWakeDateForBedtime(
            profile: profile,
            events: events,
            targetBedtime: activePlan.targetBedtime,
            now: now,
            calendar: calendar,
            historyRange: activePlan.historyRange,
            settings: settings
        )

        let plannedWakeBy = plannedNapWakeBy.flatMap {
            $0 > activeSleep.startDate ? $0 : nil
        }
        let wakeByDate = plannedWakeBy ?? bedtimeWakeBy

        guard activeSleep.startDate < plan.targetBedtime,
              wakeByDate < plan.targetBedtime else {
            return nil
        }

        return ActiveSleepPlanWakeAlert(
            profileID: profile.id,
            activeSleepEventID: activeSleep.id,
            wakeByDate: wakeByDate,
            targetBedtime: plan.targetBedtime
        )
    }

    private static func save(
        _ plan: ActiveSleepPlan,
        defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}

enum SleepPredictionEngine {
    static let algorithmVersion = "LittleWindowsSleep-v4"

    static func cacheVersion(settings: PredictionSettings) -> String {
        "\(algorithmVersion)|\(settings.cacheKey)"
    }

    static func displayAlgorithmVersion(_ cacheVersion: String?) -> String {
        guard let cacheVersion else { return algorithmVersion }
        return cacheVersion.components(separatedBy: "|").first ?? cacheVersion
    }

    static func latestWakeDateForBedtime(
        profile: BabyProfile,
        events: [BabyEvent],
        targetBedtime: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        historyRange: BackwardsSleepPlanHistoryRange = .sevenDays,
        settings: PredictionSettings = .default
    ) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        let target = date(onSameDayAs: now, matchingTimeOf: targetBedtime, calendar: calendar)
        let historyStart = historyRange.dayCount.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: todayStart)
        } ?? .distantPast
        let completedSleeps = events
            .filter {
                $0.type == .sleep &&
                    !$0.isTimerDraft &&
                    $0.endDate != nil &&
                    $0.startDate >= historyStart &&
                    $0.startDate < todayStart
            }
            .sorted { $0.startDate < $1.startDate }
        let samples = wakeWindowSamples(
            from: completedSleeps,
            now: now,
            calendar: calendar
        )
        .filter { $0.napIndex == 5 }
        let wakeMinutes = statistics(for: preferredPredictionSamples(
            samples,
            now: now,
            calendar: calendar
        )).map(planningWakeWindowMinutes) ?? fallbackWakeWindowMinutes(
            profile: profile,
            date: now,
            settings: settings,
            calendar: calendar
        )
        return target.addingTimeInterval(-wakeMinutes * 60)
    }

    static func backwardsPlan(
        profile: BabyProfile,
        events: [BabyEvent],
        targetBedtime: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        historyRange: BackwardsSleepPlanHistoryRange = .sevenDays,
        settings: PredictionSettings = .default,
        adjustments: [BackwardsSleepPlanAdjustment] = []
    ) -> BackwardsSleepPlan {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.startOfNextDay(for: now)
        let target = date(onSameDayAs: now, matchingTimeOf: targetBedtime, calendar: calendar)
        let historyStart = historyRange.dayCount.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: todayStart)
        } ?? .distantPast

        let completedSleeps = events
            .filter { $0.type == .sleep && !$0.isTimerDraft && $0.endDate != nil }
            .sorted { $0.startDate < $1.startDate }
        let historySleeps = completedSleeps.filter {
            $0.startDate >= historyStart && $0.startDate < todayStart
        }
        let sourceDays = sourceDayCount(from: historySleeps, calendar: calendar)
        let typicalNapCount = typicalDailyNapCountForPlanning(
            events: historySleeps,
            profile: profile,
            date: now,
            calendar: calendar,
            settings: settings
        )

        var explanations = [String]()
        if sourceDays > 0 {
            explanations.append(
                "This plan uses completed sleep logs from \(sourceDays) days in \(historyRange.explanationText)."
            )
        } else {
            explanations.append(
                "There are not enough completed sleep logs in \(historyRange.explanationText), so this leans on the age-based wake-window baseline."
            )
        }

        let napDurations = napDurationAveragesByIndex(
            from: historySleeps,
            calendar: calendar
        )
        let wakeWindows = wakeWindowAveragesByNextSleepIndex(
            from: historySleeps,
            now: now,
            calendar: calendar
        )
        let planningDayStart = typicalMorningWakeDate(
            from: historySleeps,
            on: now,
            calendar: calendar
        ) ?? calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? todayStart
        let fallbackWake = fallbackWakeWindowMinutes(
            profile: profile,
            date: now,
            settings: settings,
            calendar: calendar
        )
        let fallbackNap = clippedAverage(
            historySleeps
                .filter { $0.sleepKind == .nap }
                .compactMap(\.duration)
                .map { $0 / 60 },
            allowedRange: 15...180
        ) ?? 50
        let plannedNapIndexes = typicalNapCount > 0 ? Array(1...typicalNapCount) : []

        guard target > planningDayStart, target < tomorrowStart else {
            explanations.append("Choose a bedtime after the usual morning wake to build a full-day plan.")
            explanations.append("This is a planning aid based on local logs, not medical advice.")
            return BackwardsSleepPlan(
                targetBedtime: target,
                generatedAt: now,
                historyRange: historyRange,
                plannedNapCount: 0,
                typicalNapCount: typicalNapCount,
                sourceDayCount: sourceDays,
                confidence: 0.20,
                confidenceLabel: .low,
                segments: [
                    BackwardsSleepPlanSegment(
                        kind: .bedtime,
                        napIndex: nil,
                        startDate: target,
                        endDate: target,
                        durationMinutes: 0
                    )
                ],
                segmentAdjustments: [],
                explanation: explanations
            )
        }

        let napDurationsByIndex = Dictionary(
            uniqueKeysWithValues: plannedNapIndexes.map { napIndex in
                (napIndex, napDurations[napIndex] ?? fallbackNap)
            }
        )
        let wakeSlotIndexes = plannedNapIndexes + [5]
        var wakeDurationsByNextSleepIndex = Dictionary(
            uniqueKeysWithValues: wakeSlotIndexes.map { nextSleepIndex in
                let fallback = nextSleepIndex == 5 ? max(fallbackWake, 150) : fallbackWake
                return (nextSleepIndex, wakeWindows[nextSleepIndex] ?? fallback)
            }
        )
        let availableMinutes = target.timeIntervalSince(planningDayStart) / 60
        let totalNapMinutes = napDurationsByIndex.values.reduce(0, +)
        let baseWakeMinutes = wakeDurationsByNextSleepIndex.values.reduce(0, +)
        let desiredWakeMinutes = max(0, availableMinutes - totalNapMinutes)

        if !wakeSlotIndexes.isEmpty, baseWakeMinutes > 0 {
            if desiredWakeMinutes >= baseWakeMinutes {
                let slackPerWake = (desiredWakeMinutes - baseWakeMinutes) / Double(wakeSlotIndexes.count)
                for nextSleepIndex in wakeSlotIndexes {
                    wakeDurationsByNextSleepIndex[nextSleepIndex, default: 0] += slackPerWake
                }
            } else {
                let scale = desiredWakeMinutes / baseWakeMinutes
                for nextSleepIndex in wakeSlotIndexes {
                    wakeDurationsByNextSleepIndex[nextSleepIndex, default: 0] *= scale
                }
            }
        }

        var segments = [BackwardsSleepPlanSegment]()
        var cursor = planningDayStart
        for napIndex in plannedNapIndexes {
            let wakeMinutes = max(0, wakeDurationsByNextSleepIndex[napIndex] ?? fallbackWake)
            let wakeEnd = cursor.addingTimeInterval(wakeMinutes * 60)
            if wakeEnd > cursor {
                segments.append(
                    BackwardsSleepPlanSegment(
                        kind: .wakeWindow,
                        napIndex: napIndex,
                        startDate: cursor,
                        endDate: wakeEnd,
                        durationMinutes: wakeMinutes
                    )
                )
            }

            let napDuration = max(0, napDurationsByIndex[napIndex] ?? fallbackNap)
            let napEnd = wakeEnd.addingTimeInterval(napDuration * 60)
            segments.append(
                BackwardsSleepPlanSegment(
                    kind: .nap,
                    napIndex: napIndex,
                    startDate: wakeEnd,
                    endDate: napEnd,
                    durationMinutes: napDuration
                )
            )
            cursor = napEnd
        }
        if target > cursor {
            segments.append(
                BackwardsSleepPlanSegment(
                    kind: .wakeWindow,
                    napIndex: nil,
                    startDate: cursor,
                    endDate: target,
                    durationMinutes: target.timeIntervalSince(cursor) / 60
                )
            )
        }
        segments.append(
            BackwardsSleepPlanSegment(
                kind: .bedtime,
                napIndex: nil,
                startDate: target,
                endDate: target,
                durationMinutes: 0
            )
        )

        let usableAdjustments = adjustments.filter { adjustment in
            segments.contains { adjustment.matches($0) && $0.kind != .bedtime }
        }
        segments = adjustedBackwardsPlanSegments(
            segments,
            targetBedtime: target,
            adjustments: usableAdjustments
        )

        let plannedNaps = segments.filter { $0.kind == .nap }
        if plannedNaps.isEmpty {
            explanations.append("No naps fit comfortably into the full-day layout before the selected bedtime.")
        } else {
            explanations.append(
                "The full-day layout starts from the usual morning wake and lands on bedtime using typical nap lengths and wake windows by nap order."
            )
        }
        if !usableAdjustments.isEmpty {
            explanations.append("Manual window adjustments are applied before the remaining timeline is recalculated.")
        }
        explanations.append("This is a planning aid based on local logs, not medical advice.")

        let confidence = backwardsPlanConfidence(
            sourceDays: sourceDays,
            napDurationCount: napDurations.count,
            wakeWindowCount: wakeWindows.count
        )

        return BackwardsSleepPlan(
            targetBedtime: target,
            generatedAt: now,
            historyRange: historyRange,
            plannedNapCount: plannedNaps.count,
            typicalNapCount: typicalNapCount,
            sourceDayCount: sourceDays,
            confidence: confidence,
            confidenceLabel: confidenceLabel(for: confidence),
            segments: segments,
            segmentAdjustments: usableAdjustments,
            explanation: explanations
        )
    }

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

        let nextSleepIndex = nextNapIndex(events: events, date: now, calendar: calendar)
        let napsToday = events.filter {
            $0.type == .sleep &&
            $0.sleepKind == .nap &&
            calendar.isDate($0.startDate, inSameDayAs: now)
        }.count
        let typicalNapCount = typicalDailyNapCount(events: completedSleeps, now: now, calendar: calendar)
        let bedtimeCandidate = settings.bedtimePredictionEnabled &&
            Double(napsToday) >= max(1, typicalNapCount - 0.5)
        let predictionSampleIndex = bedtimeCandidate ? 5 : nextSleepIndex
        let allSamples = wakeWindowSamples(from: completedSleeps, now: now, calendar: calendar)
            .filter { $0.napIndex == predictionSampleIndex }
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
            let sampleLabel = predictionSampleIndex == 5 ? "pre-bed" : "nap \(predictionSampleIndex)"
            explanations.append(
                "\(profile.name)'s recent wake-window median for \(sampleLabel) is \(minutesText(stats.weightedMedian)); the planning target is \(minutesText(personalCenter))."
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
                let trendAdjustment = wakeWindowTrendAdjustmentMinutes(stats)
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
            napIndex: predictionSampleIndex
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
        var kind: PredictionKind = .nap
        var finalStart = provisionalStart

        if settings.bedtimePredictionEnabled,
           let bedtimeDate,
           provisionalStart >= bedtimeDate.addingTimeInterval(-45 * 60),
           bedtimeCandidate {
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
            napIndex: predictionSampleIndex
        )
    }

    static func sleepPressure(
        profile: BabyProfile?,
        events: [BabyEvent],
        records: [SleepPredictionRecord] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        settings: PredictionSettings = .default
    ) -> SleepPressure? {
        guard let profile, profile.profileType == .child else { return nil }
        guard !events.contains(where: { $0.type == .sleep && $0.isTimerRunning }) else {
            return nil
        }

        let ageDays = max(0, calendar.dateComponents([.day], from: profile.birthDate, to: now).day ?? 0)
        let ageMonths = Double(ageDays) / 30.4375
        if ageMonths < 4 {
            return SleepPressure(
                score: nil,
                band: .learning,
                confidence: 0.20,
                confidenceLabel: .low,
                awakeMinutes: nil,
                targetMinutes: nil,
                readyAt: nil,
                highAt: nil,
                nextThresholdDate: nil,
                explanation: [
                    "Sleep pressure is still learning for babies under 4 months because early sleep rhythms vary widely.",
                    "Complete sleep logs will still help Little Windows learn this profile's rhythm."
                ],
                contributingFactors: []
            )
        }

        let committedEvents = events.filter { !$0.isTimerDraft }
        let completedSleeps = committedEvents
            .filter { $0.type == .sleep && $0.endDate != nil && $0.startDate <= now }
            .sorted { $0.startDate < $1.startDate }
        guard let lastSleep = completedSleeps.last,
              let lastSleepEnd = lastSleep.endDate,
              lastSleepEnd <= now else {
            return SleepPressure(
                score: nil,
                band: .learning,
                confidence: 0.25,
                confidenceLabel: .low,
                awakeMinutes: nil,
                targetMinutes: nil,
                readyAt: nil,
                highAt: nil,
                nextThresholdDate: nil,
                explanation: [
                    "Complete one sleep log to start estimating sleep pressure from awake time.",
                    "This is a planning aid based on local logs, not medical advice."
                ],
                contributingFactors: []
            )
        }

        let awakeMinutes = max(0, now.timeIntervalSince(lastSleepEnd) / 60)
        let napsToday = committedEvents.filter {
            $0.type == .sleep &&
                $0.sleepKind == .nap &&
                calendar.isDate($0.startDate, inSameDayAs: now)
        }.count
        let typicalNapCount = typicalDailyNapCount(events: completedSleeps, now: now, calendar: calendar)
        let bedtimeCandidate = settings.bedtimePredictionEnabled &&
            Double(napsToday) >= max(1, typicalNapCount - 0.5)
        let nextSleepIndex = bedtimeCandidate ? 5 : nextNapIndex(events: committedEvents, date: now, calendar: calendar)
        let samples = preferredPredictionSamples(
            wakeWindowSamples(from: completedSleeps, now: now, calendar: calendar)
                .filter { $0.napIndex == nextSleepIndex },
            now: now,
            calendar: calendar
        )
        let stats = statistics(for: clipOutliers(samples))
        let baseline = ageBaselineMinutes(
            birthDate: profile.birthDate,
            date: now,
            customMinimum: settings.customBaselineMinimum,
            customMaximum: settings.customBaselineMaximum,
            calendar: calendar
        )
        let baselineCenter = (baseline.lowerBound + baseline.upperBound) / 2
        let personalTarget = stats.map(planningWakeWindowMinutes) ?? baselineCenter
        let personalWeight: Double
        switch stats?.effectiveSampleCount ?? 0 {
        case ..<3: personalWeight = 0.20
        case 3..<10: personalWeight = 0.45
        default: personalWeight = 0.65
        }
        var targetMinutes = baselineCenter * (1 - personalWeight) + personalTarget * personalWeight
        var rawScore = pressureScore(awakeMinutes: awakeMinutes, targetMinutes: targetMinutes)
        var explanations = [String]()
        var factors = [PredictionFactorValue]()

        if let stats {
            let sampleLabel = nextSleepIndex == 5 ? "pre-bed" : "nap \(nextSleepIndex)"
            explanations.append(
                "\(profile.name)'s recent \(sampleLabel) wake-window median is \(minutesText(stats.weightedMedian)); pressure is compared with a \(minutesText(targetMinutes)) planning target."
            )
            factors.append(PredictionFactorValue(
                name: "Recent wake rhythm",
                valueDescription: "\(stats.sampleCount) samples",
                impactMinutes: targetMinutes - baselineCenter,
                confidenceImpact: min(0.18, stats.effectiveSampleCount * 0.018),
                explanation: "Recent matching wake windows tune the pressure target for this profile."
            ))
        } else {
            explanations.append(
                "There is not enough matching wake-window history yet, so pressure leans on the editable age-based baseline."
            )
        }

        if let lastNapMinutes = lastSleep.duration.map({ $0 / 60 }),
           lastSleep.sleepKind == .nap {
            let recentNapCutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast
            let recentNapDurations = completedSleeps
                .filter { $0.sleepKind == .nap && $0.startDate >= recentNapCutoff }
                .compactMap(\.duration)
                .map { $0 / 60 }
            let adjustment = napDurationAdjustment(
                lastNapMinutes: lastNapMinutes,
                recentNapMinutes: recentNapDurations
            )
            if adjustment < 0 {
                rawScore += min(10, abs(adjustment) * 0.55)
                targetMinutes += adjustment
                explanations.append("The last nap was short, so pressure builds a little sooner.")
                factors.append(PredictionFactorValue(
                    name: "Last nap",
                    valueDescription: minutesText(lastNapMinutes),
                    impactMinutes: adjustment,
                    confidenceImpact: -0.01,
                    explanation: "Shorter naps can leave sleep pressure higher in the next wake window."
                ))
            } else if adjustment > 0 {
                rawScore -= min(6, adjustment * 0.35)
                targetMinutes += adjustment
                explanations.append("The last nap was longer than usual, so pressure builds more gradually.")
                factors.append(PredictionFactorValue(
                    name: "Last nap",
                    valueDescription: minutesText(lastNapMinutes),
                    impactMinutes: adjustment,
                    confidenceImpact: -0.01,
                    explanation: "Longer naps can lower near-term sleep pressure."
                ))
            }
        }

        let recentSleepMinutes = totalSleepMinutes(
            events: completedSleeps,
            start: now.addingTimeInterval(-24 * 60 * 60),
            end: now
        )
        if let minimumSleep = dailySleepMinimumMinutes(ageMonths: ageMonths),
           recentSleepMinutes < minimumSleep {
            let debtMinutes = minimumSleep - recentSleepMinutes
            let boost = min(10, debtMinutes / 30 * 2)
            rawScore += boost
            explanations.append(
                "Recent 24-hour sleep is below the broad age-based range, so pressure is nudged upward."
            )
            factors.append(PredictionFactorValue(
                name: "Recent sleep total",
                valueDescription: minutesText(recentSleepMinutes),
                impactMinutes: -boost,
                confidenceImpact: -0.02,
                explanation: "Broad pediatric sleep-duration ranges are used only as guardrails."
            ))
        }

        let typicalBedtimes = completedSleeps
            .filter {
                $0.sleepKind == .nightSleep &&
                    calendar.component(.hour, from: $0.startDate) >= 17
            }
            .suffix(14)
            .map(\.startDate)
        if bedtimeCandidate,
           let bedtime = circularTypicalTime(for: typicalBedtimes, on: now, calendar: calendar),
           now >= bedtime.addingTimeInterval(-75 * 60),
           now <= bedtime.addingTimeInterval(45 * 60) {
            rawScore += 5
            explanations.append("This is near the usual bedtime pattern, which raises readiness slightly.")
            factors.append(PredictionFactorValue(
                name: "Bedtime context",
                valueDescription: DateFormatting.time.string(from: bedtime),
                impactMinutes: 0,
                confidenceImpact: typicalBedtimes.count >= 5 ? 0.04 : 0,
                explanation: "Circadian timing helps separate a late nap from bedtime."
            ))
        }

        let bias = PredictionTuningService.conservativeBiasCorrection(
            records: records,
            napIndex: nextSleepIndex
        )
        if abs(bias) >= 2 {
            rawScore += bias < 0 ? min(5, abs(bias) * 0.4) : -min(5, bias * 0.25)
            explanations.append(
                "Recent prediction accuracy adds a cautious pressure adjustment."
            )
            factors.append(PredictionFactorValue(
                name: "Accuracy tuning",
                valueDescription: "Conservative recent bias",
                impactMinutes: bias,
                confidenceImpact: 0,
                explanation: "Past early or late prediction errors are corrected gradually."
            ))
        }

        let score = min(100, max(0, rawScore))
        let band = pressureBand(for: score)
        let readyMinutes = targetMinutes * 0.85
        let highMinutes = targetMinutes * 1.12
        let readyAt = lastSleepEnd.addingTimeInterval(readyMinutes * 60)
        let highAt = lastSleepEnd.addingTimeInterval(highMinutes * 60)
        let nextThresholdDate: Date?
        switch band {
        case .learning:
            nextThresholdDate = nil
        case .low, .building:
            nextThresholdDate = readyAt > now ? readyAt : nil
        case .ready:
            nextThresholdDate = highAt > now ? highAt : nil
        case .high:
            nextThresholdDate = nil
        }

        var confidence = confidenceScore(
            sampleCount: Int((stats?.effectiveSampleCount ?? 0).rounded(.down)),
            variability: stats?.standardDeviation
        )
        if stats == nil { confidence = min(confidence, 0.42) }
        confidence = min(0.92, max(0.18, confidence))
        explanations.append("This is a planning aid based on local logs, not medical advice.")

        return SleepPressure(
            score: score,
            band: band,
            confidence: confidence,
            confidenceLabel: confidenceLabel(for: confidence),
            awakeMinutes: awakeMinutes,
            targetMinutes: targetMinutes,
            readyAt: readyAt,
            highAt: highAt,
            nextThresholdDate: nextThresholdDate,
            explanation: explanations,
            contributingFactors: factors
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
        let variabilityBuffer = min(18, max(laterSideGap * 0.55, stats.standardDeviation * 0.17))
        return stats.weightedMedian + variabilityBuffer
    }

    static func wakeWindowTrendAdjustmentMinutes(_ stats: WakeWindowStatistics) -> Double {
        guard stats.trendMinutes < -6 else { return 0 }
        return max(-8, stats.trendMinutes * 0.2)
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

    private static func typicalDailyNapCountForPlanning(
        events: [BabyEvent],
        profile: BabyProfile,
        date: Date,
        calendar: Calendar,
        settings: PredictionSettings
    ) -> Int {
        let naps = events.filter { $0.sleepKind == .nap }
        let grouped = Dictionary(grouping: naps) { calendar.startOfDay(for: $0.startDate) }
        if !grouped.isEmpty {
            let average = Double(grouped.values.reduce(0) { $0 + $1.count }) / Double(grouped.count)
            return min(4, max(1, Int(average.rounded())))
        }
        let baseline = ageBaselineMinutes(
            birthDate: profile.birthDate,
            date: date,
            customMinimum: settings.customBaselineMinimum,
            customMaximum: settings.customBaselineMaximum,
            calendar: calendar
        )
        let center = (baseline.lowerBound + baseline.upperBound) / 2
        switch center {
        case ..<105: return 4
        case ..<150: return 3
        case ..<195: return 2
        default: return 1
        }
    }

    private static func napDurationAveragesByIndex(
        from sleeps: [BabyEvent],
        calendar: Calendar
    ) -> [Int: Double] {
        var values = [Int: [Double]]()
        let sorted = sleeps.sorted { $0.startDate < $1.startDate }
        for sleep in sorted where sleep.sleepKind == .nap {
            guard let duration = sleep.duration else { continue }
            let index = napIndex(for: sleep, among: sorted, calendar: calendar)
            values[index, default: []].append(duration / 60)
        }
        return values.compactMapValues {
            clippedAverage($0, allowedRange: 15...180)
        }
    }

    private static func wakeWindowAveragesByNextSleepIndex(
        from sleeps: [BabyEvent],
        now: Date,
        calendar: Calendar
    ) -> [Int: Double] {
        let samples = wakeWindowSamples(from: sleeps, now: now, calendar: calendar)
        let grouped = Dictionary(grouping: samples, by: \.napIndex)
        return grouped.compactMapValues { samples in
            clippedAverage(samples.map(\.minutes), allowedRange: 20...480)
        }
    }

    private static func typicalMorningWakeDate(
        from sleeps: [BabyEvent],
        on date: Date,
        calendar: Calendar
    ) -> Date? {
        let wakeMinutes = sleeps
            .filter { $0.sleepKind == .nightSleep }
            .compactMap(\.endDate)
            .map {
                Double(calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0))
            }
            .filter { (3 * 60 ... 12 * 60).contains($0) }
        guard let average = clippedAverage(wakeMinutes, allowedRange: 3 * 60 ... 12 * 60) else {
            return nil
        }
        let rounded = Int(average.rounded())
        return calendar.date(
            bySettingHour: rounded / 60,
            minute: rounded % 60,
            second: 0,
            of: date
        )
    }

    private static func fallbackWakeWindowMinutes(
        profile: BabyProfile,
        date: Date,
        settings: PredictionSettings,
        calendar: Calendar
    ) -> Double {
        let baseline = ageBaselineMinutes(
            birthDate: profile.birthDate,
            date: date,
            customMinimum: settings.customBaselineMinimum,
            customMaximum: settings.customBaselineMaximum,
            calendar: calendar
        )
        return (baseline.lowerBound + baseline.upperBound) / 2
    }

    private static func pressureScore(awakeMinutes: Double, targetMinutes: Double) -> Double {
        guard targetMinutes > 0 else { return 0 }
        let ratio = awakeMinutes / targetMinutes
        switch ratio {
        case ..<0.55:
            return max(0, ratio / 0.55 * 30)
        case 0.55..<0.85:
            return 30 + ((ratio - 0.55) / 0.30) * 35
        case 0.85..<1.12:
            return 65 + ((ratio - 0.85) / 0.27) * 23
        default:
            return min(100, 88 + ((ratio - 1.12) / 0.35) * 12)
        }
    }

    private static func pressureBand(for score: Double) -> SleepPressureBand {
        switch score {
        case ..<30: return .low
        case 30..<65: return .building
        case 65..<88: return .ready
        default: return .high
        }
    }

    private static func dailySleepMinimumMinutes(ageMonths: Double) -> Double? {
        switch ageMonths {
        case ..<4:
            return nil
        case ..<12:
            return 12 * 60
        case ..<36:
            return 11 * 60
        default:
            return 10 * 60
        }
    }

    private static func totalSleepMinutes(
        events: [BabyEvent],
        start: Date,
        end: Date
    ) -> Double {
        events.reduce(0) { total, event in
            guard event.type == .sleep, let eventEnd = event.endDate else { return total }
            let overlapStart = max(event.startDate, start)
            let overlapEnd = min(eventEnd, end)
            guard overlapEnd > overlapStart else { return total }
            return total + overlapEnd.timeIntervalSince(overlapStart) / 60
        }
    }

    private static func sourceDayCount(from sleeps: [BabyEvent], calendar: Calendar) -> Int {
        Set(sleeps.map { calendar.startOfDay(for: $0.startDate) }).count
    }

    private static func backwardsPlanConfidence(
        sourceDays: Int,
        napDurationCount: Int,
        wakeWindowCount: Int
    ) -> Double {
        let dayScore = min(0.40, Double(sourceDays) * 0.055)
        let napScore = min(0.18, Double(napDurationCount) * 0.045)
        let wakeScore = min(0.24, Double(wakeWindowCount) * 0.04)
        return min(0.86, max(0.20, 0.22 + dayScore + napScore + wakeScore))
    }

    private static func adjustedBackwardsPlanSegments(
        _ segments: [BackwardsSleepPlanSegment],
        targetBedtime: Date,
        adjustments: [BackwardsSleepPlanAdjustment]
    ) -> [BackwardsSleepPlanSegment] {
        guard !adjustments.isEmpty else { return segments }

        var adjustmentsByID = [String: BackwardsSleepPlanAdjustment]()
        for adjustment in adjustments {
            adjustmentsByID[adjustment.id] = adjustment
        }
        var output = [(segment: BackwardsSleepPlanSegment, isManual: Bool)]()
        var cursor: Date?
        var hasAppliedManualAdjustment = false

        for baseSegment in segments {
            if baseSegment.kind == .bedtime {
                output.append((
                    BackwardsSleepPlanSegment(
                        kind: .bedtime,
                        napIndex: nil,
                        startDate: targetBedtime,
                        endDate: targetBedtime,
                        durationMinutes: 0
                    ),
                    false
                ))
                continue
            }

            if let adjustment = adjustmentsByID[BackwardsSleepPlanAdjustment(segment: baseSegment).id] {
                var start = min(adjustment.startDate, targetBedtime)
                if let previous = output.last?.segment, output.last?.isManual == true {
                    start = max(start, previous.endDate)
                }
                let end = max(start, min(adjustment.endDate, targetBedtime))

                if let previous = output.last, !previous.isManual {
                    var precedingSegment = previous.segment
                    precedingSegment.endDate = max(precedingSegment.startDate, start)
                    precedingSegment.durationMinutes = precedingSegment.endDate
                        .timeIntervalSince(precedingSegment.startDate) / 60
                    output[output.count - 1] = (precedingSegment, false)
                }

                output.append((
                    BackwardsSleepPlanSegment(
                        kind: baseSegment.kind,
                        napIndex: baseSegment.napIndex,
                        startDate: start,
                        endDate: end,
                        durationMinutes: end.timeIntervalSince(start) / 60
                    ),
                    true
                ))
                cursor = end
                hasAppliedManualAdjustment = true
                continue
            }

            guard hasAppliedManualAdjustment, let shiftedStart = cursor else {
                output.append((baseSegment, false))
                continue
            }

            let end: Date
            if baseSegment.kind == .wakeWindow && baseSegment.napIndex == nil {
                end = targetBedtime
            } else {
                end = min(
                    shiftedStart.addingTimeInterval(max(0, baseSegment.durationMinutes) * 60),
                    targetBedtime
                )
            }

            guard end > shiftedStart else { continue }

            output.append((
                BackwardsSleepPlanSegment(
                    kind: baseSegment.kind,
                    napIndex: baseSegment.napIndex,
                    startDate: shiftedStart,
                    endDate: end,
                    durationMinutes: end.timeIntervalSince(shiftedStart) / 60
                ),
                false
            ))
            cursor = end
        }

        return output.map(\.segment)
    }

    private static func clippedAverage(
        _ values: [Double],
        allowedRange: ClosedRange<Double>
    ) -> Double? {
        let filtered = values.filter { allowedRange.contains($0) }.sorted()
        guard !filtered.isEmpty else { return nil }
        guard filtered.count >= 4 else {
            return filtered.reduce(0, +) / Double(filtered.count)
        }
        let q1 = percentile(filtered, 0.25)
        let q3 = percentile(filtered, 0.75)
        let iqr = q3 - q1
        let lower = q1 - 1.5 * iqr
        let upper = q3 + 1.5 * iqr
        let clipped = filtered.filter { (lower...upper).contains($0) }
        guard !clipped.isEmpty else { return filtered.reduce(0, +) / Double(filtered.count) }
        return clipped.reduce(0, +) / Double(clipped.count)
    }

    private static func date(
        onSameDayAs day: Date,
        matchingTimeOf time: Date,
        calendar: Calendar
    ) -> Date {
        let components = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: day
        ) ?? time
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
