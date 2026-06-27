import Foundation
import SwiftData

struct CareRoutineTemplate: Identifiable, Equatable {
    var id: CareRoutineTemplateKind { kind }
    var kind: CareRoutineTemplateKind
    var scope: CareRoutineScope
    var profileType: CareProfileType?
    var title: String
    var notes: String
    var iconName: String
    var tintName: String
    var steps: [CareRoutineStepTemplate]
}

struct CareRoutineStepTemplate: Equatable {
    var title: String
    var notes: String?
    var action: CareRoutineStepAction
    var eventType: EventType?
    var activityType: ActivityType?
    var nursingSide: NursingSide?
    var sleepKind: SleepKind?
}

struct CareRoutineStepInput: Identifiable, Equatable {
    var id = UUID()
    var title: String = ""
    var notes: String = ""
    var action: CareRoutineStepAction = .checklist
    var eventType: EventType = .custom
    var activityType: ActivityType = .custom
    var nursingSide: NursingSide = .left
    var sleepKind: SleepKind = .nap
}

struct CareRoutineInput: Equatable {
    var title: String = ""
    var notes: String = ""
    var scope: CareRoutineScope = .profile
    var iconName: String = "checklist"
    var tintName: String = "indigo"
    var reminderEnabled: Bool = false
    var reminderTimeMinutesAfterMidnight: Int? = 18 * 60
    var steps: [CareRoutineStepInput] = [CareRoutineStepInput()]
}

extension CareRoutineStepInput {
    init(step: CareRoutineStep) {
        self.init(
            id: step.id,
            title: step.title,
            notes: step.notes ?? "",
            action: step.action,
            eventType: step.eventType ?? .custom,
            activityType: step.activityType ?? .custom,
            nursingSide: step.nursingSide ?? .left,
            sleepKind: step.sleepKind ?? .nap
        )
    }
}

extension CareRoutineInput {
    init(routine: CareRoutine, steps: [CareRoutineStep]) {
        self.init(
            title: routine.title,
            notes: routine.notes ?? "",
            scope: routine.scope,
            iconName: routine.iconName,
            tintName: routine.tintName,
            reminderEnabled: routine.reminderEnabled,
            reminderTimeMinutesAfterMidnight: routine.reminderTimeMinutesAfterMidnight ?? 18 * 60,
            steps: steps.map(CareRoutineStepInput.init(step:))
        )
        if self.steps.isEmpty {
            self.steps = [CareRoutineStepInput()]
        }
    }
}

@MainActor
enum CareRoutineService {
    static let defaultReminderMinutes = 18 * 60

    static func templates(for profileType: CareProfileType?) -> [CareRoutineTemplate] {
        var values = householdTemplates
        if let profileType {
            values.append(contentsOf: profileTemplates(for: profileType))
        }
        return values
    }

