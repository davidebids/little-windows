import Foundation
import SwiftData

enum EventTimerState: String, Codable {
    case running
    case stopped
}

enum CareTimeZoneMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual override"
        }
    }
}

enum CareTimeZoneSettings {
    static let modeKey = "careTimeZoneMode"
    static let manualIdentifierKey = "careTimeZoneManualIdentifier"

    static func effectiveTimeZone(
        defaults: UserDefaults = .standard,
        automaticTimeZone: TimeZone = .autoupdatingCurrent
    ) -> TimeZone {
        let mode = CareTimeZoneMode(rawValue: defaults.string(forKey: modeKey) ?? "")
            ?? .automatic
        guard mode == .manual,
              let identifier = defaults.string(forKey: manualIdentifierKey),
              let selected = TimeZone(identifier: identifier) else {
            return automaticTimeZone
        }
        return selected
    }

    static func effectiveIdentifier(
        defaults: UserDefaults = .standard,
        automaticTimeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        effectiveTimeZone(defaults: defaults, automaticTimeZone: automaticTimeZone).identifier
    }

    static func displayName(for timeZone: TimeZone, on date: Date = Date()) -> String {
        let city = timeZone.identifier
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "_", with: " ")
            ?? timeZone.identifier
        let abbreviation = timeZone.abbreviation(for: date) ?? gmtOffsetText(for: timeZone, on: date)
        return "\(city) (\(abbreviation))"
    }

    static func gmtOffsetText(for timeZone: TimeZone, on date: Date = Date()) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let absoluteMinutes = abs(seconds) / 60
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        return minutes == 0
            ? "GMT\(sign)\(hours)"
            : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    static func normalizedLocalDay(
        for date: Date,
        timeZone: TimeZone,
        calendar: Calendar = .current
    ) -> Date {
        var sourceCalendar = calendar
        sourceCalendar.timeZone = timeZone
        let components = sourceCalendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

@Model
final class BabyEvent {
    var id: UUID = UUID()
    var profileID: UUID?
    var profileTypeSnapshotRawValue: String?
    var typeRawValue: String = EventType.custom.rawValue
    var title: String?
    var startDate: Date = Date()
    var endDate: Date?
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var caregiverName: String?
    var notes: String?

    var sleepKindRawValue: String?
    var feedKindRawValue: String?
    var amountOz: Double?
    var foodDescription: String?
    var solidReactionRawValue: String?
    var solidTextureRawValue: String?
    var solidFeedingStyleRawValue: String?
    var solidAllergenExposure: Bool?
    var solidSensitivityObserved: Bool?
    var nursingSideRawValue: String?
    var activeNursingSideRawValue: String?
    var timerStateRawValue: String?
    var timerAccumulatedSeconds: Double?
    var activeTimerSegmentStartDate: Date?
    var leftDurationSeconds: Double?
    var rightDurationSeconds: Double?
    var diaperKindRawValue: String?
    var childPottyKindRawValue: String?
    var childPottyLocationRawValue: String?
    var childPottyAccident: Bool?
    var peeAmountRawValue: String?
    var pooAmountRawValue: String?
    var pooColorRawValue: String?
    var pooTextureRawValue: String?
    var stoolColor: String?
    var stoolTexture: String?
    var bookTitle: String?
    var medicineName: String?
    var dose: Double?
    var doseUnit: String?
    var reason: String?
    var activityTypeRawValue: String?
    var heightFeet: Int?
    var heightInches: Double?
    var weightPounds: Int?
    var weightOunces: Double?
    var headCircumferenceInches: Double?
    var growthSexRawValue: String?
    var growthSourceRawValue: String?
    var weightKilograms: Double?
    var lengthCentimeters: Double?
    var headCircumferenceCentimeters: Double?
    var temperatureCelsius: Double?
    var temperatureUnitRawValue: String?
    var temperatureMethodRawValue: String?
    var dogDetailsData: Data?

    init(
        id: UUID = UUID(),
        profileID: UUID? = nil,
        type: EventType,
        title: String? = nil,
        startDate: Date = Date(),
        endDate: Date? = nil,
        startTimeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        caregiverName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.typeRawValue = type.rawValue
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
            ?? (endDate == nil ? nil : startTimeZoneIdentifier)
        self.createdAt = Date()
        self.updatedAt = Date()
        self.caregiverName = caregiverName
        self.notes = notes
    }

    var type: EventType {
        get { EventType.normalized(rawValue: typeRawValue) }
        set { typeRawValue = newValue.rawValue }
    }

    var startTimeZone: TimeZone {
        startTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    var endTimeZone: TimeZone {
        endTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? startTimeZone
    }

    var spansTimeZones: Bool {
        guard endDate != nil else { return false }
        return startTimeZone.identifier != endTimeZone.identifier
    }

    var shouldShowTimeZoneInTimeline: Bool {
        guard startTimeZoneIdentifier != nil else { return false }
        return spansTimeZones || startTimeZone.identifier != TimeZone.autoupdatingCurrent.identifier
    }

    func localStartDay(calendar: Calendar = .current) -> Date {
        CareTimeZoneSettings.normalizedLocalDay(
            for: startDate,
            timeZone: startTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                ?? calendar.timeZone,
            calendar: calendar
        )
    }

    func localEndDay(calendar: Calendar = .current) -> Date? {
        endDate.map {
            CareTimeZoneSettings.normalizedLocalDay(
                for: $0,
                timeZone: endTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                    ?? startTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                    ?? calendar.timeZone,
                calendar: calendar
            )
        }
    }

    func occursOnLocalDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        localStartDay(calendar: calendar) == calendar.startOfDay(for: date)
    }

    func localStartMinute(calendar: Calendar = .current) -> Double {
        var localCalendar = calendar
        localCalendar.timeZone = startTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? calendar.timeZone
        let components = localCalendar.dateComponents([.hour, .minute, .second], from: startDate)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
    }

    func localEndMinute(calendar: Calendar = .current) -> Double? {
        guard let endDate else { return nil }
        var localCalendar = calendar
        localCalendar.timeZone = endTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? startTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? calendar.timeZone
        let components = localCalendar.dateComponents([.hour, .minute, .second], from: endDate)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
    }

    /// Rebuilds the recorded local wall-clock date in the supplied calendar's
    /// time zone. This is for day-based charts and sorting, not elapsed-time math.
    func normalizedLocalStartDate(calendar: Calendar = .current) -> Date {
        let day = localStartDay(calendar: calendar)
        return calendar.date(
            byAdding: .second,
            value: Int((localStartMinute(calendar: calendar) * 60).rounded()),
            to: day
        ) ?? day
    }

    var profileTypeSnapshot: CareProfileType? {
        get { profileTypeSnapshotRawValue.flatMap(CareProfileType.init(rawValue:)) }
        set { profileTypeSnapshotRawValue = newValue?.rawValue }
    }

    var dogDetails: DogEventDetails {
        get {
            guard let dogDetailsData,
                  let value = try? JSONDecoder().decode(DogEventDetails.self, from: dogDetailsData) else {
                return DogEventDetails()
            }
            return value
        }
        set {
            dogDetailsData = try? JSONEncoder().encode(newValue)
        }
    }

    var sleepKind: SleepKind? {
        get { sleepKindRawValue.flatMap(SleepKind.init(rawValue:)) }
        set { sleepKindRawValue = newValue?.rawValue }
    }

    var feedKind: FeedKind? {
        get { feedKindRawValue.flatMap(FeedKind.init(rawValue:)) }
        set { feedKindRawValue = newValue?.rawValue }
    }

    var solidReaction: SolidReaction? {
        get { solidReactionRawValue.flatMap(SolidReaction.init(rawValue:)) }
        set { solidReactionRawValue = newValue?.rawValue }
    }

    var solidTexture: SolidTexture? {
        get { solidTextureRawValue.flatMap(SolidTexture.init(rawValue:)) }
        set { solidTextureRawValue = newValue?.rawValue }
    }

    var solidFeedingStyle: SolidFeedingStyle? {
        get { solidFeedingStyleRawValue.flatMap(SolidFeedingStyle.init(rawValue:)) }
        set { solidFeedingStyleRawValue = newValue?.rawValue }
    }

    var nursingSide: NursingSide? {
        get {
            if let side = nursingSideRawValue.flatMap(NursingSide.init(rawValue:)) {
                return side
            }
            guard type == .nursing else { return nil }
            return (rightDurationSeconds ?? 0) > (leftDurationSeconds ?? 0) ? .right : .left
        }
        set { nursingSideRawValue = newValue?.rawValue }
    }

    var activeNursingSide: NursingSide? {
        get {
            activeNursingSideRawValue.flatMap(NursingSide.init(rawValue:))
                ?? (isTimerDraft && type == .nursing ? nursingSide : nil)
        }
        set { activeNursingSideRawValue = newValue?.rawValue }
    }

    var diaperKind: DiaperKind? {
        get { diaperKindRawValue.flatMap(DiaperKind.init(rawValue:)) }
        set { diaperKindRawValue = newValue?.rawValue }
    }

    var childPottyKind: ChildPottyKind? {
        get { childPottyKindRawValue.flatMap(ChildPottyKind.init(rawValue:)) }
        set { childPottyKindRawValue = newValue?.rawValue }
    }

    var childPottyLocation: ChildPottyLocation? {
        get { childPottyLocationRawValue.flatMap(ChildPottyLocation.init(rawValue:)) }
        set { childPottyLocationRawValue = newValue?.rawValue }
    }

    var peeAmount: DiaperAmount? {
        get { peeAmountRawValue.flatMap(DiaperAmount.init(rawValue:)) }
        set { peeAmountRawValue = newValue?.rawValue }
    }

    var pooAmount: DiaperAmount? {
        get { pooAmountRawValue.flatMap(DiaperAmount.init(rawValue:)) }
        set { pooAmountRawValue = newValue?.rawValue }
    }

    var pooColor: PooColor? {
        get {
            pooColorRawValue.flatMap(PooColor.init(rawValue:))
                ?? stoolColor.flatMap { PooColor(rawValue: $0.lowercased()) }
        }
        set { pooColorRawValue = newValue?.rawValue }
    }

    var pooTexture: PooTexture? {
        get {
            pooTextureRawValue.flatMap(PooTexture.init(rawValue:))
                ?? stoolTexture.flatMap { PooTexture(rawValue: $0.lowercased()) }
        }
        set { pooTextureRawValue = newValue?.rawValue }
    }

    var activityType: ActivityType? {
        get {
            activityTypeRawValue.flatMap(ActivityType.init(rawValue:))
                ?? ActivityType.legacyType(rawValue: typeRawValue)
        }
        set { activityTypeRawValue = newValue?.rawValue }
    }

    var medicineUnit: MedicineUnit? {
        get { doseUnit.flatMap(MedicineUnit.init(rawValue:)) }
        set { doseUnit = newValue?.rawValue }
    }

    var temperatureUnit: TemperatureUnit {
        get {
            temperatureUnitRawValue.flatMap(TemperatureUnit.init(rawValue:))
                ?? .fahrenheit
        }
        set { temperatureUnitRawValue = newValue.rawValue }
    }

    var temperatureMethod: TemperatureMethod? {
        get { temperatureMethodRawValue.flatMap(TemperatureMethod.init(rawValue:)) }
        set { temperatureMethodRawValue = newValue?.rawValue }
    }

    var totalHeightInches: Double? {
        if let lengthCentimeters {
            return lengthCentimeters / GrowthUnitConversion.centimetersPerInch
        }
        guard heightFeet != nil || heightInches != nil else { return nil }
        return Double(heightFeet ?? 0) * 12 + (heightInches ?? 0)
    }

    var totalWeightOunces: Double? {
        if let weightKilograms {
            return weightKilograms / GrowthUnitConversion.kilogramsPerPound * 16
        }
        guard weightPounds != nil || weightOunces != nil else { return nil }
        return Double(weightPounds ?? 0) * 16 + (weightOunces ?? 0)
    }

    var growthSex: BabySex {
        get { growthSexRawValue.flatMap(BabySex.init(rawValue:)) ?? .unknown }
        set { growthSexRawValue = newValue.rawValue }
    }

    var growthSource: GrowthMeasurementSource? {
        get { growthSourceRawValue.flatMap(GrowthMeasurementSource.init(rawValue:)) }
        set { growthSourceRawValue = newValue?.rawValue }
    }

    var canonicalWeightKilograms: Double? {
        if let weightKilograms { return weightKilograms }
        guard let totalWeightOunces else { return nil }
        return totalWeightOunces / 16 * GrowthUnitConversion.kilogramsPerPound
    }

    var canonicalLengthCentimeters: Double? {
        if let lengthCentimeters { return lengthCentimeters }
        guard heightFeet != nil || heightInches != nil else { return nil }
        return GrowthUnitConversion.feetAndInchesToCentimeters(
            feet: heightFeet ?? 0,
            inches: heightInches ?? 0
        )
    }

    var canonicalHeadCircumferenceCentimeters: Double? {
        headCircumferenceCentimeters
            ?? headCircumferenceInches.map(GrowthUnitConversion.inchesToCentimeters)
    }

    func canonicalMeasurement(for chartType: GrowthChartType) -> Double? {
        switch chartType {
        case .weightForAge: canonicalWeightKilograms
        case .lengthForAge: canonicalLengthCentimeters
        case .headCircumferenceForAge: canonicalHeadCircumferenceCentimeters
        }
    }

    func temperatureValue(in unit: TemperatureUnit) -> Double? {
        guard let temperatureCelsius else { return nil }
        return unit == .celsius ? temperatureCelsius : temperatureCelsius * 9 / 5 + 32
    }

    var duration: TimeInterval? {
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSince(startDate))
    }

    var isSleepBlock: Bool {
        type == .sleep && sleepKind != .nightWaking
    }

    var isNightWaking: Bool {
        type == .sleep && sleepKind == .nightWaking
    }

    var totalNursingDurationSeconds: Double {
        (leftDurationSeconds ?? 0) + (rightDurationSeconds ?? 0)
    }

    var timelineDurationDescription: String? {
        if type == .nursing, totalNursingDurationSeconds > 0 {
            return DurationFormatting.string(seconds: totalNursingDurationSeconds)
        }
        guard let duration, duration >= 60 else { return nil }
        return DurationFormatting.string(seconds: duration)
    }

    var timerState: EventTimerState? {
        get {
            guard isTimerDraft else { return nil }
            return timerStateRawValue.flatMap(EventTimerState.init(rawValue:))
                ?? .running
        }
        set {
            timerStateRawValue = newValue?.rawValue
        }
    }

    var isTimerDraft: Bool {
        endDate == nil && type.supportsTimer
    }

    var isActiveTimer: Bool {
        isTimerDraft
    }

    var isTimerRunning: Bool {
        isTimerDraft && timerState != .stopped
    }

    func timerElapsed(at date: Date = Date()) -> TimeInterval {
        guard isTimerDraft else { return duration ?? 0 }
        let accumulated = timerAccumulatedSeconds ?? 0
        guard isTimerRunning else { return accumulated }
        let segmentStart = activeTimerSegmentStartDate ?? startDate
        return accumulated + max(0, date.timeIntervalSince(segmentStart))
    }

    func timerDisplayStartDate(at date: Date = Date()) -> Date {
        date.addingTimeInterval(-timerElapsed(at: date))
    }

    var displayTitle: String {
        return switch type {
        case .sleep: sleepKind?.displayName ?? type.displayName
        case .feed:
            if feedKind == .solid { "Solid: \(solidSummary)" } else { feedKind?.displayName ?? type.displayName }
        case .nursing:
            nursingSide.map { "\($0.displayName) nursing" } ?? type.displayName
        case .pumping:
            "Pumping\(pumpingSummary)"
        case .diaper:
            diaperSummary
        case .medicine:
            "Medicine: \(medicineSummary)"
        case .growth:
            "Growth: \(growthSummary)"
        case .temperature:
            "Temperature: \(temperatureSummary)"
        case .activity:
            if activityType == .custom {
                nonBlankTitle ?? ActivityType.custom.displayName
            } else {
                activityType?.displayName ?? type.displayName
            }
        case .food:
            "Food: \(dogFoodSummary)"
        case .water:
            "Water\(dogWaterSummary)"
        case .treat:
            "Treat\(dogTreatSummary)"
        case .potty:
            profileTypeSnapshot == .dog ? dogPottySummary : childPottySummary
        case .walk:
            dogWalkSummary
        case .rest:
            dogRestSummary
        case .training:
            "Training: \(dogTrainingSummary)"
        case .grooming:
            dogGroomingSummary
        case .symptom:
            "Symptom: \(dogSymptomSummary)"
        case .vaccine:
            "Vaccine: \(dogVaccineSummary)"
        case .glucose:
            "Glucose: \(dogGlucoseSummary)"
        case .custom:
            nonBlankTitle ?? type.displayName
        }
    }

    private var nonBlankTitle: String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private var medicineSummary: String {
        let trimmedName = medicineName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName?.isEmpty == false ? trimmedName! : "Medicine"
        guard let dose else { return name }
        let amount = dose.formatted(.number.precision(.fractionLength(0...2)))
        return "\(name), \(amount) \(medicineUnit?.displayName ?? doseUnit ?? "")"
            .trimmingCharacters(in: .whitespaces)
    }

    private var pumpingSummary: String {
        guard let amountOz, amountOz > 0 else { return "" }
        let amount = amountOz.formatted(.number.precision(.fractionLength(0...1)))
        return ": \(amount) oz"
    }

    private var solidSummary: String {
        var values: [String] = []
        if let food = foodDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !food.isEmpty {
            values.append(food)
        }
        if let solidTexture, solidTexture != .unknown {
            values.append(solidTexture.displayName.lowercased())
        }
        if let solidFeedingStyle, solidFeedingStyle != .unknown {
            values.append(solidFeedingStyle.displayName.lowercased())
        }
        if let solidReaction, solidReaction != .unknown {
            values.append(solidReaction.displayName.lowercased())
        }
        if solidAllergenExposure == true {
            values.append("allergen")
        }
        if solidSensitivityObserved == true {
            values.append("sensitivity noted")
        }
        return values.isEmpty ? "Solid" : values.joined(separator: " · ")
    }

    private var diaperSummary: String {
        guard let diaperKind else { return type.displayName }
        switch diaperKind {
        case .wet:
            let amount = optionalDiaperAmount(peeAmount)
            return "Diaper: pee\(amount)"
        case .dirty:
            return "Diaper: poo\(pooDetails)"
        case .both:
            let pee = peeAmount.map { "pee \($0.displayName.lowercased())" } ?? "pee"
            let poo = "poo" + (pooDetailWords.isEmpty ? "" : " \(pooDetailWords.joined(separator: " "))")
            return "Diaper: mixed — \(pee), \(poo)"
        }
    }

    private var childPottySummary: String {
        guard let childPottyKind else { return "Potty" }
        var details = [childPottyKind.displayName.lowercased()]
        if let childPottyLocation {
            details.append(childPottyLocation.displayName.lowercased())
        }
        if childPottyAccident == true {
            details.append("accident")
        }
        return "Potty: \(details.joined(separator: " · "))"
    }

    private func optionalDiaperAmount(_ amount: DiaperAmount?) -> String {
        guard let amount, amount != .unknown else { return "" }
        return ", \(amount.displayName.lowercased())"
    }

    private var pooDetails: String {
        pooDetailWords.isEmpty ? "" : ", \(pooDetailWords.joined(separator: ", "))"
    }

    private var pooDetailWords: [String] {
        var values: [String] = []
        if let pooAmount, pooAmount != .unknown {
            values.append(pooAmount.displayName.lowercased())
        }
        if let pooColor, pooColor != .unknown {
            values.append(pooColor.displayName.lowercased())
        }
        if let pooTexture, pooTexture != .unknown {
            values.append(pooTexture.displayName.lowercased())
        }
        return values
    }

    private var growthSummary: String {
        var parts: [String] = []
        if let totalWeightOunces {
            let pounds = Int(totalWeightOunces / 16)
            let ounces = totalWeightOunces.truncatingRemainder(dividingBy: 16)
            parts.append("\(pounds) lb \(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz")
        }
        if let totalHeightInches {
            parts.append("\(totalHeightInches.formatted(.number.precision(.fractionLength(0...1)))) in")
        }
        if let headCircumference = canonicalHeadCircumferenceCentimeters {
            let inches = headCircumference / GrowthUnitConversion.centimetersPerInch
            parts.append("HC \(inches.formatted(.number.precision(.fractionLength(0...1)))) in")
        }
        return parts.isEmpty ? type.displayName : parts.joined(separator: " · ")
    }

    private var temperatureSummary: String {
        guard let value = temperatureValue(in: temperatureUnit) else {
            return type.displayName
        }
        let method = temperatureMethod.flatMap { $0 == .unknown ? nil : $0.displayName.lowercased() }
        return "\(value.formatted(.number.precision(.fractionLength(1))))\(temperatureUnit.displayName)"
            + (method.map { ", \($0)" } ?? "")
    }

    private var dogFoodSummary: String {
        let details = dogDetails
        var parts: [String] = []
        if let meal = details.mealType, meal != .other {
            parts.append(meal.displayName.lowercased())
        }
        if let name = details.foodName?.nilIfBlank {
            parts.append(name)
        }
        if let amount = details.foodAmount, let unit = details.foodUnit {
            parts.append("\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit.displayName.lowercased())")
        }
        if let eaten = details.eatenAmount, eaten != .unknown {
            parts.append("\(eaten.displayName.lowercased()) eaten")
        }
        return parts.isEmpty ? "Food" : parts.joined(separator: ", ")
    }

    private var dogWaterSummary: String {
        let details = dogDetails
        guard let amount = details.waterAmount, let unit = details.waterUnit else {
            return ""
        }
        return ": \(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit.displayName)"
    }

    private var dogTreatSummary: String {
        let details = dogDetails
        var parts: [String] = []
        if let name = details.treatName?.nilIfBlank {
            parts.append(name)
        }
        if let quantity = details.treatQuantity {
            parts.append(quantity.formatted(.number.precision(.fractionLength(0...1))))
        }
        return parts.isEmpty ? "" : ": \(parts.joined(separator: ", "))"
    }

    private var dogPottySummary: String {
        let details = dogDetails
        let type = details.pottyType ?? .pee
        let location = details.pottyLocation
        if details.accident == true || location == .indoorAccident || location == .crateAccident {
            return "Accident: \(type.displayName.lowercased())"
        }
        var parts = [type == .both ? "mixed" : type.displayName.lowercased()]
        if let location, location != .other {
            parts.append(location.displayName.lowercased())
        }
        if type.hasPoop {
            if let quality = details.stoolQuality, quality != .unknown {
                parts.append(quality.displayName.lowercased())
            }
            if let color = details.poopColor, color != .unknown {
                parts.append(color.displayName.lowercased())
            }
        }
        return "Potty: \(parts.joined(separator: ", "))"
    }

    private var dogWalkSummary: String {
        let details = dogDetails
        var parts: [String] = []
        if let duration = duration, duration >= 60 {
            parts.append(DurationFormatting.string(seconds: duration))
        }
        if let distance = details.distance, let unit = details.distanceUnit {
            parts.append("\(distance.formatted(.number.precision(.fractionLength(0...2)))) \(unit.displayName)")
        }
        if let peeCount = details.peeCount, peeCount > 0 {
            parts.append("\(peeCount) pee")
        }
        if let poopCount = details.poopCount, poopCount > 0 {
            parts.append("\(poopCount) poop")
        }
        if let behavior = details.leashBehavior, behavior != .unknown {
            parts.append(behavior.displayName.lowercased())
        }
        return parts.isEmpty ? "Walk" : parts.joined(separator: ", ")
    }

    private var dogRestSummary: String {
        let details = dogDetails
        let type = details.restType ?? .nap
        let durationText = duration.flatMap { $0 >= 60 ? DurationFormatting.string(seconds: $0) : nil }
        if type == .crate {
            return ["Crate rest", durationText].compactMap { $0 }.joined(separator: ": ")
        }
        return ["Rest: \(type.displayName.lowercased())", durationText].compactMap { $0 }.joined(separator: ", ")
    }

    private var dogTrainingSummary: String {
        let details = dogDetails
        var parts: [String] = []
        if let skill = details.trainingSkill?.nilIfBlank {
            parts.append(skill)
        } else if let type = details.trainingType {
            parts.append(type.displayName.lowercased())
        }
        if let duration = duration, duration >= 60 {
            parts.append(DurationFormatting.string(seconds: duration))
        }
        if let outcome = details.trainingOutcome, outcome != .notApplicable {
            parts.append(outcome.displayName.lowercased())
        }
        return parts.isEmpty ? "Training" : parts.joined(separator: ", ")
    }

    private var dogGroomingSummary: String {
        let type = dogDetails.groomingType ?? .brush
        if type == .bath, let duration, duration >= 60 {
            return "Bath: \(DurationFormatting.string(seconds: duration))"
        }
        return type == .teethBrushing ? "Teeth brushing" : "Grooming: \(type.displayName.lowercased())"
    }

    private var dogSymptomSummary: String {
        let details = dogDetails
        var parts = [details.symptomType?.displayName.lowercased() ?? "symptom"]
        if let severity = details.symptomSeverity, severity != .unknown {
            parts.append(severity.displayName.lowercased())
        }
        return parts.joined(separator: ", ")
    }

    private var dogVaccineSummary: String {
        let details = dogDetails
        var parts = [details.vaccineType?.displayName ?? medicineName ?? "Vaccine"]
        if let dueDate = details.vaccineDueDate {
            parts.append("next due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }

    private var dogGlucoseSummary: String {
        let details = dogDetails
        guard let value = details.glucoseValue else { return "Glucose" }
        var parts = ["\(value.formatted(.number.precision(.fractionLength(0...1)))) \(details.glucoseUnit?.displayName ?? DogGlucoseUnit.mgdl.displayName)"]
        if let relation = details.glucoseMealRelation, relation != .unknown {
            parts.append(relation.displayName.lowercased())
        }
        return parts.joined(separator: ", ")
    }
}
