import ActivityKit
import SwiftUI
import WidgetKit

struct LittleWindowsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LittleWindowsActivityAttributes.self) { context in
            let timer = context.state.timer
            let tint = LittleWindowsWidgetStyle.tint(for: timer.typeRawValue)
            ZStack {
                LittleWindowsWidgetStyle.background
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        WidgetBrandLabel()
                        Spacer()
                        Text(timer.babyName.uppercased())
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    HStack(spacing: 13) {
                        WidgetIconBadge(systemImage: timer.systemImage, tint: tint, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timer.eventLabel)
                                .font(.headline)
                            Text(timer.startDate, style: .timer)
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        Spacer()
                        Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.subheadline.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                    }
                    detailBar(for: timer, tint: tint)
                }
                .padding(16)
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
                        WidgetIconBadge(systemImage: timer.systemImage, tint: tint, size: 34)
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
                        Text("RUNNING")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(tint)
                        Text(timer.startDate, style: .timer)
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        detailBar(for: timer, tint: tint)
                        HStack(spacing: 10) {
                            if timer.typeRawValue == "nursing" {
                                Button(intent: SwitchNursingSideIntent(eventID: timer.id.uuidString)) {
                                    Label("Switch side", systemImage: "arrow.left.arrow.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            Button(intent: StopTimerIntent(eventID: timer.id.uuidString)) {
                                Label("Stop timer", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(tint)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: timer.systemImage)
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text(timer.startDate, style: .timer)
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
    private func detailBar(for timer: ActiveTimerSnapshot, tint: Color) -> some View {
        HStack(spacing: 8) {
            if let caregiver = timer.caregiverName, !caregiver.isEmpty {
                detailPill(caregiver, icon: "person.fill", tint: tint)
            }
            if timer.typeRawValue == "nursing", let side = timer.activeNursingSideRawValue {
                detailPill("\(side.capitalized) side", icon: "\(side.prefix(1)).circle.fill", tint: tint)
                if timer.leftDurationSeconds > 0 || timer.rightDurationSeconds > 0 {
                    detailPill(
                        "L \(shortDuration(timer.leftDurationSeconds)) · R \(shortDuration(timer.rightDurationSeconds))",
                        icon: "clock.fill",
                        tint: tint
                    )
                }
            }
            if timer.additionalActiveCount > 0 {
                detailPill("+\(timer.additionalActiveCount) active", icon: "plus", tint: tint)
            }
            Spacer(minLength: 0)
        }
    }

    private func detailPill(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.74))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.16), lineWidth: 0.5)
            }
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes)m"
    }
}
