import AppIntents
import SwiftUI
import WidgetKit

private struct QuickLogEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

private struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(QuickLogEntry(date: Date(), snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        let entry = QuickLogEntry(date: Date(), snapshot: WidgetSnapshotReader.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(20 * 60))))
    }
}

struct QuickLogWidget: Widget {
    let kind = "LittleWindows.QuickLog"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickLogProvider()) { entry in
            QuickLogWidgetView(snapshot: entry.snapshot)
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
    let snapshot: WidgetSnapshot

    private var actions: [QuickLogActionSnapshot] {
        let snapshotActions = snapshot.resolvedQuickActions
        if !snapshotActions.isEmpty {
            return Array(snapshotActions.prefix(6))
        }
        return Self.fallbackActions
    }

    var body: some View {
        if snapshot.profileID == nil {
            Link(destination: URL(string: "littlewindows://care")!) {
                CareProfileRequiredWidgetState(
                    title: "Quick care logging",
                    detail: "Add a child or dog to start timers and record care.",
                    systemImage: "bolt.heart.fill"
                )
            }
        } else {
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

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
                    spacing: 7
                ) {
                    ForEach(actions) { action in
                        quickAction(action)
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }

    private func quickAction(_ action: QuickLogActionSnapshot) -> some View {
        Button(intent: OpenLittleWindowsIntent(destination: action.destination(profileID: snapshot.profileID))) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: action.systemImage)
                        .font(.headline)
                        .foregroundStyle(tint(for: action.tintName))
                        .frame(height: 20)
                    if action.resolvedIsPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(LittleWindowsWidgetStyle.lavender)
                            .offset(x: 10, y: -3)
                    }
                }
                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 37)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private func tint(for name: String) -> Color {
        switch name {
        case "cyan": .cyan
        case "green": .green
        case "indigo": LittleWindowsWidgetStyle.lavender
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        default: LittleWindowsWidgetStyle.lavender
        }
    }

    private static let fallbackActions = [
        QuickLogActionSnapshot(
            id: "tummy-time",
            title: "Tummy",
            subtitle: "Timer",
            systemImage: "figure.play",
            tintName: "green",
            destinationPath: "quick-log/tummy-time"
        ),
        QuickLogActionSnapshot(
            id: "diaper",
            title: "Diaper",
            subtitle: nil,
            systemImage: "drop.fill",
            tintName: "teal",
            destinationPath: "quick-log/diaper"
        ),
        QuickLogActionSnapshot(
            id: "temperature",
            title: "Temp",
            subtitle: nil,
            systemImage: "thermometer.medium",
            tintName: "red",
            destinationPath: "quick-log/temperature"
        ),
        QuickLogActionSnapshot(
            id: "bath",
            title: "Bath",
            subtitle: "Timer",
            systemImage: "bathtub.fill",
            tintName: "cyan",
            destinationPath: "quick-log/bath"
        ),
        QuickLogActionSnapshot(
            id: "sleep",
            title: "Sleep",
            subtitle: "Timer",
            systemImage: "moon.fill",
            tintName: "indigo",
            destinationPath: "quick-log/sleep"
        ),
        QuickLogActionSnapshot(
            id: "medicine",
            title: "Meds",
            subtitle: nil,
            systemImage: "cross.case.fill",
            tintName: "red",
            destinationPath: "quick-log/medicine"
        )
    ]
}
