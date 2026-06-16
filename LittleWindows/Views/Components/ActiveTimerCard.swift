import SwiftUI

struct ActiveTimerCard: View {
    let event: BabyEvent
    var edit: () -> Void
    var toggleRunning: () -> Void
    var save: () -> Void
    var switchNursingSide: (() -> Void)?
    var setNursingSide: ((NursingSide) -> Void)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                Button(action: edit) {
                    HStack {
                        HStack(spacing: 11) {
                            Image(systemName: event.type.systemImage)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(event.type.tint.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.displayTitle)
                                    .font(.headline)
                                Text(event.isTimerRunning ? "Running now" : "Stopped · Ready to save")
                                    .font(.caption)
                                    .foregroundStyle(event.isTimerRunning ? .secondary : event.type.tint)
                                Text("Started \(event.startDate.formatted(date: .omitted, time: .shortened)) · Tap to edit")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(elapsedText(at: context.date))
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if event.type == .nursing {
                    NursingSideSelector(
                        event: event,
                        date: context.date,
                        isCompact: true,
                        setNursingSide: setNursingSide,
                        switchNursingSide: switchNursingSide
                    )
                }

                HStack(spacing: 10) {
                    Button(action: toggleRunning) {
                        Label(
                            event.isTimerRunning ? "Stop" : "Resume",
                            systemImage: event.isTimerRunning ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(TimerSecondaryButtonStyle())

                    Button(action: save) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(TimerFilledButtonStyle())
                    .disabled(event.timerElapsed(at: context.date) < 1)
                }
            }
            .padding(16)
            .appSurface()
        }
    }

    private func elapsedText(at date: Date) -> String {
        DurationFormatting.liveString(seconds: event.timerElapsed(at: date))
    }
}

struct ActiveTimerEditorView: View {
    let event: BabyEvent
    let adjustStart: (Date) -> Void
    let stop: () -> Void
    let resume: () -> Void
    let reset: () -> Void
    let save: () -> Void
    let discard: () -> Void
    let switchNursingSide: (() -> Void)?
    let setNursingSide: ((NursingSide) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStart: Date

    init(
        event: BabyEvent,
        adjustStart: @escaping (Date) -> Void,
        stop: @escaping () -> Void,
        resume: @escaping () -> Void,
        reset: @escaping () -> Void,
        save: @escaping () -> Void,
        discard: @escaping () -> Void,
        switchNursingSide: (() -> Void)? = nil,
        setNursingSide: ((NursingSide) -> Void)? = nil
    ) {
        self.event = event
        self.adjustStart = adjustStart
        self.stop = stop
        self.resume = resume
        self.reset = reset
        self.save = save
        self.discard = discard
        self.switchNursingSide = switchNursingSide
        self.setNursingSide = setNursingSide
        _selectedStart = State(initialValue: event.startDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 12) {
                        Image(systemName: event.type.systemImage)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(
                                event.type.tint.gradient,
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                            .shadow(
                                color: event.type.tint.opacity(0.28),
                                radius: 12,
                                y: 6
                            )
                        Text(event.displayTitle)
                            .font(.title3.bold())
                        Text(
                            DurationFormatting.liveString(
                                seconds: event.timerElapsed(at: context.date)
                            )
                        )
                        .font(
                            .system(
                                size: 46,
                                weight: .bold,
                                design: .rounded
                            )
                            .monospacedDigit()
                        )
                        .contentTransition(.numericText())
                        Label(
                            event.isTimerRunning ? "Running" : "Stopped",
                            systemImage: event.isTimerRunning
                                ? "record.circle.fill"
                                : "pause.circle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            event.isTimerRunning ? Color.green : Color.secondary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            event.isTimerRunning
                                ? Color.green.opacity(0.12)
                                : Color.secondary.opacity(0.1),
                            in: Capsule()
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 18)
                    .appSurface(cornerRadius: 28)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Timer controls", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        Button {
                            event.isTimerRunning ? stop() : resume()
                        } label: {
                            Label(
                                event.isTimerRunning ? "Stop" : "Resume",
                                systemImage: event.isTimerRunning
                                    ? "stop.fill"
                                    : "play.fill"
                            )
                        }
                        .buttonStyle(TimerFilledButtonStyle())

                        Menu {
                            Button("Reset Timer", role: .destructive) {
                                reset()
                                selectedStart = event.startDate
                            }
                        } label: {
                            Label(
                                "Reset",
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                        .buttonStyle(TimerSecondaryButtonStyle())
                    }

                    Text(
                        event.isTimerRunning
                            ? "Stop pauses the timer without saving it."
                            : "Resume continues from the saved duration."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
                .appSurface()

                VStack(alignment: .leading, spacing: 16) {
                    Label("Start time", systemImage: "clock.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    DatePicker(
                        "Started",
                        selection: $selectedStart,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.body.weight(.medium))
                    .onChange(of: selectedStart) { _, newValue in
                        apply(newValue)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        adjustmentButton("−5 min", minutes: -5)
                        adjustmentButton("−1 min", minutes: -1)
                        adjustmentButton("+1 min", minutes: 1)
                    }
                }
                .padding(18)
                .appSurface()

                if event.type == .nursing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label(
                                    "Nursing sides",
                                    systemImage: "figure.and.child.holdinghands"
                                )
                                .font(.headline)

                                Spacer()

                                Text("Total \(DurationFormatting.liveString(seconds: event.timerElapsed(at: context.date)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }

                            NursingSideSelector(
                                event: event,
                                date: context.date,
                                isCompact: false,
                                setNursingSide: setNursingSide,
                                switchNursingSide: switchNursingSide
                            )

                            Text("Tap Left or Right whenever Ethan changes sides. Each side keeps its own running total until you save the event.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .appSurface()
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Label(
                            "Save Event",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(TimerFilledButtonStyle(height: 58))
                    .disabled(event.timerElapsed() < 1)

                    Menu {
                        Button("Discard Timer", role: .destructive) {
                            discard()
                            dismiss()
                        }
                    } label: {
                        Label("Discard Timer", systemImage: "trash")
                    }
                    .buttonStyle(TimerDestructiveButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .navigationTitle("Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onChange(of: event.startDate) { _, newValue in
            if abs(selectedStart.timeIntervalSince(newValue)) > 0.5 {
                selectedStart = newValue
            }
        }
    }

    private func adjustmentButton(
        _ title: String,
        minutes: Double
    ) -> some View {
        Button(title) {
            selectedStart = min(
                Date(),
                selectedStart.addingTimeInterval(minutes * 60)
            )
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.accent)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            AppTheme.accent.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func apply(_ date: Date) {
        let clamped = min(date, Date())
        if abs(selectedStart.timeIntervalSince(clamped)) > 0.5 {
            selectedStart = clamped
        }
        adjustStart(clamped)
    }
}

private struct NursingSideSelector: View {
    let event: BabyEvent
    let date: Date
    var isCompact = false
    var setNursingSide: ((NursingSide) -> Void)?
    var switchNursingSide: (() -> Void)?

    private var activeSide: NursingSide {
        event.activeNursingSide ?? event.nursingSide ?? .left
    }

    private var sideDurations: [NursingSide: TimeInterval] {
        var left = event.leftDurationSeconds ?? 0
        var right = event.rightDurationSeconds ?? 0
        if event.isTimerRunning {
            let reference = event.activeTimerSegmentStartDate ?? event.startDate
            let elapsed = max(0, date.timeIntervalSince(reference))
            switch activeSide {
            case .left:
                left += elapsed
            case .right:
                right += elapsed
            }
        }
        return [.left: left, .right: right]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 12) {
            HStack(spacing: isCompact ? 8 : 12) {
                ForEach(NursingSide.allCases) { side in
                    Button {
                        choose(side)
                    } label: {
                        NursingSideTile(
                            side: side,
                            seconds: sideDurations[side] ?? 0,
                            isActive: activeSide == side,
                            isRunning: event.isTimerRunning,
                            isCompact: isCompact
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(setNursingSide == nil && switchNursingSide == nil)
                }
            }

            if isCompact {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Tap a side to switch")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func choose(_ side: NursingSide) {
        if activeSide == side { return }
        if let setNursingSide {
            setNursingSide(side)
        } else {
            switchNursingSide?()
        }
    }
}

private struct NursingSideTile: View {
    let side: NursingSide
    let seconds: TimeInterval
    let isActive: Bool
    let isRunning: Bool
    let isCompact: Bool

    private var activeLabel: String {
        isRunning ? "Timing" : "Selected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 9) {
            HStack {
                Image(systemName: side == .left ? "l.circle.fill" : "r.circle.fill")
                    .font(isCompact ? .subheadline : .title3)
                Text(side.displayName)
                    .font(isCompact ? .subheadline.weight(.bold) : .headline)
                Spacer(minLength: 4)
                if isActive {
                    Text(activeLabel)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }

            Text(durationText(seconds))
                .font(
                    .system(
                        isCompact ? .subheadline : .title2,
                        design: .rounded
                    )
                    .weight(.bold)
                    .monospacedDigit()
                )

            if !isCompact {
                Text(isActive ? "Current side" : "Tap to switch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isActive ? .white.opacity(0.82) : Color.pink.opacity(0.9))
                    .padding(.horizontal, isActive ? 0 : 8)
                    .padding(.vertical, isActive ? 0 : 4)
                    .background {
                        if !isActive {
                            Capsule()
                                .fill(Color.pink.opacity(0.12))
                        }
                    }
            }
        }
        .foregroundStyle(isActive ? .white : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 12 : 15)
        .background {
            RoundedRectangle(cornerRadius: isCompact ? 16 : 20)
                .fill(background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 16 : 20)
                .stroke(
                    isActive ? .white.opacity(0.2) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        }
        .shadow(
            color: isActive ? Color.pink.opacity(0.18) : .clear,
            radius: 10,
            y: 5
        )
    }

    private var background: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.pink.opacity(0.86),
                        Color(red: 0.77, green: 0.32, blue: 0.66)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            Color.primary.opacity(0.045)
        )
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct TimerFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.accent.opacity(0.86),
                        AppTheme.accent
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(
                color: AppTheme.accent.opacity(
                    configuration.isPressed ? 0.12 : 0.24
                ),
                radius: configuration.isPressed ? 4 : 10,
                y: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(
                .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}

private struct TimerSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                AppTheme.accent.opacity(configuration.isPressed ? 0.15 : 0.09),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct TimerDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Color.red.opacity(configuration.isPressed ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
