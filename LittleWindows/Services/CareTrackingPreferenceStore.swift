import Foundation
import SwiftData

enum CareTodayLayout: String, Codable, CaseIterable, Identifiable {
    case full, essentials
    var id: String { rawValue }
    var title: String { self == .full ? "Full" : "Essentials" }
}

enum CareTodaySection: String, Codable, CaseIterable, Identifiable {
    case actions, medicationDue, activeTimers, weather, prediction, sleepPlan, solids, routines, timeline, guides, appointments, summary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .actions: "Logging buttons"
        case .medicationDue: "Medication due"
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

extension CareRoutineStepAction {
    var trackingPromptSection: CareTodaySection? {
        switch self {
        case .openAgeGuide, .openPuppyGuide: .guides
        case .openAppointments: .appointments
        default: nil
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

    func hasSameCareContent(as previous: Self) -> Bool {
        version == previous.version && Set(fields.keys).union(previous.fields.keys).allSatisfy { key in
            key.hasPrefix("outdoor.") || fields[key]?.value == previous.fields[key]?.value
        }
    }

    var layout: CareTodayLayout {
        fields["layout"]?.value.first.flatMap(CareTodayLayout.init(rawValue:)) ?? .full
    }

    var pausedTypes: Set<EventType> {
        Set(EventType.allCases.filter { fields["paused.\($0.rawValue)"]?.value == ["true"] })
    }

    func allows(_ type: EventType) -> Bool { fields["paused.\(type.rawValue)"]?.value != ["true"] }

    func allowsRoutineStep(eventType: EventType?, action: CareRoutineStepAction) -> Bool {
        (eventType.map(allows) ?? true) && (action.trackingPromptSection.map(allowsPrompts) ?? true)
    }

    func allowsPrompts(_ section: CareTodaySection) -> Bool {
        guard fields["prompts.\(section.rawValue)"]?.value != ["false"] else { return false }
        switch section {
        case .prediction, .sleepPlan: return allows(.sleep)
        case .solids: return allows(.feed)
        case .medicationDue: return allows(.medicine)
        default: return true
        }
    }

    func shows(_ section: CareTodaySection) -> Bool {
        guard allowsPrompts(section) else { return false }
        if let choice = fields["section.\(layout.rawValue).\(section.rawValue)"]?.value.first {
            return choice == "true"
        }
        return Self.defaultVisibility(of: section, in: layout)
    }

    static func defaultVisibility(of section: CareTodaySection, in layout: CareTodayLayout) -> Bool {
        layout == .full ? section != .medicationDue : [.actions, .activeTimers, .medicationDue].contains(section)
    }

    mutating func selectLayout(_ layout: CareTodayLayout, for type: CareProfileType, hidden: Set<EventType> = []) {
        // Import legacy action choices once; later Full edits must not change Essentials.
        if (layout == .essentials || self.layout == .essentials), fields["essentials"] == nil {
            set("essentials", value: configuredEssentials(for: type, hidden: hidden).map(\.rawValue))
        }
        set("layout", value: [layout.rawValue])
    }

    mutating func resetCurrentLayout(for type: CareProfileType) {
        for section in CareTodaySection.allCases {
            set("section.\(layout.rawValue).\(section.rawValue)", value: [String(Self.defaultVisibility(of: section, in: layout))])
        }
        if layout == .essentials {
            set("essentials", value: Self.defaultEssentials(for: type).map(\.rawValue))
        } else {
            for type in EventType.cases(for: type) { set("hidden.\(type.rawValue)", value: ["false"]) }
        }
    }

    func showsMedicationDueCard(
        scheduledAt: Date?, profileType: CareProfileType, hidden: Set<EventType> = [],
        now: Date = Date(), calendar: Calendar = .current
    ) -> Bool {
        guard shows(.medicationDue), let scheduledAt,
              scheduledAt >= now.addingTimeInterval(-24 * 60 * 60),
              let dayEnd = calendar.dateInterval(of: .day, for: now)?.end,
              scheduledAt < dayEnd else { return false }
        return layout != .essentials || !shows(.actions) || !essentialTypes(for: profileType, hidden: hidden).contains(.medicine)
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
        case .child: [.sleep, .feed, .diaper]
        case .adult: [.medicine, .symptom, .bloodPressure, .sleep]
        case .dog: [.food, .potty, .walk, .rest]
        }
    }

    mutating func set(_ key: String, value: [String], now: Date = Date(), revision: String = UUID().uuidString) {
        guard fields[key]?.value != value else { return }
        // A deliberate edit must follow a value already observed from another
        // device, even if that device's wall clock is ahead of this one.
        let observed = fields[key]?.updatedAt.addingTimeInterval(0.001) ?? now
        fields[key] = CareTrackingPreferenceValue(value: value, updatedAt: max(now, observed), revision: revision)
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

    func needsSystemReconciliation(comparedTo previous: Self) -> Bool {
        guard version == previous.version else { return true }
        return Set(fields.keys).union(previous.fields.keys).contains { key in
            // Today layout, section visibility, and ordering do not change
            // reminder policy or the widgets' independent action choices.
            guard key != "layout", key != "essentials", !key.hasPrefix("section."), !key.hasPrefix("outdoor.") else { return false }
            return fields[key]?.value != previous.fields[key]?.value
        }
    }
}

protocol CareTrackingCloudStore {
    var dictionaryRepresentation: [String: Any] { get }
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CareTrackingCloudStore {}

@MainActor
enum CareTrackingPreferenceStore {
    nonisolated static let changedNotification = Notification.Name("CareTrackingPreferences.changed")
    nonisolated static let prefix = "careTracking.v1."
    private static var observer: NSObjectProtocol?
    private nonisolated static let decoded = TrackingPreferenceDecodeCache()

    nonisolated static func preferences(profileID: UUID?, defaults: UserDefaults = .standard) -> CareTrackingPreferences {
        InteractionPerformanceAudit.count(Thread.isMainThread ? "preferences.read.main" : "preferences.read.background")
        guard let profileID,
              let data = defaults.data(forKey: key(profileID)) else { return CareTrackingPreferences() }
        return decoded.preferences(in: data)
    }

    nonisolated static func allows(_ type: EventType, profileID: UUID?) -> Bool {
        preferences(profileID: profileID).allows(type)
    }

    nonisolated static func allowsPrompts(_ section: CareTodaySection, profileID: UUID?) -> Bool {
        preferences(profileID: profileID).allowsPrompts(section)
    }

    static func update(
        profileID: UUID, defaults: UserDefaults = .standard,
        store: CareTrackingCloudStore = NSUbiquitousKeyValueStore.default,
        _ change: (inout CareTrackingPreferences) -> Void
    ) {
        if PersistenceService.isICloudSyncEnabled(defaults: defaults) {
            reconcile(profileID: profileID, defaults: defaults, store: store)
        }
        var value = preferences(profileID: profileID, defaults: defaults)
        let previous = value
        change(&value)
        guard value != previous else { return }
        save(value, profileID: profileID, defaults: defaults)
        if PersistenceService.isICloudSyncEnabled(defaults: defaults) {
            reconcile(profileID: profileID, defaults: defaults, store: store)
        }
        if defaults === UserDefaults.standard {
            notify(profileID, needsSystemReconciliation: value.needsSystemReconciliation(comparedTo: previous), careChanged: !value.hasSameCareContent(as: previous))
        }
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

    static func synchronize(
        defaults: UserDefaults = .standard,
        store: CareTrackingCloudStore = NSUbiquitousKeyValueStore.default
    ) {
        guard PersistenceService.isICloudSyncEnabled(defaults: defaults) else { return }
        let keys = Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) })
            .union(store.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) })
        for key in keys {
            guard let profileID = UUID(uuidString: String(key.dropFirst(prefix.count))) else { continue }
            reconcile(profileID: profileID, defaults: defaults, store: store)
        }
    }

