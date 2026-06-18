import ActivityKit
import Foundation

enum SystemIntegrationConstants {
    static let appGroupIdentifier = "group.com.debidia.LittleWindows"
    static let widgetSnapshotFilename = "widget-snapshot.json"
    static let pendingURLFilename = "pending-action.txt"

    private static let appGroupContainerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )

    static var isAppGroupAvailable: Bool {
        appGroupContainerURL != nil
    }

    static let sharedContainerURL: URL = {
        if let groupURL = appGroupContainerURL {
            return groupURL
        }

        let localURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return localURL.appendingPathComponent("LittleWindowsSystemIntegration", isDirectory: true)
    }()

    static func sharedFileURL(_ filename: String) -> URL {
        let directory = sharedContainerURL
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(filename)
    }
}

struct ActiveTimerSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var profileID: UUID?
    var profileName: String?
    var babyName: String
    var typeRawValue: String
    var eventLabel: String
    var systemImage: String
    var startDate: Date
    var isRunning: Bool?
    var elapsedSeconds: TimeInterval?
    var caregiverName: String?
    var activeNursingSideRawValue: String?
    var leftDurationSeconds: Double
    var rightDurationSeconds: Double
    var additionalActiveCount: Int

    var activeNursingSide: NursingSide? {
        activeNursingSideRawValue.flatMap(NursingSide.init(rawValue:))
    }

    var resolvedIsRunning: Bool {
        isRunning ?? true
    }

    var resolvedElapsedSeconds: TimeInterval {
        elapsedSeconds ?? 0
    }

    var stopURL: URL {
        profileScopedURL(path: "action/stop/\(id.uuidString)")
    }

    var openURL: URL {
        profileScopedURL(path: "event/\(id.uuidString)")
    }

    var switchSideURL: URL {
        profileScopedURL(path: "action/switch-side/\(id.uuidString)")
    }

    private func profileScopedURL(path: String) -> URL {
        if let profileID {
            return URL(string: "littlewindows://profile/\(profileID.uuidString)/\(path)")!
        }
        return URL(string: "littlewindows://\(path)")!
    }
}

struct PredictionSnapshot: Codable, Hashable {
    var profileID: UUID?
    var profileName: String?
    var kind: String
    var expectedStart: Date?
    var windowStart: Date
    var windowEnd: Date
    var confidenceLabel: String

    var resolvedExpectedStart: Date {
        expectedStart
            ?? windowStart.addingTimeInterval(
                windowEnd.timeIntervalSince(windowStart) / 2
            )
    }
}

enum PredictionTimingPhase: Equatable {
    case upcoming
    case inWindow
    case overdue
}

enum PredictionTiming {
    static func phase(
        windowStart: Date,
        windowEnd: Date,
        now: Date = Date()
    ) -> PredictionTimingPhase {
        if now < windowStart { return .upcoming }
        if now <= windowEnd { return .inWindow }
        return .overdue
    }
}

enum PredictionCountdownFormatting {
    static func text(until target: Date, from now: Date = Date()) -> String {
        let seconds = target.timeIntervalSince(now)
        guard seconds > 30 else { return "Now" }

        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 {
            return "In \(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes == 0
                ? "In \(hours)h"
                : "In \(hours)h \(remainingMinutes)m"
        }

        let days = hours / 24
        return "In \(days)d"
    }
}

struct TodaySummarySnapshot: Codable, Hashable {
    var profileID: UUID?
    var profileName: String?
    var totalSleepSeconds: TimeInterval
    var napCount: Int
    var careSessionCount: Int
    var diaperCount: Int
}

struct FoodShoppingListItemSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var quantityText: String
    var sectionName: String?
}

struct FoodShoppingListSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var activeItemCount: Int
    var checkedItemCount: Int
    var lastUsedAt: Date?
    var topActiveItems: [FoodShoppingListItemSnapshot]

    var openURL: URL {
        URL(string: "littlewindows://food/shopping/\(id.uuidString)")!
    }

    var shoppingModeURL: URL {
        URL(string: "littlewindows://food/shopping/\(id.uuidString)/mode")!
    }
}

struct FoodWidgetSnapshot: Codable, Hashable {
    var generatedAt: Date
    var selectedList: FoodShoppingListSnapshot?
    var lists: [FoodShoppingListSnapshot]

    static let empty = FoodWidgetSnapshot(
        generatedAt: Date(),
        selectedList: nil,
        lists: []
    )
}

struct WidgetSnapshot: Codable, Hashable {
    var generatedAt: Date
    var profileID: UUID?
    var profileName: String?
    var babyName: String
    var activeTimer: ActiveTimerSnapshot?
    var prediction: PredictionSnapshot?
    var todaySummary: TodaySummarySnapshot
    var food: FoodWidgetSnapshot?

    static let empty = WidgetSnapshot(
        generatedAt: Date(),
        profileID: nil,
        profileName: "Baby",
        babyName: "Baby",
        activeTimer: nil,
        prediction: nil,
        todaySummary: TodaySummarySnapshot(
            profileID: nil,
            profileName: "Baby",
            totalSleepSeconds: 0,
            napCount: 0,
            careSessionCount: 0,
            diaperCount: 0
        ),
        food: .empty
    )

    var resolvedFood: FoodWidgetSnapshot {
        food ?? .empty
    }
}

struct LittleWindowsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timer: ActiveTimerSnapshot
    }

    var babyName: String
    var profileID: UUID?
    var profileName: String?
}
