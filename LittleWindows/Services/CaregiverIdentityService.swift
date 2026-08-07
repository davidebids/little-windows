import Foundation
import SwiftData

enum CaregiverIdentityService {
    static let currentCaregiverNameKey = "currentCaregiverName"
    static let primaryCaregiverNameKey = "caregiverOne"
    static let needsLogNamePromptKey = "familySync.needsLogNamePrompt"
    static let familySyncCaregiverNamesKey = "familySync.acceptedCaregiverNames"
    static let lastModifiedAtKey = "caregiverIdentity.lastModifiedAt"

    private static let iCloudPayloadKey = "caregiverIdentity.v1"

    @MainActor
    private static var iCloudChangeObserver: NSObjectProtocol?

    private struct ICloudPayload: Codable {
        var version: Int
        var currentName: String?
        var primaryName: String?
        var updatedAt: Date
    }

    static func currentCaregiverName(
        currentName: String,
        primaryName: String,
        fallback: String = "Caregiver"
    ) -> String {
        let trimmedCurrent = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty {
            return trimmedCurrent
        }

        let trimmedPrimary = primaryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrimary.isEmpty {
            return trimmedPrimary
        }

        return fallback
    }

    static func currentCaregiverName(
        defaults: UserDefaults = .standard,
        fallback: String = "Caregiver"
    ) -> String {
        currentCaregiverName(
            currentName: defaults.string(forKey: currentCaregiverNameKey) ?? "",
            primaryName: defaults.string(forKey: primaryCaregiverNameKey) ?? "",
            fallback: fallback
        )
    }

    static func seedCurrentCaregiverNameIfNeeded(
        from primaryName: String,
        defaults: UserDefaults = .standard
    ) {
        let existing = defaults.string(forKey: currentCaregiverNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return }

        let trimmedPrimary = primaryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrimary.isEmpty else { return }
        storeIdentity(
            currentName: trimmedPrimary,
            primaryName: trimmedPrimary,
            defaults: defaults
        )
    }

    static func hasExplicitCurrentCaregiverName(defaults: UserDefaults = .standard) -> Bool {
        let name = defaults.string(forKey: currentCaregiverNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty
    }

    static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }

