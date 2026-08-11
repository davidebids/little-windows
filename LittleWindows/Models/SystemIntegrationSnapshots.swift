import Foundation

enum SystemIntegrationStorage {
    /// Serializes active-timer snapshot file access across the app's snapshot
    /// publisher and widget commands without blocking either caller.
    static let widgetSnapshotQueue = DispatchQueue(
        label: "com.debidia.LittleWindows.widget-snapshot-storage",
        qos: .utility
    )
}

enum SystemIntegrationConstants {
    static let appGroupIdentifier = "group.com.debidia.LittleWindows"
    static let widgetSnapshotFilename = "widget-snapshot.json"
    static let pendingURLFilename = "pending-action.txt"
    static let activeTimerWidgetKind = "LittleWindows.ActiveTimer"

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

struct ActiveTimerSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var profileID: UUID?
    var profileName: String?
    var babyName: String
    var typeRawValue: String
    var eventLabel: String
    var systemImage: String
    var sessionStartDate: Date?
    var startDate: Date
    var isRunning: Bool?
    var elapsedSeconds: TimeInterval?
    var caregiverName: String?
    var activeNursingSideRawValue: String?
    var activeNursingSideTimerStartDate: Date?
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

    var resolvedSessionStartDate: Date {
        sessionStartDate ?? startDate
    }

    /// Live Activities advance running timers from their reference dates. A
    /// fresh history snapshot naturally contains a larger elapsed/duration
    /// value even when no timer state changed; treating that as a mutation
    /// causes redundant ActivityKit updates during unrelated saves/deletes.
    func isEquivalentLiveActivityState(to other: Self) -> Bool {
        guard id == other.id,
              profileID == other.profileID,
              profileName == other.profileName,
              babyName == other.babyName,
              typeRawValue == other.typeRawValue,
              eventLabel == other.eventLabel,
              systemImage == other.systemImage,
              caregiverName == other.caregiverName,
              additionalActiveCount == other.additionalActiveCount,
              resolvedIsRunning == other.resolvedIsRunning,
              activeNursingSideRawValue == other.activeNursingSideRawValue,
              datesAreEquivalent(resolvedSessionStartDate, other.resolvedSessionStartDate),
              optionalDatesAreEquivalent(
                activeNursingSideTimerStartDate,
                other.activeNursingSideTimerStartDate
              ) else {
            return false
        }

        guard resolvedIsRunning else {
            return datesAreEquivalent(startDate, other.startDate)
                && valuesAreEquivalent(resolvedElapsedSeconds, other.resolvedElapsedSeconds)
                && valuesAreEquivalent(leftDurationSeconds, other.leftDurationSeconds)
                && valuesAreEquivalent(rightDurationSeconds, other.rightDurationSeconds)
        }

        // The active nursing side advances from its timer start date without a
        // content push. The inactive side is fixed and must still match so a
        // side switch or corrected duration is never deduplicated.
        switch activeNursingSide {
        case .left:
            return valuesAreEquivalent(rightDurationSeconds, other.rightDurationSeconds)
        case .right:
            return valuesAreEquivalent(leftDurationSeconds, other.leftDurationSeconds)
        case .none:
            return valuesAreEquivalent(leftDurationSeconds, other.leftDurationSeconds)
                && valuesAreEquivalent(rightDurationSeconds, other.rightDurationSeconds)
        }
    }

    private func datesAreEquivalent(_ lhs: Date, _ rhs: Date) -> Bool {
        valuesAreEquivalent(lhs.timeIntervalSinceReferenceDate, rhs.timeIntervalSinceReferenceDate)
    }

