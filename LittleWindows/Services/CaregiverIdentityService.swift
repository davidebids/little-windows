import Foundation

enum CaregiverIdentityService {
    static let currentCaregiverNameKey = "currentCaregiverName"
    static let primaryCaregiverNameKey = "caregiverOne"
    static let needsLogNamePromptKey = "familySync.needsLogNamePrompt"
    static let familySyncCaregiverNamesKey = "familySync.acceptedCaregiverNames"

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
        defaults.set(trimmedPrimary, forKey: currentCaregiverNameKey)
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