    static func namesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedName(lhs), let rhs = normalizedName(rhs) else { return false }
        return lhs == rhs
    }

    static func familySyncCaregiverNames(rawValue: String?) -> [String] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return uniqueNames(decoded)
    }

    static func familySyncCaregiverNames(defaults: UserDefaults = .standard) -> [String] {
        familySyncCaregiverNames(
            rawValue: defaults.string(forKey: familySyncCaregiverNamesKey)
        )
    }

    static func storeFamilySyncCaregiverNames(
        _ names: [String],
        defaults: UserDefaults = .standard
    ) {
        let values = uniqueNames(names)
        guard let data = try? JSONEncoder().encode(values),
              let rawValue = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(rawValue, forKey: familySyncCaregiverNamesKey)
    }

    static func storeIdentity(
        currentName: String,
        primaryName: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        let current = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = primaryName.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(current, forKey: currentCaregiverNameKey)
        defaults.set(primary, forKey: primaryCaregiverNameKey)
        defaults.set(now, forKey: lastModifiedAtKey)
        publishIdentityToICloud(defaults: defaults, now: now)
    }

    static func restoreIdentityIfMissing(
        currentName: String?,
        primaryName: String?,
        defaults: UserDefaults = .standard
    ) {
        guard !hasExplicitCurrentCaregiverName(defaults: defaults) else { return }
        let current = trimmedName(currentName) ?? trimmedName(primaryName)
        guard let current, !isPlaceholderName(current) else { return }
        let existingPrimary = trimmedName(defaults.string(forKey: primaryCaregiverNameKey))
        let restoredPrimary = if let primary = trimmedName(primaryName),
                                 !isPlaceholderName(primary) {
            primary
        } else if let existingPrimary, !isPlaceholderName(existingPrimary) {
            existingPrimary
        } else {
            current
        }
        storeIdentity(
            currentName: current,
            primaryName: restoredPrimary,
            defaults: defaults
        )
    }

    @MainActor
    @discardableResult
    static func restoreFromHistoryIfUnambiguous(
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard !hasExplicitCurrentCaregiverName(defaults: defaults) else { return nil }

        do {
            var candidates = try context.fetch(FetchDescriptor<BabyEvent>()).map(\.caregiverName)
            candidates.append(contentsOf: try context.fetch(
                FetchDescriptor<DoctorAppointment>()
            ).map(\.caregiverName))
            candidates.append(contentsOf: try context.fetch(
                FetchDescriptor<MilestoneEntry>()
            ).map(\.caregiverName))

            guard let recovered = recoverableHistoricalName(from: candidates) else { return nil }
            let existingPrimary = trimmedName(defaults.string(forKey: primaryCaregiverNameKey))
            storeIdentity(
                currentName: recovered,
                primaryName: existingPrimary.map { isPlaceholderName($0) ? recovered : $0 }
                    ?? recovered,
                defaults: defaults
            )
            return recovered
        } catch {
            return nil
        }
    }

    static func recoverableHistoricalName(from values: [String?]) -> String? {
        var namesByNormalizedValue = [String: String]()
        for value in values {
            guard let trimmed = trimmedName(value),
                  !isPlaceholderName(trimmed),
                  let normalized = normalizedName(trimmed) else {
                continue
            }
            namesByNormalizedValue[normalized] = namesByNormalizedValue[normalized] ?? trimmed
        }
        guard namesByNormalizedValue.count == 1 else { return nil }
        return namesByNormalizedValue.values.first
    }

    @MainActor
    static func startICloudSync(
        defaults: UserDefaults = .standard,
        store: NSUbiquitousKeyValueStore = .default
    ) {
        guard PersistenceService.isICloudSyncEnabled(defaults: defaults) else { return }
        _ = store.synchronize()
        reconcileWithICloud(defaults: defaults, store: store)

        guard iCloudChangeObserver == nil else { return }
        iCloudChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in
            Task { @MainActor in
                reconcileWithICloud(defaults: .standard, store: .default)
            }
        }
    }

    static func iCloudPayloadData(
        currentName: String?,
        primaryName: String?,
        updatedAt: Date
    ) -> Data? {
        let payload = ICloudPayload(
            version: 1,
            currentName: trimmedName(currentName),
            primaryName: trimmedName(primaryName),
            updatedAt: updatedAt
        )
        return try? JSONEncoder().encode(payload)
    }

    @discardableResult
    static func applyICloudPayloadData(
        _ data: Data,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let payload = try? JSONDecoder().decode(ICloudPayload.self, from: data),
              payload.version == 1 else {
            return false
        }
        let localUpdatedAt = defaults.object(forKey: lastModifiedAtKey) as? Date
        if hasExplicitCurrentCaregiverName(defaults: defaults),
           let localUpdatedAt,
           payload.updatedAt <= localUpdatedAt {
            return false
        }
        let current = trimmedName(payload.currentName) ?? trimmedName(payload.primaryName)
        guard let current, !isPlaceholderName(current) else { return false }
        let primary = trimmedName(payload.primaryName).flatMap {
            isPlaceholderName($0) ? nil : $0
        } ?? current
        defaults.set(current, forKey: currentCaregiverNameKey)
        defaults.set(primary, forKey: primaryCaregiverNameKey)
        defaults.set(payload.updatedAt, forKey: lastModifiedAtKey)
        return true
    }

    private static func publishIdentityToICloud(
        defaults: UserDefaults,
        now: Date,
        store: NSUbiquitousKeyValueStore = .default
    ) {
        let currentName = trimmedName(defaults.string(forKey: currentCaregiverNameKey))
        let primaryName = trimmedName(defaults.string(forKey: primaryCaregiverNameKey))
        guard PersistenceService.isICloudSyncEnabled(defaults: defaults),
              [currentName, primaryName].compactMap({ $0 })
                .contains(where: { !isPlaceholderName($0) }),
              let data = iCloudPayloadData(
                currentName: currentName,
                primaryName: primaryName,
                updatedAt: now
              ) else {
            return
        }
        store.set(data, forKey: iCloudPayloadKey)
        _ = store.synchronize()
    }

    @MainActor
    private static func reconcileWithICloud(
        defaults: UserDefaults,
        store: NSUbiquitousKeyValueStore
    ) {
        if let data = store.data(forKey: iCloudPayloadKey) {
            if applyICloudPayloadData(data, defaults: defaults) {
                SystemIntegrationReconciler.requestReconciliation()
            } else if hasExplicitCurrentCaregiverName(defaults: defaults) {
                let localUpdatedAt = defaults.object(forKey: lastModifiedAtKey) as? Date ?? Date()
                publishIdentityToICloud(defaults: defaults, now: localUpdatedAt, store: store)
            }
        } else if hasExplicitCurrentCaregiverName(defaults: defaults) {
            let now = defaults.object(forKey: lastModifiedAtKey) as? Date ?? Date()
            defaults.set(now, forKey: lastModifiedAtKey)
            publishIdentityToICloud(defaults: defaults, now: now, store: store)
        }
    }

    private static func trimmedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isPlaceholderName(_ value: String) -> Bool {
        guard let normalized = normalizedName(value) else { return true }
        return ["caregiver", "caregiver 1", "caregiver 2"].contains(normalized)
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = normalizedName(trimmed),
                  seen.insert(normalized).inserted else {
                return nil
            }
            return trimmed
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
