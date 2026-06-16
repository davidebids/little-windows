import Charts
import SwiftUI

struct DogInsightsView: View {
    let profile: CareProfile?
    let events: [BabyEvent]
    let period: ClosedRange<Date>

    private var periodEvents: [BabyEvent] {
        events.filter { event in
            let day = Calendar.current.startOfDay(for: event.startDate)
            return day >= period.lowerBound && day <= period.upperBound && !event.isTimerDraft
        }
    }

    private var walks: [BabyEvent] { periodEvents.filter { $0.type == .walk } }
    private var pottyEvents: [BabyEvent] { periodEvents.filter { $0.type == .potty } }
    private var trainingEvents: [BabyEvent] { periodEvents.filter { $0.type == .training } }
    private var symptomEvents: [BabyEvent] { periodEvents.filter { $0.type == .symptom } }

    var body: some View {
        VStack(spacing: 16) {
            InsightMetricGrid(metrics: metrics)

            InsightObservationsCard(trends: observations)

            InsightChartCard(
                title: "Walk time",
                subtitle: "Completed walk duration by day",
                isEmpty: dailyWalkMinutes.allSatisfy { $0.value == 0 },
                emptyMessage: "Log completed walks to see duration trends."
            ) {
                Chart(dailyWalkMinutes) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.value)
                    )
                    .foregroundStyle(.green)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            }

            InsightChartCard(
                title: "Potty logs",
                subtitle: "Pee, poop, and accident counts",
                isEmpty: dailyPottyCounts.allSatisfy { $0.value == 0 },
                emptyMessage: "Log pee, poop, or accidents to see patterns."
            ) {
                Chart(dailyPottyCounts) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Logs", point.value)
                    )
                    .foregroundStyle(point.kind == "Accidents" ? .orange : .teal)
                }
                .chartForegroundStyleScale(["Potty": Color.teal, "Accidents": Color.orange])
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            }

            InsightChartCard(
                title: "Weight",
                subtitle: "Logged weight over time",
                isEmpty: weightPoints.isEmpty,
                emptyMessage: "Log weight to see Meso's trend."
            ) {
                Chart(weightPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Pounds", point.value)
                    )
                    .foregroundStyle(.mint)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Pounds", point.value)
                    )
                    .foregroundStyle(.mint)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            }

            Text("Dog insights are tracking observations only. Little Windows does not diagnose symptoms, interpret glucose medically, or evaluate stool quality.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var metrics: [InsightMetric] {
        [
            InsightMetric(title: "Food logs", value: "\(periodEvents.filter { $0.type == .food }.count)", interpretation: "Food entries in this period.", systemImage: "fork.knife"),
            InsightMetric(title: "Walk time", value: DurationFormatting.string(seconds: walks.compactMap(\.duration).reduce(0, +)), interpretation: "Total completed walk duration.", systemImage: "figure.walk"),
            InsightMetric(title: "Potty", value: "\(pottyEvents.count)", interpretation: "Pee, poop, and accident logs.", systemImage: "pawprint.fill"),
            InsightMetric(title: "Training", value: DurationFormatting.string(seconds: trainingEvents.compactMap(\.duration).reduce(0, +)), interpretation: "Completed training time.", systemImage: "graduationcap.fill"),
            InsightMetric(title: "Symptoms", value: "\(symptomEvents.count)", interpretation: "Logged symptoms for your records.", systemImage: "exclamationmark.triangle.fill"),
            InsightMetric(title: "Stage", value: currentStageTitle, interpretation: "Current puppy/dog stage guide.", systemImage: "book.pages.fill")
        ]
    }

    private var observations: [InsightTrend] {
        var values: [InsightTrend] = []
        if !walks.isEmpty {
            let average = walks.compactMap(\.duration).reduce(0, +) / Double(walks.count)
            values.append(InsightTrend(
                metricName: "Walk rhythm",
                currentValueDescription: DurationFormatting.string(seconds: average),
                direction: .flat,
                interpretation: "\(profile?.name ?? "This dog")'s walks averaged \(DurationFormatting.string(seconds: average)) in this period.",
                significance: .low
            ))
        }
        let accidents = pottyEvents.filter { $0.dogDetails.accident == true }.count
        if accidents > 0 {
            values.append(InsightTrend(
                metricName: "Potty accidents",
                currentValueDescription: "\(accidents)",
                direction: .unknown,
                interpretation: "There were \(accidents) accident log\(accidents == 1 ? "" : "s") in the selected period.",
                significance: .medium
            ))
        }
        if !trainingEvents.isEmpty {
            values.append(InsightTrend(
                metricName: "Training",
                currentValueDescription: "\(trainingEvents.count)",
                direction: .up,
                interpretation: "Training was logged \(trainingEvents.count) time\(trainingEvents.count == 1 ? "" : "s").",
                significance: .low
            ))
        }
        return values
    }

    private var currentStageTitle: String {
        guard let profile,
              let guide = PuppyStageGuideService.shared.currentGuide(for: profile) else {
            return "N/A"
        }
        return guide.title
    }

    private var dailyWalkMinutes: [DogChartPoint] {
        dailyPoints { events in
            events.filter { $0.type == .walk }.compactMap(\.duration).reduce(0, +) / 60
        }
    }

    private var dailyPottyCounts: [DogChartPoint] {
        dailyPoints { events in
            Double(events.filter { $0.type == .potty }.count)
        } + dailyPoints(kind: "Accidents") { events in
            Double(events.filter { $0.type == .potty && $0.dogDetails.accident == true }.count)
        }
    }

    private var weightPoints: [DogChartPoint] {
        periodEvents
            .filter { $0.type == .growth }
            .compactMap { event -> DogChartPoint? in
                guard let ounces = event.totalWeightOunces else { return nil }
                return DogChartPoint(date: event.startDate, value: ounces / 16, kind: "Weight")
            }
            .sorted { $0.date < $1.date }
    }

    private func dailyPoints(
        kind: String = "Potty",
        value: ([BabyEvent]) -> Double
    ) -> [DogChartPoint] {
        var result: [DogChartPoint] = []
        var day = Calendar.current.startOfDay(for: period.lowerBound)
        let end = Calendar.current.startOfDay(for: period.upperBound)
        while day <= end {
            let eventsForDay = periodEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
            result.append(DogChartPoint(date: day, value: value(eventsForDay), kind: kind))
            day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(86_400)
        }
        return result
    }
}

private struct DogChartPoint: Identifiable {
    let id = UUID()
    var date: Date
    var value: Double
    var kind: String
}
