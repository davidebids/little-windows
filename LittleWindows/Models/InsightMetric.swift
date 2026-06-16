import Foundation

struct InsightMetric: Identifiable, Hashable {
    let id: String
    var title: String
    var value: String
    var change: String?
    var direction: InsightTrendDirection
    var interpretation: String
    var systemImage: String

    init(
        id: String? = nil,
        title: String,
        value: String,
        change: String? = nil,
        direction: InsightTrendDirection = .unknown,
        interpretation: String,
        systemImage: String
    ) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.change = change
        self.direction = direction
        self.interpretation = interpretation
        self.systemImage = systemImage
    }
}
