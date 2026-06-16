import SwiftUI

struct InsightChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    let isEmpty: Bool
    let emptyMessage: String
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        isEmpty: Bool = false,
        emptyMessage: String = "Log more data to see this chart.",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isEmpty = isEmpty
        self.emptyMessage = emptyMessage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEmpty {
                ContentUnavailableView(
                    "Not enough data",
                    systemImage: "chart.xyaxis.line",
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                content()
                    .frame(minHeight: 210)
            }
        }
        .padding(18)
        .appSurface()
    }
}

struct InsightObservationsCard: View {
    let trends: [InsightTrend]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What changed", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.indigo)

            if trends.isEmpty {
                Text("A few more days of comparable logs will reveal meaningful changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trends) { trend in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: trend.direction))
                            .font(.caption.bold())
                            .foregroundStyle(color(for: trend.significance))
                            .frame(width: 26, height: 26)
                            .background(color(for: trend.significance).opacity(0.12), in: Circle())
                        Text(trend.interpretation)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .appSurface()
    }

    private func icon(for direction: InsightTrendDirection) -> String {
        switch direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "equal"
        case .unknown: "lightbulb.fill"
        }
    }

    private func color(for significance: InsightSignificance) -> Color {
        switch significance {
        case .low: .teal
        case .medium: .indigo
        case .high: .orange
        }
    }
}

enum InsightsChartFormatting {
    static func clock(minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        let normalized = ((rounded % 1440) + 1440) % 1440
        let date = Calendar.current.date(
            from: DateComponents(hour: normalized / 60, minute: normalized % 60)
        ) ?? Date()
        return DateFormatting.time.string(from: date)
    }

    static func napLabel(_ index: Int) -> String {
        index == 5 ? "Pre-bed" : "Nap \(index)"
    }
}
