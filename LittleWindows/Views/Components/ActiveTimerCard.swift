import SwiftUI

private struct CareTimerTimelineView<Content: View>: View {
    let isRunning: Bool
    private let content: (Date) -> Content

    init(
        isRunning: Bool,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self.isRunning = isRunning
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(timeline.date)
            }
        } else {
            content(Date())
        }
    }
}

struct ActiveTimerCard: View {
    let event: CareEvent
    var planWakeAlert: ActiveSleepPlanWakeAlert?
    var edit: () -> Void
    var toggleRunning: () -> Void
    var save: () -> Void
    var switchNursingSide: (() -> Void)?
    var setNursingSide: ((NursingSide) -> Void)?

    var body: some View {
        CareTimerTimelineView(isRunning: event.isTimerRunning) { date in
            VStack(alignment: .leading, spacing: 14) {
                Button(action: edit) {
                    HStack {
                        HStack(spacing: 11) {
                            Image(systemName: event.type.systemImage(for: event.profileTypeSnapshot))
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
                                    .accessibilityIdentifier(
                                        "active-timer.status.\(event.type.rawValue)"
                                    )
                                Text("Started \(DateFormatting.timeString(from: event.startDate, timeZone: event.startTimeZone, includesTimeZone: event.shouldShowTimeZoneInTimeline)) · Tap to edit")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(elapsedText(at: date))
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
                        date: date,
                        isCompact: true,
                        setNursingSide: setNursingSide,
                        switchNursingSide: switchNursingSide
                    )
                }

                if let planWakeAlert {
                    planWakeAlertRow(planWakeAlert, now: date)
                }

                HStack(spacing: 10) {
                    Button(action: toggleRunning) {
                        Label(
                            event.isTimerRunning ? "Stop" : "Resume",
                            systemImage: event.isTimerRunning ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(TimerSecondaryButtonStyle())
                    .accessibilityIdentifier("active-timer.toggle.\(event.type.rawValue)")

                    Button(action: save) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(TimerFilledButtonStyle())
                    .disabled(event.timerElapsed(at: date) < 1)
                }
            }
            .padding(16)
            .appSurface()
        }
    }

    private func elapsedText(at date: Date) -> String {
        DurationFormatting.liveString(seconds: event.timerElapsed(at: date))
    }

    private func planWakeAlertRow(
        _ alert: ActiveSleepPlanWakeAlert,
        now: Date
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: alert.wakeByDate <= now ? "bell.badge.fill" : "bell.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .background(Color.orange.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.wakeByDate <= now ? "Wake now" : "Wake by \(DateFormatting.time.string(from: alert.wakeByDate))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Keeps \(DateFormatting.time.string(from: alert.targetBedtime)) bedtime on the active plan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ActiveTimerEditorView: View {
    let event: CareEvent
    let adjustStart: (Date) -> Void
    let stop: () -> Void
    let resume: () -> Void
    let reset: () -> Void
    let save: (Date?) -> Bool
    let discard: () -> Void
    let setStartTimeZone: (String) -> Void
    let setEndTimeZone: (String) -> Void
    let switchNursingSide: (() -> Void)?
    let setNursingSide: ((NursingSide) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStart: Date
    @State private var selectedEnd: Date
    @State private var startTimeZoneIdentifier: String
    @State private var endTimeZoneIdentifier: String
    @State private var showingResetConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var showingSaveFailure = false
    @State private var finalizedEditorAction = false

    init(
        event: CareEvent,
        adjustStart: @escaping (Date) -> Void,
        stop: @escaping () -> Void,
        resume: @escaping () -> Void,
        reset: @escaping () -> Void,
        save: @escaping (Date?) -> Bool,
        discard: @escaping () -> Void,
        setStartTimeZone: @escaping (String) -> Void = { _ in },
        setEndTimeZone: @escaping (String) -> Void = { _ in },
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
        self.setStartTimeZone = setStartTimeZone
        self.setEndTimeZone = setEndTimeZone
        self.switchNursingSide = switchNursingSide
        self.setNursingSide = setNursingSide
        _selectedStart = State(initialValue: event.startDate)
        _selectedEnd = State(initialValue: Self.defaultEndDate(for: event))
        _startTimeZoneIdentifier = State(
            initialValue: event.startTimeZoneIdentifier
                ?? CareTimeZoneSettings.effectiveIdentifier()
        )
        _endTimeZoneIdentifier = State(
            initialValue: event.endTimeZoneIdentifier
                ?? CareTimeZoneSettings.effectiveIdentifier()
        )
    }

    private var startTimeZone: TimeZone {
        TimeZone(identifier: startTimeZoneIdentifier) ?? .autoupdatingCurrent
    }

    private var endTimeZone: TimeZone {
        TimeZone(identifier: endTimeZoneIdentifier) ?? startTimeZone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CareTimerTimelineView(isRunning: event.isTimerRunning) { date in
                    VStack(spacing: 12) {
                        Image(systemName: event.type.systemImage(for: event.profileTypeSnapshot))
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
                                seconds: displayedElapsed(at: date)
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
                        .accessibilityIdentifier("active-timer.elapsed")
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

                if event.type == .nursing {
                    CareTimerTimelineView(isRunning: event.isTimerRunning) { date in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label(
                                    "Nursing sides",
                                    systemImage: "figure.and.child.holdinghands"
                                )
                                .font(.headline)

                                Spacer()

                                Text("Total \(DurationFormatting.liveString(seconds: displayedElapsed(at: date)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }

                            NursingSideSelector(
                                event: event,
                                date: date,
                                isCompact: false,
                                setNursingSide: setNursingSide,
                                switchNursingSide: switchNursingSide
                            )

                            Text("Tap Left or Right whenever sides change. Each side keeps its own running total until you save the event.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .appSurface()
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Timer controls", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        Button {
                            if event.isTimerRunning {
                                apply(selectedStart)
                                stop()
                                selectedEnd = Self.defaultEndDate(for: event)
                            } else {
                                apply(selectedStart)
                                resume()
                            }
                        } label: {
                            Label(
                                event.isTimerRunning ? "Stop" : "Resume",
                                systemImage: event.isTimerRunning
                                    ? "stop.fill"
                                    : "play.fill"
                            )
                        }
                        .buttonStyle(TimerFilledButtonStyle())

                        Button {
                            showingResetConfirmation = true
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
                            : "Finish & Save commits this paused timer to history."
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
                    .environment(\.timeZone, startTimeZone)
                    .font(.body.weight(.medium))
                    .onChange(of: selectedStart) { _, newValue in
                        clampStartIfNeeded(newValue)
                    }
                    .accessibilityIdentifier("active-timer.start-date")

                    Divider()

                    if !event.isTimerRunning {
                        DatePicker(
                            "Ended",
                            selection: $selectedEnd,
                            in: selectedStart...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .environment(\.timeZone, endTimeZone)
                        .font(.body.weight(.medium))

                        Divider()
                    }

                    NavigationLink {
                        TimeZonePickerView(selection: $startTimeZoneIdentifier)
                    } label: {
                        LabeledContent(
                            "Start time zone",
                            value: CareTimeZoneSettings.displayName(
                                for: startTimeZone,
                                on: selectedStart
                            )
                        )
                    }

                    if !event.isTimerRunning {
                        Divider()

                        NavigationLink {
                            TimeZonePickerView(selection: $endTimeZoneIdentifier)
                        } label: {
                            LabeledContent(
                                "End time zone",
                                value: CareTimeZoneSettings.displayName(
                                    for: endTimeZone,
                                    on: selectedEnd
                                )
                            )
                        }
                    }

                    Text("The elapsed timer stays exact when the start and end are in different time zones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack(spacing: 8) {
                        adjustmentButton("−5 min", minutes: -5)
                        adjustmentButton("−1 min", minutes: -1)
                        adjustmentButton("+1 min", minutes: 1)
                    }
                }
                .padding(18)
                .appSurface()

                VStack(spacing: 12) {
                    Button {
                        apply(selectedStart)
                        if save(event.isTimerRunning ? nil : selectedEnd) {
                            finalizedEditorAction = true
                            dismiss()
                        } else {
                            showingSaveFailure = true
                        }
                    } label: {
                        Label(
                            "Finish & Save Event",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(TimerFilledButtonStyle(height: 58))
                    .disabled(displayedElapsed(at: Date()) < 1)
                    .accessibilityIdentifier("active-timer.finish-and-save")

                    Button {
                        showingDiscardConfirmation = true
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
                Button("Keep Timer") {
                    apply(selectedStart)
                    finalizedEditorAction = true
                    dismiss()
                }
            }
        }
        .alert("Timer wasn't saved", isPresented: $showingSaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The timer is still open. Return to Today and try again.")
        }
        .appActionSheet(
            isPresented: $showingResetConfirmation,
            title: "Reset Timer?",
            message: "This resets the elapsed time and keeps the timer editor open.",
            systemImage: "arrow.counterclockwise",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Reset Timer",
                    subtitle: "Start this timer over from now.",
                    systemImage: "arrow.counterclockwise",
                    tint: .red,
                    role: .destructive
                ) {
                    reset()
                    selectedStart = event.startDate
                    selectedEnd = Self.defaultEndDate(for: event)
                    startTimeZoneIdentifier = event.startTimeZoneIdentifier
                        ?? CareTimeZoneSettings.effectiveIdentifier()
                    endTimeZoneIdentifier = event.endTimeZoneIdentifier
                        ?? CareTimeZoneSettings.effectiveIdentifier()
                }
            ]
        )
        .appActionSheet(
            isPresented: $showingDiscardConfirmation,
            title: "Discard Timer?",
            message: "This removes the running timer without saving it to history.",
            systemImage: "trash",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Discard Timer",
                    subtitle: "Remove this timer and return to Today.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    finalizedEditorAction = true
                    discard()
                    dismiss()
                }
            ]
        )
        .onChange(of: event.startDate) { _, newValue in
            if abs(selectedStart.timeIntervalSince(newValue)) > 0.5 {
                selectedStart = newValue
            }
            if selectedEnd < newValue {
                selectedEnd = newValue
            }
        }
        .onChange(of: event.isTimerRunning) { _, isRunning in
            if !isRunning {
                selectedEnd = Self.defaultEndDate(for: event)
                endTimeZoneIdentifier = event.endTimeZoneIdentifier
                    ?? CareTimeZoneSettings.effectiveIdentifier()
            }
        }
        .onChange(of: startTimeZoneIdentifier) { oldValue, identifier in
            if endTimeZoneIdentifier == oldValue {
                endTimeZoneIdentifier = identifier
            }
            setStartTimeZone(identifier)
        }
        .onChange(of: endTimeZoneIdentifier) { _, identifier in
            setEndTimeZone(identifier)
        }
        .onDisappear {
            // DatePicker can publish many intermediate values while its wheels
            // are moving. Keep those edits local so they never enqueue a burst
            // of SwiftData writes and system-surface refreshes. Explicit editor
            // actions persist once; an interactive dismissal persists the final
            // value here after the timer UI is already offscreen.
            if !finalizedEditorAction {
                apply(selectedStart)
            }
        }
    }

    private func displayedElapsed(at date: Date) -> TimeInterval {
        max(
            0,
            event.timerElapsed(at: date)
                + event.startDate.timeIntervalSince(selectedStart)
        )
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

    private func clampStartIfNeeded(_ date: Date) {
        let clamped = min(date, Date())
        if abs(selectedStart.timeIntervalSince(clamped)) > 0.5 {
            selectedStart = clamped
        }
    }

    private func apply(_ date: Date) {
        let clamped = min(date, Date())
        guard abs(event.startDate.timeIntervalSince(clamped)) > 0.5 else { return }
        adjustStart(clamped)
    }

    private static func defaultEndDate(for event: CareEvent) -> Date {
        min(Date(), event.startDate.addingTimeInterval(event.timerElapsed()))
    }
}

private struct NursingSideSelector: View {
    let event: CareEvent
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
