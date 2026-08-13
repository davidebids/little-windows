import CryptoKit
import Foundation
import SwiftData

enum HouseholdAttentionSnoozeStore {
    private static let storageKey = "householdAttention.personalSnoozes.v1"
    private static let maximumEntryCount = 256

    static func isSnoozed(
        sourceKey: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        activeSnoozes(now: now, defaults: defaults)[sourceKey] != nil
    }

    static func activeSnoozes(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> [String: Date] {
        activeEntries(now: now, defaults: defaults).mapValues {
            Date(timeIntervalSince1970: $0)
        }
    }

    static func snooze(
        sourceKey: String,
        until date: Date,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard !sourceKey.isEmpty, date > now else { return }
        var entries = activeEntries(now: now, defaults: defaults)
        entries[sourceKey] = date.timeIntervalSince1970
        if entries.count > maximumEntryCount {
            for key in entries.sorted(by: { $0.value < $1.value })
                .prefix(entries.count - maximumEntryCount)
                .map(\.key) {
                entries.removeValue(forKey: key)
            }
        }
        defaults.set(entries, forKey: storageKey)
    }

    static func clear(sourceKey: String, defaults: UserDefaults = .standard) {
        var entries = storedEntries(defaults: defaults)
        guard entries.removeValue(forKey: sourceKey) != nil else { return }
        defaults.set(entries, forKey: storageKey)
    }

    private static func activeEntries(
        now: Date,
        defaults: UserDefaults
    ) -> [String: TimeInterval] {
        let entries = storedEntries(defaults: defaults)
        let active = entries.filter { $0.value > now.timeIntervalSince1970 }
        if active.count != entries.count {
            defaults.set(active, forKey: storageKey)
        }
        return active
    }

    private static func storedEntries(defaults: UserDefaults) -> [String: TimeInterval] {
        (defaults.dictionary(forKey: storageKey) ?? [:]).reduce(into: [:]) { result, value in
            if let timestamp = value.value as? NSNumber {
                result[value.key] = timestamp.doubleValue
            }
        }
    }
}

enum CaregiverHandoffCheckpointStore {
    private static let storageKey = "familySync.handoffCheckpoint.v1"

    static func date(
        caregiverIdentifier: String,
        defaults: UserDefaults = .standard
    ) -> Date? {
        guard let timestamp = defaults.dictionary(forKey: storageKey)?[caregiverIdentifier] as? NSNumber else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp.doubleValue)
    }

    static func markReviewed(
        caregiverIdentifier: String,
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        var values = defaults.dictionary(forKey: storageKey) ?? [:]
        let previous = (values[caregiverIdentifier] as? NSNumber)?.doubleValue
            ?? Date.distantPast.timeIntervalSince1970
        values[caregiverIdentifier] = max(previous, date.timeIntervalSince1970)
        defaults.set(values, forKey: storageKey)
    }
}

@MainActor
enum HouseholdAttentionService {
    static func deterministicID(_ components: String...) -> UUID {
        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @discardableResult
    static func registerCurrentFamilyCaregiver(
        householdID: UUID,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> FamilyCaregiverIdentity? {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return nil
        }
        let identifier = CaregiverIdentityService.stableCaregiverIdentifier(defaults: defaults)
        let name = CaregiverIdentityService.currentCaregiverName(defaults: defaults)
        let id = UUID(uuidString: identifier) ?? deterministicID("caregiver", identifier)
        let descriptor = FetchDescriptor<FamilyCaregiverIdentity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.householdID = householdID
            existing.caregiverIdentifier = identifier
            existing.displayName = name
            existing.lastSeenAt = now
            existing.updatedAt = now
            _ = PersistenceService.save(context: context)
            return existing
        }
        let identity = FamilyCaregiverIdentity(
            id: id,
            householdID: householdID,
            caregiverIdentifier: identifier,
            displayName: name,
            createdAt: now,
            updatedAt: now,
            lastSeenAt: now
        )
        context.insert(identity)
        _ = PersistenceService.save(context: context)
        return identity
    }

