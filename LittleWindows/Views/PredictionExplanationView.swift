import SwiftUI

struct PredictionExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let prediction: SleepPrediction?

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
            } else {
                ContentUnavailableView(
                    "No prediction yet",
                    systemImage: "moon.zzz",
                    description: Text("A completed sleep event is needed first.")
                )
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
}

struct BackwardsSleepPlanView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: BabyProfile
    let events: [BabyEvent]
    let settings: PredictionSettings

    @State private var targetBedtime: Date
    @State private var historyRange: BackwardsSleepPlanHistoryRange = .sevenDays

    init(
        profile: BabyProfile,
        events: [BabyEvent],
        settings: PredictionSettings,
        now: Date = Date()
    ) {
        self.profile = profile
        self.events = events
        self.settings = settings
        _targetBedtime = State(initialValue: Self.defaultTargetBedtime(now: now))
    }

    private var plan: BackwardsSleepPlan {
        SleepPredictionEngine.backwardsPlan(
            profile: profile,
            events: events,
            targetBedtime: targetBedtime,
            historyRange: historyRange,
            settings: settings
        )
    }

    var body: some View {
        let plan = plan

        List {
            Section {
                DatePicker(
                    "Desired bedtime",
                    selection: $targetBedtime,
                    displayedComponents: .hourAndMinute
                )
                LabeledContent("Plan", value: "Today")
                LabeledContent("Confidence", value: "\(plan.confidenceLabel.displayName) - \(Int(plan.confidence * 100))%")
            } header: {
                Text("Target")
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
                ForEach(plan.segments) { segment in
                    BackwardsSleepPlanRow(segment: segment)
                }
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

    var body: some View {
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
        .padding(.vertical, 4)
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
}
