import Foundation

enum DurationFormatting {
    static func string(seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    static func liveString(seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}

enum DateFormatting {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static func window(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let startText = time.string(from: start)
        let endText = time.string(from: end)
        guard end > start else { return startText }
        if endText == startText {
            if calendar.isDate(start, equalTo: end, toGranularity: .minute) {
                return startText
            }
            return "\(day.string(from: start)) \(startText)-\(day.string(from: end)) \(endText)"
        }
        return "\(startText)-\(endText)"
    }

    static func age(from birthDate: Date, to date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: birthDate, to: date)
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 { return "\(years)y \(months)m old" }
        if months > 0 { return "\(months) months old" }
        let weeks = max(0, (components.day ?? 0) / 7)
        return weeks > 0 ? "\(weeks) weeks old" : "Newborn"
    }
}

extension Calendar {
    func startOfNextDay(for date: Date) -> Date {
        self.date(byAdding: .day, value: 1, to: startOfDay(for: date)) ?? date
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
