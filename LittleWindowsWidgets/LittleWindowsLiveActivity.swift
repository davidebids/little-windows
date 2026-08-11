import ActivityKit
import SwiftUI
import WidgetKit

struct LittleWindowsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LittleWindowsActivityAttributes.self) { context in
            let timer = context.state.timer
            let tint = LittleWindowsWidgetStyle.tint(for: timer.typeRawValue)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(timer.resolvedIsRunning ? tint : .white.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(timer.resolvedIsRunning ? "RUNNING" : "PAUSED")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(timer.resolvedIsRunning ? tint : .white.opacity(0.62))
                    Spacer()
                    WidgetBrandLabel(compact: true)
                    Text(timer.babyName.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.58))
                }

                HStack(spacing: 11) {
                    WidgetIconBadge(systemImage: timer.systemImage, tint: tint, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(timer.typeRawValue == "nursing" ? "Nursing" : timer.eventLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if timer.typeRawValue == "nursing" {
                                Text("TOTAL")
                                    .font(.caption2.weight(.heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(tint)
                            }
                            timerDuration(for: timer)
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer(minLength: 8)
                    timerControl(for: timer, tint: tint)
                }

                if hasDetails(timer) || timer.resolvedIsRunning {
                    detailBar(
                        for: timer,
                        tint: tint,
                        includesSessionStart: true
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                ZStack {
                    LittleWindowsWidgetStyle.background
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 150, height: 150)
                        .blur(radius: 28)
                        .offset(x: 118, y: -92)
                }
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [tint, tint.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
            }
            .foregroundStyle(.white)
            .activityBackgroundTint(LittleWindowsWidgetStyle.midnight)
            .activitySystemActionForegroundColor(tint)
            .widgetURL(timer.openURL)
        } dynamicIsland: { context in
            let timer = context.state.timer
            let tint = LittleWindowsWidgetStyle.tint(for: timer.typeRawValue)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 9) {
                        WidgetIconBadge(systemImage: timer.systemImage, tint: tint, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(timer.eventLabel)
                                .font(.subheadline.weight(.semibold))
                            Text(timer.babyName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(
                            timer.typeRawValue == "nursing"
                                ? "TOTAL"
                                : (timer.resolvedIsRunning ? "RUNNING" : "PAUSED")
                        )
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(tint)
                        timerDuration(for: timer)
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if hasDetails(timer) {
                            detailBar(for: timer, tint: tint)
                        }
                        HStack(spacing: 10) {
                            if timer.typeRawValue == "nursing" {
                                Button(intent: SwitchNursingSideIntent(eventID: timer.id.uuidString)) {
                                    Label("Switch side", systemImage: "arrow.left.arrow.right")
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            if timer.resolvedIsRunning {
                                Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                                    Label("Stop timer", systemImage: "stop.fill")
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(tint)
                            } else {
                                Button(intent: ResumeTimerIntent(eventID: timer.id.uuidString)) {
                                    Label("Resume timer", systemImage: "play.fill")
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(tint)
                            }
                        }
                        if timer.resolvedIsRunning {
                            startedSinceLabel(for: timer)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: timer.systemImage)
                    .foregroundStyle(tint)
            } compactTrailing: {
                timerDuration(for: timer)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 48)
            } minimal: {
                Image(systemName: timer.systemImage)
                    .foregroundStyle(tint)
            }
            .widgetURL(timer.openURL)
            .keylineTint(tint)
        }
    }

    @ViewBuilder
    private func timerDuration(for timer: ActiveTimerSnapshot) -> some View {
        if timer.resolvedIsRunning {
            Text(timer.startDate, style: .timer)
        } else {
            Text(shortDuration(timer.resolvedElapsedSeconds))
        }
    }

    @ViewBuilder
    private func timerControl(for timer: ActiveTimerSnapshot, tint: Color) -> some View {
        if timer.resolvedIsRunning {
            Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                controlLabel("Stop", systemImage: "stop.fill", tint: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop timer")
        } else {
            Button(intent: ResumeTimerIntent(eventID: timer.id.uuidString)) {
                controlLabel("Resume", systemImage: "play.fill", tint: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume timer")
        }
    }

    private func controlLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(color: tint.opacity(0.24), radius: 7, y: 3)
    }

    private func hasDetails(_ timer: ActiveTimerSnapshot) -> Bool {
        (timer.caregiverName?.isEmpty == false)
            || (timer.typeRawValue == "nursing" && timer.activeNursingSideRawValue != nil)
            || timer.additionalActiveCount > 0
    }

    @ViewBuilder
    private func detailBar(
        for timer: ActiveTimerSnapshot,
        tint: Color,
        includesSessionStart: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if let caregiver = timer.caregiverName, !caregiver.isEmpty {
                detailPill(caregiver, icon: "person.fill", tint: tint)
            }
            if timer.typeRawValue == "nursing", let side = timer.activeNursingSideRawValue {
                nursingSidePill(for: timer, side: side, tint: tint)
            }
            if timer.additionalActiveCount > 0 {
                detailPill("+\(timer.additionalActiveCount) active", icon: "plus", tint: tint)
            }
            Spacer(minLength: includesSessionStart ? 6 : 0)
            if includesSessionStart, timer.resolvedIsRunning {
                startedSinceLabel(for: timer)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .layoutPriority(1)
            }
        }
    }

    private func nursingSidePill(
        for timer: ActiveTimerSnapshot,
        side: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "\(side.prefix(1)).circle.fill")
                .foregroundStyle(tint)
            Text(side.capitalized)
            Text("·")
                .foregroundStyle(.white.opacity(0.4))
            activeNursingSideDuration(for: timer)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.11), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.24), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func activeNursingSideDuration(for timer: ActiveTimerSnapshot) -> some View {
        if timer.resolvedIsRunning,
           let startDate = timer.activeNursingSideTimerStartDate {
            Text(startDate, style: .timer)
        } else {
            Text(shortDuration(timer.activeNursingSideElapsedSeconds))
        }
    }

    private func detailPill(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white.opacity(0.74))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.16), lineWidth: 0.5)
            }
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes)m"
    }

    private func startedSinceLabel(for timer: ActiveTimerSnapshot) -> some View {
        HStack(spacing: 3) {
            Text(timer.startedSincePrefix)
            Text(timer.resolvedSessionStartDate, style: .time)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityElement(children: .combine)
    }
}
