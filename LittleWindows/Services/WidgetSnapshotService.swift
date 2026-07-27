import Foundation
import SwiftData
import WidgetKit

@MainActor
enum QuickLogActionPreferenceStore {
    private static let prefix = "quickLog.pinnedActionIDs"
    private static let maximumPinnedActions = 6

    static func pinnedActionIDs(profileID: UUID?) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(profileID: profileID)) ?? []
    }

    @discardableResult
    static func togglePinnedAction(_ actionID: String, profileID: UUID?) -> Bool {
        var ids = pinnedActionIDs(profileID: profileID)
        if let index = ids.firstIndex(of: actionID) {
            ids.remove(at: index)
            UserDefaults.standard.set(ids, forKey: key(profileID: profileID))
            return false
        }

        ids.removeAll { $0 == actionID }
        ids.insert(actionID, at: 0)
        if ids.count > maximumPinnedActions {
            ids.removeLast(ids.count - maximumPinnedActions)
        }
        UserDefaults.standard.set(ids, forKey: key(profileID: profileID))
        return true
    }

    private static func key(profileID: UUID?) -> String {
        "\(prefix).\(profileID?.uuidString ?? "default")"
    }
}

@MainActor
enum CareCategoryPreferenceStore {
    private static let prefix = "careCategory.hiddenTypeRawValues"

    static func hiddenTypes(profileID: UUID?) -> Set<EventType> {
        Set((UserDefaults.standard.stringArray(forKey: key(profileID: profileID)) ?? []).compactMap(EventType.init(rawValue:)))
    }

    static func isHidden(_ type: EventType, profileID: UUID?) -> Bool {
        hiddenTypes(profileID: profileID).contains(type)
    }

    static func setHidden(_ isHidden: Bool, type: EventType, profileID: UUID?) {
        var hidden = hiddenTypes(profileID: profileID)
        if isHidden {
            hidden.insert(type)
        } else {
            hidden.remove(type)
        }
        setHiddenTypes(hidden, profileID: profileID)
    }

    static func setHiddenTypes(_ hidden: Set<EventType>, profileID: UUID?) {
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: key(profileID: profileID))
    }

    static func reset(profileID: UUID?) {
        UserDefaults.standard.removeObject(forKey: key(profileID: profileID))
    }

    static func visibleTypes(for profileType: CareProfileType, profileID: UUID?) -> [EventType] {
        let hidden = hiddenTypes(profileID: profileID)
        return EventType.cases(for: profileType).filter { !hidden.contains($0) }
    }

    private static func key(profileID: UUID?) -> String {
        "\(prefix).\(profileID?.uuidString ?? "default")"
    }
}

@MainActor
enum WidgetSnapshotService {
    static func refresh(
        profile: BabyProfile?,
        events: [BabyEvent],
        prediction: SleepPrediction?
    ) {
        let snapshot = makeSnapshot(
            profileID: profile?.id,
            profileType: profile?.profileType ?? .child,
            babyName: profile?.name ?? "Baby",
            events: events,
            prediction: prediction
        )
        write(snapshot)
    }

    @discardableResult
    static func refreshActiveTimer(
        _ event: BabyEvent,
        at date: Date = Date()
    ) -> ActiveTimerSnapshot {
        var snapshot = read()
        let existingTimer = snapshot.activeTimer
        let timer = activeSnapshot(
            event: event,
            profileID: event.profileID ?? existingTimer?.profileID,
            babyName: existingTimer?.babyName ?? snapshot.babyName,
            additionalActiveCount: existingTimer?.additionalActiveCount ?? 0,
            now: date
        )
        snapshot.generatedAt = date
        snapshot.profileID = event.profileID ?? snapshot.profileID
        snapshot.activeTimer = timer
        write(snapshot)
        return timer
    }

