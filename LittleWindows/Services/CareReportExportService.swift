import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CareReportFormat: String, CaseIterable, Identifiable {
    case csv
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: "CSV"
        case .pdf: "PDF"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .pdf: .pdf
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .pdf: "pdf"
        }
    }
}

enum CareReportDateRangePreset: String, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        case .custom: "Custom"
        }
    }
}

struct CareReportExportOptions {
    var startDate: Date
    var endDate: Date
    var includeNotes: Bool
    var includeCaregiverNames: Bool
    var includeAppointments: Bool
    var includeMilestones: Bool
}

struct CareReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .pdf] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText, .pdf] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CareReport {
    var profile: CareProfile
    var options: CareReportExportOptions
    var events: [CareEvent]
    var appointments: [DoctorAppointment]
    var appointmentFollowUps: [AppointmentFollowUp] = []
    var milestones: [MilestoneEntry]
    var medications: [Medication] = []
    var medicationRegimens: [MedicationRegimen] = []
    var generatedAt: Date
}

@MainActor
enum CareReportExportService {
    static func export(
        profile: CareProfile,
        format: CareReportFormat,
        options: CareReportExportOptions,
        context: ModelContext
    ) throws -> Data {
        let report = try makeReport(profile: profile, options: options, context: context)
        switch format {
        case .csv:
            return csvData(for: report)
        case .pdf:
            return pdfData(for: report)
        }
    }

