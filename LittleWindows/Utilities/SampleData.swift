import Foundation
import SwiftData

enum SampleData {
    static let defaultBirthDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 31)
    ) ?? Date()

    @MainActor
    static func seedIfNeeded(in context: ModelContext) async {
        _ = try? LegacyHuckleberryGrowthMigration.migrate(in: context)
        let descriptor = FetchDescriptor<BabyProfile>()
        if (try? context.fetchCount(descriptor)) == 0 {
            do {
                let data = try bundledHuckleberryHistory()
                try DataExportImportService.importData(data, context: context)
            } catch {
                createStarterProfile(in: context)
            }
        }
        ProfileMigrationService.ensureProfilesAndAssignments(context: context)
    }

    @MainActor
    static func createStarterProfile(in context: ModelContext) {
        context.insert(BabyProfile(name: "Ethan", birthDate: defaultBirthDate, sex: .male))
        if let profile = try? context.fetch(FetchDescriptor<BabyProfile>()).first {
            ProfileService.shared.switchProfile(profile)
        }
        try? context.save()
    }

    static func bundledHuckleberryHistory() throws -> Data {
        guard let url = Bundle.main.url(
            forResource: "Ethan-Huckleberry-Backup",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    @MainActor
    static func previewContainer() -> ModelContainer {
        let schema = Schema([
            BabyProfile.self,
            BabyEvent.self,
            DoctorAppointment.self,
            MilestoneEntry.self,
            AgeGuideReadState.self,
            PuppyStageGuideReadState.self,
            SleepPredictionRecord.self,
            PredictionFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create preview data: \(error)")
        }
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let profile = BabyProfile(name: "Ethan", birthDate: defaultBirthDate, sex: .male)
        profile.displayColor = "indigo"
        context.insert(profile)
        let sampleBaby = BabyProfile(
            name: "Sample Baby",
            birthDate: calendar.date(byAdding: .month, value: -2, to: now) ?? now,
            sex: .unknown,
            displayColor: "teal"
        )
        context.insert(sampleBaby)
        let meso = BabyProfile(
            profileType: .dog,
            name: "Meso",
            birthDate: calendar.date(byAdding: .weekOfYear, value: -12, to: now) ?? now,
            sex: .female,
            notes: "Preview dog profile",
            displayColor: "teal",
            adoptionDate: calendar.date(byAdding: .weekOfYear, value: -4, to: now),
            species: "dog",
            breed: "Mini Goldendoodle",
            coatColor: "Apricot"
        )
        context.insert(meso)
        ProfileService.shared.switchProfile(profile)

        let wake = calendar.date(bySettingHour: 7, minute: 5, second: 0, of: now) ?? now
        let napStart = calendar.date(bySettingHour: 9, minute: 12, second: 0, of: now) ?? now
        let napEnd = calendar.date(bySettingHour: 10, minute: 3, second: 0, of: now) ?? now
        let feedDate = calendar.date(bySettingHour: 10, minute: 20, second: 0, of: now) ?? now

        let night = BabyEvent(type: .sleep, startDate: calendar.date(byAdding: .hour, value: -10, to: wake) ?? wake, endDate: wake)
        night.profileID = profile.id
        night.sleepKind = .nightSleep
        context.insert(night)

        let nap = BabyEvent(type: .sleep, startDate: napStart, endDate: napEnd)
        nap.profileID = profile.id
        nap.sleepKind = .nap
        context.insert(nap)

        let feed = BabyEvent(type: .feed, startDate: feedDate, endDate: feedDate)
        feed.profileID = profile.id
        feed.feedKind = .bottle
        feed.amountOz = 5
        context.insert(feed)

        let examples = [
            ("First smile", 21, MilestoneCategory.social),
            ("Sized up diapers", 30, MilestoneCategory.diapering),
            ("Lifted neck", 42, MilestoneCategory.motor),
            ("Holding hands at center", 90, MilestoneCategory.motor)
        ]
        for (title, dayOffset, category) in examples {
            let date = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: profile.birthDate
            ) ?? profile.birthDate
            context.insert(MilestoneEntry(
                profileID: profile.id,
                title: title,
                date: date,
                category: category,
                notes: title == "First smile" ? "A tiny smile worth remembering." : nil,
                isFavorite: title == "First smile"
            ))
        }
        return container
    }
}
