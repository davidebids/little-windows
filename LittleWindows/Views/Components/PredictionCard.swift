import SwiftUI

struct PredictionCard: View {
    let prediction: SleepPrediction?
    let babyName: String
    var awakeSinceDate: Date?
    var alertStatusText: String?
    var alertsEnabled = false
    var toggleAlerts: (() -> Void)?
    var showBackwardsPlanner: (() -> Void)?
    var showExplanation: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            cardContent(now: context.date)
        }
    }

    private func cardContent(now: Date) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.11, blue: 0.27),
                    Color(red: 0.24, green: 0.20, blue: 0.55),
                    Color(red: 0.32, green: 0.27, blue: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 2)
                .offset(x: 130, y: -95)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 130, height: 130)
                .blur(radius: 18)
                .offset(x: -145, y: 105)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("NEXT SLEEP", systemImage: "moon.stars.fill")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.76))
                    Spacer()
                    if let prediction {
                        confidenceStatus(prediction)
                    }
                }

                if let awakeSinceDate, awakeSinceDate <= now {
                    awakeBanner(since: awakeSinceDate, now: now)
                }

                if let prediction {
                    let phase = PredictionTiming.phase(
                        windowStart: prediction.predictedWindowStart,
                        windowEnd: prediction.predictedWindowEnd,
                        now: now
                    )
                    let countdown = countdownText(
                        prediction: prediction,
                        phase: phase,
                        now: now
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(headlineText(prediction: prediction, phase: phase))
                            .font(
                                .system(
                                    size: 42,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)

                            Spacer(minLength: 0)

                            timingStatus(countdown, phase: phase)
                        }
                        Text(
                            subtitleText(
                                prediction: prediction,
                                phase: phase,
                                now: now
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    HStack(spacing: 10) {
                        Label(
                            windowText(prediction: prediction, phase: phase),
                            systemImage: "clock.fill"
                        )
                        .font(.subheadline.weight(.semibold))

                        Spacer()

                        if let showBackwardsPlanner {
                            Button(action: showBackwardsPlanner) {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar.badge.clock")
                                    Text("Plan")
                                }
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: showExplanation) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("Why")
                            }
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                    }

                    if let alertText = resolvedAlertStatus(phase: phase) {
                        HStack(spacing: 8) {
                            Image(systemName: alertsEnabled ? "bell.fill" : "bell.slash.fill")
                                .foregroundStyle(alertsEnabled ? Color.yellow : .white.opacity(0.58))
                            Text(alertText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.76))
                                .lineLimit(2)
                            Spacer()
                            if let toggleAlerts {
                                Button(alertsEnabled ? "Alerts on" : "Notify me") {
                                    toggleAlerts()
                                }
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.white.opacity(0.12), in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Learning \(babyName)'s rhythm")
                            .font(.title2.bold())
                        Text("Complete a sleep log and the next personalized window will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                        if let showBackwardsPlanner {
                            Button(action: showBackwardsPlanner) {
                                Label("Plan bedtime", systemImage: "calendar.badge.clock")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: Color.indigo.opacity(0.18), radius: 20, y: 10)
    }

    private func headlineText(
        prediction: SleepPrediction,
        phase: PredictionTimingPhase
    ) -> String {
        if phase == .overdue { return "Now" }
        return DateFormatting.time.string(from: prediction.predictedStart)
    }

    private func countdownText(
        prediction: SleepPrediction,
        phase: PredictionTimingPhase,
        now: Date
    ) -> String {
        if phase == .overdue { return "Overdue" }
        if phase == .inWindow, prediction.predictedStart <= now { return "Likely now" }
        return PredictionCountdownFormatting.text(
            until: prediction.predictedStart,
            from: now
        )
    }

    private func subtitleText(
        prediction: SleepPrediction,
        phase: PredictionTimingPhase,
        now: Date
    ) -> String {
        let kind = prediction.predictionKind.displayName.lowercased()
        switch phase {
        case .upcoming:
            return "Expected \(kind)"
        case .inWindow:
            return prediction.predictedStart > now
                ? "Expected \(kind)"
                : "Likely \(kind) now"
        case .overdue:
            return "\(prediction.predictionKind.displayName) may be overdue"
        }
    }

    private func windowText(
        prediction: SleepPrediction,
        phase: PredictionTimingPhase
    ) -> String {
        switch phase {
        case .upcoming:
            return "Likely window: \(formattedWindow(prediction))"
        case .inWindow:
            return "In likely window: \(formattedWindow(prediction))"
        case .overdue:
            return "Previous window ended \(DateFormatting.time.string(from: prediction.predictedWindowEnd))"
        }
    }

    private func formattedWindow(_ prediction: SleepPrediction) -> String {
        DateFormatting.window(
            start: prediction.predictedWindowStart,
            end: prediction.predictedWindowEnd
        )
    }

    private func confidenceStatus(_ prediction: SleepPrediction) -> some View {
        let isLow = prediction.confidenceLabel == .low
        return HStack(spacing: 5) {
            Image(systemName: isLow ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isLow ? Color.orange : .white.opacity(0.58))
            Text("\(prediction.confidenceLabel.displayName) confidence")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isLow ? Color.orange : .white.opacity(0.66))
        }
        .accessibilityElement(children: .combine)
    }

    private func timingStatus(
        _ text: String,
        phase: PredictionTimingPhase
    ) -> some View {
        HStack(spacing: 5) {
            if phase == .overdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orange)
            }
            Text(text)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(phase == .overdue ? Color.orange : .white.opacity(0.82))
        }
        .accessibilityLabel(text)
    }

    private func awakeBanner(since date: Date, now: Date) -> some View {
        let duration = DurationFormatting.string(seconds: now.timeIntervalSince(date))
        return HStack(spacing: 9) {
            Image(systemName: "sun.max.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.yellow)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.12), in: Circle())
            Text("\(babyName) has been up for \(duration)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel("\(babyName) has been up for \(duration)")
    }

    private func resolvedAlertStatus(phase: PredictionTimingPhase) -> String? {
        guard let alertStatusText else { return nil }
        let timingStatuses = [
            "This alert time has passed",
            "Lead time passed - window starts soon",
            "You're in the likely sleep window",
            "Likely sleep window has passed"
        ]
        guard timingStatuses.contains(alertStatusText) else {
            return alertStatusText
        }
        switch phase {
        case .upcoming:
            return "Lead time passed - alert window starts soon"
        case .inWindow:
            return "You're in the likely sleep window"
        case .overdue:
            return "Likely sleep window has passed"
        }
    }
}
