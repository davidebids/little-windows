import SwiftUI

struct PredictionCard: View {
    let prediction: SleepPrediction?
    let babyName: String
    var awakeSinceDate: Date?
    var sleepPressure: ((Date) -> SleepPressure?)?
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

                if let pressure = sleepPressure?(now) {
                    sleepPressureMeter(pressure, now: now)
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

    private func sleepPressureMeter(_ pressure: SleepPressure, now: Date) -> some View {
        let color = pressureColor(pressure.band)
        let score = pressure.score ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: pressure.band.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(pressure.band.statusText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(pressureSubtitle(pressure, now: now))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let score = pressure.score {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(score.rounded()))")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(color)
                        Text("pressure")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                } else {
                    Text("Learning")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: pressureGradientColors(pressure.band),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geometry.size.width * score / 100))
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            if index > 0 {
                                Rectangle()
                                    .fill(.white.opacity(0.30))
                                    .frame(width: 1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .frame(height: 9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pressureAccessibilityLabel(pressure, now: now))
    }

    private func pressureSubtitle(_ pressure: SleepPressure, now: Date) -> String {
        if pressure.score == nil {
            return "Pressure appears after 4 months and completed sleep logs."
        }
        let awake = pressure.awakeMinutes.map { DurationFormatting.string(seconds: $0 * 60) } ?? nil
        switch pressure.band {
        case .learning:
            return "Learning from completed sleep logs."
        case .low:
            return awake.map { "Awake \($0); pressure is still low." } ?? "Pressure is still low."
        case .building:
            if let readyAt = pressure.readyAt, readyAt > now {
                return "Ready range around \(DateFormatting.time.string(from: readyAt))."
            }
            return awake.map { "Awake \($0); nearing the ready range." } ?? "Nearing the ready range."
        case .ready:
            if let highAt = pressure.highAt, highAt > now {
                return "Ready now; high around \(DateFormatting.time.string(from: highAt))."
            }
            return "Ready now; watch the next sleep window."
        case .high:
            return awake.map { "Awake \($0); pressure is above the usual range." } ?? "Pressure is above the usual range."
        }
    }

    private func pressureAccessibilityLabel(_ pressure: SleepPressure, now: Date) -> String {
        if let score = pressure.score {
            return "Sleep pressure \(pressure.band.displayName), \(Int(score.rounded())) out of 100. \(pressureSubtitle(pressure, now: now))"
        }
        return "Sleep pressure learning rhythm. \(pressureSubtitle(pressure, now: now))"
    }

    private func pressureColor(_ band: SleepPressureBand) -> Color {
        switch band {
        case .learning: return .white.opacity(0.72)
        case .low: return .cyan
        case .building: return .teal
        case .ready: return .green
        case .high: return .orange
        }
    }

    private func pressureGradientColors(_ band: SleepPressureBand) -> [Color] {
        switch band {
        case .learning:
            return [.white.opacity(0.20), .white.opacity(0.32)]
        case .low:
            return [.cyan.opacity(0.55), .cyan]
        case .building:
            return [.cyan.opacity(0.55), .teal]
        case .ready:
            return [.teal.opacity(0.65), .green]
        case .high:
            return [.yellow.opacity(0.78), .orange]
        }
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
