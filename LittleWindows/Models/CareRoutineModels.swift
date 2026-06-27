import Foundation
import SwiftData

enum CareRoutineScope: String, Codable, CaseIterable, Identifiable {
    case profile
    case household

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .profile: "Profile"
        case .household: "Household"
        }
    }
}

enum CareRoutineStepAction: String, Codable, CaseIterable, Identifiable {
    case checklist
    case logEvent
    case startTimer
    case openFoodHome
    case openFoodQuickAdd
    case openShoppingList
    case openInventory
    case openMealPrep
    case openReports
    case openMilestones
    case openAppointments
    case openAgeGuide
    case openPuppyGuide
    case openNightLight
    case openSettings
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checklist: "Checklist"
        case .logEvent: "Log Event"
        case .startTimer: "Start Timer"
        case .openFoodHome: "Open Food & Home"
        case .openFoodQuickAdd: "Quick Add Food"
        case .openShoppingList: "Open Shopping List"
        case .openInventory: "Open Inventory"
        case .openMealPrep: "Open Meal Prep"
        case .openReports: "Open Reports"
        case .openMilestones: "Open Milestones"
        case .openAppointments: "Open Appointments"
        case .openAgeGuide: "Open Age Guide"
        case .openPuppyGuide: "Open Puppy Guide"
        case .openNightLight: "Open Night Light"
        case .openSettings: "Open Settings"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .checklist: "checklist"
        case .logEvent: "plus.circle.fill"
        case .startTimer: "timer"
        case .openFoodHome: "cart.fill"
        case .openFoodQuickAdd: "cart.badge.plus"
        case .openShoppingList: "list.bullet.clipboard.fill"
        case .openInventory: "shippingbox.fill"
        case .openMealPrep: "fork.knife.circle.fill"
        case .openReports: "chart.line.uptrend.xyaxis"
        case .openMilestones: "heart.text.clipboard.fill"
        case .openAppointments: "calendar.badge.clock"
        case .openAgeGuide: "book.closed.fill"
        case .openPuppyGuide: "pawprint.fill"
        case .openNightLight: "lightbulb.fill"
        case .openSettings: "gearshape.fill"
        case .note: "note.text"
        }
    }
}

enum CareRoutineTemplateKind: String, Codable, CaseIterable, Identifiable {
    case childBedtime
    case childMorning
    case medicineCourse
    case dogAfterWalk
    case dogEvening
    case householdGroceryReset
    case householdDaycarePrep

    var id: String { rawValue }
}

enum CareRoutineRunState: String, Codable, CaseIterable, Identifiable {
    case active
    case completed
    case cancelled

    var id: String { rawValue }
}

@Model
final class CareRoutine {
    var id: UUID = UUID()
    var scopeRawValue: String = CareRoutineScope.profile.rawValue
    var profileID: UUID?
    var householdID: UUID?
    var title: String = ""
    var notes: String?
    var iconName: String = "checklist"
    var tintName: String = "indigo"
    var templateKindRawValue: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var reminderEnabled: Bool = false
    var reminderTimeMinutesAfterMidnight: Int?
    var lastStartedAt: Date?
    var lastCompletedAt: Date?

    init(
        id: UUID = UUID(),
        scope: CareRoutineScope,
        profileID: UUID? = nil,
        householdID: UUID? = nil,
        title: String,
        notes: String? = nil,
        iconName: String = "checklist",
        tintName: String = "indigo",
        templateKind: CareRoutineTemplateKind? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        sortOrder: Int = 0,
        reminderEnabled: Bool = false,
        reminderTimeMinutesAfterMidnight: Int? = nil,
        lastStartedAt: Date? = nil,
        lastCompletedAt: Date? = nil
    ) {
        self.id = id
        self.scopeRawValue = scope.rawValue
        self.profileID = profileID
        self.householdID = householdID
        self.title = title
        self.notes = notes
        self.iconName = iconName
        self.tintName = tintName
        self.templateKindRawValue = templateKind?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.reminderEnabled = reminderEnabled
        self.reminderTimeMinutesAfterMidnight = reminderTimeMinutesAfterMidnight
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
    }

