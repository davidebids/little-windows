import Foundation

struct GrowthReferenceService {
    static let shared = GrowthReferenceService()
    static let supportedPercentiles = [3.0, 5, 10, 25, 50, 75, 90, 95, 97, 99]
    static let basicPercentiles = [3.0, 25, 50, 75, 97]
    static let detailedPercentiles = supportedPercentiles
    static let sourceName = "WHO Child Growth Standards, CDC-hosted LMS data"

    private let pointsByKey: [ReferenceKey: [GrowthReferencePoint]]

    init(bundle: Bundle = .main) {
        pointsByKey = (try? Self.loadReferenceData(bundle: bundle)) ?? [:]
    }

    init(points: [GrowthReferencePoint]) {
        pointsByKey = Dictionary(
            grouping: points,
            by: { ReferenceKey(chartType: $0.chartType, sex: $0.sex) }
        )
        .mapValues { $0.sorted { $0.ageInMonths < $1.ageInMonths } }
    }

    static func loadReferenceData(
        bundle: Bundle = .main
    ) throws -> [ReferenceKey: [GrowthReferencePoint]] {
        var result: [ReferenceKey: [GrowthReferencePoint]] = [:]
        for chartType in GrowthChartType.allCases {
            for sex in [BabySex.male, .female] {
                let filename = resourceName(chartType: chartType, sex: sex)
                guard let url = bundle.url(
                    forResource: filename,
                    withExtension: "csv",
                    subdirectory: "GrowthCharts"
                ) ?? bundle.url(forResource: filename, withExtension: "csv") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let csv = try String(contentsOf: url, encoding: .utf8)
                let points = try parseCSV(csv, chartType: chartType, sex: sex)
                result[ReferenceKey(chartType: chartType, sex: sex)] = points
            }
        }
        return result
    }

    func referenceSeries(
        chartType: GrowthChartType,
        sex: BabySex,
        percentiles: [Double]
    ) -> [GrowthReferenceSeriesPoint] {
        guard let points = referencePoints(chartType: chartType, sex: sex) else { return [] }
        return percentiles.flatMap { percentile in
            points.compactMap { point in
                guard let value = Self.valueForPercentile(percentile, lms: point) else { return nil }
                return GrowthReferenceSeriesPoint(
                    chartType: chartType,
                    percentile: percentile,
                    ageInDays: point.ageInDays,
                    measurementValue: value
                )
            }
        }
    }

    func percentileForMeasurement(
        chartType: GrowthChartType,
        sex: BabySex,
        ageInDays: Int,
        value: Double
    ) -> GrowthPercentileResult? {
        guard value > 0,
              let lms = interpolatedReference(
                chartType: chartType,
                sex: sex,
                ageInDays: Double(ageInDays)
              ) else {
            return nil
        }
        let zScore = Self.lmsZScore(value: value, l: lms.l, m: lms.m, s: lms.s)
        let percentile = Self.normalCDF(zScore) * 100
        let band = Self.nearestPercentileBand(percentile)
        let exactDescription = GrowthPercentileFormatting.ordinalPercent(percentile)
        return GrowthPercentileResult(
            measurementType: chartType,
            measuredValue: value,
            unit: chartType.unit,
            ageInDays: ageInDays,
            percentileEstimate: percentile,
            zScoreEstimate: zScore,
            nearestPercentileBand: band.label,
            lowerReferencePercentile: band.lower,
            upperReferencePercentile: band.upper,
            interpretationText: "Estimated \(exactDescription) using WHO infant reference data."
        )
    }

    func zScoreForMeasurement(
        chartType: GrowthChartType,
        sex: BabySex,
        ageInDays: Int,
        value: Double
    ) -> Double? {
        percentileForMeasurement(
            chartType: chartType,
            sex: sex,
            ageInDays: ageInDays,
            value: value
        )?.zScoreEstimate
    }

