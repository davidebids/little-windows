import Foundation

struct ChartDataPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var value: Double
    var secondaryValue: Double?
    var category: String
    var series: String

    init(
        id: String? = nil,
        date: Date,
        value: Double,
        secondaryValue: Double? = nil,
        category: String = "",
        series: String = ""
    ) {
        self.id = id ?? "\(date.timeIntervalSinceReferenceDate)-\(category)-\(series)"
        self.date = date
        self.value = value
        self.secondaryValue = secondaryValue
        self.category = category
        self.series = series
    }
}