    var scope: CareRoutineScope {
        get { CareRoutineScope(rawValue: scopeRawValue) ?? .profile }
        set { scopeRawValue = newValue.rawValue }
    }

    var templateKind: CareRoutineTemplateKind? {
        get { templateKindRawValue.flatMap(CareRoutineTemplateKind.init(rawValue:)) }
        set { templateKindRawValue = newValue?.rawValue }
    }
}

@Model
final class CareRoutineStep {
    var id: UUID = UUID()
    var routineID: UUID = UUID()
    var title: String = ""
    var notes: String?
    var actionRawValue: String = CareRoutineStepAction.checklist.rawValue
    var eventTypeRawValue: String?
    var activityTypeRawValue: String?
    var nursingSideRawValue: String?
    var sleepKindRawValue: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        routineID: UUID,
        title: String,
        notes: String? = nil,
        action: CareRoutineStepAction = .checklist,
        eventType: EventType? = nil,
        activityType: ActivityType? = nil,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        sortOrder: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.routineID = routineID
        self.title = title
        self.notes = notes
        self.actionRawValue = action.rawValue
        self.eventTypeRawValue = eventType?.rawValue
        self.activityTypeRawValue = activityType?.rawValue
        self.nursingSideRawValue = nursingSide?.rawValue
        self.sleepKindRawValue = sleepKind?.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var action: CareRoutineStepAction {
        get { CareRoutineStepAction(rawValue: actionRawValue) ?? .checklist }
        set { actionRawValue = newValue.rawValue }
    }

    var eventType: EventType? {
        get { eventTypeRawValue.map(EventType.normalized(rawValue:)) }
        set { eventTypeRawValue = newValue?.rawValue }
    }

    var activityType: ActivityType? {
        get { activityTypeRawValue.flatMap(ActivityType.init(rawValue:)) }
        set { activityTypeRawValue = newValue?.rawValue }
    }

    var nursingSide: NursingSide? {
        get { nursingSideRawValue.flatMap(NursingSide.init(rawValue:)) }
        set { nursingSideRawValue = newValue?.rawValue }
    }

    var sleepKind: SleepKind? {
        get { sleepKindRawValue.flatMap(SleepKind.init(rawValue:)) }
        set { sleepKindRawValue = newValue?.rawValue }
    }
}

@Model
final class CareRoutineRun {
    var id: UUID = UUID()
    var routineID: UUID = UUID()
    var profileID: UUID?
    var householdID: UUID?
    var stateRawValue: String = CareRoutineRunState.active.rawValue
    var startedAt: Date = Date()
    var completedAt: Date?
    var cancelledAt: Date?
    var completedStepIDsData: Data?
    var skippedStepIDsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        routineID: UUID,
        profileID: UUID? = nil,
        householdID: UUID? = nil,
        state: CareRoutineRunState = .active,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        completedStepIDs: [UUID] = [],
        skippedStepIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.routineID = routineID
        self.profileID = profileID
        self.householdID = householdID
        self.stateRawValue = state.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.completedStepIDs = completedStepIDs
        self.skippedStepIDs = skippedStepIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var state: CareRoutineRunState {
        get { CareRoutineRunState(rawValue: stateRawValue) ?? .active }
        set { stateRawValue = newValue.rawValue }
    }

    var completedStepIDs: [UUID] {
        get { decodeIDs(completedStepIDsData) }
        set { completedStepIDsData = encodeIDs(newValue) }
    }

    var skippedStepIDs: [UUID] {
        get { decodeIDs(skippedStepIDsData) }
        set { skippedStepIDsData = encodeIDs(newValue) }
    }

    func isCompleted(stepID: UUID) -> Bool {
        completedStepIDs.contains(stepID)
    }

    func isSkipped(stepID: UUID) -> Bool {
        skippedStepIDs.contains(stepID)
    }

    private func decodeIDs(_ data: Data?) -> [UUID] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }

    private func encodeIDs(_ ids: [UUID]) -> Data? {
        try? JSONEncoder().encode(ids)
    }
}