    func valueForPercentile(
        chartType: GrowthChartType,
        sex: BabySex,
        ageInDays: Int,
        percentile: Double
    ) -> Double? {
        guard let lms = interpolatedReference(
            chartType: chartType,
            sex: sex,
            ageInDays: Double(ageInDays)
        ) else {
            return nil
        }
        return Self.valueForPercentile(percentile, lms: lms)
    }

    func interpolateReferenceValue(
        chartType: GrowthChartType,
        sex: BabySex,
        ageInDays: Double,
        percentile: Double
    ) -> Double? {
        guard let lms = interpolatedReference(
            chartType: chartType,
            sex: sex,
            ageInDays: ageInDays
        ) else {
            return nil
        }
        return Self.valueForPercentile(percentile, lms: lms)
    }

    func nearestPercentileBand(_ percentile: Double) -> (
        label: String,
        lower: Double?,
        upper: Double?
    ) {
        Self.nearestPercentileBand(percentile)
    }

    func chartDataForGrowthEntries(
        _ entries: [BabyEvent],
        chartType: GrowthChartType,
        profile: BabyProfile
    ) -> [GrowthMeasurementChartPoint] {
        entries
            .filter { $0.type == .growth }
            .compactMap { event in
                guard let value = event.canonicalMeasurement(for: chartType) else { return nil }
                let age = GrowthUnitConversion.ageInDays(
                    birthDate: profile.birthDate,
                    measurementDate: event.startDate
                )
                let sex = event.growthSex == .unknown ? profile.sex : event.growthSex
                return GrowthMeasurementChartPoint(
                    eventID: event.id,
                    date: event.startDate,
                    ageInDays: age,
                    measurementValue: value,
                    result: percentileForMeasurement(
                        chartType: chartType,
                        sex: sex,
                        ageInDays: age,
                        value: value
                    ),
                    source: event.growthSource,
                    notes: event.notes
                )
            }
            .sorted { $0.date < $1.date }
    }

    func referencePoints(
        chartType: GrowthChartType,
        sex: BabySex
    ) -> [GrowthReferencePoint]? {
        guard sex != .unknown else { return nil }
        return pointsByKey[ReferenceKey(chartType: chartType, sex: sex)]
    }

    func interpolatedReference(
        chartType: GrowthChartType,
        sex: BabySex,
        ageInDays: Double
    ) -> GrowthReferencePoint? {
        guard ageInDays >= 0,
              ageInDays <= 24 * GrowthUnitConversion.averageDaysPerMonth,
              let points = referencePoints(chartType: chartType, sex: sex),
              let first = points.first,
              let last = points.last else {
            return nil
        }

        let ageInMonths = ageInDays / GrowthUnitConversion.averageDaysPerMonth
        if ageInMonths <= first.ageInMonths { return first }
        if ageInMonths >= last.ageInMonths { return last }

        guard let upperIndex = points.firstIndex(where: { $0.ageInMonths >= ageInMonths }),
              upperIndex > 0 else {
            return nil
        }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let fraction = (ageInMonths - lower.ageInMonths)
            / (upper.ageInMonths - lower.ageInMonths)
        return GrowthReferencePoint(
            chartType: chartType,
            sex: sex,
            ageInMonths: ageInMonths,
            l: Self.interpolate(lower.l, upper.l, fraction: fraction),
            m: Self.interpolate(lower.m, upper.m, fraction: fraction),
            s: Self.interpolate(lower.s, upper.s, fraction: fraction),
            source: Self.sourceName
        )
    }

    static func lmsZScore(value: Double, l: Double, m: Double, s: Double) -> Double {
        guard value > 0, m > 0, s > 0 else { return .nan }
        if abs(l) < 0.000_000_1 {
            return log(value / m) / s
        }
        return (pow(value / m, l) - 1) / (l * s)
    }

    static func normalCDF(_ z: Double) -> Double {
        0.5 * (1 + erf(z / sqrt(2)))
    }

