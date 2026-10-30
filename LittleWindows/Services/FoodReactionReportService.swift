import CoreText
import Foundation
import SwiftData
import UIKit

struct FoodReactionReportOptions {
    var startDate: Date
    var endDate: Date
    var includeNotes = true
    var includeCaregiverNames = true
    var includeMealsWithoutReactions = false
}

struct FoodReactionReportEntry: Identifiable {
    let id: String
    let eventID: UUID
    let date: Date
    let timeZoneIdentifier: String
    let food: String
    let mealFoods: String
    let allergens: String
    let observation: String
    let symptoms: String
    let severity: String
    let onset: String
    let duration: String
    let response: String
    let followUp: String
    let foodNotes: String
    let mealNotes: String
    let caregiver: String
    let hasReaction: Bool
}

struct FoodReactionReport {
    let profileName: String
    let options: FoodReactionReportOptions
    let entries: [FoodReactionReportEntry]
    let mealCount: Int
    let reactionMealCount: Int
    let generatedAt: Date

    static let notice = "Caregiver-recorded observations only. A possible reaction does not confirm an allergy or identify its cause. Missing reaction notes do not establish tolerance."
}

@MainActor
enum FoodReactionReportService {
    enum ReportError: LocalizedError {
        case childProfileRequired

        var errorDescription: String? { "Choose a child profile for a food reaction report." }
    }

