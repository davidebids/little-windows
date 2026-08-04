import SwiftUI
import WatchKit

private enum WatchTheme {
    static let accent = Color.indigo
    static let surface = Color.white.opacity(0.075)
    static let line = Color.white.opacity(0.11)
    static let background = LinearGradient(
        colors: [
            Color.black,
            Color.indigo.opacity(0.18),
            Color.black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension View {
    func watchSurface(cornerRadius: CGFloat = 18) -> some View {
        background(
            WatchTheme.surface,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(WatchTheme.line, lineWidth: 0.75)
        }
    }
}

struct WatchHomeView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background
                    .ignoresSafeArea()

                Group {
                    if connectivity.state.profiles.isEmpty {
                        VStack(spacing: 8) {
                            brandHeader
                            unavailableView
                        }
                    } else {
                        homeContent
                    }
                }
            }
            .alert("Couldn’t apply action", isPresented: Binding(
                get: { connectivity.lastErrorMessage != nil },
                set: { if !$0 { connectivity.lastErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(connectivity.lastErrorMessage ?? "Please try again.")
            }
        }
        .tint(WatchTheme.accent)
    }

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                brandHeader
                profilePicker

                if let timer = connectivity.state.activeTimer {
                    ActiveWatchTimerCard(timer: timer)
                }

                if let prediction = connectivity.state.prediction {
                    WatchPredictionCard(prediction: prediction)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(WatchTheme.accent)
                        Text("Quick log")
                            .font(.headline)
                        Spacer()
                        Text("Favorites")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(connectivity.state.favoriteActions) { action in
                            WatchActionTile(action: action)
                        }
                    }
                }

                NavigationLink {
                    WatchAllActionsView(actions: connectivity.state.allActions)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(WatchTheme.accent.gradient, in: Circle())
                        Text("All Actions")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .watchSurface(cornerRadius: 15)
                }
                .buttonStyle(.plain)

                if !connectivity.state.todayMetrics.isEmpty {
                    WatchTodaySummary(metrics: connectivity.state.todayMetrics)
                }

                syncStatus
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .refreshable { connectivity.requestRefresh() }
    }

    private var brandHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "macwindow")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(WatchTheme.accent.gradient, in: RoundedRectangle(
                    cornerRadius: 7,
                    style: .continuous
                ))
            Text("Little Windows")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !connectivity.pendingCommandIDs.isEmpty {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Changes pending sync")
            }
        }
        .padding(.horizontal, 4)
    }

    private var profilePicker: some View {
        NavigationLink {
            WatchProfilePickerView()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selectedProfileIsDog
                    ? "pawprint.fill"
                    : "figure.and.child.holdinghands")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(profileTint.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(connectivity.state.selectedProfile?.name ?? "Choose profile")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(selectedProfileIsDog ? "Dog profile" : "Child profile")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(
                LinearGradient(
                    colors: [profileTint.opacity(0.24), WatchTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(profileTint.opacity(0.26), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selected profile, \(connectivity.state.selectedProfile?.name ?? "none")")
    }

    private var selectedProfileIsDog: Bool {
        connectivity.state.selectedProfile?.profileTypeRawValue == "dog"
    }

    private var profileTint: Color {
        WatchTint.color(
            connectivity.state.selectedProfile?.displayColor
                ?? (selectedProfileIsDog ? "teal" : "indigo")
        )
    }

    private var syncStatus: some View {
        HStack(spacing: 5) {
            Image(systemName: connectivity.pendingCommandIDs.isEmpty
                ? (connectivity.isReachable ? "checkmark.icloud.fill" : "iphone.slash")
                : "arrow.triangle.2.circlepath")
            Text(connectivity.pendingCommandIDs.isEmpty
                ? (connectivity.isReachable ? "Synced" : "Last updated \(relativeDate)")
                : "\(connectivity.pendingCommandIDs.count) pending")
        }
        .font(.caption2)
        .foregroundStyle(connectivity.pendingCommandIDs.isEmpty ? Color.secondary : Color.orange)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.045), in: Capsule())
    }

    private var relativeDate: String {
        connectivity.state.generatedAt.formatted(.relative(presentation: .numeric))
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Connect Little Windows", systemImage: "iphone.and.arrow.forward")
        } description: {
            Text("Open Little Windows on your iPhone once to send profiles and care actions to this watch.")
        } actions: {
            Button("Try Again") { connectivity.requestRefresh() }
        }
    }
}

private struct WatchProfilePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: WatchConnectivityClient

    var body: some View {
        List(connectivity.state.profiles) { profile in
            Button {
                connectivity.selectProfile(profile.id)
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: profile.profileTypeRawValue == "dog"
                        ? "pawprint.fill"
                        : "figure.and.child.holdinghands")
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            WatchTint.color(profile.displayColor ?? "indigo").gradient,
                            in: Circle()
                        )
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if profile.id == connectivity.state.selectedProfileID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WatchTheme.accent)
                    }
                }
            }
        }
        .navigationTitle("Profiles")
    }
}