    static func makeReport(
        profile: CareProfile,
        options: CareReportExportOptions,
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = Date()
    ) throws -> CareReport {
        let range = normalizedRange(startDate: options.startDate, endDate: options.endDate, calendar: calendar)
        let profileID = profile.id
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        // Cover the full UTC-12...UTC+14 spread before filtering by each
        // event's recorded local calendar day.
        let eventFetchLowerBound = lowerBound.addingTimeInterval(-30 * 60 * 60)
        let eventFetchUpperBound = upperBound.addingTimeInterval(30 * 60 * 60)
        let events = try context.fetch(FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID &&
                    $0.startDate >= eventFetchLowerBound &&
                    $0.startDate < eventFetchUpperBound
            },
            sortBy: [SortDescriptor(\.startDate)]
        )).filter {
            let localDay = $0.localStartDay(calendar: calendar)
            return localDay >= lowerBound && localDay < upperBound
        }
        let appointments = options.includeAppointments
            ? try context.fetch(FetchDescriptor<DoctorAppointment>(
                predicate: #Predicate {
                    $0.profileID == profileID &&
                        $0.startDate >= lowerBound &&
                        $0.startDate < upperBound
                },
                sortBy: [SortDescriptor(\.startDate)]
            ))
            : []
        let appointmentFollowUps: [AppointmentFollowUp]
        if options.includeAppointments {
            let appointmentIDs = Set(appointments.map(\.id))
            appointmentFollowUps = try context.fetch(FetchDescriptor<AppointmentFollowUp>(
                predicate: #Predicate { $0.profileID == profileID },
                sortBy: [SortDescriptor(\.createdAt)]
            )).filter { appointmentIDs.contains($0.appointmentID) }
        } else {
            appointmentFollowUps = []
        }
        let milestones = options.includeMilestones
            ? try context.fetch(FetchDescriptor<MilestoneEntry>(
                predicate: #Predicate {
                    $0.profileID == profileID &&
                        $0.date >= lowerBound &&
                        $0.date < upperBound
                },
                sortBy: [SortDescriptor(\.date)]
            ))
            : []
        let medications = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.profileID == profileID && !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        ))
        let medicationRegimens = try context.fetch(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { $0.profileID == profileID && $0.isActive },
            sortBy: [SortDescriptor(\.createdAt)]
        ))

        var normalizedOptions = options
        normalizedOptions.startDate = range.lowerBound
        normalizedOptions.endDate = calendar.date(byAdding: .second, value: -1, to: range.upperBound) ?? options.endDate
        return CareReport(
            profile: profile,
            options: normalizedOptions,
            events: events,
            appointments: appointments,
            appointmentFollowUps: appointmentFollowUps,
            milestones: milestones,
            medications: medications,
            medicationRegimens: medicationRegimens,
            generatedAt: now
        )
    }

    static func csvData(for report: CareReport) -> Data {
        Data(csvString(for: report).utf8)
    }

    static func csvString(for report: CareReport) -> String {
        let header = [
            "Profile",
            "Profile Type",
            "Date",
            "Start Time",
            "End Time",
            "Duration",
            "Event Type",
            "Subtype",
            "Amount / Value",
            "Details",
            "Caregiver",
            "Notes",
            "Start Time Zone",
            "End Time Zone"
        ]
        var rows: [(date: Date, columns: [String])] = []
        rows += report.events.map { event in
            (event.startDate, [
                report.profile.name,
                report.profile.profileType.displayName,
                DateFormatting.dayString(from: event.startDate, timeZone: event.startTimeZone),
                DateFormatting.timeString(from: event.startDate, timeZone: event.startTimeZone),
                event.endDate.map { DateFormatting.timeString(from: $0, timeZone: event.endTimeZone) } ?? "",
                durationText(for: event),
                event.type.displayName,
                subtypeText(for: event),
                amountText(for: event),
                detailsText(for: event),
                report.options.includeCaregiverNames ? (event.caregiverName ?? "") : "",
                report.options.includeNotes ? (event.notes ?? "") : "",
                event.startTimeZone.identifier,
                event.endDate == nil ? "" : event.endTimeZone.identifier
            ])
        }
        if report.options.includeAppointments {
            rows += report.appointments.map { appointment in
                (appointment.startDate, [
                    report.profile.name,
                    report.profile.profileType.displayName,
                    dateFormatter.string(from: appointment.startDate),
                    timeFormatter.string(from: appointment.startDate),
                    appointment.endDate.map { timeFormatter.string(from: $0) } ?? "",
                    appointment.endDate.map { durationText(seconds: max(0, $0.timeIntervalSince(appointment.startDate))) } ?? "",
                    "Appointment",
                    appointment.appointmentType.displayName,
                    "",
                    appointmentDetailsText(
                        for: appointment,
                        followUps: report.appointmentFollowUps.filter { $0.appointmentID == appointment.id },
                        includeNotes: report.options.includeNotes
                    ),
                    report.options.includeCaregiverNames ? (appointment.caregiverName ?? "") : "",
                    report.options.includeNotes ? (appointment.notes ?? "") : "",
                    "",
                    ""
                ])
            }
        }
        if report.options.includeMilestones {
            rows += report.milestones.map { milestone in
                (milestone.date, [
                    report.profile.name,
                    report.profile.profileType.displayName,
                    dateFormatter.string(from: milestone.date),
                    "",
                    "",
                    "",
                    "Milestone",
                    milestone.category.displayName,
                    milestone.approximateDate ? "Approximate date" : "",
                    milestone.title,
                    report.options.includeCaregiverNames ? (milestone.caregiverName ?? "") : "",
                    report.options.includeNotes ? (milestone.notes ?? "") : "",
                    "",
                    ""
                ])
            }
        }
        rows += report.medications.map { medication in
            let regimen = report.medicationRegimens.first { $0.medicationID == medication.id }
            return (report.generatedAt, [
                report.profile.name,
                report.profile.profileType.displayName,
                dateFormatter.string(from: report.generatedAt),
                "",
                "",
                "",
                "Medication Plan",
                medication.form.displayName,
                medication.strengthDescription ?? "",
                medicationPlanDetails(medication: medication, regimen: regimen),
                "",
                "",
                "",
                ""
            ])
        }
        let sortedRows = rows.sorted { first, second in
            if first.date == second.date {
                return first.columns[6] < second.columns[6]
            }
            return first.date < second.date
        }.map(\.columns)
        return ([header] + sortedRows).map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func pdfData(for report: CareReport) -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            var cursor = PDFCursor(
                pageBounds: pageBounds,
                continuationTitle: "Little Windows Care Report",
                continuationSubtitle: pdfSingleLineText(
                    "\(report.profile.name) - \(dateFormatter.string(from: report.options.startDate)) to \(dateFormatter.string(from: report.options.endDate))",
                    limit: 72
                )
            )
            context.beginPage()

            drawBrandHeader(for: report, cursor: &cursor)

            drawSection("At a Glance", cursor: &cursor, context: context)
            drawOverview(summaryHighlights(for: report), cursor: &cursor, context: context)

            drawSection("Summary", cursor: &cursor, context: context)
            drawKeyValues(summaryRows(for: report), cursor: &cursor, context: context)

            if !report.medications.isEmpty {
                drawSection("Current Medications", cursor: &cursor, context: context)
                for medication in report.medications {
                    let regimen = report.medicationRegimens.first { $0.medicationID == medication.id }
                    drawCompactRecord(
                        title: medication.name,
                        details: medicationPlanDetails(medication: medication, regimen: regimen),
                        cursor: &cursor,
                        context: context
                    )
                }
            }

            if report.events.isEmpty {
                drawSection("Care Logs", cursor: &cursor, context: context)
                drawEmptyState("No care events were logged in this date range.", cursor: &cursor, context: context)
            }

            let grouped = Dictionary(grouping: report.events, by: \.type)
            for section in sectionOrder(for: report.profile.profileType) {
                let events = grouped[section.eventType] ?? []
                guard !events.isEmpty else { continue }
                drawSection(section.title, cursor: &cursor, context: context)
                for event in events {
                    drawEvent(event, options: report.options, cursor: &cursor, context: context)
                }
            }

            if report.options.includeAppointments, !report.appointments.isEmpty {
                drawSection("Appointments", cursor: &cursor, context: context)
                for appointment in report.appointments {
                    drawCompactRecord(
                        title: "\(dateTimeFormatter.string(from: appointment.startDate)): \(appointment.title)",
                        details: appointmentDetailsText(
                            for: appointment,
                            followUps: report.appointmentFollowUps.filter { $0.appointmentID == appointment.id },
                            includeNotes: report.options.includeNotes
                        ),
                        cursor: &cursor,
                        context: context
                    )
                }
            }

            if report.options.includeMilestones, !report.milestones.isEmpty {
                drawSection("Milestones", cursor: &cursor, context: context)
                for milestone in report.milestones {
                    drawCompactRecord(
                        title: "\(dateFormatter.string(from: milestone.date)): \(milestone.title)",
                        details: report.options.includeNotes ? (milestone.notes ?? "") : "",
                        cursor: &cursor,
                        context: context
                    )
                }
            }

            drawPageFooter(cursor)
        }
    }

    static func defaultRange(for preset: CareReportDateRangePreset, now: Date = Date(), calendar: Calendar = .current) -> (Date, Date) {
        let today = calendar.startOfDay(for: now)
        switch preset {
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: today) ?? today, today)
        case .custom:
            return (today, today)
        }
    }

    static func defaultFilename(profile: CareProfile, format: CareReportFormat, startDate: Date, endDate: Date) -> String {
        let normalized = normalizedDisplayRange(startDate: startDate, endDate: endDate)
        let profileName = profile.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let safeName = profileName.isEmpty ? "Profile" : profileName
        return "Little-Windows-\(safeName)-\(filenameDateFormatter.string(from: normalized.start))-to-\(filenameDateFormatter.string(from: normalized.end)).\(format.fileExtension)"
    }

    static func normalizedRange(startDate: Date, endDate: Date, calendar: Calendar = .current) -> Range<Date> {
        let lower = calendar.startOfDay(for: min(startDate, endDate))
        let upperDay = calendar.startOfDay(for: max(startDate, endDate))
        let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay.addingTimeInterval(86_400)
        return lower..<upper
    }

    static func normalizedDisplayRange(startDate: Date, endDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let range = normalizedRange(startDate: startDate, endDate: endDate, calendar: calendar)
        let displayEnd = calendar.date(byAdding: .second, value: -1, to: range.upperBound) ?? max(startDate, endDate)
        return (range.lowerBound, displayEnd)
    }

    static func csvCell(_ value: String) -> String {
        var safe = value
        let trimmedPrefix = safe.drop { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" }
        if let first = trimmedPrefix.first, ["=", "+", "-", "@"].contains(first) {
            safe = "'" + safe
        }
        safe = safe.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(safe)\""
    }

    static func subtypeText(for event: CareEvent) -> String {
        switch event.type {
        case .sleep:
            return event.sleepKind?.displayName ?? ""
        case .feed:
            return event.feedKind?.displayName ?? ""
        case .nursing:
            return event.nursingSide?.displayName ?? ""
        case .diaper:
            return event.diaperKind?.displayName ?? ""
        case .potty:
            if event.profileTypeSnapshot == .dog {
                return event.dogDetails.pottyType?.displayName ?? ""
            }
            return event.childPottyKind?.displayName ?? ""
        case .activity:
            return event.activityType?.displayName ?? ""
        case .walk:
            return event.dogDetails.distance.map { "\($0)" } ?? ""
        case .rest:
            return event.dogDetails.restType?.displayName ?? ""
        case .training:
            return event.dogDetails.trainingType?.displayName ?? ""
        case .grooming:
            return event.dogDetails.groomingType?.displayName ?? ""
        case .symptom:
            return event.profileTypeSnapshot == .adult
                ? event.healthObservationDetails.symptomName ?? ""
                : event.dogDetails.symptomType?.displayName ?? ""
        case .vaccine:
            return event.dogDetails.vaccineType?.displayName ?? ""
        default:
            return event.title ?? ""
        }
    }

    static func amountText(for event: CareEvent) -> String {
        switch event.type {
        case .feed, .pumping:
            return event.amountOz.map { measurementFormatter.string(from: $0, unit: "oz") } ?? ""
        case .medicine:
            return compactJoined([
                event.dose.map { numberFormatter.string(from: NSNumber(value: $0)) ?? "\($0)" },
                event.doseUnit
            ], separator: " ")
        case .growth:
            return compactJoined([
                event.canonicalWeightKilograms.map { measurementFormatter.string(from: $0, unit: "kg") },
                event.canonicalLengthCentimeters.map { measurementFormatter.string(from: $0, unit: "cm") },
                event.headCircumferenceCentimeters.map { measurementFormatter.string(from: $0, unit: "cm head") }
            ])
        case .temperature:
            return event.temperatureCelsius.map { measurementFormatter.string(from: celsiusToFahrenheit($0), unit: "F") } ?? ""
        case .food:
            let details = event.dogDetails
            return compactJoined([
                details.foodAmount.map { measurementFormatter.string(from: $0, unit: details.foodUnit?.displayName ?? "") },
                details.eatenAmount?.displayName
            ])
        case .water:
            let details = event.dogDetails
            return details.waterAmount.map { measurementFormatter.string(from: $0, unit: details.waterUnit?.displayName ?? "") } ?? ""
        case .treat:
            return event.dogDetails.treatQuantity.map { measurementFormatter.string(from: $0, unit: "treats") } ?? ""
        case .walk:
            let details = event.dogDetails
            return details.distance.map { measurementFormatter.string(from: $0, unit: details.distanceUnit?.displayName ?? "") } ?? ""
        case .glucose:
            if event.profileTypeSnapshot == .adult {
                let details = event.healthObservationDetails
                return details.bloodGlucoseValue.map {
                    measurementFormatter.string(from: $0, unit: details.bloodGlucoseUnit?.displayName ?? "")
                } ?? ""
            }
            let details = event.dogDetails
            return details.glucoseValue.map { measurementFormatter.string(from: $0, unit: details.glucoseUnit?.displayName ?? "") } ?? ""
        case .bloodPressure:
            let details = event.healthObservationDetails
            guard let systolic = details.systolicBloodPressure,
                  let diastolic = details.diastolicBloodPressure else { return "" }
            return "\(systolic)/\(diastolic) mmHg"
        case .heartRate:
            return event.healthObservationDetails.heartRateBPM.map { "\($0) bpm" } ?? ""
        case .oxygenSaturation:
            return event.healthObservationDetails.oxygenSaturationPercent.map {
                measurementFormatter.string(from: $0, unit: "%")
            } ?? ""
        case .respiratoryRate:
            return event.healthObservationDetails.respiratoryRatePerMinute.map { "\($0) breaths/min" } ?? ""
        case .pain:
            return event.healthObservationDetails.painScore.map { "\($0)/10" } ?? ""
        default:
            return ""
        }
    }

    static func detailsText(for event: CareEvent) -> String {
        var parts: [String] = []
        switch event.type {
        case .feed:
            parts.appendIfPresent(event.foodDescription.map { "Food: \($0)" })
            parts.appendIfPresent(event.solidFeedingStyle.map { "Style: \($0.displayName)" })
            parts.appendIfPresent(event.solidTexture.map { "Texture: \($0.displayName)" })
            parts.appendIfPresent(event.solidReaction.map { "Reaction: \($0.displayName)" })
            if event.solidAllergenExposure == true { parts.append("Common allergen exposure") }
            if event.solidSensitivityObserved == true { parts.append("Sensitivity observed") }
            let solidDetails = event.solidFoodDetails
            let amountSummaries = solidDetails.compactMap(solidAmountSummary)
            if !amountSummaries.isEmpty {
                parts.append("Amounts: \(amountSummaries.joined(separator: "; "))")
            }
            let nutritionSnapshots = solidDetails.compactMap(\.nutritionSnapshot)
            let nutrition = nutritionSnapshots.reduce(SolidNutritionValues()) {
                $0.adding($1.nutrients)
            }
            let nutritionSummary = solidNutritionSummary(nutrition)
            if !nutritionSummary.isEmpty {
                let completeCount = nutritionSnapshots.filter(\.isComplete).count
                let note = if nutritionSnapshots.count == solidDetails.count,
                              completeCount == solidDetails.count {
                    "Estimated nutrients"
                } else {
                    "Estimated nutrients (coverage: \(nutritionSnapshots.count) of \(solidDetails.count) foods quantified; \(completeCount) with all eight nutrients)"
                }
                parts.append("\(note): \(nutritionSummary)")
            }
        case .nursing:
            parts.appendIfPresent(event.leftDurationSeconds.map { "Left: \(durationText(seconds: $0))" })
            parts.appendIfPresent(event.rightDurationSeconds.map { "Right: \(durationText(seconds: $0))" })
        case .diaper:
            parts.appendIfPresent(event.peeAmount.map { "Pee amount: \($0.displayName)" })
            parts.appendIfPresent(event.pooAmount.map { "Poo amount: \($0.displayName)" })
            parts.appendIfPresent(event.pooColor.map { "Poo color: \($0.displayName)" })
            parts.appendIfPresent(event.pooTexture.map { "Poo texture: \($0.displayName)" })
            if event.diaperRash == true { parts.append("Diaper rash") }
        case .potty:
            if event.profileTypeSnapshot == .dog {
                appendDogPottyDetails(event.dogDetails, to: &parts)
            } else {
                parts.appendIfPresent(event.childPottyLocation.map { "Location: \($0.displayName)" })
                if event.childPottyAccident == true { parts.append("Accident") }
                parts.appendIfPresent(event.peeAmount.map { "Pee amount: \($0.displayName)" })
                parts.appendIfPresent(event.pooAmount.map { "Poo amount: \($0.displayName)" })
                parts.appendIfPresent(event.pooColor.map { "Poo color: \($0.displayName)" })
                parts.appendIfPresent(event.pooTexture.map { "Poo texture: \($0.displayName)" })
            }
        case .medicine:
            parts.appendIfPresent(event.medicineName.map { "Medicine: \($0)" })
            parts.appendIfPresent(event.reason.map { "Reason: \($0)" })
            appendDogMedicineDetails(event.dogDetails, to: &parts)
        case .temperature:
            parts.appendIfPresent(event.temperatureMethod.map { "Method: \($0.displayName)" })
        case .activity:
            parts.appendIfPresent(event.bookTitle.map { "Book: \($0)" })
        case .food:
            let details = event.dogDetails
            parts.appendIfPresent(details.foodName.map { "Food: \($0)" })
            parts.appendIfPresent(details.mealType.map { "Meal: \($0.displayName)" })
        case .water:
            break
        case .treat:
            parts.appendIfPresent(event.dogDetails.treatName.map { "Treat: \($0)" })
        case .walk:
            let details = event.dogDetails
            parts.appendIfPresent(details.leashBehavior.map { "Leash: \($0.displayName)" })
            parts.appendIfPresent(details.weather.map { "Weather: \($0)" })
            parts.appendIfPresent(details.peeCount.map { "Pee count: \($0)" })
            parts.appendIfPresent(details.poopCount.map { "Poop count: \($0)" })
        case .training:
            let details = event.dogDetails
            parts.appendIfPresent(details.trainingSkill.map { "Skill: \($0)" })
            parts.appendIfPresent(details.trainingOutcome.map { "Outcome: \($0.displayName)" })
        case .symptom:
            if event.profileTypeSnapshot == .adult {
                let details = event.healthObservationDetails
                parts.appendIfPresent(details.symptomSeverity.map { "Severity: \($0)/10" })
                parts.appendIfPresent(details.symptomBodyLocation.map { "Location: \($0)" })
                if details.symptomResolved == true { parts.append("Resolved") }
            } else {
                let details = event.dogDetails
                parts.appendIfPresent(details.symptomSeverity.map { "Severity: \($0.displayName)" })
                if details.symptomResolved == true { parts.append("Resolved") }
            }
        case .vaccine:
            let details = event.dogDetails
            parts.appendIfPresent(details.vaccineDueDate.map { "Next due: \(dateFormatter.string(from: $0))" })
            parts.appendIfPresent(details.vaccineLotNumber.map { "Lot: \($0)" })
            parts.appendIfPresent(details.vaccineClinic.map { "Clinic: \($0)" })
        case .glucose:
            if event.profileTypeSnapshot == .adult {
                parts.appendIfPresent(event.healthObservationDetails.bloodGlucoseContext.map { "Context: \($0.displayName)" })
            } else {
                parts.appendIfPresent(event.dogDetails.glucoseMealRelation.map { "Meal relation: \($0.displayName)" })
            }
        case .pain:
            parts.appendIfPresent(event.healthObservationDetails.painLocation.map { "Location: \($0)" })
        default:
            break
        }
        return compactJoined(parts)
    }

    private static func solidAmountSummary(_ detail: SolidFoodLogDetail) -> String? {
        guard let unit = detail.portionUnit else { return nil }
        if let eaten = detail.amountEaten {
            return "\(detail.foodName) \(eaten.formatted(.number.precision(.fractionLength(0...2)))) \(unit.abbreviatedName) eaten"
        }
        if let offered = detail.amountOffered, let estimate = detail.consumptionEstimate {
            return "\(detail.foodName) \(estimate.displayName.lowercased()) of \(offered.formatted(.number.precision(.fractionLength(0...2)))) \(unit.abbreviatedName)"
        }
        if let offered = detail.amountOffered {
            return "\(detail.foodName) \(offered.formatted(.number.precision(.fractionLength(0...2)))) \(unit.abbreviatedName) offered"
        }
        return nil
    }

    private static func solidNutritionSummary(_ values: SolidNutritionValues) -> String {
        var valuesText: [String] = []
        valuesText.appendIfPresent(values.energyKilocalories.map {
            "\($0.formatted(.number.precision(.fractionLength(0...1)))) kcal"
        })
        valuesText.appendIfPresent(values.proteinGrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) g protein"
        })
        valuesText.appendIfPresent(values.fatGrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) g fat"
        })
        valuesText.appendIfPresent(values.fiberGrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) g fiber"
        })
        valuesText.appendIfPresent(values.ironMilligrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) mg iron"
        })
        valuesText.appendIfPresent(values.zincMilligrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) mg zinc"
        })
        valuesText.appendIfPresent(values.calciumMilligrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...1)))) mg calcium"
        })
        valuesText.appendIfPresent(values.vitaminCMilligrams.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) mg vitamin C"
        })
        return valuesText.joined(separator: ", ")
    }

    static func medicationPlanDetails(
        medication: Medication,
        regimen: MedicationRegimen?
    ) -> String {
        var parts = [
            medication.strengthDescription.map { "Strength: \($0)" },
            "Form: \(medication.form.displayName)",
            "Route: \(medication.route.displayName)",
            medication.reasonForTaking.nilIfBlank.map { "For: \($0)" }
        ].compactMap { $0 }
        if let regimen {
            parts.append("Schedule: \(regimen.scheduleSummary)")
            parts.append(
                "Dose: \(regimen.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(regimen.doseUnit)"
            )
            if !regimen.doseTimes.isEmpty {
                parts.append("Times: \(regimen.doseTimes.map(\.id).joined(separator: ", "))")
            }
            if regimen.remindersEnabled {
                parts.append(regimen.followUpRemindersEnabled
                    ? "Reminders: scheduled and 30-minute follow-up"
                    : "Reminders: scheduled")
                parts.append("Travel timing: \(regimen.timeZoneBehavior.displayName)")
            }
        }
        parts.appendIfPresent(medication.instructions.nilIfBlank.map { "Instructions: \($0)" })
        parts.appendIfPresent(medication.prescriber.nilIfBlank.map { "Prescriber: \($0)" })
        parts.appendIfPresent(medication.pharmacy.nilIfBlank.map { "Pharmacy: \($0)" })
        return compactJoined(parts)
    }

    static func appointmentDetailsText(
        for appointment: DoctorAppointment,
        followUps: [AppointmentFollowUp] = [],
        includeNotes: Bool
    ) -> String {
        var values = [
            appointment.doctorName.map { "Doctor: \($0)" },
            appointment.clinicName.map { "Clinic: \($0)" },
            appointment.locationName.map { "Location: \($0)" },
            appointment.questionsToAsk.map { "Questions: \($0)" },
            includeNotes ? appointment.visitSummary.map { "Visit summary: \($0)" } : nil,
            includeNotes ? appointment.medicationsDiscussed.map { "Medications: \($0)" } : nil,
            includeNotes ? appointment.vaccinesGiven.map { "Vaccines: \($0)" } : nil
        ]
        if !followUps.isEmpty {
            let followUpText = followUps.map { followUp in
                var detail = followUp.title
                if let dueDate = followUp.dueDate {
                    detail += " (due \(dueDate.formatted(date: .abbreviated, time: .shortened)))"
                }
                if followUp.isCompleted { detail += " [completed]" }
                if includeNotes, let notes = followUp.details {
                    detail += ": \(notes)"
                }
                return detail
            }.joined(separator: "; ")
            values.append("Follow-ups: \(followUpText)")
        }
        return compactJoined(values)
    }

    static func durationText(for event: CareEvent) -> String {
        guard let endDate = event.endDate else { return "" }
        return durationText(seconds: max(0, endDate.timeIntervalSince(event.startDate)))
    }

    static func durationText(seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func summaryRows(for report: CareReport) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Total events", "\(report.events.count)"),
            ("Appointments", "\(report.appointments.count)"),
            ("Milestones", "\(report.milestones.count)"),
            ("Current medications", "\(report.medications.count)")
        ]
        let sleepMinutes = report.events
            .filter { $0.type == .sleep }
            .reduce(0.0) { total, event in
                total + max(0, (event.endDate ?? event.startDate).timeIntervalSince(event.startDate) / 60)
            }
        if sleepMinutes > 0 {
            rows.append(("Logged sleep", durationText(seconds: sleepMinutes * 60)))
        }
        let bottleOunces = report.events
            .filter { $0.type == .feed || $0.type == .pumping }
            .compactMap(\.amountOz)
            .reduce(0, +)
        if bottleOunces > 0 {
            rows.append(("Bottle/pumping amount", measurementFormatter.string(from: bottleOunces, unit: "oz")))
        }
        let medicineCount = report.events.filter { $0.type == .medicine }.count
        if medicineCount > 0 {
            rows.append(("Medicine logs", "\(medicineCount)"))
        }
        let temperatureValues = report.events.compactMap(\.temperatureCelsius)
        if let maxTemperature = temperatureValues.max() {
            rows.append(("Highest temperature", measurementFormatter.string(from: celsiusToFahrenheit(maxTemperature), unit: "F")))
        }
        let counts = Dictionary(grouping: report.events, by: \.type).mapValues(\.count)
        for type in EventType.cases(for: report.profile.profileType) {
            if let count = counts[type], count > 0 {
                rows.append((type.displayName, "\(count)"))
            }
        }
        return rows
    }

    private static func summaryHighlights(for report: CareReport) -> [String] {
        let rangeText = "\(dateFormatter.string(from: report.options.startDate)) to \(dateFormatter.string(from: report.options.endDate))"
        var includedRecords = [pluralized(report.events.count, singular: "care log", plural: "care logs")]
        if report.options.includeAppointments {
            includedRecords.append(pluralized(report.appointments.count, singular: "appointment", plural: "appointments"))
        }
        if report.options.includeMilestones {
            includedRecords.append(pluralized(report.milestones.count, singular: "milestone", plural: "milestones"))
        }

        var highlights = [
            "Covers \(rangeText) for \(report.profile.name), with \(sentenceList(includedRecords))."
        ]

        if report.events.isEmpty {
            highlights.append("No care events were logged for this profile in the selected range.")
            return highlights
        }

        let counts = Dictionary(grouping: report.events, by: \.type).mapValues(\.count)
        let topCategories = counts
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.displayName < second.key.displayName
                }
                return first.value > second.value
            }
            .prefix(3)
            .map { "\($0.key.displayName) (\($0.value))" }
        if !topCategories.isEmpty {
            highlights.append("Most logged categories: \(topCategories.joined(separator: ", ")).")
        }

        let sleepSeconds = report.events
            .filter { $0.type == .sleep }
            .reduce(0.0) { total, event in
                total + max(0, (event.endDate ?? event.startDate).timeIntervalSince(event.startDate))
            }
        if sleepSeconds > 0 {
            highlights.append("Logged sleep total: \(durationText(seconds: sleepSeconds)).")
        }

        let bottleOunces = report.events
            .filter { $0.type == .feed || $0.type == .pumping }
            .compactMap(\.amountOz)
            .reduce(0, +)
        if bottleOunces > 0 {
            highlights.append("Bottle/pumping amount total: \(measurementFormatter.string(from: bottleOunces, unit: "oz")).")
        }

        let medicineCount = report.events.filter { $0.type == .medicine }.count
        if medicineCount > 0 {
            highlights.append("Medicine logs included: \(medicineCount).")
        }

        if let maxTemperature = report.events.compactMap(\.temperatureCelsius).max() {
            highlights.append("Highest logged temperature: \(measurementFormatter.string(from: celsiusToFahrenheit(maxTemperature), unit: "F")).")
        }

        if let latestEvent = report.events.max(by: { $0.startDate < $1.startDate }) {
            highlights.append("Latest care log: \(dateTimeFormatter.string(from: latestEvent.startDate)) - \(latestEvent.type.displayName).")
        }

        return highlights
    }

    private static func sectionOrder(for profileType: CareProfileType) -> [(title: String, eventType: EventType)] {
        switch profileType {
        case .child:
            return [
                ("Sleep", .sleep),
                ("Feeding", .feed),
                ("Nursing", .nursing),
                ("Pumping", .pumping),
                ("Diapers", .diaper),
                ("Potty", .potty),
                ("Medicine", .medicine),
                ("Temperature", .temperature),
                ("Growth", .growth),
                ("Activity", .activity)
            ]
        case .adult:
            return [
                ("Medicine", .medicine),
                ("Symptoms", .symptom),
                ("Blood Pressure", .bloodPressure),
                ("Heart Rate", .heartRate),
                ("Oxygen Saturation", .oxygenSaturation),
                ("Respiratory Rate", .respiratoryRate),
                ("Blood Glucose", .glucose),
                ("Temperature", .temperature),
                ("Pain", .pain),
                ("Growth and Weight", .growth),
                ("Sleep", .sleep),
                ("Activity", .activity)
            ]
        case .dog:
            return [
                ("Food", .food),
                ("Water", .water),
                ("Treats", .treat),
                ("Potty", .potty),
                ("Walks", .walk),
                ("Rest", .rest),
                ("Training", .training),
                ("Grooming", .grooming),
                ("Medicine", .medicine),
                ("Symptoms", .symptom),
                ("Vaccines", .vaccine),
                ("Glucose", .glucose),
                ("Growth", .growth),
                ("Temperature", .temperature)
            ]
        }
    }

    private static func drawBrandHeader(for report: CareReport, cursor: inout PDFCursor) {
        let headerHeight: CGFloat = 74
        let headerRect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: headerHeight)
        PDFStyle.headerFill.setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 12).fill()

        let iconRect = CGRect(x: headerRect.minX + 14, y: headerRect.minY + 14, width: 46, height: 46)
        drawAppIcon(in: iconRect)

        let titleX = iconRect.maxX + 12
        let titleWidth = headerRect.width - 214
        drawFixedText(
            "Little Windows",
            at: CGPoint(x: titleX, y: headerRect.minY + 13),
            width: titleWidth,
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: PDFStyle.brandText
        )
        drawFixedText(
            "Care Visit Report",
            at: CGPoint(x: titleX, y: headerRect.minY + 27),
            width: titleWidth,
            font: .systemFont(ofSize: 20, weight: .bold),
            color: PDFStyle.ink
        )
        drawFixedText(
            pdfSingleLineText("\(report.profile.name) - \(report.profile.profileType.displayName)", limit: 56),
            at: CGPoint(x: titleX, y: headerRect.minY + 52),
            width: titleWidth,
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: PDFStyle.ink
        )

        let metaX = headerRect.maxX - 178
        drawFixedText(
            "\(dateFormatter.string(from: report.options.startDate)) to \(dateFormatter.string(from: report.options.endDate))",
            at: CGPoint(x: metaX, y: headerRect.minY + 18),
            width: 158,
            font: .systemFont(ofSize: 8.5, weight: .semibold),
            color: PDFStyle.ink,
            alignment: .right
        )
        drawFixedText(
            "Generated \(dateTimeFormatter.string(from: report.generatedAt))",
            at: CGPoint(x: metaX, y: headerRect.minY + 33),
            width: 158,
            font: .systemFont(ofSize: 8, weight: .regular),
            color: PDFStyle.mutedText,
            alignment: .right
        )
        drawFixedText(
            pdfSingleLineText(profileSubtitle(for: report.profile), limit: 62),
            at: CGPoint(x: metaX, y: headerRect.minY + 48),
            width: 158,
            font: .systemFont(ofSize: 8, weight: .regular),
            color: PDFStyle.mutedText,
            alignment: .right
        )

        cursor.y = headerRect.maxY + 10
        drawNotice("Local care logs for visit prep. This report is not medical advice.", cursor: &cursor)
    }

    private static func drawSection(_ text: String, cursor: inout PDFCursor, context: UIGraphicsPDFRendererContext) {
        let font = UIFont.systemFont(ofSize: 10.5, weight: .bold)
        let title = text.uppercased()
        let titleHeight = textHeight(title, width: cursor.contentWidth, font: font)
        ensureRoom(titleHeight + 20, cursor: &cursor, context: context)
        cursor.addSpace(8)
        drawFixedText(
            title,
            at: CGPoint(x: cursor.margin, y: cursor.y),
            width: cursor.contentWidth,
            font: font,
            color: PDFStyle.brandText
        )
        cursor.y += titleHeight + 5

        let ruleRect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: 1)
        PDFStyle.rule.setFill()
        UIRectFill(ruleRect)
        cursor.y += 5
    }

    private static func drawBody(
        _ text: String,
        cursor: inout PDFCursor,
        weight: UIFont.Weight = .regular,
        color: UIColor = PDFStyle.ink
    ) {
        drawText(text, cursor: &cursor, font: .systemFont(ofSize: 8.8, weight: weight), color: color, after: 2)
    }

    private static func drawKeyValues(
        _ rows: [(String, String)],
        cursor: inout PDFCursor,
        context: UIGraphicsPDFRendererContext
    ) {
        let columns = 3
        let gap: CGFloat = 7
        let cellWidth = (cursor.contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight: CGFloat = 30
        var index = 0
        while index < rows.count {
            ensureRoom(cellHeight + 4, cursor: &cursor, context: context)
            let rowY = cursor.y
            for column in 0..<columns {
                let rowIndex = index + column
                guard rowIndex < rows.count else { continue }
                let x = cursor.margin + CGFloat(column) * (cellWidth + gap)
                let rect = CGRect(x: x, y: rowY, width: cellWidth, height: cellHeight)
                PDFStyle.cardFill.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
                drawFixedText(
                    rows[rowIndex].0,
                    at: CGPoint(x: rect.minX + 7, y: rect.minY + 5),
                    width: rect.width - 14,
                    font: .systemFont(ofSize: 7.3, weight: .semibold),
                    color: PDFStyle.mutedText
                )
                drawFixedText(
                    rows[rowIndex].1,
                    at: CGPoint(x: rect.minX + 7, y: rect.minY + 16),
                    width: rect.width - 14,
                    font: .systemFont(ofSize: 10.5, weight: .bold),
                    color: PDFStyle.ink
                )
            }
            cursor.y += cellHeight + 4
            index += columns
        }
    }

    private static func drawOverview(
        _ highlights: [String],
        cursor: inout PDFCursor,
        context: UIGraphicsPDFRendererContext
    ) {
        let bulletWidth: CGFloat = 12
        let inset: CGFloat = 9
        let gap: CGFloat = 2
        let font = UIFont.systemFont(ofSize: 8.4, weight: .regular)
        let textWidth = cursor.contentWidth - inset * 2 - bulletWidth
        let lineHeights = highlights.map { textHeight($0, width: textWidth, font: font) }
        let contentHeight = lineHeights.reduce(0, +) + CGFloat(max(0, highlights.count - 1)) * gap
        let boxHeight = max(28, contentHeight + inset * 2)

        ensureRoom(boxHeight + 3, cursor: &cursor, context: context)

        let rect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: boxHeight)
        PDFStyle.overviewFill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()

        var y = rect.minY + inset
        for index in highlights.indices {
            drawFixedText(
                "-",
                at: CGPoint(x: rect.minX + inset, y: y),
                width: bulletWidth,
                font: .systemFont(ofSize: 8.4, weight: .semibold),
                color: PDFStyle.brandText
            )
            drawFixedText(
                highlights[index],
                at: CGPoint(x: rect.minX + inset + bulletWidth, y: y),
                width: textWidth,
                font: font,
                color: PDFStyle.ink
            )
            y += lineHeights[index] + gap
        }
        cursor.y = rect.maxY + 3
    }

    private static func drawEmptyState(
        _ text: String,
        cursor: inout PDFCursor,
        context: UIGraphicsPDFRendererContext
    ) {
        ensureRoom(28, cursor: &cursor, context: context)
        let rect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: 26)
        PDFStyle.rowFill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
        drawFixedText(
            text,
            at: CGPoint(x: rect.minX + 8, y: rect.minY + 8),
            width: rect.width - 16,
            font: .systemFont(ofSize: 8, weight: .medium),
            color: PDFStyle.mutedText
        )
        cursor.y = rect.maxY + 3
    }

    private static func drawEvent(
        _ event: CareEvent,
        options: CareReportExportOptions,
        cursor: inout PDFCursor,
        context: UIGraphicsPDFRendererContext
    ) {
        let title = compactJoined([
            event.type.displayName,
            subtypeText(for: event),
            amountText(for: event),
            durationText(for: event)
        ], separator: " - ")
        var detailParts = [String]()
        detailParts.appendIfPresent(pdfSafeText(detailsText(for: event), limit: 220))
        if options.includeCaregiverNames, let caregiver = event.caregiverName, !caregiver.isEmpty {
            detailParts.append("Caregiver: \(pdfSafeText(caregiver, limit: 80))")
        }
        if options.includeNotes, let notes = event.notes, !notes.isEmpty {
            detailParts.append("Notes: \(pdfSafeText(notes, limit: 260))")
        }
        drawTimelineRow(
            time: "\(DateFormatting.dayString(from: event.startDate, timeZone: event.startTimeZone)) \(DateFormatting.timeString(from: event.startDate, timeZone: event.startTimeZone, includesTimeZone: true))",
            title: title,
            details: compactJoined(detailParts, separator: "  |  "),
            cursor: &cursor,
            context: context
        )
    }

    private static func drawCompactRecord(
        title: String,
        details: String,
        cursor: inout PDFCursor,
        context: UIGraphicsPDFRendererContext
    ) {
        drawTimelineRow(
            time: "",
            title: title,
            details: pdfSafeText(details, limit: 320),
            cursor: &cursor,
            context: context
        )
    }

    private static func drawTimelineRow(
        time: String,
        title: String,
        details: String,
        cursor: inout PDFCursor,
        context: UIGraphicsPDFRendererContext
    ) {
        let timeWidth: CGFloat = time.isEmpty ? 0 : 104
        let gap: CGFloat = time.isEmpty ? 0 : 10
        let textX = cursor.margin + timeWidth + gap
        let textWidth = cursor.contentWidth - timeWidth - gap - 10
        let titleFont = UIFont.systemFont(ofSize: 8.8, weight: .semibold)
        let detailFont = UIFont.systemFont(ofSize: 7.7, weight: .regular)
        let titleHeight = textHeight(title, width: textWidth, font: titleFont)
        let detailHeight = details.isEmpty ? 0 : textHeight(details, width: textWidth, font: detailFont)
        let rowHeight = max(26, titleHeight + detailHeight + (details.isEmpty ? 10 : 13))

        ensureRoom(rowHeight + 3, cursor: &cursor, context: context)

        let rowRect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: rowHeight)
        PDFStyle.rowFill.setFill()
        UIBezierPath(roundedRect: rowRect, cornerRadius: 4).fill()

        if !time.isEmpty {
            drawFixedText(
                time,
                at: CGPoint(x: rowRect.minX + 7, y: rowRect.minY + 7),
                width: timeWidth - 14,
                font: .systemFont(ofSize: 7.4, weight: .semibold),
                color: PDFStyle.mutedText
            )
        }
        drawFixedText(
            title,
            at: CGPoint(x: textX, y: rowRect.minY + 6),
            width: textWidth,
            font: titleFont,
            color: PDFStyle.ink
        )
        if !details.isEmpty {
            drawFixedText(
                details,
                at: CGPoint(x: textX, y: rowRect.minY + 8 + titleHeight),
                width: textWidth,
                font: detailFont,
                color: PDFStyle.mutedText
            )
        }
        cursor.y += rowHeight + 3
    }

    private static func drawNotice(_ text: String, cursor: inout PDFCursor) {
        let rect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: 21)
        PDFStyle.noticeFill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
        drawFixedText(
            text,
            at: CGPoint(x: rect.minX + 8, y: rect.minY + 6),
            width: rect.width - 16,
            font: .systemFont(ofSize: 7.7, weight: .medium),
            color: PDFStyle.brandText
        )
        cursor.y = rect.maxY + 2
    }

    private static func drawAppIcon(in rect: CGRect) {
        if let icon = appIconImage() {
            guard let currentContext = UIGraphicsGetCurrentContext() else {
                icon.draw(in: rect)
                return
            }
            currentContext.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: 10).addClip()
            icon.draw(in: rect)
            currentContext.restoreGState()
        } else {
            PDFStyle.brandText.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
            drawFixedText(
                "LW",
                at: CGPoint(x: rect.minX, y: rect.minY + 14),
                width: rect.width,
                font: .systemFont(ofSize: 14, weight: .bold),
                color: .white,
                alignment: .center
            )
        }
    }

    private static func appIconImage() -> UIImage? {
        if let icon = UIImage(named: "AppIcon") {
            return icon
        }
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String]
        else {
            return nil
        }
        return iconFiles.reversed().lazy.compactMap { UIImage(named: $0) }.first
    }

    private static func drawText(
        _ text: String,
        cursor: inout PDFCursor,
        font: UIFont,
        color: UIColor,
        after: CGFloat = 3
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: .greatestFiniteMagnitude)
        let height = textHeight(text, width: rect.width, font: font, attributes: attributes)
        text.draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height), withAttributes: attributes)
        cursor.y += height + after
    }

    private static func drawFixedText(
        _ text: String,
        at point: CGPoint,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let height = textHeight(text, width: width, font: font, attributes: attributes)
        text.draw(in: CGRect(x: point.x, y: point.y, width: width, height: height), withAttributes: attributes)
    }

    private static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return textHeight(text, width: width, font: font, attributes: attributes)
    }

    private static func textHeight(
        _ text: String,
        width: CGFloat,
        font _: UIFont,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).height.rounded(.up)
    }

    private static func ensureRoom(_ height: CGFloat, cursor: inout PDFCursor, context: UIGraphicsPDFRendererContext) {
        guard cursor.y + height > cursor.contentMaxY else { return }
        drawPageFooter(cursor)
        context.beginPage()
        cursor.pageNumber += 1
        cursor.y = cursor.margin
        drawContinuationHeader(cursor: &cursor)
    }

    private static func drawContinuationHeader(cursor: inout PDFCursor) {
        drawFixedText(
            cursor.continuationTitle,
            at: CGPoint(x: cursor.margin, y: cursor.y),
            width: cursor.contentWidth * 0.45,
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: PDFStyle.brandText
        )
        drawFixedText(
            cursor.continuationSubtitle,
            at: CGPoint(x: cursor.margin + cursor.contentWidth * 0.45, y: cursor.y),
            width: cursor.contentWidth * 0.55,
            font: .systemFont(ofSize: 7.5, weight: .medium),
            color: PDFStyle.mutedText,
            alignment: .right
        )
        cursor.y += 17
        PDFStyle.rule.setFill()
        UIRectFill(CGRect(x: cursor.margin, y: cursor.y, width: cursor.contentWidth, height: 1))
        cursor.y += 9
    }

    private static func drawPageFooter(_ cursor: PDFCursor) {
        let footerY = cursor.pageBounds.maxY - cursor.margin - 12
        PDFStyle.rule.setFill()
        UIRectFill(CGRect(x: cursor.margin, y: footerY - 6, width: cursor.contentWidth, height: 1))
        drawFixedText(
            "Little Windows care report",
            at: CGPoint(x: cursor.margin, y: footerY),
            width: cursor.contentWidth * 0.6,
            font: .systemFont(ofSize: 7, weight: .medium),
            color: PDFStyle.mutedText
        )
        drawFixedText(
            "Page \(cursor.pageNumber)",
            at: CGPoint(x: cursor.margin + cursor.contentWidth * 0.6, y: footerY),
            width: cursor.contentWidth * 0.4,
            font: .systemFont(ofSize: 7, weight: .medium),
            color: PDFStyle.mutedText,
            alignment: .right
        )
    }

    private static func profileSubtitle(for profile: CareProfile) -> String {
        switch profile.profileType {
        case .child:
            return "Age: \(profile.ageDescription)"
        case .adult:
            return compactJoined([
                profile.adultRelationship.map { "Relationship: \($0.displayName)" },
                profile.birthDate.map { _ in "Age: \(profile.ageDescription)" }
            ], separator: " - ")
        case .dog:
            return compactJoined([
                profile.breed.map { "Breed: \($0)" },
                "Age: \(profile.ageDescription)",
                profile.vetName.map { "Vet: \($0)" },
                profile.vetClinic.map { "Clinic: \($0)" }
            ], separator: " - ")
        }
    }

    private static func pdfSafeText(_ text: String, limit: Int = 900) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func pdfSingleLineText(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func appendDogPottyDetails(_ details: DogEventDetails, to parts: inout [String]) {
        parts.appendIfPresent(details.pottyLocation.map { "Location: \($0.displayName)" })
        if details.accident == true { parts.append("Accident") }
        parts.appendIfPresent(details.peeAmount.map { "Pee amount: \($0.displayName)" })
        parts.appendIfPresent(details.peeColor.map { "Pee color: \($0.displayName)" })
        parts.appendIfPresent(details.poopAmount.map { "Poop amount: \($0.displayName)" })
        parts.appendIfPresent(details.poopColor.map { "Poop color: \($0.displayName)" })
        parts.appendIfPresent(details.stoolQuality.map { "Stool: \($0.displayName)" })
    }

    private static func appendDogMedicineDetails(_ details: DogEventDetails, to parts: inout [String]) {
        parts.appendIfPresent(details.medicineUnit.map { "Dog unit: \($0.displayName)" })
        parts.appendIfPresent(details.medicineRoute.map { "Route: \($0.displayName)" })
    }

    private static func compactJoined(_ values: [String?], separator: String = "; ") -> String {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.joined(separator: separator)
    }

    private static func compactJoined(_ values: [String], separator: String = "; ") -> String {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    private static func pluralized(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private static func sentenceList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            let leading = values.dropLast().joined(separator: ", ")
            return "\(leading), and \(values[values.count - 1])"
        }
    }

    private static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9 / 5 + 32
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let measurementFormatter = CareReportMeasurementFormatter()
}

