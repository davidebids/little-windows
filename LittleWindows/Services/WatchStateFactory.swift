import Foundation
import SwiftData

enum WatchFavoritePreferenceStore {
    static let maximumFavoriteCount = 6

    private static let keyPrefix = "watch.favoriteActionIDs"

    static func customActionIDs(profileID: UUID) -> [String]? {
        let defaults = UserDefaults.standard
        let preferenceKey = key(profileID: profileID)
        guard defaults.object(forKey: preferenceKey) != nil else { return nil }
        return defaults.stringArray(forKey: preferenceKey) ?? []
    }

    static func setCustomActionIDs(_ actionIDs: [String], profileID: UUID) {
        var seen: Set<String> = []
        let sanitized = actionIDs.compactMap { actionID -> String? in
            let canonicalID = WatchActionCatalog.canonicalActionID(for: actionID)
            guard seen.insert(canonicalID).inserted else { return nil }
            return canonicalID
        }.prefix(maximumFavoriteCount)
        let resolved = Array(sanitized)
        guard !resolved.isEmpty else {
            useSmartFavorites(profileID: profileID)
            return
        }
        UserDefaults.standard.set(resolved, forKey: key(profileID: profileID))
    }

    static func useSmartFavorites(profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(profileID: profileID))
    }

    static func resolvedFavorites(
        smartFavorites: [WatchActionSnapshot],
        allActions: [WatchActionSnapshot],
        profileID: UUID
    ) -> [WatchActionSnapshot] {
        guard let customIDs = customActionIDs(profileID: profileID),
              !customIDs.isEmpty else {
            return Array(smartFavorites.prefix(maximumFavoriteCount))
        }
        let actionsByID = Dictionary(uniqueKeysWithValues: allActions.map { ($0.id, $0) })
        let customActions = customIDs.compactMap { actionsByID[$0] }
        return customActions.isEmpty
            ? Array(smartFavorites.prefix(maximumFavoriteCount))
            : Array(customActions.prefix(maximumFavoriteCount))
    }

    private static func key(profileID: UUID) -> String {
        "\(keyPrefix).\(profileID.uuidString)"
    }
}

