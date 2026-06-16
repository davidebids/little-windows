import Charts
import SwiftUI

struct GrowthInsightsView: View {
    let profile: BabyProfile?
    let events: [BabyEvent]
    @State private var detailedPercentiles = false

    private let service = GrowthReferenceService.shared

    private var growthEvents: [BabyEvent] {
        events.filter { $0.type == .growth }.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        Group {
            if let profile {
                controls(profile: profile)
                latestSummary(profile: profile)

                ForEach(GrowthChartType.allCases) { chartType in
                    GrowthPercentileChart(
                        chartType: chartType,
                        profile: profile,
                        entries: growthEvents,
                        percentiles: detailedPercentiles
                            ? GrowthReferenceService.detailedPercentiles
                            : GrowthReferenceService.basicPercentiles,
                        service: service
                    )
                }

                Text("Growth charts are reference tools based on public datasets and are not medical advice. Ask your pediatrician if you have concerns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            } else {
                ContentUnavailableView(
                    "Baby profile needed",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Add a birth date and sex in Settings to calculate growth percentiles.")
                )
            }
        }
    }

    private func controls(profile: BabyProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WHO infant growth charts")
                        .font(.headline)
                    Text("Birth to 24 months · \(profile.sex.displayName.lowercased()) reference")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Detailed", isOn: $detailedPercentiles)
                    .labelsHidden()
            }
            HStack {
                Label(
                    detailedPercentiles ? "Detailed percentile curves" : "Basic percentile curves",
                    systemImage: "chart.xyaxis.line"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
                Spacer()
                Text(detailedPercentiles ? "P3–P99" : "P3 · P25 · P50 · P75 · P97")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if profile.sex == .unknown {
                Label(
                    "Choose male or female in Settings to display official sex-specific curves.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .appSurface()
    }

    private func latestSummary(profile: BabyProfile) -> some View {
        let summaries = GrowthChartType.allCases.map {
            GrowthLatestSummary(
                chartType: $0,
                points: service.chartDataForGrowthEntries(
                    growthEvents,
                    chartType: $0,
                    profile: profile
                )
            )
        }
        return VStack(alignment: .leading, spacing: 14) {
            Label("Latest measurements", systemImage: "ruler.fill")
                .font(.headline)
                .foregroundStyle(.indigo)

            ForEach(summaries) { summary in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: summary.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(summary.color)
                        .frame(width: 34, height: 34)
                        .background(summary.color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.chartType.displayName)
                            .font(.subheadline.weight(.semibold))
                        if let latest = summary.latest {
                            Text(summary.displayValue(latest.measurementValue))
                                .font(.title3.bold())
                            Text(
                                latest.result?.exactPercentileDescription
                                    ?? "Percentile unavailable"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.indigo)
                            if let change = summary.changeDescription {
                                Text(change)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No measurement logged")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let latest = summary.latest {
                        Text(DateFormatting.age(from: profile.birthDate, to: latest.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if summary.id != summaries.last?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .appSurface()
    }
}

private struct GrowthPercentileChart: View {
    let chartType: GrowthChartType
    let profile: BabyProfile
    let entries: [BabyEvent]
    let percentiles: [Double]
    let service: GrowthReferenceService
    @State private var selectedAgeMonths: Double?

    private var referenceSeries: [GrowthReferenceSeriesPoint] {
        service.referenceSeries(
            chartType: chartType,
            sex: profile.sex,
            percentiles: percentiles
        )
    }

    private var measurements: [GrowthMeasurementChartPoint] {
        service.chartDataForGrowthEntries(
            entries,
            chartType: chartType,
            profile: profile
        )
    }

    private var selectedMeasurement: GrowthMeasurementChartPoint? {
        guard let selectedAgeMonths else { return nil }
        return measurements.min {
            abs(Double($0.ageInDays) / GrowthUnitConversion.averageDaysPerMonth - selectedAgeMonths)
                < abs(Double($1.ageInDays) / GrowthUnitConversion.averageDaysPerMonth - selectedAgeMonths)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chartType.displayName)
                    .font(.headline)
                Text("WHO reference curves with \(profile.name)'s measurements")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if profile.sex == .unknown {
                ContentUnavailableView(
                    "Reference sex needed",
                    systemImage: "chart.line.downtrend.xyaxis",
                    description: Text("Choose a growth-chart sex in Settings.")
                )
                .frame(minHeight: 220)
            } else {
                Chart {
                    ForEach(referenceSeries) { point in
                        LineMark(
                            x: .value("Age (months)", point.ageInDays / GrowthUnitConversion.averageDaysPerMonth),
                            y: .value(displayUnit, displayValue(point.measurementValue)),
                            series: .value("Percentile", point.percentile)
                        )
                        .foregroundStyle(referenceColor(for: point.percentile))
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: point.percentile == 50 ? 1.5 : 0.8,
                                dash: point.percentile == 50 ? [] : [3, 3]
                            )
                        )
                    }

                    ForEach(measurements) { point in
                        LineMark(
                            x: .value("Age (months)", Double(point.ageInDays) / GrowthUnitConversion.averageDaysPerMonth),
                            y: .value(displayUnit, displayValue(point.measurementValue)),
                            series: .value("Child", profile.name)
                        )
                        .foregroundStyle(.indigo)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Age (months)", Double(point.ageInDays) / GrowthUnitConversion.averageDaysPerMonth),
                            y: .value(displayUnit, displayValue(point.measurementValue))
                        )
                        .foregroundStyle(.indigo)
                        .symbolSize(65)
                    }

                    if let selectedMeasurement {
                        RuleMark(
                            x: .value(
                                "Selected age",
                                Double(selectedMeasurement.ageInDays)
                                    / GrowthUnitConversion.averageDaysPerMonth
                            )
                        )
                        .foregroundStyle(.indigo.opacity(0.45))
                    }
                }
                .chartXScale(domain: 0...24)
                .chartXAxis {
                    AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21, 24]) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXSelection(value: $selectedAgeMonths)
                .frame(height: 280)

                percentileLegend

                if let selectedMeasurement {
                    selectionDetails(selectedMeasurement)
                } else if measurements.isEmpty {
                    Text("Log a \(measurementName) from Today to add \(profile.name)'s first point.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Touch and drag across the chart to inspect a measurement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .appSurface()
    }

    private var percentileLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(percentiles, id: \.self) { percentile in
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(referenceColor(for: percentile))
                            .frame(width: 14, height: 2)
                        Text("P\(Int(percentile))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Capsule()
                        .fill(.indigo)
                        .frame(width: 16, height: 3)
                    Text(profile.name)
                        .font(.caption2.weight(.semibold))
                }
            }
        }
    }

    private func selectionDetails(_ point: GrowthMeasurementChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(point.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(DateFormatting.age(from: profile.birthDate, to: point.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(displayValueText(point.measurementValue))
                .font(.title3.bold())
            Text(point.result?.exactPercentileDescription ?? "Percentile unavailable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
            if let source = point.source {
                Label(source.displayName, systemImage: "cross.case.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notes = point.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func displayValue(_ metricValue: Double) -> Double {
        switch chartType {
        case .weightForAge:
            metricValue / GrowthUnitConversion.kilogramsPerPound
        case .lengthForAge, .headCircumferenceForAge:
            metricValue / GrowthUnitConversion.centimetersPerInch
        }
    }

    private func displayValueText(_ metricValue: Double) -> String {
        GrowthLatestSummary(chartType: chartType, points: [])
            .displayValue(metricValue)
    }

    private var displayUnit: String {
        chartType == .weightForAge ? "lb" : "in"
    }

    private var measurementName: String {
        switch chartType {
        case .weightForAge: "weight"
        case .lengthForAge: "length"
        case .headCircumferenceForAge: "head circumference"
        }
    }

    private func referenceColor(for percentile: Double) -> Color {
        percentile == 50 ? .secondary.opacity(0.75) : .secondary.opacity(0.34)
    }
}

private struct GrowthLatestSummary: Identifiable {
    let chartType: GrowthChartType
    let points: [GrowthMeasurementChartPoint]

    var id: GrowthChartType { chartType }
    var latest: GrowthMeasurementChartPoint? { points.last }
    var previous: GrowthMeasurementChartPoint? { points.dropLast().last }

    var systemImage: String {
        switch chartType {
        case .weightForAge: "scalemass.fill"
        case .lengthForAge: "ruler.fill"
        case .headCircumferenceForAge: "circle.dashed"
        }
    }

    var color: Color {
        switch chartType {
        case .weightForAge: .indigo
        case .lengthForAge: .mint
        case .headCircumferenceForAge: .orange
        }
    }

    func displayValue(_ metricValue: Double) -> String {
        switch chartType {
        case .weightForAge:
            let value = GrowthUnitConversion.kilogramsToPoundsAndOunces(metricValue)
            return "\(value.pounds) lb \(value.ounces.formatted(.number.precision(.fractionLength(0...1)))) oz"
        case .lengthForAge, .headCircumferenceForAge:
            let inches = metricValue / GrowthUnitConversion.centimetersPerInch
            return "\(inches.formatted(.number.precision(.fractionLength(0...2)))) in"
        }
    }

    var changeDescription: String? {
        guard let latest, let previous else { return nil }
        let days = max(1, latest.ageInDays - previous.ageInDays)
        let difference = latest.measurementValue - previous.measurementValue
        let velocity: String
        switch chartType {
        case .weightForAge:
            let pounds = difference / GrowthUnitConversion.kilogramsPerPound
            let poundsPerWeek = pounds / Double(days) * 7
            velocity = "\(signed(pounds)) lb since last · \(signed(poundsPerWeek)) lb/week"
        case .lengthForAge, .headCircumferenceForAge:
            let inches = difference / GrowthUnitConversion.centimetersPerInch
            let inchesPerMonth = inches / Double(days) * GrowthUnitConversion.averageDaysPerMonth
            velocity = "\(signed(inches)) in since last · \(signed(inchesPerMonth)) in/month"
        }

        let priorPercentile = previous.result?.exactPercentileDescription
        let latestPercentile = latest.result?.exactPercentileDescription
        if let priorPercentile, let latestPercentile, priorPercentile != latestPercentile {
            return "\(velocity). Changed from \(priorPercentile) to \(latestPercentile)."
        }
        if let latestPercentile {
            return "\(velocity). Tracking at \(latestPercentile)."
        }
        return velocity
    }

    private func signed(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(0...2))))"
    }
}
