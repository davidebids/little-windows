import Charts
import SwiftUI

struct ActivityInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.activityMetrics)
            InsightObservationsCard(trends: snapshot.activityTrends)

            InsightChartCard(
                title: "Tummy time trend",
                subtitle: "Minutes per day",
                isEmpty: snapshot.dailyActivities.allSatisfy { $0.tummyMinutes == 0 }
            ) {
                Chart(snapshot.dailyActivities) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.tummyMinutes)
                    )
                    .foregroundStyle(.green.gradient)
                    .cornerRadius(4)
                }
            }

            InsightChartCard(
                title: "Activity trend",
                subtitle: "Story, indoor, outdoor, and screen minutes per day",
                isEmpty: snapshot.dailyActivities.allSatisfy {
                    $0.readingMinutes + $0.indoorMinutes + $0.outdoorMinutes + $0.screenMinutes == 0
                }
            ) {
                Chart(snapshot.dailyActivities) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.readingMinutes)
                    )
                    .foregroundStyle(by: .value("Activity", "Story"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.indoorMinutes)
                    )
                    .foregroundStyle(by: .value("Activity", "Indoor"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.outdoorMinutes)
                    )
                    .foregroundStyle(by: .value("Activity", "Outdoor"))
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.screenMinutes)
                    )
                    .foregroundStyle(by: .value("Activity", "Screen"))
                }
            }

            InsightChartCard(
                title: "Activity mix",
                subtitle: "Duration for timed activities; count for point events",
                isEmpty: snapshot.activityMix.allSatisfy { $0.value == 0 }
            ) {
                Chart(snapshot.activityMix) { item in
                    BarMark(
                        x: .value("Activity", item.category),
                        y: .value("Amount", item.value)
                    )
                    .foregroundStyle(by: .value("Activity", item.category))
                    .cornerRadius(5)
                }
                .chartLegend(.hidden)
            }

            if !snapshot.medicineNames.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Medicines logged", systemImage: "cross.case.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    ForEach(snapshot.medicineNames, id: \.self) { name in
                        Text(name)
                            .font(.subheadline)
                    }
                    Text("This is a log summary only, not medical guidance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appSurface()
            }
        }
    }
}

struct TemperatureInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.temperatureMetrics)
            InsightChartCard(
                title: "Temperature trend",
                subtitle: "Logged values in Fahrenheit",
                isEmpty: snapshot.temperatureMeasurements.isEmpty,
                emptyMessage: "Log a temperature to see the trend."
            ) {
                Chart(snapshot.temperatureMeasurements) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Temperature", point.fahrenheit)
                    )
                    .foregroundStyle(.red)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Temperature", point.fahrenheit)
                    )
                    .foregroundStyle(.red)
                }
            }
            Text("Temperature logs are for record keeping only. Check with your pediatrician if you are concerned.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }
}

struct MedicineInsightsView: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        Group {
            InsightMetricGrid(metrics: snapshot.medicineMetrics)
            VStack(alignment: .leading, spacing: 12) {
                Label("Administration history", systemImage: "cross.case.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                if snapshot.medicineEvents.isEmpty {
                    ContentUnavailableView(
                        "No medicine logged",
                        systemImage: "cross.case",
                        description: Text("Medicine entries in the selected period will appear here.")
                    )
                } else {
                    ForEach(snapshot.medicineEvents.prefix(12)) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                Text("This history does not provide dosing advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .appSurface()
        }
    }
}
