import SwiftUI

struct InsightMetricCard: View {
    let metric: InsightMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: metric.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12), in: Circle())
                Spacer()
                if let change = metric.change {
                    Label(change, systemImage: trendIcon)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Text(metric.value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(metric.interpretation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }

    private var accent: Color {
        switch metric.direction {
        case .up: .indigo
        case .down: .orange
        case .flat: .teal
        case .unknown: .purple
        }
    }

    private var trendIcon: String {
        switch metric.direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "minus"
        case .unknown: "circle"
        }
    }
}

struct InsightMetricGrid: View {
    let metrics: [InsightMetric]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(metrics) { metric in
                InsightMetricCard(metric: metric)
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 158), spacing: 10)]
    }
}