private struct WatchActionTile: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    let action: WatchActionSnapshot

    var body: some View {
        Group {
            if action.startsTimer {
                NavigationLink {
                    WatchTimerStartView(action: action)
                } label: {
                    label
                }
            } else if action.requiresChoice {
                NavigationLink {
                    WatchActionOptionsView(action: action)
                } label: {
                    label
                }
            } else {
                Button {
                    connectivity.perform(action)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    label
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: Circle())
            Text(action.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if let subtitle = action.subtitle {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.18), WatchTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 0.75)
        }
    }

    private var tint: Color { WatchTint.color(action.tintName) }
}

private enum WatchTimerStartMode: String, CaseIterable, Identifiable {
    case now
    case earlier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .earlier: "Earlier"
        }
    }
}

private struct WatchTimerStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: WatchConnectivityClient

    let action: WatchActionSnapshot

    @State private var selectedOptionID: String
    @State private var startMode = WatchTimerStartMode.now
    @State private var manualStartTime: Date

    init(action: WatchActionSnapshot) {
        self.action = action
        let now = Date()
        _selectedOptionID = State(initialValue: action.options.first?.id ?? "")
        _manualStartTime = State(initialValue: WatchTimerStartPolicy.normalizedManualStart(
            now.addingTimeInterval(-5 * 60),
            now: now
        ))
    }

    var body: some View {
        List {
            if action.requiresChoice {
                Section(action.id == "nursing" ? "Side" : "Type") {
                    Picker("Choice", selection: $selectedOptionID) {
                        ForEach(action.options) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option.id)
                        }
                    }
                }
            }

            Section("Start time") {
                HStack(spacing: 6) {
                    ForEach(WatchTimerStartMode.allCases) { mode in
                        Button {
                            if mode == .earlier, startMode != .earlier {
                                let now = Date()
                                manualStartTime = WatchTimerStartPolicy.normalizedManualStart(
                                    now.addingTimeInterval(-5 * 60),
                                    now: now
                                )
                            }
                            startMode = mode
                        } label: {
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    startMode == mode
                                        ? WatchTint.color(action.tintName).opacity(0.28)
                                        : WatchTheme.surface,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            startMode == mode
                                                ? WatchTint.color(action.tintName).opacity(0.7)
                                                : Color.secondary.opacity(0.2),
                                            lineWidth: 0.75
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            startMode == mode ? .isSelected : []
                        )
                    }
                }

                if startMode == .earlier {
                    DatePicker(
                        "Started at",
                        selection: $manualStartTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .accessibilityHint("Choose the timer start time")

                    Text("Set the exact time • 1-minute steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    startTimer()
                } label: {
                    Label(
                        startMode == .now
                            ? "Start Now"
                            : "Start at \(manualStartLabel)",
                        systemImage: "play.fill"
                    )
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                }
                .tint(WatchTint.color(action.tintName))
                .disabled(action.requiresChoice && selectedOptionID.isEmpty)
            }
        }
        .navigationTitle(action.title)
    }

    private func startTimer() {
        let optionID = selectedOptionID.isEmpty ? nil : selectedOptionID
        let timerStartDate = startMode == .earlier
            ? WatchTimerStartPolicy.resolvedTimeOfDayStart(
                manualStartTime,
                now: Date()
            )
            : nil
        guard connectivity.perform(
            action,
            optionID: optionID,
            timerStartDate: timerStartDate
        ) else {
            return
        }
        WKInterfaceDevice.current().play(.click)
        dismiss()
    }

    private var manualStartLabel: String {
        manualStartTime.formatted(date: .omitted, time: .shortened)
    }
}

private struct WatchActionOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    let action: WatchActionSnapshot

    var body: some View {
        List(action.options) { option in
            Button {
                connectivity.perform(action, optionID: option.id)
                WKInterfaceDevice.current().play(.click)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: option.systemImage)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(WatchTint.color(action.tintName).gradient, in: Circle())
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }
        }
        .navigationTitle(action.title)
    }
}

private struct WatchAllActionsView: View {
    let actions: [WatchActionSnapshot]

    private var timers: [WatchActionSnapshot] {
        actions.filter(\.startsTimer)
    }

    private var quickLogs: [WatchActionSnapshot] {
        actions.filter { action in !timers.contains(where: { $0.id == action.id }) }
    }

    var body: some View {
        List {
            if !timers.isEmpty {
                Section("Timers") {
                    ForEach(timers) { WatchActionRow(action: $0) }
                }
            }
            if !quickLogs.isEmpty {
                Section("Quick Logs") {
                    ForEach(quickLogs) { WatchActionRow(action: $0) }
                }
            }
        }
        .navigationTitle("All Actions")
    }
}

