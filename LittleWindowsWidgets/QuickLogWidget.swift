import AppIntents
import SwiftUI
import WidgetKit

private struct QuickLogEntry: TimelineEntry {
    var date: Date
}

private struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { QuickLogEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(QuickLogEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        completion(Timeline(entries: [QuickLogEntry(date: Date())], policy: .never))
    }
}

struct QuickLogWidget: Widget {
    let kind = "LittleWindows.QuickLog"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickLogProvider()) { _ in
            QuickLogWidgetView()
                .containerBackground(for: .widget) {
                    LittleWindowsWidgetStyle.background
                }
        }
        .configurationDisplayName("Quick Log")
        .description("Start common timers with one tap.")
        .supportedFamilies([.systemMedium])
    }
}

private struct QuickLogWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetBrandLabel()
                    Text("Quick log")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "bolt.fill")
                    .foregroundStyle(LittleWindowsWidgetStyle.lavender)
            }
            HStack(spacing: 7) {
                action("Tummy", "figure.play", .green, StartTummyTimeIntent())
                action("Story", "book.fill", .blue, StartStoryTimeIntent())
                action("Diaper", "drop.fill", .teal, LogDiaperIntent())
            }
            HStack(spacing: 7) {
                action("Temp", "thermometer.medium", .red, LogTemperatureIntent())
                action("Bath", "bathtub.fill", .cyan, StartBathIntent())
                action("Sleep", "moon.fill", LittleWindowsWidgetStyle.lavender, StartSleepTimerIntent())
            }
        }
        .foregroundStyle(.white)
    }

    private func action<I: AppIntent>(
        _ title: String,
        _ icon: String,
        _ tint: Color,
        _ intent: I
    ) -> some View {
        Button(intent: intent) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 37)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}
