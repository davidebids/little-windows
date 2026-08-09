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

                if !connectivity.state.activeTimers.isEmpty {
                    WatchActiveTimersStack(timers: connectivity.state.activeTimers)
                }

                if let prediction = connectivity.state.prediction {
                    WatchPredictionCard(prediction: prediction)
                }

                if let medication = connectivity.state.upcomingMedication {
                    WatchMedicationCard(medication: medication)
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
            Image("BrandLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(
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
            HStack(spacing: 7) {
                Image(systemName: selectedProfileSystemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(profileTint.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(connectivity.state.selectedProfile?.name ?? "Choose profile")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    Text(selectedProfileTypeLabel)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [profileTint.opacity(0.24), WatchTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(profileTint.opacity(0.26), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selected profile, \(connectivity.state.selectedProfile?.name ?? "none")")
    }

    private var selectedProfileIsDog: Bool {
        connectivity.state.selectedProfile?.profileTypeRawValue == "dog"
    }

    private var selectedProfileTypeLabel: String {
        switch connectivity.state.selectedProfile?.profileTypeRawValue {
        case "adult": "Adult profile"
        case "dog": "Dog profile"
        default: "Child profile"
        }
    }

    private var selectedProfileSystemImage: String {
        switch connectivity.state.selectedProfile?.profileTypeRawValue {
        case "adult": "person.crop.circle.fill"
        case "dog": "pawprint.fill"
        default: "figure.and.child.holdinghands"
        }
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
            Label("Add care when you’re ready", systemImage: "heart.text.clipboard")
        } description: {
            Text("Add or restore a care profile in Little Windows on your iPhone, then refresh this watch.")
        } actions: {
            Button("Try Again") { connectivity.requestRefresh() }
        }
    }
}

private struct WatchMedicationCard: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    let medication: WatchMedicationSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Color.red.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("UPCOMING MEDICATION")
                            .font(.system(size: 7.5, weight: .bold))
                            .tracking(0.55)
                            .foregroundStyle(.secondary)
                        Text(medication.medicationName)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 3)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(doseText)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(medication.scheduledAt, style: .time)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                        Text(relativeLabel(at: context.date))
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(timingTint(at: context.date))
                    }
                }

                HStack(spacing: 5) {
                    Button {
                        if connectivity.logMedicationTaken(medication) {
                            WKInterfaceDevice.current().play(.click)
                        }
                    } label: {
                        actionLabel("Taken", systemImage: "checkmark")
                    }
                    .buttonStyle(WatchTimerControlStyle(tint: .green, isFilled: true))

                    Button {
                        if connectivity.logMedicationSkipped(medication) {
                            WKInterfaceDevice.current().play(.click)
                        }
                    } label: {
                        actionLabel("Skip", systemImage: "minus")
                    }
                    .buttonStyle(WatchTimerControlStyle(tint: .secondary))

                    if medication.snoozeAvailable {
                        Button {
                            if connectivity.snoozeMedication(medication) {
                                WKInterfaceDevice.current().play(.click)
                            }
                        } label: {
                            actionLabel("10m", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(WatchTimerControlStyle(tint: .orange))
                        .accessibilityLabel("Snooze medication for 10 minutes")
                    }
                }
            }
            .padding(8)
            .background(
                LinearGradient(
                    colors: [Color.red.opacity(0.18), WatchTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.24), lineWidth: 0.8)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var doseText: String {
        "\(medication.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(medication.doseUnit)"
    }

    private func relativeLabel(at date: Date) -> String {
        let interval = medication.scheduledAt.timeIntervalSince(date)
        if abs(interval) < 60 { return "Due now" }
        let minutes = max(1, Int(abs(interval) / 60))
        if interval > 0 {
            return minutes < 60 ? "Due in \(minutes)m" : "Due later"
        }
        return minutes < 60 ? "\(minutes)m overdue" : "Overdue"
    }

    private func timingTint(at date: Date) -> Color {
        medication.scheduledAt < date.addingTimeInterval(-60) ? .orange : .secondary
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 7.5, weight: .bold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
                    Image(systemName: {
                        switch profile.profileTypeRawValue {
                        case "adult": "person.crop.circle.fill"
                        case "dog": "pawprint.fill"
                        default: "figure.and.child.holdinghands"
                        }
                    }())
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

private enum WatchManualTimeField: Hashable {
    case hour
    case minute
    case period
}

private struct WatchTimerStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: WatchConnectivityClient

    let action: WatchActionSnapshot

    @State private var selectedOptionID: String
    @State private var startMode = WatchTimerStartMode.now
    @State private var manualHour: Double
    @State private var manualMinute: Double
    @State private var manualPeriod: Double
    @State private var selectedTimeField: WatchManualTimeField?
    @FocusState private var manualTimePickerIsFocused: Bool

    init(action: WatchActionSnapshot) {
        self.action = action
        let now = Date()
        let initialStart = WatchTimerStartPolicy.normalizedManualStart(
            now.addingTimeInterval(-5 * 60),
            now: now
        )
        let initialComponents = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: initialStart
        )
        let initialHour = initialComponents.hour ?? 0
        _selectedOptionID = State(initialValue: action.options.first?.id ?? "")
        _manualHour = State(initialValue: Double(Self.twelveHourValue(initialHour)))
        _manualMinute = State(initialValue: Double(initialComponents.minute ?? 0))
        _manualPeriod = State(initialValue: initialHour >= 12 ? 1 : 0)
    }

    var body: some View {
        List {
            if action.requiresChoice {
                Section(action.id == "nursing" ? "Starting side" : "Sleep type") {
                    NavigationLink {
                        WatchTimerOptionPickerView(
                            action: action,
                            selectedOptionID: $selectedOptionID
                        )
                    } label: {
                        optionSelectionLabel
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Start time") {
                HStack(spacing: 6) {
                    ForEach(WatchTimerStartMode.allCases) { mode in
                        Button {
                            if mode == .earlier, startMode != .earlier {
                                setManualTime(to: Date().addingTimeInterval(-5 * 60))
                            }
                            startMode = mode
                            if mode == .now {
                                selectedTimeField = nil
                                manualTimePickerIsFocused = false
                            }
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
                    manualTimePicker
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
                .disabled(
                    (action.requiresChoice && selectedOptionID.isEmpty)
                        || (startMode == .earlier && resolvedManualStartDate() == nil)
                )
            }
        }
        .navigationTitle(action.title)
    }

    private var optionSelectionLabel: some View {
        let selectedOption = action.options.first { $0.id == selectedOptionID }
        return HStack(spacing: 9) {
            Image(systemName: selectedOption?.systemImage ?? action.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    WatchTint.color(action.tintName).gradient,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedOption?.title ?? "Choose")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Tap to change")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 3)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            action.id == "nursing" ? "Starting side" : "Sleep type"
        )
        .accessibilityValue(selectedOption?.title ?? "Not selected")
        .accessibilityHint("Tap to change")
    }

    private var manualTimePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                timeField(
                    title: "Hour",
                    value: String(Int(manualHour.rounded())),
                    field: .hour
                )

                Text(":")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)

                timeField(
                    title: "Minute",
                    value: String(format: "%02d", Int(manualMinute.rounded())),
                    field: .minute
                )

                timeField(
                    title: "Period",
                    value: manualPeriod < 0.5 ? "AM" : "PM",
                    field: .period
                )
            }

            if resolvedManualStartDate() == nil {
                Label("Choose a time no later than now", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                Label("Tap a field, then turn the Digital Crown", systemImage: "digitalcrown.horizontal.arrow.counterclockwise")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .focusable()
        .focused($manualTimePickerIsFocused)
        .digitalCrownRotation(
            crownSelection,
            from: crownRange.lowerBound,
            through: crownRange.upperBound,
            by: 1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
    }

    private func timeField(
        title: String,
        value: String,
        field: WatchManualTimeField
    ) -> some View {
        let isFocused = selectedTimeField == field
        return Button {
            selectedTimeField = field
            manualTimePickerIsFocused = true
            WKInterfaceDevice.current().play(.click)
        } label: {
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(
                        isFocused ? WatchTint.color(action.tintName) : .secondary
                    )
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isFocused
                    ? WatchTint.color(action.tintName).opacity(0.16)
                    : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isFocused
                            ? WatchTint.color(action.tintName)
                            : Color.secondary.opacity(0.34),
                        lineWidth: isFocused ? 1.5 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Tap, then turn the Digital Crown to adjust")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var crownSelection: Binding<Double> {
        Binding(
            get: {
                switch selectedTimeField {
                case .hour: manualHour
                case .minute: manualMinute
                case .period: manualPeriod
                case nil: 0
                }
            },
            set: { newValue in
                switch selectedTimeField {
                case .hour: manualHour = newValue
                case .minute: manualMinute = newValue
                case .period: manualPeriod = newValue
                case nil: break
                }
            }
        )
    }

    private var crownRange: ClosedRange<Double> {
        switch selectedTimeField {
        case .hour: 1...12
        case .minute: 0...59
        case .period: 0...1
        case nil: 0...1
        }
    }

    private func startTimer() {
        let optionID = selectedOptionID.isEmpty ? nil : selectedOptionID
        let timerStartDate: Date?
        if startMode == .earlier {
            guard let resolvedStart = resolvedManualStartDate() else {
                WKInterfaceDevice.current().play(.failure)
                return
            }
            timerStartDate = resolvedStart
        } else {
            timerStartDate = nil
        }
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
        selectedManualTime(now: Date()).formatted(date: .omitted, time: .shortened)
    }

    private func resolvedManualStartDate(now: Date = Date()) -> Date? {
        WatchTimerStartPolicy.validatedTimeOfDayStart(
            selectedManualTime(now: now),
            now: now
        )
    }

    private func selectedManualTime(now: Date) -> Date {
        let hour = Int(manualHour.rounded()) % 12
            + (manualPeriod < 0.5 ? 0 : 12)
        return Calendar.autoupdatingCurrent.date(
            bySettingHour: hour,
            minute: Int(manualMinute.rounded()),
            second: 0,
            of: now
        ) ?? now
    }

    private func setManualTime(to proposedDate: Date) {
        let now = Date()
        let normalizedDate = WatchTimerStartPolicy.normalizedManualStart(
            proposedDate,
            now: now
        )
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: normalizedDate
        )
        let hour = components.hour ?? 0
        manualHour = Double(Self.twelveHourValue(hour))
        manualMinute = Double(components.minute ?? 0)
        manualPeriod = hour >= 12 ? 1 : 0
    }

    private static func twelveHourValue(_ hour: Int) -> Int {
        let value = hour % 12
        return value == 0 ? 12 : value
    }
}

private struct WatchTimerOptionPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let action: WatchActionSnapshot
    @Binding var selectedOptionID: String

    var body: some View {
        List(action.options) { option in
            Button {
                selectedOptionID = option.id
                WKInterfaceDevice.current().play(.click)
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: option.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            WatchTint.color(action.tintName).gradient,
                            in: Circle()
                        )
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    if option.id == selectedOptionID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WatchTint.color(action.tintName))
                    }
                }
            }
            .accessibilityAddTraits(
                option.id == selectedOptionID ? .isSelected : []
            )
        }
        .navigationTitle(action.id == "nursing" ? "Starting Side" : "Sleep Type")
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

private struct WatchActiveTimersStack: View {
    let timers: [WatchTimerSnapshot]

    var body: some View {
        TimelineView(.periodic(
            from: .now,
            by: timers.contains(where: \.isRunning) ? 1 : 60
        )) { context in
            VStack(alignment: .leading, spacing: 8) {
                if timers.count > 1 {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                        Text("ACTIVE TIMERS")
                            .tracking(0.7)
                        Spacer()
                        Text("\(timers.count)")
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WatchTheme.surface, in: Capsule())
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }

                ForEach(timers) { timer in
                    ActiveWatchTimerCard(timer: timer, date: context.date)
                }
            }
        }
    }
}

private struct ActiveWatchTimerCard: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    @State private var confirmingDiscard = false
    let timer: WatchTimerSnapshot
    let date: Date

    var body: some View {
        VStack(spacing: 7) {
            timerHeader

            if isNursing {
                HStack(spacing: 6) {
                    nursingSide(
                        "left",
                        seconds: timer.leftDuration(at: date)
                    )
                    nursingSide(
                        "right",
                        seconds: timer.rightDuration(at: date)
                    )
                }
            }

            timerControls
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [timerTint.opacity(0.2), WatchTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(timerTint.opacity(0.26), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private var timerHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: timer.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(timerTint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(timer.title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 3) {
                    Circle()
                        .fill(timer.isRunning ? Color.green : Color.orange)
                        .frame(width: 4, height: 4)
                    Text(statusLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(duration(timer.elapsed(at: date)))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(2)
        }
    }

    private var timerControls: some View {
        HStack(spacing: 5) {
            if timer.isRunning {
                Button {
                    connectivity.stopTimer(timer.id, save: false)
                } label: {
                    controlLabel("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(WatchTimerControlStyle(tint: .orange))
                .accessibilityHint("Stops timing without saving")
            } else {
                Button {
                    connectivity.resumeTimer(timer.id)
                } label: {
                    controlLabel("Resume", systemImage: "play.fill")
                }
                .buttonStyle(WatchTimerControlStyle(tint: .green))
            }

            Button {
                connectivity.stopTimer(timer.id, save: true)
            } label: {
                controlLabel("Save", systemImage: "checkmark")
            }
            .buttonStyle(WatchTimerControlStyle(
                tint: WatchTheme.accent,
                isFilled: true
            ))
            .accessibilityLabel(timer.isRunning ? "Stop and save" : "Save timer")

            if !timer.isRunning {
                Button {
                    confirmingDiscard = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(WatchTimerControlStyle(tint: .red))
                .frame(width: 32)
                .accessibilityLabel("Discard draft")
            }
        }
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Timer", role: .destructive) {
                connectivity.discardTimer(timer.id)
            }
            Button("Keep Draft", role: .cancel) {}
        } message: {
            Text("This timer will not be saved.")
        }
    }

    private func nursingSide(_ side: String, seconds: TimeInterval) -> some View {
        let isActive = timer.activeNursingSideRawValue == side
        let shortLabel = side == "left" ? "L" : "R"
        return Button {
            guard !isActive else { return }
            connectivity.selectNursingSide(side, timerID: timer.id)
            WKInterfaceDevice.current().play(.click)
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: side == "left" ? "l.circle.fill" : "r.circle.fill")
                    Text(side.capitalized)
                    if isActive, timer.isRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                    }
                }
                .font(.system(size: 8, weight: .bold))
                Text(duration(seconds))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? AnyShapeStyle(timerTint.gradient)
                    : AnyShapeStyle(Color.white.opacity(0.055)),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.white.opacity(0.18) : WatchTheme.line,
                        lineWidth: 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shortLabel) side, \(duration(seconds))")
        .accessibilityHint(isActive ? "Currently selected" : "Switch timer to this side")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var isNursing: Bool {
        timer.activeNursingSideRawValue != nil
    }

    private var statusLabel: String {
        guard timer.isRunning else { return "Draft" }
        guard isNursing else { return "Running" }
        return timer.activeNursingSideRawValue == "left" ? "Left" : "Right"
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

    private func controlLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
        }
    }
}

private struct WatchTimerControlStyle: ButtonStyle {
    let tint: Color
    var isFilled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isFilled ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                isFilled
                    ? AnyShapeStyle(tint.gradient)
                    : AnyShapeStyle(tint.opacity(configuration.isPressed ? 0.2 : 0.12)),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
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
