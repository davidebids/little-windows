import SwiftUI

struct PredictionExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let prediction: SleepPrediction?
    var sleepPressure: SleepPressure?

    var body: some View {
        List {
            if let prediction {
                Section("Prediction") {
                    LabeledContent("Likely time", value: DateFormatting.time.string(from: prediction.predictedStart))
                    LabeledContent(
                        "Window",
                        value: DateFormatting.window(
                            start: prediction.predictedWindowStart,
                            end: prediction.predictedWindowEnd
                        )
                    )
                    LabeledContent(
                        "Confidence",
                        value: "\(prediction.confidenceLabel.displayName) - \(Int(prediction.confidence * 100))%"
                    )
                }
                Section("Why") {
                    ForEach(Array(prediction.explanation.enumerated()), id: \.offset) { _, explanation in
                        Text(explanation)
                    }
                }
                if !prediction.contributingFactors.isEmpty {
                    Section("Contributing factors") {
                        ForEach(prediction.contributingFactors) { factor in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(factor.name).font(.headline)
                                    Spacer()
                                    if abs(factor.impactMinutes) >= 1 {
                                        Text("\(factor.impactMinutes > 0 ? "+" : "")\(Int(factor.impactMinutes.rounded()))m")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(factor.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let sleepPressure {
                    pressureSection(sleepPressure)
                }
            } else {
                ContentUnavailableView(
                    "No prediction yet",
                    systemImage: "moon.zzz",
                    description: Text("A completed sleep event is needed first.")
                )
                if let sleepPressure {
                    pressureSection(sleepPressure)
                }
            }
        }
        .navigationTitle("Prediction details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func pressureSection(_ pressure: SleepPressure) -> some View {
        Section("Sleep pressure") {
            LabeledContent("State", value: pressure.band.displayName)
            if let score = pressure.score {
                LabeledContent("Score", value: "\(Int(score.rounded())) / 100")
            }
            if let awakeMinutes = pressure.awakeMinutes {
                LabeledContent(
                    "Awake",
                    value: DurationFormatting.string(seconds: awakeMinutes * 60)
                )
            }
            if let targetMinutes = pressure.targetMinutes {
                LabeledContent(
                    "Planning target",
                    value: DurationFormatting.string(seconds: targetMinutes * 60)
                )
            }
            LabeledContent(
                "Confidence",
                value: "\(pressure.confidenceLabel.displayName) - \(Int(pressure.confidence * 100))%"
            )
            if let nextThreshold = pressure.nextThresholdDate {
                LabeledContent(
                    "Next threshold",
                    value: DateFormatting.time.string(from: nextThreshold)
                )
            }
        }

        Section("Pressure factors") {
            ForEach(Array(pressure.explanation.enumerated()), id: \.offset) { _, explanation in
                Text(explanation)
            }
            ForEach(pressure.contributingFactors) { factor in
                VStack(alignment: .leading, spacing: 4) {
                    Text(factor.name).font(.headline)
                    Text(factor.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BackwardsSleepPlanView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: BabyProfile
    let events: [BabyEvent]
    let settings: PredictionSettings
    let activePlan: ActiveSleepPlan?
    let activatePlan: (BackwardsSleepPlan) -> Void
    let deactivatePlan: () -> Void

    @State private var targetBedtime: Date
    @State private var historyRange: BackwardsSleepPlanHistoryRange = .sevenDays
    @State private var segmentAdjustments: [BackwardsSleepPlanAdjustment] = []

    init(
        profile: BabyProfile,
        events: [BabyEvent],
        settings: PredictionSettings,
        activePlan: ActiveSleepPlan? = nil,
        activatePlan: @escaping (BackwardsSleepPlan) -> Void = { _ in },
        deactivatePlan: @escaping () -> Void = {},
        now: Date = Date()
    ) {
        self.profile = profile
        self.events = events
        self.settings = settings
        self.activePlan = activePlan
        self.activatePlan = activatePlan
        self.deactivatePlan = deactivatePlan
        _targetBedtime = State(
            initialValue: activePlan?.targetBedtime ?? Self.defaultTargetBedtime(now: now)
        )
        _historyRange = State(initialValue: activePlan?.historyRange ?? .sevenDays)
        _segmentAdjustments = State(initialValue: activePlan?.segmentAdjustments ?? [])
    }

    private var plan: BackwardsSleepPlan {
        SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: targetBedtime,
            historyRange: historyRange,
            settings: settings,
            adjustments: segmentAdjustments
        )
    }

    var body: some View {
        let plan = plan
        let isActivePlan = activePlan.map {
            $0.profileID == profile.id &&
                abs($0.targetBedtime.timeIntervalSince(plan.targetBedtime)) < 60 &&
                $0.historyRange == historyRange &&
                $0.segmentAdjustments == plan.segmentAdjustments
        } ?? false

        List {
            Section {
                DatePicker(
                    "Desired bedtime",
                    selection: $targetBedtime,
                    displayedComponents: .hourAndMinute
                )
                LabeledContent("Plan", value: "Today")
                LabeledContent("Confidence", value: "\(plan.confidenceLabel.displayName) - \(Int(plan.confidence * 100))%")
                Button {
                    if isActivePlan {
                        deactivatePlan()
                    } else {
                        activatePlan(plan)
                    }
                } label: {
                    Label(
                        isActivePlan ? "Active Plan" : "Activate Plan",
                        systemImage: isActivePlan ? "checkmark.circle.fill" : "bell.badge.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActivePlan ? .green : .indigo)
                if !segmentAdjustments.isEmpty {
                    Button("Reset Manual Adjustments", role: .destructive) {
                        withAnimation(.snappy) {
                            segmentAdjustments.removeAll()
                        }
                    }
                }
            } header: {
                Text("Target")
            } footer: {
                if isActivePlan {
                    Text("A running nap will show and schedule the latest wake-up time for this bedtime.")
                }
            }

            Section {
                Picker("Use data from", selection: $historyRange) {
                    ForEach(BackwardsSleepPlanHistoryRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("History")
            } footer: {
                Text("Shorter history reacts faster to recent changes. Longer history can smooth out unusual days.")
            }

            Section {
                HStack(spacing: 12) {
                    PlanMetric(
                        title: "Naps",
                        value: "\(plan.plannedNapCount)",
                        systemImage: "moon.fill",
                        tint: .indigo
                    )
                    PlanMetric(
                        title: "Usual",
                        value: "\(plan.typicalNapCount)",
                        systemImage: "chart.bar.fill",
                        tint: .teal
                    )
                    PlanMetric(
                        title: "History",
                        value: "\(plan.sourceDayCount)d",
                        systemImage: "calendar",
                        tint: .orange
                    )
                }
            } header: {
                Text("Summary")
            }

            Section {
                dayLayoutContent(for: plan)
            } header: {
                Text("Day Layout")
            }

            Section("Why") {
                ForEach(Array(plan.explanation.enumerated()), id: \.offset) { _, explanation in
                    Text(explanation)
                }
            }
        }
        .navigationTitle("Plan bedtime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private static func defaultTargetBedtime(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let preferred = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: today) ?? now
        if preferred > now.addingTimeInterval(30 * 60) {
            return preferred
        }
        let later = now.addingTimeInterval(90 * 60)
        let minute = calendar.component(.minute, from: later)
        let roundedOffset = (5 - (minute % 5)) % 5
        return calendar.date(byAdding: .minute, value: roundedOffset, to: later) ?? later
    }

    private func adjustment(for segment: BackwardsSleepPlanSegment) -> BackwardsSleepPlanAdjustment? {
        segmentAdjustments.first { $0.matches(segment) }
    }

    private func updateAdjustment(
        for segment: BackwardsSleepPlanSegment,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        guard segment.kind != .bedtime else { return }
        var adjustment = adjustment(for: segment) ?? BackwardsSleepPlanAdjustment(segment: segment)
        let newStartDate = startDate ?? adjustment.startDate
        let minimumEndDate = newStartDate.addingTimeInterval(5 * 60)
        let newEndDate = max(endDate ?? adjustment.endDate, minimumEndDate)
        adjustment.startDate = newStartDate
        adjustment.endDate = newEndDate

        withAnimation(.snappy) {
            if let index = segmentAdjustments.firstIndex(where: { $0.id == adjustment.id }) {
                segmentAdjustments[index] = adjustment
            } else {
                segmentAdjustments.append(adjustment)
            }
        }
    }

    private func resetAdjustment(for segment: BackwardsSleepPlanSegment) {
        segmentAdjustments.removeAll { $0.matches(segment) }
    }

    @ViewBuilder
    private func dayLayoutContent(for plan: BackwardsSleepPlan) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                PlanDayArcView(plan: plan)
                    .frame(width: 210)
                dayLayoutRows(for: plan)
            }

            VStack(alignment: .leading, spacing: 14) {
                PlanDayArcView(plan: plan)
                dayLayoutRows(for: plan)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    private func dayLayoutRows(for plan: BackwardsSleepPlan) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                BackwardsSleepPlanRow(
                    segment: segment,
                    adjustment: adjustment(for: segment),
                    updateAdjustment: { startDate, endDate in
                        updateAdjustment(
                            for: segment,
                            startDate: startDate,
                            endDate: endDate
                        )
                    },
                    resetAdjustment: {
                        withAnimation(.snappy) {
                            resetAdjustment(for: segment)
                        }
                    }
                )
                .padding(.vertical, 6)

                if index < plan.segments.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
    }
}

private struct PlanMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct BackwardsSleepPlanRow: View {
    let segment: BackwardsSleepPlanSegment
    let adjustment: BackwardsSleepPlanAdjustment?
    let updateAdjustment: (_ startDate: Date?, _ endDate: Date?) -> Void
    let resetAdjustment: () -> Void

    @State private var showingEditor = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.headline)
                        if adjustment != nil {
                            Text("Adjusted")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                        }
                        Spacer()
                        Text(timeText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if segment.kind != .bedtime {
                HStack {
                    Button {
                        beginEditing()
                    } label: {
                        Label(adjustment == nil ? "Edit" : "Edit Adjustment", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if adjustment != nil {
                        Button("Reset", role: .destructive) {
                            resetAdjustment()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker(
                            "Start",
                            selection: $draftStartDate,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)

                        if canEditEndDate {
                            DatePicker(
                                "End",
                                selection: $draftEndDate,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                        } else {
                            LabeledContent("End", value: DateFormatting.time.string(from: segment.endDate))
                        }
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingEditor = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            applyDraft()
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var systemImage: String {
        switch segment.kind {
        case .wakeWindow: "sun.max.fill"
        case .nap: "moon.fill"
        case .bedtime: "bed.double.fill"
        }
    }

    private var tint: Color {
        switch segment.kind {
        case .wakeWindow: .orange
        case .nap: .indigo
        case .bedtime: .purple
        }
    }

    private var title: String {
        switch segment.kind {
        case .wakeWindow:
            if let napIndex = segment.napIndex {
                return "Wake before nap \(napIndex)"
            }
            return "Wake before bedtime"
        case .nap:
            return "Nap \(segment.napIndex ?? 1)"
        case .bedtime:
            return "Asleep by"
        }
    }

    private var timeText: String {
        switch segment.kind {
        case .bedtime:
            return DateFormatting.time.string(from: segment.startDate)
        default:
            return DateFormatting.window(start: segment.startDate, end: segment.endDate)
        }
    }

    private var detailText: String {
        switch segment.kind {
        case .wakeWindow:
            return "\(durationText) awake"
        case .nap:
            return "\(durationText) nap"
        case .bedtime:
            return "Target bedtime for today"
        }
    }

    private var durationText: String {
        DurationFormatting.string(seconds: segment.durationMinutes * 60)
    }

    private var canEditEndDate: Bool {
        segment.kind == .nap || segment.napIndex != nil
    }

    private func beginEditing() {
        draftStartDate = adjustment?.startDate ?? segment.startDate
        draftEndDate = adjustment?.endDate ?? segment.endDate
        showingEditor = true
    }

    private func applyDraft() {
        updateAdjustment(
            draftStartDate,
            canEditEndDate ? draftEndDate : nil
        )
        showingEditor = false
    }
}