    private func optionalDatesAreEquivalent(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return datesAreEquivalent(lhs, rhs)
        default:
            return false
        }
    }

    private func valuesAreEquivalent(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) < 0.01
    }

    var startedSincePrefix: String {
        typeRawValue == "sleep" ? "Sleeping since" : "\(eventLabel) since"
    }

    var activeNursingSideElapsedSeconds: TimeInterval {
        switch activeNursingSide {
        case .left:
            leftDurationSeconds
        case .right:
            rightDurationSeconds
        case .none:
            0
        }
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

struct PredictionSnapshot: Codable, Hashable, Sendable {
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

struct TodaySummarySnapshot: Codable, Hashable, Sendable {
    var profileID: UUID?
    var profileName: String?
    var profileTypeRawValue: String?
    var totalSleepSeconds: TimeInterval
    var napCount: Int
    var careSessionCount: Int
    var diaperCount: Int
    var pumpingSessionCount: Int?
    var pumpingSeconds: TimeInterval?
    var solidFeedCount: Int?
    var solidSensitivityCount: Int?
    var allowsSolids: Bool? = nil
    var profileBirthDate: Date? = nil
    var solidsWorkspaceActivated: Bool? = nil
    var hasSolidHistory: Bool? = nil
    var childPottyCount: Int?
    var childPottyAccidentCount: Int?
    var dogFoodCount: Int?
    var dogWaterCount: Int?
    var dogPottyCount: Int?
    var dogWalkSeconds: TimeInterval?
    var summaryMetrics: [CareSummaryMetricSnapshot]?

    var isDog: Bool {
        profileTypeRawValue == "dog"
    }

    var resolvedAllowsSolids: Bool {
        allowsSolids ?? allowsSolids(at: Date())
    }

    func allowsSolids(
        at date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isDog, profileID != nil else { return false }
        if solidsWorkspaceActivated == true || hasSolidHistory == true { return true }
        if let profileBirthDate {
            let ageMonths = calendar.dateComponents([.month], from: profileBirthDate, to: date).month ?? 0
            return ageMonths >= 6
        }
        return allowsSolids ?? false
    }
}

struct CareSummaryMetricSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var value: String
    var systemImage: String
    var tintName: String
    var eventTypeRawValue: String?
}

struct FoodShoppingListItemSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var quantityText: String
    var sectionName: String?
}

struct FoodShoppingListSnapshot: Codable, Hashable, Identifiable, Sendable {
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

struct FoodWidgetSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var selectedList: FoodShoppingListSnapshot?
    var lists: [FoodShoppingListSnapshot]

    static let empty = FoodWidgetSnapshot(
        generatedAt: Date(),
        selectedList: nil,
        lists: []
    )
}

struct QuickLogActionSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var systemImage: String
    var tintName: String
    var destinationPath: String
    var isPinned: Bool?

    var resolvedIsPinned: Bool {
        isPinned ?? false
    }

    func destination(profileID: UUID?) -> String {
        if let profileID {
            return "profile/\(profileID.uuidString)/\(destinationPath)"
        }
        return destinationPath
    }

    func destinationURL(profileID: UUID?) -> URL {
        URL(string: "littlewindows://\(destination(profileID: profileID))")!
    }
}

struct WidgetSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var profileID: UUID?
    var profileName: String?
    var babyName: String
    var activeTimer: ActiveTimerSnapshot?
    var prediction: PredictionSnapshot?
    var todaySummary: TodaySummarySnapshot
    var food: FoodWidgetSnapshot?
    var quickActions: [QuickLogActionSnapshot]?

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
            profileTypeRawValue: "child",
            totalSleepSeconds: 0,
            napCount: 0,
            careSessionCount: 0,
            diaperCount: 0,
            pumpingSessionCount: nil,
            pumpingSeconds: nil,
            solidFeedCount: nil,
            solidSensitivityCount: nil,
            childPottyCount: nil,
            childPottyAccidentCount: nil,
            dogFoodCount: nil,
            dogWaterCount: nil,
            dogPottyCount: nil,
            dogWalkSeconds: nil,
            summaryMetrics: []
        ),
        food: .empty,
        quickActions: []
    )

    var resolvedFood: FoodWidgetSnapshot {
        food ?? .empty
    }

    var resolvedQuickActions: [QuickLogActionSnapshot] {
        quickActions ?? []
    }
}
