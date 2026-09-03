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