    static func visibleRoutines(
        routines: [CareRoutine],
        profileID: UUID?,
        householdID: UUID?
    ) -> [CareRoutine] {
        routines
            .filter { !$0.isArchived }
            .filter { routine in
                switch routine.scope {
                case .profile:
                    return routine.profileID == profileID
                case .household:
                    return householdID == nil || routine.householdID == householdID
                }
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func activeRun(
        for routine: CareRoutine,
        runs: [CareRoutineRun]
    ) -> CareRoutineRun? {
        runs
            .filter { $0.routineID == routine.id && $0.state == .active }
            .max { $0.startedAt < $1.startedAt }
    }

    static func steps(
        for routine: CareRoutine,
        steps: [CareRoutineStep]
    ) -> [CareRoutineStep] {
        steps
            .filter { $0.routineID == routine.id }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func createRoutine(
        from template: CareRoutineTemplate,
        profileID: UUID?,
        householdID: UUID?,
        existingRoutines: [CareRoutine],
        context: ModelContext
    ) -> CareRoutine {
        let nextOrder = (existingRoutines.map(\.sortOrder).max() ?? -1) + 1
        let routine = CareRoutine(
            scope: template.scope,
            profileID: template.scope == .profile ? profileID : nil,
            householdID: template.scope == .household ? householdID : nil,
            title: template.title,
            notes: template.notes,
            iconName: template.iconName,
            tintName: template.tintName,
            templateKind: template.kind,
            sortOrder: nextOrder
        )
        context.insert(routine)
        for (index, step) in template.steps.enumerated() {
            context.insert(CareRoutineStep(
                routineID: routine.id,
                title: step.title,
                notes: step.notes,
                action: step.action,
                eventType: step.eventType,
                activityType: step.activityType,
                nursingSide: step.nursingSide,
                sleepKind: step.sleepKind,
                sortOrder: index
            ))
        }
        save(context)
        return routine
    }

    static func createRoutine(
        title: String,
        notes: String = "",
        scope: CareRoutineScope,
        iconName: String = "checklist",
        tintName: String = "indigo",
        reminderEnabled: Bool = false,
        reminderTimeMinutesAfterMidnight: Int? = nil,
        steps: [CareRoutineStepInput] = [],
        profileID: UUID?,
        householdID: UUID?,
        existingRoutines: [CareRoutine],
        context: ModelContext
    ) -> CareRoutine? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let validSteps = normalizedSteps(steps)
        guard !validSteps.isEmpty else { return nil }
        let nextOrder = (existingRoutines.map(\.sortOrder).max() ?? -1) + 1
        let routine = CareRoutine(
            scope: scope,
            profileID: scope == .profile ? profileID : nil,
            householdID: scope == .household ? householdID : nil,
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            iconName: iconName,
            tintName: tintName,
            sortOrder: nextOrder,
            reminderEnabled: reminderEnabled,
            reminderTimeMinutesAfterMidnight: reminderEnabled
                ? (reminderTimeMinutesAfterMidnight ?? defaultReminderMinutes)
                : nil
        )
        context.insert(routine)
        for (index, step) in validSteps.enumerated() {
            let eventType = eventType(for: step)
            context.insert(CareRoutineStep(
                routineID: routine.id,
                title: step.title,
                notes: step.notes.nilIfEmpty,
                action: step.action,
                eventType: eventType,
                activityType: eventType == .activity ? step.activityType : nil,
                nursingSide: eventType == .nursing ? step.nursingSide : nil,
                sleepKind: eventType == .sleep ? step.sleepKind : nil,
                sortOrder: index
            ))
        }
        save(context)
        return routine
    }

    static func updateRoutine(
        _ routine: CareRoutine,
        input: CareRoutineInput,
        profileID: UUID?,
        householdID: UUID?,
        existingSteps: [CareRoutineStep],
        context: ModelContext
    ) -> Bool {
        let trimmed = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let validSteps = normalizedSteps(input.steps)
        guard !validSteps.isEmpty else { return false }

        routine.scope = input.scope
        routine.profileID = input.scope == .profile ? profileID : nil
        routine.householdID = input.scope == .household ? householdID : nil
        routine.title = trimmed
        routine.notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        routine.iconName = input.iconName
        routine.tintName = input.tintName
        routine.templateKind = nil
        routine.reminderEnabled = input.reminderEnabled
        routine.reminderTimeMinutesAfterMidnight = input.reminderEnabled
            ? (input.reminderTimeMinutesAfterMidnight ?? defaultReminderMinutes)
            : nil
        routine.updatedAt = Date()

        let routineSteps = existingSteps.filter { $0.routineID == routine.id }
        let stepsByID = Dictionary(uniqueKeysWithValues: routineSteps.map { ($0.id, $0) })
        let retainedIDs = Set(validSteps.map(\.id))

        for step in routineSteps where !retainedIDs.contains(step.id) {
            context.delete(step)
        }

        for (index, inputStep) in validSteps.enumerated() {
            let eventType = eventType(for: inputStep)
            let step = stepsByID[inputStep.id] ?? CareRoutineStep(
                id: inputStep.id,
                routineID: routine.id,
                title: inputStep.title,
                sortOrder: index
            )
            if stepsByID[inputStep.id] == nil {
                context.insert(step)
            }
            step.routineID = routine.id
            step.title = inputStep.title
            step.notes = inputStep.notes.nilIfEmpty
            step.action = inputStep.action
            step.eventType = eventType
            step.activityType = eventType == .activity ? inputStep.activityType : nil
            step.nursingSide = eventType == .nursing ? inputStep.nursingSide : nil
            step.sleepKind = eventType == .sleep ? inputStep.sleepKind : nil
            step.sortOrder = index
            step.updatedAt = Date()
        }

        save(context)
        return true
    }

    static func duplicateRoutine(
        _ routine: CareRoutine,
        steps: [CareRoutineStep],
        existingRoutines: [CareRoutine],
        context: ModelContext
    ) -> CareRoutine {
        let nextOrder = (existingRoutines.map(\.sortOrder).max() ?? -1) + 1
        let copy = CareRoutine(
            scope: routine.scope,
            profileID: routine.profileID,
            householdID: routine.householdID,
            title: uniqueCopyTitle(for: routine.title, existingRoutines: existingRoutines),
            notes: routine.notes,
            iconName: routine.iconName,
            tintName: routine.tintName,
            sortOrder: nextOrder
        )
        context.insert(copy)

        for (index, step) in CareRoutineService.steps(for: routine, steps: steps).enumerated() {
            context.insert(CareRoutineStep(
                routineID: copy.id,
                title: step.title,
                notes: step.notes,
                action: step.action,
                eventType: step.eventType,
                activityType: step.activityType,
                nursingSide: step.nursingSide,
                sleepKind: step.sleepKind,
                sortOrder: index
            ))
        }

        save(context)
        return copy
    }

    static func reorderRoutines(
        _ routines: [CareRoutine],
        from source: IndexSet,
        to destination: Int,
        context: ModelContext
    ) {
        var ordered = routines
        var adjustedDestination = destination

        for sourceIndex in source.sorted(by: >) {
            let item = ordered.remove(at: sourceIndex)
            if sourceIndex < adjustedDestination {
                adjustedDestination -= 1
            }
            ordered.insert(item, at: min(adjustedDestination, ordered.count))
        }

        for (index, routine) in ordered.enumerated() {
            routine.sortOrder = index
            routine.updatedAt = Date()
        }
        save(context)
    }

    static func updateRoutine(
        _ routine: CareRoutine,
        title: String,
        notes: String,
        reminderEnabled: Bool,
        reminderTimeMinutesAfterMidnight: Int?,
        context: ModelContext
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        routine.title = trimmed
        routine.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        routine.reminderEnabled = reminderEnabled
        routine.reminderTimeMinutesAfterMidnight = reminderTimeMinutesAfterMidnight
        routine.updatedAt = Date()
        save(context)
    }

    static func addStep(
        to routine: CareRoutine,
        title: String,
        action: CareRoutineStepAction,
        eventType: EventType?,
        activityType: ActivityType? = nil,
        nursingSide: NursingSide? = nil,
        sleepKind: SleepKind? = nil,
        existingSteps: [CareRoutineStep],
        context: ModelContext
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (existingSteps.map(\.sortOrder).max() ?? -1) + 1
        context.insert(CareRoutineStep(
            routineID: routine.id,
            title: trimmed,
            action: action,
            eventType: eventType,
            activityType: activityType,
            nursingSide: nursingSide,
            sleepKind: sleepKind,
            sortOrder: nextOrder
        ))
        routine.updatedAt = Date()
        save(context)
    }

    static func archive(_ routine: CareRoutine, context: ModelContext) {
        routine.isArchived = true
        routine.updatedAt = Date()
        save(context)
    }

    static func startRun(
        routine: CareRoutine,
        activeRuns: [CareRoutineRun],
        context: ModelContext
    ) -> CareRoutineRun {
        if let existing = activeRun(for: routine, runs: activeRuns) {
            return existing
        }
        let run = CareRoutineRun(
            routineID: routine.id,
            profileID: routine.profileID,
            householdID: routine.householdID
        )
        routine.lastStartedAt = run.startedAt
        routine.updatedAt = Date()
        context.insert(run)
        save(context)
        return run
    }

    static func completeStep(
        _ step: CareRoutineStep,
        in run: CareRoutineRun,
        routine: CareRoutine,
        allSteps: [CareRoutineStep],
        context: ModelContext
    ) {
        var completed = run.completedStepIDs
        if !completed.contains(step.id) {
            completed.append(step.id)
        }
        run.completedStepIDs = completed
        run.skippedStepIDs = run.skippedStepIDs.filter { $0 != step.id }
        run.updatedAt = Date()
        finishIfDone(run, routine: routine, allSteps: allSteps)
        save(context)
    }

    static func skipStep(
        _ step: CareRoutineStep,
        in run: CareRoutineRun,
        routine: CareRoutine,
        allSteps: [CareRoutineStep],
        context: ModelContext
    ) {
        var skipped = run.skippedStepIDs
        if !skipped.contains(step.id) {
            skipped.append(step.id)
        }
        run.skippedStepIDs = skipped
        run.updatedAt = Date()
        finishIfDone(run, routine: routine, allSteps: allSteps)
        save(context)
    }

    static func finishRun(_ run: CareRoutineRun, routine: CareRoutine, context: ModelContext) {
        let now = Date()
        run.state = .completed
        run.completedAt = now
        run.updatedAt = now
        routine.lastCompletedAt = now
        routine.updatedAt = now
        save(context)
    }

    static func cancelRun(_ run: CareRoutineRun, context: ModelContext) {
        let now = Date()
        run.state = .cancelled
        run.cancelledAt = now
        run.updatedAt = now
        save(context)
    }

    private static func finishIfDone(
        _ run: CareRoutineRun,
        routine: CareRoutine,
        allSteps: [CareRoutineStep]
    ) {
        let ids = Set(allSteps.filter { $0.routineID == routine.id }.map(\.id))
        let resolved = Set(run.completedStepIDs + run.skippedStepIDs)
        guard !ids.isEmpty, ids.isSubset(of: resolved) else { return }
        let now = Date()
        run.state = .completed
        run.completedAt = now
        routine.lastCompletedAt = now
        routine.updatedAt = now
    }

    private static func save(_ context: ModelContext) {
        try? context.save()
        PersistenceService.recordLocalSave()
    }

    private static func normalizedSteps(_ steps: [CareRoutineStepInput]) -> [CareRoutineStepInput] {
        steps
            .map { input -> CareRoutineStepInput in
                var copy = input
                copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.notes = copy.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }
            .filter { !$0.title.isEmpty }
    }

    private static func uniqueCopyTitle(
        for title: String,
        existingRoutines: [CareRoutine]
    ) -> String {
        let existingTitles = Set(existingRoutines.map { $0.title.lowercased() })
        let base = "\(title) Copy"
        guard existingTitles.contains(base.lowercased()) else { return base }

        var suffix = 2
        while existingTitles.contains("\(base) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private static func eventType(for step: CareRoutineStepInput) -> EventType? {
        switch step.action {
        case .logEvent:
            return step.eventType
        case .startTimer:
            return step.eventType.supportsTimer ? step.eventType : .custom
        case .checklist,
             .openFoodHome,
             .openFoodQuickAdd,
             .openShoppingList,
             .openInventory,
             .openMealPrep,
             .openReports,
             .openMilestones,
             .openAppointments,
             .openAgeGuide,
             .openPuppyGuide,
             .openNightLight,
             .openSettings,
             .note:
            return nil
        }
    }
}

private extension CareRoutineService {
    static func profileTemplates(for profileType: CareProfileType) -> [CareRoutineTemplate] {
        switch profileType {
        case .child:
            return [
                CareRoutineTemplate(
                    kind: .childBedtime,
                    scope: .profile,
                    profileType: .child,
                    title: "Bedtime routine",
                    notes: "A steady wind-down for evenings and naps.",
                    iconName: "moon.stars.fill",
                    tintName: "indigo",
                    steps: [
                        CareRoutineStepTemplate(title: "Dim the room", notes: nil, action: .openNightLight),
                        CareRoutineStepTemplate(title: "Fresh diaper", notes: nil, action: .logEvent, eventType: .diaper),
                        CareRoutineStepTemplate(title: "Feed or nursing", notes: nil, action: .logEvent, eventType: .feed),
                        CareRoutineStepTemplate(title: "Start sleep timer", notes: nil, action: .startTimer, eventType: .sleep, sleepKind: .nightSleep)
                    ]
                ),
                CareRoutineTemplate(
                    kind: .childMorning,
                    scope: .profile,
                    profileType: .child,
                    title: "Morning care",
                    notes: "A quick reset for the first care window.",
                    iconName: "sun.max.fill",
                    tintName: "orange",
                    steps: [
                        CareRoutineStepTemplate(title: "Log diaper", notes: nil, action: .logEvent, eventType: .diaper),
                        CareRoutineStepTemplate(title: "Log feed", notes: nil, action: .logEvent, eventType: .feed),
                        CareRoutineStepTemplate(title: "Add any notes", notes: nil, action: .note)
                    ]
                ),
                medicineTemplate(scope: .profile, profileType: .child)
            ]
        case .dog:
            return [
                CareRoutineTemplate(
                    kind: .dogAfterWalk,
                    scope: .profile,
                    profileType: .dog,
                    title: "After walk",
                    notes: "Close the loop after a walk.",
                    iconName: "figure.walk",
                    tintName: "green",
                    steps: [
                        CareRoutineStepTemplate(title: "Start or review walk", notes: nil, action: .startTimer, eventType: .walk),
                        CareRoutineStepTemplate(title: "Offer water", notes: nil, action: .logEvent, eventType: .water),
                        CareRoutineStepTemplate(title: "Log potty", notes: nil, action: .logEvent, eventType: .potty)
                    ]
                ),
                CareRoutineTemplate(
                    kind: .dogEvening,
                    scope: .profile,
                    profileType: .dog,
                    title: "Dog evening care",
                    notes: "A simple evening care pass.",
                    iconName: "pawprint.fill",
                    tintName: "teal",
                    steps: [
                        CareRoutineStepTemplate(title: "Log food", notes: nil, action: .logEvent, eventType: .food),
                        CareRoutineStepTemplate(title: "Log water", notes: nil, action: .logEvent, eventType: .water),
                        CareRoutineStepTemplate(title: "Grooming check", notes: nil, action: .logEvent, eventType: .grooming)
                    ]
                ),
                medicineTemplate(scope: .profile, profileType: .dog)
            ]
        }
    }

    static var householdTemplates: [CareRoutineTemplate] {
        [
            CareRoutineTemplate(
                kind: .householdGroceryReset,
                scope: .household,
                profileType: nil,
                title: "Grocery reset",
                notes: "Review the kitchen and refresh the shopping list.",
                iconName: "cart.fill",
                tintName: "orange",
                steps: [
                    CareRoutineStepTemplate(title: "Open Food & Home", notes: nil, action: .openFoodHome),
                    CareRoutineStepTemplate(title: "Check pantry staples", notes: nil, action: .checklist),
                    CareRoutineStepTemplate(title: "Review meal prep", notes: nil, action: .checklist)
                ]
            ),
            CareRoutineTemplate(
                kind: .householdDaycarePrep,
                scope: .household,
                profileType: nil,
                title: "Daycare prep",
                notes: "Pack the usual items before leaving home.",
                iconName: "backpack.fill",
                tintName: "mint",
                steps: [
                    CareRoutineStepTemplate(title: "Pack bottles or food", notes: nil, action: .checklist),
                    CareRoutineStepTemplate(title: "Pack diapers and wipes", notes: nil, action: .checklist),
                    CareRoutineStepTemplate(title: "Add a caregiver note", notes: nil, action: .note)
                ]
            )
        ]
    }

    static func medicineTemplate(
        scope: CareRoutineScope,
        profileType: CareProfileType
    ) -> CareRoutineTemplate {
        CareRoutineTemplate(
            kind: .medicineCourse,
            scope: scope,
            profileType: profileType,
            title: "Medicine course",
            notes: "A repeatable check for medicine routines.",
            iconName: "cross.case.fill",
            tintName: "red",
            steps: [
                CareRoutineStepTemplate(title: "Confirm dose instructions", notes: nil, action: .checklist),
                CareRoutineStepTemplate(title: "Log medicine", notes: nil, action: .logEvent, eventType: .medicine),
                CareRoutineStepTemplate(title: "Add any reaction notes", notes: nil, action: .note)
            ]
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
