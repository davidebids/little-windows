import Combine
import Foundation
import SwiftData
import UIKit
import UserNotifications

enum LittleWindowConfidenceThreshold: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    func includes(_ confidence: ConfidenceLabel) -> Bool {
        let confidenceRank: Int
        switch confidence {
        case .low: confidenceRank = 0
        case .medium: confidenceRank = 1
        case .high: confidenceRank = 2
        }
        return confidenceRank >= rank
    }
}

struct LittleWindowAlertSettings: Equatable {
    var enabled: Bool
    var leadMinutes: Int
    var napAlertsEnabled: Bool
    var bedtimeAlertsEnabled: Bool
    var confidenceThreshold: LittleWindowConfidenceThreshold

    static var current: LittleWindowAlertSettings {
        let defaults = UserDefaults.standard
        return LittleWindowAlertSettings(
            enabled: defaults.bool(forKey: "predictionNotificationsEnabled"),
            leadMinutes: defaults.object(forKey: "notificationLeadMinutes") == nil
                ? 10
                : defaults.integer(forKey: "notificationLeadMinutes"),
            napAlertsEnabled: defaults.object(forKey: "littleWindowNapAlertsEnabled") == nil
                ? true
                : defaults.bool(forKey: "littleWindowNapAlertsEnabled"),
            bedtimeAlertsEnabled: defaults.object(forKey: "littleWindowBedtimeAlertsEnabled") == nil
                ? true
                : defaults.bool(forKey: "littleWindowBedtimeAlertsEnabled"),
            confidenceThreshold: LittleWindowConfidenceThreshold(
                rawValue: defaults.string(forKey: "littleWindowConfidenceThreshold") ?? ""
            ) ?? .medium
        )
    }

    var signature: String {
        "\(leadMinutes)|\(napAlertsEnabled)|\(bedtimeAlertsEnabled)|\(confidenceThreshold.rawValue)"
    }
}

enum LittleWindowAlertSkipReason: String, Codable, Equatable {
    case alertsOff
    case noPrediction
    case sleeping
    case napAlertsOff
    case bedtimeAlertsOff
    case belowConfidenceThreshold
    case alertTimePassed
    case permissionDenied
}

enum LittleWindowAlertDecision: Equatable {
    case schedule(Date)
    case skip(LittleWindowAlertSkipReason)
}

enum SleepPressureAlertSkipReason: String, Codable, Equatable {
    case alertsOff
    case noPressure
    case learning
    case sleeping
    case alreadyHigh
    case alertTimePassed
    case permissionDenied
}

enum SleepPressureAlertDecision: Equatable {
    case schedule(Date, SleepPressureBand)
    case skip(SleepPressureAlertSkipReason)
}

struct LittleWindowNotificationState: Codable, Equatable {
    var lastScheduledPredictionID: String?
    var lastScheduledPredictionStart: Date?
    var lastScheduledAlertTime: Date?
    var lastScheduledKindRawValue: String?
    var lastScheduledConfidenceRawValue: String?
    var settingsSignature: String?
    var skipReason: LittleWindowAlertSkipReason?
    var lastUpdatedAt: Date

    static let empty = LittleWindowNotificationState(lastUpdatedAt: Date())
}

struct LittleWindowNotificationCopy: Equatable {
    var title: String
    var body: String
}

enum FamilySyncActivityNotificationCategory: String, Equatable {
    case general
    case homeTodo
    case trip
}

struct FamilySyncActivityNotification: Equatable {
    var title: String
    var body: String
    var deepLinkPath: String
    var category: FamilySyncActivityNotificationCategory = .general
}

struct SolidMealReminderSnapshot: Sendable {
    var id: UUID
    var profileID: UUID
    var scheduledAt: Date
    var title: String
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var isCompleted: Bool

    init(
        id: UUID,
        profileID: UUID,
        scheduledAt: Date,
        title: String,
        reminderEnabled: Bool,
        reminderOffsetMinutes: Int,
        isCompleted: Bool
    ) {
        self.id = id
        self.profileID = profileID
        self.scheduledAt = scheduledAt
        self.title = title
        self.reminderEnabled = reminderEnabled
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.isCompleted = isCompleted
    }

    @MainActor
    init(plan: PlannedSolidMeal) {
        self.init(
            id: plan.id,
            profileID: plan.profileID,
            scheduledAt: plan.scheduledAt,
            title: plan.title,
            reminderEnabled: plan.reminderEnabled,
            reminderOffsetMinutes: plan.reminderOffsetMinutes,
            isCompleted: plan.isCompleted
        )
    }
}

struct SolidAllergenReminderSnapshot: Sendable {
    var profileID: UUID
    var allergenID: String
    var statusRawValue: String
    var nextExposureDueAt: Date?
    var reminderEnabled: Bool

    init(
        profileID: UUID,
        allergenID: String,
        statusRawValue: String,
        nextExposureDueAt: Date?,
        reminderEnabled: Bool
    ) {
        self.profileID = profileID
        self.allergenID = allergenID
        self.statusRawValue = statusRawValue
        self.nextExposureDueAt = nextExposureDueAt
        self.reminderEnabled = reminderEnabled
    }

    @MainActor
    init(progress: SolidAllergenProgress) {
        self.init(
            profileID: progress.profileID,
            allergenID: progress.allergenID,
            statusRawValue: progress.statusRawValue,
            nextExposureDueAt: progress.nextExposureDueAt,
            reminderEnabled: progress.reminderEnabled
        )
    }
}

enum PackingTripReminderScheduleResult: Equatable {
    case notEligible
    case permissionRequired
    case permissionDenied
    case noFutureReminders
    case scheduled(Int)
    case failed
}

struct PackingTripReminderSnapshot: Sendable {
    var id: UUID
    var householdID: UUID
    var title: String
    var isUpcoming: Bool
    var isArchived: Bool
    var reminderDate: Date?
    var finalCheckDate: Date?
    var targetCaregiverName: String?
    var assignedRemainingCount: Int
    var usesTargetedReminders: Bool
    var isEligibleForCurrentCaregiver: Bool

