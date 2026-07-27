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
        _ = PersistenceService.save(context: context)
        SystemIntegrationReconciler.requestReconciliation()
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
        _ = PersistenceService.save(context: context)
        SystemIntegrationReconciler.requestReconciliation()
        return profile
    }

    func updateChildProfile(_ profile: CareProfile) {
        profile.updatedAt = Date()
        switchProfile(profile)
        if let context = profile.modelContext {
            _ = PersistenceService.save(context: context)
        }
    }

    func archiveProfile(
        _ profile: CareProfile,
        profiles: [CareProfile],
        context: ModelContext
    ) {
        guard !profile.isArchived else { return }
        let active = allActiveProfiles(in: profiles)
        guard active.count > 1 else { return }
        profile.isArchived = true
        profile.updatedAt = Date()
        if selectedProfileID == profile.id {
            if let fallback = active.first(where: { $0.id != profile.id }) {
                switchProfile(fallback)
            }
        }
        guard PersistenceService.save(context: context) else { return }
        SystemIntegrationReconciler.requestReconciliation()
    }

    func archiveChildProfile(
        _ profile: CareProfile,
        profiles: [CareProfile],
        context: ModelContext
    ) {
        archiveProfile(profile, profiles: profiles, context: context)
    }

    func restoreProfile(_ profile: CareProfile, context: ModelContext) {
        profile.isArchived = false
        profile.updatedAt = Date()
        switchProfile(profile)
        guard PersistenceService.save(context: context) else { return }
        SystemIntegrationReconciler.requestReconciliation()
    }

    func canDeleteProfile(_ profile: CareProfile, profiles: [CareProfile]) -> Bool {
        profile.isArchived || allActiveProfiles(in: profiles).contains { $0.id != profile.id }
    }

    func deleteProfile(
        _ profile: CareProfile,
        profiles: [CareProfile],
        context: ModelContext
    ) {
        guard canDeleteProfile(profile, profiles: profiles) else { return }
        let activeFallback = allActiveProfiles(in: profiles).first { $0.id != profile.id }
        deleteProfileScopedRecords(profileID: profile.id, context: context)
        PhotoAttachmentStore.deleteAttachments(profileID: profile.id, context: context)
        context.delete(profile)
        if selectedProfileID == profile.id {
            if let activeFallback {
                switchProfile(activeFallback)
            } else {
                selectedProfileID = nil
                UserDefaults.standard.removeObject(forKey: selectedProfileKey)
            }
        }
        guard PersistenceService.save(context: context) else { return }
        SystemIntegrationReconciler.requestReconciliation()
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

    private func deleteProfileScopedRecords(profileID: UUID, context: ModelContext) {
        deleteProfileScopedRecords(of: BabyEvent.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: SleepPredictionRecord.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: MilestoneEntry.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: DoctorAppointment.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: AgeGuideReadState.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: PuppyStageGuideReadState.self, profileID: profileID, context: context)
    }

    private func deleteProfileScopedRecords<Record: PersistentModel & ProfileScopedRecord>(
        of type: Record.Type,
        profileID: UUID,
        context: ModelContext
    ) {
        ((try? context.fetch(FetchDescriptor<Record>())) ?? [])
            .filter { $0.profileID == profileID }
            .forEach { context.delete($0) }
    }
}

@MainActor
enum ProfileMigrationService {
    static func ensureProfilesAndAssignments(
        context: ModelContext,
        profiles: [CareProfile]? = nil,
        saveChanges: Bool = true
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
        if saveChanges {
            if PersistenceService.save(context: context) == false {
                return
            }
        }
    }

    static func hasOrphanedProfileScopedRecords(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        hasOrphanedBabyEvents(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedPredictionRecords(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedMilestones(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedAppointments(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedAgeGuideStates(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedPuppyGuideStates(context: context, validProfileIDs: validProfileIDs)
    }

    private static func hasOrphanedBabyEvents(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<BabyEvent>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { $0.profileID == profileID }
            )
            return partial + ((try? context.fetchCount(descriptor)) ?? 0)
        }
        return validCount != total
    }

    private static func hasOrphanedPredictionRecords(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<SleepPredictionRecord>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<SleepPredictionRecord>(
                predicate: #Predicate<SleepPredictionRecord> { $0.profileID == profileID }
            )
            return partial + ((try? context.fetchCount(descriptor)) ?? 0)
        }
        return validCount != total
    }

    private static func hasOrphanedMilestones(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<MilestoneEntry>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<MilestoneEntry>(
                predicate: #Predicate<MilestoneEntry> { $0.profileID == profileID }
            )
            return partial + ((try? context.fetchCount(descriptor)) ?? 0)
        }
        return validCount != total
    }

    private static func hasOrphanedAppointments(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<DoctorAppointment>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<DoctorAppointment>(
                predicate: #Predicate<DoctorAppointment> { $0.profileID == profileID }
            )
            return partial + ((try? context.fetchCount(descriptor)) ?? 0)
        }
        return validCount != total
    }

    private static func hasOrphanedAgeGuideStates(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<AgeGuideReadState>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<AgeGuideReadState>(
                predicate: #Predicate<AgeGuideReadState> { $0.profileID == profileID }
            )
            return partial + ((try? context.fetchCount(descriptor)) ?? 0)
        }
        return validCount != total
    }

    private static func hasOrphanedPuppyGuideStates(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<PuppyStageGuideReadState>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<PuppyStageGuideReadState>(
                predicate: #Predicate<PuppyStageGuideReadState> { $0.profileID == profileID }
            )
            return partial + ((try? context.fetchCount(descriptor)) ?? 0)
        }
        return validCount != total
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