    static func makeSnapshot(
        profileID: UUID? = nil,
        profileType: CareProfileType = .child,
        babyName: String,
        events: [BabyEvent],
        prediction: SleepPrediction?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let timerDrafts = events.filter(\.isTimerDraft)
        let primary = EventTimerService.primaryActiveEvent(in: timerDrafts)
            ?? timerDrafts.max { $0.updatedAt < $1.updatedAt }
        let activeTimer = primary.map {
            activeSnapshot(
                event: $0,
                profileID: profileID ?? $0.profileID,
                babyName: babyName,
                additionalActiveCount: max(0, timerDrafts.count - 1),
                now: now
            )
        }
        let todayEvents = events.filter {
            !$0.isTimerDraft && $0.occursOnLocalDay(now, calendar: calendar)
        }
        let daily = DailySummaryService.summary(for: todayEvents)
        let careSessions = groupedCareSessions(todayEvents).count

        return WidgetSnapshot(
            generatedAt: now,
            profileID: profileID,
            profileName: babyName,
            babyName: babyName,
            activeTimer: activeTimer,
            prediction: prediction.map {
                PredictionSnapshot(
                    profileID: profileID,
                    profileName: babyName,
                    kind: $0.predictionKind.displayName,
                    expectedStart: $0.predictedStart,
                    windowStart: $0.predictedWindowStart,
                    windowEnd: $0.predictedWindowEnd,
                    confidenceLabel: $0.confidenceLabel.displayName
                )
            },
            todaySummary: TodaySummarySnapshot(
                profileID: profileID,
                profileName: babyName,
                profileTypeRawValue: profileType.rawValue,
                totalSleepSeconds: daily.totalSleep,
                napCount: daily.napCount,
                careSessionCount: careSessions,
                diaperCount: daily.wetDiapers + daily.dirtyDiapers + daily.bothDiapers,
                pumpingSessionCount: daily.pumpingSessions,
                pumpingSeconds: daily.pumpingTotal,
                solidFeedCount: daily.solidFeedCount,
                solidSensitivityCount: daily.solidSensitivityObservations,
                childPottyCount: daily.childPottyCount,
                childPottyAccidentCount: daily.childPottyAccidents,
                dogFoodCount: daily.dogFoodCount,
                dogWaterCount: daily.waterCount,
                dogPottyCount: daily.pottyCount,
                dogWalkSeconds: daily.walkTime,
                summaryMetrics: summaryMetrics(for: profileType, daily: daily)
            ),
            food: read().food,
            quickActions: makeQuickActions(
                profileID: profileID,
                profileType: profileType,
                events: events,
                activeTimer: activeTimer,
                pinnedActionIDs: QuickLogActionPreferenceStore.pinnedActionIDs(profileID: profileID),
                now: now,
                calendar: calendar
            )
        )
    }

