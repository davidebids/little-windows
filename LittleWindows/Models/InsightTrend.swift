import Foundation

enum InsightTrendDirection: String, Codable, Hashable {
    case up
    case down
    case flat
    case unknown
}

enum InsightSignificance: String, Codable, Hashable {
    case low
    case medium
    case high
}

struct InsightTrend: Identifiable, Hashable {
    let id: String
    var metricName: String
    var currentValueDescription: String
    var previousValueDescription: String?
    var percentChange: Double?
    var direction: InsightTrendDirection
    var interpretation: String
    var significance: InsightSignificance

    init(
        id: String? = nil,
        metricName: String,
        currentValueDescription: String,
        previousValueDescription: String? = nil,
        percentChange: Double? = nil,
        direction: InsightTrendDirection,
        interpretation: String,
        significance: InsightSignificance
    ) {
        self.id = id ?? metricName
        self.metricName = metricName
        self.currentValueDescription = currentValueDescription
        self.previousValueDescription = previousValueDescription
        self.percentChange = percentChange
        self.direction = direction
        self.interpretation = interpretation
        self.significance = significance
    }
}