    static func createFollowUp(
        appointment: DoctorAppointment,
        householdID: UUID,
        title: String,
        details: String?,
        dueDate: Date?,
        assignedCaregiverIdentifier: String? = nil,
        assignedCaregiverName: String? = nil,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> AppointmentFollowUp? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return nil }
        let assignedIdentifier = assignedCaregiverIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedName = assignedCaregiverName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard assignedIdentifier.isEmpty == assignedName.isEmpty else { return nil }
        if !assignedIdentifier.isEmpty {
            guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync,
                  let profileID = appointment.profileID,
                  isFamilySharedProfile(profileID, context: context) else {
                return nil
            }
        }
        let caregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier(defaults: defaults)
        let caregiverName = CaregiverIdentityService.currentCaregiverName(defaults: defaults)
        let followUp = AppointmentFollowUp(
            appointmentID: appointment.id,
            householdID: householdID,
            profileID: appointment.profileID,
            title: cleanedTitle,
            details: cleanedOptional(details),
            dueDate: dueDate,
            createdByCaregiverIdentifier: caregiverIdentifier,
            createdByCaregiverName: caregiverName,
            createdAt: now,
            updatedAt: now
        )
        context.insert(followUp)
        if !assignedIdentifier.isEmpty {
            context.insert(HouseholdAttentionClaim(
                id: deterministicID("claim", followUp.attentionSourceKey),
                householdID: householdID,
                profileID: followUp.profileID,
                sourceKey: followUp.attentionSourceKey,
                caregiverIdentifier: assignedIdentifier,
                caregiverName: assignedName,
                updatedByCaregiverIdentifier: caregiverIdentifier,
                updatedByCaregiverName: caregiverName,
                createdAt: now,
                updatedAt: now
            ))
        }
        appointment.updatedAt = now
        guard PersistenceService.save(context: context) else { return nil }
        return followUp
    }

    static func updateFollowUp(
        _ followUp: AppointmentFollowUp,
        title: String,
        details: String?,
        dueDate: Date?,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return false }
        let cleanedDetails = cleanedOptional(details)
        guard followUp.title != cleanedTitle
                || followUp.details != cleanedDetails
                || followUp.dueDate != dueDate else {
            return true
        }
        followUp.title = cleanedTitle
        followUp.details = cleanedDetails
        followUp.dueDate = dueDate
        followUp.updatedAt = now
        return PersistenceService.save(context: context)
    }

    static func setFollowUpCompleted(
        _ followUp: AppointmentFollowUp,
        completed: Bool,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        if completed {
            followUp.completedAt = now
            followUp.completedByCaregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier(
                defaults: defaults
            )
            followUp.completedByCaregiverName = CaregiverIdentityService.currentCaregiverName(
                defaults: defaults
            )
        } else {
            followUp.completedAt = nil
            followUp.completedByCaregiverIdentifier = nil
            followUp.completedByCaregiverName = nil
        }
        followUp.updatedAt = now
        HouseholdAttentionSnoozeStore.clear(sourceKey: followUp.attentionSourceKey, defaults: defaults)
        return PersistenceService.save(context: context)
    }

    static func deleteFollowUp(
        _ followUp: AppointmentFollowUp,
        context: ModelContext
    ) -> Bool {
        deleteInteractions(sourceKey: followUp.attentionSourceKey, context: context)
        context.delete(followUp)
        return PersistenceService.save(context: context)
    }

    static func deleteFollowUps(
        appointmentID: UUID,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<AppointmentFollowUp>(
            predicate: #Predicate { $0.appointmentID == appointmentID }
        )
        for followUp in (try? context.fetch(descriptor)) ?? [] {
            deleteInteractions(sourceKey: followUp.attentionSourceKey, context: context)
            context.delete(followUp)
        }
    }

    @discardableResult
    static func deleteAppointment(
        _ appointment: DoctorAppointment,
        context: ModelContext
    ) async -> Bool {
        await NotificationManager.shared.cancelAppointmentReminders(
            appointmentID: appointment.id
        )
        deleteFollowUps(appointmentID: appointment.id, context: context)
        context.delete(appointment)
        return PersistenceService.save(context: context)
    }

    @discardableResult
    static func acknowledge(
        sourceKey: String,
        sourceUpdatedAt: Date,
        householdID: UUID,
        profileID: UUID?,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return false
        }
        let cleanedSourceKey = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSourceKey.isEmpty else { return false }
        guard isShareEligible(
            householdID: householdID,
            profileID: profileID,
            sourceKey: cleanedSourceKey,
            context: context
        ) else { return false }
        let caregiverIdentifier = CaregiverIdentityService.stableCaregiverIdentifier(defaults: defaults)
        let caregiverName = CaregiverIdentityService.currentCaregiverName(defaults: defaults)
        let id = deterministicID("ack", cleanedSourceKey, caregiverIdentifier)
        let descriptor = FetchDescriptor<HouseholdAttentionAcknowledgement>(
            predicate: #Predicate { $0.id == id }
        )
        if let acknowledgement = try? context.fetch(descriptor).first {
            acknowledgement.householdID = householdID
            acknowledgement.profileID = profileID
            acknowledgement.sourceUpdatedAt = sourceUpdatedAt
            acknowledgement.caregiverName = caregiverName
            acknowledgement.acknowledgedAt = now
            acknowledgement.updatedAt = now
        } else {
            context.insert(HouseholdAttentionAcknowledgement(
                id: id,
                householdID: householdID,
                profileID: profileID,
                sourceKey: cleanedSourceKey,
                sourceUpdatedAt: sourceUpdatedAt,
                caregiverIdentifier: caregiverIdentifier,
                caregiverName: caregiverName,
                acknowledgedAt: now,
                updatedAt: now
            ))
        }
        return PersistenceService.save(context: context)
    }

    @discardableResult
    static func claim(
        sourceKey: String,
        householdID: UUID,
        profileID: UUID?,
        caregiverIdentifier: String,
        caregiverName: String,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return false
        }
        guard isShareEligible(
            householdID: householdID,
            profileID: profileID,
            sourceKey: sourceKey,
            context: context
        ) else { return false }
        guard isClaimableFollowUp(
            sourceKey: sourceKey,
            householdID: householdID,
            profileID: profileID,
            context: context
        ) else { return false }
        let cleanedCaregiverIdentifier = caregiverIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCaregiverName = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedCaregiverIdentifier.isEmpty == cleanedCaregiverName.isEmpty else { return false }
        let currentIdentifier = CaregiverIdentityService.stableCaregiverIdentifier(defaults: defaults)
        let currentName = CaregiverIdentityService.currentCaregiverName(defaults: defaults)
        let id = deterministicID("claim", sourceKey)
        let descriptor = FetchDescriptor<HouseholdAttentionClaim>(predicate: #Predicate { $0.id == id })
        if let claim = try? context.fetch(descriptor).first {
            claim.householdID = householdID
            claim.profileID = profileID
            claim.caregiverIdentifier = cleanedCaregiverIdentifier
            claim.caregiverName = cleanedCaregiverName
            claim.updatedByCaregiverIdentifier = currentIdentifier
            claim.updatedByCaregiverName = currentName
            claim.updatedAt = now
        } else {
            context.insert(HouseholdAttentionClaim(
                id: id,
                householdID: householdID,
                profileID: profileID,
                sourceKey: sourceKey,
                caregiverIdentifier: cleanedCaregiverIdentifier,
                caregiverName: cleanedCaregiverName,
                updatedByCaregiverIdentifier: currentIdentifier,
                updatedByCaregiverName: currentName,
                createdAt: now,
                updatedAt: now
            ))
        }
        return PersistenceService.save(context: context)
    }

    @discardableResult
    static func clearClaim(
        sourceKey: String,
        householdID: UUID,
        profileID: UUID?,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        claim(
            sourceKey: sourceKey,
            householdID: householdID,
            profileID: profileID,
            caregiverIdentifier: "",
            caregiverName: "",
            context: context,
            now: now,
            defaults: defaults
        )
    }

    @discardableResult
    static func setClaimIfNeeded(
        sourceKey: String,
        householdID: UUID,
        profileID: UUID?,
        currentClaim: HouseholdAttentionClaim?,
        caregiverIdentifier: String?,
        caregiverName: String?,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        let desiredIdentifier = caregiverIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let desiredName = caregiverName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentIdentifier = currentClaim?.sourceKey == sourceKey
            ? currentClaim?.caregiverIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            : ""
        guard desiredIdentifier != currentIdentifier else { return true }
        if desiredIdentifier.isEmpty {
            return clearClaim(
                sourceKey: sourceKey,
                householdID: householdID,
                profileID: profileID,
                context: context,
                now: now,
                defaults: defaults
            )
        }
        return claim(
            sourceKey: sourceKey,
            householdID: householdID,
            profileID: profileID,
            caregiverIdentifier: desiredIdentifier,
            caregiverName: desiredName,
            context: context,
            now: now,
            defaults: defaults
        )
    }

    @discardableResult
    static func addHandoffNote(
        householdID: UUID,
        profileID: UUID?,
        sourceKey: String?,
        sourceTitle: String?,
        body: String,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> CaregiverHandoffNote? {
        guard PersistenceService.familySyncMode(defaults: defaults) == .sharedFamilySync else {
            return nil
        }
        guard isShareEligible(
            householdID: householdID,
            profileID: profileID,
            sourceKey: sourceKey,
            context: context
        ) else { return nil }
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBody.isEmpty else { return nil }
        let cleanedSourceKey = cleanedOptional(sourceKey)
        let cleanedSourceTitle = cleanedOptional(sourceTitle)
        guard (cleanedSourceKey == nil) == (cleanedSourceTitle == nil) else { return nil }
        let note = CaregiverHandoffNote(
            householdID: householdID,
            profileID: profileID,
            sourceKey: cleanedSourceKey,
            sourceTitleSnapshot: cleanedSourceTitle,
            body: cleanedBody,
            authorCaregiverIdentifier: CaregiverIdentityService.stableCaregiverIdentifier(defaults: defaults),
            authorCaregiverName: CaregiverIdentityService.currentCaregiverName(defaults: defaults),
            createdAt: now,
            updatedAt: now
        )
        context.insert(note)
        guard PersistenceService.save(context: context) else { return nil }
        return note
    }

    private static func deleteInteractions(sourceKey: String, context: ModelContext) {
        let acknowledgements = (try? context.fetch(FetchDescriptor<HouseholdAttentionAcknowledgement>(
            predicate: #Predicate { $0.sourceKey == sourceKey }
        ))) ?? []
        acknowledgements.forEach(context.delete)
        let claims = (try? context.fetch(FetchDescriptor<HouseholdAttentionClaim>(
            predicate: #Predicate { $0.sourceKey == sourceKey }
        ))) ?? []
        claims.forEach(context.delete)
        let notes = (try? context.fetch(FetchDescriptor<CaregiverHandoffNote>(
            predicate: #Predicate { $0.sourceKey == sourceKey }
        ))) ?? []
        notes.forEach(context.delete)
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func isClaimableFollowUp(
        sourceKey: String,
        householdID: UUID,
        profileID: UUID?,
        context: ModelContext
    ) -> Bool {
        let prefix = "\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):"
        guard sourceKey.hasPrefix(prefix),
              let followUpID = UUID(uuidString: String(sourceKey.dropFirst(prefix.count))) else {
            return false
        }
        let descriptor = FetchDescriptor<AppointmentFollowUp>(
            predicate: #Predicate { $0.id == followUpID }
        )
        guard let followUp = try? context.fetch(descriptor).first else { return false }
        return followUp.householdID == householdID
            && followUp.profileID == profileID
            && !followUp.isCompleted
    }

    private static func isShareEligible(
        householdID: UUID,
        profileID: UUID?,
        sourceKey: String?,
        context: ModelContext
    ) -> Bool {
        let appointmentPrefix = "\(HouseholdAttentionSourceKind.appointmentFollowUp.rawValue):"
        if let sourceKey, sourceKey.hasPrefix(appointmentPrefix) {
            // Profile-less appointments are legacy/private records. Family Sync's
            // shared payload intentionally excludes them, so never create local-only
            // collaboration state that another caregiver cannot receive.
            guard let followUpID = UUID(uuidString: String(sourceKey.dropFirst(appointmentPrefix.count))) else {
                return false
            }
            let descriptor = FetchDescriptor<AppointmentFollowUp>(
                predicate: #Predicate { $0.id == followUpID }
            )
            guard let followUp = try? context.fetch(descriptor).first,
                  followUp.householdID == householdID,
                  let followUpProfileID = followUp.profileID,
                  followUpProfileID == profileID else {
                return false
            }
        }
        guard let profileID else { return true }
        return isFamilySharedProfile(profileID, context: context)
    }

    private static func isFamilySharedProfile(
        _ profileID: UUID,
        context: ModelContext
    ) -> Bool {
        let descriptor = FetchDescriptor<CareProfile>(
            predicate: #Predicate { $0.id == profileID }
        )
        guard let profile = try? context.fetch(descriptor).first else { return false }
        return profile.sharingScope == .family
    }
}