    private static func summaryMetrics(
        for profileType: CareProfileType,
        daily: DailySummary
    ) -> [CareSummaryMetricSnapshot] {
        switch profileType {
        case .child:
            return [
                metric("sleep-total", "Sleep", DurationFormatting.string(seconds: daily.totalSleep), "moon.fill", "indigo", .sleep),
                metric("sleep-naps", "Naps", "\(daily.napCount)", "bed.double.fill", "purple", .sleep),
                metric("feed-total", "Feeds", "\(daily.feedCount)", "waterbottle.fill", "orange", .feed),
                metric("feed-bottle", "Bottle", String(format: "%.1f oz", daily.bottleOunces), "drop.fill", "cyan", .feed),
                metric("feed-solids", "Solids", "\(daily.solidFeedCount)", "carrot.fill", "orange", .feed),
                metric("nursing", "Nursing", DurationFormatting.string(seconds: daily.nursingTotal), "figure.and.child.holdinghands", "pink", .nursing),
                metric("pumping", "Pumping", "\(daily.pumpingSessions)", "drop.circle.fill", "cyan", .pumping),
                metric("diapers", "Diapers", "\(daily.wetDiapers + daily.dirtyDiapers + daily.bothDiapers)", "humidity.fill", "teal", .diaper),
                metric("potty", "Potty", "\(daily.childPottyCount)", "figure.child", "teal", .potty),
                metric("medicine", "Medicine", "\(daily.medicineNames.count)", "cross.case.fill", "red", .medicine),
                metric("growth", "Growth", "\(daily.growthCount)", "ruler.fill", "green", .growth),
                metric("temperature", "Temp", "\(daily.temperatureCount)", "thermometer.medium", "red", .temperature),
                metric("activity", "Activity", "\(daily.activityCount)", "figure.play", "green", .activity),
                metric("custom", "Custom", "\(daily.customCount)", "sparkles", "gray", .custom)
            ]
        case .dog:
            return [
                metric("food", "Food", "\(daily.dogFoodCount)", "fork.knife", "orange", .food),
                metric("water", "Water", "\(daily.waterCount)", "drop.fill", "cyan", .water),
                metric("treats", "Treats", "\(daily.treatCount)", "birthday.cake.fill", "pink", .treat),
                metric("potty", "Potty", "\(daily.pottyCount)", "pawprint.fill", "teal", .potty),
                metric("walks", "Walks", DurationFormatting.string(seconds: daily.walkTime), "figure.walk", "green", .walk),
                metric("rest", "Rest", DurationFormatting.string(seconds: daily.restTime), "bed.double.fill", "indigo", .rest),
                metric("training", "Training", DurationFormatting.string(seconds: daily.trainingTime), "graduationcap.fill", "purple", .training),
                metric("grooming", "Grooming", DurationFormatting.string(seconds: daily.groomingTime), "comb.fill", "mint", .grooming),
                metric("medicine", "Medicine", "\(daily.medicineNames.count)", "cross.case.fill", "red", .medicine),
                metric("symptoms", "Symptoms", "\(daily.symptomCount)", "exclamationmark.triangle.fill", "orange", .symptom),
                metric("vaccines", "Vaccines", "\(daily.vaccineCount)", "syringe.fill", "blue", .vaccine),
                metric("glucose", "Glucose", "\(daily.glucoseCount)", "drop.triangle.fill", "pink", .glucose),
                metric("custom", "Custom", "\(daily.customCount)", "sparkles", "gray", .custom)
            ]
        }
    }

    private static func metric(
        _ id: String,
        _ title: String,
        _ value: String,
        _ systemImage: String,
        _ tintName: String,
        _ eventType: EventType
    ) -> CareSummaryMetricSnapshot {
        CareSummaryMetricSnapshot(
            id: id,
            title: title,
            value: value,
            systemImage: systemImage,
            tintName: tintName,
            eventTypeRawValue: eventType.rawValue
        )
    }

