import Foundation
import SwiftData

enum CareTodayLayout: String, Codable, CaseIterable, Identifiable {
    case full, essentials
    var id: String { rawValue }
    var title: String { self == .full ? "Full" : "Essentials" }
}

enum CareTodaySection: String, Codable, CaseIterable, Identifiable {
    case actions, activeTimers, weather, prediction, sleepPlan, solids, routines, timeline, guides, appointments, summary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .actions: "Logging buttons"
        case .activeTimers: "Active timers"
        case .weather: "Weather"
        case .prediction: "Sleep prediction"
        case .sleepPlan: "Sleep planning"
        case .solids: "Solids"
        case .routines: "Routines"
        case .timeline: "Today's timeline"
        case .guides: "Guides"
        case .appointments: "Appointments"
        case .summary: "Daily summary"
        }
    }

    func applies(to type: CareProfileType) -> Bool {
        switch self {
        case .prediction, .sleepPlan, .solids: type == .child
        case .guides: type != .adult
        case .summary: type == .dog
        default: true
        }
    }
}

/// Each field carries its own revision so offline edits to different categories
/// merge without replacing one another. False values are retained as tombstones.
struct CareTrackingPreferenceValue: Codable, Equatable, Sendable {
    var value: [String]
    var updatedAt: Date
    var revision: String

    func isNewer(than other: Self) -> Bool {
        updatedAt == other.updatedAt ? revision > other.revision : updatedAt > other.updatedAt
    }
}

struct CareTrackingPreferences: Codable, Equatable, Sendable {
    var version = 1
    var fields: [String: CareTrackingPreferenceValue] = [:]

    var layout: CareTodayLayout {
        fields["layout"]?.value.first.flatMap(CareTodayLayout.init(rawValue:)) ?? .full
    }

    var pausedTypes: Set<EventType> {
        Set(EventType.allCases.filter { fields["paused.\($0.rawValue)"]?.value == ["true"] })
    }

    func allows(_ type: EventType) -> Bool { !pausedTypes.contains(type) }

    func allowsPrompts(_ section: CareTodaySection) -> Bool {
        guard fields["prompts.\(section.rawValue)"]?.value != ["false"] else { return false }
        switch section {
        case .prediction, .sleepPlan: return allows(.sleep)
        case .solids: return allows(.feed)
        default: return true
        }
    }

    func shows(_ section: CareTodaySection) -> Bool {
        guard allowsPrompts(section) else { return false }
        if let choice = fields["section.\(layout.rawValue).\(section.rawValue)"]?.value.first {
            return choice == "true"
        }
        return layout == .full || section == .actions
    }

    func essentialTypes(for type: CareProfileType, hidden: Set<EventType> = []) -> [EventType] {
        let selected = configuredEssentials(for: type, hidden: hidden)
        return selected.filter { allows($0) }
    }

    func configuredEssentials(for type: CareProfileType, hidden: Set<EventType> = []) -> [EventType] {
        let raw = fields["essentials"]?.value
            ?? Self.defaultEssentials(for: type).filter { !hidden.contains($0) }.map(\.rawValue)
        let supported = Set(EventType.cases(for: type))
        var seen = Set<EventType>()
        return raw.compactMap(EventType.init(rawValue:)).filter {
            supported.contains($0) && seen.insert($0).inserted
        }
    }

    static func defaultEssentials(for type: CareProfileType) -> [EventType] {
        switch type {
        case .child: [.sleep, .feed, .diaper, .medicine]
        case .adult: [.medicine, .symptom, .bloodPressure, .sleep]
        case .dog: [.food, .potty, .walk, .rest]
        }
    }

    mutating func set(_ key: String, value: [String], now: Date = Date(), revision: String = UUID().uuidString) {
        fields[key] = CareTrackingPreferenceValue(value: value, updatedAt: now, revision: revision)
    }

    func merging(_ other: Self) -> Self {
        guard other.version == 1 else { return self }
        var result = self
        for (key, value) in other.fields {
            if result.fields[key].map({ value.isNewer(than: $0) }) ?? true {
                result.fields[key] = value
            }
        }
        return result
    }
}

@MainActor
enum CareTrackingPreferenceStore {
    nonisolated static let changedNotification = Notification.Name("CareTrackingPreferences.changed")
    nonisolated static let prefix = "careTracking.v1."
    private static var observer: NSObjectProtocol?

    nonisolated static func preferences(profileID: UUID?, defaults: UserDefaults = .standard) -> CareTrackingPreferences {
        guard let profileID,
              let data = defaults.data(forKey: key(profileID)),
              let value = try? JSONDecoder().decode(CareTrackingPreferences.self, from: data),
              value.version == 1 else { return CareTrackingPreferences() }
        return value
    }

