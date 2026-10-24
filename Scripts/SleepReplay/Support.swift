// Storage-free adapters for replaying the actual app engine on macOS.
// Prediction calculations are compiled from the app sources, not copied here.
import Foundation

enum PredictionKind: String, Sendable { case nap, bedtime }
enum ConfidenceLabel: String, Sendable {
    case low, medium, high
    var displayName: String { rawValue.capitalized }
}
enum SleepKind {
    case nap, nightSleep, nightWaking
    var displayName: String { self == .nap ? "Nap" : "Night sleep" }
}
enum EventType {
    case sleep, feed, nursing
    var displayName: String { self == .feed ? "Feed" : "Nursing" }
}
enum ProfileType {
    case child, dog
    var capabilities: Capabilities { Capabilities(supportsSleepPrediction: self == .child) }
}
struct Capabilities { var supportsSleepPrediction: Bool }
struct CareProfile {
    var id = UUID()
    var name = "Test Child"
    var profileType = ProfileType.child
    var birthDate: Date?
    init(id: UUID = UUID(), name: String = "Test Child", birthDate: Date?, ownerIdentifier: String = "") {
        self.id = id; self.name = name; self.birthDate = birthDate
    }
}
final class CareEvent {
    var id = UUID()
    var profileID: UUID?
    var type = EventType.sleep
    var sleepKind: SleepKind? = .nap
    var startDate: Date
    var endDate: Date?
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var excludeFromSleepPredictions = false
    init(startDate: Date, endDate: Date?, kind: SleepKind) {
        self.startDate = startDate
        self.endDate = endDate
        sleepKind = kind
    }
    init(id: UUID = UUID(), profileID: UUID? = nil, type: EventType, startDate: Date, endDate: Date?,
         startTimeZoneIdentifier: String? = nil, endTimeZoneIdentifier: String? = nil) {
        self.id = id; self.profileID = profileID; self.type = type
        self.startDate = startDate; self.endDate = endDate
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
    }
    var duration: TimeInterval? { endDate.map { max(0, $0.timeIntervalSince(startDate)) } }
    var isSleepBlock: Bool { type == .sleep && sleepKind != .nightWaking }
    var isPredictionSleepBlock: Bool { isSleepBlock && !excludeFromSleepPredictions }
    var isTimerDraft: Bool { endDate == nil }
    var isTimerRunning: Bool { isTimerDraft }
    func localStartDay(calendar: Calendar) -> Date { calendar.startOfDay(for: startDate) }
    func occursOnLocalDay(_ date: Date, calendar: Calendar) -> Bool {
        localStartDay(calendar: calendar) == calendar.startOfDay(for: date)
    }
    func localStartMinute(calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }
}
final class SleepPredictionRecord {
    var profileID: UUID?
    var actualSleepEventID: UUID?
    var actualSleepStart: Date?
    var generatedAt: Date
    var errorMinutes: Double?
    var napIndex: Int
    init(prediction: SleepPrediction, actual: CareEvent, generatedAt: Date) {
        self.generatedAt = generatedAt
        napIndex = prediction.napIndex
        actualSleepEventID = actual.id
        actualSleepStart = actual.startDate
        errorMinutes = actual.startDate.timeIntervalSince(prediction.predictedStart) / 60
    }
    init(prediction: SleepPrediction, basedOnLastSleepEventID: UUID?, profileID: UUID?, settings: PredictionSettings) {
        self.profileID = profileID
        generatedAt = Date()
        napIndex = prediction.napIndex
    }
}
struct PredictionFactorValue: Hashable, Sendable {
    var id = UUID()
    var name: String
    var valueDescription: String
    var impactMinutes: Double
    var confidenceImpact: Double
    var explanation: String
    var predictionInputSignature: String? = nil
    var usesPreparedSleepCombination: Bool? = nil
}
enum SystemIntegrationReconciler {
    static func requestReconciliation() { }
}
enum DateFormatting {
    static let time = DateFormatter()
    static func window(start: Date, end: Date) -> String { "" }
}
enum DurationFormatting {
    static func string(seconds: Double) -> String { String(Int(seconds / 60)) }
}
extension Calendar {
    func startOfNextDay(for date: Date) -> Date {
        self.date(byAdding: .day, value: 1, to: startOfDay(for: date))!
    }
}
