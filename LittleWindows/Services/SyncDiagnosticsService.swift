import Foundation
import SwiftData

@MainActor
enum SyncDiagnosticsService {
    static func snapshot(context: ModelContext) -> SyncDiagnosticSnapshot {
        let profiles = (try? context.fetch(FetchDescriptor<BabyProfile>())) ?? []
        let profileIDs = Set(profiles.map(\.id))
        let events = (try? context.fetch(FetchDescriptor<BabyEvent>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<SleepPredictionRecord>())) ?? []
        let milestones = (try? context.fetch(FetchDescriptor<MilestoneEntry>())) ?? []
        let appointments = (try? context.fetch(FetchDescriptor<DoctorAppointment>())) ?? []
        let ageGuideStates = (try? context.fetch(FetchDescriptor<AgeGuideReadState>())) ?? []
        let puppyGuideStates = (try? context.fetch(FetchDescriptor<PuppyStageGuideReadState>())) ?? []

        let orphanedCount =
            events.orphanedCount(profileIDs: profileIDs)
            + records.orphanedCount(profileIDs: profileIDs)
            + milestones.orphanedCount(profileIDs: profileIDs)
            + appointments.orphanedCount(profileIDs: profileIDs)
            + ageGuideStates.orphanedCount(profileIDs: profileIDs)
            + puppyGuideStates.orphanedCount(profileIDs: profileIDs)

        let duplicateEthanProfiles = profiles.filter {
            !$0.isArchived
                && $0.profileType == .child
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Ethan") == .orderedSame
        }.count

        return SyncDiagnosticSnapshot(
            generatedAt: Date(),
            profileCount: profiles.count,
            activeProfileCount: profiles.filter { !$0.isArchived }.count,
            recordCounts: [
                SyncDiagnosticCount(name: "Profiles", count: profiles.count),
                SyncDiagnosticCount(name: "Events", count: events.count),
                SyncDiagnosticCount(name: "Predictions", count: records.count),
                SyncDiagnosticCount(name: "Milestones", count: milestones.count),
                SyncDiagnosticCount(name: "Appointments", count: appointments.count),
                SyncDiagnosticCount(name: "Age guide states", count: ageGuideStates.count),
                SyncDiagnosticCount(name: "Puppy guide states", count: puppyGuideStates.count)
            ],
            orphanedProfileScopedRecordCount: orphanedCount,
            duplicateEthanProfileCount: max(0, duplicateEthanProfiles - 1),
            migrationState: CloudMigrationService.state(),
            lastLocalSaveAt: PersistenceService.lastLocalSaveAt()
        )
    }
}

private extension Array where Element: ProfileScopedRecord {
    func orphanedCount(profileIDs: Set<UUID>) -> Int {
        filter { record in
            guard let profileID = record.profileID else { return true }
            return !profileIDs.contains(profileID)
        }.count
    }
}