    private static func reconcile(profileID: UUID, defaults: UserDefaults, store: CareTrackingCloudStore) {
        let local = preferences(profileID: profileID, defaults: defaults)
        let remote = store.data(forKey: key(profileID)).flatMap {
            try? JSONDecoder().decode(CareTrackingPreferences.self, from: $0)
        } ?? CareTrackingPreferences()
        // An older build must not overwrite a newer preference schema.
        guard remote.version == 1 else { return }
        let merged = local.merging(remote)
        if merged != local {
            save(merged, profileID: profileID, defaults: defaults)
            if defaults === UserDefaults.standard {
                notify(profileID, needsSystemReconciliation: merged.needsSystemReconciliation(comparedTo: local), careChanged: !merged.hasSameCareContent(as: local))
            }
        }
        if merged != remote, let data = try? JSONEncoder().encode(merged) {
            // Writes synchronize automatically. Avoid forcing disk/cloud work
            // from interactive edit handlers; launch/foreground still refresh.
            store.set(data, forKey: key(profileID))
        }
    }

    private static func save(_ preferences: CareTrackingPreferences, profileID: UUID, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key(profileID))
    }

    nonisolated static func affectsCare(_ notification: Notification) -> Bool { notification.userInfo?["careChanged"] as? Bool ?? true }

    private static func notify(_ profileID: UUID, needsSystemReconciliation: Bool, careChanged: Bool) {
        NotificationCenter.default.post(name: changedNotification, object: profileID, userInfo: ["careChanged": careChanged])
        guard needsSystemReconciliation else { return }
        Task { await NotificationManager.shared.cancelPausedTrackingReminders() }
        SystemIntegrationReconciler.requestReconciliation()
    }

    nonisolated static func key(_ profileID: UUID) -> String { prefix + profileID.uuidString }

    nonisolated static func allowsRoutine(_ routine: CareRoutine, steps: [CareRoutineStep]? = nil) -> Bool {
        guard let profileID = routine.profileID else { return true }
        let preferences = preferences(profileID: profileID)
        let routineID = routine.id
        let descriptor = FetchDescriptor<CareRoutineStep>(predicate: #Predicate { $0.routineID == routineID })
        let resolvedSteps = steps ?? ((try? routine.modelContext?.fetch(descriptor)) ?? [])
        return preferences.allowsPrompts(.routines) && resolvedSteps.filter { $0.routineID == routine.id }.allSatisfy {
            preferences.allowsRoutineStep(eventType: $0.eventType, action: $0.action)
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
            let sections = (userInfo["trackingPromptSectionRawValues"] as? [String] ?? []).compactMap(CareTodaySection.init(rawValue:))
            return preferences.allowsPrompts(.routines) && types.allSatisfy(preferences.allows)
                && sections.allSatisfy(preferences.allowsPrompts)
        }
        return true
    }
}

/// The encoded value is the key, so external defaults/cloud edits are visible
/// on the very next read. No time-based expiration or notification dependency.
private final class TrackingPreferenceDecodeCache: @unchecked Sendable {
    private final class Entry {
        let preferences: CareTrackingPreferences
        init(_ preferences: CareTrackingPreferences) { self.preferences = preferences }
    }
    private let cache: NSCache<NSData, Entry> = {
        let cache = NSCache<NSData, Entry>()
        cache.countLimit = 256; cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()
    func preferences(in data: Data) -> CareTrackingPreferences {
        let key = data as NSData
        if let entry = cache.object(forKey: key) { return entry.preferences }
        InteractionPerformanceAudit.count(Thread.isMainThread ? "preferences.decode.main" : "preferences.decode.background")
        let decoded = try? JSONDecoder().decode(CareTrackingPreferences.self, from: data)
        let value: CareTrackingPreferences
        if let decoded, decoded.version == 1 { value = decoded } else { value = CareTrackingPreferences() }
        cache.setObject(Entry(value), forKey: key, cost: data.count * 2)
        return value
    }
}
