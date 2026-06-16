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
        let ethan: CareProfile
        if let existing = activeProfiles.first {
            ethan = existing
        } else {
            ethan = CareProfile(
                name: "Ethan",
                birthDate: SampleData.defaultBirthDate,
                sex: .male
            )
            context.insert(ethan)
        }

        assignMissingProfileIDs(to: ethan.id, context: context)
        let profilesForSelection = activeProfiles.isEmpty ? existingProfiles + [ethan] : existingProfiles
        _ = ProfileService.shared.ensureSelection(in: profilesForSelection)
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    static func assignMissingProfileIDs(
        to profileID: UUID,
        context: ModelContext
    ) {
        let eventDescriptor = FetchDescriptor<BabyEvent>(
            predicate: #Predicate<BabyEvent> { $0.profileID == nil }
        )
        ((try? context.fetch(eventDescriptor)) ?? [])
            .forEach {
                $0.profileID = profileID
                $0.profileTypeSnapshot = $0.profileTypeSnapshot ?? .child
            }
        let recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { $0.profileID == nil }
        )
        ((try? context.fetch(recordDescriptor)) ?? [])
            .forEach { $0.profileID = profileID }
        let milestoneDescriptor = FetchDescriptor<MilestoneEntry>(
            predicate: #Predicate<MilestoneEntry> { $0.profileID == nil }
        )
        ((try? context.fetch(milestoneDescriptor)) ?? [])
            .forEach { $0.profileID = profileID }
        let appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate<DoctorAppointment> { $0.profileID == nil }
        )
        ((try? context.fetch(appointmentDescriptor)) ?? [])
            .forEach { $0.profileID = profileID }
        let ageGuideDescriptor = FetchDescriptor<AgeGuideReadState>(
            predicate: #Predicate<AgeGuideReadState> { $0.profileID == nil }
        )
        ((try? context.fetch(ageGuideDescriptor)) ?? [])
            .forEach { $0.profileID = profileID }
        let puppyGuideDescriptor = FetchDescriptor<PuppyStageGuideReadState>(
            predicate: #Predicate<PuppyStageGuideReadState> { $0.profileID == nil }
        )
        ((try? context.fetch(puppyGuideDescriptor)) ?? [])
            .forEach { $0.profileID = profileID }
    }
}
