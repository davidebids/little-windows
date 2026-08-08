import SwiftUI
import WidgetKit

private struct ActiveTimerEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

private struct ActiveTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveTimerEntry {
        ActiveTimerEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveTimerEntry) -> Void) {
        completion(ActiveTimerEntry(date: Date(), snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveTimerEntry>) -> Void) {
        let entry = ActiveTimerEntry(date: Date(), snapshot: WidgetSnapshotReader.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct ActiveTimerWidget: Widget {
    let kind = "LittleWindows.ActiveTimer"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveTimerProvider()) { entry in
            ActiveTimerWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LittleWindowsWidgetStyle.background
                }
        }
        .configurationDisplayName("Active Timer")
        .description("Run, stop, resume, and review the current timer draft.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct ActiveTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        if snapshot.profileID == nil {
            missingProfileContent
        } else if let timer = snapshot.activeTimer {
            switch family {
            case .accessoryInline:
                Label {
                    if timer.typeRawValue == "nursing",
                       let side = timer.activeNursingSideRawValue {
                        HStack(spacing: 3) {
                            Text("Total")
                            timerDuration(timer)
                            Text("· \(side.prefix(1).uppercased())")
                            activeNursingSideDuration(timer)
                        }
                    } else if timer.resolvedIsRunning {
                        Text("\(timer.eventLabel) · \(timer.startDate, style: .timer)")
                    } else {
                        Text("\(timer.eventLabel) stopped · \(elapsedText(timer))")
                    }
                } icon: {
                    Image(systemName: timer.systemImage)
                }
                .widgetAccentable()
            case .accessoryRectangular:
                Link(destination: timer.openURL) {
                    HStack(spacing: 9) {
                        Image(systemName: timer.systemImage)
                            .font(.title3.weight(.semibold))
                            .widgetAccentable()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(timer.typeRawValue == "nursing" ? "Nursing" : timer.eventLabel)
                                .font(.caption.weight(.semibold))
                            if timer.typeRawValue == "nursing",
                               let side = timer.activeNursingSideRawValue {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("Total")
                                        .font(.caption2.weight(.semibold))
                                    timerDuration(timer)
                                        .font(.headline.monospacedDigit())
                                }
                                HStack(spacing: 3) {
                                    Text(side.capitalized)
                                    activeNursingSideDuration(timer)
                                        .monospacedDigit()
                                }
                                .font(.caption2.weight(.semibold))
                            } else if timer.resolvedIsRunning {
                                Text(timer.startDate, style: .timer)
                                    .font(.headline.monospacedDigit())
                            } else {
                                Text("\(elapsedText(timer)) · Stopped")
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
            case .systemSmall:
                if timer.typeRawValue == "nursing",
                   timer.activeNursingSideRawValue != nil {
                    smallNursingTimer(timer)
                } else {
                    smallTimer(timer)
                }
            default:
                mediumTimer(timer)
            }
        } else {
            Link(destination: URL(string: "littlewindows://today")!) {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetBrandLabel()
                    Spacer()
                    WidgetIconBadge(
                        systemImage: "timer",
                        tint: LittleWindowsWidgetStyle.lavender
                    )
                    Text("Ready when you are")
                        .font(.headline)
                    Text("Tap to start a timer")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                }
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var missingProfileContent: some View {
        let destination = URL(string: "littlewindows://active-timer")!
        switch family {
        case .accessoryInline:
            Link(destination: destination) {
                Label("Add care profile", systemImage: "person.crop.circle.badge.plus")
                    .widgetAccentable()
            }
        case .accessoryRectangular:
            Link(destination: destination) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Care timers")
                            .font(.headline)
                        Text("Add a care profile")
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .widgetAccentable()
                }
            }
        default:
            Link(destination: destination) {
                CareProfileRequiredWidgetState(
                    title: "Care timers",
                    detail: "Add a care profile to start and manage care timers.",
                    systemImage: "timer"
                )
            }
        }
    }

    private func smallTimer(_ timer: ActiveTimerSnapshot) -> some View {
        let tint = LittleWindowsWidgetStyle.tint(for: timer.typeRawValue)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetBrandLabel(compact: true)
                Spacer()
                if timer.additionalActiveCount > 0 {
                    Text("+\(timer.additionalActiveCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.11), in: Capsule())
                }
            }
            Spacer(minLength: 6)
            WidgetIconBadge(systemImage: timer.systemImage, tint: tint, size: 38)
            Text(timer.eventLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 7)
            timerDuration(timer)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.74)
            Spacer(minLength: 6)
            if timer.resolvedIsRunning {
                Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                    Label("Stop", systemImage: "stop.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            } else {
                Button(intent: ResumeTimerIntent(eventID: timer.id.uuidString)) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .widgetURL(timer.openURL)
    }

    private func smallNursingTimer(_ timer: ActiveTimerSnapshot) -> some View {
        let tint = LittleWindowsWidgetStyle.tint(for: timer.typeRawValue)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetBrandLabel(compact: true)
                Spacer()
                Image(systemName: timer.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: Circle())
            }
            Spacer(minLength: 4)
            Text("NURSING")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("TOTAL")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(tint)
                    timerDuration(timer)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1, height: 31)
                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.activeNursingSideRawValue?.uppercased() ?? "SIDE")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(tint)
                    activeNursingSideDuration(timer)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 5)
            if timer.resolvedIsRunning {
                Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            } else {
                Button(intent: ResumeTimerIntent(eventID: timer.id.uuidString)) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .widgetURL(timer.openURL)
    }

    private func mediumTimer(_ timer: ActiveTimerSnapshot) -> some View {
        let tint = LittleWindowsWidgetStyle.tint(for: timer.typeRawValue)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetBrandLabel()
                Spacer()
                HStack(spacing: 11) {
                    WidgetIconBadge(systemImage: timer.systemImage, tint: tint, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.typeRawValue == "nursing" ? "Nursing" : timer.eventLabel)
                            .font(.headline)
                        Text(timer.babyName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                if timer.typeRawValue == "nursing",
                   let side = timer.activeNursingSideRawValue {
                    HStack(spacing: 4) {
                        Image(systemName: "\(side.prefix(1)).circle.fill")
                        Text(side.capitalized)
                        activeNursingSideDuration(timer)
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                } else if timer.additionalActiveCount > 0 {
                    Text("+\(timer.additionalActiveCount) more active")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                Text(
                    timer.typeRawValue == "nursing"
                        ? "TOTAL"
                        : (timer.resolvedIsRunning ? "RUNNING" : "STOPPED")
                )
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(tint)
                timerDuration(timer)
                    .font(.title.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 8) {
                    Link(destination: timer.openURL) {
                        Image(systemName: "arrow.up.forward")
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.bordered)
                    if timer.resolvedIsRunning {
                        Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                    } else {
                        Button(intent: ResumeTimerIntent(eventID: timer.id.uuidString)) {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                    }
                }
                .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .widgetURL(timer.openURL)
    }

    @ViewBuilder
    private func timerDuration(_ timer: ActiveTimerSnapshot) -> some View {
        if timer.resolvedIsRunning {
            Text(timer.startDate, style: .timer)
        } else {
            Text(elapsedText(timer))
        }
    }

    @ViewBuilder
    private func activeNursingSideDuration(_ timer: ActiveTimerSnapshot) -> some View {
        if timer.resolvedIsRunning,
           let startDate = timer.activeNursingSideTimerStartDate {
            Text(startDate, style: .timer)
        } else {
            Text(elapsedText(seconds: timer.activeNursingSideElapsedSeconds))
        }
    }

    private func elapsedText(_ timer: ActiveTimerSnapshot) -> String {
        elapsedText(seconds: timer.resolvedElapsedSeconds)
    }

    private func elapsedText(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}
