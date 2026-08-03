import Foundation

enum WatchCompanionProtocol {
    static let schemaVersion = 1
    static let appGroupIdentifier = "group.com.debidia.LittleWindows"
    static let stateFilename = "watch-companion-state.json"
    static let outboxFilename = "watch-companion-outbox.json"
    static let stateMessageKey = "watchState"
    static let stateRequestMessageKey = "watchStateRequest"
    static let commandMessageKey = "watchCommand"
    static let acknowledgementMessageKey = "watchAcknowledgement"
    static let stateReceiptMessageKey = "watchStateReceipt"
}

struct WatchStateReceipt: Codable, Hashable {
    var schemaVersion: Int
    var stateRevision: UUID
    var receivedAt: Date
}

struct WatchProfileSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var profileTypeRawValue: String
    var displayColor: String?
    var hiddenCategoryRawValues: [String]? = nil
    var activeTimerCategoryRawValues: [String]? = nil
}

struct WatchActionOption: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var systemImage: String
}

struct WatchActionSnapshot: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var systemImage: String
    var tintName: String
    var categoryRawValue: String
    var options: [WatchActionOption]

    var requiresChoice: Bool { !options.isEmpty }
    var startsTimer: Bool { subtitle == "Timer" || id == "nursing" }
}

struct WatchTimerSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var profileID: UUID
    var title: String
    var systemImage: String
    var displayStartDate: Date
    var isRunning: Bool
    var elapsedSeconds: TimeInterval
    var activeNursingSideRawValue: String?
    var leftDurationSeconds: TimeInterval
    var rightDurationSeconds: TimeInterval
    var updatedAt: Date
    var elapsedReferenceDate: Date? = nil

    func elapsed(at date: Date = Date()) -> TimeInterval {
        isRunning
            ? elapsedSeconds + liveDelta(at: date)
            : elapsedSeconds
    }

    func leftDuration(at date: Date = Date()) -> TimeInterval {
        nursingDuration(
            base: leftDurationSeconds,
            sideRawValue: "left",
            at: date
        )
    }

    func rightDuration(at date: Date = Date()) -> TimeInterval {
        nursingDuration(
            base: rightDurationSeconds,
            sideRawValue: "right",
            at: date
        )
    }

    mutating func accrueLiveDurations(at date: Date) {
        guard isRunning else {
            elapsedReferenceDate = date
            return
        }
        elapsedSeconds = elapsed(at: date)
        leftDurationSeconds = leftDuration(at: date)
        rightDurationSeconds = rightDuration(at: date)
        elapsedReferenceDate = date
    }

    private func nursingDuration(
        base: TimeInterval,
        sideRawValue: String,
        at date: Date
    ) -> TimeInterval {
        guard isRunning, activeNursingSideRawValue == sideRawValue else {
            return base
        }
        return base + liveDelta(at: date)
    }

    private func liveDelta(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(elapsedReferenceDate ?? updatedAt))
    }
}

struct WatchPredictionSnapshot: Codable, Hashable {
    var title: String
    var expectedStart: Date
    var windowStart: Date
    var windowEnd: Date
    var confidenceLabel: String
}

struct WatchMetricSnapshot: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var value: String
    var systemImage: String
    var tintName: String
}

struct WatchCompanionState: Codable, Hashable {
    var schemaVersion: Int
    var generatedAt: Date
    var revision: UUID
    var selectedProfileID: UUID?
    var profiles: [WatchProfileSnapshot]
    var activeTimer: WatchTimerSnapshot?
    var prediction: WatchPredictionSnapshot?
    var todayMetrics: [WatchMetricSnapshot]
    var favoriteActions: [WatchActionSnapshot]
    var allActions: [WatchActionSnapshot]

    static let empty = WatchCompanionState(
        schemaVersion: WatchCompanionProtocol.schemaVersion,
        generatedAt: .distantPast,
        revision: UUID(),
        selectedProfileID: nil,
        profiles: [],
        activeTimer: nil,
        prediction: nil,
        todayMetrics: [],
        favoriteActions: [],
        allActions: []
    )

    var selectedProfile: WatchProfileSnapshot? {
        profiles.first { $0.id == selectedProfileID }
    }

    func hasSameContent(as other: WatchCompanionState) -> Bool {
        var lhs = self
        var rhs = other
        lhs.generatedAt = .distantPast
        rhs.generatedAt = .distantPast
        lhs.revision = Self.contentComparisonRevision
        rhs.revision = Self.contentComparisonRevision
        return lhs == rhs
    }

    private static let contentComparisonRevision = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!
}

enum WatchCompanionTimeline {
    static func entryDates(
        timerIsRunning: Bool,
        from startDate: Date,
        liveDuration: TimeInterval = 60 * 60,
        interval: TimeInterval = 60
    ) -> [Date] {
        guard timerIsRunning, liveDuration > 0, interval > 0 else {
            return [startDate]
        }
        let entryCount = max(1, Int(ceil(liveDuration / interval)))
        return (0...entryCount).map {
            startDate.addingTimeInterval(Double($0) * interval)
        }
    }
}

enum WatchCommandKind: String, Codable, Hashable {
    case selectProfile
    case performAction
    case stopTimer
    case stopAndSaveTimer
    case discardTimer
    case resumeTimer
    case switchNursingSide
}