    static func makeReport(
        profile: CareProfile,
        options: FoodReactionReportOptions,
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = Date()
    ) throws -> FoodReactionReport {
        guard profile.profileType == .child else { throw ReportError.childProfileRequired }
        let range = CareReportExportService.normalizedRange(
            startDate: options.startDate, endDate: options.endDate, calendar: calendar
        )
        let profileID = profile.id
        let lower = range.lowerBound.addingTimeInterval(-30 * 60 * 60)
        let upper = range.upperBound.addingTimeInterval(30 * 60 * 60)
        // The event's saved food details are authoritative. Derived food-index
        // records may still be backfilling and must not duplicate observations.
        let events = try context.fetch(FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.startDate >= lower && $0.startDate < upper
            },
            sortBy: [SortDescriptor(\.startDate), SortDescriptor(\.createdAt)]
        )).filter {
            $0.type == .feed && $0.feedKind == .solid && !$0.isTimerDraft
                && range.contains($0.localStartDay(calendar: calendar))
        }
        var entries: [FoodReactionReportEntry] = []
        for event in events {
            let details = event.solidFoodDetails
            let mealFoods = details.isEmpty
                ? recorded(event.foodDescription)
                : details.map(\.foodName).joined(separator: ", ")
            for (index, detail) in details.enumerated() {
                let hasReaction = hasReactionDetails(detail)
                guard hasReaction || options.includeMealsWithoutReactions else { continue }
                entries.append(FoodReactionReportEntry(
                    id: "\(event.id)-\(index)", eventID: event.id,
                    date: event.startDate, timeZoneIdentifier: event.startTimeZone.identifier,
                    food: recorded(detail.foodName), mealFoods: mealFoods,
                    allergens: allergenNames(detail.allergenIDs),
                    observation: hasReaction ? "Possible reaction recorded" : "No reaction details recorded",
                    symptoms: detail.symptoms.isEmpty ? "Not recorded" : detail.symptoms.map(\.displayName).joined(separator: ", "),
                    severity: detail.severity == .unknown ? "Not recorded" : detail.severity.displayName,
                    onset: minutes(detail.onsetMinutes), duration: minutes(detail.durationMinutes),
                    response: options.includeNotes ? recorded(detail.responseNotes) : "",
                    followUp: detail.followUp == .none ? "Not recorded" : detail.followUp.displayName,
                    foodNotes: options.includeNotes ? (detail.notes ?? "") : "",
                    mealNotes: options.includeNotes ? (event.notes ?? "") : "",
                    caregiver: options.includeCaregiverNames ? (event.caregiverName ?? "") : "",
                    hasReaction: hasReaction
                ))
            }
            // Older sensitivity flags describe the whole meal. Do not assign
            // that observation to each ingredient or infer allergens by name.
            let mealLevelReaction = event.solidSensitivityObserved == true
                && !details.contains(where: hasReactionDetails)
            if mealLevelReaction || (details.isEmpty && options.includeMealsWithoutReactions) {
                entries.append(FoodReactionReportEntry(
                    id: "\(event.id)-meal", eventID: event.id,
                    date: event.startDate, timeZoneIdentifier: event.startTimeZone.identifier,
                    food: "Meal-level observation", mealFoods: mealFoods,
                    allergens: details.isEmpty ? "Not recorded" : allergenNames(details.flatMap(\.allergenIDs)),
                    observation: mealLevelReaction
                        ? "Possible reaction recorded for the meal; individual food not identified"
                        : "No reaction details recorded",
                    symptoms: "Not recorded", severity: "Not recorded",
                    onset: "Not recorded", duration: "Not recorded",
                    response: "", followUp: "Not recorded", foodNotes: "",
                    mealNotes: options.includeNotes ? (event.notes ?? "") : "",
                    caregiver: options.includeCaregiverNames ? (event.caregiverName ?? "") : "",
                    hasReaction: mealLevelReaction
                ))
            }
        }
        var normalizedOptions = options
        normalizedOptions.startDate = range.lowerBound
        normalizedOptions.endDate = range.upperBound.addingTimeInterval(-1)
        return FoodReactionReport(
            profileName: profile.name, options: normalizedOptions, entries: entries,
            mealCount: events.count,
            reactionMealCount: Set(entries.filter(\.hasReaction).map(\.eventID)).count,
            generatedAt: now
        )
    }

    static func csvData(for report: FoodReactionReport) -> Data {
        var header = [
            "Profile", "Meal Date", "Meal Time", "Time Zone", "Food", "Meal Foods",
            "Recorded Allergens", "Observation", "Symptoms", "Recorded Severity",
            "Onset After Meal", "Duration", "Follow-up"
        ]
        if report.options.includeNotes { header += ["Response Taken", "Food Notes", "Meal Notes"] }
        if report.options.includeCaregiverNames { header.append("Caregiver") }
        var rows = [header]
        rows += report.entries.map { entry in
            let zone = TimeZone(identifier: entry.timeZoneIdentifier) ?? .current
            var row = [
                report.profileName, DateFormatting.dayString(from: entry.date, timeZone: zone),
                DateFormatting.timeString(from: entry.date, timeZone: zone),
                entry.timeZoneIdentifier, entry.food, entry.mealFoods, entry.allergens,
                entry.observation, entry.symptoms, entry.severity, entry.onset, entry.duration, entry.followUp
            ]
            if report.options.includeNotes { row += [entry.response, entry.foodNotes, entry.mealNotes] }
            if report.options.includeCaregiverNames { row.append(entry.caregiver) }
            return row
        }
        // Keep the interpretation notice in the file, including empty exports,
        // without changing the number or meaning of the data columns.
        var notice = Array(repeating: "", count: header.count)
        notice[0] = "Report note"
        notice[7] = FoodReactionReport.notice
        rows.append(notice)
        return Data((rows.map { $0.map(CareReportExportService.csvCell).joined(separator: ",") }
            .joined(separator: "\n") + "\n").utf8)
    }

    static func defaultFilename(for report: FoodReactionReport, format: CareReportFormat) -> String {
        let name = report.profileName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Little-Windows-\(name.isEmpty ? "Child" : name)-Food-Reactions-\(formatter.string(from: report.options.startDate))-to-\(formatter.string(from: report.options.endDate)).\(format.fileExtension)"
    }

    static func pdfData(for report: FoodReactionReport) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            let layout = FoodReactionPDFLayout(context: context, bounds: bounds)
            layout.beginPage()
            layout.header(report)
            layout.summary(reactions: report.reactionMealCount, meals: report.mealCount)
            layout.note("About these observations", value: FoodReactionReport.notice, highlighted: true)
            layout.paragraph(report.options.includeMealsWithoutReactions
                ? "Includes foods without reaction details. Each food observation appears separately; meal counts count each meal once."
                : "Only recorded reaction observations are listed. Other foods served in the same meal appear as context.", size: 8.5, muted: true)
            if !report.options.includeNotes {
                layout.paragraph("Free-text notes and response descriptions are excluded.", size: 8.5, muted: true)
            }
            if !report.options.includeCaregiverNames {
                layout.paragraph("Caregiver name fields are excluded.", size: 8.5, muted: true)
            }
            if report.entries.isEmpty {
                layout.note("No observations to show", value: report.options.includeMealsWithoutReactions
                    ? "No saved solid meals were logged in this date range."
                    : "No possible reaction observations were recorded in this date range.")
            }
            for entry in report.entries {
                let zone = TimeZone(identifier: entry.timeZoneIdentifier) ?? .current
                let timestamp = "\(DateFormatting.dayString(from: entry.date, timeZone: zone)) at \(DateFormatting.timeString(from: entry.date, timeZone: zone)) (\(entry.timeZoneIdentifier))"
                layout.observationHeader(food: entry.food, timestamp: timestamp, observation: entry.observation)
                layout.pairedFields([
                    ("Foods served together", entry.mealFoods), ("Recorded allergens", entry.allergens),
                    ("Symptoms", entry.symptoms), ("Recorded severity", entry.severity),
                    ("Onset after meal", entry.onset), ("Duration", entry.duration)
                ])
                layout.pairedFields([
                    ("Response taken", entry.response), ("Follow-up", entry.followUp)
                ].filter { !$0.1.isEmpty })
                layout.pairedFields([
                    ("Food notes", entry.foodNotes), ("Meal notes", entry.mealNotes)
                ].filter { !$0.1.isEmpty })
                if !entry.caregiver.isEmpty {
                    layout.paragraph("Recorded by \(entry.caregiver)", size: 8.5, muted: true)
                }
                layout.space(14)
            }
            layout.footer()
        }
    }

    private static func hasReactionDetails(_ detail: SolidFoodLogDetail) -> Bool {
        detail.suspectedReaction || !detail.symptoms.isEmpty || detail.severity != .unknown
            || detail.onsetMinutes != nil || detail.durationMinutes != nil
            || !detail.responseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || detail.followUp != .none
    }

    private static func recorded(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Not recorded"
        }
        return value
    }

    private static func minutes(_ value: Int?) -> String {
        value.map { "\($0) min" } ?? "Not recorded"
    }

    private static func allergenNames(_ ids: [String]) -> String {
        let names = Set(ids.map { SolidsAllergen(rawValue: $0)?.displayName ?? $0 }).sorted()
        return names.isEmpty ? "Not recorded" : names.joined(separator: ", ")
    }
}