    static func inverseNormalCDF(_ probability: Double) -> Double {
        let p = min(1 - 1e-12, max(1e-12, probability))
        let a = [
            -39.69683028665376, 220.9460984245205, -275.9285104469687,
            138.3577518672690, -30.66479806614716, 2.506628277459239
        ]
        let b = [
            -54.47609879822406, 161.5858368580409, -155.6989798598866,
            66.80131188771972, -13.28068155288572
        ]
        let c = [
            -0.007784894002430293, -0.3223964580411365, -2.400758277161838,
            -2.549732539343734, 4.374664141464968, 2.938163982698783
        ]
        let d = [
            0.007784695709041462, 0.3224671290700398,
            2.445134137142996, 3.754408661907416
        ]
        let low = 0.02425
        let high = 1 - low

        if p < low {
            let q = sqrt(-2 * log(p))
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > high {
            let q = sqrt(-2 * log(1 - p))
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }

    static func nearestPercentileBand(_ percentile: Double) -> (
        label: String,
        lower: Double?,
        upper: Double?
    ) {
        let value = min(100, max(0, percentile))
        let references = supportedPercentiles
        if let nearest = references.min(by: { abs($0 - value) < abs($1 - value) }),
           abs(nearest - value) <= 2 {
            return ("Near P\(percentileLabel(nearest))", nearest, nearest)
        }
        if value < references[0] {
            return ("Below P\(percentileLabel(references[0]))", nil, references[0])
        }
        if value > references.last! {
            return ("Above P\(percentileLabel(references.last!))", references.last, nil)
        }
        for pair in zip(references, references.dropFirst()) where value >= pair.0 && value <= pair.1 {
            return (
                "Between P\(percentileLabel(pair.0)) and P\(percentileLabel(pair.1))",
                pair.0,
                pair.1
            )
        }
        return ("Near P\(Int(value.rounded()))", nil, nil)
    }

    private static func valueForPercentile(
        _ percentile: Double,
        lms: GrowthReferencePoint
    ) -> Double? {
        guard percentile > 0, percentile < 100 else { return nil }
        let z = inverseNormalCDF(percentile / 100)
        if abs(lms.l) < 0.000_000_1 {
            return lms.m * exp(lms.s * z)
        }
        let base = 1 + lms.l * lms.s * z
        guard base > 0 else { return nil }
        return lms.m * pow(base, 1 / lms.l)
    }

    private static func interpolate(_ lower: Double, _ upper: Double, fraction: Double) -> Double {
        lower + (upper - lower) * min(1, max(0, fraction))
    }

    private static func percentileLabel(_ percentile: Double) -> String {
        percentile.formatted(.number.precision(.fractionLength(0)))
    }

    private static func resourceName(
        chartType: GrowthChartType,
        sex: BabySex
    ) -> String {
        let sexName = sex == .male ? "boys" : "girls"
        let chartName: String
        switch chartType {
        case .weightForAge: chartName = "weight_for_age"
        case .lengthForAge: chartName = "length_for_age"
        case .headCircumferenceForAge: chartName = "head_circumference_for_age"
        }
        return "who_\(sexName)_\(chartName)_0_24"
    }

    private static func parseCSV(
        _ csv: String,
        chartType: GrowthChartType,
        sex: BabySex
    ) throws -> [GrowthReferencePoint] {
        let lines = csv
            .replacingOccurrences(of: "\u{feff}", with: "")
            .split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { throw CocoaError(.fileReadCorruptFile) }
        return try lines.dropFirst().map { line in
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 4,
                  let month = Double(columns[0]),
                  let l = Double(columns[1]),
                  let m = Double(columns[2]),
                  let s = Double(columns[3]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return GrowthReferencePoint(
                chartType: chartType,
                sex: sex,
                ageInMonths: month,
                l: l,
                m: m,
                s: s,
                source: sourceName
            )
        }
    }
}

struct ReferenceKey: Hashable {
    var chartType: GrowthChartType
    var sex: BabySex
}