    static func makeQuickActions(
        profileID: UUID? = nil,
        profileType: CareProfileType,
        events: [BabyEvent],
        activeTimer: ActiveTimerSnapshot? = nil,
        pinnedActionIDs: [String] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [QuickLogActionSnapshot] {
        let recentCutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let hiddenTypes = CareCategoryPreferenceStore.hiddenTypes(profileID: profileID)
        let candidates = quickActionCandidates(for: profileType).filter {
            !hiddenTypes.contains($0.eventType)
        }
        var candidateIndicesByType: [EventType: [Int]] = [:]
        for index in candidates.indices {
            candidateIndicesByType[candidates[index].eventType, default: []].append(index)
        }
        var activeTypes: Set<EventType> = []
        var stats = candidates.map { _ in (recentCount: 0, lastDate: Optional<Date>.none) }
        var repeatSource: BabyEvent?

        for event in events {
            guard event.matchesProfile(profileID) else { continue }
            if event.isTimerDraft {
                activeTypes.insert(event.type)
                continue
            }

            if !hiddenTypes.contains(event.type),
               EventMutationService.canQuickRepeat(event),
               repeatSource.map({ event.startDate > $0.startDate }) ?? true {
                repeatSource = event
            }

            guard let matchingCandidateIndices = candidateIndicesByType[event.type] else { continue }
            let isRecent = event.startDate >= recentCutoff
            for index in matchingCandidateIndices where candidates[index].matches(event) {
                if isRecent {
                    stats[index].recentCount += 1
                }
                if stats[index].lastDate.map({ event.startDate > $0 }) ?? true {
                    stats[index].lastDate = event.startDate
                }
            }
        }
        var pinnedOrder: [String: Int] = [:]
        for (index, actionID) in pinnedActionIDs.enumerated() where pinnedOrder[actionID] == nil {
            pinnedOrder[actionID] = index
        }

        func pinAdjusted(
            _ candidate: QuickLogActionCandidate,
            score: Double
        ) -> (candidate: QuickLogActionCandidate, score: Double) {
            var candidate = candidate
            var score = score
            if let pinIndex = pinnedOrder[candidate.action.id] {
                score += 30 - (Double(pinIndex) * 0.01)
                candidate.action.isPinned = true
            }
            return (candidate, score)
        }

        var scored = candidates.enumerated().compactMap { index, candidate -> (candidate: QuickLogActionCandidate, score: Double)? in
            guard !(candidate.startsTimer && activeTypes.contains(candidate.eventType)) else {
                return nil
            }
            var score = candidate.baseScore
            let signal = stats[index]
            score += min(Double(signal.recentCount), 8) * 0.28

            if let last = signal.lastDate {
                let hours = now.timeIntervalSince(last) / 3_600
                switch hours {
                case ..<0.33:
                    score -= 3.0
                case 0.33..<1.5:
                    score -= 0.8
                case 1.5..<5:
                    score += 1.2
                case 5..<18:
                    score += 0.8
                default:
                    score += 0.35
                }
            } else {
                score += 0.45
            }

            return pinAdjusted(candidate, score: score)
        }

        if let repeatSource {
            let repeatAction = QuickLogActionSnapshot(
                id: "repeat-last",
                title: "Repeat",
                subtitle: repeatSource.displayTitle,
                systemImage: "arrow.clockwise",
                tintName: "indigo",
                destinationPath: "quick-log/repeat-last"
            )
            let repeatCandidate = QuickLogActionCandidate(
                action: repeatAction,
                eventType: repeatSource.type,
                startsTimer: false,
                baseScore: 10.4
            ) { _ in false }
            scored.append(pinAdjusted(repeatCandidate, score: 10.4))
        }

        if let activeTimer {
            let timerAction = QuickLogActionSnapshot(
                id: "active-timer",
                title: activeTimer.resolvedIsRunning ? "Timer" : "Resume",
                subtitle: activeTimer.eventLabel,
                systemImage: activeTimer.resolvedIsRunning ? "timer" : "play.fill",
                tintName: activeTimer.resolvedIsRunning ? "indigo" : "green",
                destinationPath: "active-timer"
            )
            let timerCandidate = QuickLogActionCandidate(
                action: timerAction,
                eventType: EventType.normalized(rawValue: activeTimer.typeRawValue),
                startsTimer: false,
                baseScore: 12
            ) { _ in false }
            scored.append(pinAdjusted(timerCandidate, score: 12))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidate.action.title < rhs.candidate.action.title
                }
                return lhs.score > rhs.score
            }
            .map { $0.candidate.action }
            .prefix(6)
            .map { $0 }
    }

    static func refreshFood(context: ModelContext, now: Date = Date()) {
        let existing = read()
        var snapshot = existing
        snapshot.generatedAt = now
        snapshot.food = makeFoodSnapshot(context: context, now: now)
        write(snapshot)
    }

