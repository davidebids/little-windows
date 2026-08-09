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
        allProfiles(in: profiles).filter { !$0.isArchived }
    }

    func allChildProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        allActiveProfiles(in: profiles).filter { $0.profileType == .child }
    }

    func allAdultProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        allActiveProfiles(in: profiles).filter { $0.profileType == .adult }
    }

    func allDogProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        allActiveProfiles(in: profiles).filter { $0.profileType == .dog }
    }

    func allProfiles(in profiles: [CareProfile]) -> [CareProfile] {
        var seenProfileIDs = Set<UUID>()
        return profiles
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .filter { seenProfileIDs.insert($0.id).inserted }
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
        sex: ProfileSex,
        sharingScope: CareProfileSharingScope = .privateOnly,
        notes: String = "",
        displayColor: String? = nil,
        context: ModelContext
    ) -> CareProfile {
        let profile = CareProfile(
            profileType: .child,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: birthDate,
            sex: sex,
            sharingScope: sharingScope,
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
    func createAdultProfile(
        name: String,
        birthDate: Date? = nil,
        sex: ProfileSex = .unknown,
        relationship: AdultCareRelationship,
        sharingScope: CareProfileSharingScope = .privateOnly,
        notes: String = "",
        displayColor: String? = "purple",
        context: ModelContext
    ) -> CareProfile {
        let profile = CareProfile(
            profileType: .adult,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: birthDate,
            sex: sex,
            adultRelationship: relationship,
            sharingScope: sharingScope,
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
        sex: ProfileSex = .unknown,
        sharingScope: CareProfileSharingScope = .privateOnly,
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
            sharingScope: sharingScope,
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

    func updateProfile(_ profile: CareProfile) {
        profile.updatedAt = Date()
        switchProfile(profile)
        if let context = profile.modelContext {
            _ = PersistenceService.save(context: context)
        }
    }

    func canChangeSharingScope(
        for profile: CareProfile,
        caregiverIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier()
    ) -> Bool {
        let ownerIdentifier = profile.ownerIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ownerIdentifier.isEmpty || ownerIdentifier == caregiverIdentifier
    }

    @discardableResult
    func setSharingScope(
        _ sharingScope: CareProfileSharingScope,
        for profile: CareProfile,
        caregiverIdentifier: String = CaregiverIdentityService.stableCaregiverIdentifier()
    ) -> Bool {
        guard canChangeSharingScope(
            for: profile,
            caregiverIdentifier: caregiverIdentifier
        ) else {
            return false
        }

        if profile.ownerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.ownerIdentifier = caregiverIdentifier
        }
        profile.sharingScope = sharingScope
        return true
    }


    @available(*, deprecated, renamed: "updateProfile")
    func updateChildProfile(_ profile: CareProfile) {
        updateProfile(profile)
    }

    func archiveProfile(
        _ profile: CareProfile,
        profiles: [CareProfile],
        context: ModelContext
    ) {
        guard !profile.isArchived else { return }
        let active = allActiveProfiles(in: profiles)
        guard active.contains(where: { $0.id == profile.id }) else { return }
        let archivesFinalActiveProfile = active.count == 1
        let archivedAt = Date()
        let profileID = profile.id
        let openTimers = (try? context.fetch(FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.endDate == nil
            }
        ))) ?? []
        for timer in openTimers where timer.isTimerDraft {
            EventTimerService.save(timer, context: context, at: archivedAt)
        }
        profile.isArchived = true
        profile.updatedAt = archivedAt
        if selectedProfileID == profile.id {
            if let fallback = active.first(where: { $0.id != profile.id }) {
                switchProfile(fallback)
            } else {
                selectedProfileID = nil
                UserDefaults.standard.removeObject(forKey: selectedProfileKey)
            }
        }
        guard PersistenceService.save(context: context) else { return }
        ActiveSleepPlanService.clear(profileID: profileID)
        if archivesFinalActiveProfile {
            WidgetSnapshotService.refresh(
                profile: nil,
                events: [],
                prediction: nil
            )
            WatchConnectivityService.shared.publishCurrentState()
            Task {
                await LiveActivityManager.shared.synchronize(profile: nil, events: [])
            }
        }
        Task {
            await NotificationManager.shared.cancelCareAlerts(profileID: profileID)
        }
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
        let profileID = profile.id
        let activeFallback = allActiveProfiles(in: profiles).first { $0.id != profile.id }
        deleteProfileScopedRecords(profileID: profileID, context: context)
        PhotoAttachmentStore.deleteAttachments(profileID: profileID, context: context)
        context.delete(profile)
        if selectedProfileID == profileID {
            if let activeFallback {
                switchProfile(activeFallback)
            } else {
                selectedProfileID = nil
                UserDefaults.standard.removeObject(forKey: selectedProfileKey)
            }
        }
        guard PersistenceService.save(context: context) else { return }
        ActiveSleepPlanService.clear(profileID: profileID)
        Task {
            await NotificationManager.shared.cancelCareAlerts(profileID: profileID)
        }
        SystemIntegrationReconciler.requestReconciliation()
    }

    func switchProfile(_ profile: CareProfile) {
        selectedProfileID = profile.id
        UserDefaults.standard.set(profile.id.uuidString, forKey: selectedProfileKey)
        WatchConnectivityService.shared.publishCurrentState()
        SystemIntegrationReconciler.requestReconciliation()
    }

    func switchProfile(id: UUID, profiles: [CareProfile]) {
        guard let profile = allActiveProfiles(in: profiles).first(where: { $0.id == id }) else {
            _ = ensureSelection(in: profiles)
            return
        }
        switchProfile(profile)
    }

    private func deleteProfileScopedRecords(profileID: UUID, context: ModelContext) {
        let routineIDs = Set(
            ((try? context.fetch(FetchDescriptor<CareRoutine>())) ?? [])
                .filter { $0.profileID == profileID }
                .map(\.id)
        )
        ((try? context.fetch(FetchDescriptor<CareRoutineRun>())) ?? [])
            .filter { $0.profileID == profileID || routineIDs.contains($0.routineID) }
            .forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<CareRoutineStep>())) ?? [])
            .filter { routineIDs.contains($0.routineID) }
            .forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<CareRoutine>())) ?? [])
            .filter { routineIDs.contains($0.id) }
            .forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<TripTraveler>())) ?? [])
            .filter { $0.profileID == profileID }
            .forEach {
                $0.profileID = nil
                $0.updatedAt = Date()
            }
        deleteProfileScopedRecords(of: CareEvent.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: Medication.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: MedicationRegimen.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: MedicationSchedulePhase.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: MedicationDoseRecord.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: MedicationSupplyLog.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: SleepPredictionRecord.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: MilestoneEntry.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: DoctorAppointment.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: AgeGuideReadState.self, profileID: profileID, context: context)
        deleteProfileScopedRecords(of: PuppyStageGuideReadState.self, profileID: profileID, context: context)
        deleteRequiredProfileScopedRecords(
            of: SolidsProfileState.self,
            profileID: profileID,
            profileIDKeyPath: \.profileID,
            context: context
        )
        deleteRequiredProfileScopedRecords(
            of: SolidFoodProgress.self,
            profileID: profileID,
            profileIDKeyPath: \.profileID,
            context: context
        )
        deleteRequiredProfileScopedRecords(
            of: SolidFoodEventItem.self,
            profileID: profileID,
            profileIDKeyPath: \.profileID,
            context: context
        )
        deleteRequiredProfileScopedRecords(
            of: SolidAllergenProgress.self,
            profileID: profileID,
            profileIDKeyPath: \.profileID,
            context: context
        )
        deleteRequiredProfileScopedRecords(
            of: PlannedSolidMeal.self,
            profileID: profileID,
            profileIDKeyPath: \.profileID,
            context: context
        )
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

    private func deleteRequiredProfileScopedRecords<Record: PersistentModel>(
        of type: Record.Type,
        profileID: UUID,
        profileIDKeyPath: KeyPath<Record, UUID>,
        context: ModelContext
    ) {
        ((try? context.fetch(FetchDescriptor<Record>())) ?? [])
            .filter { $0[keyPath: profileIDKeyPath] == profileID }
            .forEach { context.delete($0) }
    }
}

