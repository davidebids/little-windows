import SwiftUI
import WidgetKit

private struct SummaryEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

private struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: Date(), snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = SummaryEntry(date: Date(), snapshot: WidgetSnapshotReader.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct TodaySummaryWidget: Widget {
    let kind = "LittleWindows.TodaySummary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryProvider()) { entry in
            TodaySummaryWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LittleWindowsWidgetStyle.background
                }
        }
        .configurationDisplayName("Today Summary")
        .description("A quick profile-specific care summary for today.")
        .supportedFamilies([.systemMedium])
    }
}

private struct TodaySummaryWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Link(destination: URL(string: "littlewindows://today")!) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetBrandLabel()
                        Text("\(snapshot.babyName)'s day")
                            .font(.headline)
                    }
                    Spacer()
                    Text(snapshot.generatedAt, style: .time)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
                HStack(spacing: 10) {
                    ForEach(widgetMetrics) { item in
                        metric(item.value, item.title, item.systemImage, tint(named: item.tintName))
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }

    private var widgetMetrics: [CareSummaryMetricSnapshot] {
        if let metrics = snapshot.todaySummary.summaryMetrics, !metrics.isEmpty {
            let preferredIDs = snapshot.todaySummary.isDog
                ? ["food", "water", "potty", "walks"]
                : ["sleep-total", "sleep-naps", "feed-total", "diapers"]
            return preferredIDs.compactMap { id in
                metrics.first { $0.id == id }
            }
        }

        if snapshot.todaySummary.isDog {
            return [
                CareSummaryMetricSnapshot(id: "food", title: "Food", value: "\(snapshot.todaySummary.dogFoodCount ?? 0)", systemImage: "fork.knife", tintName: "orange", eventTypeRawValue: "food"),
                CareSummaryMetricSnapshot(id: "water", title: "Water", value: "\(snapshot.todaySummary.dogWaterCount ?? 0)", systemImage: "drop.fill", tintName: "cyan", eventTypeRawValue: "water"),
                CareSummaryMetricSnapshot(id: "potty", title: "Potty", value: "\(snapshot.todaySummary.dogPottyCount ?? 0)", systemImage: "pawprint.fill", tintName: "teal", eventTypeRawValue: "potty"),
                CareSummaryMetricSnapshot(id: "walks", title: "Walks", value: DurationFormatting.string(seconds: snapshot.todaySummary.dogWalkSeconds ?? 0), systemImage: "figure.walk", tintName: "green", eventTypeRawValue: "walk")
            ]
        }

        return [
            CareSummaryMetricSnapshot(id: "sleep-total", title: "Sleep", value: DurationFormatting.string(seconds: snapshot.todaySummary.totalSleepSeconds), systemImage: "moon.fill", tintName: "indigo", eventTypeRawValue: "sleep"),
            CareSummaryMetricSnapshot(id: "sleep-naps", title: "Naps", value: "\(snapshot.todaySummary.napCount)", systemImage: "bed.double.fill", tintName: "purple", eventTypeRawValue: "sleep"),
            CareSummaryMetricSnapshot(id: "feed-total", title: "Care", value: "\(snapshot.todaySummary.careSessionCount)", systemImage: "waterbottle.fill", tintName: "orange", eventTypeRawValue: "feed"),
            CareSummaryMetricSnapshot(id: "diapers", title: "Diapers", value: "\(snapshot.todaySummary.diaperCount)", systemImage: "drop.fill", tintName: "cyan", eventTypeRawValue: "diaper")
        ]
    }

    private func tint(named name: String) -> Color {
        switch name {
        case "blue": .blue
        case "cyan": .cyan
        case "green": .green
        case "indigo": LittleWindowsWidgetStyle.lavender
        case "mint": .mint
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        default: .white.opacity(0.8)
        }
    }

    private func metric(_ value: String, _ title: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: Circle())
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
    }
}