private struct PDFCursor {
    var pageBounds: CGRect
    var continuationTitle: String
    var continuationSubtitle: String
    var margin: CGFloat = 34
    var y: CGFloat = 34
    var pageNumber = 1
    var contentWidth: CGFloat { pageBounds.width - margin * 2 }
    var contentMaxY: CGFloat { pageBounds.maxY - margin - 24 }

    mutating func addSpace(_ value: CGFloat) {
        y += value
    }
}

private enum PDFStyle {
    static let ink = UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1)
    static let mutedText = UIColor(red: 0.34, green: 0.39, blue: 0.45, alpha: 1)
    static let brandText = UIColor(red: 0.10, green: 0.38, blue: 0.44, alpha: 1)
    static let headerFill = UIColor(red: 0.89, green: 0.96, blue: 0.96, alpha: 1)
    static let noticeFill = UIColor(red: 0.94, green: 0.98, blue: 0.98, alpha: 1)
    static let overviewFill = UIColor(red: 0.95, green: 0.98, blue: 0.98, alpha: 1)
    static let cardFill = UIColor(red: 0.96, green: 0.98, blue: 0.98, alpha: 1)
    static let rowFill = UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1)
    static let rule = UIColor(red: 0.77, green: 0.88, blue: 0.88, alpha: 1)
}

private struct CareReportMeasurementFormatter {
    func string(from value: Double, unit: String) -> String {
        let formatted = numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUnit.isEmpty ? formatted : "\(formatted) \(trimmedUnit)"
    }

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

private extension Array where Element == String {
    mutating func appendIfPresent(_ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        append(value)
    }
}