/// Framesetter pagination preserves complete notes, including a single note
/// longer than one page. No summary truncation is applied to exported facts.
@MainActor
private final class FoodReactionPDFLayout {
    let context: UIGraphicsPDFRendererContext
    let bounds: CGRect
    private var y: CGFloat = 44
    private var page = 0
    private let margin: CGFloat = 44
    private var width: CGFloat { bounds.width - 2 * margin }
    private var bottom: CGFloat { bounds.height - 70 }

    private enum Theme {
        static let accent = UIColor.systemIndigo.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        static let ink = UIColor(red: 0.14, green: 0.14, blue: 0.23, alpha: 1)
        static let muted = UIColor(red: 0.40, green: 0.40, blue: 0.48, alpha: 1)
        static let lavender = UIColor(red: 0.95, green: 0.94, blue: 1, alpha: 1)
        static let surface = UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
        static let line = UIColor(red: 0.88, green: 0.87, blue: 0.94, alpha: 1)
    }

    init(context: UIGraphicsPDFRendererContext, bounds: CGRect) {
        self.context = context
        self.bounds = bounds
    }

    func beginPage() {
        context.beginPage()
        page += 1
        y = margin
        if page > 1 {
            fixed("Little Windows", rect: CGRect(x: margin, y: y, width: 200, height: 15),
                  font: font(10, bold: true), color: Theme.accent)
            fixed("Food Reaction Report / continued", rect: CGRect(x: margin + 235, y: y, width: width - 235, height: 15),
                  font: font(9), color: Theme.muted, alignment: .right)
            y += 24
        }
    }