    @MainActor
    init(
        trip: PackingTrip,
        items: [PackingItem] = [],
        currentCaregiverName: String = CaregiverIdentityService.currentCaregiverName()
    ) {
        id = trip.id
        householdID = trip.householdID
        title = trip.title
        isUpcoming = trip.status == .upcoming
        isArchived = trip.isArchived
        reminderDate = trip.reminderDate
        finalCheckDate = trip.finalCheckDate
        let assignedItems = items.filter {
            $0.tripID == trip.id
                && $0.state != .notNeeded
                && CaregiverIdentityService.normalizedName($0.assignedCaregiverName) != nil
        }
        let matchingRemaining = assignedItems.filter {
            $0.state == .needed
                && $0.caregiverReminderEnabled
                && CaregiverIdentityService.namesMatch(
                    $0.assignedCaregiverName,
                    currentCaregiverName
                )
        }
        targetCaregiverName = matchingRemaining.isEmpty
            ? nil
            : currentCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        assignedRemainingCount = matchingRemaining.count
        usesTargetedReminders = !assignedItems.isEmpty
        isEligibleForCurrentCaregiver = assignedItems.isEmpty || !matchingRemaining.isEmpty
    }
}

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    static let nextNotificationID = "littlewindow.next"
    static let prewindowNotificationID = "littlewindow.next.prewindow"
    static let windowStartNotificationID = "littlewindow.next.windowstart"
    static let categoryID = "LITTLE_WINDOW_ALERT"
    static let startSleepActionID = "START_SLEEP_TIMER"
    static let snoozeActionID = "SNOOZE_LITTLE_WINDOW"
    static let openPredictionActionID = "OPEN_LITTLE_WINDOWS_PREDICTION"
    static let appointmentCategoryID = "DOCTOR_APPOINTMENT_ALERT"
    static let openAppointmentActionID = "OPEN_APPOINTMENT"
    static let completeAppointmentActionID = "COMPLETE_APPOINTMENT"
    static let addVisitNotesActionID = "ADD_VISIT_NOTES"
    static let activeSleepPlanWakeNotificationBaseID = "activeSleepPlan.wake"
    static let sleepPressureNotificationBaseID = "sleepPressure.ready"
    static let activeSleepPlanCategoryID = "ACTIVE_SLEEP_PLAN_WAKE"
    static let ageGuideCategoryID = "MONTHLY_AGE_GUIDE"
    static let openAgeGuideActionID = "OPEN_AGE_GUIDE"
    static let foodReminderCategoryID = "FOOD_HOME_REMINDER"
    static let openFoodActionID = "OPEN_FOOD_HOME"
    static let packingTripReminderCategoryID = "PACKING_TRIP_REMINDER"
    static let openPackingTripActionID = "OPEN_PACKING_TRIP"
    static let itineraryReminderCategoryID = "TRIP_ITINERARY_REMINDER"
    static let routineReminderCategoryID = "CARE_ROUTINE_REMINDER"
    static let openRoutineActionID = "OPEN_CARE_ROUTINES"
    static let familySyncActivityCategoryID = "FAMILY_SYNC_ACTIVITY"
    static let openFamilySyncActivityActionID = "OPEN_FAMILY_SYNC_ACTIVITY"
    static let familySyncAccessEndedNotificationID = "family.sync.access-ended"

    private static let stateKey = "littleWindowNotificationState"
    private static let statesByProfileKey = "littleWindowNotificationStatesByProfile"
    private static let unscopedStateKey = "unscoped"
    private static let allNotificationIDs = [
        nextNotificationID,
        prewindowNotificationID,
        windowStartNotificationID
    ]

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationState: LittleWindowNotificationState
    private var statesByProfile: [String: LittleWindowNotificationState]
    private var lockedItineraryReminderIDs = Set<UUID>()
    private var itineraryReminderWaiters = [UUID: [CheckedContinuation<Void, Never>]]()

    private override init() {
        let loadedStates = Self.loadStatesByProfile()
        statesByProfile = loadedStates
        notificationState = loadedStates[Self.unscopedStateKey] ?? Self.loadState()
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func configure() async {
        registerNotificationCategories()
        UIApplication.shared.registerForRemoteNotifications()
        await refreshAuthorizationStatus()
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await getAuthorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        registerNotificationCategories()
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func ensureAuthorization() async -> Bool {
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func registerNotificationCategories() {
        let startSleep = UNNotificationAction(
            identifier: Self.startSleepActionID,
            title: "Start Sleep Timer",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "Snooze 10 min",
            options: []
        )
        let open = UNNotificationAction(
            identifier: Self.openPredictionActionID,
            title: "Open Little Windows",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [startSleep, snooze, open],
            intentIdentifiers: [],
            options: []
        )
        let openAppointment = UNNotificationAction(
            identifier: Self.openAppointmentActionID,
            title: "Open Appointment",
            options: [.foreground]
        )
        let completeAppointment = UNNotificationAction(
            identifier: Self.completeAppointmentActionID,
            title: "Mark Complete",
            options: [.foreground]
        )
        let addNotes = UNNotificationAction(
            identifier: Self.addVisitNotesActionID,
            title: "Add Visit Notes",
            options: [.foreground]
        )
        let appointmentCategory = UNNotificationCategory(
            identifier: Self.appointmentCategoryID,
            actions: [openAppointment, completeAppointment, addNotes],
            intentIdentifiers: [],
            options: []
        )
        let activePlanCategory = UNNotificationCategory(
            identifier: Self.activeSleepPlanCategoryID,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        let openAgeGuide = UNNotificationAction(
            identifier: Self.openAgeGuideActionID,
            title: "Read Guide",
            options: [.foreground]
        )
        let ageGuideCategory = UNNotificationCategory(
            identifier: Self.ageGuideCategoryID,
            actions: [openAgeGuide],
            intentIdentifiers: [],
            options: []
        )
        let openFood = UNNotificationAction(
            identifier: Self.openFoodActionID,
            title: "Open Food & Home",
            options: [.foreground]
        )
        let foodCategory = UNNotificationCategory(
            identifier: Self.foodReminderCategoryID,
            actions: [openFood],
            intentIdentifiers: [],
            options: []
        )
        let openPackingTrip = UNNotificationAction(
            identifier: Self.openPackingTripActionID,
            title: "Open Trip",
            options: [.foreground]
        )
        let packingTripCategory = UNNotificationCategory(
            identifier: Self.packingTripReminderCategoryID,
            actions: [openPackingTrip],
            intentIdentifiers: [],
            options: []
        )
        let itineraryCategory = UNNotificationCategory(
            identifier: Self.itineraryReminderCategoryID,
            actions: [openPackingTrip],
            intentIdentifiers: [],
            options: []
        )
        let openRoutine = UNNotificationAction(
            identifier: Self.openRoutineActionID,
            title: "Open Routines",
            options: [.foreground]
        )
        let routineCategory = UNNotificationCategory(
            identifier: Self.routineReminderCategoryID,
            actions: [openRoutine],
            intentIdentifiers: [],
            options: []
        )
        let openFamilySyncActivity = UNNotificationAction(
            identifier: Self.openFamilySyncActivityActionID,
            title: "Open",
            options: [.foreground]
        )
        let familySyncActivityCategory = UNNotificationCategory(
            identifier: Self.familySyncActivityCategoryID,
            actions: [openFamilySyncActivity],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            category,
            appointmentCategory,
            activePlanCategory,
            ageGuideCategory,
            foodCategory,
            packingTripCategory,
            itineraryCategory,
            routineCategory,
            familySyncActivityCategory
        ])
    }

    func schedule(
        prediction: SleepPrediction?,
        babyName: String,
        profileID: UUID? = nil,
        leadMinutes: Int,
        enabled: Bool,
        isSleeping: Bool = false
    ) async {
        var settings = LittleWindowAlertSettings.current
        settings.enabled = enabled
        settings.leadMinutes = leadMinutes
        await rescheduleLittleWindowAlertIfNeeded(
            prediction: prediction,
            babyName: babyName,
            profileID: profileID,
            settings: settings,
            isSleeping: isSleeping
        )
    }

    func scheduleLittleWindowAlert(
        prediction: SleepPrediction,
        babyName: String,
        profileID: UUID? = nil,
        settings: LittleWindowAlertSettings,
        now: Date = Date()
    ) async {
        await rescheduleLittleWindowAlertIfNeeded(
            prediction: prediction,
            babyName: babyName,
            profileID: profileID,
            settings: settings,
            now: now
        )
    }

    func rescheduleLittleWindowAlertIfNeeded(
        prediction: SleepPrediction?,
        babyName: String,
        profileID: UUID? = nil,
        settings: LittleWindowAlertSettings = .current,
        isSleeping: Bool = false,
        now: Date = Date()
    ) async {
        let decision = Self.schedulingDecision(
            prediction: prediction,
            settings: settings,
            isSleeping: isSleeping,
            now: now
        )

        guard case .schedule(let fireDate) = decision, let prediction else {
            await cancelPendingLittleWindowAlerts(profileID: profileID)
            let reason: LittleWindowAlertSkipReason
            if case .skip(let value) = decision {
                reason = value
            } else {
                reason = .noPrediction
            }
            updateState(
                LittleWindowNotificationState(
                    skipReason: reason,
                    lastUpdatedAt: now
                ),
                profileID: profileID
            )
            return
        }

        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await cancelPendingLittleWindowAlerts(profileID: profileID)
            updateState(
                LittleWindowNotificationState(
                    skipReason: status == .denied ? .permissionDenied : .alertsOff,
                    lastUpdatedAt: now
                ),
                profileID: profileID
            )
            return
        }

        if Self.shouldKeepExistingSchedule(
            state: state(profileID: profileID),
            prediction: prediction,
            fireDate: fireDate,
            settings: settings
        ) {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let identifiers = Self.littleWindowNotificationIDs(profileID: profileID)
            if pending.contains(where: { identifiers.contains($0.identifier) }) {
                return
            }
        }

        await cancelPendingLittleWindowAlerts(profileID: profileID, clearState: false)
        let content = buildNotificationContent(
            for: prediction,
            babyName: babyName,
            profileID: profileID,
            leadMinutes: settings.leadMinutes
        )
        let trigger = Self.oneShotTrigger(at: fireDate, now: now)
        let identifier = settings.leadMinutes == 0
            ? Self.scopedNotificationID(Self.windowStartNotificationID, profileID: profileID)
            : Self.scopedNotificationID(Self.prewindowNotificationID, profileID: profileID)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            updateState(
                LittleWindowNotificationState(
                    lastScheduledPredictionID: Self.predictionID(for: prediction),
                    lastScheduledPredictionStart: prediction.predictedStart,
                    lastScheduledAlertTime: fireDate,
                    lastScheduledKindRawValue: prediction.predictionKind.rawValue,
                    lastScheduledConfidenceRawValue: prediction.confidenceLabel.rawValue,
                    settingsSignature: settings.signature,
                    skipReason: nil,
                    lastUpdatedAt: now
                ),
                profileID: profileID
            )
        } catch {
            updateState(
                LittleWindowNotificationState(
                    skipReason: .alertsOff,
                    lastUpdatedAt: now
                ),
                profileID: profileID
            )
        }
    }

    func cancelPendingLittleWindowAlerts(
        profileID: UUID? = nil,
        clearState: Bool = true
    ) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.littleWindowNotificationIDs(profileID: profileID)
        )
        if clearState {
            updateState(.empty, profileID: profileID)
        }
    }

    func cancelAllPendingLittleWindowAlerts(clearState: Bool = true) async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { identifier in
            Self.allNotificationIDs.contains(identifier)
                || Self.allNotificationIDs.contains { identifier.hasSuffix(".\($0)") }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        if clearState {
            statesByProfile.removeAll()
            notificationState = .empty
            UserDefaults.standard.removeObject(forKey: Self.statesByProfileKey)
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
        }
    }

    func rescheduleSleepPressureAlertIfNeeded(
        pressure: SleepPressure?,
        babyName: String,
        profileID: UUID? = nil,
        enabled: Bool,
        isSleeping: Bool = false,
        now: Date = Date()
    ) async {
        let decision = Self.sleepPressureAlertDecision(
            pressure: pressure,
            enabled: enabled,
            isSleeping: isSleeping,
            now: now
        )

        await cancelPendingSleepPressureAlerts(profileID: profileID)
        guard case .schedule(let fireDate, let targetBand) = decision,
              let pressure else {
            return
        }

        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = buildSleepPressureNotificationContent(
            pressure: pressure,
            targetBand: targetBand,
            babyName: babyName,
            profileID: profileID
        )
        let request = UNNotificationRequest(
            identifier: Self.sleepPressureNotificationID(profileID: profileID),
            content: content,
            trigger: Self.oneShotTrigger(at: fireDate, now: now)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelPendingSleepPressureAlerts(profileID: UUID? = nil) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.sleepPressureNotificationID(profileID: profileID)]
        )
    }

    func cancelAllPendingSleepPressureAlerts() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter {
            $0 == Self.sleepPressureNotificationBaseID
                || $0.hasSuffix(".\(Self.sleepPressureNotificationBaseID)")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
    }

    func scheduleAppointmentReminders(
        appointment: DoctorAppointment,
        babyName: String = "Baby",
        now: Date = Date()
    ) async {
        await rescheduleAppointmentReminders(
            appointment: appointment,
            babyName: babyName,
            now: now
        )
    }

    func rescheduleAppointmentReminders(
        appointment: DoctorAppointment,
        babyName: String = "Baby",
        now: Date = Date()
    ) async {
        await cancelAppointmentReminders(appointmentID: appointment.id)
        guard UserDefaults.standard.object(forKey: "appointmentRemindersEnabled") == nil
                || UserDefaults.standard.bool(forKey: "appointmentRemindersEnabled") else {
            return
        }
        guard appointment.remindersEnabled, !appointment.isCompleted else { return }

        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let center = UNUserNotificationCenter.current()
        for leadTime in appointment.reminderLeadTimes {
            let fireDate = appointment.startDate.addingTimeInterval(
                Double(-leadTime.rawValue) * 60
            )
            guard fireDate > now else { continue }
            let request = UNNotificationRequest(
                identifier: Self.appointmentNotificationID(
                    appointmentID: appointment.id,
                    leadTime: leadTime,
                    profileID: appointment.profileID
                ),
                content: buildAppointmentNotificationContent(
                    appointment: appointment,
                    babyName: babyName,
                    profileID: appointment.profileID,
                    leadTime: leadTime
                ),
                trigger: Self.oneShotTrigger(at: fireDate, now: now)
            )
            try? await center.add(request)
        }
    }

    func cancelAppointmentReminders(appointmentID: UUID) async {
        let prefix = "appointment.\(appointmentID.uuidString)."
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
    }

    func scheduleActiveSleepPlanWakeAlert(
        _ alert: ActiveSleepPlanWakeAlert?,
        babyName: String,
        now: Date = Date()
    ) async {
        await cancelActiveSleepPlanWakeAlert(profileID: alert?.profileID)
        guard let alert else { return }

        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = buildActiveSleepPlanWakeContent(
            alert: alert,
            babyName: babyName
        )
        let trigger: UNNotificationTrigger?
        if alert.wakeByDate > now {
            trigger = Self.oneShotTrigger(at: alert.wakeByDate, now: now)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(
            identifier: Self.activeSleepPlanWakeNotificationID(profileID: alert.profileID),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelActiveSleepPlanWakeAlert(profileID: UUID? = nil) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.activeSleepPlanWakeNotificationID(profileID: profileID)]
        )
    }

    func buildAppointmentNotificationContent(
        appointment: DoctorAppointment,
        babyName: String = "Baby",
        profileID: UUID? = nil,
        leadTime: AppointmentReminderLeadTime
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let time = Self.timeString(
            from: appointment.startDate,
            timeZone: appointment.timeZone
        )
        switch leadTime {
        case .oneDay:
            content.title = "\(babyName)'s appointment tomorrow"
            content.body = "\(appointment.displayTitle) at \(time)."
        case .atTime:
            content.title = "Appointment now"
            content.body = "\(babyName)'s \(appointment.appointmentType.displayName.lowercased()) is starting."
        default:
            content.title = "Doctor visit coming up"
            content.body = "\(appointment.displayTitle) in \(leadTime.displayName.replacingOccurrences(of: " before", with: ""))."
        }
        content.sound = .default
        content.categoryIdentifier = Self.appointmentCategoryID
        var userInfo: [String: Any] = [
            "appointmentID": appointment.id.uuidString,
            "deepLink": Self.deepLink(
                path: "appointment/\(appointment.id.uuidString)",
                profileID: profileID
            )
        ]
        if let profileID {
            userInfo["profileID"] = profileID.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    func buildActiveSleepPlanWakeContent(
        alert: ActiveSleepPlanWakeAlert,
        babyName: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let wakeTime = DateFormatting.time.string(from: alert.wakeByDate)
        let bedtime = DateFormatting.time.string(from: alert.targetBedtime)
        content.title = "Wake \(babyName) by \(wakeTime)"
        content.body = "To keep \(bedtime) bedtime, this nap should end around \(wakeTime)."
        content.sound = .default
        content.categoryIdentifier = Self.activeSleepPlanCategoryID
        content.userInfo = [
            "profileID": alert.profileID.uuidString,
            "activeSleepEventID": alert.activeSleepEventID.uuidString,
            "targetBedtime": alert.targetBedtime.timeIntervalSince1970,
            "wakeBy": alert.wakeByDate.timeIntervalSince1970,
            "deepLink": Self.deepLink(path: "active-timer", profileID: alert.profileID)
        ]
        return content
    }

    func scheduleMonthlyAgeGuideNotification(
        profile: BabyProfile,
        readStates: [AgeGuideReadState],
        context: ModelContext,
        timing: MonthlyAgeGuideNotificationTiming,
        now: Date = Date()
    ) async {
        await cancelMonthlyAgeGuideNotifications(profileID: profile.id)
        guard UserDefaults.standard.object(forKey: "monthlyAgeGuideNotificationsEnabled") == nil
                || UserDefaults.standard.bool(forKey: "monthlyAgeGuideNotificationsEnabled") else {
            return
        }

        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let service = AgeGuideService.shared
        guard let candidate = service.allAgeGuides()
            .compactMap({ guide -> (AgeGuide, Date)? in
                guard readStates.first(where: {
                    $0.guideID == guide.id && $0.notificationSentAt != nil
                }) == nil,
                      let reachedDate = service.monthlyBirthdayDate(
                        for: profile,
                        ageMonth: guide.ageMonth
                      ) else {
                    return nil
                }
                let fireDate = Self.monthlyAgeGuideFireDate(
                    reachedDate: reachedDate,
                    timing: timing
                )
                return fireDate > now ? (guide, fireDate) : nil
            })
            .sorted(by: { $0.1 < $1.1 })
            .first else {
            return
        }

        let request = UNNotificationRequest(
            identifier: Self.monthlyAgeGuideNotificationID(
                guideID: candidate.0.id,
                profileID: profile.id
            ),
            content: buildMonthlyAgeGuideNotificationContent(
                guide: candidate.0,
                babyName: profile.name,
                profileID: profile.id
            ),
            trigger: Self.oneShotTrigger(at: candidate.1, now: now)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            return
        }
    }

    func cancelMonthlyAgeGuideNotifications(profileID: UUID? = nil) async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { identifier in
                guard let profileID else { return identifier.hasPrefix("ageguide.") }
                return identifier.hasPrefix("ageguide.\(profileID.uuidString).")
            }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
    }

    func scheduleFoodReminder(reminder: FoodReminder, now: Date = Date()) async {
        await cancelFoodReminder(reminderID: reminder.id)
        guard reminder.isEnabled, reminder.dateTime > now else { return }
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }
        let request = UNNotificationRequest(
            identifier: Self.foodReminderNotificationID(reminderID: reminder.id),
            content: buildFoodReminderNotificationContent(reminder: reminder),
            trigger: Self.oneShotTrigger(at: reminder.dateTime, now: now)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelFoodReminder(reminderID: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.foodReminderNotificationID(reminderID: reminderID)]
        )
    }

    func scheduleSolidMealReminder(plan: PlannedSolidMeal, now: Date = Date()) async {
        await scheduleSolidMealReminder(snapshot: SolidMealReminderSnapshot(plan: plan), now: now)
    }

    func scheduleSolidMealReminder(
        snapshot: SolidMealReminderSnapshot,
        now: Date = Date()
    ) async {
        await cancelSolidMealReminder(planID: snapshot.id)
        guard snapshot.reminderEnabled, !snapshot.isCompleted else { return }
        let fireDate = snapshot.scheduledAt.addingTimeInterval(
            Double(-snapshot.reminderOffsetMinutes) * 60
        )
        guard fireDate > now else { return }
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let content = UNMutableNotificationContent()
        content.title = "Solids meal coming up"
        content.body = snapshot.title
        content.sound = .default
        content.categoryIdentifier = Self.foodReminderCategoryID
        content.userInfo = [
            "profileID": snapshot.profileID.uuidString,
            "plannedSolidMealID": snapshot.id.uuidString,
            "deepLink": Self.deepLink(
                path: "food/solids/plan/\(snapshot.id.uuidString)",
                profileID: snapshot.profileID
            )
        ]
        let request = UNNotificationRequest(
            identifier: Self.solidMealReminderNotificationID(planID: snapshot.id),
            content: content,
            trigger: Self.oneShotTrigger(at: fireDate, now: now)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelSolidMealReminder(planID: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.solidMealReminderNotificationID(planID: planID)]
        )
    }

    func scheduleSolidAllergenReminder(
        progress: SolidAllergenProgress,
        now: Date = Date()
    ) async {
        await scheduleSolidAllergenReminder(
            snapshot: SolidAllergenReminderSnapshot(progress: progress),
            now: now
        )
    }

    func scheduleSolidAllergenReminder(
        snapshot: SolidAllergenReminderSnapshot,
        now: Date = Date()
    ) async {
        await cancelSolidAllergenReminder(
            profileID: snapshot.profileID,
            allergenID: snapshot.allergenID
        )
        guard snapshot.reminderEnabled,
              snapshot.statusRawValue != SolidAllergenStatus.suspectedReaction.rawValue,
              snapshot.statusRawValue != SolidAllergenStatus.avoidPendingAdvice.rawValue,
              let fireDate = snapshot.nextExposureDueAt,
              fireDate > now else { return }
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let name = SolidsAllergen(rawValue: snapshot.allergenID)?.displayName ?? snapshot.allergenID
        let content = UNMutableNotificationContent()
        content.title = "Keep \(name) in rotation"
        content.body = "Plan an age-appropriate \(name.lowercased()) food if it remains tolerated."
        content.sound = .default
        content.categoryIdentifier = Self.foodReminderCategoryID
        content.userInfo = [
            "profileID": snapshot.profileID.uuidString,
            "allergenID": snapshot.allergenID,
            "deepLink": Self.deepLink(
                path: "food/solids/allergens/\(snapshot.allergenID)",
                profileID: snapshot.profileID
            )
        ]
        let request = UNNotificationRequest(
            identifier: Self.solidAllergenReminderNotificationID(
                profileID: snapshot.profileID,
                allergenID: snapshot.allergenID
            ),
            content: content,
            trigger: Self.oneShotTrigger(at: fireDate, now: now)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelSolidAllergenReminder(profileID: UUID, allergenID: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.solidAllergenReminderNotificationID(
                profileID: profileID,
                allergenID: allergenID
            )]
        )
    }

    @discardableResult
    func reschedulePackingTripReminders(
        trip: PackingTrip,
        now: Date = Date()
    ) async -> PackingTripReminderScheduleResult {
        let snapshot = PackingTripReminderSnapshot(trip: trip)
        return await reschedulePackingTripReminders(snapshot: snapshot, now: now)
    }

    @discardableResult
    func reschedulePackingTripReminders(
        trip: PackingTrip,
        items: [PackingItem],
        currentCaregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) async -> PackingTripReminderScheduleResult {
        let snapshot = PackingTripReminderSnapshot(
            trip: trip,
            items: items,
            currentCaregiverName: currentCaregiverName
        )
        return await reschedulePackingTripReminders(snapshot: snapshot, now: now)
    }

    @discardableResult
    func reschedulePackingTripReminders(
        snapshot: PackingTripReminderSnapshot,
        now: Date = Date()
    ) async -> PackingTripReminderScheduleResult {
        await cancelPackingTripReminders(tripID: snapshot.id)
        guard !snapshot.isArchived,
              snapshot.isUpcoming,
              snapshot.isEligibleForCurrentCaregiver else { return .notEligible }
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        if status == .notDetermined {
            return .permissionRequired
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return .permissionDenied
        }
        let reminders = Self.packingTripReminderDates(snapshot: snapshot, now: now)
        guard !reminders.isEmpty else { return .noFutureReminders }
        do {
            for reminder in reminders {
                let request = UNNotificationRequest(
                    identifier: Self.packingTripNotificationID(
                        tripID: snapshot.id,
                        kind: reminder.finalCheck ? "final" : "start"
                    ),
                    content: buildPackingTripNotificationContent(
                        snapshot: snapshot,
                        finalCheck: reminder.finalCheck
                    ),
                    trigger: Self.oneShotTrigger(at: reminder.date, now: now)
                )
                try await UNUserNotificationCenter.current().add(request)
            }
            return .scheduled(reminders.count)
        } catch {
            await cancelPackingTripReminders(tripID: snapshot.id)
            return .failed
        }
    }

    static func packingTripReminderDates(
        trip: PackingTrip,
        now: Date
    ) -> [(date: Date, finalCheck: Bool)] {
        packingTripReminderDates(
            snapshot: PackingTripReminderSnapshot(trip: trip),
            now: now
        )
    }

    static func packingTripReminderDates(
        snapshot: PackingTripReminderSnapshot,
        now: Date
    ) -> [(date: Date, finalCheck: Bool)] {
        var values = [(date: Date, finalCheck: Bool)]()
        if let reminderDate = snapshot.reminderDate, reminderDate > now {
            values.append((reminderDate, false))
        }
        if let finalCheckDate = snapshot.finalCheckDate, finalCheckDate > now {
            values.append((finalCheckDate, true))
        }
        return values.sorted { $0.date < $1.date }
    }

    func cancelPackingTripReminders(tripID: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                Self.packingTripNotificationID(tripID: tripID, kind: "start"),
                Self.packingTripNotificationID(tripID: tripID, kind: "final")
            ]
        )
    }

    func rescheduleItineraryItemReminder(
        item: TripItineraryItem,
        trip: PackingTrip,
        choiceIsSelected: Bool = true,
        authorizationAlreadyConfirmed: Bool = false,
        currentCaregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) async {
        await lockItineraryReminder(item.id)
        defer { unlockItineraryReminder(item.id) }
        guard !Task.isCancelled else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.itineraryItemNotificationID(itemID: item.id)]
        )
        guard !trip.isArchived,
              trip.status == .upcoming,
              choiceIsSelected,
              !item.isCompleted,
              item.bookingStatus != .cancelled,
              let fireDate = item.reminderDate,
              fireDate > now else { return }
        if let assigned = item.assignedCaregiverName,
           !CaregiverIdentityService.namesMatch(assigned, currentCaregiverName) {
            return
        }
        if !authorizationAlreadyConfirmed {
            let status = await getAuthorizationStatus()
            authorizationStatus = status
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        }
        let request = UNNotificationRequest(
            identifier: Self.itineraryItemNotificationID(itemID: item.id),
            content: buildItineraryItemNotificationContent(item: item, trip: trip),
            trigger: Self.oneShotTrigger(at: fireDate, now: now)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelItineraryItemReminder(itemID: UUID) async {
        await lockItineraryReminder(itemID)
        defer { unlockItineraryReminder(itemID) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.itineraryItemNotificationID(itemID: itemID)]
        )
    }

    private func lockItineraryReminder(_ itemID: UUID) async {
        guard lockedItineraryReminderIDs.contains(itemID) else {
            lockedItineraryReminderIDs.insert(itemID)
            return
        }
        await withCheckedContinuation { continuation in
            itineraryReminderWaiters[itemID, default: []].append(continuation)
        }
    }

    private func unlockItineraryReminder(_ itemID: UUID) {
        guard var waiters = itineraryReminderWaiters[itemID], !waiters.isEmpty else {
            itineraryReminderWaiters.removeValue(forKey: itemID)
            lockedItineraryReminderIDs.remove(itemID)
            return
        }
        let next = waiters.removeFirst()
        itineraryReminderWaiters[itemID] = waiters.isEmpty ? nil : waiters
        next.resume()
    }

    func buildItineraryItemNotificationContent(
        item: TripItineraryItem,
        trip: PackingTrip
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.kind == .flight ? "Flight coming up" : "Coming up on \(trip.title)"
        content.body = item.title
        content.sound = .default
        content.categoryIdentifier = Self.itineraryReminderCategoryID
        content.userInfo = [
            "packingTripID": trip.id.uuidString,
            "itineraryItemID": item.id.uuidString,
            "householdID": trip.householdID.uuidString,
            "deepLink": Self.deepLink(
                path: "food/trips/\(trip.id.uuidString)/itinerary/\(item.id.uuidString)",
                profileID: nil
            )
        ]
        return content
    }

    func buildPackingTripNotificationContent(
        trip: PackingTrip,
        finalCheck: Bool
    ) -> UNMutableNotificationContent {
        buildPackingTripNotificationContent(
            snapshot: PackingTripReminderSnapshot(trip: trip),
            finalCheck: finalCheck
        )
    }

    func buildPackingTripNotificationContent(
        snapshot: PackingTripReminderSnapshot,
        finalCheck: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if snapshot.usesTargetedReminders {
            let count = snapshot.assignedRemainingCount
            let itemText = count == 1 ? "item" : "items"
            content.title = finalCheck ? "Your final packing check" : "Your packing reminder"
            content.body = "You have \(count) assigned \(itemText) left to pack for \(snapshot.title)."
        } else {
            content.title = finalCheck ? "Final packing check" : "Time to start packing"
            content.body = finalCheck
                ? "Review what is still unpacked for \(snapshot.title)."
                : "Open \(snapshot.title) and make progress on the shared packing list."
        }
        content.sound = .default
        content.categoryIdentifier = Self.packingTripReminderCategoryID
        var userInfo: [AnyHashable: Any] = [
            "packingTripID": snapshot.id.uuidString,
            "householdID": snapshot.householdID.uuidString,
            "deepLink": Self.deepLink(path: "food/trips/\(snapshot.id.uuidString)", profileID: nil)
        ]
        if let targetCaregiverName = snapshot.targetCaregiverName {
            userInfo["targetCaregiverName"] = targetCaregiverName
        }
        content.userInfo = userInfo
        return content
    }

    func scheduleRoutineReminder(routine: CareRoutine) async {
        await cancelRoutineReminder(routineID: routine.id)
        guard routine.reminderEnabled,
              let minutes = routine.reminderTimeMinutesAfterMidnight else {
            return
        }
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let request = UNNotificationRequest(
            identifier: Self.routineReminderNotificationID(routineID: routine.id),
            content: buildRoutineReminderNotificationContent(routine: routine),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelRoutineReminder(routineID: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.routineReminderNotificationID(routineID: routineID)]
        )
    }

    func buildMonthlyAgeGuideNotificationContent(
        guide: AgeGuide,
        babyName: String,
        profileID: UUID? = nil
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(babyName) is \(guide.ageLabel.lowercased()) old"
        content.body = "Read this month's guide and capture new milestones."
        content.sound = .default
        content.categoryIdentifier = Self.ageGuideCategoryID
        var userInfo: [String: Any] = [
            "ageGuideMonth": guide.ageMonth,
            "deepLink": Self.deepLink(path: "age-guide/\(guide.ageMonth)", profileID: profileID)
        ]
        if let profileID {
            userInfo["profileID"] = profileID.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    func buildRoutineReminderNotificationContent(
        routine: CareRoutine
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = routine.title
        content.body = "Open your routine when you are ready."
        content.sound = .default
        content.categoryIdentifier = Self.routineReminderCategoryID
        var userInfo: [String: Any] = [
            "routineID": routine.id.uuidString,
            "deepLink": Self.deepLink(path: "routines", profileID: routine.profileID)
        ]
        if let householdID = routine.householdID {
            userInfo["householdID"] = householdID.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    func buildFoodReminderNotificationContent(
        reminder: FoodReminder
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        switch reminder.type {
        case .todos:
            content.body = "Check your Home to-do list."
        case .shopping:
            content.body = "Open your shopping list before the next trip."
        case .mealPrep:
            content.body = "Check prepared meals and servings."
        case .returns:
            content.body = "Check return labels, packages, and drop-off timing."
        case .custom:
            content.body = "Food & Home reminder."
        }
        content.sound = .default
        content.categoryIdentifier = Self.foodReminderCategoryID
        let path: String
        if let todoListID = reminder.relatedTodoListID {
            path = "food/todos/\(todoListID.uuidString)"
        } else if let listID = reminder.relatedShoppingListID {
            path = "food/shopping/\(listID.uuidString)"
        } else if let mealPrepID = reminder.relatedMealPrepItemID {
            path = "food/meal-prep/\(mealPrepID.uuidString)"
        } else if let returnRequestID = reminder.relatedReturnRequestID {
            path = "food/returns/\(returnRequestID.uuidString)"
        } else if reminder.type == .mealPrep {
            path = "food/meal-prep"
        } else if reminder.type == .shopping {
            path = "food/shopping"
        } else if reminder.type == .todos {
            path = "food/todos"
        } else if reminder.type == .returns {
            path = "food/returns"
        } else {
            path = "food"
        }
        content.userInfo = [
            "foodReminderID": reminder.id.uuidString,
            "householdID": reminder.householdID.uuidString,
            "deepLink": Self.deepLink(path: path, profileID: nil)
        ]
        return content
    }

    func reconcileScheduledNotifications(
        context: ModelContext,
        profiles: [BabyProfile],
        events: [BabyEvent],
        predictionRecords: [SleepPredictionRecord],
        appointments: [DoctorAppointment],
        foodReminders: [FoodReminder],
        plannedSolidMeals: [PlannedSolidMeal],
        solidAllergenProgress: [SolidAllergenProgress],
        packingTrips: [PackingTrip],
        packingItems: [PackingItem],
        itineraryChoiceGroups: [TripItineraryChoiceGroup],
        itineraryItems: [TripItineraryItem],
        routines: [CareRoutine],
        ageGuideReadStates: [AgeGuideReadState]
    ) async {
        await refreshAuthorizationStatus()
        let allowed = authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral
        guard allowed else { return }

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let appointmentIDs = Set(appointments.filter {
            !$0.isCompleted && $0.remindersEnabled
        }.map { "appointment.\($0.id.uuidString)." })
        let foodIDs = Set(foodReminders.filter {
            $0.isEnabled && $0.dateTime > Date()
        }.map { Self.foodReminderNotificationID(reminderID: $0.id) })
        let solidMealIDs = Set(plannedSolidMeals.filter {
            $0.reminderEnabled && !$0.isCompleted &&
                $0.scheduledAt.addingTimeInterval(Double(-$0.reminderOffsetMinutes) * 60) > Date()
        }.map { Self.solidMealReminderNotificationID(planID: $0.id) })
        let solidAllergenIDs = Set(solidAllergenProgress.filter {
            $0.reminderEnabled &&
                $0.status != .suspectedReaction &&
                $0.status != .avoidPendingAdvice &&
                $0.nextExposureDueAt.map { $0 > Date() } == true
        }.map {
            Self.solidAllergenReminderNotificationID(
                profileID: $0.profileID,
                allergenID: $0.allergenID
            )
        })
        let routineIDs = Set(routines.filter {
            !$0.isArchived && $0.reminderEnabled
        }.map { Self.routineReminderNotificationID(routineID: $0.id) })
        let currentCaregiverName = CaregiverIdentityService.currentCaregiverName()
        let packingItemsByTripID = Dictionary(grouping: packingItems, by: \.tripID)
        let packingTripsByID = Dictionary(
            packingTrips.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let itineraryChoiceGroupsByID = Dictionary(
            itineraryChoiceGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let packingTripIDs = Set(packingTrips.flatMap { trip -> [String] in
            let snapshot = PackingTripReminderSnapshot(
                trip: trip,
                items: packingItemsByTripID[trip.id] ?? [],
                currentCaregiverName: currentCaregiverName
            )
            guard !snapshot.isArchived,
                  snapshot.isUpcoming,
                  snapshot.isEligibleForCurrentCaregiver else { return [] }
            return [
                trip.reminderDate.map { _ in Self.packingTripNotificationID(tripID: trip.id, kind: "start") },
                trip.finalCheckDate.map { _ in Self.packingTripNotificationID(tripID: trip.id, kind: "final") }
            ].compactMap { $0 }
        })
        let itineraryIDs = Set(itineraryItems.compactMap { item -> String? in
            guard item.reminderEnabled,
                  !item.isCompleted,
                  item.bookingStatus != .cancelled,
                  item.reminderDate.map({ $0 > Date() }) == true,
                  let trip = packingTripsByID[item.tripID],
                  !trip.isArchived,
                  trip.status == .upcoming else { return nil }
            if let assigned = item.assignedCaregiverName,
               !CaregiverIdentityService.namesMatch(assigned, currentCaregiverName) {
                return nil
            }
            if let choiceGroupID = item.choiceGroupID,
               itineraryChoiceGroupsByID[choiceGroupID]?.selectedItemID != item.id {
                return nil
            }
            return Self.itineraryItemNotificationID(itemID: item.id)
        })
        let orphaned = pending.map(\.identifier).filter { identifier in
            if identifier.hasPrefix("appointment.") {
                return !appointmentIDs.contains { identifier.hasPrefix($0) }
            }
            if identifier.hasPrefix("food.reminder.") {
                return !foodIDs.contains(identifier)
            }
            if identifier.hasPrefix("solids.meal.") {
                return !solidMealIDs.contains(identifier)
            }
            if identifier.hasPrefix("solids.allergen.") {
                return !solidAllergenIDs.contains(identifier)
            }
            if identifier.hasPrefix("routine.reminder.") {
                return !routineIDs.contains(identifier)
            }
            if identifier.hasPrefix("packing.trip.") {
                return !packingTripIDs.contains(identifier)
            }
            if identifier.hasPrefix("trip.itinerary.") {
                return !itineraryIDs.contains(identifier)
            }
            return false
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: orphaned
        )

        let predictionSettings = PredictionSettings(
            feedAdjustmentEnabled: Self.defaultBool("feedAdjustmentEnabled", fallback: true),
            nursingAdjustmentEnabled: Self.defaultBool("nursingAdjustmentEnabled", fallback: true),
            bedtimePredictionEnabled: Self.defaultBool("bedtimePredictionEnabled", fallback: true),
            customBaselineMinimum: Self.positiveDouble("customWakeMinimum"),
            customBaselineMaximum: Self.positiveDouble("customWakeMaximum")
        )
        if LittleWindowAlertSettings.current.enabled {
            for profile in profiles where !profile.isArchived && profile.profileType == .child {
                let scopedEvents = events.filter { $0.matchesProfile(profile.id) }
                let scopedRecords = predictionRecords.filter { $0.matchesProfile(profile.id) }
                let prediction = PredictionTuningService.currentPrediction(
                    profile: profile,
                    events: scopedEvents,
                    records: scopedRecords,
                    settings: predictionSettings
                )
                await rescheduleLittleWindowAlertIfNeeded(
                    prediction: prediction,
                    babyName: profile.name,
                    profileID: profile.id,
                    isSleeping: scopedEvents.contains {
                        $0.isSleepBlock && $0.isTimerRunning
                    }
                )
            }
        } else {
            await cancelAllPendingLittleWindowAlerts()
        }

        if UserDefaults.standard.bool(forKey: "sleepPressureAlertsEnabled") {
            for profile in profiles where !profile.isArchived && profile.profileType == .child {
                let scopedEvents = events.filter { $0.matchesProfile(profile.id) }
                let scopedRecords = predictionRecords.filter { $0.matchesProfile(profile.id) }
                await rescheduleSleepPressureAlertIfNeeded(
                    pressure: SleepPredictionEngine.sleepPressure(
                        profile: profile,
                        events: scopedEvents,
                        records: scopedRecords,
                        settings: predictionSettings
                    ),
                    babyName: profile.name,
                    profileID: profile.id,
                    enabled: true,
                    isSleeping: scopedEvents.contains {
                        $0.isSleepBlock && $0.isTimerRunning
                    }
                )
            }
        } else {
            await cancelAllPendingSleepPressureAlerts()
        }

        if UserDefaults.standard.object(forKey: "appointmentRemindersEnabled") == nil
            || UserDefaults.standard.bool(forKey: "appointmentRemindersEnabled") {
            for appointment in appointments where !appointment.isCompleted && appointment.remindersEnabled {
                let name = profiles.first { $0.id == appointment.profileID }?.name ?? "Baby"
                await rescheduleAppointmentReminders(
                    appointment: appointment,
                    babyName: name
                )
            }
        } else {
            for appointment in appointments {
                await cancelAppointmentReminders(appointmentID: appointment.id)
            }
        }

        for reminder in foodReminders {
            if reminder.isEnabled && reminder.dateTime > Date() {
                await scheduleFoodReminder(reminder: reminder)
            } else {
                await cancelFoodReminder(reminderID: reminder.id)
            }
        }
        for plan in plannedSolidMeals {
            await scheduleSolidMealReminder(plan: plan)
        }
        for progress in solidAllergenProgress {
            await scheduleSolidAllergenReminder(progress: progress)
        }
        for trip in packingTrips {
            await reschedulePackingTripReminders(
                trip: trip,
                items: packingItemsByTripID[trip.id] ?? [],
                currentCaregiverName: currentCaregiverName
            )
        }
        for item in itineraryItems {
            if let trip = packingTripsByID[item.tripID] {
                let choiceIsSelected: Bool
                if let choiceGroupID = item.choiceGroupID {
                    choiceIsSelected = itineraryChoiceGroupsByID[choiceGroupID]?.selectedItemID == item.id
                } else {
                    choiceIsSelected = true
                }
                await rescheduleItineraryItemReminder(
                    item: item,
                    trip: trip,
                    choiceIsSelected: choiceIsSelected,
                    authorizationAlreadyConfirmed: true,
                    currentCaregiverName: currentCaregiverName
                )
            } else {
                await cancelItineraryItemReminder(itemID: item.id)
            }
        }
        for routine in routines {
            if !routine.isArchived && routine.reminderEnabled {
                await scheduleRoutineReminder(routine: routine)
            } else {
                await cancelRoutineReminder(routineID: routine.id)
            }
        }

        if UserDefaults.standard.bool(forKey: "monthlyAgeGuideNotificationsEnabled") {
            let timing = MonthlyAgeGuideNotificationTiming(
                rawValue: UserDefaults.standard.string(
                    forKey: "monthlyAgeGuideNotificationTiming"
                ) ?? ""
            ) ?? .monthlyBirthday
            for profile in profiles where !profile.isArchived && profile.profileType == .child {
                await scheduleMonthlyAgeGuideNotification(
                    profile: profile,
                    readStates: ageGuideReadStates.filter { $0.matchesProfile(profile.id) },
                    context: context,
                    timing: timing
                )
            }
        } else {
            await cancelMonthlyAgeGuideNotifications()
        }
    }

    func showFamilySyncActivityNotification(
        _ notification: FamilySyncActivityNotification
    ) async {
        guard Self.familySyncActivityNotificationsEnabled(for: notification.category) else { return }
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = Self.familySyncActivityCategoryID
        content.userInfo = [
            "deepLink": Self.deepLink(path: notification.deepLinkPath, profileID: nil)
        ]
        let request = UNNotificationRequest(
            identifier: "family.sync.activity.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func showFamilySyncAccessEndedNotification(
        reason: FamilyShareInactiveReason
    ) async {
        let status = await getAuthorizationStatus()
        authorizationStatus = status
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let request = UNNotificationRequest(
            identifier: Self.familySyncAccessEndedNotificationID,
            content: buildFamilySyncAccessEndedNotificationContent(reason: reason),
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func buildFamilySyncAccessEndedNotificationContent(
        reason: FamilyShareInactiveReason
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reason.title
        content.body = reason.notificationBody
        content.sound = .default
        content.categoryIdentifier = Self.familySyncActivityCategoryID
        content.userInfo = [
            "deepLink": Self.deepLink(path: "settings/family-sync", profileID: nil)
        ]
        return content
    }

    nonisolated static func familySyncActivityNotificationsEnabled(
        for category: FamilySyncActivityNotificationCategory,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.object(forKey: "familySyncActivityNotificationsEnabled") == nil
                || defaults.bool(forKey: "familySyncActivityNotificationsEnabled") else {
            return false
        }
        switch category {
        case .general:
            return true
        case .homeTodo:
            return defaults.object(forKey: "familySyncHomeTodoNotificationsEnabled") == nil
                || defaults.bool(forKey: "familySyncHomeTodoNotificationsEnabled")
        case .trip:
            return defaults.object(forKey: "familySyncTripNotificationsEnabled") == nil
                || defaults.bool(forKey: "familySyncTripNotificationsEnabled")
        }
    }

    func buildNotificationContent(
        for prediction: SleepPrediction,
        babyName: String,
        profileID: UUID? = nil,
        leadMinutes: Int
    ) -> UNMutableNotificationContent {
        let copy = Self.notificationCopy(
            for: prediction,
            babyName: babyName,
            leadMinutes: leadMinutes
        )
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        var userInfo: [String: Any] = [
            "babyName": babyName,
            "predictionKind": prediction.predictionKind.rawValue,
            "windowStart": prediction.predictedWindowStart.timeIntervalSince1970,
            "windowEnd": prediction.predictedWindowEnd.timeIntervalSince1970,
            "deepLink": Self.deepLink(path: "prediction", profileID: profileID)
        ]
        if let profileID {
            userInfo["profileID"] = profileID.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    func buildSleepPressureNotificationContent(
        pressure: SleepPressure,
        targetBand: SleepPressureBand,
        babyName: String,
        profileID: UUID? = nil
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch targetBand {
        case .high:
            content.title = "Sleep pressure is high"
            content.body = "\(babyName) is past the usual ready range. A sleep window may be close."
        default:
            content.title = "Sleep pressure is ready"
            content.body = "\(babyName) is entering the usual ready range for sleep."
        }
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        var userInfo: [String: Any] = [
            "babyName": babyName,
            "sleepPressureBand": targetBand.rawValue,
            "deepLink": Self.deepLink(path: "prediction", profileID: profileID)
        ]
        if let score = pressure.score {
            userInfo["sleepPressureScore"] = Int(score.rounded())
        }
        if let profileID {
            userInfo["profileID"] = profileID.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    func handleNotificationAction(_ response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        if action == Self.snoozeActionID {
            let content = response.notification.request.content.mutableCopy()
                as? UNMutableNotificationContent
            guard let content else { return }
            let fireDate = Date().addingTimeInterval(10 * 60)
            let request = UNNotificationRequest(
                identifier: response.notification.request.identifier,
                content: content,
                trigger: Self.oneShotTrigger(at: fireDate)
            )
            try? await UNUserNotificationCenter.current().add(request)
            let profileID = (content.userInfo["profileID"] as? String)
                .flatMap(UUID.init(uuidString:))
            var state = state(profileID: profileID)
            state.lastScheduledAlertTime = fireDate
            state.skipReason = nil
            state.lastUpdatedAt = Date()
            updateState(state, profileID: profileID)
            return
        }

        if action == Self.openAppointmentActionID ||
            action == Self.completeAppointmentActionID ||
            action == Self.addVisitNotesActionID {
            if let id = response.notification.request.content.userInfo["appointmentID"] as? String {
                let profilePrefix = Self.profilePathPrefix(
                    from: response.notification.request.content.userInfo
                )
                let suffix = action == Self.addVisitNotesActionID ? "/notes" : ""
                DeepLinkRouter.shared.route(
                    URL(string: "littlewindows://\(profilePrefix)appointment/\(id)\(suffix)")!
                )
            } else {
                DeepLinkRouter.shared.route(URL(string: "littlewindows://appointments")!)
            }
        } else if response.notification.request.content.categoryIdentifier == Self.activeSleepPlanCategoryID {
            let profilePrefix = Self.profilePathPrefix(
                from: response.notification.request.content.userInfo
            )
            DeepLinkRouter.shared.route(URL(string: "littlewindows://\(profilePrefix)active-timer")!)
        } else if action == Self.openAgeGuideActionID ||
                    response.notification.request.content.categoryIdentifier == Self.ageGuideCategoryID {
            if let month = response.notification.request.content.userInfo["ageGuideMonth"] as? Int {
                let profilePrefix = Self.profilePathPrefix(
                    from: response.notification.request.content.userInfo
                )
                DeepLinkRouter.shared.route(URL(string: "littlewindows://\(profilePrefix)age-guide/\(month)")!)
            } else {
                DeepLinkRouter.shared.route(URL(string: "littlewindows://milestones")!)
            }
        } else if action == Self.openFoodActionID ||
                    response.notification.request.content.categoryIdentifier == Self.foodReminderCategoryID {
            if let deepLink = response.notification.request.content.userInfo["deepLink"] as? String,
               let url = URL(string: deepLink) {
                DeepLinkRouter.shared.route(url)
            } else {
                DeepLinkRouter.shared.route(URL(string: "littlewindows://food")!)
            }
        } else if action == Self.openPackingTripActionID ||
                    response.notification.request.content.categoryIdentifier == Self.packingTripReminderCategoryID ||
                    response.notification.request.content.categoryIdentifier == Self.itineraryReminderCategoryID {
            if let deepLink = response.notification.request.content.userInfo["deepLink"] as? String,
               let url = URL(string: deepLink) {
                DeepLinkRouter.shared.route(url)
            } else {
                DeepLinkRouter.shared.route(URL(string: "littlewindows://food/trips")!)
            }
        } else if action == Self.openFamilySyncActivityActionID ||
                    response.notification.request.content.categoryIdentifier == Self.familySyncActivityCategoryID {
            if let deepLink = response.notification.request.content.userInfo["deepLink"] as? String,
               let url = URL(string: deepLink) {
                DeepLinkRouter.shared.route(url)
            } else {
                DeepLinkRouter.shared.route(URL(string: "littlewindows://history")!)
            }
        } else if action == Self.startSleepActionID {
            let profilePrefix = Self.profilePathPrefix(
                from: response.notification.request.content.userInfo
            )
            DeepLinkRouter.shared.route(URL(string: "littlewindows://\(profilePrefix)quick-log/sleep")!)
        } else {
            let profilePrefix = Self.profilePathPrefix(
                from: response.notification.request.content.userInfo
            )
            DeepLinkRouter.shared.route(URL(string: "littlewindows://\(profilePrefix)prediction")!)
        }
    }

    func statusText(
        prediction: SleepPrediction?,
        profileID: UUID? = nil,
        settings: LittleWindowAlertSettings = .current,
        isSleeping: Bool = false,
        now: Date = Date()
    ) -> String {
        let decision = Self.schedulingDecision(
            prediction: prediction,
            settings: settings,
            isSleeping: isSleeping,
            now: now
        )
        switch decision {
        case .schedule:
            if authorizationStatus == .denied {
                return "Notifications disabled in iOS Settings"
            }
            let storedState = state(profileID: profileID)
            if storedState.lastScheduledAlertTime != nil,
               storedState.skipReason == nil {
                return settings.leadMinutes == 0
                    ? "Alert scheduled at window start"
                    : "Alert scheduled \(settings.leadMinutes) minutes before"
            }
            return settings.enabled ? "Ready to schedule alert" : "Alerts off"
        case .skip(let reason):
            switch reason {
            case .alertsOff: return "Alerts off"
            case .noPrediction: return "Waiting for the next prediction"
            case .sleeping: return "Sleeping now - next alert paused"
            case .napAlertsOff: return "Nap alerts are off"
            case .bedtimeAlertsOff: return "Bedtime alerts are off"
            case .belowConfidenceThreshold:
                return "\(prediction?.confidenceLabel.displayName ?? "Low") confidence - no alert scheduled"
            case .alertTimePassed:
                guard let prediction else { return "Waiting for the next prediction" }
                let phase = PredictionTiming.phase(
                    windowStart: prediction.predictedWindowStart,
                    windowEnd: prediction.predictedWindowEnd,
                    now: now
                )
                switch phase {
                case .upcoming:
                    return "Lead time passed - window starts soon"
                case .inWindow:
                    return "You're in the likely sleep window"
                case .overdue:
                    return "Likely sleep window has passed"
                }
            case .permissionDenied: return "Notifications disabled in iOS Settings"
            }
        }
    }

    static func alertFireDate(
        prediction: SleepPrediction,
        leadMinutes: Int
    ) -> Date {
        prediction.predictedWindowStart.addingTimeInterval(Double(-leadMinutes) * 60)
    }

    private static func oneShotTrigger(
        at fireDate: Date,
        now: Date = Date()
    ) -> UNTimeIntervalNotificationTrigger {
        UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )
    }

    private static func timeString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func schedulingDecision(
        prediction: SleepPrediction?,
        settings: LittleWindowAlertSettings,
        isSleeping: Bool = false,
        now: Date = Date()
    ) -> LittleWindowAlertDecision {
        guard settings.enabled else { return .skip(.alertsOff) }
        guard let prediction else { return .skip(.noPrediction) }
        guard !isSleeping else { return .skip(.sleeping) }
        if prediction.predictionKind == .nap, !settings.napAlertsEnabled {
            return .skip(.napAlertsOff)
        }
        if prediction.predictionKind == .bedtime, !settings.bedtimeAlertsEnabled {
            return .skip(.bedtimeAlertsOff)
        }
        guard settings.confidenceThreshold.includes(prediction.confidenceLabel) else {
            return .skip(.belowConfidenceThreshold)
        }
        let fireDate = alertFireDate(
            prediction: prediction,
            leadMinutes: settings.leadMinutes
        )
        guard fireDate > now else { return .skip(.alertTimePassed) }
        return .schedule(fireDate)
    }

    static func sleepPressureAlertDecision(
        pressure: SleepPressure?,
        enabled: Bool,
        isSleeping: Bool = false,
        now: Date = Date()
    ) -> SleepPressureAlertDecision {
        guard enabled else { return .skip(.alertsOff) }
        guard let pressure else { return .skip(.noPressure) }
        guard !isSleeping else { return .skip(.sleeping) }
        guard pressure.isActionable else { return .skip(.learning) }

        let fireDate: Date?
        let targetBand: SleepPressureBand
        switch pressure.band {
        case .learning:
            return .skip(.learning)
        case .low, .building:
            fireDate = pressure.readyAt
            targetBand = .ready
        case .ready:
            fireDate = pressure.highAt
            targetBand = .high
        case .high:
            return .skip(.alreadyHigh)
        }

        guard let fireDate, fireDate > now else {
            return .skip(.alertTimePassed)
        }
        return .schedule(fireDate, targetBand)
    }

    static func sleepPressureStatusText(
        pressure: SleepPressure?,
        enabled: Bool,
        isSleeping: Bool = false,
        authorizationStatus: UNAuthorizationStatus = .authorized,
        now: Date = Date()
    ) -> String {
        let decision = sleepPressureAlertDecision(
            pressure: pressure,
            enabled: enabled,
            isSleeping: isSleeping,
            now: now
        )
        switch decision {
        case .schedule(let date, let band):
            if authorizationStatus == .denied {
                return "Notifications disabled in iOS Settings"
            }
            return "\(band.displayName) alert at \(DateFormatting.time.string(from: date))"
        case .skip(let reason):
            switch reason {
            case .alertsOff: return "Pressure alerts off"
            case .noPressure: return "Waiting for sleep pressure"
            case .learning: return "Learning rhythm"
            case .sleeping: return "Sleeping now - pressure alert paused"
            case .alreadyHigh: return "Pressure is already high"
            case .alertTimePassed: return "Ready range has already started"
            case .permissionDenied: return "Notifications disabled in iOS Settings"
            }
        }
    }

    static func shouldKeepExistingSchedule(
        state: LittleWindowNotificationState,
        prediction: SleepPrediction,
        fireDate: Date,
        settings: LittleWindowAlertSettings
    ) -> Bool {
        guard state.skipReason == nil,
              state.settingsSignature == settings.signature,
              state.lastScheduledKindRawValue == prediction.predictionKind.rawValue,
              let previousStart = state.lastScheduledPredictionStart,
              let previousFireDate = state.lastScheduledAlertTime else {
            return false
        }
        return abs(previousStart.timeIntervalSince(prediction.predictedStart)) < 5 * 60
            && abs(previousFireDate.timeIntervalSince(fireDate)) < 5 * 60
    }

    static func notificationCopy(
        for prediction: SleepPrediction,
        babyName: String,
        leadMinutes: Int
    ) -> LittleWindowNotificationCopy {
        let window = DateFormatting.window(
            start: prediction.predictedWindowStart,
            end: prediction.predictedWindowEnd
        )
        if leadMinutes == 0 {
            return LittleWindowNotificationCopy(
                title: "Little Window now",
                body: "\(babyName)'s predicted \(prediction.predictionKind.rawValue) window is starting now."
            )
        }
        switch prediction.predictionKind {
        case .nap:
            return LittleWindowNotificationCopy(
                title: "Nap window soon",
                body: "\(babyName)'s Little Window is estimated for \(window)."
            )
        case .bedtime:
            return LittleWindowNotificationCopy(
                title: "Bedtime window soon",
                body: "\(babyName)'s bedtime window may be coming up around \(DateFormatting.time.string(from: prediction.predictedStart))."
            )
        }
    }

    private static func predictionID(for prediction: SleepPrediction) -> String {
        "\(prediction.predictionKind.rawValue)-\(Int(prediction.predictedStart.timeIntervalSince1970))"
    }

    static func appointmentNotificationID(
        appointmentID: UUID,
        leadTime: AppointmentReminderLeadTime,
        profileID: UUID? = nil
    ) -> String {
        if let profileID {
            return "appointment.\(appointmentID.uuidString).profile.\(profileID.uuidString).\(leadTime.rawValue)"
        }
        return "appointment.\(appointmentID.uuidString).\(leadTime.rawValue)"
    }

    static func monthlyAgeGuideFireDate(
        reachedDate: Date,
        timing: MonthlyAgeGuideNotificationTiming,
        calendar: Calendar = .current
    ) -> Date {
        let base: Date
        switch timing {
        case .monthlyBirthday:
            base = reachedDate
        case .oneDayAfter:
            base = calendar.date(byAdding: .day, value: 1, to: reachedDate) ?? reachedDate
        case .firstWeekendAfter:
            var candidate = reachedDate
            while !calendar.isDateInWeekend(candidate) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            base = candidate
        }
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: base
        ) ?? base
    }

    static func monthlyAgeGuideNotificationID(guideID: String, profileID: UUID? = nil) -> String {
        if let profileID {
            return "ageguide.\(profileID.uuidString).\(guideID)"
        }
        return "ageguide.\(guideID)"
    }

    static func foodReminderNotificationID(reminderID: UUID) -> String {
        "food.reminder.\(reminderID.uuidString)"
    }

    static func solidMealReminderNotificationID(planID: UUID) -> String {
        "solids.meal.\(planID.uuidString)"
    }

    static func solidAllergenReminderNotificationID(profileID: UUID, allergenID: String) -> String {
        "solids.allergen.\(profileID.uuidString).\(allergenID)"
    }

    static func routineReminderNotificationID(routineID: UUID) -> String {
        "routine.reminder.\(routineID.uuidString)"
    }

    static func packingTripNotificationID(tripID: UUID, kind: String) -> String {
        "packing.trip.\(tripID.uuidString).\(kind)"
    }

    static func itineraryItemNotificationID(itemID: UUID) -> String {
        "trip.itinerary.\(itemID.uuidString)"
    }

    static func activeSleepPlanWakeNotificationID(profileID: UUID? = nil) -> String {
        scopedNotificationID(activeSleepPlanWakeNotificationBaseID, profileID: profileID)
    }

    static func sleepPressureNotificationID(profileID: UUID? = nil) -> String {
        scopedNotificationID(sleepPressureNotificationBaseID, profileID: profileID)
    }

    static func scopedNotificationID(_ identifier: String, profileID: UUID?) -> String {
        guard let profileID else { return identifier }
        return "profile.\(profileID.uuidString).\(identifier)"
    }

    static func littleWindowNotificationIDs(profileID: UUID?) -> [String] {
        allNotificationIDs.map { scopedNotificationID($0, profileID: profileID) }
    }

    static func deepLink(path: String, profileID: UUID?) -> String {
        guard let profileID else { return "littlewindows://\(path)" }
        return "littlewindows://profile/\(profileID.uuidString)/\(path)"
    }

    private static func profilePathPrefix(from userInfo: [AnyHashable: Any]) -> String {
        guard let profileID = userInfo["profileID"] as? String else { return "" }
        return "profile/\(profileID)/"
    }

    private static func defaultBool(_ key: String, fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? fallback
            : UserDefaults.standard.bool(forKey: key)
    }

    private static func positiveDouble(_ key: String) -> Double? {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : nil
    }

    private func state(profileID: UUID?) -> LittleWindowNotificationState {
        statesByProfile[Self.stateStorageKey(profileID: profileID)] ?? .empty
    }

    private func updateState(
        _ state: LittleWindowNotificationState,
        profileID: UUID? = nil
    ) {
        statesByProfile[Self.stateStorageKey(profileID: profileID)] = state
        notificationState = state
        if let data = try? JSONEncoder().encode(statesByProfile) {
            UserDefaults.standard.set(data, forKey: Self.statesByProfileKey)
        }
    }

    private static func stateStorageKey(profileID: UUID?) -> String {
        profileID?.uuidString ?? unscopedStateKey
    }

    private static func loadState() -> LittleWindowNotificationState {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(
                LittleWindowNotificationState.self,
                from: data
              ) else {
            return .empty
        }
        return state
    }

    private static func loadStatesByProfile() -> [String: LittleWindowNotificationState] {
        if let data = UserDefaults.standard.data(forKey: statesByProfileKey),
           let states = try? JSONDecoder().decode(
            [String: LittleWindowNotificationState].self,
            from: data
           ) {
            return states
        }
        let legacy = loadState()
        return legacy == .empty ? [:] : [unscopedStateKey: legacy]
    }
}

@MainActor
enum SystemIntegrationReconciler {
    static let reconciliationRequestedNotification = Notification.Name(
        "SystemIntegrationReconciler.reconciliationRequested"
    )
    private static let lastCompletedAtKey = "systemIntegrations.lastReconciledAt"
    private static var reconciliationTask: Task<Void, Never>?

    static func requestReconciliation() {
        NotificationCenter.default.post(name: reconciliationRequestedNotification, object: nil)
    }

    static func reconcileIfNeeded(
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) async {
        guard needsForegroundReconciliation(
            lastCompletedAt: defaults.object(forKey: lastCompletedAtKey) as? Date,
            lastLocalSaveAt: PersistenceService.lastLocalSaveAt(defaults: defaults),
            now: now
        ) else {
            return
        }
        await reconcile(context: context, defaults: defaults)
    }

    static func reconcile(context: ModelContext) async {
        await reconcile(context: context, defaults: .standard)
    }

    static func needsForegroundReconciliation(
        lastCompletedAt: Date?,
        lastLocalSaveAt: Date?,
        now: Date,
        calendar: Calendar = .current,
        maximumAge: TimeInterval = 15 * 60
    ) -> Bool {
        guard let lastCompletedAt else { return true }
        if let lastLocalSaveAt, lastLocalSaveAt > lastCompletedAt {
            return true
        }
        if !calendar.isDate(lastCompletedAt, inSameDayAs: now) {
            return true
        }
        return now.timeIntervalSince(lastCompletedAt) >= maximumAge
    }

    private static func reconcile(
        context: ModelContext,
        defaults: UserDefaults
    ) async {
        if let reconciliationTask {
            await reconciliationTask.value
            return
        }
        let task = Task { @MainActor in
            await performReconciliation(context: context)
            defaults.set(Date(), forKey: lastCompletedAtKey)
        }
        reconciliationTask = task
        await task.value
        reconciliationTask = nil
    }

    private static func performReconciliation(context: ModelContext) async {
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }
        let profiles = (try? context.fetch(FetchDescriptor<BabyProfile>())) ?? []
        let profile = ProfileService.shared.ensureSelection(in: profiles)
        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let activeProfileIDs = profiles
            .filter { !$0.isArchived }
            .map(\.id)
        let childProfileIDs = profiles
            .filter { !$0.isArchived && $0.profileType == .child }
            .map(\.id)
        let events = await recentEvents(
            profileIDs: activeProfileIDs,
            recentCutoff: recentCutoff,
            context: context
        )
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }
        let predictionRecords = await recentPredictionRecords(
            profileIDs: childProfileIDs,
            recentCutoff: recentCutoff,
            context: context
        )
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }

        let appointments = (try? context.fetch(FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate { !$0.isCompleted && $0.remindersEnabled }
        ))) ?? []
        let now = Date()
        let foodReminders = (try? context.fetch(FetchDescriptor<FoodReminder>(
            predicate: #Predicate { $0.isEnabled && $0.dateTime > now }
        ))) ?? []
        let plannedSolidMeals = (try? context.fetch(FetchDescriptor<PlannedSolidMeal>(
            predicate: #Predicate { $0.reminderEnabled && $0.completedEventID == nil }
        ))) ?? []
        let solidAllergenProgress = (try? context.fetch(
            FetchDescriptor<SolidAllergenProgress>(
                predicate: #Predicate { $0.reminderEnabled }
            )
        )) ?? []
        let selectedProfileID = profile?.id
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let solidsProfileStates = (try? context.fetch(FetchDescriptor<SolidsProfileState>(
            predicate: #Predicate { $0.profileID == selectedProfileID }
        ))) ?? []
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }

        let upcomingStatus = PackingTripStatus.upcoming.rawValue
        let packingTrips = (try? context.fetch(FetchDescriptor<PackingTrip>(
            predicate: #Predicate {
                !$0.isArchived
                    && $0.statusRawValue == upcomingStatus
            }
        ))) ?? []
        let upcomingTripIDs = packingTrips.map(\.id)
        let packingItems = upcomingTripIDs.isEmpty ? [] :
            ((try? context.fetch(FetchDescriptor<PackingItem>(
                predicate: #Predicate { upcomingTripIDs.contains($0.tripID) }
            ))) ?? [])
        let itineraryItems = (try? context.fetch(FetchDescriptor<TripItineraryItem>(
            predicate: #Predicate { $0.reminderEnabled && !$0.isCompleted }
        ))) ?? []
        let itineraryChoiceGroupIDs = Array(Set(itineraryItems.compactMap(\.choiceGroupID)))
        let itineraryChoiceGroups = itineraryChoiceGroupIDs.isEmpty ? [] :
            ((try? context.fetch(FetchDescriptor<TripItineraryChoiceGroup>(
                predicate: #Predicate { itineraryChoiceGroupIDs.contains($0.id) }
            ))) ?? [])
        let routines = (try? context.fetch(FetchDescriptor<CareRoutine>(
            predicate: #Predicate { $0.reminderEnabled }
        ))) ?? []
        let ageGuideReadStates: [AgeGuideReadState]
        if UserDefaults.standard.bool(forKey: "monthlyAgeGuideNotificationsEnabled") {
            ageGuideReadStates = (try? context.fetch(
                FetchDescriptor<AgeGuideReadState>()
            )) ?? []
        } else {
            ageGuideReadStates = []
        }
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }

        let scopedEvents = events.filter { $0.matchesProfile(profile?.id) }
        let scopedRecords = predictionRecords.filter { $0.matchesProfile(profile?.id) }
        let prediction = PredictionTuningService.currentPrediction(
            profile: profile,
            events: scopedEvents,
            records: scopedRecords,
            settings: PredictionSettings(
                feedAdjustmentEnabled: UserDefaults.standard.object(
                    forKey: "feedAdjustmentEnabled"
                ) == nil || UserDefaults.standard.bool(forKey: "feedAdjustmentEnabled"),
                nursingAdjustmentEnabled: UserDefaults.standard.object(
                    forKey: "nursingAdjustmentEnabled"
                ) == nil || UserDefaults.standard.bool(forKey: "nursingAdjustmentEnabled"),
                bedtimePredictionEnabled: UserDefaults.standard.object(
                    forKey: "bedtimePredictionEnabled"
                ) == nil || UserDefaults.standard.bool(forKey: "bedtimePredictionEnabled"),
                customBaselineMinimum: positiveDouble("customWakeMinimum"),
                customBaselineMaximum: positiveDouble("customWakeMaximum")
            )
        )
        WidgetSnapshotService.refresh(
            profile: profile,
            events: scopedEvents,
            prediction: prediction,
            solidsState: solidsProfileStates.first { $0.profileID == profile?.id }
        )
        await Task.yield()
        WidgetSnapshotService.refreshFood(context: context)
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }
        await LiveActivityManager.shared.synchronize(profile: profile, events: scopedEvents)
        await AppInteractionMonitor.waitUntilIdle()
        guard !Task.isCancelled else { return }
        await NotificationManager.shared.reconcileScheduledNotifications(
            context: context,
            profiles: profiles,
            events: events,
            predictionRecords: predictionRecords,
            appointments: appointments,
            foodReminders: foodReminders,
            plannedSolidMeals: plannedSolidMeals,
            solidAllergenProgress: solidAllergenProgress,
            packingTrips: packingTrips,
            packingItems: packingItems,
            itineraryChoiceGroups: itineraryChoiceGroups,
            itineraryItems: itineraryItems,
            routines: routines,
            ageGuideReadStates: ageGuideReadStates
        )
    }

    private static func recentEvents(
        profileIDs: [UUID],
        recentCutoff: Date,
        context: ModelContext
    ) async -> [BabyEvent] {
        var result: [BabyEvent] = []
        let pageSize = 200
        let maximumPerProfile = 900
        for profileID in profileIDs {
            var offset = 0
            while offset < maximumPerProfile && !Task.isCancelled {
                // Foreground reconciliation is maintenance work. Re-establish a
                // full interaction-free window between pages so a brief pause
                // while scrolling or changing tabs cannot let it resume and
                // monopolize the main actor again.
                await AppInteractionMonitor.waitUntilIdle()
                guard !Task.isCancelled else { return result }
                var descriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.profileID == profileID
                            && (event.startDate >= recentCutoff || event.endDate == nil)
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
                )
                descriptor.fetchLimit = min(pageSize, maximumPerProfile - offset)
                descriptor.fetchOffset = offset
                let page = (try? context.fetch(descriptor)) ?? []
                result.append(contentsOf: page)
                guard page.count == descriptor.fetchLimit else { break }
                offset += page.count
                await Task.yield()
            }
        }
        return result
    }

    private static func recentPredictionRecords(
        profileIDs: [UUID],
        recentCutoff: Date,
        context: ModelContext
    ) async -> [SleepPredictionRecord] {
        var result: [SleepPredictionRecord] = []
        let pageSize = 120
        let maximumPerProfile = 240
        for profileID in profileIDs {
            var offset = 0
            while offset < maximumPerProfile && !Task.isCancelled {
                await AppInteractionMonitor.waitUntilIdle()
                guard !Task.isCancelled else { return result }
                var descriptor = FetchDescriptor<SleepPredictionRecord>(
                    predicate: #Predicate<SleepPredictionRecord> { record in
                        record.profileID == profileID
                            && (record.generatedAt >= recentCutoff
                                || record.actualSleepEventID == nil)
                    },
                    sortBy: [
                        SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)
                    ]
                )
                descriptor.fetchLimit = min(pageSize, maximumPerProfile - offset)
                descriptor.fetchOffset = offset
                let page = (try? context.fetch(descriptor)) ?? []
                result.append(contentsOf: page)
                guard page.count == descriptor.fetchLimit else { break }
                offset += page.count
                await Task.yield()
            }
        }
        return result
    }

    private static func positiveDouble(_ key: String) -> Double? {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : nil
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationManager.shared.handleNotificationAction(response)
    }
}
