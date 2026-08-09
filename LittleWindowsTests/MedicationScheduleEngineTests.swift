import SwiftData
import UserNotifications
import XCTest
@testable import LittleWindows

final class MedicationScheduleEngineTests: XCTestCase {
    func testMedicationDoseUnitsCoverCommonMedicationForms() {
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .tablet), .tablet)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .capsule), .capsule)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .liquid), .milliliters)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .injection), .milliliters)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .inhaler), .puffs)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .drops), .drops)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .cream), .applications)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .patch), .patches)
        XCTAssertEqual(MedicationDoseUnit.defaultUnit(for: .other), .doses)

        XCTAssertTrue(MedicationDoseUnit.allCases.contains(.milligrams))
        XCTAssertTrue(MedicationDoseUnit.allCases.contains(.micrograms))
        XCTAssertTrue(MedicationDoseUnit.allCases.contains(.units))
        XCTAssertTrue(MedicationDoseUnit.allCases.contains(.teaspoons))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, month: Int = 1, year: Int = 2026, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @MainActor
    func testDailyScheduleCreatesEveryConfiguredDose() {
        let regimen = makeRegimen(
            kind: .daily,
            times: [MedicationDoseTime(hour: 8, minute: 0), MedicationDoseTime(hour: 20, minute: 0)]
        )

        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: date(1),
            through: date(3, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(occurrences.count, 6)
        XCTAssertEqual(occurrences.map { calendar.component(.hour, from: $0.scheduledAt) }, [8, 20, 8, 20, 8, 20])
    }

    @MainActor
    func testScheduleStartDateUsesTheSelectedCalendarDay() {
        let regimen = makeRegimen(kind: .daily, start: date(1, hour: 12))

        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: date(1),
            through: date(1, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(calendar.component(.hour, from: occurrences[0].scheduledAt), 8)
    }

    @MainActor
    func testSpringDaylightSavingGapStillProducesOneDose() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = losAngeles.date(from: DateComponents(
            year: 2026, month: 3, day: 8
        ))!
        let end = losAngeles.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 23, minute: 59
        ))!
        let regimen = MedicationRegimen(
            profileID: UUID(),
            medicationID: UUID(),
            scheduleKind: .daily,
            startDate: start,
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 2, minute: 30)],
            timeZoneIdentifier: losAngeles.timeZone.identifier
        )

        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: start,
            through: end,
            calendar: losAngeles
        )

        XCTAssertEqual(occurrences.count, 1)
        XCTAssertTrue(losAngeles.isDate(occurrences[0].scheduledAt, inSameDayAs: start))
        XCTAssertGreaterThanOrEqual(losAngeles.component(.hour, from: occurrences[0].scheduledAt), 3)
    }

    @MainActor
    func testLoggedOccurrencesAreExcludedFromReminderCandidates() throws {
        let regimen = makeRegimen(kind: .daily)
        let profileID = try XCTUnwrap(regimen.profileID)
        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: date(1),
            through: date(2, hour: 23),
            calendar: calendar
        )
        let record = MedicationDoseRecord(
            profileID: profileID,
            medicationID: regimen.medicationID,
            regimenID: regimen.id,
            occurrenceKey: occurrences[0].occurrenceKey,
            scheduledAt: occurrences[0].scheduledAt,
            status: .taken,
            doseAmount: 1,
            doseUnit: "tablet"
        )

        XCTAssertEqual(
            MedicationScheduleEngine.unloggedOccurrences(occurrences, records: [record]),
            [occurrences[1]]
        )
    }

    @MainActor
    func testLocalTimeScheduleKeepsItsCalendarDayAndIdentityWhenTraveling() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let components = DateComponents(year: 2026, month: 8, day: 8)
        let regimen = MedicationRegimen(
            profileID: UUID(),
            medicationID: UUID(),
            scheduleKind: .daily,
            startDate: losAngeles.date(from: components)!,
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
            timeZoneBehavior: .localTime,
            timeZoneIdentifier: losAngeles.timeZone.identifier
        )
        let losAngelesStart = losAngeles.date(from: components)!
        let losAngelesEnd = losAngeles.date(from: DateComponents(
            year: 2026, month: 8, day: 8, hour: 23, minute: 59
        ))!
        let tokyoStart = tokyo.date(from: components)!
        let tokyoEnd = tokyo.date(from: DateComponents(
            year: 2026, month: 8, day: 8, hour: 23, minute: 59
        ))!

        let home = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: losAngelesStart,
            through: losAngelesEnd,
            calendar: losAngeles
        )
        let traveling = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: tokyoStart,
            through: tokyoEnd,
            calendar: tokyo
        )

        XCTAssertEqual(home.count, 1)
        XCTAssertEqual(traveling.count, 1)
        XCTAssertEqual(home[0].occurrenceKey, traveling[0].occurrenceKey)
        XCTAssertEqual(tokyo.component(.hour, from: traveling[0].scheduledAt), 8)

        let storedInTokyo = tokyo.date(from: components)!
        let displayedInLosAngeles = MedicationScheduleDate.displayDate(
            for: storedInTokyo,
            anchorTimeZoneIdentifier: tokyo.timeZone.identifier,
            calendar: losAngeles
        )
        XCTAssertEqual(
            losAngeles.dateComponents([.year, .month, .day], from: displayedInLosAngeles),
            components
        )

        let editedComponents = DateComponents(year: 2026, month: 8, day: 10)
        let selectedInLosAngeles = losAngeles.date(from: editedComponents)!
        let storedForTokyo = MedicationScheduleDate.storedDate(
            for: selectedInLosAngeles,
            anchorTimeZoneIdentifier: tokyo.timeZone.identifier,
            calendar: losAngeles
        )
        let redisplayedInTokyo = MedicationScheduleDate.displayDate(
            for: storedForTokyo,
            anchorTimeZoneIdentifier: tokyo.timeZone.identifier,
            calendar: tokyo
        )
        XCTAssertEqual(
            tokyo.dateComponents([.year, .month, .day], from: redisplayedInTokyo),
            editedComponents
        )
    }

    @MainActor
    func testSpecificWeekdaysAndEveryNDaysSchedules() {
        // January 5, 2026 is a Monday. Calendar weekday 2 maps to bit 1.
        let weekdays = makeRegimen(kind: .specificWeekdays, start: date(5), weekdayMask: 1 << 1)
        let weekdayOccurrences = MedicationScheduleEngine.occurrences(
            regimen: weekdays,
            phases: [],
            from: date(5),
            through: date(18, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(weekdayOccurrences.map { calendar.component(.day, from: $0.scheduledAt) }, [5, 12])

        let everyThreeDays = makeRegimen(kind: .everyNDays, intervalDays: 3)
        let intervalOccurrences = MedicationScheduleEngine.occurrences(
            regimen: everyThreeDays,
            phases: [],
            from: date(1),
            through: date(10, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(intervalOccurrences.map { calendar.component(.day, from: $0.scheduledAt) }, [1, 4, 7, 10])
    }

    @MainActor
    func testFixedCourseAndOnOffCycleRespectBoundaries() {
        let fixed = makeRegimen(kind: .fixedCourse, end: date(3))
        XCTAssertEqual(
            MedicationScheduleEngine.occurrences(
                regimen: fixed,
                phases: [],
                from: date(1),
                through: date(7, hour: 23),
                calendar: calendar
            ).count,
            3
        )

        let cycle = makeRegimen(kind: .cycle, cycleOnDays: 2, cycleOffDays: 1)
        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: cycle,
            phases: [],
            from: date(1),
            through: date(7, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.scheduledAt) }, [1, 2, 4, 5, 7])
    }

    @MainActor
    func testAlternatingAndTaperSchedulesUsePhases() throws {
        let alternating = makeRegimen(kind: .alternating)
        let alternatingProfileID = try XCTUnwrap(alternating.profileID)
        let alternatingPhases = [
            MedicationSchedulePhase(
                profileID: alternatingProfileID, regimenID: alternating.id, sequence: 0,
                durationDays: 1, doseAmount: 1, doseUnit: "tablet",
                doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
            ),
            MedicationSchedulePhase(
                profileID: alternatingProfileID, regimenID: alternating.id, sequence: 1,
                durationDays: 1, doseAmount: 2, doseUnit: "tablets",
                doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
            )
        ]
        let alternatingOccurrences = MedicationScheduleEngine.occurrences(
            regimen: alternating,
            phases: alternatingPhases,
            from: date(1),
            through: date(4, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(alternatingOccurrences.map(\.doseAmount), [1, 2, 1, 2])

        let taper = makeRegimen(kind: .taper)
        let taperProfileID = try XCTUnwrap(taper.profileID)
        let taperPhases = [
            MedicationSchedulePhase(
                profileID: taperProfileID, regimenID: taper.id, sequence: 0,
                durationDays: 2, doseAmount: 4, doseUnit: "mg",
                doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
            ),
            MedicationSchedulePhase(
                profileID: taperProfileID, regimenID: taper.id, sequence: 1,
                durationDays: 2, doseAmount: 2, doseUnit: "mg",
                doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
            )
        ]
        let taperOccurrences = MedicationScheduleEngine.occurrences(
            regimen: taper,
            phases: taperPhases,
            from: date(1),
            through: date(7, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(taperOccurrences.map(\.doseAmount), [4, 4, 2, 2])
    }

    @MainActor
    func testAsNeededSafetyRulesAndAdherence() throws {
        let regimen = makeRegimen(
            kind: .asNeeded,
            minimumHoursBetweenDoses: 6,
            maximumDosesPerDay: 2
        )
        let profileID = try XCTUnwrap(regimen.profileID)
        let first = MedicationDoseRecord(
            profileID: profileID,
            medicationID: regimen.medicationID,
            regimenID: regimen.id,
            status: .taken,
            loggedAt: date(1, hour: 8),
            takenAt: date(1, hour: 8),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        XCTAssertEqual(
            MedicationScheduleEngine.asNeededDecision(
                regimen: regimen,
                records: [first],
                at: date(1, hour: 10),
                calendar: calendar
            ),
            .waitUntil(date(1, hour: 14))
        )

        let second = MedicationDoseRecord(
            profileID: profileID,
            medicationID: regimen.medicationID,
            regimenID: regimen.id,
            status: .taken,
            loggedAt: date(1, hour: 15),
            takenAt: date(1, hour: 15),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        XCTAssertEqual(
            MedicationScheduleEngine.asNeededDecision(
                regimen: regimen,
                records: [first, second],
                at: date(1, hour: 22),
                calendar: calendar
            ),
            .dailyLimitReached(2)
        )

        let scheduled = makeRegimen(kind: .daily)
        let scheduledProfileID = try XCTUnwrap(scheduled.profileID)
        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: scheduled,
            phases: [],
            from: date(1),
            through: date(3, hour: 23),
            calendar: calendar
        )
        let taken = MedicationDoseRecord(
            profileID: scheduledProfileID, medicationID: scheduled.medicationID,
            regimenID: scheduled.id, occurrenceKey: occurrences[0].occurrenceKey,
            scheduledAt: occurrences[0].scheduledAt, status: .taken,
            doseAmount: 1, doseUnit: "tablet"
        )
        let skipped = MedicationDoseRecord(
            profileID: scheduledProfileID, medicationID: scheduled.medicationID,
            regimenID: scheduled.id, occurrenceKey: occurrences[1].occurrenceKey,
            scheduledAt: occurrences[1].scheduledAt, status: .skipped,
            doseAmount: 1, doseUnit: "tablet"
        )
        XCTAssertEqual(
            MedicationScheduleEngine.adherence(
                occurrences: occurrences,
                records: [taken, skipped],
                through: date(3, hour: 23)
            ),
            MedicationAdherenceSummary(scheduledCount: 3, takenCount: 1, skippedCount: 1, missedCount: 1)
        )
    }

    @MainActor
    func testAdultProfilesDefaultPrivateAndExposeAdultCapabilities() {
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .parent
        )

        XCTAssertEqual(profile.sharingScope, .privateOnly)
        XCTAssertTrue(profile.isOwned(by: profile.ownerIdentifier))
        XCTAssertFalse(profile.isOwned(by: UUID().uuidString))
        XCTAssertNil(profile.birthDate)
        XCTAssertTrue(profile.profileType.capabilities.supportsMedications)
        XCTAssertTrue(profile.profileType.capabilities.supportsHealthObservations)
        XCTAssertFalse(profile.profileType.capabilities.supportsSleepPrediction)
        XCTAssertFalse(profile.profileType.capabilities.supportsPediatricGrowthReferences)
        XCTAssertEqual(
            WatchActionCatalog.actions(profileTypeRawValue: "adult").map(\.id),
            ["sleep", "activity"]
        )
        XCTAssertEqual(
            BloodGlucoseUnit.millimolesPerLiter.milligramsPerDeciliter(from: 5.5),
            99.1001,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testSymptomsAndVitalsCannotBeClonedAsFreshMeasurements() {
        let measuredHealthTypes: [EventType] = [
            .symptom,
            .bloodPressure,
            .heartRate,
            .oxygenSaturation,
            .respiratoryRate,
            .glucose,
            .pain
        ]

        for type in measuredHealthTypes {
            let event = CareEvent(profileID: UUID(), type: type, startDate: date(1))
            event.profileTypeSnapshot = .adult
            XCTAssertFalse(
                EventMutationService.canQuickRepeat(event),
                "\(type.displayName) should require a fresh measurement or review."
            )
        }

        let medicationEvent = CareEvent(
            profileID: UUID(),
            type: .medicine,
            startDate: date(1)
        )
        XCTAssertFalse(EventMutationService.canQuickRepeat(medicationEvent))
    }

    @MainActor
    func testBackupRoundTripPreservesMedicationAndHealthDetails() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let event = CareEvent(profileID: profile.id, type: .bloodPressure, startDate: date(1, hour: 9))
        event.profileTypeSnapshot = .adult
        event.healthObservationDetails = HealthObservationDetails(
            systolicBloodPressure: 118,
            diastolicBloodPressure: 76,
            heartRateBPM: 64
        )
        let medication = Medication(profileID: profile.id, name: "Test Medication", strength: 10)
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet",
            remindersEnabled: true,
            followUpRemindersEnabled: true
        )
        let dose = MedicationDoseRecord(
            profileID: profile.id,
            medicationID: medication.id,
            regimenID: regimen.id,
            status: .taken,
            loggedAt: date(1, hour: 8),
            takenAt: date(1, hour: 8),
            doseAmount: 1,
            doseUnit: "tablet",
            supplyAdjustmentApplied: -1
        )
        context.insert(profile)
        context.insert(event)
        context.insert(medication)
        context.insert(regimen)
        context.insert(dose)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)
        try DataExportImportService.importData(
            backup,
            context: context,
            createRecoveryBackup: false
        )

        let restoredEvents = try context.fetch(FetchDescriptor<CareEvent>())
        let restoredMedications = try context.fetch(FetchDescriptor<Medication>())
        let restoredRegimens = try context.fetch(FetchDescriptor<MedicationRegimen>())
        let restoredDoses = try context.fetch(FetchDescriptor<MedicationDoseRecord>())
        XCTAssertEqual(restoredEvents.first?.healthObservationDetails.systolicBloodPressure, 118)
        XCTAssertEqual(restoredEvents.first?.healthObservationDetails.diastolicBloodPressure, 76)
        XCTAssertEqual(restoredMedications.map(\.name), ["Test Medication"])
        XCTAssertEqual(restoredRegimens.first?.scheduleKind, .daily)
        XCTAssertEqual(restoredRegimens.first?.followUpRemindersEnabled, true)
        XCTAssertEqual(restoredDoses.first?.status, .taken)
        XCTAssertEqual(restoredDoses.first?.supplyAdjustmentApplied, -1)
    }

    @MainActor
    func testBackupValidationRejectsInvalidHealthObservationPayload() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let event = CareEvent(
            profileID: profile.id,
            type: .oxygenSaturation,
            startDate: date(1, hour: 9)
        )
        event.profileTypeSnapshot = .adult
        event.healthObservationDetails = HealthObservationDetails(
            oxygenSaturationPercent: 98
        )
        context.insert(profile)
        context.insert(event)
        try context.save()

        let validBackup = try DataExportImportService.exportData(context: context)
        XCTAssertNoThrow(try DataExportImportService.validateBackupData(validBackup))
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validBackup) as? [String: Any]
        )
        var events = try XCTUnwrap(json["events"] as? [[String: Any]])
        events[0]["healthObservationDetailsData"] = try JSONEncoder().encode(
            HealthObservationDetails(oxygenSaturationPercent: 130)
        ).base64EncodedString()
        json["events"] = events
        let corruptedBackup = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try DataExportImportService.validateBackupData(corruptedBackup))
    }

    @MainActor
    func testBackupValidationRejectsCrossProfileMedicationReferences() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let privateProfile = CareProfile(
            profileType: .adult,
            name: "Private Adult",
            adultRelationship: .myself
        )
        let sharedProfile = CareProfile(
            profileType: .adult,
            name: "Shared Adult",
            adultRelationship: .parent,
            sharingScope: .family
        )
        let medication = Medication(
            profileID: privateProfile.id,
            name: "Test Medication"
        )
        let mismatchedRegimen = MedicationRegimen(
            profileID: sharedProfile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(privateProfile)
        context.insert(sharedProfile)
        context.insert(medication)
        context.insert(mismatchedRegimen)
        try context.save()

        let backup = try DataExportImportService.exportData(context: context)

        XCTAssertThrowsError(try DataExportImportService.validateBackupData(backup))
    }

    @MainActor
    func testBackupValidationRejectsAlternatingScheduleWithoutItsPhases() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(profileID: profile.id, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .alternating,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        context.insert(MedicationSchedulePhase(
            profileID: profile.id,
            regimenID: regimen.id,
            sequence: 0,
            durationDays: 1,
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
        ))
        context.insert(MedicationSchedulePhase(
            profileID: profile.id,
            regimenID: regimen.id,
            sequence: 1,
            durationDays: 1,
            doseAmount: 2,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
        ))
        try context.save()

        let validBackup = try DataExportImportService.exportData(context: context)
        XCTAssertNoThrow(try DataExportImportService.validateBackupData(validBackup))
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validBackup) as? [String: Any]
        )
        json["medicationSchedulePhases"] = []
        let corruptedBackup = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try DataExportImportService.validateBackupData(corruptedBackup))
    }

    @MainActor
    func testBackupValidationRejectsMultipleActiveSchedulesForOneMedication() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(profileID: profile.id, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()

        let validBackup = try DataExportImportService.exportData(context: context)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validBackup) as? [String: Any]
        )
        var regimens = try XCTUnwrap(json["medicationRegimens"] as? [[String: Any]])
        var duplicate = try XCTUnwrap(regimens.first)
        duplicate["id"] = UUID().uuidString
        regimens.append(duplicate)
        json["medicationRegimens"] = regimens
        let corruptedBackup = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try DataExportImportService.validateBackupData(corruptedBackup))
    }

    @MainActor
    func testManagedDoseCommandRejectsStaleSchedulePayload() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let scheduleCalendar = MedicationScheduleDate.currentCalendar()
        let scheduledAt = try XCTUnwrap(scheduleCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 8,
            hour: 8
        )))
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(profileID: profile.id, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: scheduleCalendar.startOfDay(for: scheduledAt),
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
            timeZoneIdentifier: scheduleCalendar.timeZone.identifier
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()
        let occurrence = try XCTUnwrap(MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: scheduledAt,
            through: scheduledAt
        ).first)
        let reference = MedicationScheduledDoseReference(
            profileID: profile.id,
            medicationID: medication.id,
            regimenID: regimen.id,
            phaseID: occurrence.phaseID,
            occurrenceKey: occurrence.occurrenceKey,
            scheduledAt: occurrence.scheduledAt,
            doseAmount: occurrence.doseAmount,
            doseUnit: occurrence.doseUnit
        )

        regimen.doseAmount = 2
        try context.save()

        XCTAssertEqual(
            MedicationService.recordScheduledDose(
                reference,
                status: .taken,
                at: scheduledAt,
                context: context
            ),
            .rejected("This medication schedule changed. Open Medications to review it.")
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<MedicationDoseRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CareEvent>()).isEmpty)
    }

    @MainActor
    func testManagedDoseCommandIsIdempotentAndRejectsConflictingStatus() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let scheduleCalendar = MedicationScheduleDate.currentCalendar()
        let scheduledAt = try XCTUnwrap(scheduleCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 8,
            hour: 8
        )))
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            currentSupply: 4
        )
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: scheduleCalendar.startOfDay(for: scheduledAt),
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
            timeZoneIdentifier: scheduleCalendar.timeZone.identifier
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()
        let occurrence = try XCTUnwrap(MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: scheduledAt,
            through: scheduledAt
        ).first)
        let reference = MedicationScheduledDoseReference(
            profileID: profile.id,
            medicationID: medication.id,
            regimenID: regimen.id,
            phaseID: occurrence.phaseID,
            occurrenceKey: occurrence.occurrenceKey,
            scheduledAt: occurrence.scheduledAt,
            doseAmount: occurrence.doseAmount,
            doseUnit: occurrence.doseUnit
        )

        XCTAssertEqual(
            MedicationService.recordScheduledDose(
                reference,
                status: .taken,
                at: scheduledAt,
                context: context
            ),
            .applied(medicationName: "Test Medication")
        )
        XCTAssertEqual(
            MedicationService.recordScheduledDose(
                reference,
                status: .taken,
                at: scheduledAt,
                context: context
            ),
            .duplicate(medicationName: "Test Medication")
        )
        XCTAssertEqual(
            MedicationService.recordScheduledDose(
                reference,
                status: .skipped,
                at: scheduledAt,
                context: context
            ),
            .rejected("This dose was already recorded as taken.")
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<MedicationDoseRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareEvent>()).count, 1)
        XCTAssertEqual(medication.currentSupply, 3)
    }

    func testMedicationSnoozeStateExpiresAndCanBeClearedByRegimen() throws {
        let suiteName = "MedicationSnoozeStateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let regimenID = UUID()
        let occurrenceKey = "\(regimenID.uuidString)|2026-08-08|08:00"
        let now = date(8, month: 8, hour: 8)

        MedicationSnoozeStateStore.markSnoozed(
            occurrenceKey: occurrenceKey,
            until: now.addingTimeInterval(10 * 60),
            now: now,
            defaults: defaults
        )

        XCTAssertTrue(MedicationSnoozeStateStore.isSnoozed(
            occurrenceKey: occurrenceKey,
            now: now.addingTimeInterval(9 * 60),
            defaults: defaults
        ))
        XCTAssertFalse(MedicationSnoozeStateStore.isSnoozed(
            occurrenceKey: occurrenceKey,
            now: now.addingTimeInterval(10 * 60),
            defaults: defaults
        ))

        MedicationSnoozeStateStore.markSnoozed(
            occurrenceKey: occurrenceKey,
            until: now.addingTimeInterval(20 * 60),
            now: now,
            defaults: defaults
        )
        let secondOccurrenceKey = "\(regimenID.uuidString)|2026-08-08|09:00"
        MedicationSnoozeStateStore.markSnoozed(
            occurrenceKey: secondOccurrenceKey,
            until: now.addingTimeInterval(20 * 60),
            now: now,
            defaults: defaults
        )
        MedicationSnoozeStateStore.retain(
            occurrenceKeys: [occurrenceKey],
            for: regimenID,
            defaults: defaults
        )
        XCTAssertTrue(MedicationSnoozeStateStore.isSnoozed(
            occurrenceKey: occurrenceKey,
            now: now,
            defaults: defaults
        ))
        XCTAssertFalse(MedicationSnoozeStateStore.isSnoozed(
            occurrenceKey: secondOccurrenceKey,
            now: now,
            defaults: defaults
        ))

        MedicationSnoozeStateStore.clear(regimenID: regimenID, defaults: defaults)
        XCTAssertFalse(MedicationSnoozeStateStore.isSnoozed(
            occurrenceKey: occurrenceKey,
            now: now,
            defaults: defaults
        ))
    }

    func testMedicationNotificationPayloadBuildsManagedDoseCommand() throws {
        let profileID = UUID()
        let medicationID = UUID()
        let regimenID = UUID()
        let phaseID = UUID()
        let scheduledAt = date(1, hour: 8)
        let command = try XCTUnwrap(MedicationNotificationScheduler.doseCommand(
            from: [
                "profileID": profileID.uuidString,
                "medicationID": medicationID.uuidString,
                "regimenID": regimenID.uuidString,
                "phaseID": phaseID.uuidString,
                "occurrenceKey": "scheduled-dose",
                "scheduledAt": scheduledAt.timeIntervalSince1970,
                "doseAmount": 1.5,
                "doseUnit": "tablet"
            ],
            status: .taken
        ))

        XCTAssertEqual(command.profileID, profileID)
        XCTAssertEqual(command.medicationID, medicationID)
        XCTAssertEqual(command.regimenID, regimenID)
        XCTAssertEqual(command.phaseID, phaseID)
        XCTAssertEqual(command.occurrenceKey, "scheduled-dose")
        XCTAssertEqual(command.scheduledAt, scheduledAt)
        XCTAssertEqual(command.doseAmount, 1.5)
        XCTAssertEqual(command.doseUnit, "tablet")
        XCTAssertEqual(command.status, .taken)
        XCTAssertNil(MedicationNotificationScheduler.doseCommand(
            from: ["profileID": profileID.uuidString],
            status: .taken
        ))
    }

    func testWatchMedicationSnoozeBuildsManagedNotificationRequest() throws {
        let scheduledAt = date(1, hour: 8)
        let fireDate = date(1, hour: 9)
        let medication = WatchMedicationSnapshot(
            profileID: UUID(),
            medicationID: UUID(),
            regimenID: UUID(),
            phaseID: UUID(),
            occurrenceKey: "watch-dose",
            medicationName: "Test Medication",
            scheduledAt: scheduledAt,
            doseAmount: 1.5,
            doseUnit: "tablets",
            snoozeAvailable: true
        )

        let request = MedicationNotificationScheduler.watchSnoozeRequest(
            medication: medication,
            fireDate: fireDate
        )
        let command = try XCTUnwrap(MedicationNotificationScheduler.doseCommand(
            from: request.content.userInfo,
            status: .taken
        ))
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)

        XCTAssertTrue(request.identifier.hasSuffix(".snooze"))
        XCTAssertEqual(request.content.categoryIdentifier, MedicationNotificationScheduler.categoryIdentifier)
        XCTAssertEqual(request.content.title, "Time for Test Medication")
        XCTAssertEqual(command.profileID, medication.profileID)
        XCTAssertEqual(command.medicationID, medication.medicationID)
        XCTAssertEqual(command.regimenID, medication.regimenID)
        XCTAssertEqual(command.occurrenceKey, medication.occurrenceKey)
        XCTAssertEqual(command.scheduledAt, scheduledAt)
        XCTAssertEqual(command.doseAmount, 1.5)
        XCTAssertEqual(command.doseUnit, "tablets")
        XCTAssertEqual(
            trigger.dateComponents,
            Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
        )
    }

    func testMedicationNotificationBudgetLeavesRoomForOtherAppReminders() {
        XCTAssertEqual(
            MedicationNotificationScheduler.availableMedicationRequestCount(
                nonMedicationPendingRequestCount: 0
            ),
            48
        )
        XCTAssertEqual(
            MedicationNotificationScheduler.availableMedicationRequestCount(
                nonMedicationPendingRequestCount: 40
            ),
            24
        )
        XCTAssertEqual(
            MedicationNotificationScheduler.availableMedicationRequestCount(
                nonMedicationPendingRequestCount: 64
            ),
            0
        )
        XCTAssertEqual(
            MedicationNotificationScheduler.availableMedicationRequestCount(
                nonMedicationPendingRequestCount: 80
            ),
            0
        )
    }

    @MainActor
    func testMedicationMutationsRejectCrossProfileRelationships() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let firstProfile = CareProfile(profileType: .adult, name: "First Adult")
        let secondProfile = CareProfile(profileType: .adult, name: "Second Adult")
        let medication = Medication(
            profileID: firstProfile.id,
            name: "Test Medication"
        )
        let crossProfileRegimen = MedicationRegimen(
            profileID: secondProfile.id,
            medicationID: medication.id,
            scheduleKind: .asNeeded,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(firstProfile)
        context.insert(secondProfile)
        context.insert(medication)
        context.insert(crossProfileRegimen)
        try context.save()

        XCTAssertNil(MedicationService.recordDose(
            medication: medication,
            regimen: crossProfileRegimen,
            status: .taken,
            context: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MedicationDoseRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CareEvent>()).isEmpty)

        let crossProfileRecord = MedicationDoseRecord(
            profileID: secondProfile.id,
            medicationID: medication.id,
            regimenID: crossProfileRegimen.id,
            status: .skipped,
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(crossProfileRecord)
        try context.save()

        MedicationService.updateDoseRecordStatus(
            crossProfileRecord,
            medication: medication,
            status: .taken,
            context: context
        )
        XCTAssertEqual(crossProfileRecord.status, .skipped)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CareEvent>()).isEmpty)

        MedicationService.deleteDoseRecord(
            crossProfileRecord,
            medication: medication,
            context: context
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<MedicationDoseRecord>()).count, 1)
    }

    @MainActor
    func testDoseCorrectionsKeepTimelineAndSupplyConsistent() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            currentSupply: 0.5
        )
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .asNeeded,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()

        let record = try XCTUnwrap(MedicationService.recordDose(
            medication: medication,
            regimen: regimen,
            status: .taken,
            at: date(1, hour: 8),
            context: context
        ))
        XCTAssertEqual(medication.currentSupply, 0)
        XCTAssertEqual(record.supplyAdjustmentApplied, -0.5)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareEvent>()).first?.profileTypeSnapshot, .adult)

        MedicationService.updateDoseRecordStatus(
            record,
            medication: medication,
            status: .skipped,
            at: date(1, hour: 9),
            context: context
        )
        XCTAssertEqual(medication.currentSupply, 0.5)
        XCTAssertEqual(record.supplyAdjustmentApplied, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CareEvent>()).isEmpty)

        MedicationService.updateDoseRecordStatus(
            record,
            medication: medication,
            status: .taken,
            at: date(1, hour: 10),
            context: context
        )
        let mirrorID = try XCTUnwrap(record.careEventID)
        XCTAssertEqual(medication.currentSupply, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareEvent>()).count, 1)

        XCTAssertTrue(MedicationService.prepareForCareEventDeletion(
            eventID: mirrorID,
            context: context
        ))
        if let mirror = try context.fetch(FetchDescriptor<CareEvent>()).first {
            context.delete(mirror)
        }
        try context.save()
        XCTAssertEqual(medication.currentSupply, 0.5)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MedicationDoseRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CareEvent>()).isEmpty)

        MedicationService.updateSupply(
            medication: medication,
            newSupply: 12,
            reason: .refill,
            notes: "Test refill.",
            context: context
        )
        let refillLog = try XCTUnwrap(
            context.fetch(FetchDescriptor<MedicationSupplyLog>())
                .first(where: { $0.reason == .refill })
        )
        XCTAssertEqual(refillLog.adjustment, 11.5)
        XCTAssertEqual(refillLog.resultingSupply, 12)
        XCTAssertEqual(refillLog.notes, "Test refill.")
    }

    @MainActor
    func testFamilyExportExcludesAndRemoteImportPreservesPrivateProfiles() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let privateProfile = CareProfile(
            profileType: .adult,
            name: "Private Adult",
            adultRelationship: .myself
        )
        let sharedProfile = CareProfile(
            profileType: .adult,
            name: "Shared Adult",
            adultRelationship: .parent,
            sharingScope: .family
        )
        let privateMedication = Medication(profileID: privateProfile.id, name: "Private Medication")
        let sharedMedication = Medication(profileID: sharedProfile.id, name: "Shared Medication")
        context.insert(privateProfile)
        context.insert(sharedProfile)
        context.insert(privateMedication)
        context.insert(sharedMedication)
        try context.save()

        let familyData = try DataExportImportService.exportData(
            context: context,
            includeCaregiverIdentity: false,
            profileScope: .familyShared
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: familyData) as? [String: Any])
        let exportedProfiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        let exportedMedications = try XCTUnwrap(json["medications"] as? [[String: Any]])
        XCTAssertEqual(exportedProfiles.compactMap { $0["name"] as? String }, ["Shared Adult"])
        XCTAssertEqual(exportedMedications.compactMap { $0["name"] as? String }, ["Shared Medication"])

        try DataExportImportService.importData(
            familyData,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false,
            preservePrivateProfiles: true
        )
        let restoredProfiles = try context.fetch(FetchDescriptor<CareProfile>())
        let restoredMedications = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(Set(restoredProfiles.map(\.name)), Set(["Private Adult", "Shared Adult"]))
        XCTAssertEqual(Set(restoredMedications.map(\.name)), Set(["Private Medication", "Shared Medication"]))
    }

    @MainActor
    func testRemoteImportCannotOverwritePrivateProfileFromStalePayload() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Private Adult",
            adultRelationship: .myself
        )
        let medication = Medication(profileID: profile.id, name: "Original Medication")
        context.insert(profile)
        context.insert(medication)
        try context.save()

        let stalePayload = try DataExportImportService.exportData(context: context)
        profile.name = "Updated Private Adult"
        medication.name = "Updated Medication"
        try context.save()

        try DataExportImportService.importData(
            stalePayload,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false,
            preservePrivateProfiles: true
        )

        let profiles = try context.fetch(FetchDescriptor<CareProfile>())
        let medications = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Updated Private Adult")
        XCTAssertEqual(medications.count, 1)
        XCTAssertEqual(medications.first?.name, "Updated Medication")
    }

    @MainActor
    func testFamilyMergeResolvesConcurrentLogsForTheSameScheduledDose() throws {
        let baseContainer = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let baseContext = baseContainer.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Shared Adult",
            adultRelationship: .parent,
            sharingScope: .family
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            currentSupply: 10,
            updatedAt: date(1)
        )
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet",
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        baseContext.insert(profile)
        baseContext.insert(medication)
        baseContext.insert(regimen)
        try baseContext.save()
        let base = try DataExportImportService.exportData(
            context: baseContext,
            includeCaregiverIdentity: false,
            profileScope: .familyShared
        )

        let localContainer = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let localContext = localContainer.mainContext
        try DataExportImportService.importData(
            base,
            context: localContext,
            recordLocalSave: false,
            createRecoveryBackup: false
        )
        let localMedication = try XCTUnwrap(localContext.fetch(FetchDescriptor<Medication>()).first)
        let localRegimen = try XCTUnwrap(localContext.fetch(FetchDescriptor<MedicationRegimen>()).first)
        let occurrence = try XCTUnwrap(MedicationScheduleEngine.occurrences(
            regimen: localRegimen,
            phases: [],
            from: date(1),
            through: date(1, hour: 23),
            calendar: calendar
        ).first)
        MedicationService.recordDose(
            medication: localMedication,
            regimen: localRegimen,
            occurrence: occurrence,
            status: .taken,
            at: date(1, hour: 9),
            context: localContext
        )
        let local = try DataExportImportService.exportData(
            context: localContext,
            includeCaregiverIdentity: false,
            profileScope: .familyShared
        )

        let remoteContainer = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let remoteContext = remoteContainer.mainContext
        try DataExportImportService.importData(
            base,
            context: remoteContext,
            recordLocalSave: false,
            createRecoveryBackup: false
        )
        let remoteMedication = try XCTUnwrap(remoteContext.fetch(FetchDescriptor<Medication>()).first)
        let remoteRegimen = try XCTUnwrap(remoteContext.fetch(FetchDescriptor<MedicationRegimen>()).first)
        MedicationService.recordDose(
            medication: remoteMedication,
            regimen: remoteRegimen,
            occurrence: occurrence,
            status: .skipped,
            at: date(1, hour: 10),
            context: remoteContext
        )
        let remote = try DataExportImportService.exportData(
            context: remoteContext,
            includeCaregiverIdentity: false,
            profileScope: .familyShared
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: base,
            local: local,
            remote: remote,
            localChangedAt: date(1, hour: 9),
            remoteChangedAt: date(1, hour: 10)
        )
        let resultContainer = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let resultContext = resultContainer.mainContext
        try DataExportImportService.importData(
            merged,
            context: resultContext,
            recordLocalSave: false,
            createRecoveryBackup: false
        )

        let doses = try resultContext.fetch(FetchDescriptor<MedicationDoseRecord>())
        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(doses.first?.status, .skipped)
        XCTAssertTrue(try resultContext.fetch(FetchDescriptor<CareEvent>()).isEmpty)
        XCTAssertEqual(try resultContext.fetch(FetchDescriptor<Medication>()).first?.currentSupply, 10)
        XCTAssertTrue(try resultContext.fetch(FetchDescriptor<MedicationSupplyLog>()).isEmpty)
    }

    @MainActor
    func testDuplicateRepairRecognizesMedicationOnlyProfileAsHavingCareData() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let original = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .parent,
            createdAt: date(1),
            updatedAt: date(1)
        )
        let setupShell = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .parent,
            createdAt: date(2),
            updatedAt: date(2)
        )
        let medication = Medication(profileID: original.id, name: "Test Medication")
        context.insert(original)
        context.insert(setupShell)
        context.insert(medication)
        try context.save()

        let removedCount = ProfileDuplicateRepairService.repair(context: context)

        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareProfile>()).map(\.id), [original.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).first?.profileID, original.id)
    }

    @MainActor
    func testDuplicateRepairPreservesAdultPrivacyBoundaries() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let ownerID = UUID().uuidString
        let privateProfile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            sex: .unknown,
            adultRelationship: .parent,
            sharingScope: .privateOnly,
            ownerIdentifier: ownerID
        )
        let sharedProfile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            sex: .unknown,
            adultRelationship: .parent,
            sharingScope: .family,
            ownerIdentifier: ownerID
        )
        context.insert(privateProfile)
        context.insert(sharedProfile)
        try context.save()

        let removedCount = ProfileDuplicateRepairService.repair(context: context)

        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareProfile>()).count, 2)
    }

    @MainActor
    private func makeRegimen(
        kind: MedicationScheduleKind,
        start: Date? = nil,
        end: Date? = nil,
        times: [MedicationDoseTime] = [MedicationDoseTime(hour: 8, minute: 0)],
        weekdayMask: Int = 127,
        intervalDays: Int = 2,
        cycleOnDays: Int = 21,
        cycleOffDays: Int = 7,
        minimumHoursBetweenDoses: Double? = nil,
        maximumDosesPerDay: Int? = nil
    ) -> MedicationRegimen {
        MedicationRegimen(
            profileID: UUID(),
            medicationID: UUID(),
            scheduleKind: kind,
            startDate: start ?? date(1),
            endDate: end,
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: times,
            weekdayMask: weekdayMask,
            intervalDays: intervalDays,
            cycleOnDays: cycleOnDays,
            cycleOffDays: cycleOffDays,
            minimumHoursBetweenDoses: minimumHoursBetweenDoses,
            maximumDosesPerDay: maximumDosesPerDay
        )
    }
}