private struct WatchActionRow: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    let action: WatchActionSnapshot

    var body: some View {
        Group {
            if action.startsTimer {
                NavigationLink {
                    WatchTimerStartView(action: action)
                } label: {
                    rowLabel
                }
            } else if action.requiresChoice {
                NavigationLink {
                    WatchActionOptionsView(action: action)
                } label: {
                    rowLabel
                }
            } else {
                Button {
                    connectivity.perform(action)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    rowLabel
                }
            }
        }
        .tint(WatchTint.color(action.tintName))
    }

    private var rowLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: action.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(WatchTint.color(action.tintName).gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ActiveWatchTimerCard: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    @State private var confirmingDiscard = false
    let timer: WatchTimerSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 9) {
                timerHeader

                VStack(spacing: 1) {
                    Text("TOTAL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(duration(timer.elapsed(at: context.date)))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(timer.isRunning ? runningDetail : "Draft paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(timer.isRunning ? timerTint : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))

                if isNursing {
                    HStack(spacing: 6) {
                        nursingSide(
                            "left",
                            seconds: timer.leftDuration(at: context.date)
                        )
                        nursingSide(
                            "right",
                            seconds: timer.rightDuration(at: context.date)
                        )
                    }

                    Button {
                        connectivity.switchNursingSide()
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text(timer.activeNursingSideRawValue == "left"
                                ? "Switch to Right"
                                : "Switch to Left")
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(timerTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(timerTint.opacity(0.24), lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(.plain)
                }

                timerControls
            }
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [timerTint.opacity(0.24), WatchTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(timerTint.opacity(0.28), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private var timerHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: timer.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(timerTint.gradient, in: Circle())
            Text(timer.title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Circle()
                    .fill(timer.isRunning ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                Text(timer.isRunning ? "LIVE" : "PAUSED")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 7.5, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())
            .layoutPriority(1)
        }
    }

    private var timerControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                if timer.isRunning {
                    Button {
                        connectivity.stopTimer(save: false)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(WatchTimerControlStyle(tint: .orange))
                    .accessibilityHint("Stops timing without saving")
                } else {
                    Button {
                        connectivity.resumeTimer()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(WatchTimerControlStyle(tint: .green))
                }

                Button {
                    connectivity.stopTimer(save: true)
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(WatchTimerControlStyle(
                    tint: WatchTheme.accent,
                    isFilled: true
                ))
                .accessibilityLabel(timer.isRunning ? "Stop and save" : "Save timer")
            }

            if !timer.isRunning {
                Button {
                    confirmingDiscard = true
                } label: {
                    Label("Discard Draft", systemImage: "trash")
                }
                .buttonStyle(WatchTimerControlStyle(tint: .red))
            }
        }
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Timer", role: .destructive) {
                connectivity.discardTimer()
            }
            Button("Keep Draft", role: .cancel) {}
        } message: {
            Text("This timer will not be saved.")
        }
    }

    private func nursingSide(_ side: String, seconds: TimeInterval) -> some View {
        let isActive = timer.activeNursingSideRawValue == side
        let shortLabel = side == "left" ? "L" : "R"
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: side == "left" ? "l.circle.fill" : "r.circle.fill")
                Text(side.capitalized)
                if isActive, timer.isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }
            .font(.system(size: 9, weight: .bold))
            Text(duration(seconds))
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
                .accessibilityLabel("\(shortLabel) side \(duration(seconds))")
        }
        .foregroundStyle(isActive ? Color.white : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            isActive ? AnyShapeStyle(timerTint.gradient) : AnyShapeStyle(Color.white.opacity(0.055)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.white.opacity(0.18) : WatchTheme.line, lineWidth: 0.75)
        }
    }

    private var isNursing: Bool {
        timer.activeNursingSideRawValue != nil
    }

    private var runningDetail: String {
        guard isNursing else { return "Running now" }
        return timer.activeNursingSideRawValue == "left" ? "Left side running" : "Right side running"
    }

    private var timerTint: Color {
        isNursing ? .pink : WatchTheme.accent
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainingSeconds = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct WatchTimerControlStyle: ButtonStyle {
    let tint: Color
    var isFilled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.bold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(isFilled ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                isFilled
                    ? AnyShapeStyle(tint.gradient)
                    : AnyShapeStyle(tint.opacity(configuration.isPressed ? 0.2 : 0.12)),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.25), lineWidth: 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct WatchPredictionCard: View {
    let prediction: WatchPredictionSnapshot

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "moon.stars.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.indigo.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Next \(prediction.title)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(prediction.expectedStart, style: .time)
                    .font(.title3.bold())
                Text("\(prediction.windowStart.formatted(date: .omitted, time: .shortened))–\(prediction.windowEnd.formatted(date: .omitted, time: .shortened)) · \(prediction.confidenceLabel)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.22), WatchTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.indigo.opacity(0.24), lineWidth: 0.75)
        }
    }
}

private struct WatchTodaySummary: View {
    let metrics: [WatchMetricSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(WatchTheme.accent)
                Text("Today")
                    .font(.headline)
            }
            ForEach(metrics) { metric in
                HStack {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(WatchTint.color(metric.tintName).gradient, in: Circle())
                    Text(metric.title)
                    Spacer()
                    Text(metric.value)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(.vertical, 1)
            }
        }
        .padding(10)
        .watchSurface(cornerRadius: 17)
    }
}

enum WatchTint {
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "cyan": .cyan
        case "green": .green
        case "indigo": .indigo
        case "mint": .mint
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "brown": .brown
        default: .indigo
        }
    }
}
