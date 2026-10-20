import Foundation

/// Optional context attached to one sleep event, separate from body temperature.
struct SleepConditions: Codable, Equatable, Sendable {
    var outdoorHighCelsius: Double?
    var outdoorLowCelsius: Double?
    var weatherDate: Date?
    var weatherTimeZoneIdentifier: String?
    var weatherLocationName: String?
    var forecastFetchedAt: Date?
    var usedSleepSack: Bool?
    var sleepSackTOG: Double?
    var automaticallyUsesWeather: Bool?

    var isEmpty: Bool {
        outdoorHighCelsius == nil && outdoorLowCelsius == nil && usedSleepSack == nil
            && automaticallyUsesWeather != false
    }

    var isValid: Bool {
        let temperatures = [outdoorHighCelsius, outdoorLowCelsius].compactMap { $0 }
        return temperatures.allSatisfy { $0.isFinite && (-100...70).contains($0) }
            && !(outdoorHighCelsius.map { high in outdoorLowCelsius.map { $0 > high } ?? false } ?? false)
            && (sleepSackTOG.map { $0.isFinite && (0...10).contains($0) && usedSleepSack == true } ?? true)
    }

    var summary: String {
        formattedSummary(unit: OutdoorTemperatureSettings.preferredUnit())
    }

    func formattedSummary(unit: TemperatureUnit) -> String {
        var parts = [String]()
        if let high = outdoorHighCelsius { parts.append("High \(OutdoorTemperatureFormatting.string(high, unit: unit))") }
        if let low = outdoorLowCelsius { parts.append("Low \(OutdoorTemperatureFormatting.string(low, unit: unit))") }
        if let usedSleepSack {
            if usedSleepSack {
                parts.append(sleepSackTOG.map { "Sleep sack · \($0.formatted()) TOG" } ?? "Sleep sack")
            } else {
                parts.append("No sleep sack")
            }
        }
        return parts.joined(separator: " · ")
    }
}

enum OutdoorTemperatureSettings {
    static let unitKey = "outdoorTemperatureUnit"

    static func preferredUnit(defaults: UserDefaults = .standard, locale: Locale = .current) -> TemperatureUnit {
        defaults.string(forKey: unitKey).flatMap(TemperatureUnit.init(rawValue:))
            ?? (locale.measurementSystem == .us ? .fahrenheit : .celsius)
    }
}

enum OutdoorTemperatureFormatting {
    static func date(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func string(_ celsius: Double, unit: TemperatureUnit? = nil) -> String {
        let chosen = unit ?? OutdoorTemperatureSettings.preferredUnit()
        let value = chosen == .celsius ? celsius : celsius * 9 / 5 + 32
        return "\(value.formatted(.number.precision(.fractionLength(0...1))))\(chosen.displayName)"
    }
}

enum SleepSackUsage: String, CaseIterable, Identifiable {
    case notLogged = "Not logged"
    case used = "Used"
    case notUsed = "Not used"
    var id: String { rawValue }
}

struct SleepConditionsDraft {
    var highText: String
    var lowText: String
    var togText: String
    var sackUsage: SleepSackUsage
    var unit: TemperatureUnit
    var provenance: SleepConditions

    init(_ details: SleepConditions? = nil, unit: TemperatureUnit? = nil) {
        let details = details ?? SleepConditions()
        self.unit = unit ?? OutdoorTemperatureSettings.preferredUnit()
        provenance = details
        func text(_ celsius: Double?) -> String {
            guard let celsius else { return "" }
            let value = self.unit == .celsius ? celsius : celsius * 9 / 5 + 32
            return value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
        }
        highText = ""
        lowText = ""
        togText = details.sleepSackTOG.map { $0.formatted(.number.grouping(.never)) } ?? ""
        sackUsage = details.usedSleepSack.map { $0 ? .used : .notUsed } ?? .notLogged
        highText = text(details.outdoorHighCelsius)
        lowText = text(details.outdoorLowCelsius)
    }

    var usesAutomaticWeather: Bool {
        get { provenance.automaticallyUsesWeather ?? (provenance.forecastFetchedAt != nil || (highText.isEmpty && lowText.isEmpty)) }
        set { provenance.automaticallyUsesWeather = newValue }
    }

    mutating func invalidateAutomaticWeather(for date: Date, locationName: String?) {
        guard usesAutomaticWeather, provenance.forecastFetchedAt != nil,
              let recordedDate = provenance.weatherDate else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = provenance.weatherTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let changedCity = locationName.map { $0 != provenance.weatherLocationName } ?? false
        guard !calendar.isDate(recordedDate, inSameDayAs: date) || changedCity else { return }
        highText = ""
        lowText = ""
        provenance.outdoorHighCelsius = nil
        provenance.outdoorLowCelsius = nil
        provenance.forecastFetchedAt = nil
        provenance.weatherDate = nil
        provenance.weatherLocationName = nil
        provenance.weatherTimeZoneIdentifier = nil
    }

    mutating func fillFromWeather(_ conditions: SleepConditions?) {
        guard usesAutomaticWeather, let conditions else { return }
        self = SleepConditionsDraft(conditions, unit: unit)
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? Double(trimmed, format: .number.locale(.current), lenient: false)
    }

    var validationMessage: String? {
        for text in [highText, lowText] where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let number = Self.number(text), number.isFinite else { return "Enter a valid outdoor temperature, or leave it blank." }
        }
        if sackUsage == .used, !togText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let tog = Self.number(togText), tog.isFinite, (0...10).contains(tog) else {
                return "Enter a TOG rating between 0 and 10, or leave it blank if unknown."
            }
        }
        guard details.isValid else { return "Check the temperatures. The high must be at least the low, and both must be between −100°C and 70°C." }
        return nil
    }

    var details: SleepConditions {
        var value = provenance
        func celsius(_ text: String) -> Double? {
            Self.number(text).map { unit == .celsius ? $0 : ($0 - 32) * 5 / 9 }
        }
        value.outdoorHighCelsius = celsius(highText)
        value.outdoorLowCelsius = celsius(lowText)
        value.usedSleepSack = sackUsage == .notLogged ? nil : sackUsage == .used
        value.sleepSackTOG = sackUsage == .used ? Self.number(togText) : nil
        if value.outdoorHighCelsius == nil && value.outdoorLowCelsius == nil {
            value.weatherDate = nil
            value.weatherTimeZoneIdentifier = nil
            value.weatherLocationName = nil
            value.forecastFetchedAt = nil
        }
        return value
    }

    mutating func changeUnit(to unit: TemperatureUnit) {
        guard validationMessage == nil else { return }
        self = SleepConditionsDraft(details, unit: unit)
    }
}
