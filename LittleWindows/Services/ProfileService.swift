import Foundation
import SwiftData

@MainActor
final class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published private(set) var selectedProfileID: UUID?

    private let selectedProfileKey = "selectedCareProfileID"

    private init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: selectedProfileKey) {
            selectedProfileID = UUID(uuidString: raw)
        }
    }

    func selectedProfile(in profiles: [CareProfile]) -> CareProfile? {
        let active = allActiveProfiles(in: profiles)
        if let selectedProfileID,
           let selected = active.first(where: { $0.id == selectedProfileID }) {
            return selected
        }
        return active.first
    }

    func allActiveProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        profiles
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func allChildProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        profiles
            .filter { $0.profileType == .child && !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func allDogProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        profiles
            .filter { $0.profileType == .dog && !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func ensureSelection(in profiles: [CareProfile]) -> CareProfile? {
        guard let profile = selectedProfile(in: profiles) else {
            selectedProfileID = nil
            UserDefaults.standard.removeObject(forKey: selectedProfileKey)
            return nil
        }
        if selectedProfileID != profile.id {
            switchProfile(profile)
        }
        return profile
    }

    @discardableResult
    func createChildProfile(
        name: String,
        birthDate: Date,
        sex: BabySex,
        notes: String = "",
        displayColor: String? = nil,
        context: ModelContext
    ) -> CareProfile {
        let profile = CareProfile(
            profileType: .child,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: birthDate,
            sex: sex,
            notes: notes,
            displayColor: displayColor
        )
        context.insert(profile)
        switchProfile(profile)
        try? context.save()
        PersistenceService.recordLocalSave()
        return profile
    }

    @discardableResult
    func createDogProfile(
        name: String,
        birthDate: Date,
        sex: BabySex = .unknown,
        adoptionDate: Date? = nil,
        breed: String? = nil,
        coatColor: String? = nil,
        microchipNumber: String? = nil,
        vetName: String? = nil,
        vetClinic: String? = nil,
        vetPhone: String? = nil,
        emergencyVet: String? = nil,
        notes: String = "",
        displayColor: String? = "teal",
        context: ModelContext
    ) -> CareProfile {
        let profile = CareProfile(
            profileType: .dog,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: birthDate,
            sex: sex,
            notes: notes,
            displayColor: displayColor,
            adoptionDate: adoptionDate,
            species: "dog",
            breed: breed,
            coatColor: coatColor,
            microchipNumber: microchipNumber,
            vetName: vetName,
            vetClinic: vetClinic,
            vetPhone: vetPhone,
            emergencyVet: emergencyVet
        )
        context.insert(profile)
        switchProfile(profile)
        try? context.save()
        PersistenceService.recordLocalSave()
        return profile
    }

    func updateChildProfile(_ profile: CareProfile) {
        profile.updatedAt = Date()
        switchProfile(profile)
        try? profile.modelContext?.save()
        PersistenceService.recordLocalSave()
    }

    func archiveChildProfile(
        _ profile: CareProfile,
        profiles: [CareProfile],
        context: ModelContext
    ) {
        let active = allActiveProfiles(in: profiles)
        guard active.count > 1 else { return }
        profile.isArchived = true
        profile.updatedAt = Date()
        if selectedProfileID == profile.id {
            if let fallback = active.first(where: { $0.id != profile.id }) {
                switchProfile(fallback)
            }
        }
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    func switchProfile(_ profile: CareProfile) {
        selectedProfileID = profile.id
        UserDefaults.standard.set(profile.id.uuidString, forKey: selectedProfileKey)
    }

    func switchProfile(id: UUID, profiles: [CareProfile]) {
        guard let profile = allActiveProfiles(in: profiles).first(where: { $0.id == id }) else {
            _ = ensureSelection(in: profiles)
            return
        }
        switchProfile(profile)
    }
}

@MainActor
enum ProfileMigrationService {
    static func ensureProfilesAndAssignments(
        context: ModelContext,
        profiles: [CareProfile]? = nil
    ) {
        let existingProfiles = profiles ?? ((try? context.fetch(FetchDescriptor<CareProfile>())) ?? [])
        let activeProfiles = existingProfiles.filter { !$0.isArchived && $0.profileType == .child }
        let existingProfileIDs = Set(existingProfiles.map(\.id))
        guard hasOrphanedProfileScopedRecords(context: context, validProfileIDs: existingProfileIDs) else {
            _ = ProfileService.shared.ensureSelection(in: existingProfiles)
            return
        }

        let childProfile: CareProfile
        if let existing = activeProfiles.first {
            childProfile = existing
        } else {
            childProfile = CareProfile(
                name: "Imported Child",
                birthDate: SampleData.defaultBirthDate,
                sex: .unknown
            )
            context.insert(childProfile)
        }

        assignOrphanedProfileIDs(
            to: childProfile.id,
            validProfileIDs: existingProfileIDs.union([childProfile.id]),
            context: context
        )
        let profilesForSelection = activeProfiles.isEmpty ? existingProfiles + [childProfile] : existingProfiles
        _ = ProfileService.shared.ensureSelection(in: profilesForSelection)
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    static func hasOrphanedProfileScopedRecords(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        ((try? context.fetch(FetchDescriptor<BabyEvent>())) ?? []).containsOrphanedProfileID(validProfileIDs)
            || ((try? context.fetch(FetchDescriptor<SleepPredictionRecord>())) ?? []).containsOrphanedProfileID(validProfileIDs)
            || ((try? context.fetch(FetchDescriptor<MilestoneEntry>())) ?? []).containsOrphanedProfileID(validProfileIDs)
            || ((try? context.fetch(FetchDescriptor<DoctorAppointment>())) ?? []).containsOrphanedProfileID(validProfileIDs)
            || ((try? context.fetch(FetchDescriptor<AgeGuideReadState>())) ?? []).containsOrphanedProfileID(validProfileIDs)
            || ((try? context.fetch(FetchDescriptor<PuppyStageGuideReadState>())) ?? []).containsOrphanedProfileID(validProfileIDs)
    }

    static func assignOrphanedProfileIDs(
        to profileID: UUID,
        validProfileIDs: Set<UUID>,
        context: ModelContext
    ) {
        ((try? context.fetch(FetchDescriptor<BabyEvent>())) ?? [])
            .filter { $0.hasOrphanedProfileID(validProfileIDs) }
            .forEach {
                $0.profileID = profileID
                $0.profileTypeSnapshot = $0.profileTypeSnapshot ?? .child
            }
        ((try? context.fetch(FetchDescriptor<SleepPredictionRecord>())) ?? [])
            .filter { $0.hasOrphanedProfileID(validProfileIDs) }
            .forEach { $0.profileID = profileID }
        ((try? context.fetch(FetchDescriptor<MilestoneEntry>())) ?? [])
            .filter { $0.hasOrphanedProfileID(validProfileIDs) }
            .forEach { $0.profileID = profileID }
        ((try? context.fetch(FetchDescriptor<DoctorAppointment>())) ?? [])
            .filter { $0.hasOrphanedProfileID(validProfileIDs) }
            .forEach { $0.profileID = profileID }
        ((try? context.fetch(FetchDescriptor<AgeGuideReadState>())) ?? [])
            .filter { $0.hasOrphanedProfileID(validProfileIDs) }
            .forEach { $0.profileID = profileID }
        ((try? context.fetch(FetchDescriptor<PuppyStageGuideReadState>())) ?? [])
            .filter { $0.hasOrphanedProfileID(validProfileIDs) }
            .forEach { $0.profileID = profileID }
    }
}

private extension ProfileScopedRecord {
    func hasOrphanedProfileID(_ validProfileIDs: Set<UUID>) -> Bool {
        guard let profileID else { return true }
        return !validProfileIDs.contains(profileID)
    }
}

private extension Array where Element: ProfileScopedRecord {
    func containsOrphanedProfileID(_ validProfileIDs: Set<UUID>) -> Bool {
        contains { $0.hasOrphanedProfileID(validProfileIDs) }
    }
}