    func ensureRoom(_ height: CGFloat) {
        if y + height > bottom {
            footer()
            beginPage()
        }
    }

    func space(_ amount: CGFloat) { y += amount }

    func header(_ report: FoodReactionReport) {
        let rect = CGRect(x: margin, y: y, width: width, height: 86)
        card(rect, fill: Theme.lavender, radius: 18)
        let iconRect = CGRect(x: rect.minX + 16, y: rect.minY + 22, width: 48, height: 48)
        if let logo = UIImage(named: "BrandLogo") {
            context.cgContext.saveGState()
            UIBezierPath(roundedRect: iconRect, cornerRadius: 12).addClip()
            logo.draw(in: iconRect)
            context.cgContext.restoreGState()
        }
        let x = rect.minX + 78
        fixed("Little Windows", rect: CGRect(x: x, y: rect.minY + 18, width: width - 96, height: 18),
              font: font(12, bold: true), color: Theme.accent)
        fixed("Food Reaction Report", rect: CGRect(x: x, y: rect.minY + 36, width: width - 96, height: 32),
              font: font(24, bold: true), color: Theme.ink)
        fixed("Meals, observations & follow-up", rect: CGRect(x: x, y: rect.minY + 67, width: width - 96, height: 16),
              font: font(9), color: Theme.muted)
        y = rect.maxY + 10
        paragraph(report.profileName, size: 17, bold: true)
        paragraph("\(report.options.startDate.formatted(date: .abbreviated, time: .omitted)) to \(report.options.endDate.formatted(date: .abbreviated, time: .omitted))", size: 10, muted: true)
        paragraph("Prepared \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))", size: 8, muted: true)
        space(4)
    }

    func summary(reactions: Int, meals: Int) {
        ensureRoom(60)
        let gap: CGFloat = 10
        let cellWidth = (width - gap) / 2
        for (index, metric) in [("Meals with possible reactions", reactions), ("Solid meals logged", meals)].enumerated() {
            let rect = CGRect(x: margin + CGFloat(index) * (cellWidth + gap), y: y, width: cellWidth, height: 50)
            card(rect, fill: index == 0 ? Theme.lavender : Theme.surface)
            fixed("\(metric.1)", rect: CGRect(x: rect.minX + 14, y: rect.minY + 5, width: cellWidth - 28, height: 26),
                  font: font(21, bold: true), color: index == 0 ? Theme.accent : Theme.ink)
            fixed(metric.0, rect: CGRect(x: rect.minX + 14, y: rect.minY + 33, width: cellWidth - 28, height: 14),
                  font: font(8.5), color: Theme.muted)
        }
        y += 60
    }

    func observationHeader(food: String, timestamp: String, observation: String) {
        ensureRoom(170)
        space(6)
        let title = attributed(food, size: 16, bold: true)
        title.append(attributed("\n\(timestamp)", size: 8.5, muted: true))
        title.append(attributed("\n\(observation)", size: 9, bold: true, color: Theme.accent))
        flow(title, inset: 11, fill: Theme.lavender)
    }