@MainActor
enum WatchStateFactory {
    static func make(context: ModelContext, now: Date = Date()) -> WatchCompanionState {
        let profiles = ((try? context.fetch(FetchDescriptor<BabyProfile>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\BabyProfile.createdAt)]
        ))) ?? [])
        let selectedProfile = ProfileService.shared.selectedProfile(in: profiles)
            ?? profiles.first
        guard let selectedProfile else {
            return WatchCompanionState(
                schemaVersion: WatchCompanionProtocol.schemaVersion,
                generatedAt: now,
                revision: UUID(),
                selectedProfileID: nil,
                profiles: [],
                activeTimers: [],
                prediction: nil,
                todayMetrics: [],
                favoriteActions: [],
                allActions: []
            )
        }

        let profileID = selectedProfile.id
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -14,
            to: Calendar.current.startOfDay(for: now)
        ) ?? now
        var descriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate { event in
                event.profileID == profileID
                    && (event.startDate >= recentCutoff || event.endDate == nil)
            },
            sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 600
        let events = (try? context.fetch(descriptor)) ?? []
        var activeTimerDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate { $0.endDate == nil }
        )
        activeTimerDescriptor.fetchLimit = 300
        let activeTimerEvents = ((try? context.fetch(activeTimerDescriptor)) ?? [])
            .filter { $0.isTimerDraft && $0.timerStateRawValue != nil }
        var activeTimerCategoriesByProfile: [UUID: Set<String>] = [:]
        for event in activeTimerEvents {
            guard let eventProfileID = event.profileID else { continue }
            activeTimerCategoriesByProfile[eventProfileID, default: []]
                .insert(event.type.rawValue)
        }
        let hiddenCategoriesByProfile = Dictionary(uniqueKeysWithValues: profiles.map {
            (
                $0.id,
                Set(CareCategoryPreferenceStore.hiddenTypes(profileID: $0.id).map(\.rawValue))
            )
        })
        let priorSnapshot = WidgetSnapshotService.read()
        let freshSnapshot = WidgetSnapshotService.makeSnapshot(
            profileID: profileID,
            profileType: selectedProfile.profileType,
            profileBirthDate: selectedProfile.birthDate,
            babyName: selectedProfile.name,
            events: events,
            prediction: nil,
            now: now
        )
        let hiddenCategories = hiddenCategoriesByProfile[profileID] ?? []
        let activeTimerCategories = activeTimerCategoriesByProfile[profileID] ?? []
        let allActions = WatchActionCatalog.actions(
            profileTypeRawValue: selectedProfile.profileType.rawValue
        ).filter {
            !hiddenCategories.contains($0.categoryRawValue)
                && !($0.startsTimer && activeTimerCategories.contains($0.categoryRawValue))
        }
        let smartFavoriteActions = smartFavorites(
            from: freshSnapshot.resolvedQuickActions,
            allActions: allActions
        )
        let favoriteActions = WatchFavoritePreferenceStore.resolvedFavorites(
            smartFavorites: smartFavoriteActions,
            allActions: allActions,
            profileID: profileID
        )

        let activeTimers = events.filter {
            $0.isTimerDraft && $0.timerStateRawValue != nil
        }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate > rhs.startDate
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { event in
                let timer = WidgetSnapshotService.activeSnapshot(
                    event: event,
                    profileID: profileID,
                    babyName: selectedProfile.name,
                    additionalActiveCount: 0,
                    now: now
                )
                let elapsedReferenceDate = event.isTimerRunning
                    ? (event.activeTimerSegmentStartDate ?? event.startDate)
                    : now
                return WatchTimerSnapshot(
                    id: event.id,
                    profileID: profileID,
                    title: timer.eventLabel,
                    systemImage: timer.systemImage,
                    displayStartDate: event.timerDisplayStartDate(at: now),
                    isRunning: event.isTimerRunning,
                    elapsedSeconds: event.timerElapsed(at: elapsedReferenceDate),
                    activeNursingSideRawValue: event.activeNursingSide?.rawValue,
                    leftDurationSeconds: event.leftDurationSeconds ?? 0,
                    rightDurationSeconds: event.rightDurationSeconds ?? 0,
                    updatedAt: event.updatedAt,
                    elapsedReferenceDate: elapsedReferenceDate
                )
            }
        let prediction = priorSnapshot.profileID == profileID
            ? priorSnapshot.prediction.map {
                WatchPredictionSnapshot(
                    title: $0.kind,
                    expectedStart: $0.resolvedExpectedStart,
                    windowStart: $0.windowStart,
                    windowEnd: $0.windowEnd,
                    confidenceLabel: $0.confidenceLabel
                )
            }
            : nil
        let currentPrediction = prediction.flatMap {
            $0.windowEnd >= now ? $0 : nil
        }
        let metrics = orderedMetrics(
            freshSnapshot.todaySummary.summaryMetrics ?? []
        ).prefix(6).map {
            WatchMetricSnapshot(
                id: $0.id,
                title: $0.title,
                value: $0.value,
                systemImage: $0.systemImage,
                tintName: $0.tintName
            )
        }

        return WatchCompanionState(
            schemaVersion: WatchCompanionProtocol.schemaVersion,
            generatedAt: now,
            revision: UUID(),
            selectedProfileID: profileID,
            profiles: profiles.map {
                WatchProfileSnapshot(
                    id: $0.id,
                    name: $0.name,
                    profileTypeRawValue: $0.profileType.rawValue,
                    displayColor: $0.displayColor,
                    hiddenCategoryRawValues: Array(
                        hiddenCategoriesByProfile[$0.id] ?? []
                    ).sorted(),
                    activeTimerCategoryRawValues: Array(
                        activeTimerCategoriesByProfile[$0.id] ?? []
                    ).sorted()
                )
            },
            activeTimers: activeTimers,
            prediction: currentPrediction,
            todayMetrics: Array(metrics),
            favoriteActions: favoriteActions,
            allActions: allActions
        )
    }

    static func smartFavorites(
        from quickActions: [QuickLogActionSnapshot],
        allActions: [WatchActionSnapshot]
    ) -> [WatchActionSnapshot] {
        let byID = Dictionary(uniqueKeysWithValues: allActions.map { ($0.id, $0) })
        var result: [WatchActionSnapshot] = []
        for quickAction in quickActions {
            let id = WatchActionCatalog.canonicalActionID(for: quickAction.id)
            guard let action = byID[id], !result.contains(where: { $0.id == id }) else {
                continue
            }
            result.append(action)
            if result.count == WatchFavoritePreferenceStore.maximumFavoriteCount {
                return result
            }
        }
        for action in allActions where !result.contains(where: { $0.id == action.id }) {
            result.append(action)
            if result.count == WatchFavoritePreferenceStore.maximumFavoriteCount {
                break
            }
        }
        return result
    }

    private static func orderedMetrics(
        _ metrics: [CareSummaryMetricSnapshot]
    ) -> [CareSummaryMetricSnapshot] {
        let meaningful = metrics.filter { metric in
            metric.value != "0"
                && metric.value != "0m"
                && metric.value != "0h"
                && metric.value != "0.0 oz"
        }
        let remaining = metrics.filter { metric in
            !meaningful.contains(where: { $0.id == metric.id })
        }
        return meaningful + remaining
    }
}
