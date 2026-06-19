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
                    if snapshot.todaySummary.isDog {
                        metric("\(snapshot.todaySummary.dogFoodCount ?? 0)", "Food", "fork.knife", .orange)
                        metric("\(snapshot.todaySummary.dogWaterCount ?? 0)", "Water", "drop.fill", .cyan)
                        metric("\(snapshot.todaySummary.dogPottyCount ?? 0)", "Potty", "pawprint.fill", .teal)
                        metric(
                            DurationFormatting.string(seconds: snapshot.todaySummary.dogWalkSeconds ?? 0),
                            "Walks",
                            "figure.walk",
                            .green
                        )
                    } else {
                        metric(
                            DurationFormatting.string(seconds: snapshot.todaySummary.totalSleepSeconds),
                            "Sleep",
                            "moon.fill",
                            LittleWindowsWidgetStyle.lavender
                        )
                        metric("\(snapshot.todaySummary.napCount)", "Naps", "bed.double.fill", .purple)
                        metric("\(snapshot.todaySummary.careSessionCount)", "Care", "waterbottle.fill", .orange)
                        metric("\(snapshot.todaySummary.diaperCount)", "Diapers", "drop.fill", .cyan)
                    }
                }
            }
            .foregroundStyle(.white)
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
