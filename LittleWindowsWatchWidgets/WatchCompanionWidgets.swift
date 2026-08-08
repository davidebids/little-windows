import SwiftUI
import WidgetKit

private struct WatchCompanionEntry: TimelineEntry {
    var date: Date
    var state: WatchCompanionState
}

private struct WatchCompanionProvider: TimelineProvider {
    var includesLiveTimerEntries = false

    func placeholder(in context: Context) -> WatchCompanionEntry {
        WatchCompanionEntry(date: Date(), state: .empty)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WatchCompanionEntry) -> Void
    ) {
        completion(WatchCompanionEntry(date: Date(), state: WatchSharedStorage.readState()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WatchCompanionEntry>) -> Void
    ) {
        let now = Date()
        let state = WatchSharedStorage.readState()
        let dates = WatchCompanionTimeline.entryDates(
            timerIsRunning: includesLiveTimerEntries
                && state.activeTimers.contains(where: \.isRunning),
            from: now
        )
        let entries = dates.map {
            WatchCompanionEntry(date: $0, state: state)
        }
        let refreshDate = dates.count > 1
            ? (dates.last ?? now).addingTimeInterval(1)
            : now.addingTimeInterval(15 * 60)
        completion(Timeline(
            entries: entries,
            policy: .after(refreshDate)
        ))
    }
}

struct WatchActiveTimerWidget: Widget {
    let kind = "LittleWindows.Watch.ActiveTimer"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchCompanionProvider(includesLiveTimerEntries: true)
        ) { entry in
            WatchActiveTimerWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.indigo.opacity(0.22) }
        }
        .configurationDisplayName("Active Timer")
        .description("See the current Little Windows timer.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct WatchActiveTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchCompanionEntry

    var body: some View {
        if entry.state.profiles.isEmpty {
            WatchMissingProfileWidgetView(
                family: family,
                inlineTitle: "Add care profile",
                rectangularTitle: "Care timers",
                rectangularDetail: "Add on iPhone",
                systemImage: "person.crop.circle.badge.plus"
            )
        } else if let timer = entry.state.activeTimers.first(where: \.isRunning)
            ?? entry.state.activeTimers.first {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(timer.elapsed(at: entry.date), 4 * 60 * 60), in: 0...(4 * 60 * 60)) {
                    Image(systemName: timer.systemImage)
                } currentValueLabel: {
                    Text(compactDuration(timer.elapsed(at: entry.date)))
                        .minimumScaleFactor(0.65)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Label(
                    "\(timer.title) \(compactDuration(timer.elapsed(at: entry.date)))",
                    systemImage: timer.systemImage
                )
            default:
                HStack(spacing: 7) {
                    Image(systemName: timer.systemImage)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(compactDuration(timer.elapsed(at: entry.date)))
                            .font(.headline.monospacedDigit())
                    }
                }
            }
        } else {
            Label("No active timer", systemImage: "checkmark.circle")
                .font(.caption)
        }
    }

    private func compactDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return minutes >= 60
            ? "\(minutes / 60)h \(minutes % 60)m"
            : "\(minutes)m"
    }
}

struct WatchSleepWindowWidget: Widget {
    let kind = "LittleWindows.Watch.SleepWindow"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchCompanionProvider()) { entry in
            WatchSleepWindowWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.purple.opacity(0.2) }
        }
        .configurationDisplayName("Next Sleep Window")
        .description("See the next predicted sleep window.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct WatchSleepWindowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchCompanionEntry

    var body: some View {
        if entry.state.profiles.isEmpty {
            WatchMissingProfileWidgetView(
                family: family,
                inlineTitle: "Add child profile",
                rectangularTitle: "Sleep insights",
                rectangularDetail: "Add a child on iPhone",
                systemImage: "person.crop.circle.badge.plus"
            )
        } else if let prediction = entry.state.prediction {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: "moon.stars.fill")
                    Text(prediction.expectedStart, style: .time)
                        .font(.caption2.weight(.semibold))
                }
            case .accessoryInline:
                Label {
                    Text("Sleep ") + Text(prediction.expectedStart, style: .time)
                } icon: {
                    Image(systemName: "moon.stars.fill")
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Next \(prediction.title)", systemImage: "moon.stars.fill")
                        .font(.caption2)
                    Text(prediction.expectedStart, style: .time)
                        .font(.headline)
                    Text(prediction.confidenceLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("No sleep window", systemImage: "moon")
                .font(.caption)
        }
    }
}

struct WatchTodayWidget: Widget {
    let kind = "LittleWindows.Watch.Today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchCompanionProvider()) { entry in
            WatchTodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.blue.opacity(0.18) }
        }
        .configurationDisplayName("Today")
        .description("See a current Little Windows care count.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct WatchTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchCompanionEntry

    private var metric: WatchMetricSnapshot? { entry.state.todayMetrics.first }

    var body: some View {
        if entry.state.profiles.isEmpty {
            WatchMissingProfileWidgetView(
                family: family,
                inlineTitle: "Add care profile",
                rectangularTitle: "Care summary",
                rectangularDetail: "Add on iPhone",
                systemImage: "person.crop.circle.badge.plus"
            )
        } else if let metric {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: metric.systemImage)
                    Text(metric.value)
                        .font(.caption.weight(.bold))
                        .minimumScaleFactor(0.7)
                }
            case .accessoryInline:
                Label("\(metric.title) \(metric.value)", systemImage: metric.systemImage)
            default:
                HStack(spacing: 7) {
                    Image(systemName: metric.systemImage)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.title)
                            .font(.caption2)
                        Text(metric.value)
                            .font(.headline)
                    }
                }
            }
        } else {
            Label("Open Little Windows", systemImage: "sparkles")
                .font(.caption)
        }
    }
}

private struct WatchMissingProfileWidgetView: View {
    let family: WidgetFamily
    let inlineTitle: String
    let rectangularTitle: String
    let rectangularDetail: String
    let systemImage: String

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: systemImage)
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel(inlineTitle)
        case .accessoryInline:
            Label(inlineTitle, systemImage: systemImage)
        default:
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(rectangularTitle)
                        .font(.caption.weight(.semibold))
                    Text(rectangularDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .widgetAccentable()
            }
        }
    }
}

@main
struct LittleWindowsWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchActiveTimerWidget()
        WatchSleepWindowWidget()
        WatchTodayWidget()
    }
}