    static func makeFoodSnapshot(
        context: ModelContext,
        now: Date = Date()
    ) -> FoodWidgetSnapshot {
        var householdDescriptor = FetchDescriptor<Household>(
            sortBy: [SortDescriptor(\Household.createdAt)]
        )
        householdDescriptor.fetchLimit = 1
        let householdID = ((try? context.fetch(householdDescriptor)) ?? []).first?.id

        let lists: [ShoppingList]
        let items: [ShoppingListItem]
        let sections: [FoodStoreSection]
        if let householdID {
            var listDescriptor = FetchDescriptor<ShoppingList>(
                predicate: #Predicate<ShoppingList> { list in
                    list.householdID == householdID && !list.isArchived
                },
                sortBy: [
                    SortDescriptor(\ShoppingList.sortOrder),
                    SortDescriptor(\ShoppingList.name)
                ]
            )
            listDescriptor.fetchLimit = 12
            lists = (try? context.fetch(listDescriptor)) ?? []

            items = shoppingItems(for: lists, householdID: householdID, context: context)

            sections = (try? context.fetch(
                FetchDescriptor<FoodStoreSection>(
                    predicate: #Predicate<FoodStoreSection> { section in
                        section.householdID == householdID
                    }
                )
            )) ?? []
        } else {
            var listDescriptor = FetchDescriptor<ShoppingList>(
                predicate: #Predicate<ShoppingList> { list in
                    !list.isArchived
                },
                sortBy: [
                    SortDescriptor(\ShoppingList.sortOrder),
                    SortDescriptor(\ShoppingList.name)
                ]
            )
            listDescriptor.fetchLimit = 12
            lists = (try? context.fetch(listDescriptor)) ?? []

            items = shoppingItems(for: lists, context: context)

            sections = (try? context.fetch(FetchDescriptor<FoodStoreSection>())) ?? []
        }
        let sectionNames = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.name) })
        let snapshots = lists.map { list in
            shoppingListSnapshot(
                list: list,
                items: items.filter { $0.shoppingListID == list.id },
                sectionNames: sectionNames
            )
        }
        let selected = snapshots.first { $0.activeItemCount > 0 }
            ?? snapshots.first { $0.name.localizedCaseInsensitiveContains("Trader") }
            ?? snapshots.first
        return FoodWidgetSnapshot(
            generatedAt: now,
            selectedList: selected,
            lists: Array(snapshots.prefix(4))
        )
    }

    private static func shoppingItems(
        for lists: [ShoppingList],
        householdID: UUID,
        context: ModelContext
    ) -> [ShoppingListItem] {
        lists.flatMap { list in
            let listID = list.id
            var descriptor = FetchDescriptor<ShoppingListItem>(
                predicate: #Predicate<ShoppingListItem> { item in
                    item.householdID == householdID && item.shoppingListID == listID
                },
                sortBy: [
                    SortDescriptor(\ShoppingListItem.sortOrder),
                    SortDescriptor(\ShoppingListItem.name)
                ]
            )
            descriptor.fetchLimit = 80
            return (try? context.fetch(descriptor)) ?? []
        }
    }

    private static func shoppingItems(
        for lists: [ShoppingList],
        context: ModelContext
    ) -> [ShoppingListItem] {
        lists.flatMap { list in
            let listID = list.id
            var descriptor = FetchDescriptor<ShoppingListItem>(
                predicate: #Predicate<ShoppingListItem> { item in
                    item.shoppingListID == listID
                },
                sortBy: [
                    SortDescriptor(\ShoppingListItem.sortOrder),
                    SortDescriptor(\ShoppingListItem.name)
                ]
            )
            descriptor.fetchLimit = 80
            return (try? context.fetch(descriptor)) ?? []
        }
    }

    static func activeSnapshot(
        event: BabyEvent,
        profileID: UUID? = nil,
        babyName: String,
        additionalActiveCount: Int,
        now: Date = Date()
    ) -> ActiveTimerSnapshot {
        var leftDuration = event.leftDurationSeconds ?? 0
        var rightDuration = event.rightDurationSeconds ?? 0
        if event.type == .nursing, event.isTimerRunning {
            let segmentStart = event.activeTimerSegmentStartDate ?? event.startDate
            let liveSegmentDuration = max(0, now.timeIntervalSince(segmentStart))
            switch event.activeNursingSide {
            case .left:
                leftDuration += liveSegmentDuration
            case .right:
                rightDuration += liveSegmentDuration
            case .none:
                break
            }
        }
        let activeSideDuration: TimeInterval
        switch event.activeNursingSide {
        case .left:
            activeSideDuration = leftDuration
        case .right:
            activeSideDuration = rightDuration
        case .none:
            activeSideDuration = 0
        }
        let activeSideTimerStartDate = event.type == .nursing
            && event.isTimerRunning
            && event.activeNursingSide != nil
            ? now.addingTimeInterval(-activeSideDuration)
            : nil

        return ActiveTimerSnapshot(
            id: event.id,
            profileID: profileID ?? event.profileID,
            profileName: babyName,
            babyName: babyName,
            typeRawValue: event.type.rawValue,
            eventLabel: runningLabel(for: event),
            systemImage: event.activityType?.systemImage ?? event.type.systemImage(for: event.profileTypeSnapshot),
            startDate: event.timerDisplayStartDate(at: now),
            isRunning: event.isTimerRunning,
            elapsedSeconds: event.timerElapsed(at: now),
            caregiverName: event.caregiverName,
            activeNursingSideRawValue: event.activeNursingSide?.rawValue,
            activeNursingSideTimerStartDate: activeSideTimerStartDate,
            leftDurationSeconds: leftDuration,
            rightDurationSeconds: rightDuration,
            additionalActiveCount: additionalActiveCount
        )
    }

    static func read() -> WidgetSnapshot {
        let url = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.widgetSnapshotFilename
        )
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func clear() {
        write(.empty)
    }

    private static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.widgetSnapshotFilename
        )
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func shoppingListSnapshot(
        list: ShoppingList,
        items: [ShoppingListItem],
        sectionNames: [UUID: String]
    ) -> FoodShoppingListSnapshot {
        let activeItems = items
            .filter { !$0.isChecked }
            .sorted { lhs, rhs in
                ((lhs.sortOrder ?? 0), lhs.name) < ((rhs.sortOrder ?? 0), rhs.name)
            }
        return FoodShoppingListSnapshot(
            id: list.id,
            name: list.name,
            activeItemCount: activeItems.count,
            checkedItemCount: items.filter(\.isChecked).count,
            lastUsedAt: list.lastUsedAt,
            topActiveItems: activeItems.prefix(4).map { item in
                FoodShoppingListItemSnapshot(
                    id: item.id,
                    name: item.name,
                    quantityText: item.quantityText,
                    sectionName: item.storeSectionID.flatMap { sectionNames[$0] }
                )
            }
        )
    }

    private struct QuickLogActionCandidate {
        var action: QuickLogActionSnapshot
        var eventType: EventType
        var startsTimer: Bool
        var baseScore: Double
        var matches: (BabyEvent) -> Bool
    }

    private static func quickActionCandidates(for profileType: CareProfileType) -> [QuickLogActionCandidate] {
        switch profileType {
        case .child:
            [
                candidate("sleep", "Start sleep", "Timer", "moon.stars.fill", "indigo", "quick-log/sleep", .sleep, startsTimer: true, baseScore: 8.0),
                candidate("feed", "Feed", nil, "waterbottle.fill", "orange", "quick-log/feed", .feed, baseScore: 7.5),
                candidate("nursing-left", "Nurse left", "Timer", "l.circle.fill", "pink", "quick-log/nursing-left", .nursing, startsTimer: true, baseScore: 7.2),
                candidate("nursing-right", "Nurse right", "Timer", "r.circle.fill", "pink", "quick-log/nursing-right", .nursing, startsTimer: true, baseScore: 7.1),
                candidate("pumping", "Pump", "Timer", "drop.circle.fill", "cyan", "quick-log/pumping", .pumping, startsTimer: true, baseScore: 6.6),
                candidate("diaper", "Diaper", nil, "drop.fill", "teal", "quick-log/diaper", .diaper, baseScore: 7.0),
                candidate("potty", "Potty", nil, "figure.child", "teal", "quick-log/child-potty", .potty, baseScore: 5.7),
                candidate("tummy-time", "Tummy", "Timer", "figure.play", "green", "quick-log/tummy-time", .activity, startsTimer: true, baseScore: 5.4) {
                    $0.type == .activity && $0.activityType == .tummyTime
                },
                candidate("medicine", "Medicine", nil, "cross.case.fill", "red", "quick-log/medicine", .medicine, baseScore: 5.2),
                candidate("temperature", "Temp", nil, "thermometer.medium", "red", "quick-log/temperature", .temperature, baseScore: 4.8)
            ]
        case .dog:
            [
                candidate("food", "Food", nil, "fork.knife", "orange", "quick-log/food", .food, baseScore: 8.0),
                candidate("water", "Water", nil, "drop.fill", "cyan", "quick-log/water", .water, baseScore: 7.6),
                candidate("walk", "Walk", "Timer", "figure.walk", "green", "quick-log/walk", .walk, startsTimer: true, baseScore: 7.0),
                candidate("pee", "Pee", nil, "pawprint.fill", "teal", "quick-log/pee", .potty, baseScore: 6.8) {
                    $0.type == .potty && ($0.dogDetails.pottyType == .pee || $0.dogDetails.pottyType == .both)
                },
                candidate("poop", "Poop", nil, "pawprint.circle.fill", "teal", "quick-log/poop", .potty, baseScore: 6.4) {
                    $0.type == .potty && ($0.dogDetails.pottyType == .poop || $0.dogDetails.pottyType == .both)
                },
                candidate("medicine", "Medicine", nil, "cross.case.fill", "red", "quick-log/medicine", .medicine, baseScore: 5.8),
                candidate("training", "Training", "Timer", "graduationcap.fill", "purple", "quick-log/training", .training, startsTimer: true, baseScore: 5.4)
            ]
        }
    }

    private static func candidate(
        _ id: String,
        _ title: String,
        _ subtitle: String?,
        _ systemImage: String,
        _ tintName: String,
        _ destinationPath: String,
        _ eventType: EventType,
        startsTimer: Bool = false,
        baseScore: Double,
        matches: @escaping (BabyEvent) -> Bool
    ) -> QuickLogActionCandidate {
        QuickLogActionCandidate(
            action: QuickLogActionSnapshot(
                id: id,
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tintName: tintName,
                destinationPath: destinationPath
            ),
            eventType: eventType,
            startsTimer: startsTimer,
            baseScore: baseScore,
            matches: matches
        )
    }

    private static func candidate(
        _ id: String,
        _ title: String,
        _ subtitle: String?,
        _ systemImage: String,
        _ tintName: String,
        _ destinationPath: String,
        _ eventType: EventType,
        startsTimer: Bool = false,
        baseScore: Double
    ) -> QuickLogActionCandidate {
        candidate(
            id,
            title,
            subtitle,
            systemImage,
            tintName,
            destinationPath,
            eventType,
            startsTimer: startsTimer,
            baseScore: baseScore
        ) { $0.type == eventType }
    }

    private static func groupedCareSessions(_ events: [BabyEvent]) -> [Date] {
        let dates = events.filter {
            $0.type == .feed || $0.type == .nursing
        }.map(\.startDate).sorted()
        var sessions = [Date]()
        for date in dates {
            if let last = sessions.last, date.timeIntervalSince(last) < 45 * 60 {
                continue
            }
            sessions.append(date)
        }
        return sessions
    }

    private static func runningLabel(for event: BabyEvent) -> String {
        switch event.type {
        case .sleep: "Sleeping"
        case .nursing: "Nursing"
        case .pumping: "Pumping"
        case .feed: "Feeding"
        case .activity: event.activityType?.displayName ?? "Activity"
        default: event.type.displayName
        }
    }
}
