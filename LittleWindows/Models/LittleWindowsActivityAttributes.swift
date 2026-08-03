import ActivityKit
import Foundation

struct LittleWindowsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timer: ActiveTimerSnapshot
    }

    var babyName: String
    var profileID: UUID?
    var profileName: String?
}
