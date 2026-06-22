import Foundation

enum CaregiverIdentityService {
    static let currentCaregiverNameKey = "currentCaregiverName"
    static let primaryCaregiverNameKey = "caregiverOne"
    static let needsLogNamePromptKey = "familySync.needsLogNamePrompt"

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
}
