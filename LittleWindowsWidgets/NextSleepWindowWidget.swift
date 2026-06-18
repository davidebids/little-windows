import SwiftUI
import WidgetKit

private struct PredictionEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

private struct PredictionProvider: TimelineProvider {
    func placeholder(in context: Context) -> PredictionEntry {
        PredictionEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (PredictionEntry) -> Void) {
        completion(PredictionEntry(date: Date(), snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PredictionEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let calendar = Calendar.current
        let firstMinute = calendar.date(
            bySetting: .second,
            value: 0,
            of: now
        ) ?? now
        var entries = (0...60).compactMap { offset -> PredictionEntry? in
            guard let date = calendar.date(
                byAdding: .minute,
                value: offset,
                to: firstMinute
            ) else {
                return nil
            }
            return PredictionEntry(date: date, snapshot: snapshot)
        }
        if let expectedStart = snapshot.prediction?.resolvedExpectedStart,
           expectedStart > now,
           expectedStart < now.addingTimeInterval(62 * 60) {
            entries.append(
                PredictionEntry(
                    date: expectedStart,
                    snapshot: snapshot
                )
            )
            entries.sort { $0.date < $1.date }
        }
        let refreshDate = calendar.date(
            byAdding: .minute,
            value: 61,
            to: firstMinute
        ) ?? now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
}

struct NextSleepWindowWidget: Widget {
    let kind = "LittleWindows.NextSleep"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PredictionProvider()) { entry in
            NextSleepWidgetView(snapshot: entry.snapshot, now: entry.date)
                .containerBackground(for: .widget) {
                    LittleWindowsWidgetStyle.background
                }
        }
        .configurationDisplayName("Next Sleep Window")
        .description("See the next likely nap or bedtime window.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct NextSleepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        Link(destination: URL(string: "littlewindows://prediction")!) {
            if let prediction = snapshot.prediction {
                if family == .accessoryRectangular {
                    HStack(spacing: 9) {
                        Image(systemName: "moon.stars.fill")
                            .font(.title3.weight(.semibold))
                            .widgetAccentable()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Next \(prediction.kind.lowercased())")
                                .font(.caption.weight(.semibold))
                            Text(
                                "\(headlineText(prediction)) · \(countdownText(prediction))"
                            )
                                .font(.headline)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                            Text(windowText(prediction))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            WidgetBrandLabel()
                            Spacer()
                            Text(prediction.confidenceLabel.uppercased())
                                .font(.caption2.weight(.heavy))
                                .tracking(0.7)
                                .foregroundStyle(LittleWindowsWidgetStyle.lavender)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.09), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        Label("Next \(prediction.kind.lowercased())", systemImage: "moon.stars.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(headlineText(prediction))
                                .font(.title2.weight(.bold))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(countdownText(prediction))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    LittleWindowsWidgetStyle.violet.opacity(0.58),
                                    in: Capsule()
                                )
                                .lineLimit(1)
                        }
                        Text(windowText(prediction))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Label("Open Insights", systemImage: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LittleWindowsWidgetStyle.lavender)
                    }
                    .foregroundStyle(.white)
                }
            } else {
                if family == .accessoryRectangular {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learning sleep rhythm")
                                .font(.headline)
                            Text("Complete a sleep timer")
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "moon.stars.fill")
                            .widgetAccentable()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        WidgetBrandLabel()
                        Spacer()
                        WidgetIconBadge(
                            systemImage: "moon.stars.fill",
                            tint: LittleWindowsWidgetStyle.lavender
                        )
                        Text("Learning the next window")
                            .font(.headline)
                        Text("Complete a sleep timer to refresh the prediction.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func windowText(_ prediction: PredictionSnapshot) -> String {
        switch timingPhase(prediction) {
        case .upcoming:
            return "Likely window \(formattedWindow(prediction))"
        case .inWindow:
            return "In window \(formattedWindow(prediction))"
        case .overdue:
            return "Previous window ended \(prediction.windowEnd.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func headlineText(_ prediction: PredictionSnapshot) -> String {
        if timingPhase(prediction) == .overdue { return "Now" }
        return prediction.resolvedExpectedStart.formatted(
            date: .omitted,
            time: .shortened
        )
    }

    private func countdownText(_ prediction: PredictionSnapshot) -> String {
        let phase = timingPhase(prediction)
        if phase == .overdue { return "Overdue" }
        if phase == .inWindow, prediction.resolvedExpectedStart <= now {
            return "Likely now"
        }
        return PredictionCountdownFormatting.text(
            until: prediction.resolvedExpectedStart,
            from: now
        )
    }

    private func formattedWindow(_ prediction: PredictionSnapshot) -> String {
        "\(prediction.windowStart.formatted(date: .omitted, time: .shortened))-\(prediction.windowEnd.formatted(date: .omitted, time: .shortened))"
    }

    private func timingPhase(_ prediction: PredictionSnapshot) -> PredictionTimingPhase {
        PredictionTiming.phase(
            windowStart: prediction.windowStart,
            windowEnd: prediction.windowEnd,
            now: now
        )
    }
}
