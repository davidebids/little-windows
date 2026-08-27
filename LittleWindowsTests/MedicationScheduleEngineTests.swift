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
    func testAdherenceSeparatesDoseOutcomesAndTakenExceptions() throws {
        let regimen = makeRegimen(kind: .daily)
        let profileID = try XCTUnwrap(regimen.profileID)
        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: date(1),
            through: date(7, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(occurrences.count, 7)

        let outcomes: [(MedicationDoseStatus, MedicationDoseTiming?, Double?, MedicationDoseReason?)] = [
            (.taken, .late, 0.5, nil),
            (.held, nil, nil, .perClinicianInstruction),
            (.refused, nil, nil, .refused),
            (.unable, nil, nil, .unableToTake),
            (.missed, nil, nil, .outOfSupply),
            (.skipped, nil, nil, nil)
        ]
        let records = zip(occurrences, outcomes).map { occurrence, outcome in
            MedicationDoseRecord(
                profileID: profileID,
                medicationID: regimen.medicationID,
                regimenID: regimen.id,
                occurrenceKey: occurrence.occurrenceKey,
                scheduledAt: occurrence.scheduledAt,
                status: outcome.0,
                takenAt: outcome.0 == .taken ? occurrence.scheduledAt.addingTimeInterval(45 * 60) : nil,
                actualDoseAmount: outcome.2,
                timing: outcome.1,
                reason: outcome.3,
                doseAmount: occurrence.doseAmount,
                doseUnit: occurrence.doseUnit
            )
        }

        let summary = MedicationScheduleEngine.adherence(
            occurrences: occurrences,
            records: records,
            through: date(7, hour: 23)
        )
        XCTAssertEqual(summary.scheduledCount, 7)
        XCTAssertEqual(summary.takenCount, 1)
        XCTAssertEqual(summary.lateCount, 1)
        XCTAssertEqual(summary.differentAmountCount, 1)
        XCTAssertEqual(summary.heldCount, 1)
        XCTAssertEqual(summary.refusedCount, 1)
        XCTAssertEqual(summary.unableCount, 1)
        XCTAssertEqual(summary.recordedMissedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.missedCount, 1)
        XCTAssertEqual(summary.recordedNotTakenCount, 5)
        XCTAssertEqual(summary.takenExceptionCount, 1)
        XCTAssertEqual(summary.exceptionCount, 7)
        XCTAssertEqual(summary.completionRate ?? -1, 1.0 / 7.0, accuracy: 0.000_001)
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
    func testMedicationPlanEditsCreateVersionsAndPreservePriorDoseMeaning() throws {
        let planCalendar = MedicationScheduleDate.currentCalendar()
        func planDate(_ day: Int, hour: Int = 0) -> Date {
            planCalendar.date(from: DateComponents(
                year: 2026,
                month: 1,
                day: day,
                hour: hour
            ))!
        }
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
        context.insert(profile)
        let medication = MedicationService.createMedication(
            profileID: profile.id,
            name: "Test Medication",
            form: .tablet,
            strength: 10,
            strengthUnit: "mg",
            route: .oral,
            instructions: "Take with food.",
            reasonForTaking: "Test purpose",
            prescriber: "Test Clinician",
            pharmacy: "Test Pharmacy",
            currentSupply: nil,
            refillThreshold: nil,
            context: context
        )
        let originalRegimen = try XCTUnwrap(MedicationService.createRegimen(
            for: medication,
            scheduleKind: .alternating,
            startDate: planDate(1),
            endDate: nil,
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
            weekdayMask: 127,
            intervalDays: 1,
            cycleOnDays: 1,
            cycleOffDays: 0,
            minimumHoursBetweenDoses: nil,
            maximumDosesPerDay: nil,
            remindersEnabled: true,
            followUpRemindersEnabled: true,
            timeZoneBehavior: .localTime,
            phases: [(durationDays: 1, doseAmount: 1), (durationDays: 1, doseAmount: 2)],
            changeContext: MedicationPlanChangeContext(
                effectiveFrom: planDate(1),
                source: .prescriptionLabel,
                notes: "Initial label review.",
                confirmsCurrent: true
            ),
            context: context
        ))
        let occurrence = try XCTUnwrap(MedicationScheduleEngine.occurrences(
            regimen: originalRegimen,
            phases: MedicationService.phasesForRegimen(originalRegimen.id, context: context),
            from: planDate(1),
            through: planDate(1, hour: 23),
            calendar: planCalendar
        ).first)
        let originalDose = try XCTUnwrap(MedicationService.recordDose(
            medication: medication,
            regimen: originalRegimen,
            occurrence: occurrence,
            status: .taken,
            at: occurrence.scheduledAt,
            context: context
        ))

        let revisedRegimen = try XCTUnwrap(MedicationService.updateMedication(
            medication: medication,
            regimen: originalRegimen,
            name: "Test Medication",
            form: .tablet,
            strength: 10,
            strengthUnit: "mg",
            route: .oral,
            instructions: "Take in the morning.",
            reasonForTaking: "Test purpose",
            prescriber: "Test Clinician",
            pharmacy: "Test Pharmacy",
            currentSupply: nil,
            refillThreshold: nil,
            scheduleKind: .daily,
            startDate: planDate(2),
            endDate: nil,
            doseAmount: 2,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 9, minute: 0)],
            weekdayMask: 127,
            intervalDays: 1,
            cycleOnDays: 1,
            cycleOffDays: 0,
            minimumHoursBetweenDoses: nil,
            maximumDosesPerDay: nil,
            remindersEnabled: true,
            followUpRemindersEnabled: false,
            timeZoneBehavior: .localTime,
            phases: [],
            changeContext: MedicationPlanChangeContext(
                effectiveFrom: planDate(2),
                source: .clinician,
                notes: "Dose changed after visit.",
                confirmsCurrent: true
            ),
            context: context
        ))

        XCTAssertNotEqual(originalRegimen.id, revisedRegimen.id)
        XCTAssertFalse(originalRegimen.isActive)
        XCTAssertEqual(originalRegimen.doseAmount, 1)
        XCTAssertEqual(originalRegimen.doseTimes, [MedicationDoseTime(hour: 8, minute: 0)])
        let preservedPhases = MedicationService.phasesForRegimen(
            originalRegimen.id,
            context: context
        )
        XCTAssertEqual(preservedPhases.map(\.doseAmount), [1, 2])
        XCTAssertTrue(revisedRegimen.isActive)
        XCTAssertEqual(revisedRegimen.doseAmount, 2)
        XCTAssertEqual(revisedRegimen.doseTimes, [MedicationDoseTime(hour: 9, minute: 0)])
        XCTAssertEqual(originalDose.regimenID, originalRegimen.id)
        XCTAssertEqual(originalDose.doseAmount, occurrence.doseAmount)
        XCTAssertTrue(medication.isConfirmedCurrent)
        XCTAssertNotNil(medication.lastReviewedAt)

        let revisions = try context.fetch(FetchDescriptor<MedicationPlanRevision>(
            sortBy: [SortDescriptor(\.changedAt)]
        ))
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(revisions.first?.changeKind, .added)
        let changedRevision = try XCTUnwrap(revisions.last)
        XCTAssertEqual(changedRevision.changeKind, .updated)
        XCTAssertEqual(changedRevision.source, .clinician)
        XCTAssertEqual(
            changedRevision.effectiveFrom,
            planCalendar.startOfDay(for: planDate(2))
        )
        XCTAssertEqual(changedRevision.priorRegimenID, originalRegimen.id)
        XCTAssertEqual(changedRevision.regimenID, revisedRegimen.id)
        XCTAssertEqual(changedRevision.beforeSnapshot?.doseAmount, 1)
        XCTAssertEqual(changedRevision.afterSnapshot?.doseAmount, 2)
        XCTAssertEqual(changedRevision.beforeSnapshot?.instructions, "Take with food.")
        XCTAssertEqual(changedRevision.afterSnapshot?.instructions, "Take in the morning.")
        XCTAssertFalse(changedRevision.changedByName.isEmpty)

        let versionedOccurrences = MedicationScheduleEngine.versionedOccurrences(
            medicationID: medication.id,
            regimens: [originalRegimen, revisedRegimen],
            phases: preservedPhases + MedicationService.phasesForRegimen(
                revisedRegimen.id,
                context: context
            ),
            revisions: revisions,
            from: planDate(1),
            through: planDate(3, hour: 23),
            calendar: planCalendar
        )
        XCTAssertEqual(versionedOccurrences.map(\.regimenID), [
            originalRegimen.id,
            revisedRegimen.id,
            revisedRegimen.id
        ])
        XCTAssertEqual(versionedOccurrences.map { planCalendar.component(.hour, from: $0.scheduledAt) }, [8, 9, 9])
    }

    @MainActor
    func testVersionedOccurrencesIgnoreAbandonedConcurrentPlanBranch() {
        let profileID = UUID()
        let medication = Medication(profileID: profileID, name: "Test Medication")
        let original = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
            isActive: false
        )
        let abandoned = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(2),
            doseAmount: 2,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 9, minute: 0)],
            isActive: false
        )
        let authoritative = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(2),
            doseAmount: 3,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 10, minute: 0)],
            isActive: true
        )
        let revisions = [
            MedicationPlanRevision(
                profileID: profileID,
                medicationID: medication.id,
                regimenID: original.id,
                changeKind: .added,
                source: .prescriptionLabel,
                effectiveFrom: date(1),
                changedAt: date(1),
                afterSnapshot: MedicationPlanSnapshot(
                    medication: medication,
                    regimen: original,
                    phases: []
                )
            ),
            MedicationPlanRevision(
                profileID: profileID,
                medicationID: medication.id,
                priorRegimenID: original.id,
                regimenID: abandoned.id,
                changeKind: .updated,
                source: .caregiver,
                effectiveFrom: date(2),
                changedAt: date(3, hour: 9),
                afterSnapshot: MedicationPlanSnapshot(
                    medication: medication,
                    regimen: abandoned,
                    phases: []
                )
            ),
            MedicationPlanRevision(
                profileID: profileID,
                medicationID: medication.id,
                priorRegimenID: original.id,
                regimenID: authoritative.id,
                changeKind: .updated,
                source: .clinician,
                effectiveFrom: date(2),
                changedAt: date(3, hour: 10),
                afterSnapshot: MedicationPlanSnapshot(
                    medication: medication,
                    regimen: authoritative,
                    phases: []
                )
            )
        ]

        let occurrences = MedicationScheduleEngine.versionedOccurrences(
            medicationID: medication.id,
            regimens: [original, abandoned, authoritative],
            phases: [],
            revisions: revisions,
            from: date(1),
            through: date(3, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(occurrences.map(\.regimenID), [
            original.id,
            authoritative.id,
            authoritative.id
        ])
        XCTAssertEqual(
            occurrences.map { calendar.component(.hour, from: $0.scheduledAt) },
            [8, 10, 10]
        )
    }

    @MainActor
    func testSameDayPlanChangePreservesEarlierDoseUnderPriorPlan() {
        let profileID = UUID()
        let medication = Medication(profileID: profileID, name: "Test Medication")
        let original = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
            isActive: false
        )
        let revised = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(2),
            doseAmount: 2,
            doseUnit: "tablet",
            doseTimes: [
                MedicationDoseTime(hour: 9, minute: 0),
                MedicationDoseTime(hour: 18, minute: 0)
            ],
            isActive: true
        )
        let revisions = [
            MedicationPlanRevision(
                profileID: profileID,
                medicationID: medication.id,
                regimenID: original.id,
                changeKind: .added,
                source: .prescriptionLabel,
                effectiveFrom: date(1),
                changedAt: date(1, hour: 7),
                afterSnapshot: MedicationPlanSnapshot(
                    medication: medication,
                    regimen: original,
                    phases: []
                )
            ),
            MedicationPlanRevision(
                profileID: profileID,
                medicationID: medication.id,
                priorRegimenID: original.id,
                regimenID: revised.id,
                changeKind: .updated,
                source: .clinician,
                effectiveFrom: date(2),
                changedAt: date(2, hour: 12),
                afterSnapshot: MedicationPlanSnapshot(
                    medication: medication,
                    regimen: revised,
                    phases: []
                )
            )
        ]

        let occurrences = MedicationScheduleEngine.versionedOccurrences(
            medicationID: medication.id,
            regimens: [original, revised],
            phases: [],
            revisions: revisions,
            from: date(1),
            through: date(2, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(occurrences.map(\.regimenID), [
            original.id,
            original.id,
            revised.id
        ])
        XCTAssertEqual(
            occurrences.map { calendar.component(.hour, from: $0.scheduledAt) },
            [8, 8, 18]
        )
    }

    func testFamilySyncMergeLeavesOneAuthoritativeActiveRegimen() throws {
        let medicationID = UUID().uuidString
        let originalID = UUID().uuidString
        let localID = UUID().uuidString
        let remoteID = UUID().uuidString
        let base = Data(
            """
            {"version":30,"exportedAt":"2026-01-01T08:00:00Z","medications":[{"id":"\(medicationID)","isArchived":false,"updatedAt":"2026-01-01T08:00:00Z"}],"medicationRegimens":[{"id":"\(originalID)","medicationID":"\(medicationID)","isActive":true,"updatedAt":"2026-01-01T08:00:00Z"}]}
            """.utf8
        )
        let local = Data(
            """
            {"version":30,"exportedAt":"2026-01-02T09:00:00Z","medications":[{"id":"\(medicationID)","isArchived":false,"updatedAt":"2026-01-01T08:00:00Z"}],"medicationRegimens":[{"id":"\(originalID)","medicationID":"\(medicationID)","isActive":false,"updatedAt":"2026-01-02T09:00:00Z"},{"id":"\(localID)","medicationID":"\(medicationID)","isActive":true,"updatedAt":"2026-01-02T09:00:00Z"}]}
            """.utf8
        )
        let remote = Data(
            """
            {"version":30,"exportedAt":"2026-01-02T10:00:00Z","medications":[{"id":"\(medicationID)","isArchived":false,"updatedAt":"2026-01-01T08:00:00Z"}],"medicationRegimens":[{"id":"\(originalID)","medicationID":"\(medicationID)","isActive":false,"updatedAt":"2026-01-02T10:00:00Z"},{"id":"\(remoteID)","medicationID":"\(medicationID)","isActive":true,"updatedAt":"2026-01-02T10:00:00Z"}]}
            """.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: base,
            local: local,
            remote: remote,
            localChangedAt: date(2, hour: 9),
            remoteChangedAt: date(2, hour: 10)
        )
        let payloads = try DataExportImportService.familySyncEntityPayloads(from: merged)
        let regimens = try payloads.compactMap { key, payload -> [String: Any]? in
            guard key.hasPrefix("medicationRegimens|") else { return nil }
            return try XCTUnwrap(
                JSONSerialization.jsonObject(with: payload) as? [String: Any]
            )
        }
        let activeRegimens = regimens.filter { ($0["isActive"] as? Bool) == true }

        XCTAssertEqual(activeRegimens.count, 1)
        XCTAssertEqual(activeRegimens.first?["id"] as? String, remoteID)
    }

    func testFamilySyncMergeResolvesConcurrentRefillTasksAndStaleClaims() throws {
        let medicationID = UUID().uuidString
        let localTaskID = UUID().uuidString
        let remoteTaskID = UUID().uuidString
        let localClaimID = UUID().uuidString
        let remoteClaimID = UUID().uuidString
        let localSourceKey = "medicationRefill:\(localTaskID.lowercased())"
        let remoteSourceKey = "medicationRefill:\(remoteTaskID.lowercased())"
        let base = Data(
            #"{"version":30,"exportedAt":"2026-01-01T08:00:00Z","medicationRefillTasks":[],"attentionClaims":[]}"#.utf8
        )
        let local = Data(
            """
            {"version":30,"exportedAt":"2026-01-02T09:00:00Z","medicationRefillTasks":[{"id":"\(localTaskID)","medicationID":"\(medicationID)","statusRawValue":"needsRequest","updatedAt":"2026-01-02T09:00:00Z"}],"attentionClaims":[{"id":"\(localClaimID)","sourceKey":"\(localSourceKey)","updatedAt":"2026-01-02T09:00:00Z"}]}
            """.utf8
        )
        let remote = Data(
            """
            {"version":30,"exportedAt":"2026-01-02T10:00:00Z","medicationRefillTasks":[{"id":"\(remoteTaskID)","medicationID":"\(medicationID)","statusRawValue":"requested","updatedAt":"2026-01-02T10:00:00Z"}],"attentionClaims":[{"id":"\(remoteClaimID)","sourceKey":"\(remoteSourceKey)","updatedAt":"2026-01-02T10:00:00Z"}]}
            """.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: base,
            local: local,
            remote: remote,
            localChangedAt: date(2, hour: 9),
            remoteChangedAt: date(2, hour: 10)
        )
        let payloads = try DataExportImportService.familySyncEntityPayloads(from: merged)
        let tasks = try payloads.compactMap { key, payload -> [String: Any]? in
            guard key.hasPrefix("medicationRefillTasks|") else { return nil }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        }
        let claims = payloads.keys.filter { $0.hasPrefix("attentionClaims|") }

        XCTAssertEqual(tasks.filter {
            ($0["statusRawValue"] as? String) == MedicationRefillStatus.requested.rawValue
        }.count, 1)
        XCTAssertEqual(tasks.filter {
            ($0["statusRawValue"] as? String) == MedicationRefillStatus.cancelled.rawValue
        }.count, 1)
        XCTAssertEqual(claims, ["attentionClaims|\(remoteClaimID)"])
    }

    func testFamilySyncMergeKeepsCompletedPickupOverStaleOpenEdit() throws {
        let taskID = UUID().uuidString
        let base = Data(
            """
            {"version":30,"exportedAt":"2026-01-01T08:00:00Z","medicationRefillTasks":[{"id":"\(taskID)","statusRawValue":"readyForPickup","updatedAt":"2026-01-01T08:00:00Z"}]}
            """.utf8
        )
        let local = Data(
            """
            {"version":30,"exportedAt":"2026-01-02T09:00:00Z","medicationRefillTasks":[{"id":"\(taskID)","statusRawValue":"pickedUp","updatedAt":"2026-01-02T09:00:00Z"}]}
            """.utf8
        )
        let remote = Data(
            """
            {"version":30,"exportedAt":"2026-01-02T10:00:00Z","medicationRefillTasks":[{"id":"\(taskID)","statusRawValue":"readyForPickup","updatedAt":"2026-01-02T10:00:00Z"}]}
            """.utf8
        )

        let merged = try DataExportImportService.mergeFamilySyncData(
            base: base,
            local: local,
            remote: remote,
            localChangedAt: date(2, hour: 9),
            remoteChangedAt: date(2, hour: 10)
        )
        let payload = try XCTUnwrap(
            DataExportImportService.familySyncEntityPayloads(from: merged)[
                "medicationRefillTasks|\(taskID)"
            ]
        )
        let task = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])

        XCTAssertEqual(
            task["statusRawValue"] as? String,
            MedicationRefillStatus.pickedUp.rawValue
        )
    }

    @MainActor
    func testMedicationReconciliationConfirmsAndLinksReviewSession() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .parent
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

        let appointmentID = UUID()
        let reconciliationID = UUID()
        XCTAssertTrue(MedicationService.confirmCurrent(
            medication: medication,
            regimens: [regimen],
            changeContext: MedicationPlanChangeContext(
                effectiveFrom: date(2),
                source: .dischargePaperwork,
                appointmentID: appointmentID,
                reconciliationID: reconciliationID,
                notes: "Compared with discharge list.",
                confirmsCurrent: true
            ),
            context: context
        ))
        XCTAssertTrue(medication.isConfirmedCurrent)
        XCTAssertNotNil(medication.lastReviewedAt)
        let confirmation = try XCTUnwrap(
            context.fetch(FetchDescriptor<MedicationPlanRevision>()).first
        )
        XCTAssertEqual(confirmation.changeKind, .confirmedCurrent)
        XCTAssertEqual(confirmation.source, .dischargePaperwork)
        XCTAssertEqual(confirmation.appointmentID, appointmentID)
        XCTAssertEqual(confirmation.reconciliationID, reconciliationID)
        XCTAssertEqual(confirmation.beforeSnapshot?.isConfirmedCurrent, false)
        XCTAssertEqual(confirmation.afterSnapshot?.isConfirmedCurrent, true)
        XCTAssertNil(confirmation.beforeSnapshot?.lastReviewedAt)
        XCTAssertNotNil(confirmation.afterSnapshot?.lastReviewedAt)

        let reconciliation = try XCTUnwrap(MedicationService.completeReconciliation(
            id: reconciliationID,
            profileID: profile.id,
            source: .dischargePaperwork,
            effectiveFrom: date(2),
            appointmentID: appointmentID,
            notes: "Discharge reconciliation complete.",
            reviewedMedicationIDs: [medication.id],
            context: context
        ))
        XCTAssertEqual(reconciliation.id, reconciliationID)
        XCTAssertEqual(reconciliation.source, .dischargePaperwork)
        XCTAssertEqual(reconciliation.appointmentID, appointmentID)
        XCTAssertEqual(reconciliation.reviewedMedicationIDs, [medication.id])
    }

    @MainActor
    func testSupplyProjectionUsesActualTakenAmountsAndFlagsTripRisk() throws {
        let profileID = UUID()
        let medication = Medication(
            profileID: profileID,
            name: "Test Medication",
            currentSupply: 10
        )
        let now = date(10, hour: 12)
        let records = (7...10).map { day in
            MedicationDoseRecord(
                profileID: profileID,
                medicationID: medication.id,
                status: .taken,
                loggedAt: date(day, hour: 8),
                takenAt: date(day, hour: 8),
                actualDoseAmount: 1,
                doseAmount: 2,
                doseUnit: "tablet"
            )
        }

        let projection = try XCTUnwrap(MedicationService.supplyProjection(
            medication: medication,
            doseRecords: records,
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(projection.averageDailyUse, 1, accuracy: 0.000_001)
        XCTAssertEqual(projection.estimatedDaysRemaining, 10, accuracy: 0.000_001)
        XCTAssertEqual(projection.observedDoseCount, 4)
        XCTAssertEqual(projection.observedDayCount, 4)
        XCTAssertEqual(projection.estimatedRunOutDate, now.addingTimeInterval(10 * 86_400))
        XCTAssertEqual(projection.confidence, .developing)

        let householdID = UUID()
        let duringTrip = PackingTrip(
            householdID: householdID,
            title: "Test Trip",
            startDate: date(15),
            endDate: date(22)
        )
        guard case .duringTrip(let duringRunOut)? = MedicationService.tripSupplyRisk(
            projection: projection,
            trip: duringTrip,
            calendar: calendar
        ) else {
            return XCTFail("Expected a during-trip supply warning.")
        }
        XCTAssertEqual(duringRunOut, projection.estimatedRunOutDate)

        let afterRunOutTrip = PackingTrip(
            householdID: householdID,
            title: "Later Test Trip",
            startDate: date(21),
            endDate: date(24)
        )
        guard case .beforeTrip(let beforeRunOut)? = MedicationService.tripSupplyRisk(
            projection: projection,
            trip: afterRunOutTrip,
            calendar: calendar
        ) else {
            return XCTFail("Expected a before-trip supply warning.")
        }
        XCTAssertEqual(beforeRunOut, projection.estimatedRunOutDate)
    }

    @MainActor
    func testBatchSupplyProjectionKeepsMedicationHistoriesIsolated() throws {
        let profileID = UUID()
        let firstMedication = Medication(
            profileID: profileID,
            name: "Test Medication A",
            currentSupply: 10
        )
        let secondMedication = Medication(
            profileID: profileID,
            name: "Test Medication B",
            currentSupply: 24
        )
        let now = date(10, hour: 12)
        let firstRecords = (7...10).map { day in
            MedicationDoseRecord(
                profileID: profileID,
                medicationID: firstMedication.id,
                status: .taken,
                loggedAt: date(day, hour: 8),
                takenAt: date(day, hour: 8),
                actualDoseAmount: 1,
                doseAmount: 1,
                doseUnit: "tablet"
            )
        }
        let secondRecords = (7...10).map { day in
            MedicationDoseRecord(
                profileID: profileID,
                medicationID: secondMedication.id,
                status: .taken,
                loggedAt: date(day, hour: 8),
                takenAt: date(day, hour: 8),
                actualDoseAmount: 2,
                doseAmount: 2,
                doseUnit: "tablet"
            )
        }
        let ignoredRecord = MedicationDoseRecord(
            profileID: profileID,
            medicationID: firstMedication.id,
            scheduledAt: date(10, hour: 9),
            status: .held,
            loggedAt: date(10, hour: 9),
            doseAmount: 20,
            doseUnit: "tablet"
        )

        let projections = MedicationService.supplyProjections(
            medications: [firstMedication, secondMedication],
            doseRecords: firstRecords + secondRecords + [ignoredRecord],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(projections.count, 2)
        let first = try XCTUnwrap(projections[firstMedication.id])
        XCTAssertEqual(first.averageDailyUse, 1, accuracy: 0.000_001)
        XCTAssertEqual(first.estimatedDaysRemaining, 10, accuracy: 0.000_001)
        XCTAssertEqual(first.observedDoseCount, 4)
        let second = try XCTUnwrap(projections[secondMedication.id])
        XCTAssertEqual(second.averageDailyUse, 2, accuracy: 0.000_001)
        XCTAssertEqual(second.estimatedDaysRemaining, 12, accuracy: 0.000_001)
        XCTAssertEqual(second.observedDoseCount, 4)
    }

    @MainActor
    func testRefillLifecycleAddsFillAndDecrementsRemainingRefills() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let household = Household(name: "Home")
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            pharmacy: "Test Pharmacy",
            currentSupply: 5,
            refillLeadDays: 7,
            prescriptionNumber: "RX-TEST",
            fillQuantity: 30,
            refillsRemaining: 2
        )
        context.insert(household)
        context.insert(profile)
        context.insert(medication)
        try context.save()

        XCTAssertNil(MedicationService.createRefillTask(
            medication: medication,
            householdID: UUID(),
            dueDate: date(12),
            fillQuantity: 30,
            context: context,
            now: date(10)
        ))
        let task = try XCTUnwrap(MedicationService.createRefillTask(
            medication: medication,
            householdID: household.id,
            dueDate: date(12),
            fillQuantity: 30,
            assignedCaregiverIdentifier: "test-caregiver",
            assignedCaregiverName: "Test Caregiver",
            notes: "Request before travel.",
            context: context,
            now: date(10)
        ))
        XCTAssertEqual(task.status, .needsRequest)
        XCTAssertEqual(task.prescriptionNumberSnapshot, "RX-TEST")
        XCTAssertEqual(task.assignedCaregiverName, "Test Caregiver")
        XCTAssertNil(MedicationService.createRefillTask(
            medication: medication,
            householdID: household.id,
            dueDate: date(13),
            fillQuantity: 30,
            context: context,
            now: date(10)
        ))

        XCTAssertTrue(MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: .requested,
            context: context,
            now: date(11)
        ))
        XCTAssertEqual(task.status, .requested)
        XCTAssertEqual(task.requestedAt, date(11))
        XCTAssertTrue(MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: .readyForPickup,
            context: context,
            now: date(12)
        ))
        XCTAssertEqual(task.status, .readyForPickup)
        XCTAssertTrue(MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: .pickedUp,
            context: context,
            now: date(13)
        ))
        XCTAssertEqual(task.status, .pickedUp)
        XCTAssertEqual(medication.currentSupply, 35)
        XCTAssertEqual(medication.refillsRemaining, 1)
        XCTAssertNotNil(task.completedByCaregiverIdentifier)
        let refillLog = try XCTUnwrap(
            context.fetch(FetchDescriptor<MedicationSupplyLog>()).last
        )
        XCTAssertEqual(refillLog.reason, .refill)
        XCTAssertEqual(refillLog.adjustment, 30)
        XCTAssertEqual(refillLog.resultingSupply, 35)

        XCTAssertTrue(MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: .pickedUp,
            context: context,
            now: date(14)
        ))
        XCTAssertEqual(medication.currentSupply, 35)
        XCTAssertEqual(medication.refillsRemaining, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MedicationSupplyLog>()).filter { $0.reason == .refill }.count,
            1
        )
    }

    @MainActor
    func testArchivingMedicationCancelsOpenRefillTask() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let household = Household(name: "Home")
        let profile = CareProfile(profileType: .adult, name: "Test Adult")
        let medication = Medication(profileID: profile.id, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(household)
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()

        let task = try XCTUnwrap(MedicationService.createRefillTask(
            medication: medication,
            householdID: household.id,
            dueDate: date(5),
            fillQuantity: 30,
            context: context,
            now: date(1)
        ))

        MedicationService.archive(
            medication: medication,
            regimens: [regimen],
            context: context
        )

        XCTAssertTrue(medication.isArchived)
        XCTAssertEqual(task.status, .cancelled)
        XCTAssertEqual(task.cancelledAt, task.updatedAt)
        XCTAssertFalse(task.isOpen)
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
        let household = Household(name: "Home")
        let event = CareEvent(profileID: profile.id, type: .bloodPressure, startDate: date(1, hour: 9))
        event.profileTypeSnapshot = .adult
        event.healthObservationDetails = HealthObservationDetails(
            systolicBloodPressure: 118,
            diastolicBloodPressure: 76,
            heartRateBPM: 64
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            strength: 10,
            currentSupply: 12,
            refillThreshold: 5,
            refillLeadDays: 8,
            prescriptionNumber: "RX-BACKUP",
            fillQuantity: 30,
            refillsRemaining: 3,
            prescriptionExpirationDate: date(30),
            lastReviewedAt: date(2, hour: 10),
            isConfirmedCurrent: true
        )
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
            loggedAt: date(1, hour: 10),
            takenAt: date(1, hour: 9),
            actualDoseAmount: 0.5,
            timing: .late,
            doseAmount: 1,
            doseUnit: "tablet",
            supplyAdjustmentApplied: -0.5,
            notes: "Actual dose recorded."
        )
        let missedDose = MedicationDoseRecord(
            profileID: profile.id,
            medicationID: medication.id,
            regimenID: regimen.id,
            status: .missed,
            loggedAt: date(2, hour: 8),
            reason: .outOfSupply,
            doseAmount: 1,
            doseUnit: "tablet",
            notes: "Refill requested."
        )
        let reconciliationID = UUID()
        let planRevision = MedicationPlanRevision(
            profileID: profile.id,
            medicationID: medication.id,
            regimenID: regimen.id,
            changeKind: .confirmedCurrent,
            source: .prescriptionLabel,
            effectiveFrom: date(2),
            changedAt: date(2, hour: 10),
            reconciliationID: reconciliationID,
            notes: "Label confirmed.",
            afterSnapshot: MedicationPlanSnapshot(
                medication: medication,
                regimen: regimen,
                phases: []
            )
        )
        let reconciliation = MedicationReconciliation(
            id: reconciliationID,
            profileID: profile.id,
            source: .prescriptionLabel,
            effectiveFrom: date(2),
            completedAt: date(2, hour: 10),
            notes: "Medication review complete.",
            reviewedMedicationIDs: [medication.id]
        )
        let refillTask = MedicationRefillTask(
            householdID: household.id,
            profileID: profile.id,
            medicationID: medication.id,
            status: .requested,
            dueDate: date(8),
            fillQuantity: 30,
            prescriptionNumberSnapshot: "RX-BACKUP",
            pharmacySnapshot: "Test Pharmacy",
            notes: "Backup refill task.",
            requestedAt: date(3),
            assignedCaregiverIdentifier: "test-caregiver",
            assignedCaregiverName: "Test Caregiver"
        )
        context.insert(household)
        context.insert(profile)
        context.insert(event)
        context.insert(medication)
        context.insert(regimen)
        context.insert(dose)
        context.insert(missedDose)
        context.insert(planRevision)
        context.insert(reconciliation)
        context.insert(refillTask)
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
        let restoredPlanRevisions = try context.fetch(FetchDescriptor<MedicationPlanRevision>())
        let restoredReconciliations = try context.fetch(FetchDescriptor<MedicationReconciliation>())
        let restoredRefillTasks = try context.fetch(FetchDescriptor<MedicationRefillTask>())
        XCTAssertEqual(restoredEvents.first?.healthObservationDetails.systolicBloodPressure, 118)
        XCTAssertEqual(restoredEvents.first?.healthObservationDetails.diastolicBloodPressure, 76)
        XCTAssertEqual(restoredMedications.map(\.name), ["Test Medication"])
        XCTAssertEqual(restoredMedications.first?.isConfirmedCurrent, true)
        XCTAssertEqual(restoredMedications.first?.lastReviewedAt, date(2, hour: 10))
        XCTAssertEqual(restoredMedications.first?.refillLeadDays, 8)
        XCTAssertEqual(restoredMedications.first?.prescriptionNumber, "RX-BACKUP")
        XCTAssertEqual(restoredMedications.first?.fillQuantity, 30)
        XCTAssertEqual(restoredMedications.first?.refillsRemaining, 3)
        XCTAssertEqual(restoredMedications.first?.prescriptionExpirationDate, date(30))
        XCTAssertEqual(restoredRegimens.first?.scheduleKind, .daily)
        XCTAssertEqual(restoredRegimens.first?.followUpRemindersEnabled, true)
        let restoredTakenDose = try XCTUnwrap(restoredDoses.first { $0.id == dose.id })
        XCTAssertEqual(restoredTakenDose.status, .taken)
        XCTAssertEqual(restoredTakenDose.takenAt, date(1, hour: 9))
        XCTAssertEqual(restoredTakenDose.actualDoseAmount, 0.5)
        XCTAssertEqual(restoredTakenDose.timing, .late)
        XCTAssertTrue(restoredTakenDose.hasDifferentActualAmount)
        XCTAssertEqual(restoredTakenDose.supplyAdjustmentApplied, -0.5)
        XCTAssertEqual(restoredTakenDose.notes, "Actual dose recorded.")
        let restoredMissedDose = try XCTUnwrap(restoredDoses.first { $0.id == missedDose.id })
        XCTAssertEqual(restoredMissedDose.status, .missed)
        XCTAssertEqual(restoredMissedDose.reason, .outOfSupply)
        XCTAssertNil(restoredMissedDose.actualDoseAmount)
        XCTAssertEqual(restoredMissedDose.notes, "Refill requested.")
        XCTAssertEqual(restoredPlanRevisions.first?.changeKind, .confirmedCurrent)
        XCTAssertEqual(restoredPlanRevisions.first?.source, .prescriptionLabel)
        XCTAssertEqual(restoredPlanRevisions.first?.afterSnapshot?.doseAmount, 1)
        XCTAssertEqual(restoredReconciliations.first?.id, reconciliationID)
        XCTAssertEqual(restoredReconciliations.first?.reviewedMedicationIDs, [medication.id])
        XCTAssertEqual(restoredRefillTasks.first?.id, refillTask.id)
        XCTAssertEqual(restoredRefillTasks.first?.status, .requested)
        XCTAssertEqual(restoredRefillTasks.first?.assignedCaregiverName, "Test Caregiver")
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
    func testActualDoseCorrectionsReconcileSupplyAndTimeline() throws {
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
            currentSupply: 10
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
            at: date(1, hour: 9),
            takenAt: date(1, hour: 9),
            actualDoseAmount: 0.5,
            timing: .late,
            notes: "Half dose taken.",
            context: context
        ))
        XCTAssertEqual(record.actualDoseAmount, 0.5)
        XCTAssertEqual(record.timing, .late)
        XCTAssertEqual(record.supplyAdjustmentApplied, -0.5)
        XCTAssertEqual(medication.currentSupply, 9.5)
        var mirror = try XCTUnwrap(context.fetch(FetchDescriptor<CareEvent>()).first)
        XCTAssertEqual(mirror.startDate, date(1, hour: 9))
        XCTAssertEqual(mirror.dose, 0.5)
        XCTAssertEqual(mirror.notes, "Half dose taken.")

        XCTAssertTrue(MedicationService.updateDoseRecord(
            record,
            medication: medication,
            entry: MedicationDoseEntry(
                status: .taken,
                takenAt: date(1, hour: 10),
                actualDoseAmount: 0.75,
                timing: .late,
                reason: nil,
                notes: "Corrected actual amount."
            ),
            at: date(1, hour: 10),
            context: context
        ))
        XCTAssertEqual(record.actualDoseAmount, 0.75)
        XCTAssertEqual(record.supplyAdjustmentApplied, -0.75)
        XCTAssertEqual(medication.currentSupply, 9.25)
        let mirrorsAfterCorrection = try context.fetch(FetchDescriptor<CareEvent>())
        XCTAssertEqual(mirrorsAfterCorrection.count, 1)
        mirror = try XCTUnwrap(mirrorsAfterCorrection.first)
        XCTAssertEqual(mirror.startDate, date(1, hour: 10))
        XCTAssertEqual(mirror.dose, 0.75)
        XCTAssertEqual(mirror.notes, "Corrected actual amount.")

        XCTAssertTrue(MedicationService.updateDoseRecord(
            record,
            medication: medication,
            entry: MedicationDoseEntry(
                status: .held,
                takenAt: nil,
                actualDoseAmount: nil,
                timing: nil,
                reason: .perClinicianInstruction,
                notes: "Held until reviewed."
            ),
            at: date(1, hour: 11),
            context: context
        ))
        XCTAssertEqual(record.status, .held)
        XCTAssertEqual(record.reason, .perClinicianInstruction)
        XCTAssertNil(record.takenAt)
        XCTAssertNil(record.actualDoseAmount)
        XCTAssertEqual(record.supplyAdjustmentApplied, 0)
        XCTAssertEqual(medication.currentSupply, 10)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CareEvent>()).isEmpty)
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
        let household = Household(name: "Test Home")
        let privateAppointment = DoctorAppointment(
            profileID: privateProfile.id,
            title: "Private Visit",
            startDate: Date()
        )
        let sharedAppointment = DoctorAppointment(
            profileID: sharedProfile.id,
            title: "Shared Visit",
            startDate: Date()
        )
        let unscopedAppointment = DoctorAppointment(
            title: "Unscoped Visit",
            startDate: Date()
        )
        let privateFollowUp = AppointmentFollowUp(
            appointmentID: privateAppointment.id,
            householdID: household.id,
            profileID: privateProfile.id,
            title: "Private Follow-up"
        )
        let sharedFollowUp = AppointmentFollowUp(
            appointmentID: sharedAppointment.id,
            householdID: household.id,
            profileID: sharedProfile.id,
            title: "Shared Follow-up"
        )
        let unscopedFollowUp = AppointmentFollowUp(
            appointmentID: unscopedAppointment.id,
            householdID: household.id,
            profileID: nil,
            title: "Unscoped Follow-up"
        )
        let privateAcknowledgement = HouseholdAttentionAcknowledgement(
            id: UUID(),
            householdID: household.id,
            profileID: privateProfile.id,
            sourceKey: privateFollowUp.attentionSourceKey,
            sourceUpdatedAt: privateFollowUp.updatedAt,
            caregiverIdentifier: UUID().uuidString,
            caregiverName: "Caregiver One"
        )
        let sharedAcknowledgement = HouseholdAttentionAcknowledgement(
            id: UUID(),
            householdID: household.id,
            profileID: sharedProfile.id,
            sourceKey: sharedFollowUp.attentionSourceKey,
            sourceUpdatedAt: sharedFollowUp.updatedAt,
            caregiverIdentifier: UUID().uuidString,
            caregiverName: "Caregiver Two"
        )
        let sharedClaim = HouseholdAttentionClaim(
            id: HouseholdAttentionService.deterministicID("claim", sharedFollowUp.attentionSourceKey),
            householdID: household.id,
            profileID: sharedProfile.id,
            sourceKey: sharedFollowUp.attentionSourceKey,
            caregiverIdentifier: sharedAcknowledgement.caregiverIdentifier,
            caregiverName: "Caregiver Two",
            updatedByCaregiverIdentifier: sharedAcknowledgement.caregiverIdentifier,
            updatedByCaregiverName: "Caregiver Two"
        )
        let unscopedAcknowledgement = HouseholdAttentionAcknowledgement(
            id: UUID(),
            householdID: household.id,
            profileID: nil,
            sourceKey: unscopedFollowUp.attentionSourceKey,
            sourceUpdatedAt: unscopedFollowUp.updatedAt,
            caregiverIdentifier: UUID().uuidString,
            caregiverName: "Unscoped Caregiver"
        )
        let unscopedClaim = HouseholdAttentionClaim(
            id: HouseholdAttentionService.deterministicID("claim", unscopedFollowUp.attentionSourceKey),
            householdID: household.id,
            profileID: nil,
            sourceKey: unscopedFollowUp.attentionSourceKey,
            caregiverIdentifier: unscopedAcknowledgement.caregiverIdentifier,
            caregiverName: "Unscoped Caregiver",
            updatedByCaregiverIdentifier: unscopedAcknowledgement.caregiverIdentifier,
            updatedByCaregiverName: "Unscoped Caregiver"
        )
        let unscopedHandoffNote = CaregiverHandoffNote(
            householdID: household.id,
            profileID: nil,
            sourceKey: unscopedFollowUp.attentionSourceKey,
            sourceTitleSnapshot: unscopedFollowUp.title,
            body: "Must not be shared without a shared appointment.",
            authorCaregiverIdentifier: unscopedAcknowledgement.caregiverIdentifier,
            authorCaregiverName: "Unscoped Caregiver"
        )
        let generalHandoffNote = CaregiverHandoffNote(
            householdID: household.id,
            profileID: nil,
            sourceKey: nil,
            sourceTitleSnapshot: nil,
            body: "Check the shared bag.",
            authorCaregiverIdentifier: sharedAcknowledgement.caregiverIdentifier,
            authorCaregiverName: "Caregiver Two"
        )
        context.insert(privateProfile)
        context.insert(sharedProfile)
        context.insert(privateMedication)
        context.insert(sharedMedication)
        context.insert(household)
        context.insert(privateAppointment)
        context.insert(sharedAppointment)
        context.insert(unscopedAppointment)
        context.insert(privateFollowUp)
        context.insert(sharedFollowUp)
        context.insert(unscopedFollowUp)
        context.insert(privateAcknowledgement)
        context.insert(sharedAcknowledgement)
        context.insert(sharedClaim)
        context.insert(unscopedAcknowledgement)
        context.insert(unscopedClaim)
        context.insert(unscopedHandoffNote)
        context.insert(generalHandoffNote)
        try context.save()

        let familyData = try DataExportImportService.exportData(
            context: context,
            includeCaregiverIdentity: false,
            profileScope: .familyShared
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: familyData) as? [String: Any])
        let exportedProfiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        let exportedMedications = try XCTUnwrap(json["medications"] as? [[String: Any]])
        let exportedFollowUps = try XCTUnwrap(json["appointmentFollowUps"] as? [[String: Any]])
        let exportedAcknowledgements = try XCTUnwrap(
            json["attentionAcknowledgements"] as? [[String: Any]]
        )
        let exportedClaims = try XCTUnwrap(json["attentionClaims"] as? [[String: Any]])
        let exportedHandoffNotes = try XCTUnwrap(json["caregiverHandoffNotes"] as? [[String: Any]])
        XCTAssertEqual(exportedProfiles.compactMap { $0["name"] as? String }, ["Shared Adult"])
        XCTAssertEqual(exportedMedications.compactMap { $0["name"] as? String }, ["Shared Medication"])
        XCTAssertEqual(exportedFollowUps.compactMap { $0["title"] as? String }, ["Shared Follow-up"])
        XCTAssertEqual(
            exportedAcknowledgements.compactMap { $0["caregiverName"] as? String },
            ["Caregiver Two"]
        )
        XCTAssertEqual(exportedClaims.compactMap { $0["caregiverName"] as? String }, ["Caregiver Two"])
        XCTAssertEqual(exportedHandoffNotes.compactMap { $0["body"] as? String }, ["Check the shared bag."])

        try DataExportImportService.importData(
            familyData,
            context: context,
            recordLocalSave: false,
            createRecoveryBackup: false,
            preservePrivateProfiles: true
        )
        let restoredProfiles = try context.fetch(FetchDescriptor<CareProfile>())
        let restoredMedications = try context.fetch(FetchDescriptor<Medication>())
        let restoredFollowUps = try context.fetch(FetchDescriptor<AppointmentFollowUp>())
        let restoredAcknowledgements = try context.fetch(FetchDescriptor<HouseholdAttentionAcknowledgement>())
        let restoredClaims = try context.fetch(FetchDescriptor<HouseholdAttentionClaim>())
        let restoredHandoffNotes = try context.fetch(FetchDescriptor<CaregiverHandoffNote>())
        XCTAssertEqual(Set(restoredProfiles.map(\.name)), Set(["Private Adult", "Shared Adult"]))
        XCTAssertEqual(Set(restoredMedications.map(\.name)), Set(["Private Medication", "Shared Medication"]))
        XCTAssertEqual(Set(restoredFollowUps.map(\.title)), Set(["Private Follow-up", "Shared Follow-up"]))
        XCTAssertEqual(
            Set(restoredAcknowledgements.map(\.caregiverName)),
            Set(["Caregiver One", "Caregiver Two"])
        )
        XCTAssertEqual(restoredClaims.map(\.caregiverName), ["Caregiver Two"])
        XCTAssertEqual(restoredHandoffNotes.map(\.body), ["Check the shared bag."])
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
    func testDuplicateDoseLookupLargeHistoryPerformance() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profileID = UUID()
        let medication = Medication(profileID: profileID, name: "Test Medication")
        let regimen = MedicationRegimen(
            profileID: profileID,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        let occurrence = try XCTUnwrap(MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: date(1),
            through: date(1, hour: 23),
            calendar: calendar
        ).first)
        let existingRecord = MedicationDoseRecord(
            profileID: profileID,
            medicationID: medication.id,
            regimenID: regimen.id,
            occurrenceKey: occurrence.occurrenceKey,
            scheduledAt: occurrence.scheduledAt,
            status: .taken,
            loggedAt: occurrence.scheduledAt,
            takenAt: occurrence.scheduledAt,
            doseAmount: occurrence.doseAmount,
            doseUnit: occurrence.doseUnit
        )
        context.insert(medication)
        context.insert(regimen)
        context.insert(existingRecord)
        for index in 0..<5_000 {
            context.insert(MedicationDoseRecord(
                profileID: UUID(),
                medicationID: UUID(),
                regimenID: UUID(),
                occurrenceKey: "unrelated-\(index)",
                scheduledAt: date(1),
                status: .taken,
                loggedAt: date(1),
                takenAt: date(1),
                doseAmount: 1,
                doseUnit: "tablet"
            ))
        }
        try context.save()
        var resolvedRecord: MedicationDoseRecord?

        measure(metrics: [XCTClockMetric()]) {
            resolvedRecord = MedicationService.recordDose(
                medication: medication,
                regimen: regimen,
                occurrence: occurrence,
                status: .taken,
                at: occurrence.scheduledAt,
                context: context
            )
        }

        XCTAssertEqual(resolvedRecord?.id, existingRecord.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MedicationDoseRecord>()), 5_001)
    }

    @MainActor
    func testBatchSupplyProjectionLargeHistoryPerformance() {
        let profileID = UUID()
        let now = date(10, hour: 12)
        let medications = (0..<40).map { index in
            Medication(
                profileID: profileID,
                name: "Test Medication \(index)",
                currentSupply: 120
            )
        }
        var records = [MedicationDoseRecord]()
        records.reserveCapacity(medications.count * 60 * 3)
        for medication in medications {
            for dayOffset in 0..<60 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else {
                    continue
                }
                for doseIndex in 0..<3 {
                    let takenAt = date.addingTimeInterval(-Double(doseIndex) * 60 * 60)
                    records.append(MedicationDoseRecord(
                        profileID: profileID,
                        medicationID: medication.id,
                        status: .taken,
                        loggedAt: takenAt,
                        takenAt: takenAt,
                        actualDoseAmount: 1,
                        doseAmount: 1,
                        doseUnit: "tablet"
                    ))
                }
            }
        }
        var projectionCount = 0

        measure(metrics: [XCTClockMetric()]) {
            projectionCount = MedicationService.supplyProjections(
                medications: medications,
                doseRecords: records,
                now: now,
                calendar: calendar
            ).count
        }

        XCTAssertEqual(projectionCount, medications.count)
    }

    @MainActor
    func testVersionedPlanReconstructionLargeHistoryPerformance() {
        let profileID = UUID()
        let medication = Medication(profileID: profileID, name: "Test Medication")
        let baseDate = date(1)
        var regimens = [MedicationRegimen]()
        var revisions = [MedicationPlanRevision]()
        var priorRegimenID: UUID?
        for index in 0..<180 {
            guard let effectiveDate = calendar.date(
                byAdding: .day,
                value: index,
                to: baseDate
            ) else { continue }
            let regimen = MedicationRegimen(
                profileID: profileID,
                medicationID: medication.id,
                scheduleKind: .daily,
                startDate: effectiveDate,
                doseAmount: Double((index % 3) + 1),
                doseUnit: "tablet",
                doseTimes: [MedicationDoseTime(hour: 8, minute: 0)],
                isActive: index == 179
            )
            regimens.append(regimen)
            revisions.append(MedicationPlanRevision(
                profileID: profileID,
                medicationID: medication.id,
                priorRegimenID: priorRegimenID,
                regimenID: regimen.id,
                changeKind: index == 0 ? .added : .updated,
                source: .clinician,
                effectiveFrom: effectiveDate,
                changedAt: effectiveDate.addingTimeInterval(12 * 60 * 60),
                afterSnapshot: MedicationPlanSnapshot(
                    medication: medication,
                    regimen: regimen,
                    phases: []
                )
            ))
            priorRegimenID = regimen.id
        }
        let rangeStart = calendar.date(byAdding: .day, value: 170, to: baseDate)!
        let rangeEnd = calendar.date(byAdding: .day, value: 180, to: baseDate)!
            .addingTimeInterval(-0.001)
        var occurrenceCount = 0

        measure(metrics: [XCTClockMetric()]) {
            occurrenceCount = MedicationScheduleEngine.versionedOccurrences(
                medicationID: medication.id,
                regimens: regimens,
                phases: [],
                revisions: revisions,
                from: rangeStart,
                through: rangeEnd,
                calendar: calendar
            ).count
        }

        XCTAssertEqual(occurrenceCount, 10)
    }

    @MainActor
    func testDoseOutcomeValidationRejectsIncompleteOrFutureDetailsAndInfersLateTiming() throws {
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
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()
        let occurrence = try XCTUnwrap(MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: [],
            from: date(1),
            through: date(1, hour: 23),
            calendar: calendar
        ).first)

        XCTAssertNil(MedicationService.recordDose(
            medication: medication,
            regimen: regimen,
            occurrence: occurrence,
            status: .missed,
            at: date(1, hour: 10),
            context: context
        ))
        XCTAssertNil(MedicationService.recordDose(
            medication: medication,
            regimen: regimen,
            occurrence: occurrence,
            status: .taken,
            at: date(1, hour: 10),
            takenAt: date(1, hour: 11),
            context: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MedicationDoseRecord>()).isEmpty)

        let lateDose = try XCTUnwrap(MedicationService.recordDose(
            medication: medication,
            regimen: regimen,
            occurrence: occurrence,
            status: .taken,
            at: date(1, hour: 9),
            takenAt: date(1, hour: 9),
            context: context
        ))
        XCTAssertEqual(lateDose.timing, .late)
    }

    @MainActor
    func testReconciliationCannotFinishWithUnreviewedMedicationAndAbandoningKeepsAuditUnlinked() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .parent
        )
        let firstMedication = Medication(profileID: profile.id, name: "Test Medication A")
        let secondMedication = Medication(profileID: profile.id, name: "Test Medication B")
        let firstRegimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: firstMedication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        let secondRegimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: secondMedication.id,
            scheduleKind: .daily,
            startDate: date(1),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(profile)
        context.insert(firstMedication)
        context.insert(secondMedication)
        context.insert(firstRegimen)
        context.insert(secondRegimen)
        try context.save()

        let reconciliationID = UUID()
        XCTAssertTrue(MedicationService.confirmCurrent(
            medication: firstMedication,
            regimens: [firstRegimen, secondRegimen],
            changeContext: MedicationPlanChangeContext(
                effectiveFrom: date(2),
                source: .clinician,
                reconciliationID: reconciliationID,
                confirmsCurrent: true
            ),
            context: context
        ))
        XCTAssertNil(MedicationService.completeReconciliation(
            id: reconciliationID,
            profileID: profile.id,
            source: .clinician,
            effectiveFrom: date(2),
            reviewedMedicationIDs: [firstMedication.id],
            context: context
        ))
        XCTAssertTrue(MedicationService.abandonReconciliation(
            id: reconciliationID,
            context: context
        ))
        let revision = try XCTUnwrap(context.fetch(FetchDescriptor<MedicationPlanRevision>()).first)
        XCTAssertNil(revision.reconciliationID)
        XCTAssertTrue(firstMedication.isConfirmedCurrent)
    }

    @MainActor
    func testHomeSurfacesLeadTimeRefillPlanningAndLinksToMedication() throws {
        let now = date(10, hour: 12)
        let householdID = UUID()
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            currentSupply: 5,
            refillLeadDays: 7,
            fillQuantity: 30,
            refillsRemaining: 1
        )
        let lowSupplyWithoutHistory = Medication(
            profileID: profile.id,
            name: "Low Supply Medication",
            currentSupply: 2,
            refillThreshold: 5,
            refillLeadDays: 7
        )
        let doses = (1...10).map { day in
            MedicationDoseRecord(
                profileID: profile.id,
                medicationID: medication.id,
                status: .taken,
                loggedAt: date(day, hour: 8),
                takenAt: date(day, hour: 8),
                actualDoseAmount: 1,
                doseAmount: 1,
                doseUnit: "tablet"
            )
        }
        let summary = TodayHomeSummaryService.summary(
            householdID: householdID,
            currentCaregiverName: "Test Caregiver",
            todoLists: [],
            todoItems: [],
            shoppingLists: [],
            shoppingItems: [],
            inventoryItems: [],
            mealPrepItems: [],
            mealPrepUsages: [],
            packingTrips: [],
            packingItems: [],
            itineraryItems: [],
            returnRequests: [],
            returnItems: [],
            returnPackages: [],
            reminders: [],
            profiles: [profile],
            medications: [medication, lowSupplyWithoutHistory],
            medicationDoseRecords: doses,
            now: now,
            calendar: calendar
        )
        let item = try XCTUnwrap(summary.allAttentionItems.first {
            $0.id == "attention-refill-plan-\(medication.id.uuidString)"
        })
        XCTAssertEqual(item.title, "Start refill for Test Medication")
        XCTAssertEqual(item.route, .medication(medication.id, profileID: profile.id))
        let fallbackItem = try XCTUnwrap(summary.allAttentionItems.first {
            $0.id == "attention-refill-plan-\(lowSupplyWithoutHistory.id.uuidString)"
        })
        XCTAssertTrue(fallbackItem.detail.contains("at or below the refill alert"))
    }

    @MainActor
    func testTripMedicationQueriesScopeOptionalProfileIDsWithoutRuntimePredicateFailures() throws {
        let container = try ModelContainer(
            for: PersistenceService.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let travelerProfileID = UUID()
        let otherProfileID = UUID()
        let travelerMedication = Medication(profileID: travelerProfileID, name: "Traveler Medication")
        let unscopedMedication = Medication(profileID: UUID(), name: "Unscoped Medication")
        unscopedMedication.profileID = nil
        context.insert(travelerMedication)
        context.insert(Medication(profileID: otherProfileID, name: "Other Medication"))
        context.insert(unscopedMedication)
        context.insert(MedicationDoseRecord(
            profileID: travelerProfileID,
            medicationID: travelerMedication.id,
            status: .taken,
            loggedAt: date(2),
            doseAmount: 1,
            doseUnit: "tablet"
        ))
        context.insert(MedicationDoseRecord(
            profileID: otherProfileID,
            medicationID: UUID(),
            status: .taken,
            loggedAt: date(2),
            doseAmount: 1,
            doseUnit: "tablet"
        ))
        try context.save()

        let travelerProfileIDs: Set<UUID?> = [travelerProfileID]
        let medicationDescriptor = FetchDescriptor<Medication>(predicate: #Predicate {
            !$0.isArchived && travelerProfileIDs.contains($0.profileID)
        })
        let lookbackStart = date(1)
        let doseDescriptor = FetchDescriptor<MedicationDoseRecord>(predicate: #Predicate {
            $0.loggedAt >= lookbackStart && travelerProfileIDs.contains($0.profileID)
        })

        XCTAssertEqual(try context.fetch(medicationDescriptor).map(\.id), [travelerMedication.id])
        XCTAssertEqual(try context.fetch(doseDescriptor).map(\.medicationID), [travelerMedication.id])

        let noTravelerProfileIDs = Set<UUID?>()
        let emptyTripDescriptor = FetchDescriptor<Medication>(predicate: #Predicate {
            !$0.isArchived && noTravelerProfileIDs.contains($0.profileID)
        })
        XCTAssertTrue(try context.fetch(emptyTripDescriptor).isEmpty)
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