@MainActor
enum ProfileDuplicateRepairService {
    private static let minimumSetupShellAgeDifference: TimeInterval = 60

    @discardableResult
    static func repair(
        context: ModelContext,
        profiles: [CareProfile]? = nil,
        saveChanges: Bool = true
    ) -> Int {
        let fetchedProfiles = profiles
            ?? ((try? context.fetch(FetchDescriptor<CareProfile>())) ?? [])
        guard fetchedProfiles.count > 1 else { return 0 }

        let sortedProfiles = fetchedProfiles.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        var canonicalProfileByID: [UUID: CareProfile] = [:]
        var removedObjectIDs = Set<ObjectIdentifier>()

        // SwiftData/CloudKit can contain multiple model objects carrying the
        // same app-level UUID. All profile-scoped data already points to that
        // UUID, so only the extra profile object needs to be removed.
        for profile in sortedProfiles {
            if canonicalProfileByID[profile.id] == nil {
                canonicalProfileByID[profile.id] = profile
            } else {
                removedObjectIDs.insert(ObjectIdentifier(profile))
            }
        }

        let uniqueProfiles = sortedProfiles.filter {
            !removedObjectIDs.contains(ObjectIdentifier($0))
        }
        let linkedDataByProfileID = Dictionary(uniqueKeysWithValues: uniqueProfiles.compactMap {
            profile -> (UUID, Bool)? in
            guard let hasLinkedData = hasLinkedData(
                profileID: profile.id,
                context: context
            ) else { return nil }
            return (profile.id, hasLinkedData)
        })
        let profilesWithLinkedData = Set(linkedDataByProfileID.compactMap {
            $0.value ? $0.key : nil
        })
        let profilesConfirmedEmpty = Set(linkedDataByProfileID.compactMap {
            $0.value ? nil : $0.key
        })
        var replacementByRemovedProfileID: [UUID: CareProfile] = [:]

        // A reinstall can create a new onboarding profile before the original
        // profile finishes downloading from iCloud. Only remove a newer,
        // otherwise-empty setup shell when it has exactly one matching older
        // profile that already owns user data.
        for shell in uniqueProfiles where profilesConfirmedEmpty.contains(shell.id) {
            guard isEmptySetupShell(shell) else { continue }
            let matches = uniqueProfiles.filter { candidate in
                candidate.id != shell.id
                    && profilesWithLinkedData.contains(candidate.id)
                    && candidate.createdAt.addingTimeInterval(minimumSetupShellAgeDifference)
                        <= shell.createdAt
                    && profilesRepresentSamePerson(candidate, shell)
            }
            guard matches.count == 1, let canonical = matches.first else { continue }
            removedObjectIDs.insert(ObjectIdentifier(shell))
            replacementByRemovedProfileID[shell.id] = canonical
        }

        let removedProfiles = fetchedProfiles.filter {
            removedObjectIDs.contains(ObjectIdentifier($0))
        }
        guard !removedProfiles.isEmpty else { return 0 }

        if let selectedProfileID = ProfileService.shared.selectedProfileID,
           let replacement = replacementByRemovedProfileID[selectedProfileID] {
            ProfileService.shared.switchProfile(replacement)
        }
        removedProfiles.forEach(context.delete)

        if saveChanges, !PersistenceService.save(context: context) {
            return 0
        }
        if saveChanges {
            SystemIntegrationReconciler.requestReconciliation()
        }
        return removedProfiles.count
    }

