import ActivityKit
import Foundation

struct LittleWindowsActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var timer: ActiveTimerSnapshot
    }

    var babyName: String
    var profileID: UUID?
    var profileName: String?
}
