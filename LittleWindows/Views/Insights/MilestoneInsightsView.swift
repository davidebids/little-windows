import Charts
import SwiftUI

struct MilestoneInsightsView: View {
    let milestones: [MilestoneEntry]
    let profile: BabyProfile?
    let period: ClosedRange<Date>
    let readStates: [AgeGuideReadState]

    private var periodMilestones: [MilestoneEntry] {
        let end = Calendar.current.startOfNextDay(for: period.upperBound)
        return milestones.filter { $0.date >= period.lowerBound && $0.date < end }
    }

    private var favorites: [MilestoneEntry] {
        milestones.filter(\.isFavorite).sorted { $0.date > $1.date }
    }

    private var recent: [MilestoneEntry] {
        Array(milestones.sorted { $0.date > $1.date }.prefix(5))
    }

    private var categoryCounts: [MilestoneCategoryCount] {
        Dictionary(grouping: periodMilestones, by: \.category)
            .map { MilestoneCategoryCount(category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var monthlyCounts: [MilestoneMonthCount] {
        let calendar = Calendar.current
        return Dictionary(
            grouping: milestones,
            by: { calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date }
        )
        .map { MilestoneMonthCount(month: $0.key, count: $0.value.count) }
        .sorted { $0.month < $1.month }
    }

    private var currentGuide: AgeGuide? {
        profile.flatMap { AgeGuideService.shared.currentAgeGuide(for: $0) }
    }

    private var currentMonthMilestones: [MilestoneEntry] {
        guard let profile, let guide = currentGuide,
              let start = AgeGuideService.shared.monthlyBirthdayDate(
                for: profile,
                ageMonth: guide.ageMonth
              ) else {
            return []
        }
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? Date()
        return milestones.filter { $0.date >= start && $0.date < end }
    }

    private var remainingPrompts: Int {
        guard let guide = currentGuide else { return 0 }
        let titles = Set(currentMonthMilestones.map { $0.title.lowercased() })
        return guide.milestonePrompts.filter {
            !titles.contains($0.title.lowercased())
        }.count
    }

    private var isCurrentGuideUnread: Bool {
        guard let currentGuide else { return false }
        return !readStates.contains {
            $0.guideID == currentGuide.id && $0.firstOpenedAt != nil
        }
    }

    var body: some View {
        Group {
            InsightMetricGrid(metrics: [
                InsightMetric(
                    title: "Current age",
                    value: profile.map { DateFormatting.age(from: $0.birthDate) } ?? "Not set",
                    interpretation: currentGuide.map {
                        isCurrentGuideUnread
                            ? "\($0.ageLabel) guide is ready to read."
                            : "\($0.ageLabel) guide has been opened."
                    } ?? "Add a profile birth date to unlock monthly guides.",
                    systemImage: "birthday.cake.fill"
                ),
                InsightMetric(
                    title: "Total memories",
                    value: "\(milestones.count)",
                    interpretation: "Milestones captured across \(profile?.name ?? "your baby")'s timeline.",
                    systemImage: "heart.text.clipboard.fill"
                ),
                InsightMetric(
                    title: "In this period",
                    value: "\(periodMilestones.count)",
                    interpretation: "Memories dated within the selected Insights range.",
                    systemImage: "calendar.badge.plus"
                ),
                InsightMetric(
                    title: "Favorites",
                    value: "\(favorites.count)",
                    interpretation: "Moments marked as especially meaningful.",
                    systemImage: "heart.fill"
                ),
                InsightMetric(
                    title: "This age",
                    value: "\(currentMonthMilestones.count)",
                    interpretation: "Milestones captured during the current monthly age window.",
                    systemImage: "calendar.badge.plus"
                ),
                InsightMetric(
                    title: "Prompts left",
                    value: "\(remainingPrompts)",
                    interpretation: "Current guide prompts that have not yet matched a same-title milestone.",
                    systemImage: "lightbulb.fill"
                )
            ])

            InsightChartCard(
                title: "Milestones by category",
                subtitle: "Memories in the selected date range",
                isEmpty: categoryCounts.isEmpty,
                emptyMessage: "Capture a milestone in this date range to see its category."
            ) {
                Chart(categoryCounts) { item in
                    BarMark(
                        x: .value("Category", item.category.displayName),
                        y: .value("Memories", item.count)
                    )
                    .foregroundStyle(item.category.tint.gradient)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let category = value.as(String.self) {
                                Text(category)
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }

            InsightChartCard(
                title: "Memory timeline",
                subtitle: "Milestones captured by month",
                isEmpty: monthlyCounts.isEmpty,
                emptyMessage: "Monthly density appears as memories are added."
            ) {
                Chart(monthlyCounts) { item in
                    BarMark(
                        x: .value("Month", item.month, unit: .month),
                        y: .value("Memories", item.count)
                    )
                    .foregroundStyle(MilestonePalette.accent.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
            }

            milestoneList(
                title: "Recent milestones",
                systemImage: "clock.fill",
                values: recent,
                emptyMessage: "Recent memories will appear here."
            )

            milestoneList(
                title: "Favorite memories",
                systemImage: "heart.fill",
                values: Array(favorites.prefix(5)),
                emptyMessage: "Favorite a milestone to keep it close."
            )
        }
    }

    private func milestoneList(
        title: String,
        systemImage: String,
        values: [MilestoneEntry],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(MilestonePalette.accent)

            if values.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values) { milestone in
                    NavigationLink {
                        MilestoneDetailView(milestone: milestone)
                    } label: {
                        MilestoneTimelineRow(
                            milestone: milestone,
                            babyName: profile?.name ?? "Baby",
                            birthDate: profile?.birthDate
                        )
                    }
                    .buttonStyle(.plain)
                    if milestone.id != values.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .appSurface()
    }
}

private struct MilestoneCategoryCount: Identifiable {
    let category: MilestoneCategory
    let count: Int
    var id: MilestoneCategory { category }
}

private struct MilestoneMonthCount: Identifiable {
    let month: Date
    let count: Int
    var id: Date { month }
}
