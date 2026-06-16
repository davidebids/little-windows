import Foundation

enum InsightsDateRange: String, CaseIterable, Identifiable {
    case sevenDays
    case fourteenDays
    case thirtyDays
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .thirtyDays: "30 days"
        case .custom: "Custom"
        }
    }

    var presetDays: Int? {
        switch self {
        case .sevenDays: 7
        case .fourteenDays: 14
        case .thirtyDays: 30
        case .custom: nil
        }
    }
}

enum InsightsSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sleep = "Sleep"
    case wakeWindows = "Wake Windows"
    case feeding = "Feeding"
    case diapers = "Diapers"
    case activities = "Activities"
    case medicine = "Medicine"
    case appointments = "Appointments"
    case growth = "Growth"
    case temperature = "Temperature"
    case milestones = "Milestones"
    case predictionAccuracy = "Prediction Accuracy"

    var id: String { rawValue }

    var usesDateRange: Bool {
        self != .growth
    }

    var supportsPreviousPeriodComparison: Bool {
        self != .growth && self != .milestones
    }
}

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published var selectedRange: InsightsDateRange = .sevenDays
    @Published var comparesToPreviousPeriod = true
    @Published var selectedSection: InsightsSection = .overview
    @Published var customStartDate: Date
    @Published var customEndDate: Date
    @Published private(set) var snapshot = InsightsSnapshot.empty

    private var profileName = "Baby"
    private var events = [BabyEvent]()
    private var records = [SleepPredictionRecord]()
    private var now = Date()

    init(now: Date = Date(), calendar: Calendar = .current) {
        let end = calendar.startOfDay(for: now)
        customEndDate = end
        customStartDate = calendar.date(byAdding: .day, value: -6, to: end) ?? end
    }

    func refresh(
        profileName: String,
        events: [BabyEvent],
        records: [SleepPredictionRecord],
        now: Date = Date()
    ) {
        self.profileName = profileName
        self.events = events
        self.records = records
        self.now = now
        rebuild()
    }

    func rebuild() {
        let period = selectedPeriod()
        snapshot = InsightsAnalyticsService.snapshot(
            profileName: profileName,
            events: events,
            records: records,
            periodStart: period.lowerBound,
            periodEnd: period.upperBound,
            now: now,
            compareToPrevious: comparesToPreviousPeriod
        )
    }

    func updateCustomStart(_ date: Date) {
        customStartDate = Calendar.current.startOfDay(for: min(date, customEndDate))
        rebuild()
    }

    func updateCustomEnd(_ date: Date) {
        customEndDate = Calendar.current.startOfDay(for: max(date, customStartDate))
        rebuild()
    }

    var periodLabel: String {
        let period = selectedPeriod()
        return "\(period.lowerBound.formatted(date: .abbreviated, time: .omitted)) - \(period.upperBound.formatted(date: .abbreviated, time: .omitted))"
    }

    var selectedPeriodRange: ClosedRange<Date> {
        selectedPeriod()
    }

    var previousPeriodLabel: String {
        let calendar = Calendar.current
        let period = selectedPeriod(calendar: calendar)
        let dayCount = max(
            1,
            (calendar.dateComponents(
                [.day],
                from: period.lowerBound,
                to: period.upperBound
            ).day ?? 0) + 1
        )
        let previousStart = calendar.date(
            byAdding: .day,
            value: -dayCount,
            to: period.lowerBound
        ) ?? period.lowerBound
        let previousEnd = calendar.date(
            byAdding: .day,
            value: -1,
            to: period.lowerBound
        ) ?? period.lowerBound

        return "\(previousStart.formatted(date: .abbreviated, time: .omitted)) - \(previousEnd.formatted(date: .abbreviated, time: .omitted))"
    }

    private func selectedPeriod(calendar: Calendar = .current) -> ClosedRange<Date> {
        let end = selectedRange == .custom
            ? calendar.startOfDay(for: customEndDate)
            : calendar.startOfDay(for: now)
        let start: Date
        if let days = selectedRange.presetDays {
            start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        } else {
            start = min(calendar.startOfDay(for: customStartDate), end)
        }
        return start...end
    }
}