struct WatchCommand: Codable, Hashable, Identifiable {
    var id: UUID
    var schemaVersion: Int
    var kind: WatchCommandKind
    var profileID: UUID
    var eventID: UUID?
    var actionID: String?
    var optionID: String?
    var issuedAt: Date
    var timeZoneIdentifier: String
    var expectedEventUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = WatchCompanionProtocol.schemaVersion,
        kind: WatchCommandKind,
        profileID: UUID,
        eventID: UUID? = nil,
        actionID: String? = nil,
        optionID: String? = nil,
        issuedAt: Date = Date(),
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        expectedEventUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.profileID = profileID
        self.eventID = eventID
        self.actionID = actionID
        self.optionID = optionID
        self.issuedAt = issuedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.expectedEventUpdatedAt = expectedEventUpdatedAt
    }
}

enum WatchCommandDeliveryOrder {
    static func ordered(_ commands: [WatchCommand]) -> [WatchCommand] {
        commands.sorted {
            if $0.issuedAt == $1.issuedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.issuedAt < $1.issuedAt
        }
    }

    static func nextDirectCommand(
        in commands: [WatchCommand],
        outstandingBackgroundCommandIDs: Set<UUID>,
        directCommandInFlightID: UUID?
    ) -> WatchCommand? {
        guard directCommandInFlightID == nil,
              let first = ordered(commands).first,
              !outstandingBackgroundCommandIDs.contains(first.id) else {
            return nil
        }
        return first
    }
}

enum WatchAcknowledgementStatus: String, Codable, Hashable {
    case applied
    case duplicate
    case rejected
    case unsupported
}

struct WatchAcknowledgement: Codable, Hashable {
    var schemaVersion: Int
    var commandID: UUID
    var status: WatchAcknowledgementStatus
    var message: String?
    var state: WatchCompanionState?
}

enum WatchActionCatalog {
    static func actions(profileTypeRawValue: String) -> [WatchActionSnapshot] {
        profileTypeRawValue == "dog" ? dogActions : childActions
    }

    static func canonicalActionID(for actionID: String) -> String {
        switch actionID {
        case "nursing-left", "nursing-right": "nursing"
        case "child-potty", "pee", "poop": "potty"
        default: actionID
        }
    }

    private static let childActions: [WatchActionSnapshot] = [
        action(
            "sleep", "Sleep", "Timer", "moon.stars.fill", "indigo", "sleep",
            options: [
                option("nap", "Nap", "sun.haze.fill"),
                option("nightSleep", "Night sleep", "moon.fill"),
                option("nightWaking", "Night waking", "bell.fill")
            ]
        ),
        action(
            "nursing", "Nursing", "Choose side", "figure.and.child.holdinghands", "pink", "nursing",
            options: [
                option("left", "Left", "l.circle.fill"),
                option("right", "Right", "r.circle.fill")
            ]
        ),
        action(
            "feed", "Feed", "Quick log", "waterbottle.fill", "orange", "feed",
            options: [
                option("bottle", "Bottle", "waterbottle.fill"),
                option("other", "Other feed", "fork.knife")
            ]
        ),
        action(
            "diaper", "Diaper", "Quick log", "drop.fill", "teal", "diaper",
            options: [
                option("wet", "Pee", "drop.fill"),
                option("dirty", "Poo", "circle.fill"),
                option("both", "Mixed", "drop.circle.fill")
            ]
        ),
        action("pumping", "Pumping", "Timer", "drop.circle.fill", "cyan", "pumping"),
        action("tummy-time", "Tummy time", "Timer", "figure.play", "green", "activity"),
        action(
            "potty", "Potty", "Quick log", "figure.child", "teal", "potty",
            options: [
                option("pee", "Pee", "drop.fill"),
                option("poo", "Poo", "circle.fill"),
                option("both", "Both", "drop.circle.fill")
            ]
        ),
        action("story-time", "Story time", "Timer", "book.fill", "blue", "activity"),
        action("brush-teeth", "Brush teeth", "Timer", "mouth.fill", "teal", "activity"),
        action("indoor-play", "Indoor play", "Timer", "house.fill", "green", "activity"),
        action("outdoor-play", "Outdoor play", "Timer", "sun.max.fill", "orange", "activity"),
        action("screen-time", "Screen time", "Timer", "tv.fill", "purple", "activity"),
        action("bath", "Bath", "Timer", "bathtub.fill", "cyan", "activity")
    ]

    private static let dogActions: [WatchActionSnapshot] = [
        action("food", "Food", "Quick log", "fork.knife", "orange", "food"),
        action("water", "Water", "Quick log", "drop.fill", "cyan", "water"),
        action(
            "potty", "Potty", "Quick log", "pawprint.fill", "teal", "potty",
            options: [
                option("pee", "Pee", "drop.fill"),
                option("poop", "Poop", "circle.fill"),
                option("both", "Both", "drop.circle.fill")
            ]
        ),
        action("walk", "Walk", "Timer", "figure.walk", "green", "walk"),
        action("treat", "Treat", "Quick log", "birthday.cake.fill", "pink", "treat"),
        action("rest", "Rest", "Timer", "bed.double.fill", "indigo", "rest"),
        action("training", "Training", "Timer", "graduationcap.fill", "purple", "training"),
        action("grooming", "Grooming", "Timer", "comb.fill", "cyan", "grooming")
    ]

    private static func action(
        _ id: String,
        _ title: String,
        _ subtitle: String?,
        _ systemImage: String,
        _ tintName: String,
        _ categoryRawValue: String,
        options: [WatchActionOption] = []
    ) -> WatchActionSnapshot {
        WatchActionSnapshot(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tintName: tintName,
            categoryRawValue: categoryRawValue,
            options: options
        )
    }

    private static func option(
        _ id: String,
        _ title: String,
        _ systemImage: String
    ) -> WatchActionOption {
        WatchActionOption(id: id, title: title, systemImage: systemImage)
    }
}
