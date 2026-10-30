import PDFKit
import SwiftData
import XCTest
@testable import LittleWindows

final class CareReportExportServiceTests: XCTestCase {
    @MainActor
    func testCSVQuotesCellsAndDefusesSpreadsheetFormulas() {
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let event = CareEvent(
            profileID: profile.id,
            type: .feed,
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 2_100),
            caregiverName: "=Caregiver"
        )
        event.feedKind = .solid
        event.foodDescription = "Banana, yogurt"
        event.notes = "  +Needs follow-up\nsecond line"

        let csv = CareReportExportService.csvString(for: CareReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 86_400),
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            events: [event],
            appointments: [],
            milestones: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertFalse(csv.contains("\"' =Caregiver\""))
        XCTAssertTrue(csv.contains("\"'=Caregiver\""))
        XCTAssertTrue(csv.contains("\"'  +Needs follow-up\nsecond line\""))
        XCTAssertTrue(csv.contains("\"Food: Banana, yogurt\""))
    }

    @MainActor
    func testDiaperRashAppearsOnlyWhenRecorded() {
        let withRash = CareEvent(type: .diaper)
        withRash.diaperKind = .wet
        withRash.diaperRash = true

        let withoutRash = CareEvent(type: .diaper)
        withoutRash.diaperKind = .wet

        XCTAssertTrue(CareReportExportService.detailsText(for: withRash).contains("Diaper rash"))
        XCTAssertFalse(CareReportExportService.detailsText(for: withoutRash).contains("Diaper rash"))
    }

    @MainActor
    func testChildStoolObservationsAppearInCareReport() {
        let event = CareEvent(type: .diaper)
        event.diaperKind = .dirty
        event.pooTexture = .hard
        event.pooDifficultOrPainful = true
        event.pooProlongedStraining = true
        event.pooVisibleBlood = true

        let details = CareReportExportService.detailsText(for: event)
        XCTAssertTrue(details.contains("Poo texture: Hard"))
        XCTAssertTrue(details.contains("Difficult or painful to pass"))
        XCTAssertTrue(details.contains("Prolonged straining"))
        XCTAssertTrue(details.contains("Visible blood"))
    }

    @MainActor
    func testSolidNutritionExportReportsIncompleteFoodCoverage() {
        let event = CareEvent(type: .feed)
        event.feedKind = .solid
        event.solidFoodDetails = [
            SolidFoodLogDetail(
                foodID: "banana",
                foodName: "Banana",
                amountEaten: 50,
                portionUnit: .gram,
                consumptionEstimate: .exact,
                nutritionSnapshot: SolidNutritionSnapshot(
                    sourceKind: .usdaFoodDataCentral,
                    sourceID: "test-banana",
                    sourceDescription: "Test banana",
                    sourceVersion: "test",
                    amountDescription: "50 g",
                    eatenAmount: 50,
                    portionUnit: .gram,
                    estimatedEatenGrams: 50,
                    nutrients: SolidNutritionValues(
                        energyKilocalories: 44.5,
                        proteinGrams: 0.55,
                        fatGrams: 0.15,
                        fiberGrams: 1.3,
                        ironMilligrams: 0.13,
                        zincMilligrams: 0.08,
                        calciumMilligrams: 2.5,
                        vitaminCMilligrams: 4.35
                    ),
                    isComplete: true,
                    capturedAt: Date()
                )
            ),
            SolidFoodLogDetail(foodID: "custom-test", foodName: "Test food")
        ]

        let details = CareReportExportService.detailsText(for: event)
        XCTAssertTrue(details.contains("coverage: 1 of 2 foods quantified; 1 with all eight nutrients"))
    }

    @MainActor
    func testCSVIncludesAppointmentsAndMilestonesWhenEnabled() {
        let start = Date(timeIntervalSince1970: 1_800)
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let appointment = DoctorAppointment(
            profileID: profile.id,
            title: "Well check",
            appointmentType: .wellnessCheck,
            startDate: start,
            doctorName: "Dr. Example",
            visitSummary: "Growing steadily",
            caregiverName: "Caregiver A"
        )
        let followUp = AppointmentFollowUp(
            appointmentID: appointment.id,
            householdID: UUID(),
            profileID: profile.id,
            title: "Schedule next visit",
            details: "Use the patient portal",
            dueDate: start.addingTimeInterval(3_600)
        )
        let milestone = MilestoneEntry(
            profileID: profile.id,
            title: "First tooth",
            date: start,
            approximateDate: true,
            category: .growth,
            notes: "Lower tooth",
            caregiverName: "Caregiver B"
        )

        let csv = CareReportExportService.csvString(for: CareReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 86_400),
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: true,
                includeMilestones: true
            ),
            events: [],
            appointments: [appointment],
            appointmentFollowUps: [followUp],
            milestones: [milestone],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertTrue(csv.contains("\"Appointment\""))
        XCTAssertTrue(csv.contains("\"Wellness Check\""))
        XCTAssertTrue(csv.contains("Doctor: Dr. Example; Visit summary: Growing steadily"))
        XCTAssertTrue(csv.contains("Follow-ups: Schedule next visit"))
        XCTAssertTrue(csv.contains("Use the patient portal"))
        let detailsWithoutNotes = CareReportExportService.appointmentDetailsText(
            for: appointment,
            followUps: [followUp],
            includeNotes: false
        )
        XCTAssertTrue(detailsWithoutNotes.contains("Schedule next visit"))
        XCTAssertFalse(detailsWithoutNotes.contains("Use the patient portal"))
        XCTAssertTrue(csv.contains("\"Milestone\""))
        XCTAssertTrue(csv.contains("\"Growth\""))
        XCTAssertTrue(csv.contains("\"Approximate date\""))
        XCTAssertTrue(csv.contains("\"First tooth\""))
    }

    @MainActor
    func testCSVRowsAreChronologicalAcrossRecordTypes() throws {
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let appointmentDate = Date(timeIntervalSince1970: 1_000)
        let milestoneDate = Date(timeIntervalSince1970: 2_000)
        let eventDate = Date(timeIntervalSince1970: 3_000)
        let event = CareEvent(profileID: profile.id, type: .feed, startDate: eventDate)
        event.feedKind = .bottle
        let appointment = DoctorAppointment(
            profileID: profile.id,
            title: "Well check",
            appointmentType: .wellnessCheck,
            startDate: appointmentDate
        )
        let milestone = MilestoneEntry(
            profileID: profile.id,
            title: "First tooth",
            date: milestoneDate,
            category: .growth
        )

        let csv = CareReportExportService.csvString(for: CareReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 86_400),
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: true,
                includeMilestones: true
            ),
            events: [event],
            appointments: [appointment],
            milestones: [milestone],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))

        let appointmentIndex = try XCTUnwrap(csv.range(of: "\"Appointment\"")?.lowerBound)
        let milestoneIndex = try XCTUnwrap(csv.range(of: "\"Milestone\"")?.lowerBound)
        let feedIndex = try XCTUnwrap(csv.range(of: "\"Feed\"")?.lowerBound)
        XCTAssertLessThan(appointmentIndex, milestoneIndex)
        XCTAssertLessThan(milestoneIndex, feedIndex)
    }

    @MainActor
    func testCSVRespectsNotesAndCaregiverPrivacyToggles() {
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let event = CareEvent(
            profileID: profile.id,
            type: .medicine,
            startDate: Date(timeIntervalSince1970: 1_800),
            caregiverName: "Caregiver A",
            notes: "Private note"
        )
        event.medicineName = "Vitamin"

        let csv = CareReportExportService.csvString(for: CareReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 86_400),
                includeNotes: false,
                includeCaregiverNames: false,
                includeAppointments: false,
                includeMilestones: false
            ),
            events: [event],
            appointments: [],
            milestones: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertFalse(csv.contains("Caregiver A"))
        XCTAssertFalse(csv.contains("Private note"))
        XCTAssertTrue(csv.contains("Medicine: Vitamin"))
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(csvColumnCount(lines[0]), csvColumnCount(lines[1]))
    }

    @MainActor
    func testReportIncludesCurrentMedicationPlan() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(
            profileID: profile.id,
            name: "Test Medication",
            form: .tablet,
            strength: 10,
            strengthUnit: "mg",
            route: .oral,
            instructions: "Take with water"
        )
        let regimen = MedicationRegimen(
            profileID: profile.id,
            medicationID: medication.id,
            scheduleKind: .daily,
            startDate: Date(),
            doseAmount: 1,
            doseUnit: "tablet",
            doseTimes: [MedicationDoseTime(hour: 8, minute: 0)]
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()

        let report = try CareReportExportService.makeReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(),
                endDate: Date(),
                includeNotes: false,
                includeCaregiverNames: false,
                includeAppointments: false,
                includeMilestones: false
            ),
            context: context
        )
        let csv = CareReportExportService.csvString(for: report)

        XCTAssertEqual(report.medications.map(\.name), ["Test Medication"])
        XCTAssertEqual(report.medicationRegimens.map(\.id), [regimen.id])
        XCTAssertTrue(csv.contains("Medication Plan"))
        XCTAssertTrue(csv.contains("Strength: 10 mg"))
        XCTAssertTrue(csv.contains("Schedule: Every day"))
        XCTAssertTrue(csv.contains("Instructions: Take with water"))
    }

    @MainActor
    func testReportFiltersByProfileAndInclusiveDateRange() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let profile = CareProfile(profileType: .child, name: "Sample Child", birthDate: start)
        let sibling = CareProfile(profileType: .child, name: "Sibling", birthDate: start)
        context.insert(profile)
        context.insert(sibling)

        let included = CareEvent(profileID: profile.id, type: .sleep, startDate: start.addingTimeInterval(3_600))
        let includedOnEndDay = CareEvent(profileID: profile.id, type: .diaper, startDate: end.addingTimeInterval(3_600))
        let excludedProfile = CareEvent(profileID: sibling.id, type: .feed, startDate: start.addingTimeInterval(3_600))
        let excludedDate = CareEvent(profileID: profile.id, type: .feed, startDate: end.addingTimeInterval(90_000))
        for event in [included, includedOnEndDay, excludedProfile, excludedDate] {
            context.insert(event)
        }
        try context.save()

        let report = try CareReportExportService.makeReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: start,
                endDate: end,
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            context: context,
            calendar: calendar,
            now: start
        )

        XCTAssertEqual(report.events.map(\.id), [included.id, includedOnEndDay.id])
    }

    @MainActor
    func testReportUsesEachEventsRecordedLocalDayAndExportsZones() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let selectedDay = try XCTUnwrap(
            pacificCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15))
        )
        let nextDay = try XCTUnwrap(
            pacificCalendar.date(byAdding: .day, value: 1, to: selectedDay)
        )
        let start = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-01-15T06:00:00Z")
        )
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: selectedDay
        )
        let event = CareEvent(
            profileID: profile.id,
            type: .diaper,
            startDate: start,
            startTimeZoneIdentifier: "America/New_York"
        )
        context.insert(profile)
        context.insert(event)
        try context.save()

        let report = try CareReportExportService.makeReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: selectedDay,
                endDate: selectedDay,
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            context: context,
            calendar: pacificCalendar,
            now: selectedDay
        )

        XCTAssertEqual(report.events.map(\.id), [event.id])
        XCTAssertFalse(pacificCalendar.isDate(start, inSameDayAs: selectedDay))
        XCTAssertLessThan(selectedDay, nextDay)
        let csv = CareReportExportService.csvString(for: report)
        XCTAssertTrue(csv.contains("Start Time Zone"))
        XCTAssertTrue(csv.contains("America/New_York"))
    }

    @MainActor
    func testPDFGenerationProducesNonEmptyPDFData() throws {
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let event = CareEvent(
            profileID: profile.id,
            type: .temperature,
            startDate: Date(timeIntervalSince1970: 1_800),
            notes: "Checked at home"
        )
        event.temperatureCelsius = 37
        event.temperatureMethod = .forehead

        let data = CareReportExportService.pdfData(for: CareReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 86_400),
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            events: [event],
            appointments: [],
            milestones: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("At a Glance"))
        XCTAssertTrue(text.contains("Covers"))
        XCTAssertTrue(text.contains("Most logged categories: Temperature (1)."))
        XCTAssertTrue(text.contains("Highest logged temperature"))
        XCTAssertTrue(text.contains("Latest care log"))
    }

    @MainActor
    func testPDFPaginatesWithContinuationFooterAndNoDuplicateAppendix() throws {
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child With A Very Long Name That Should Not Break The Header",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let events = (0..<70).map { index in
            let event = CareEvent(
                profileID: profile.id,
                type: .temperature,
                startDate: Date(timeIntervalSince1970: TimeInterval(index * 1_800)),
                notes: "Temperature note \(index) with enough text to exercise row wrapping and pagination."
            )
            event.temperatureCelsius = 37 + Double(index % 3) / 10
            event.temperatureMethod = .forehead
            return event
        }

        let data = CareReportExportService.pdfData(for: CareReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 86_400),
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            events: events,
            appointments: [],
            milestones: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(text.contains("Care Visit Report"))
        XCTAssertTrue(text.contains("Little Windows Care Report"))
        XCTAssertTrue(text.contains("Page 1"))
        XCTAssertTrue(text.contains("Page 2"))
        XCTAssertFalse(text.contains("Event Appendix"))
    }

    @MainActor
    func testReportExportsRichMedicationOutcomesWithoutDuplicatingTimelineMirror() throws {
        let container = try makeInMemoryContainer()
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
            scheduleKind: .asNeeded,
            startDate: Date(timeIntervalSince1970: 0),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(profile)
        context.insert(medication)
        context.insert(regimen)
        try context.save()

        let takenAt = Date(timeIntervalSince1970: 3_600)
        _ = try XCTUnwrap(MedicationService.recordDose(
            medication: medication,
            regimen: regimen,
            status: .taken,
            at: takenAt,
            takenAt: takenAt,
            actualDoseAmount: 0.5,
            timing: .late,
            notes: "Actual dose note",
            context: context
        ))
        let missed = MedicationDoseRecord(
            profileID: profile.id,
            medicationID: medication.id,
            regimenID: regimen.id,
            scheduledAt: Date(timeIntervalSince1970: 7_200),
            status: .missed,
            loggedAt: Date(timeIntervalSince1970: 7_500),
            reason: .away,
            doseAmount: 1,
            doseUnit: "tablet",
            caregiverName: "Test Caregiver",
            notes: "Missed dose note"
        )
        context.insert(missed)
        try context.save()

        let report = try CareReportExportService.makeReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 0),
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            context: context,
            calendar: Calendar(identifier: .gregorian),
            now: Date(timeIntervalSince1970: 8_000)
        )
        XCTAssertTrue(report.events.isEmpty)
        XCTAssertEqual(report.medicationDoseRecords.count, 2)

        let csv = CareReportExportService.csvString(for: report)
        XCTAssertTrue(csv.contains("Taken late, different amount"))
        XCTAssertTrue(csv.contains("Missed"))
        XCTAssertTrue(csv.contains("Reason: Away from home"))
        XCTAssertTrue(csv.contains("Actual dose note"))
        XCTAssertTrue(csv.contains("Test Caregiver"))
        XCTAssertEqual(csv.components(separatedBy: "\"Medication Dose\"").count - 1, 2)
    }

    @MainActor
    func testMedicationReportRangeUsesActualOrScheduledDoseTimeForBackfilledRecords() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let profile = CareProfile(
            profileType: .adult,
            name: "Test Adult",
            adultRelationship: .myself
        )
        let medication = Medication(profileID: profile.id, name: "Test Medication")
        context.insert(profile)
        context.insert(medication)
        let selectedDay = Date(timeIntervalSince1970: 10 * 86_400)
        let nextDay = selectedDay.addingTimeInterval(86_400)
        let backfilledTaken = MedicationDoseRecord(
            profileID: profile.id,
            medicationID: medication.id,
            scheduledAt: selectedDay.addingTimeInterval(8 * 60 * 60),
            status: .taken,
            loggedAt: nextDay.addingTimeInterval(10 * 60 * 60),
            takenAt: selectedDay.addingTimeInterval(9 * 60 * 60),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        let backfilledMissed = MedicationDoseRecord(
            profileID: profile.id,
            medicationID: medication.id,
            scheduledAt: selectedDay.addingTimeInterval(12 * 60 * 60),
            status: .missed,
            loggedAt: nextDay.addingTimeInterval(11 * 60 * 60),
            reason: .away,
            doseAmount: 1,
            doseUnit: "tablet"
        )
        let takenOnNextDay = MedicationDoseRecord(
            profileID: profile.id,
            medicationID: medication.id,
            scheduledAt: selectedDay.addingTimeInterval(18 * 60 * 60),
            status: .taken,
            loggedAt: nextDay.addingTimeInterval(20 * 60 * 60),
            takenAt: nextDay.addingTimeInterval(19 * 60 * 60),
            doseAmount: 1,
            doseUnit: "tablet"
        )
        context.insert(backfilledTaken)
        context.insert(backfilledMissed)
        context.insert(takenOnNextDay)
        try context.save()
        var reportCalendar = Calendar(identifier: .gregorian)
        reportCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let report = try CareReportExportService.makeReport(
            profile: profile,
            options: CareReportExportOptions(
                startDate: selectedDay,
                endDate: selectedDay,
                includeNotes: true,
                includeCaregiverNames: true,
                includeAppointments: false,
                includeMilestones: false
            ),
            context: context,
            calendar: reportCalendar,
            now: nextDay
        )

        XCTAssertEqual(
            Set(report.medicationDoseRecords.map(\.id)),
            Set([backfilledTaken.id, backfilledMissed.id])
        )
    }

    @MainActor
    func testDefaultFilenameNormalizesReversedCustomDates() throws {
        let profile = CareProfile(
            profileType: .child,
            name: "Sample Child!",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let calendar = Calendar(identifier: .gregorian)
        let later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
        let earlier = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6)))

        let filename = CareReportExportService.defaultFilename(
            profile: profile,
            format: .pdf,
            startDate: later,
            endDate: earlier
        )

        XCTAssertEqual(filename, "Little-Windows-Sample-Child-2026-06-06-to-2026-07-05.pdf")
    }

    @MainActor
    func testFoodReactionReportPreservesFoodLevelDetailsAndMealContext() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let date = Date()
        let reaction = SolidFoodLogDetail(
            foodID: "yogurt", foodName: "Yogurt", allergenIDs: ["milk"],
            notes: "First serving", suspectedReaction: true, symptoms: [.hivesOrRash],
            severity: .mild, onsetMinutes: 0, durationMinutes: 25,
            responseNotes: "Recorded caregiver response", followUp: .discussWithClinician
        )
        let event = reactionMeal(profile: profile, date: date, details: [
            reaction, SolidFoodLogDetail(foodID: "banana", foodName: "Banana")
        ])
        event.notes = "Meal context"
        event.caregiverName = "Sample Caregiver"
        context.insert(profile)
        context.insert(event)
        // Derived index duplicates must never produce duplicate report rows.
        context.insert(SolidFoodEventItem(
            eventID: event.id, profileID: profile.id, foodID: "yogurt",
            foodNameSnapshot: "Yogurt", suspectedReaction: true
        ))
        try context.save()
        let report = try FoodReactionReportService.makeReport(
            profile: profile, options: reactionOptions(date), context: context
        )
        let entry = try XCTUnwrap(report.entries.first)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.mealCount, 1)
        XCTAssertEqual(report.reactionMealCount, 1)
        XCTAssertEqual(entry.food, "Yogurt")
        XCTAssertEqual(entry.mealFoods, "Yogurt, Banana")
        XCTAssertEqual(entry.allergens, "Milk")
        XCTAssertEqual(entry.symptoms, "Hives or rash")
        XCTAssertEqual(entry.severity, "Mild")
        XCTAssertEqual(entry.onset, "0 min")
        XCTAssertEqual(entry.duration, "25 min")
        XCTAssertEqual(entry.response, "Recorded caregiver response")
        XCTAssertEqual(entry.followUp, "Discuss with clinician")
        XCTAssertEqual(entry.foodNotes, "First serving")
        XCTAssertEqual(entry.mealNotes, "Meal context")
        XCTAssertEqual(entry.caregiver, "Sample Caregiver")
        let data = FoodReactionReportService.pdfData(for: report)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1, "A typical observation with short notes should fit on one page.")
        XCTAssertTrue(document.string?.contains("First serving") == true)
        XCTAssertTrue(document.string?.contains("Meal context") == true)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Food reaction report sample"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testFoodReactionReportScopesByProfileSavedSolidsAndRecordedLocalDay() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let sibling = CareProfile(profileType: .child, name: "Sibling")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        let details = [SolidFoodLogDetail(foodID: "egg", foodName: "Egg", suspectedReaction: true)]
        let included = reactionMeal(profile: profile, date: day.addingTimeInterval(-3600), details: details)
        included.startTimeZoneIdentifier = "Pacific/Kiritimati"
        let excludedLocalDay = reactionMeal(profile: profile, date: day.addingTimeInterval(3600), details: details)
        excludedLocalDay.startTimeZoneIdentifier = "America/Los_Angeles"
        let otherProfile = reactionMeal(profile: sibling, date: day, details: details)
        let bottle = reactionMeal(profile: profile, date: day, details: details)
        bottle.feedKind = .bottle
        let draft = reactionMeal(profile: profile, date: day, details: details)
        draft.endDate = nil
        let outside = reactionMeal(profile: profile, date: day.addingTimeInterval(3 * 86_400), details: details)
        [included, excludedLocalDay, otherProfile, bottle, draft, outside].forEach(context.insert)
        try context.save()
        let report = try FoodReactionReportService.makeReport(
            profile: profile, options: reactionOptions(day), context: context, calendar: calendar
        )
        XCTAssertEqual(report.entries.map(\.eventID), [included.id])
        XCTAssertEqual(report.entries.first?.timeZoneIdentifier, "Pacific/Kiritimati")
        XCTAssertEqual(report.mealCount, 1)
        let csv = String(decoding: FoodReactionReportService.csvData(for: report), as: UTF8.self)
        XCTAssertTrue(csv.contains("Pacific/Kiritimati"))
        XCTAssertTrue(csv.contains(DateFormatting.dayString(from: included.startDate, timeZone: included.startTimeZone)))
        XCTAssertThrowsError(try FoodReactionReportService.makeReport(
            profile: CareProfile(profileType: .dog, name: "Sample Dog"),
            options: reactionOptions(day), context: context
        ))
    }

    @MainActor
    func testFoodReactionLegacyMealFlagDoesNotInventAnIngredientOrAllergen() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let date = Date()
        let event = reactionMeal(profile: profile, date: date, details: [])
        event.foodDescription = "Egg, banana"
        event.solidSensitivityObserved = true
        context.insert(event)
        try context.save()
        let report = try FoodReactionReportService.makeReport(
            profile: profile, options: reactionOptions(date), context: context
        )
        let entry = try XCTUnwrap(report.entries.first)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(entry.food, "Meal-level observation")
        XCTAssertEqual(entry.mealFoods, "Egg, banana")
        XCTAssertEqual(entry.allergens, "Not recorded")
        XCTAssertEqual(entry.symptoms, "Not recorded")
        XCTAssertTrue(entry.observation.contains("individual food not identified"))
    }

    @MainActor
    func testFoodReactionPrivacyControlsRemoveFreeTextFromPDFAndCSV() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let date = Date()
        let event = reactionMeal(profile: profile, date: date, details: [
            SolidFoodLogDetail(
                foodID: "egg", foodName: "Egg", notes: "PRIVATE-FOOD-NOTE",
                suspectedReaction: true, symptoms: [.vomiting], severity: .moderate,
                onsetMinutes: 15, responseNotes: "PRIVATE-RESPONSE", followUp: .monitoring
            )
        ])
        event.notes = "PRIVATE-MEAL-NOTE"
        event.caregiverName = "PRIVATE-CAREGIVER"
        context.insert(event)
        try context.save()
        var options = reactionOptions(date)
        options.includeNotes = false
        options.includeCaregiverNames = false
        let report = try FoodReactionReportService.makeReport(profile: profile, options: options, context: context)
        let csv = String(decoding: FoodReactionReportService.csvData(for: report), as: UTF8.self)
        let pdf = try XCTUnwrap(PDFDocument(data: FoodReactionReportService.pdfData(for: report)))
        let pdfText = try XCTUnwrap(pdf.string)
        for text in [csv, pdfText] {
            XCTAssertFalse(text.contains("PRIVATE-"))
            XCTAssertTrue(text.contains("Vomiting"))
            XCTAssertTrue(text.contains("Moderate"))
            XCTAssertTrue(text.contains("15 min"))
            XCTAssertTrue(text.contains("Monitoring"))
        }
        XCTAssertFalse(csv.components(separatedBy: "\n")[0].contains("Caregiver"))
        XCTAssertFalse(csv.components(separatedBy: "\n")[0].contains("Response Taken"))
    }

    @MainActor
    func testFoodReactionOptionalContextAndSymptomOnlyRecords() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let date = Date()
        let event = reactionMeal(profile: profile, date: date, details: [
            SolidFoodLogDetail(foodID: "egg", foodName: "Egg", symptoms: [.hivesOrRash]),
            SolidFoodLogDetail(foodID: "milk", foodName: "Yogurt", suspectedReaction: true),
            SolidFoodLogDetail(foodID: "banana", foodName: "Banana")
        ])
        event.solidSensitivityObserved = true
        context.insert(event)
        try context.save()
        var options = reactionOptions(date)
        let focused = try FoodReactionReportService.makeReport(profile: profile, options: options, context: context)
        XCTAssertEqual(focused.entries.count, 2)
        XCTAssertEqual(focused.reactionMealCount, 1)
        options.includeMealsWithoutReactions = true
        let contextual = try FoodReactionReportService.makeReport(profile: profile, options: options, context: context)
        XCTAssertEqual(contextual.entries.count, 3)
        XCTAssertEqual(contextual.reactionMealCount, 1)
        XCTAssertEqual(contextual.entries.last?.observation, "No reaction details recorded")
        XCTAssertFalse(contextual.entries.last?.hasReaction ?? true)
    }

    @MainActor
    func testFoodReactionCSVQuotesAndDefusesUserEnteredValues() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let date = Date()
        let event = reactionMeal(profile: profile, date: date, details: [
            SolidFoodLogDetail(foodID: "custom", foodName: "=Food", suspectedReaction: true,
                               responseNotes: "  +Response, with \"quotes\"\nand a new line")
        ])
        context.insert(event)
        try context.save()
        let report = try FoodReactionReportService.makeReport(
            profile: profile, options: reactionOptions(date), context: context
        )
        let csv = String(decoding: FoodReactionReportService.csvData(for: report), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"'=Food\""))
        XCTAssertTrue(csv.contains("\"'  +Response, with \"\"quotes\"\"\nand a new line\""))
        XCTAssertTrue(csv.contains(FoodReactionReport.notice))
    }

    @MainActor
    func testFoodReactionPDFPreservesLongNotesAcrossPages() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let date = Date()
        let note = String(repeating: "Caregiver recorded context for this food. ", count: 350) + "FINAL-FOOD-NOTE"
        let event = reactionMeal(profile: profile, date: date, details: [
            SolidFoodLogDetail(foodID: "egg", foodName: "Egg", allergenIDs: ["egg"],
                               notes: note, suspectedReaction: true, symptoms: [.hivesOrRash],
                               severity: .mild, onsetMinutes: 10, durationMinutes: 30,
                               responseNotes: "Recorded response", followUp: .resolved)
        ])
        event.notes = "FINAL-MEAL-NOTE"
        context.insert(event)
        try context.save()
        let report = try FoodReactionReportService.makeReport(
            profile: profile, options: reactionOptions(date), context: context
        )
        let data = FoodReactionReportService.pdfData(for: report)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 2)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("FINAL-FOOD-NOTE"))
        XCTAssertTrue(text.contains("FINAL-MEAL-NOTE"))
        for index in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: index))
            XCTAssertTrue(page.string?.contains("Page \(index + 1)") == true)
            for line in page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? [] {
                let rect = line.bounds(for: page)
                XCTAssertGreaterThanOrEqual(rect.minX, 40)
                XCTAssertGreaterThanOrEqual(rect.minY, 32)
                XCTAssertLessThanOrEqual(rect.maxX, 572)
                XCTAssertLessThanOrEqual(rect.maxY, 755)
            }
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Food reaction report long notes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testFoodReactionEmptyReportAndReversedRangeHaveHonestOutput() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let profile = CareProfile(profileType: .child, name: "Sample Child")
        let now = Date()
        let options = FoodReactionReportOptions(startDate: now, endDate: now.addingTimeInterval(-7 * 86_400))
        let report = try FoodReactionReportService.makeReport(profile: profile, options: options, context: context)
        XCTAssertLessThan(report.options.startDate, report.options.endDate)
        XCTAssertEqual(report.mealCount, 0)
        let document = try XCTUnwrap(PDFDocument(data: FoodReactionReportService.pdfData(for: report)))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("No possible reaction observations were recorded") == true)
        XCTAssertTrue(document.string?.contains("does not confirm an allergy") == true)
        XCTAssertTrue(FoodReactionReportService.defaultFilename(for: report, format: .pdf).contains("Food-Reactions"))
    }

    @MainActor
    private func reactionMeal(profile: CareProfile, date: Date, details: [SolidFoodLogDetail]) -> CareEvent {
        let event = CareEvent(profileID: profile.id, type: .feed, startDate: date, endDate: date.addingTimeInterval(300))
        event.feedKind = .solid
        event.solidFoodDetails = details
        return event
    }

    private func reactionOptions(_ date: Date) -> FoodReactionReportOptions {
        FoodReactionReportOptions(startDate: date, endDate: date)
    }

    private func csvColumnCount(_ row: Substring) -> Int {
        var count = 1
        var isInsideQuotedCell = false
        var index = row.startIndex
        while index < row.endIndex {
            let character = row[index]
            if character == "\"" {
                let next = row.index(after: index)
                if isInsideQuotedCell, next < row.endIndex, row[next] == "\"" {
                    index = row.index(after: next)
                    continue
                }
                isInsideQuotedCell.toggle()
            } else if character == ",", !isInsideQuotedCell {
                count += 1
            }
            index = row.index(after: index)
        }
        return count
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = PersistenceService.schema
        let configuration = ModelConfiguration(
            "CareReportExportServiceTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
