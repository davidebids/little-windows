import Combine
import Foundation
import SwiftData
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
    static let ageGuideCategoryID = "MONTHLY_AGE_GUIDE"
    static let openAgeGuideActionID = "OPEN_AGE_GUIDE"
    static let foodReminderCategoryID = "FOOD_HOME_REMINDER"
    static let openFoodActionID = "OPEN_FOOD_HOME"

    private static let stateKey = "littleWindowNotificationState"
    private static let allNotificationIDs = [
        nextNotificationID,
        prewindowNotificationID,
        windowStartNotificationID
    ]

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationState: LittleWindowNotificationState

    private override init() {
        notificationState = Self.loadState()
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func configure() async {
        registerNotificationCategories()
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
        UNUserNotificationCenter.current().setNotificationCategories([
            category,
            appointmentCategory,
            ageGuideCategory,
            foodCategory
        ])
    }

    func schedule(
        prediction: SleepPrediction?,
        babyName: String,
        profileID: UUID? = nil,
        leadMinutes: Int,
        enabled: Bool
    ) async {
        var settings = LittleWindowAlertSettings.current
        settings.enabled = enabled
        settings.leadMinutes = leadMinutes
        await rescheduleLittleWindowAlertIfNeeded(
            prediction: prediction,
            babyName: babyName,
            profileID: profileID,
            settings: settings
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
                )
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
                )
            )
            return
        }

        if Self.shouldKeepExistingSchedule(
            state: notificationState,
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
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
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
                )
            )
        } catch {
            updateState(
                LittleWindowNotificationState(
                    skipReason: .alertsOff,
                    lastUpdatedAt: now
                )
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
            updateState(.empty)
        }
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
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
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
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
            )
            try? await center.add(request)
        }
        appointment.lastScheduledAt = Date()
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

    func buildAppointmentNotificationContent(
        appointment: DoctorAppointment,
        babyName: String = "Baby",
        profileID: UUID? = nil,
        leadTime: AppointmentReminderLeadTime
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let time = DateFormatting.time.string(from: appointment.startDate)
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

    func scheduleMonthlyAgeGuideNotification(
        profile: BabyProfile,
        readStates: [AgeGuideReadState],
        context: ModelContext,
        timing: MonthlyAgeGuideNotificationTiming,
        now: Date = Date()
    ) async {
        await cancelMonthlyAgeGuideNotifications()
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

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: candidate.1
        )
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
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)

        let state = readStates.first { $0.guideID == candidate.0.id } ?? AgeGuideReadState(
            profileID: profile.id,
            guideID: candidate.0.id
        )
        if state.modelContext == nil {
            context.insert(state)
        }
        state.notificationSentAt = now
        state.updatedAt = now
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    func cancelMonthlyAgeGuideNotifications() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("ageguide.") }
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
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.dateTime
        )
        let request = UNNotificationRequest(
            identifier: Self.foodReminderNotificationID(reminderID: reminder.id),
            content: buildFoodReminderNotificationContent(reminder: reminder),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelFoodReminder(reminderID: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.foodReminderNotificationID(reminderID: reminderID)]
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

    func buildFoodReminderNotificationContent(
        reminder: FoodReminder
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        switch reminder.type {
        case .shopping:
            content.body = "Open your shopping list before the next trip."
        case .mealPrep:
            content.body = "Check prepared meals and servings."
        case .custom:
            content.body = "Food & Home reminder."
        }
        content.sound = .default
        content.categoryIdentifier = Self.foodReminderCategoryID
        let path: String
        if let listID = reminder.relatedShoppingListID {
            path = "food/shopping/\(listID.uuidString)"
        } else if let mealPrepID = reminder.relatedMealPrepItemID {
            path = "food/meal-prep/\(mealPrepID.uuidString)"
        } else if reminder.type == .mealPrep {
            path = "food/meal-prep"
        } else if reminder.type == .shopping {
            path = "food/shopping"
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

    func handleNotificationAction(_ response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        if action == Self.snoozeActionID {
            let content = response.notification.request.content.mutableCopy()
                as? UNMutableNotificationContent
            guard let content else { return }
            let fireDate = Date().addingTimeInterval(10 * 60)
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: response.notification.request.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
            )
            try? await UNUserNotificationCenter.current().add(request)
            var state = notificationState
            state.lastScheduledAlertTime = fireDate
            state.skipReason = nil
            state.lastUpdatedAt = Date()
            updateState(state)
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
            if notificationState.lastScheduledAlertTime != nil,
               notificationState.skipReason == nil {
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

    private func updateState(_ state: LittleWindowNotificationState) {
        notificationState = state
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
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