    func pairedFields(_ fields: [(String, String)]) {
        let gap: CGFloat = 6
        var index = 0
        while index < fields.count {
            let pair = Array(fields[index..<min(index + 2, fields.count)])
            let cellWidth = pair.count == 1 ? width : (width - gap) / 2
            let texts = pair.map { label, value in
                let text = attributed(label.uppercased(), size: 7.5, bold: true, color: Theme.muted)
                text.append(attributed("\n\(value)", size: 10, bold: true))
                return text
            }
            let heights = texts.map { measured($0, width: cellWidth - 24) }
            let height = max(37, (heights.max() ?? 0) + 16)
            if height > 500 {
                // Arbitrarily long food lists and symptom text still retain
                // every character by using the same paginated note layout.
                for (label, value) in pair { note(label, value: value) }
            } else {
                ensureRoom(height + 6)
                for (column, text) in texts.enumerated() {
                    let rect = CGRect(x: margin + CGFloat(column) * (cellWidth + gap), y: y, width: cellWidth, height: height)
                    card(rect, fill: Theme.surface)
                    text.draw(in: rect.insetBy(dx: 12, dy: 8))
                }
                y += height + 6
            }
            index += 2
        }
    }

    func note(_ label: String, value: String, highlighted: Bool = false) {
        let text = attributed(label, size: 8.5, bold: true, color: highlighted ? Theme.accent : Theme.muted)
        text.append(attributed("\n\(value)", size: 9))
        flow(text, inset: 10, fill: highlighted ? Theme.lavender : Theme.surface)
    }

    func paragraph(_ text: String, size: CGFloat, bold: Bool = false, muted: Bool = false) {
        flow(attributed(text, size: size, bold: bold, muted: muted))
    }

    private func attributed(
        _ text: String, size: CGFloat, bold: Bool = false, muted: Bool = false, color: UIColor? = nil
    ) -> NSMutableAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 2
        style.lineBreakMode = .byWordWrapping
        return NSMutableAttributedString(string: text, attributes: [
            .font: font(size, bold: bold), .foregroundColor: color ?? (muted ? Theme.muted : Theme.ink),
            .paragraphStyle: style
        ])
    }

    private func flow(_ attributed: NSAttributedString, inset: CGFloat = 0, fill: UIColor? = nil) {
        let textWidth = width - inset * 2
        let fullHeight = measured(attributed, width: textWidth) + inset * 2 + 7
        if fullHeight < 580 { ensureRoom(fullHeight) }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var offset = 0
        while offset < attributed.length {
            ensureRoom(min(fullHeight, 40 + inset * 2))
            let remaining = CFRange(location: offset, length: attributed.length - offset)
            let available = CGRect(x: margin + inset, y: bounds.height - bottom + inset,
                                   width: textWidth, height: bottom - y - inset * 2)
            let frame = CTFramesetterCreateFrame(framesetter, remaining, CGPath(rect: available, transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { return }
            let used = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, visible, nil, CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil
            )
            let blockHeight = ceil(used.height) + inset * 2
            if let fill {
                card(CGRect(x: margin, y: y, width: width, height: blockHeight), fill: fill)
            }
            let cg = context.cgContext
            cg.saveGState()
            cg.textMatrix = .identity
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, cg)
            cg.restoreGState()
            y += blockHeight + (fill == nil ? 5 : 8)
            offset += visible.length
            if offset < attributed.length {
                footer()
                beginPage()
            }
        }
    }

    func footer() {
        Theme.line.setFill()
        UIRectFill(CGRect(x: margin, y: bounds.height - 55, width: width, height: 0.5))
        let text = "Little Windows food reaction report | Page \(page)"
        (text as NSString).draw(at: CGPoint(x: margin, y: bounds.height - 44), withAttributes: [
            .font: font(8), .foregroundColor: Theme.muted
        ])
    }

    private func card(_ rect: CGRect, fill: UIColor, radius: CGFloat = 11) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fill.setFill()
        path.fill()
        Theme.line.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: rounded, size: size)
    }

    private func measured(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    private func fixed(
        _ text: String, rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ])
    }
}