    nonisolated static func allows(_ type: EventType, profileID: UUID?) -> Bool {
        preferences(profileID: profileID).allows(type)
    }

    nonisolated static func allowsPrompts(_ section: CareTodaySection, profileID: UUID?) -> Bool {
        preferences(profileID: profileID).allowsPrompts(section)
    }

    static func update(profileID: UUID, _ change: (inout CareTrackingPreferences) -> Void) {
        var value = preferences(profileID: profileID)
        change(&value)
        save(value, profileID: profileID)
        if PersistenceService.isICloudSyncEnabled() {
            reconcile(profileID: profileID, store: .default)
        }
        notify(profileID)
    }

    static func startICloudSync() {
        guard PersistenceService.isICloudSyncEnabled() else { return }
        let store = NSUbiquitousKeyValueStore.default
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store, queue: .main
            ) { _ in
                Task { @MainActor in synchronize() }
            }
        }
        _ = store.synchronize()
        synchronize()
    }

    private static func synchronize() {
        guard PersistenceService.isICloudSyncEnabled() else { return }
        let store = NSUbiquitousKeyValueStore.default
        let keys = Set(UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) })
            .union(store.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) })
        for key in keys {
            guard let profileID = UUID(uuidString: String(key.dropFirst(prefix.count))) else { continue }
            reconcile(profileID: profileID, store: store)
        }
    }

    private static func reconcile(profileID: UUID, store: NSUbiquitousKeyValueStore) {
        let local = preferences(profileID: profileID)
        let remote = store.data(forKey: key(profileID)).flatMap {
            try? JSONDecoder().decode(CareTrackingPreferences.self, from: $0)
        } ?? CareTrackingPreferences()
        // An older build must not overwrite a newer preference schema.
        guard remote.version == 1 else { return }
        let merged = local.merging(remote)
        if merged != local {
            save(merged, profileID: profileID)
            notify(profileID)
        }
        if merged != remote, let data = try? JSONEncoder().encode(merged) {
            store.set(data, forKey: key(profileID))
            _ = store.synchronize()
        }
    }

    private static func save(_ preferences: CareTrackingPreferences, profileID: UUID) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key(profileID))
    }

    private static func notify(_ profileID: UUID) {
        NotificationCenter.default.post(name: changedNotification, object: profileID)
        Task { await NotificationManager.shared.cancelPausedTrackingReminders() }
        SystemIntegrationReconciler.requestReconciliation()
    }

    nonisolated static func key(_ profileID: UUID) -> String { prefix + profileID.uuidString }

    static func allowsRoutine(_ routine: CareRoutine, steps: [CareRoutineStep]? = nil) -> Bool {
        guard let profileID = routine.profileID else { return true }
        let preferences = preferences(profileID: profileID)
        let resolvedSteps = steps ?? ((try? routine.modelContext?.fetch(FetchDescriptor<CareRoutineStep>())) ?? [])
        return preferences.allowsPrompts(.routines) && resolvedSteps.filter { $0.routineID == routine.id }.allSatisfy {
            $0.eventType.map(preferences.allows) ?? true
        }
    }

    /// Applied immediately before publishing a notification as well as when
    /// clearing pending requests, including requests scheduled before a pause.
    nonisolated static func allowsNotification(
        identifier: String, userInfo: [AnyHashable: Any], defaults: UserDefaults = .standard
    ) -> Bool {
        let profileID = (userInfo["profileID"] as? String).flatMap(UUID.init(uuidString:))
            ?? (userInfo["deepLink"] as? String).flatMap { raw -> UUID? in
                guard let url = URL(string: raw), url.host == "profile" else { return nil }
                return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
            }
        guard let profileID else { return true }
        let preferences = preferences(profileID: profileID, defaults: defaults)
        if identifier.contains("littlewindow.") || identifier.contains("sleepPressure.") || identifier.contains("activeSleepPlan.") {
            return preferences.allows(.sleep)
        }
        if identifier.hasPrefix("medication.") { return preferences.allows(.medicine) }
        if identifier.hasPrefix("solids.digestive.") {
            return preferences.allows(.feed) && preferences.allows(.diaper)
        }
        if identifier.hasPrefix("solids.") { return preferences.allows(.feed) }
        if identifier.hasPrefix("ageguide.") { return preferences.allowsPrompts(.guides) }
        if identifier.hasPrefix("appointment.") { return preferences.allowsPrompts(.appointments) }
        if identifier.hasPrefix("routine.") {
            let types = (userInfo["trackingCategoryRawValues"] as? [String] ?? []).compactMap(EventType.init(rawValue:))
            return preferences.allowsPrompts(.routines) && types.allSatisfy(preferences.allows)
        }
        return true
    }
}
