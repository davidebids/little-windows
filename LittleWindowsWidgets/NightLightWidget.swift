import AppIntents
import SwiftUI
import WidgetKit

private struct NightLightWidgetEntry: TimelineEntry {
    let date: Date
}

private struct NightLightWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NightLightWidgetEntry {
        NightLightWidgetEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (NightLightWidgetEntry) -> Void
    ) {
        completion(NightLightWidgetEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<NightLightWidgetEntry>) -> Void
    ) {
        completion(Timeline(
            entries: [NightLightWidgetEntry(date: Date())],
            policy: .never
        ))
    }
}

struct NightLightWidget: Widget {
    let kind = "LittleWindows.NightLight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NightLightWidgetProvider()) { _ in
            NightLightWidgetView()
                .containerBackground(for: .widget) {
                    NightLightWidgetBackground()
                }
        }
        .configurationDisplayName("Night Light")
        .description("Start a dim red diaper-change light with one tap.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct NightLightWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private let diaperLightURL = URL(
        string: "littlewindows://night-light/diaper-change"
    )!

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
        case .accessoryCircular:
            linkedAccessory {
                VStack(spacing: 1) {
                    Image(systemName: "lightbulb.min.fill")
                        .font(.title3)
                    Text("RED")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                }
                .widgetAccentable()
            }
        case .accessoryRectangular:
            linkedAccessory {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.min.fill")
                        .font(.title3)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Diaper light")
                            .font(.headline)
                        Text("Dim red · 10 min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .accessoryInline:
            linkedAccessory {
                Label("Start diaper light", systemImage: "lightbulb.min.fill")
            }
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        Link(destination: diaperLightURL) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetBrandLabel(compact: true)

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.22))
                        .frame(width: 58, height: 58)
                        .blur(radius: 5)
                    Image(systemName: "lightbulb.min.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.34, blue: 0.28))
                }

                Text("Diaper light")
                    .font(.headline)
                Text("Dim red · 10 min")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))

                Label("Tap to start", systemImage: "arrow.up.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.42))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(.white)
        }
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetBrandLabel()
                    Text("Night Light")
                        .font(.headline)
                }
                Spacer()
                Text("Tap to start")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }

            HStack(spacing: 8) {
                presetButton(
                    title: "Diaper",
                    detail: "Dim red",
                    systemImage: "lightbulb.min.fill",
                    tint: Color(red: 1, green: 0.36, blue: 0.3),
                    intent: StartDiaperChangeLightIntent()
                )
                presetButton(
                    title: "Nursing",
                    detail: "Warm amber",
                    systemImage: "heart.circle.fill",
                    tint: .orange,
                    intent: StartNursingLightIntent()
                )
                presetButton(
                    title: "Soothing",
                    detail: "Glow + sound",
                    systemImage: "moon.stars.fill",
                    tint: LittleWindowsWidgetStyle.lavender,
                    intent: StartSoothingLightIntent()
                )
            }
        }
        .foregroundStyle(.white)
    }

    private func linkedAccessory<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Link(destination: diaperLightURL) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func presetButton<I: AppIntent>(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct NightLightWidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.025, blue: 0.035),
                    Color(red: 0.25, green: 0.055, blue: 0.075),
                    LittleWindowsWidgetStyle.midnight
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.red.opacity(0.24))
                .frame(width: 170, height: 170)
                .blur(radius: 22)
                .offset(x: 92, y: -66)
        }
    }
}
