import Foundation

enum BabySex: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case unknown

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum GrowthMeasurementSource: String, Codable, CaseIterable, Identifiable {
    case pediatrician
    case home
    case other

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum GrowthChartType: String, Codable, CaseIterable, Identifiable {
    case weightForAge
    case lengthForAge
    case headCircumferenceForAge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightForAge: "Weight-for-age"
        case .lengthForAge: "Length-for-age"
        case .headCircumferenceForAge: "Head circumference-for-age"
        }
    }

    var unit: String {
        switch self {
        case .weightForAge: "kg"
        case .lengthForAge, .headCircumferenceForAge: "cm"
        }
    }
}

struct GrowthReferencePoint: Identifiable, Hashable {
    var chartType: GrowthChartType
    var sex: BabySex
    var ageInMonths: Double
    var l: Double
    var m: Double
    var s: Double
    var source: String

    var id: String { "\(chartType.rawValue)-\(sex.rawValue)-\(ageInMonths)" }
    var ageInDays: Double { ageInMonths * GrowthUnitConversion.averageDaysPerMonth }
}

struct GrowthReferenceSeriesPoint: Identifiable, Hashable {
    var chartType: GrowthChartType
    var percentile: Double
    var ageInDays: Double
    var measurementValue: Double

    var id: String {
        "\(chartType.rawValue)-\(percentile)-\(ageInDays)"
    }
}

struct GrowthPercentileResult: Hashable {
    var measurementType: GrowthChartType
    var measuredValue: Double
    var unit: String
    var ageInDays: Int
    var percentileEstimate: Double?
    var zScoreEstimate: Double?
    var nearestPercentileBand: String
    var lowerReferencePercentile: Double?
    var upperReferencePercentile: Double?
    var interpretationText: String

    var exactPercentileDescription: String? {
        percentileEstimate.map(GrowthPercentileFormatting.ordinalPercent)
    }
}

struct GrowthMeasurementChartPoint: Identifiable, Hashable {
    var eventID: UUID
    var date: Date
    var ageInDays: Int
    var measurementValue: Double
    var result: GrowthPercentileResult?
    var source: GrowthMeasurementSource?
    var notes: String?

    var id: String { "\(eventID)-\(result?.measurementType.rawValue ?? "")" }
}

enum GrowthUnitConversion {
    static let kilogramsPerPound = 0.45359237
    static let centimetersPerInch = 2.54
    static let averageDaysPerMonth = 30.4375

    static func poundsAndOuncesToKilograms(pounds: Int, ounces: Double) -> Double {
        (Double(pounds) + ounces / 16) * kilogramsPerPound
    }

    static func feetAndInchesToCentimeters(feet: Int, inches: Double) -> Double {
        (Double(feet) * 12 + inches) * centimetersPerInch
    }

    static func inchesToCentimeters(_ inches: Double) -> Double {
        inches * centimetersPerInch
    }

    static func kilogramsToPoundsAndOunces(_ kilograms: Double) -> (pounds: Int, ounces: Double) {
        let totalOunces = kilograms / kilogramsPerPound * 16
        return (Int(totalOunces / 16), totalOunces.truncatingRemainder(dividingBy: 16))
    }

    static func centimetersToFeetAndInches(_ centimeters: Double) -> (feet: Int, inches: Double) {
        let totalInches = centimeters / centimetersPerInch
        return (Int(totalInches / 12), totalInches.truncatingRemainder(dividingBy: 12))
    }

    static func ageInDays(
        birthDate: Date,
        measurementDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        max(
            0,
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: birthDate),
                to: calendar.startOfDay(for: measurementDate)
            ).day ?? 0
        )
    }
}

enum GrowthPercentileFormatting {
    static func ordinalPercent(_ percentile: Double) -> String {
        let rounded = Int(min(100, max(0, percentile)).rounded())
        let remainder100 = rounded % 100
        let suffix: String
        if 11...13 ~= remainder100 {
            suffix = "th"
        } else {
            switch rounded % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(rounded)\(suffix)%"
    }
}
