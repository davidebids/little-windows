import PDFKit
import SwiftData
import XCTest
@testable import LittleWindows

final class CareReportExportServiceTests: XCTestCase {
    @MainActor
    func testCSVQuotesCellsAndDefusesSpreadsheetFormulas() {
        let profile = BabyProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let event = BabyEvent(
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
    func testCSVIncludesAppointmentsAndMilestonesWhenEnabled() {
        let start = Date(timeIntervalSince1970: 1_800)
        let profile = BabyProfile(
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
            milestones: [milestone],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertTrue(csv.contains("\"Appointment\""))
        XCTAssertTrue(csv.contains("\"Wellness Check\""))
        XCTAssertTrue(csv.contains("\"Doctor: Dr. Example; Visit summary: Growing steadily\""))
        XCTAssertTrue(csv.contains("\"Milestone\""))
        XCTAssertTrue(csv.contains("\"Growth\""))
        XCTAssertTrue(csv.contains("\"Approximate date\""))
        XCTAssertTrue(csv.contains("\"First tooth\""))
    }

    @MainActor
    func testCSVRowsAreChronologicalAcrossRecordTypes() throws {
        let profile = BabyProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let appointmentDate = Date(timeIntervalSince1970: 1_000)
        let milestoneDate = Date(timeIntervalSince1970: 2_000)
        let eventDate = Date(timeIntervalSince1970: 3_000)
        let event = BabyEvent(profileID: profile.id, type: .feed, startDate: eventDate)
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
        let profile = BabyProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let event = BabyEvent(
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
    }

    @MainActor
    func testReportFiltersByProfileAndInclusiveDateRange() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let profile = BabyProfile(profileType: .child, name: "Sample Child", birthDate: start)
        let sibling = BabyProfile(profileType: .child, name: "Sibling", birthDate: start)
        context.insert(profile)
        context.insert(sibling)

        let included = BabyEvent(profileID: profile.id, type: .sleep, startDate: start.addingTimeInterval(3_600))
        let includedOnEndDay = BabyEvent(profileID: profile.id, type: .diaper, startDate: end.addingTimeInterval(3_600))
        let excludedProfile = BabyEvent(profileID: sibling.id, type: .feed, startDate: start.addingTimeInterval(3_600))
        let excludedDate = BabyEvent(profileID: profile.id, type: .feed, startDate: end.addingTimeInterval(90_000))
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
        let profile = BabyProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: selectedDay
        )
        let event = BabyEvent(
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
        let profile = BabyProfile(
            profileType: .child,
            name: "Sample Child",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let event = BabyEvent(
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
        let profile = BabyProfile(
            profileType: .child,
            name: "Sample Child With A Very Long Name That Should Not Break The Header",
            birthDate: Date(timeIntervalSince1970: 0)
        )
        let events = (0..<70).map { index in
            let event = BabyEvent(
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
    func testDefaultFilenameNormalizesReversedCustomDates() throws {
        let profile = BabyProfile(
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