    private static func profilesRepresentSamePerson(
        _ lhs: CareProfile,
        _ rhs: CareProfile
    ) -> Bool {
        guard lhs.profileType == rhs.profileType,
              normalized(lhs.name) == normalized(rhs.name),
              lhs.sex == rhs.sex,
              optionalDatesMatch(lhs.birthDate, rhs.birthDate),
              lhs.sharingScope == rhs.sharingScope,
              lhs.ownerIdentifier == rhs.ownerIdentifier,
              lhs.isArchived == rhs.isArchived else {
            return false
        }
        switch lhs.profileType {
        case .child:
            return true
        case .adult:
            return lhs.adultRelationship == rhs.adultRelationship
        case .dog:
            return optionalDatesAreCompatible(lhs.adoptionDate, rhs.adoptionDate)
                && optionalTextIsCompatible(lhs.breed, rhs.breed)
        }
    }

    private static func optionalDatesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)):
            Calendar.current.isDate(lhs, inSameDayAs: rhs)
        default: false
        }
    }

    private static func optionalDatesAreCompatible(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return true }
        return Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    private static func optionalTextIsCompatible(_ lhs: String?, _ rhs: String?) -> Bool {
        let lhs = normalized(lhs ?? "")
        let rhs = normalized(rhs ?? "")
        return lhs.isEmpty || rhs.isEmpty || lhs == rhs
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func isEmptySetupShell(_ profile: CareProfile) -> Bool {
        profile.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && profile.birthWeightKilograms == nil
            && profile.birthLengthCentimeters == nil
            && profile.birthHeadCircumferenceCentimeters == nil
            && profile.profilePhotoAttachmentID == nil
            && normalized(profile.microchipNumber ?? "").isEmpty
            && normalized(profile.vetName ?? "").isEmpty
            && normalized(profile.vetClinic ?? "").isEmpty
            && normalized(profile.vetPhone ?? "").isEmpty
            && normalized(profile.emergencyVet ?? "").isEmpty
    }

    private static func hasLinkedData(profileID: UUID, context: ModelContext) -> Bool? {
        guard let hasCareEvents = hasRecord(
            FetchDescriptor<CareEvent>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasCareEvents { return true }
        guard let hasMedications = hasRecord(
            FetchDescriptor<Medication>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasMedications { return true }
        guard let hasMedicationRegimens = hasRecord(
            FetchDescriptor<MedicationRegimen>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasMedicationRegimens { return true }
        guard let hasMedicationPhases = hasRecord(
            FetchDescriptor<MedicationSchedulePhase>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasMedicationPhases { return true }
        guard let hasMedicationDoses = hasRecord(
            FetchDescriptor<MedicationDoseRecord>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasMedicationDoses { return true }
        guard let hasMedicationSupplyLogs = hasRecord(
            FetchDescriptor<MedicationSupplyLog>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasMedicationSupplyLogs { return true }
        guard let hasPredictions = hasRecord(
            FetchDescriptor<SleepPredictionRecord>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasPredictions { return true }
        guard let hasMilestones = hasRecord(
            FetchDescriptor<MilestoneEntry>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasMilestones { return true }
        guard let hasAppointments = hasRecord(
            FetchDescriptor<DoctorAppointment>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasAppointments { return true }
        guard let hasAgeGuideStates = hasRecord(
            FetchDescriptor<AgeGuideReadState>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasAgeGuideStates { return true }
        guard let hasPuppyGuideStates = hasRecord(
            FetchDescriptor<PuppyStageGuideReadState>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasPuppyGuideStates { return true }
        guard let hasSolidsState = hasRecord(
            FetchDescriptor<SolidsProfileState>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasSolidsState { return true }
        guard let hasFoodProgress = hasRecord(
            FetchDescriptor<SolidFoodProgress>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasFoodProgress { return true }
        guard let hasFoodEventItems = hasRecord(
            FetchDescriptor<SolidFoodEventItem>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasFoodEventItems { return true }
        guard let hasAllergenProgress = hasRecord(
            FetchDescriptor<SolidAllergenProgress>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasAllergenProgress { return true }
        guard let hasPlannedMeals = hasRecord(
            FetchDescriptor<PlannedSolidMeal>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasPlannedMeals { return true }
        guard let hasPhotos = hasRecord(
            FetchDescriptor<PhotoAttachment>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasPhotos { return true }
        guard let hasTripTravelers = hasRecord(
            FetchDescriptor<TripTraveler>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasTripTravelers { return true }
        guard let hasRoutines = hasRecord(
            FetchDescriptor<CareRoutine>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        ) else { return nil }
        if hasRoutines { return true }
        return hasRecord(
            FetchDescriptor<CareRoutineRun>(predicate: #Predicate { $0.profileID == profileID }),
            context: context
        )
    }

    private static func hasRecord<Record: PersistentModel>(
        _ descriptor: FetchDescriptor<Record>,
        context: ModelContext
    ) -> Bool? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        do {
            return try context.fetchCount(descriptor) > 0
        } catch {
            return nil
        }
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
        hasOrphanedCareEvents(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedPredictionRecords(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedMilestones(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedAppointments(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedAgeGuideStates(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedPuppyGuideStates(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedSolidsProfileStates(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedSolidFoodProgress(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedSolidFoodEventItems(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedSolidAllergenProgress(context: context, validProfileIDs: validProfileIDs)
            || hasOrphanedPlannedSolidMeals(context: context, validProfileIDs: validProfileIDs)
    }

    private static func hasOrphanedCareEvents(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        let total = (try? context.fetchCount(FetchDescriptor<CareEvent>())) ?? 0
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        let validCount = validProfileIDs.reduce(0) { partial, profileID in
            let descriptor = FetchDescriptor<CareEvent>(
                predicate: #Predicate<CareEvent> { $0.profileID == profileID }
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

    private static func hasOrphanedSolidsProfileStates(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        hasOrphanedRequiredRecords(
            total: (try? context.fetchCount(FetchDescriptor<SolidsProfileState>())) ?? 0,
            validProfileIDs: validProfileIDs
        ) { profileID in
            let descriptor = FetchDescriptor<SolidsProfileState>(
                predicate: #Predicate { $0.profileID == profileID }
            )
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    private static func hasOrphanedSolidFoodProgress(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        hasOrphanedRequiredRecords(
            total: (try? context.fetchCount(FetchDescriptor<SolidFoodProgress>())) ?? 0,
            validProfileIDs: validProfileIDs
        ) { profileID in
            let descriptor = FetchDescriptor<SolidFoodProgress>(
                predicate: #Predicate { $0.profileID == profileID }
            )
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    private static func hasOrphanedSolidFoodEventItems(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        hasOrphanedRequiredRecords(
            total: (try? context.fetchCount(FetchDescriptor<SolidFoodEventItem>())) ?? 0,
            validProfileIDs: validProfileIDs
        ) { profileID in
            let descriptor = FetchDescriptor<SolidFoodEventItem>(
                predicate: #Predicate { $0.profileID == profileID }
            )
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    private static func hasOrphanedSolidAllergenProgress(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        hasOrphanedRequiredRecords(
            total: (try? context.fetchCount(FetchDescriptor<SolidAllergenProgress>())) ?? 0,
            validProfileIDs: validProfileIDs
        ) { profileID in
            let descriptor = FetchDescriptor<SolidAllergenProgress>(
                predicate: #Predicate { $0.profileID == profileID }
            )
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    private static func hasOrphanedPlannedSolidMeals(
        context: ModelContext,
        validProfileIDs: Set<UUID>
    ) -> Bool {
        hasOrphanedRequiredRecords(
            total: (try? context.fetchCount(FetchDescriptor<PlannedSolidMeal>())) ?? 0,
            validProfileIDs: validProfileIDs
        ) { profileID in
            let descriptor = FetchDescriptor<PlannedSolidMeal>(
                predicate: #Predicate { $0.profileID == profileID }
            )
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    private static func hasOrphanedRequiredRecords(
        total: Int,
        validProfileIDs: Set<UUID>,
        countForProfile: (UUID) -> Int
    ) -> Bool {
        guard total > 0 else { return false }
        guard !validProfileIDs.isEmpty else { return true }
        return validProfileIDs.reduce(0) { $0 + countForProfile($1) } != total
    }

    static func assignOrphanedProfileIDs(
        to profileID: UUID,
        validProfileIDs: Set<UUID>,
        context: ModelContext
    ) {
        ((try? context.fetch(FetchDescriptor<CareEvent>())) ?? [])
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
        assignOrphanedRequiredProfileIDs(
            SolidsProfileState.self,
            to: profileID,
            validProfileIDs: validProfileIDs,
            profileIDKeyPath: \.profileID,
            context: context
        )
        assignOrphanedRequiredProfileIDs(
            SolidFoodProgress.self,
            to: profileID,
            validProfileIDs: validProfileIDs,
            profileIDKeyPath: \.profileID,
            context: context
        )
        assignOrphanedRequiredProfileIDs(
            SolidFoodEventItem.self,
            to: profileID,
            validProfileIDs: validProfileIDs,
            profileIDKeyPath: \.profileID,
            context: context
        )
        assignOrphanedRequiredProfileIDs(
            SolidAllergenProgress.self,
            to: profileID,
            validProfileIDs: validProfileIDs,
            profileIDKeyPath: \.profileID,
            context: context
        )
        assignOrphanedRequiredProfileIDs(
            PlannedSolidMeal.self,
            to: profileID,
            validProfileIDs: validProfileIDs,
            profileIDKeyPath: \.profileID,
            context: context
        )
    }

    private static func assignOrphanedRequiredProfileIDs<Record: PersistentModel & AnyObject>(
        _ type: Record.Type,
        to profileID: UUID,
        validProfileIDs: Set<UUID>,
        profileIDKeyPath: ReferenceWritableKeyPath<Record, UUID>,
        context: ModelContext
    ) {
        ((try? context.fetch(FetchDescriptor<Record>())) ?? [])
            .filter { !validProfileIDs.contains($0[keyPath: profileIDKeyPath]) }
            .forEach { $0[keyPath: profileIDKeyPath] = profileID }
    }

}

private extension ProfileScopedRecord {
    func hasOrphanedProfileID(_ validProfileIDs: Set<UUID>) -> Bool {
        guard let profileID else { return true }
        return !validProfileIDs.contains(profileID)
    }
}
