import SwiftData
import SwiftUI

struct CareRoutineRunRoute: Identifiable {
    let id = UUID()
    var routineID: UUID
    var runID: UUID
}

struct PendingRoutineStepCompletion {
    var routineID: UUID
    var runID: UUID
    var stepID: UUID
}

struct CareRoutinesTodayCard: View {
    @State private var routinePendingDelete: CareRoutine?

    var routines: [CareRoutine]
    var steps: [CareRoutineStep]
    var runs: [CareRoutineRun]
    var templates: [CareRoutineTemplate]
    var addTemplate: (CareRoutineTemplate) -> Void
    var startRoutine: (CareRoutine) -> Void
    var archiveRoutine: (CareRoutine) -> Void
    var cancelRun: (CareRoutineRun) -> Void
    var openRun: (CareRoutine, CareRoutineRun) -> Void
    var manage: () -> Void

    var body: some View {
        Section {
            if routines.isEmpty {
                RoutineTemplateStarterCard(
                    templates: templates,
                    addTemplate: addTemplate,
                    manage: manage
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(routines.prefix(3)) { routine in
                    let routineSteps = CareRoutineService.steps(for: routine, steps: steps)
                    let run = CareRoutineService.activeRun(for: routine, runs: runs)
                    let latestRun = CareRoutineService.latestRun(for: routine, runs: runs)
                    CareRoutineTodayRow(
                        routine: routine,
                        steps: routineSteps,
                        activeRun: run,
                        latestRun: latestRun,
                        start: { startRoutine(routine) },
                        resume: { run.map { openRun(routine, $0) } }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        if let run {
                            Button {
                                cancelRun(run)
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle.fill")
                            }
                            .tint(.orange)
                        }

                        Button(role: .destructive) {
                            routinePendingDelete = routine
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
                }

                if routines.count > 3 || !templates.isEmpty {
                    Button(action: manage) {
                        Label("Manage routines", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            AppSectionHeader(title: "Routines", subtitle: routines.isEmpty ? "Templates" : "\(routines.count) saved")
        }
        .appActionSheet(
            isPresented: Binding(
                get: { routinePendingDelete != nil },
                set: { if !$0 { routinePendingDelete = nil } }
            ),
            title: "Delete routine?",
            message: routinePendingDelete.map { "This removes \($0.title) from Today. Completed history stays in backups and reports." },
            systemImage: "trash.fill",
            tint: .red,
            options: deleteOptions
        )
    }

    private var deleteOptions: [AppActionSheetOption] {
        guard let routine = routinePendingDelete else { return [] }
        return [
            AppActionSheetOption(
                title: "Delete \(routine.title)",
                subtitle: "Remove it from Today",
                systemImage: "trash.fill",
                role: .destructive
            ) {
                archiveRoutine(routine)
                routinePendingDelete = nil
            }
        ]
    }
}

private struct RoutineTemplateStarterCard: View {
    var templates: [CareRoutineTemplate]
    var addTemplate: (CareRoutineTemplate) -> Void
    var manage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add a routine")
                        .font(.headline)
                    Text("Start from a template or build your own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !templates.isEmpty {
                templateButtons
            }

            RoutineBrowseButton(action: manage)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(AppTheme.accent.opacity(0.055))
        }
        .appSurface()
    }

    private var templateButtons: some View {
        VStack(spacing: 8) {
            ForEach(templates.prefix(3)) { template in
                Button {
                    addTemplate(template)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: template.iconName)
                            .foregroundStyle(color(named: template.tintName))
                            .frame(width: 26, height: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(template.scope.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.line, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RoutineBrowseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                Text("Browse templates and build custom")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent.opacity(0.75))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(AppTheme.accent.opacity(0.16), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse templates and build custom routines")
    }
}

private struct CareRoutineTodayRow: View {
    var routine: CareRoutine
    var steps: [CareRoutineStep]
    var activeRun: CareRoutineRun?
    var latestRun: CareRoutineRun?
    var start: () -> Void
    var resume: () -> Void

    private var tint: Color {
        color(named: routine.tintName)
    }

    private var completedCount: Int {
        activeRun?.completedStepIDs.count ?? 0
    }

    private var skippedCount: Int {
        activeRun?.skippedStepIDs.count ?? 0
    }

    private var resolvedCount: Int {
        min(completedCount + skippedCount, steps.count)
    }

    private var progressText: String {
        guard activeRun != nil else {
            return "\(steps.count) step\(steps.count == 1 ? "" : "s")"
        }
        return "\(completedCount)/\(steps.count) done"
    }

    private var nextStep: CareRoutineStep? {
        guard let activeRun else {
            return steps.first
        }
        let resolvedIDs = Set(activeRun.completedStepIDs + activeRun.skippedStepIDs)
        return steps.first { !resolvedIDs.contains($0.id) }
    }

    private var detailText: String {
        if activeRun != nil {
            if let nextStep {
                return "Next: \(nextStep.title)"
            }
            return "Ready to finish"
        }

        if let lastCompletedAt = routine.lastCompletedAt {
            if Calendar.current.isDateInToday(lastCompletedAt) {
                return "Completed today at \(DateFormatting.time.string(from: lastCompletedAt))"
            }
            return "Completed \(DateFormatting.day.string(from: lastCompletedAt))"
        }

        return routine.scope.displayName
    }

    private var collaborationText: String? {
        if let activeRun,
           let name = activeRun.startedByCaregiverName,
           !name.isEmpty {
            return "Started by \(name)"
        }

        guard let latestRun,
              latestRun.state == .completed,
              let completedAt = latestRun.completedAt,
              Calendar.current.isDateInToday(completedAt),
              let name = latestRun.completedByCaregiverName,
              !name.isEmpty else {
            return nil
        }

        return "Finished by \(name) at \(DateFormatting.time.string(from: completedAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: routine.iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(routine.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if activeRun != nil {
                            RoutineStatusPill(title: "Active", systemImage: "bolt.fill", color: .green)
                        }
                    }

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let collaborationText {
                        Label(collaborationText, systemImage: "person.2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activeRun == nil ? .secondary : tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.10), in: Capsule())
            }

            ProgressView(value: Double(resolvedCount), total: Double(max(steps.count, 1)))
                .tint(tint)
                .accessibilityLabel("\(routine.title) progress")
                .accessibilityValue(progressText)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    metadataLabels
                    Spacer(minLength: 8)
                    startButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    metadataLabels
                    startButton
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(tint.opacity(activeRun == nil ? 0.045 : 0.075))
        }
        .appSurface()
    }

    private var metadataLabels: some View {
        HStack(spacing: 8) {
            Label(routine.scope.displayName, systemImage: routine.scope == .household ? "house.fill" : "person.crop.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if routine.reminderEnabled {
                Label("Reminder", systemImage: "bell.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startButton: some View {
        RoutineStartButton(
            title: activeRun == nil ? "Start" : "Resume",
            systemImage: activeRun == nil ? "play.fill" : "arrow.clockwise",
            tint: tint,
            accessibilityLabel: "\(activeRun == nil ? "Start" : "Resume") \(routine.title)",
            action: activeRun == nil ? start : resume
        )
    }
}

private struct RoutineStartButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.caption.weight(.bold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(tint.gradient, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RoutineStatusPill: View {
    var title: String
    var systemImage: String
    var color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }
}

private struct CareRoutineCompactRow: View {
    var routine: CareRoutine
    var steps: [CareRoutineStep]
    var activeRun: CareRoutineRun?
    var start: () -> Void
    var resume: () -> Void

    private var progressText: String {
        guard let activeRun else {
            return "\(steps.count) step\(steps.count == 1 ? "" : "s")"
        }
        let completed = activeRun.completedStepIDs.count
        return "\(completed)/\(steps.count) done"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: routine.iconName)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color(named: routine.tintName).gradient, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(activeRun == nil ? "Start" : "Resume") {
                activeRun == nil ? start() : resume()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct CareRoutineManagerView: View {
    var profileType: CareProfileType?
    var routines: [CareRoutine]
    var steps: [CareRoutineStep]
    var runs: [CareRoutineRun]
    var templates: [CareRoutineTemplate]
    var addTemplate: (CareRoutineTemplate) -> Void
    var createRoutine: (CareRoutineInput) -> Void
    var updateRoutine: (CareRoutine, CareRoutineInput) -> Void
    var duplicateRoutine: (CareRoutine) -> Void
    var moveRoutines: (IndexSet, Int) -> Void
    var startRoutine: (CareRoutine) -> Void
    var archiveRoutine: (CareRoutine) -> Void
    var toggleReminder: (CareRoutine) -> Void
    var openRun: (CareRoutine, CareRoutineRun) -> Void

    @State private var showingRoutineBuilder = false
    @State private var routineToEdit: CareRoutine?
    @State private var routinePendingDelete: CareRoutine?

    var body: some View {
        List {
            Section {
                Button {
                    showingRoutineBuilder = true
                } label: {
                    Label("Build a routine", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section {
                ForEach(templates) { template in
                    Button {
                        addTemplate(template)
                    } label: {
                        TemplateRow(template: template)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                AppSectionHeader(title: "Templates")
            }

            Section {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No saved routines",
                        systemImage: "checklist",
                        description: Text("Add a template to start using routines from Today.")
                    )
                } else {
                    ForEach(routines) { routine in
                        let activeRun = CareRoutineService.activeRun(for: routine, runs: runs)
                        Button {
                            if let activeRun {
                                openRun(routine, activeRun)
                            } else {
                                startRoutine(routine)
                            }
                        } label: {
                            CareRoutineCompactRow(
                                routine: routine,
                                steps: CareRoutineService.steps(for: routine, steps: steps),
                                activeRun: activeRun,
                                start: { startRoutine(routine) },
                                resume: { activeRun.map { openRun(routine, $0) } }
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                if let activeRun {
                                    openRun(routine, activeRun)
                                } else {
                                    startRoutine(routine)
                                }
                            } label: {
                                Label(activeRun == nil ? "Start" : "Resume", systemImage: "play.fill")
                            }
                            Button {
                                routineToEdit = routine
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                duplicateRoutine(routine)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button {
                                toggleReminder(routine)
                            } label: {
                                Label(
                                    routine.reminderEnabled ? "Reminder Off" : "Remind Daily",
                                    systemImage: routine.reminderEnabled ? "bell.slash.fill" : "bell.fill"
                                )
                            }
                            Button(role: .destructive) {
                                routinePendingDelete = routine
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions {
                            Button {
                                routineToEdit = routine
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button {
                                duplicateRoutine(routine)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.green)

                            Button {
                                toggleReminder(routine)
                            } label: {
                                Label(
                                    routine.reminderEnabled ? "Reminder Off" : "Remind Daily",
                                    systemImage: routine.reminderEnabled ? "bell.slash.fill" : "bell.fill"
                                )
                            }
                            .tint(.indigo)

                            Button(role: .destructive) {
                                routinePendingDelete = routine
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                    .onMove(perform: moveRoutines)
                }
            } header: {
                AppSectionHeader(title: "Saved")
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRoutineBuilder = true
                } label: {
                    Label("New Routine", systemImage: "plus")
                }
            }
        }
        .appActionSheet(
            isPresented: Binding(
                get: { routinePendingDelete != nil },
                set: { if !$0 { routinePendingDelete = nil } }
            ),
            title: "Delete routine?",
            message: routinePendingDelete.map { "This removes \($0.title) from Today. Completed history stays in backups and reports." },
            systemImage: "trash.fill",
            tint: .red,
            options: deleteOptions
        )
        .sheet(isPresented: $showingRoutineBuilder) {
            NavigationStack {
                CareRoutineBuilderView(
                    navigationTitle: "New Routine",
                    saveTitle: "Save",
                    profileType: profileType,
                    initialInput: CareRoutineInput()
                ) { input in
                    createRoutine(input)
                    showingRoutineBuilder = false
                }
            }
        }
        .sheet(item: $routineToEdit) { routine in
            NavigationStack {
                CareRoutineBuilderView(
                    navigationTitle: "Edit Routine",
                    saveTitle: "Done",
                    profileType: profileType,
                    initialInput: CareRoutineInput(
                        routine: routine,
                        steps: CareRoutineService.steps(for: routine, steps: steps)
                    )
                ) { input in
                    updateRoutine(routine, input)
                    routineToEdit = nil
                }
            }
        }
    }

    private var deleteOptions: [AppActionSheetOption] {
        guard let routine = routinePendingDelete else { return [] }
        return [
            AppActionSheetOption(
                title: "Delete \(routine.title)",
                subtitle: "Remove it from Today",
                systemImage: "trash.fill",
                role: .destructive
            ) {
                archiveRoutine(routine)
                routinePendingDelete = nil
            }
        ]
    }
}

private struct CareRoutineBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    var navigationTitle: String
    var saveTitle: String
    var profileType: CareProfileType?
    var initialInput: CareRoutineInput
    var create: (CareRoutineInput) -> Void

    @State private var input: CareRoutineInput

    init(
        navigationTitle: String,
        saveTitle: String,
        profileType: CareProfileType?,
        initialInput: CareRoutineInput,
        create: @escaping (CareRoutineInput) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.saveTitle = saveTitle
        self.profileType = profileType
        self.initialInput = initialInput
        self.create = create
        _input = State(initialValue: initialInput)
    }

    private let iconOptions = [
        "checklist",
        "moon.stars.fill",
        "sun.max.fill",
        "cross.case.fill",
        "cart.fill",
        "backpack.fill",
        "pawprint.fill",
        "figure.walk",
        "fork.knife",
        "lightbulb.fill"
    ]

    private let tintOptions = ["indigo", "orange", "green", "teal", "red", "mint", "pink"]

    private var eventTypes: [EventType] {
        profileType.map(EventType.cases(for:)) ?? EventType.allCases
    }

    private var canSave: Bool {
        !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && input.steps.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        List {
            Section {
                TextField("Routine name", text: $input.title)
                TextField("Notes", text: $input.notes, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Scope", selection: $input.scope) {
                    ForEach(CareRoutineScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                Picker("Icon", selection: $input.iconName) {
                    ForEach(iconOptions, id: \.self) { iconName in
                        Label(iconName.accessibilityLabelFromSymbolName, systemImage: iconName)
                            .tag(iconName)
                    }
                }
                Picker("Color", selection: $input.tintName) {
                    ForEach(tintOptions, id: \.self) { tintName in
                        Label(tintName.capitalized, systemImage: "circle.fill")
                            .foregroundStyle(color(named: tintName))
                            .tag(tintName)
                    }
                }
                Toggle("Daily Reminder", isOn: $input.reminderEnabled)
                if input.reminderEnabled {
                    DatePicker(
                        "Reminder Time",
                        selection: Binding(
                            get: { date(for: input.reminderTimeMinutesAfterMidnight) },
                            set: { input.reminderTimeMinutesAfterMidnight = minutesAfterMidnight(for: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                AppSectionHeader(title: "Details")
            }

            Section {
                ForEach($input.steps) { $step in
                    RoutineStepBuilderRow(step: $step, eventTypes: eventTypes)
                }
                .onDelete { offsets in
                    input.steps.remove(atOffsets: offsets)
                    if input.steps.isEmpty {
                        input.steps.append(CareRoutineStepInput())
                    }
                }
                .onMove { source, destination in
                    input.steps.move(fromOffsets: source, toOffset: destination)
                }

                Button {
                    input.steps.append(CareRoutineStepInput())
                } label: {
                    Label("Add Step", systemImage: "plus.circle.fill")
                }
            } header: {
                AppSectionHeader(title: "Steps")
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(saveTitle) {
                    create(input)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
    }

    private func date(for minutesAfterMidnight: Int?) -> Date {
        let minutes = minutesAfterMidnight ?? 18 * 60
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? Date()
    }

    private func minutesAfterMidnight(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 18) * 60 + (components.minute ?? 0)
    }
}

private struct RoutineStepBuilderRow: View {
    @Binding var step: CareRoutineStepInput
    var eventTypes: [EventType]

    private var actionSections: [RoutineActionSection] {
        var navigationActions: [CareRoutineStepAction] = [
            .openFoodHome,
            .openFoodQuickAdd,
            .openShoppingList,
            .openInventory,
            .openMealPrep,
            .openReports,
            .openMilestones,
            .openAppointments,
            .openNightLight,
            .openSettings
        ]
        if eventTypes.contains(.sleep) {
            let index = navigationActions.firstIndex(of: .openNightLight) ?? navigationActions.endIndex
            navigationActions.insert(.openAgeGuide, at: index)
        }
        if eventTypes.contains(.walk) {
            let index = navigationActions.firstIndex(of: .openNightLight) ?? navigationActions.endIndex
            navigationActions.insert(.openPuppyGuide, at: index)
        }
        return [
            RoutineActionSection(title: "Routine", actions: [.checklist, .note]),
            RoutineActionSection(title: "Care Logging", actions: [.logEvent, .startTimer]),
            RoutineActionSection(title: "Open App Areas", actions: navigationActions)
        ]
    }

    private var timerEventTypes: [EventType] {
        eventTypes.filter(\.supportsTimer)
    }

    private var selectedEventTypes: [EventType] {
        switch step.action {
        case .startTimer:
            return timerEventTypes.isEmpty ? [.custom] : timerEventTypes
        case .logEvent:
            return eventTypes
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
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Step name", text: $step.title)
            Picker("Action", selection: $step.action) {
                ForEach(actionSections) { section in
                    Section(section.title) {
                        ForEach(section.actions) { action in
                            Label(action.displayName, systemImage: action.systemImage).tag(action)
                        }
                    }
                }
            }
            .onChange(of: step.action) {
                normalizeEventType()
            }

            if step.action == .logEvent || step.action == .startTimer {
                Picker(step.action == .startTimer ? "Timer" : "Event", selection: $step.eventType) {
                    ForEach(selectedEventTypes) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                }
                .onAppear(perform: normalizeEventType)
                .onChange(of: step.eventType) {
                    normalizeEventType()
                }

                if step.eventType == .sleep {
                    Picker("Sleep", selection: $step.sleepKind) {
                        ForEach(SleepKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }

                if step.eventType == .nursing {
                    Picker("Side", selection: $step.nursingSide) {
                        ForEach(NursingSide.allCases) { side in
                            Text(side.displayName).tag(side)
                        }
                    }
                }

                if step.eventType == .activity {
                    Picker("Activity", selection: $step.activityType) {
                        ForEach(ActivityType.allCases) { activity in
                            Text(activity.displayName).tag(activity)
                        }
                    }
                }
            }

            TextField("Step notes", text: $step.notes, axis: .vertical)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }

    private func normalizeEventType() {
        guard !selectedEventTypes.isEmpty else { return }
        if !selectedEventTypes.contains(step.eventType) {
            step.eventType = selectedEventTypes.first ?? .custom
        }
    }
}

private struct RoutineActionSection: Identifiable {
    var title: String
    var actions: [CareRoutineStepAction]

    var id: String { title }
}

private struct TemplateRow: View {
    var template: CareRoutineTemplate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.iconName)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color(named: template.tintName).gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(template.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(AppTheme.accent)
        }
    }
}

struct CareRoutineRunView: View {
    var routine: CareRoutine
    var steps: [CareRoutineStep]
    var run: CareRoutineRun
    var perform: (CareRoutineStep) -> Void
    var skip: (CareRoutineStep) -> Void
    var finish: () -> Void
    var cancel: () -> Void

    private var completedCount: Int {
        steps.filter { run.isCompleted(stepID: $0.id) }.count
    }

    private var runActorText: String? {
        switch run.state {
        case .active:
            guard let name = run.startedByCaregiverName, !name.isEmpty else { return nil }
            return "Started by \(name) at \(DateFormatting.time.string(from: run.startedAt))"
        case .completed:
            guard let completedAt = run.completedAt else { return nil }
            if let name = run.completedByCaregiverName, !name.isEmpty {
                return "Finished by \(name) at \(DateFormatting.time.string(from: completedAt))"
            }
            return "Finished at \(DateFormatting.time.string(from: completedAt))"
        case .cancelled:
            guard let cancelledAt = run.cancelledAt else { return nil }
            if let name = run.cancelledByCaregiverName, !name.isEmpty {
                return "Cancelled by \(name) at \(DateFormatting.time.string(from: cancelledAt))"
            }
            return "Cancelled at \(DateFormatting.time.string(from: cancelledAt))"
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(routine.title, systemImage: routine.iconName)
                        .font(.title3.bold())
                    if let runActorText {
                        Label(runActorText, systemImage: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completedCount), total: Double(max(steps.count, 1)))
                        .accessibilityLabel("\(routine.title) progress")
                        .accessibilityValue("\(completedCount) of \(steps.count) steps completed")
                    Text("\(completedCount) of \(steps.count) steps completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(steps) { step in
                    StepRunRow(
                        step: step,
                        isCompleted: run.isCompleted(stepID: step.id),
                        isSkipped: run.isSkipped(stepID: step.id),
                        resolutionRecord: run.resolutionRecord(for: step.id),
                        perform: { perform(step) },
                        skip: { skip(step) }
                    )
                }
            } header: {
                AppSectionHeader(title: "Steps")
            }
        }
        .navigationTitle("Routine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", role: .destructive, action: cancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish", action: finish)
                    .fontWeight(.semibold)
            }
        }
    }
}

private struct StepRunRow: View {
    var step: CareRoutineStep
    var isCompleted: Bool
    var isSkipped: Bool
    var resolutionRecord: CareRoutineStepResolutionRecord?
    var perform: () -> Void
    var skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                    Text(actionDetailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let resolutionText {
                        Text(resolutionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if !isCompleted && !isSkipped {
                HStack {
                    Button(actionTitle, action: perform)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("\(actionTitle) \(step.title)")
                    Button("Skip", action: skip)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Skip \(step.title)")
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var actionTitle: String {
        switch step.action {
        case .checklist, .note: "Complete"
        case .logEvent: "Log"
        case .startTimer: "Start"
        case .openFoodHome,
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
             .openSettings:
            "Open"
        }
    }

    private var actionDetailText: String {
        switch step.action {
        case .logEvent:
            return "Log \(step.eventType?.displayName ?? "Event")"
        case .startTimer:
            return "Start \(step.eventType?.displayName ?? "Timer")"
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
            return step.action.displayName
        }
    }

    private var resolutionText: String? {
        guard isCompleted || isSkipped else { return nil }
        let fallback = isSkipped ? "Skipped" : "Completed"
        guard let resolutionRecord else { return fallback }

        let action = resolutionRecord.resolution == .skipped ? "Skipped" : "Completed"
        let time = DateFormatting.time.string(from: resolutionRecord.resolvedAt)
        if let name = resolutionRecord.caregiverName, !name.isEmpty {
            return "\(action) by \(name) at \(time)"
        }
        return "\(action) at \(time)"
    }

    private var statusIcon: String {
        if isCompleted { return "checkmark.circle.fill" }
        if isSkipped { return "minus.circle.fill" }
        return step.action.systemImage
    }

    private var statusColor: Color {
        if isCompleted { return .green }
        if isSkipped { return .secondary }
        return AppTheme.accent
    }
}

private func color(named name: String) -> Color {
    switch name {
    case "orange": return .orange
    case "green": return .green
    case "teal": return .teal
    case "red": return .red
    case "mint": return .mint
    case "pink": return .pink
    default: return .indigo
    }
}

private extension String {
    var accessibilityLabelFromSymbolName: String {
        replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
