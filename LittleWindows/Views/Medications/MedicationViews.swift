import SwiftData
import SwiftUI

private struct MedicationDashboard {
    var medications: [Medication]
    var archivedMedications: [Medication]
    var activeRegimens: [MedicationRegimen]
    var regimensByMedicationID: [UUID: [MedicationRegimen]]
    var phasesByRegimenID: [UUID: [MedicationSchedulePhase]]
    var medicationByID: [UUID: Medication]
    var regimenByID: [UUID: MedicationRegimen]
    var recordByOccurrenceKey: [String: MedicationDoseRecord]
    var records: [MedicationDoseRecord]
    var todayOccurrences: [MedicationOccurrence]
    var overdueOccurrences: [MedicationOccurrence]
    var futureOccurrences: [MedicationOccurrence]
    var asNeededRegimens: [MedicationRegimen]
}

private struct MedicationDoseEditorConfiguration: Identifiable {
    let id = UUID()
    let medicationID: UUID
    let regimenID: UUID?
    let phaseID: UUID?
    let occurrenceKey: String?
    let scheduledAt: Date?
    let scheduledDoseAmount: Double
    let doseUnit: String
    let medicationName: String
    let recordID: UUID?
    let initialEntry: MedicationDoseEntry

    var allowsNotTakenOutcome: Bool { scheduledAt != nil }
}

private enum MedicationDoseEditorOutcome: String, CaseIterable, Identifiable {
    case taken
    case held
    case refused
    case unable
    case missed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .taken: "Taken"
        case .held: "Held per clinician"
        case .refused: "Refused"
        case .unable: "Unable to take"
        case .missed: "Missed"
        }
    }

    var status: MedicationDoseStatus {
        switch self {
        case .taken: .taken
        case .held: .held
        case .refused: .refused
        case .unable: .unable
        case .missed: .missed
        }
    }

    init(status: MedicationDoseStatus) {
        switch status {
        case .taken: self = .taken
        case .held: self = .held
        case .refused: self = .refused
        case .unable: self = .unable
        case .missed, .skipped: self = .missed
        }
    }
}

private struct MedicationDoseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: MedicationDoseEditorConfiguration
    let onSave: (MedicationDoseEntry) -> String?

    @State private var outcome: MedicationDoseEditorOutcome
    @State private var actualTime: Date
    @State private var actualDoseAmount: Double
    @State private var takenLate: Bool
    @State private var missedReason: MedicationDoseReason?
    @State private var notes: String
    @State private var validationMessage: String?

    private let missedReasons: [MedicationDoseReason] = [
        .asleep, .away, .outOfSupply, .forgot, .sideEffects, .other
    ]

    init(
        configuration: MedicationDoseEditorConfiguration,
        onSave: @escaping (MedicationDoseEntry) -> String?
    ) {
        self.configuration = configuration
        self.onSave = onSave
        let entry = configuration.initialEntry
        _outcome = State(initialValue: MedicationDoseEditorOutcome(status: entry.status))
        _actualTime = State(initialValue: entry.takenAt ?? Date())
        _actualDoseAmount = State(
            initialValue: entry.actualDoseAmount ?? configuration.scheduledDoseAmount
        )
        _takenLate = State(initialValue: entry.timing == .late)
        _missedReason = State(initialValue: entry.reason)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        Form {
            Section("Dose") {
                LabeledContent("Medication", value: configuration.medicationName)
                if let scheduledAt = configuration.scheduledAt {
                    LabeledContent(
                        "Scheduled",
                        value: scheduledAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                LabeledContent(
                    "Scheduled amount",
                    value: "\(doseText(configuration.scheduledDoseAmount)) \(configuration.doseUnit)"
                )
            }

            if configuration.allowsNotTakenOutcome {
                Section("Outcome") {
                    Picker("Outcome", selection: $outcome) {
                        ForEach(MedicationDoseEditorOutcome.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .accessibilityIdentifier("medication-dose.outcome")
                }
            }

            if outcome == .taken {
                Section("What was taken") {
                    DatePicker("Actual time", selection: $actualTime, in: ...Date())
                    LabeledContent("Actual amount") {
                        HStack {
                            TextField(
                                "Required",
                                value: $actualDoseAmount,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            Text(configuration.doseUnit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if configuration.scheduledAt != nil {
                        Toggle("Taken late", isOn: $takenLate)
                    }
                    if amountDiffers {
                        Label(
                            "This records a different or partial amount from the scheduled dose.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Reason") {
                    if outcome == .missed {
                        Picker("Reason", selection: $missedReason) {
                            Text("Choose a reason").tag(nil as MedicationDoseReason?)
                            ForEach(missedReasons) { reason in
                                Text(reason.displayName).tag(reason as MedicationDoseReason?)
                            }
                        }
                        .accessibilityIdentifier("medication-dose.reason")
                    } else {
                        LabeledContent("Recorded as", value: defaultReason.displayName)
                    }
                }
            }

            Section("Notes") {
                TextField("Optional details", text: $notes, axis: .vertical)
                    .lineLimit(3...7)
            }

            Section {
                Text("Record what happened. Follow the medication label or care team instructions for medical decisions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(configuration.recordID == nil ? "Log Dose" : "Edit Dose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .alert("Check dose", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var amountDiffers: Bool {
        abs(actualDoseAmount - configuration.scheduledDoseAmount) > 0.000_001
    }

    private var defaultReason: MedicationDoseReason {
        switch outcome {
        case .held: .perClinicianInstruction
        case .refused: .refused
        case .unable: .unableToTake
        case .missed: missedReason ?? .other
        case .taken: .other
        }
    }

    private func doseText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func save() {
        if outcome == .taken, (!actualDoseAmount.isFinite || actualDoseAmount <= 0) {
            validationMessage = "Enter the amount that was actually taken."
            return
        }
        if outcome == .missed, missedReason == nil {
            validationMessage = "Choose why the dose was missed."
            return
        }
        let status = outcome.status
        let entry = MedicationDoseEntry(
            status: status,
            takenAt: status == .taken ? actualTime : nil,
            actualDoseAmount: status == .taken ? actualDoseAmount : nil,
            timing: status == .taken && configuration.scheduledAt != nil
                ? (takenLate ? .late : .onSchedule)
                : nil,
            reason: status == .taken ? nil : defaultReason,
            notes: notes
        )
        if let message = onSave(entry) {
            validationMessage = message
        } else {
            dismiss()
        }
    }
}

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allMedications: [Medication]
    @Query private var allRegimens: [MedicationRegimen]
    @Query private var allPhases: [MedicationSchedulePhase]
    @Query private var allPlanRevisions: [MedicationPlanRevision]
    @Query private var allDoseRecords: [MedicationDoseRecord]
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared

    let profile: CareProfile
    @State private var showingEditor = false
    @State private var showingReconciliation = false
    @State private var actionMessage: String?
    @State private var doseEditorConfiguration: MedicationDoseEditorConfiguration?
    @State private var selectedMedicationID: UUID?

    init(profile: CareProfile) {
        self.profile = profile
        let profileID = profile.id
        let calendar = MedicationScheduleDate.currentCalendar()
        let currentDay = calendar.startOfDay(for: Date())
        let relevantRecordStart = calendar.date(byAdding: .day, value: -8, to: currentDay) ?? currentDay
        _allMedications = Query(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\Medication.name)]
        ))
        _allRegimens = Query(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationRegimen.createdAt)]
        ))
        _allPhases = Query(FetchDescriptor<MedicationSchedulePhase>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationSchedulePhase.sequence)]
        ))
        _allPlanRevisions = Query(FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationPlanRevision.effectiveFrom)]
        ))
        _allDoseRecords = Query(FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.loggedAt >= relevantRecordStart
            },
            sortBy: [SortDescriptor(\MedicationDoseRecord.loggedAt, order: .reverse)]
        ))
    }

    private var scheduleCalendar: Calendar {
        MedicationScheduleDate.currentCalendar()
    }

    private func makeDashboard(now: Date = Date()) -> MedicationDashboard {
        let medications = allMedications.filter { !$0.isArchived }
        let archivedMedications = allMedications.filter(\.isArchived)
        let activeRegimens = allRegimens.filter(\.isActive)
        let medicationByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let regimenByID = Dictionary(uniqueKeysWithValues: allRegimens.map { ($0.id, $0) })
        let regimensByMedicationID = Dictionary(grouping: activeRegimens, by: \.medicationID)
        let allRegimensByMedicationID = Dictionary(grouping: allRegimens, by: \.medicationID)
        let phasesByRegimenID = Dictionary(grouping: allPhases, by: \.regimenID)
        let revisionsByMedicationID = Dictionary(grouping: allPlanRevisions, by: \.medicationID)
        let recordByOccurrenceKey = Dictionary(
            allDoseRecords.compactMap { record in
                record.occurrenceKey.map { ($0, record) }
            },
            uniquingKeysWith: { first, second in
                first.loggedAt >= second.loggedAt ? first : second
            }
        )
        let start = scheduleCalendar.startOfDay(for: now)
        let end = scheduleCalendar.date(byAdding: .day, value: 7, to: now) ?? now
        let occurrences = activeRegimens.flatMap { regimen in
            MedicationScheduleEngine.occurrences(
                regimen: regimen,
                phases: phasesByRegimenID[regimen.id] ?? [],
                from: start,
                through: end
            )
        }.sorted { $0.scheduledAt < $1.scheduledAt }
        let overdueStart = scheduleCalendar.date(
            byAdding: .day,
            value: -7,
            to: start
        ) ?? start
        let overdueOccurrences = medications.flatMap { medication in
            let medicationRegimens = allRegimensByMedicationID[medication.id] ?? []
            return MedicationScheduleEngine.versionedOccurrences(
                medicationID: medication.id,
                regimens: medicationRegimens,
                phases: medicationRegimens.flatMap { phasesByRegimenID[$0.id] ?? [] },
                revisions: revisionsByMedicationID[medication.id] ?? [],
                from: overdueStart,
                through: start.addingTimeInterval(-0.001),
                calendar: scheduleCalendar
            )
        }.filter {
            recordByOccurrenceKey[$0.occurrenceKey] == nil
        }.sorted { $0.scheduledAt > $1.scheduledAt }
        return MedicationDashboard(
            medications: medications,
            archivedMedications: archivedMedications,
            activeRegimens: activeRegimens,
            regimensByMedicationID: regimensByMedicationID,
            phasesByRegimenID: phasesByRegimenID,
            medicationByID: medicationByID,
            regimenByID: regimenByID,
            recordByOccurrenceKey: recordByOccurrenceKey,
            records: allDoseRecords,
            todayOccurrences: occurrences.filter {
                scheduleCalendar.isDate($0.scheduledAt, inSameDayAs: now)
            },
            overdueOccurrences: overdueOccurrences,
            futureOccurrences: occurrences.filter {
                $0.scheduledAt > now && !scheduleCalendar.isDate($0.scheduledAt, inSameDayAs: now)
            },
            asNeededRegimens: activeRegimens.filter { $0.scheduleKind == .asNeeded }
        )
    }

    var body: some View {
        let dashboard = makeDashboard()
        List {
            todaySection(dashboard)
            asNeededSection(dashboard)
            medicationSection(dashboard)
            overdueSection(dashboard)
            upcomingSection(dashboard)
            archivedSection(dashboard)
            safetySection
        }
        .navigationTitle("Medications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reconcile medications", systemImage: "checkmark.seal") {
                    showingReconciliation = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add medication", systemImage: "plus") {
                    showingEditor = true
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                MedicationEditorView(profile: profile)
            }
        }
        .sheet(isPresented: $showingReconciliation) {
            NavigationStack {
                MedicationReconciliationView(profile: profile)
            }
        }
        .sheet(item: $doseEditorConfiguration) { configuration in
            NavigationStack {
                MedicationDoseEditorView(configuration: configuration) { entry in
                    saveDoseEntry(configuration: configuration, entry: entry)
                }
            }
        }
        .alert("Medication", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
        .task(id: deepLinkRouter.pendingMedicationDoseCommand?.id) {
            applyPendingDoseCommand()
        }
        .task(id: deepLinkRouter.pendingMedicationDetailID) {
            guard let medicationID = deepLinkRouter.pendingMedicationDetailID else { return }
            defer { deepLinkRouter.pendingMedicationDetailID = nil }
            guard dashboard.medicationByID[medicationID] != nil else {
                actionMessage = "That medication is no longer current."
                return
            }
            selectedMedicationID = medicationID
        }
        .navigationDestination(item: $selectedMedicationID) { medicationID in
            if let medication = dashboard.medicationByID[medicationID] {
                MedicationDetailView(
                    profile: profile,
                    medication: medication,
                    regimens: dashboard.regimensByMedicationID[medication.id] ?? [],
                    phases: (dashboard.regimensByMedicationID[medication.id] ?? []).flatMap {
                        dashboard.phasesByRegimenID[$0.id] ?? []
                    }
                )
            } else {
                ContentUnavailableView(
                    "Medication unavailable",
                    systemImage: "pills",
                    description: Text("This medication may have been archived or removed.")
                )
            }
        }
    }

    @ViewBuilder
    private func overdueSection(_ dashboard: MedicationDashboard) -> some View {
        if !dashboard.overdueOccurrences.isEmpty {
            Section {
                ForEach(dashboard.overdueOccurrences.prefix(20)) { occurrence in
                    occurrenceRow(occurrence, dashboard: dashboard)
                }
            } header: {
                AppSectionHeader(
                    title: "Unlogged past doses",
                    subtitle: "Last 7 days"
                )
            } footer: {
                Text("Record what actually happened so adherence reports do not leave these doses as unknown.")
            }
        }
    }

    @ViewBuilder
    private func todaySection(_ dashboard: MedicationDashboard) -> some View {
        Section {
            if dashboard.todayOccurrences.isEmpty {
                ContentUnavailableView(
                    "No scheduled doses today",
                    systemImage: "checkmark.circle",
                    description: Text("Scheduled doses will appear here.")
                )
            } else {
                ForEach(dashboard.todayOccurrences) { occurrence in
                    occurrenceRow(occurrence, dashboard: dashboard)
                }
            }
        } header: {
            AppSectionHeader(title: "Today", subtitle: profile.name)
        }
    }

    @ViewBuilder
    private func asNeededSection(_ dashboard: MedicationDashboard) -> some View {
        if !dashboard.asNeededRegimens.isEmpty {
            Section("As needed") {
                ForEach(dashboard.asNeededRegimens) { regimen in
                    if let medication = dashboard.medicationByID[regimen.medicationID] {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(medication.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(asNeededSubtitle(regimen))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Log dose") {
                                presentDoseEditor(
                                    medication: medication,
                                    regimen: regimen,
                                    occurrence: nil
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func medicationSection(_ dashboard: MedicationDashboard) -> some View {
        Section {
            if dashboard.medications.isEmpty {
                ContentUnavailableView {
                    Label("No medications", systemImage: "pills")
                } description: {
                    Text("Add a medication, its dose, and the schedule you want to follow.")
                } actions: {
                    Button("Add Medication") { showingEditor = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(dashboard.medications) { medication in
                    NavigationLink {
                        MedicationDetailView(
                            profile: profile,
                            medication: medication,
                            regimens: dashboard.regimensByMedicationID[medication.id] ?? [],
                            phases: (dashboard.regimensByMedicationID[medication.id] ?? []).flatMap {
                                dashboard.phasesByRegimenID[$0.id] ?? []
                            }
                        )
                    } label: {
                        medicationRow(medication, dashboard: dashboard)
                    }
                }
            }
        } header: {
            AppSectionHeader(title: "Medication list", subtitle: dashboard.medications.count.description)
        }
    }

    @ViewBuilder
    private func upcomingSection(_ dashboard: MedicationDashboard) -> some View {
        if !dashboard.futureOccurrences.isEmpty {
            Section("Next 7 days") {
                ForEach(dashboard.futureOccurrences.prefix(12)) { occurrence in
                    occurrenceRow(occurrence, dashboard: dashboard)
                }
            }
        }
    }

    @ViewBuilder
    private func archivedSection(_ dashboard: MedicationDashboard) -> some View {
        if !dashboard.archivedMedications.isEmpty {
            Section("Archived") {
                ForEach(dashboard.archivedMedications) { medication in
                    HStack {
                        Label(medication.name, systemImage: "archivebox.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore") {
                            guard MedicationService.restore(
                                medication: medication,
                                regimens: allRegimens,
                                context: modelContext
                            ) else {
                                actionMessage = "This medication could not be restored. Review its plan history and try again."
                                return
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var safetySection: some View {
        Section {
            Label("Little Windows records the schedule you enter; it does not verify doses, interactions, or medical instructions.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func occurrenceRow(
        _ occurrence: MedicationOccurrence,
        dashboard: MedicationDashboard
    ) -> some View {
        if let regimen = dashboard.regimenByID[occurrence.regimenID],
           let medication = dashboard.medicationByID[regimen.medicationID] {
            let record = dashboard.recordByOccurrenceKey[occurrence.occurrenceKey]
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(medication.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(doseText(occurrence.doseAmount)) \(occurrence.doseUnit) · \(occurrenceDateText(occurrence.scheduledAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let record {
                        Label(
                            record.outcomeDisplayName,
                            systemImage: record.status == .taken
                                ? "checkmark.circle.fill"
                                : "exclamationmark.circle.fill"
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(record.status == .taken ? .green : .secondary)
                    }
                }
                if record == nil {
                    HStack {
                        Button("Taken") {
                            recordScheduledDose(
                                occurrence,
                                medication: medication,
                                regimen: regimen,
                                status: .taken
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Other…") {
                            presentDoseEditor(
                                medication: medication,
                                regimen: regimen,
                                occurrence: occurrence
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func medicationRow(_ medication: Medication, dashboard: MedicationDashboard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: medication.needsRefill ? "pills.circle.fill" : "pills.fill")
                .foregroundStyle(medication.needsRefill ? .orange : .red)
                .frame(width: 38, height: 38)
                .background((medication.needsRefill ? Color.orange : Color.red).opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.name)
                    .font(.subheadline.weight(.semibold))
                Text([
                    medication.strengthDescription,
                    dashboard.regimensByMedicationID[medication.id]?.first?.scheduleSummary
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if medication.needsRefill {
                    Text("Refill soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if medication.isConfirmedCurrent, let reviewedAt = medication.lastReviewedAt {
                    Text("Confirmed current · \(reviewedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("Needs medication review")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func doseText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func occurrenceDateText(_ date: Date) -> String {
        "\(DateFormatting.dayString(from: date, timeZone: scheduleCalendar.timeZone)) at \(DateFormatting.timeString(from: date, timeZone: scheduleCalendar.timeZone))"
    }

    private func asNeededSubtitle(_ regimen: MedicationRegimen) -> String {
        var parts = ["\(doseText(regimen.doseAmount)) \(regimen.doseUnit)"]
        if let gap = regimen.minimumHoursBetweenDoses {
            parts.append("at least \(doseText(gap)) hr apart")
        }
        if let maximum = regimen.maximumDosesPerDay {
            parts.append("up to \(maximum)/day")
        }
        return parts.joined(separator: " · ")
    }

    private func presentDoseEditor(
        medication: Medication,
        regimen: MedicationRegimen,
        occurrence: MedicationOccurrence?
    ) {
        let scheduledAmount = occurrence?.doseAmount ?? regimen.doseAmount
        doseEditorConfiguration = MedicationDoseEditorConfiguration(
            medicationID: medication.id,
            regimenID: regimen.id,
            phaseID: occurrence?.phaseID,
            occurrenceKey: occurrence?.occurrenceKey,
            scheduledAt: occurrence?.scheduledAt,
            scheduledDoseAmount: scheduledAmount,
            doseUnit: occurrence?.doseUnit ?? regimen.doseUnit,
            medicationName: medication.name,
            recordID: nil,
            initialEntry: MedicationDoseEntry(
                status: .taken,
                takenAt: Date(),
                actualDoseAmount: scheduledAmount,
                timing: occurrence == nil ? nil : .onSchedule,
                reason: nil,
                notes: ""
            )
        )
    }

    private func saveDoseEntry(
        configuration: MedicationDoseEditorConfiguration,
        entry: MedicationDoseEntry
    ) -> String? {
        guard let regimenID = configuration.regimenID,
              let medication = allMedications.first(where: { $0.id == configuration.medicationID }),
              let regimen = allRegimens.first(where: { $0.id == regimenID }) else {
            return "This medication changed. Close this form and try again."
        }
        if regimen.scheduleKind == .asNeeded {
            let actualTime = entry.takenAt ?? Date()
            switch MedicationScheduleEngine.asNeededDecision(
                regimen: regimen,
                records: allDoseRecords,
                at: actualTime
            ) {
            case .allowed:
                break
            case .waitUntil(let date):
                return "Based on the interval you entered, the next dose is due after \(date.formatted(date: .omitted, time: .shortened)). Check the medication instructions if plans changed."
            case .dailyLimitReached(let maximum):
                return "The daily limit you entered is \(maximum) doses. Check the medication instructions before logging another dose."
            }
            guard MedicationService.recordDose(
                medication: medication,
                regimen: regimen,
                status: entry.status,
                at: Date(),
                takenAt: entry.takenAt,
                actualDoseAmount: entry.actualDoseAmount,
                timing: entry.timing,
                reason: entry.reason,
                notes: entry.notes,
                context: modelContext
            ) != nil else {
                return "This dose could not be saved. Please try again."
            }
            return nil
        }

        guard let occurrenceKey = configuration.occurrenceKey,
              let scheduledAt = configuration.scheduledAt else {
            return "This scheduled dose changed. Close this form and try again."
        }
        let result = MedicationService.recordScheduledDose(
            MedicationScheduledDoseReference(
                profileID: profile.id,
                medicationID: medication.id,
                regimenID: regimen.id,
                phaseID: configuration.phaseID,
                occurrenceKey: occurrenceKey,
                scheduledAt: scheduledAt,
                doseAmount: configuration.scheduledDoseAmount,
                doseUnit: configuration.doseUnit
            ),
            status: entry.status,
            at: Date(),
            takenAt: entry.takenAt,
            actualDoseAmount: entry.actualDoseAmount,
            timing: entry.timing,
            reason: entry.reason,
            notes: entry.notes,
            context: modelContext
        )
        switch result {
        case .applied:
            return nil
        case .duplicate(let medicationName):
            return "\(medicationName) already has an outcome for this dose."
        case .rejected(let message):
            return message
        }
    }

    private func recordScheduledDose(
        _ occurrence: MedicationOccurrence,
        medication: Medication,
        regimen: MedicationRegimen,
        status: MedicationDoseStatus
    ) {
        let result = MedicationService.recordScheduledDose(
            MedicationScheduledDoseReference(
                profileID: profile.id,
                medicationID: medication.id,
                regimenID: regimen.id,
                phaseID: occurrence.phaseID,
                occurrenceKey: occurrence.occurrenceKey,
                scheduledAt: occurrence.scheduledAt,
                doseAmount: occurrence.doseAmount,
                doseUnit: occurrence.doseUnit
            ),
            status: status,
            context: modelContext
        )
        if case .rejected(let message) = result {
            actionMessage = message
        }
    }

    private func applyPendingDoseCommand() {
        guard let command = deepLinkRouter.pendingMedicationDoseCommand,
              command.profileID == profile.id else { return }
        defer { deepLinkRouter.pendingMedicationDoseCommand = nil }
        let reference = MedicationScheduledDoseReference(
            profileID: command.profileID,
            medicationID: command.medicationID,
            regimenID: command.regimenID,
            phaseID: command.phaseID,
            occurrenceKey: command.occurrenceKey,
            scheduledAt: command.scheduledAt,
            doseAmount: command.doseAmount,
            doseUnit: command.doseUnit
        )
        if command.status == nil {
            switch MedicationService.resolveScheduledDose(reference, context: modelContext) {
            case .valid(let medication, let regimen, let occurrence, let existingRecord):
                if let existingRecord {
                    actionMessage = "This dose was already recorded as \(existingRecord.outcomeDisplayName.lowercased())."
                } else {
                    presentDoseEditor(
                        medication: medication,
                        regimen: regimen,
                        occurrence: occurrence
                    )
                }
            case .rejected(let message):
                actionMessage = message
            }
            return
        }
        guard let status = command.status else { return }
        switch MedicationService.recordScheduledDose(
            reference,
            status: status,
            context: modelContext
        ) {
        case .applied(let medicationName):
            actionMessage = "Recorded \(medicationName) as \(status.displayName.lowercased())."
        case .duplicate(let medicationName):
            actionMessage = "\(medicationName) was already recorded as \(status.displayName.lowercased())."
        case .rejected(let message):
            actionMessage = message
        }
    }
}

private struct MedicationDoseHistoryRow: Identifiable, Sendable {
    let id: UUID
    let regimenID: UUID?
    let occurrenceKey: String?
    let statusRawValue: String
    let loggedAt: Date
    let takenAt: Date?
    let scheduledAt: Date?
    let actualDoseAmount: Double?
    let timingRawValue: String?
    let reasonRawValue: String?
    let doseAmount: Double
    let doseUnit: String
    let notes: String

    var status: MedicationDoseStatus {
        MedicationDoseStatus(rawValue: statusRawValue) ?? .skipped
    }

    var timing: MedicationDoseTiming? {
        timingRawValue.flatMap(MedicationDoseTiming.init(rawValue:))
    }

    var reason: MedicationDoseReason? {
        reasonRawValue.flatMap(MedicationDoseReason.init(rawValue:))
    }

    var effectiveActualDoseAmount: Double? {
        status == .taken ? (actualDoseAmount ?? doseAmount) : nil
    }

    var hasDifferentActualAmount: Bool {
        guard let effectiveActualDoseAmount else { return false }
        return abs(effectiveActualDoseAmount - doseAmount) > 0.000_001
    }

    var outcomeDisplayName: String {
        guard status == .taken else { return status.displayName }
        return switch (timing == .late, hasDifferentActualAmount) {
        case (true, true): "Taken late, different amount"
        case (true, false): "Taken late"
        case (false, true): "Different amount taken"
        case (false, false): "Taken"
        }
    }

    var displayDate: Date {
        takenAt ?? scheduledAt ?? loggedAt
    }
}

private struct MedicationSupplyHistoryRow: Identifiable, Sendable {
    let id: UUID
    let adjustment: Double
    let resultingSupply: Double?
    let reasonRawValue: String
    let notes: String
    let loggedAt: Date

    var reason: MedicationSupplyReason? {
        MedicationSupplyReason(rawValue: reasonRawValue)
    }
}

private struct MedicationPlanAuditChange: Identifiable, Sendable {
    let label: String
    let before: String
    let after: String

    var id: String { label }
}

private struct MedicationPlanRevisionHistoryRow: Identifiable, Sendable {
    let id: UUID
    let changeKindRawValue: String
    let sourceRawValue: String
    let effectiveFrom: Date
    let changedAt: Date
    let changedByName: String
    let notes: String
    let appointmentID: UUID?
    let changes: [MedicationPlanAuditChange]

    var changeKind: MedicationPlanChangeKind {
        MedicationPlanChangeKind(rawValue: changeKindRawValue) ?? .updated
    }

    var source: MedicationPlanChangeSource {
        MedicationPlanChangeSource(rawValue: sourceRawValue) ?? .caregiver
    }
}

private struct MedicationHistorySnapshot: Sendable {
    let doseRecords: [MedicationDoseHistoryRow]
    let supplyLogs: [MedicationSupplyHistoryRow]
    let planRevisions: [MedicationPlanRevisionHistoryRow]
}

private struct MedicationTripSupplyWarning: Identifiable {
    let trip: PackingTrip
    let risk: MedicationTripSupplyRisk

    var id: UUID { trip.id }
}

@ModelActor
private actor MedicationHistoryWorker {
    func snapshot(medicationID: UUID) -> MedicationHistorySnapshot {
        var doseDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate { $0.medicationID == medicationID },
            sortBy: [SortDescriptor(\MedicationDoseRecord.loggedAt, order: .reverse)]
        )
        // Keep the fetch bounded while retaining the prior 30-day adherence
        // headroom for schedules restored from older or external backups.
        doseDescriptor.fetchLimit = 750
        let doseRecords = ((try? modelContext.fetch(doseDescriptor)) ?? []).map {
            MedicationDoseHistoryRow(
                id: $0.id,
                regimenID: $0.regimenID,
                occurrenceKey: $0.occurrenceKey,
                statusRawValue: $0.statusRawValue,
                loggedAt: $0.loggedAt,
                takenAt: $0.takenAt,
                scheduledAt: $0.scheduledAt,
                actualDoseAmount: $0.actualDoseAmount,
                timingRawValue: $0.timingRawValue,
                reasonRawValue: $0.reasonRawValue,
                doseAmount: $0.doseAmount,
                doseUnit: $0.doseUnit,
                notes: $0.notes
            )
        }

        let supplyDescriptor = FetchDescriptor<MedicationSupplyLog>(
            predicate: #Predicate { $0.medicationID == medicationID },
            sortBy: [SortDescriptor(\MedicationSupplyLog.loggedAt, order: .reverse)]
        )
        let supplyLogs = ((try? modelContext.fetch(supplyDescriptor)) ?? []).map {
            MedicationSupplyHistoryRow(
                id: $0.id,
                adjustment: $0.adjustment,
                resultingSupply: $0.resultingSupply,
                reasonRawValue: $0.reasonRawValue,
                notes: $0.notes,
                loggedAt: $0.loggedAt
            )
        }

        let revisionDescriptor = FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate { $0.medicationID == medicationID },
            sortBy: [SortDescriptor(\MedicationPlanRevision.changedAt, order: .reverse)]
        )
        let planRevisions = ((try? modelContext.fetch(revisionDescriptor)) ?? []).map { revision in
            MedicationPlanRevisionHistoryRow(
                id: revision.id,
                changeKindRawValue: revision.changeKindRawValue,
                sourceRawValue: revision.sourceRawValue,
                effectiveFrom: revision.effectiveFrom,
                changedAt: revision.changedAt,
                changedByName: revision.changedByName,
                notes: revision.notes,
                appointmentID: revision.appointmentID,
                changes: planChanges(
                    before: revision.beforeSnapshot,
                    after: revision.afterSnapshot
                )
            )
        }

        return MedicationHistorySnapshot(
            doseRecords: doseRecords,
            supplyLogs: supplyLogs,
            planRevisions: planRevisions
        )
    }

    private func planChanges(
        before: MedicationPlanSnapshot?,
        after: MedicationPlanSnapshot?
    ) -> [MedicationPlanAuditChange] {
        guard let after else { return [] }
        let beforeValues = before.map(planValues) ?? [:]
        let afterValues = planValues(after)
        return planFieldOrder.compactMap { label in
            let oldValue = beforeValues[label] ?? "Not recorded"
            let newValue = afterValues[label] ?? "Not recorded"
            guard before == nil || oldValue != newValue else { return nil }
            return MedicationPlanAuditChange(
                label: label,
                before: oldValue,
                after: newValue
            )
        }
    }

    private var planFieldOrder: [String] {
        [
            "Medication", "Form", "Strength", "Route", "Purpose", "Instructions",
            "Prescriber", "Pharmacy", "Status", "Review status", "Last reviewed",
            "Schedule", "Schedule instructions", "Dose", "Dose times",
            "Schedule phases", "Course end", "Minimum interval", "Daily limit",
            "Reminders", "Reminder lead", "Refill alert", "Refill lead time", "Prescription number",
            "Fill quantity", "Refills remaining", "Prescription expiration"
        ]
    }

    private func planValues(_ snapshot: MedicationPlanSnapshot) -> [String: String] {
        let number: (Double) -> String = {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        }
        let dose = if let amount = snapshot.doseAmount, let unit = snapshot.doseUnit {
            "\(number(amount)) \(unit)"
        } else {
            "Not scheduled"
        }
        let strength = snapshot.strength.map {
            "\(number($0)) \(snapshot.strengthUnit)"
        } ?? "Not entered"
        let schedule: String = switch snapshot.scheduleKind {
        case .daily: "Every day"
        case .specificWeekdays: "Selected weekdays (mask \(snapshot.weekdayMask ?? 0))"
        case .everyNDays: "Every \(snapshot.intervalDays ?? 1) days"
        case .fixedCourse: "Fixed course"
        case .cycle: "\(snapshot.cycleOnDays ?? 1) days on, \(snapshot.cycleOffDays ?? 0) days off"
        case .alternating: "Alternating doses"
        case .taper: "Taper schedule"
        case .asNeeded: "As needed"
        case nil: "Not scheduled"
        }
        let doseTimes = snapshot.doseTimes.isEmpty
            ? "None"
            : snapshot.doseTimes.map(\.id).joined(separator: ", ")
        let phaseSummary = snapshot.phases.isEmpty
            ? "None"
            : snapshot.phases.map { phase in
                let duration = phase.durationDays.map { " for \($0) days" } ?? ""
                return "Phase \(phase.sequence + 1): \(number(phase.doseAmount)) \(phase.doseUnit)\(duration)"
            }.joined(separator: "; ")
        let reminders = snapshot.remindersEnabled == true
            ? (snapshot.followUpRemindersEnabled == true ? "On with follow-up" : "On")
            : "Off"
        return [
            "Medication": snapshot.medicationName,
            "Form": snapshot.form.displayName,
            "Strength": strength,
            "Route": snapshot.route.displayName,
            "Purpose": snapshot.reasonForTaking.nilIfBlank ?? "Not entered",
            "Instructions": snapshot.instructions.nilIfBlank ?? "Not entered",
            "Prescriber": snapshot.prescriber.nilIfBlank ?? "Not entered",
            "Pharmacy": snapshot.pharmacy.nilIfBlank ?? "Not entered",
            "Status": snapshot.isArchived ? "Stopped" : "Current",
            "Review status": snapshot.isConfirmedCurrent == true ? "Confirmed current" : "Needs review",
            "Last reviewed": snapshot.lastReviewedAt?.formatted(
                date: .abbreviated,
                time: .shortened
            ) ?? "Not reviewed",
            "Schedule": schedule,
            "Schedule instructions": snapshot.regimenInstructions?.nilIfBlank ?? "Not entered",
            "Dose": dose,
            "Dose times": doseTimes,
            "Schedule phases": phaseSummary,
            "Course end": snapshot.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "None",
            "Minimum interval": snapshot.minimumHoursBetweenDoses.map { "\(number($0)) hours" } ?? "None",
            "Daily limit": snapshot.maximumDosesPerDay.map { "\($0) doses" } ?? "None",
            "Reminders": reminders,
            "Reminder lead": snapshot.reminderLeadMinutes.map { "\($0) minutes" } ?? "Not recorded",
            "Refill alert": snapshot.refillThreshold.map(number) ?? "Off",
            "Refill lead time": snapshot.refillLeadDays.map { "\($0) days" } ?? "Not recorded",
            "Prescription number": snapshot.prescriptionNumber?.nilIfBlank ?? "Not entered",
            "Fill quantity": snapshot.fillQuantity.map(number) ?? "Not entered",
            "Refills remaining": snapshot.refillsRemaining.map(String.init) ?? "Not entered",
            "Prescription expiration": snapshot.prescriptionExpirationDate?.formatted(
                date: .abbreviated,
                time: .omitted
            ) ?? "Not entered"
        ]
    }
}

private struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var liveRegimens: [MedicationRegimen]
    @Query private var livePhases: [MedicationSchedulePhase]
    @Query private var liveDoseRecords: [MedicationDoseRecord]
    @Query private var livePlanRevisions: [MedicationPlanRevision]
    @Query private var refillTasks: [MedicationRefillTask]
    @Query private var upcomingTrips: [PackingTrip]
    @Query private var tripTravelers: [TripTraveler]
    let profile: CareProfile
    let medication: Medication
    let regimens: [MedicationRegimen]
    let phases: [MedicationSchedulePhase]
    @State private var showingSupplyEditor = false
    @State private var showingEditor = false
    @State private var supply = 0.0
    @State private var supplyReason: MedicationSupplyReason = .correction
    @State private var supplyNotes = ""
    @State private var records: [MedicationDoseHistoryRow] = []
    @State private var supplyLogs: [MedicationSupplyHistoryRow] = []
    @State private var planRevisions: [MedicationPlanRevisionHistoryRow] = []
    @State private var isLoadingHistory = true
    @State private var historyRevision = 0
    @State private var doseRecordToDelete: MedicationDoseHistoryRow?
    @State private var doseEditorConfiguration: MedicationDoseEditorConfiguration?
    @State private var showingArchiveConfirmation = false
    @State private var showingReconciliation = false
    @State private var showingRefillEditor = false
    @State private var refillActionMessage: String?
    @State private var refillTaskPendingPickup: MedicationRefillTask?

    init(
        profile: CareProfile,
        medication: Medication,
        regimens: [MedicationRegimen],
        phases: [MedicationSchedulePhase]
    ) {
        self.profile = profile
        self.medication = medication
        self.regimens = regimens
        self.phases = phases
        let profileID = profile.id
        let medicationID = medication.id
        let recentDoseStart = Calendar.current.date(
            byAdding: .day,
            value: -62,
            to: Date()
        ) ?? Date().addingTimeInterval(-62 * 86_400)
        _liveRegimens = Query(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate {
                $0.profileID == profileID && $0.medicationID == medicationID
            },
            sortBy: [SortDescriptor(\MedicationRegimen.createdAt)]
        ))
        _livePhases = Query(FetchDescriptor<MedicationSchedulePhase>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationSchedulePhase.sequence)]
        ))
        var liveDoseDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate {
                $0.medicationID == medicationID && $0.loggedAt >= recentDoseStart
            },
            sortBy: [SortDescriptor(\MedicationDoseRecord.loggedAt, order: .reverse)]
        )
        liveDoseDescriptor.fetchLimit = 5_000
        _liveDoseRecords = Query(liveDoseDescriptor)
        _livePlanRevisions = Query(FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate { $0.medicationID == medicationID },
            sortBy: [SortDescriptor(\MedicationPlanRevision.effectiveFrom)]
        ))
        _refillTasks = Query(FetchDescriptor<MedicationRefillTask>(
            predicate: #Predicate { $0.medicationID == medicationID },
            sortBy: [SortDescriptor(\MedicationRefillTask.updatedAt, order: .reverse)]
        ))
        let upcomingStatus = PackingTripStatus.upcoming.rawValue
        _upcomingTrips = Query(FetchDescriptor<PackingTrip>(
            predicate: #Predicate {
                !$0.isArchived && $0.statusRawValue == upcomingStatus
            },
            sortBy: [SortDescriptor(\PackingTrip.startDate)]
        ))
        _tripTravelers = Query(FetchDescriptor<TripTraveler>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\TripTraveler.updatedAt, order: .reverse)]
        ))
    }

    private var displayedRegimens: [MedicationRegimen] {
        liveRegimens.isEmpty ? regimens : liveRegimens
    }

    private var displayedPhases: [MedicationSchedulePhase] {
        let regimenIDs = Set(displayedRegimens.map(\.id))
        let scoped = livePhases.filter { regimenIDs.contains($0.regimenID) }
        return scoped.isEmpty ? phases : scoped
    }

    private var activeRegimen: MedicationRegimen? {
        displayedRegimens.first { $0.isActive }
    }

    private var scheduleCalendar: Calendar {
        MedicationScheduleDate.currentCalendar()
    }

    private var adherence: MedicationAdherenceSummary? {
        guard displayedRegimens.contains(where: { $0.scheduleKind.isScheduled }) else { return nil }
        let now = Date()
        let start = scheduleCalendar.date(byAdding: .day, value: -30, to: now) ?? now
        let occurrences = MedicationScheduleEngine.versionedOccurrences(
            medicationID: medication.id,
            regimens: displayedRegimens,
            phases: displayedPhases,
            revisions: livePlanRevisions,
            from: start,
            through: now,
            calendar: scheduleCalendar
        )
        return MedicationScheduleEngine.adherence(
            occurrences: occurrences,
            records: liveDoseRecords,
            through: now
        )
    }

    private var supplyProjection: MedicationSupplyProjection? {
        MedicationService.supplyProjection(
            medication: medication,
            doseRecords: liveDoseRecords
        )
    }

    private var activeRefillTask: MedicationRefillTask? {
        refillTasks.first(where: \.isOpen)
    }

    private var relevantTrips: [PackingTrip] {
        let tripIDs = Set(tripTravelers.map(\.tripID))
        return upcomingTrips.filter { tripIDs.contains($0.id) }
    }

    private func tripSupplyRisks(
        projection: MedicationSupplyProjection?
    ) -> [MedicationTripSupplyWarning] {
        guard let projection else { return [] }
        return relevantTrips.compactMap { trip in
            MedicationService.tripSupplyRisk(projection: projection, trip: trip)
                .map { MedicationTripSupplyWarning(trip: trip, risk: $0) }
        }
    }

    var body: some View {
        let adherenceSummary = adherence
        let projectedSupply = supplyProjection
        let refillTask = activeRefillTask
        let tripRisks = tripSupplyRisks(projection: projectedSupply)
        List {
            Section("Medication") {
                LabeledContent("Name", value: medication.name)
                if let strength = medication.strengthDescription {
                    LabeledContent("Strength", value: strength)
                }
                LabeledContent(
                    "Form",
                    value: MedicationForm(rawValue: medication.formRawValue)?.displayName ?? "Other"
                )
                LabeledContent(
                    "Route",
                    value: MedicationRoute(rawValue: medication.routeRawValue)?.displayName ?? "Other"
                )
                if !medication.reasonForTaking.isEmpty {
                    LabeledContent("For", value: medication.reasonForTaking)
                }
                if !medication.instructions.isEmpty {
                    Text(medication.instructions)
                }
            }
            if let regimen = activeRegimen {
                Section("Schedule") {
                    LabeledContent("Pattern", value: regimen.scheduleSummary)
                    LabeledContent("Dose", value: "\(regimen.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(regimen.doseUnit)")
                    if !regimen.doseTimes.isEmpty {
                        LabeledContent("Times", value: regimen.doseTimes.map(\.id).joined(separator: ", "))
                    }
                    LabeledContent("Reminders", value: regimen.remindersEnabled ? "On" : "Off")
                    if regimen.remindersEnabled {
                        LabeledContent(
                            "Follow-up reminder",
                            value: regimen.followUpRemindersEnabled ? "After 30 minutes" : "Off"
                        )
                        let timeZoneBehavior = MedicationTimeZoneBehavior(
                            rawValue: regimen.timeZoneBehaviorRawValue
                        )
                        LabeledContent(
                            "When traveling",
                            value: timeZoneBehavior?.displayName ?? "Not specified"
                        )
                        if timeZoneBehavior == .fixedTimeZone,
                           let identifier = regimen.timeZoneIdentifier,
                           let timeZone = TimeZone(identifier: identifier) {
                            LabeledContent(
                                "Home time zone",
                                value: CareTimeZoneSettings.displayName(for: timeZone)
                            )
                        }
                    }
                }
            }
            planReviewSection
            planHistorySection
            if let adherence = adherenceSummary, let rate = adherence.completionRate {
                Section("Last 30 days") {
                    LabeledContent("Taken", value: "\(adherence.takenCount) of \(adherence.scheduledCount)")
                    LabeledContent("Completion", value: rate.formatted(.percent.precision(.fractionLength(0))))
                    if adherence.lateCount > 0 {
                        LabeledContent("Taken late", value: adherence.lateCount.description)
                    }
                    if adherence.differentAmountCount > 0 {
                        LabeledContent("Different amount", value: adherence.differentAmountCount.description)
                    }
                    if adherence.heldCount > 0 {
                        LabeledContent("Held", value: adherence.heldCount.description)
                    }
                    if adherence.refusedCount > 0 {
                        LabeledContent("Refused", value: adherence.refusedCount.description)
                    }
                    if adherence.unableCount > 0 {
                        LabeledContent("Unable to take", value: adherence.unableCount.description)
                    }
                    if adherence.recordedMissedCount > 0 {
                        LabeledContent("Missed", value: adherence.recordedMissedCount.description)
                    }
                    if adherence.skippedCount > 0 {
                        LabeledContent("Skipped", value: adherence.skippedCount.description)
                    }
                    LabeledContent("Not logged", value: adherence.missedCount.description)
                }
            }
            supplyAndRefillSection(
                projection: projectedSupply,
                activeRefillTask: refillTask
            )
            tripSupplySection(tripRisks)
            refillHistorySection
            supplyHistorySection
            if isLoadingHistory && records.isEmpty && supplyLogs.isEmpty {
                Section("History") {
                    ProgressView("Loading medication history…")
                }
            }
            if !records.isEmpty {
                Section {
                    ForEach(records.prefix(30)) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    record.outcomeDisplayName,
                                    systemImage: record.status == .taken
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.circle"
                                )
                                .foregroundStyle(record.status == .taken ? .green : .secondary)
                                if let detail = doseHistoryDetail(record) {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(record.displayDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Menu("Dose actions", systemImage: "ellipsis.circle") {
                                Button("Edit Details", systemImage: "square.and.pencil") {
                                    presentDoseEditor(for: record)
                                }
                                Button("Delete Dose", role: .destructive) {
                                    doseRecordToDelete = record
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                } header: {
                    Text("Dose history")
                        .accessibilityIdentifier("medication-detail.history-loaded")
                }
            }
            Section {
                Button("Archive Medication", role: .destructive) {
                    showingArchiveConfirmation = true
                }
            }
        }
        .navigationTitle(medication.name)
        .toolbar {
            if activeRegimen != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEditor = true }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let activeRegimen {
                NavigationStack {
                    MedicationEditorView(
                        profile: profile,
                        medication: medication,
                        regimen: activeRegimen,
                        phases: displayedPhases.filter { $0.regimenID == activeRegimen.id }
                    )
                }
            }
        }
        .sheet(isPresented: $showingSupplyEditor) {
            supplyEditor
        }
        .sheet(item: $doseEditorConfiguration) { configuration in
            NavigationStack {
                MedicationDoseEditorView(configuration: configuration) { entry in
                    saveDoseEdit(configuration: configuration, entry: entry)
                }
            }
        }
        .sheet(isPresented: $showingReconciliation) {
            NavigationStack {
                MedicationReconciliationView(profile: profile)
            }
        }
        .sheet(isPresented: $showingRefillEditor) {
            NavigationStack {
                MedicationRefillEditorView(
                    profile: profile,
                    medication: medication,
                    task: refillTask,
                    projection: projectedSupply
                )
            }
        }
        .alert("Refill", isPresented: Binding(
            get: { refillActionMessage != nil },
            set: { if !$0 { refillActionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refillActionMessage ?? "")
        }
        .appActionSheet(
            isPresented: Binding(
                get: { doseRecordToDelete != nil },
                set: { if !$0 { doseRecordToDelete = nil } }
            ),
            title: "Delete this dose record?",
            message: "This removes the dose from medication history and the care timeline, and restores any supply that was deducted.",
            systemImage: "trash.fill",
            tint: .red,
            options: doseRecordToDelete.map { record in
                [AppActionSheetOption(
                    title: "Delete Dose",
                    subtitle: "Remove the dose and restore its deducted supply.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    deleteDoseRecord(record)
                    doseRecordToDelete = nil
                }]
            } ?? [],
            cancelAction: { doseRecordToDelete = nil }
        )
        .appActionSheet(
            isPresented: $showingArchiveConfirmation,
            title: "Archive \(medication.name)?",
            message: "Scheduled reminders will stop. You can restore this medication from the archived list.",
            systemImage: "archivebox.fill",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Archive Medication",
                    subtitle: "Stop its reminders and move it to the archived list.",
                    systemImage: "archivebox.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    guard MedicationService.archive(
                        medication: medication,
                        regimens: displayedRegimens,
                        context: modelContext
                    ) else {
                        refillActionMessage = "The medication could not be archived. Please try again."
                        return
                    }
                    dismiss()
                }
            ]
        )
        .appActionSheet(
            isPresented: Binding(
                get: { refillTaskPendingPickup != nil },
                set: { if !$0 { refillTaskPendingPickup = nil } }
            ),
            title: "Mark refill picked up?",
            message: "This adds the fill quantity to supply and reduces remaining refills by one.",
            systemImage: "bag.badge.checkmark.fill",
            tint: .green,
            options: refillTaskPendingPickup.map { task in
                [AppActionSheetOption(
                    title: "Confirm Pickup",
                    subtitle: "Record the fill and close this refill task.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                ) {
                    refillTaskPendingPickup = nil
                    updateRefillStatus(task, to: .pickedUp)
                }]
            } ?? [],
            cancelAction: { refillTaskPendingPickup = nil }
        )
        .task(id: historyRevision) {
            await loadHistory()
        }
    }

    @ViewBuilder
    private func supplyAndRefillSection(
        projection: MedicationSupplyProjection?,
        activeRefillTask: MedicationRefillTask?
    ) -> some View {
        Section("Supply and refill") {
            if let current = medication.currentSupply {
                LabeledContent(
                    "Remaining",
                    value: current.formatted(.number.precision(.fractionLength(0...2)))
                )
            } else {
                Text("Supply tracking is off")
                    .foregroundStyle(.secondary)
            }
            if let projection {
                LabeledContent(
                    "Estimated run-out",
                    value: projection.estimatedRunOutDate.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
                LabeledContent(
                    "Recent actual use",
                    value: "\(projection.averageDailyUse.formatted(.number.precision(.fractionLength(0...2)))) per day"
                )
                Text(
                    "\(projection.confidence.displayName) · \(projection.observedDoseCount) taken doses across \(projection.observedDayCount) days"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if activeRefillTask == nil,
                   let planningDate = Calendar.current.date(
                       byAdding: .day,
                       value: -medication.refillLeadDays,
                       to: projection.estimatedRunOutDate
                   ), planningDate <= Date() {
                    Label(
                        "Refill planning is due based on the \(medication.refillLeadDays)-day lead time.",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            } else if medication.currentSupply != nil {
                Text("Log taken doses to estimate the run-out date from actual use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !medication.prescriptionNumber.isEmpty {
                LabeledContent("Prescription", value: medication.prescriptionNumber)
            }
            if let fillQuantity = medication.fillQuantity {
                LabeledContent(
                    "Fill quantity",
                    value: fillQuantity.formatted(.number.precision(.fractionLength(0...2)))
                )
            }
            if let refillsRemaining = medication.refillsRemaining {
                LabeledContent("Refills remaining", value: refillsRemaining.description)
            }
            if let expirationDate = medication.prescriptionExpirationDate {
                LabeledContent(
                    "Prescription expires",
                    value: expirationDate.formatted(date: .abbreviated, time: .omitted)
                )
                if expirationDate < Date() {
                    Label("Prescription expiration has passed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if let task = activeRefillTask {
                Divider()
                LabeledContent("Refill status", value: task.status.displayName)
                if let dueDate = task.dueDate {
                    LabeledContent(
                        "Task due",
                        value: dueDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let assignedName = task.assignedCaregiverName {
                    LabeledContent("Assigned to", value: assignedName)
                }
                refillStatusAction(task)
                refillStatusCorrection(task)
                Button("Edit refill task", systemImage: "square.and.pencil") {
                    showingRefillEditor = true
                }
            } else {
                Button("Start Refill Task", systemImage: "pills.circle") {
                    showingRefillEditor = true
                }
            }
            Button("Update supply") {
                supply = medication.currentSupply ?? 0
                supplyReason = .correction
                supplyNotes = ""
                showingSupplyEditor = true
            }
        }
    }

    @ViewBuilder
    private func refillStatusCorrection(_ task: MedicationRefillTask) -> some View {
        switch task.status {
        case .requested:
            Button("Correct to Request Needed", systemImage: "arrow.uturn.backward") {
                updateRefillStatus(task, to: .needsRequest)
            }
        case .readyForPickup:
            Button("Correct to Requested", systemImage: "arrow.uturn.backward") {
                updateRefillStatus(task, to: .requested)
            }
        case .needsRequest, .pickedUp, .cancelled:
            EmptyView()
        }
    }

    @ViewBuilder
    private func refillStatusAction(_ task: MedicationRefillTask) -> some View {
        switch task.status {
        case .needsRequest:
            Button("Mark Requested", systemImage: "paperplane.fill") {
                updateRefillStatus(task, to: .requested)
            }
        case .requested:
            Button("Mark Ready for Pickup", systemImage: "bag.badge.checkmark") {
                updateRefillStatus(task, to: .readyForPickup)
            }
        case .readyForPickup:
            Button("Mark Picked Up", systemImage: "checkmark.circle.fill") {
                refillTaskPendingPickup = task
            }
        case .pickedUp, .cancelled:
            EmptyView()
        }
    }

    @ViewBuilder
    private func tripSupplySection(
        _ risks: [MedicationTripSupplyWarning]
    ) -> some View {
        if !risks.isEmpty {
            Section("Upcoming trip supply") {
                ForEach(risks) { warning in
                    let trip = warning.trip
                    let risk = warning.risk
                    let runOutDate: Date = switch risk {
                    case .beforeTrip(let date), .duringTrip(let date): date
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            tripRiskTitle(risk, trip: trip),
                            systemImage: "suitcase.rolling.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        Text(
                            "Estimated run-out \(runOutDate.formatted(date: .abbreviated, time: .omitted)); trip is \(trip.formattedDate(trip.startDate))–\(trip.formattedDate(trip.endDate))."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func tripRiskTitle(
        _ risk: MedicationTripSupplyRisk,
        trip: PackingTrip
    ) -> String {
        switch risk {
        case .beforeTrip: "May run out before \(trip.title)"
        case .duringTrip: "Will run out during \(trip.title)"
        }
    }

    private func updateRefillStatus(
        _ task: MedicationRefillTask,
        to status: MedicationRefillStatus
    ) {
        guard MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: status,
            context: modelContext
        ) else {
            refillActionMessage = status == .pickedUp
                ? "Enter a fill quantity before marking this refill picked up."
                : "The refill status could not be updated."
            return
        }
        historyRevision += 1
    }

    @ViewBuilder
    private var supplyHistorySection: some View {
        if !supplyLogs.isEmpty {
            Section("Supply history") {
                ForEach(supplyLogs) { log in
                    supplyLogRow(log)
                }
            }
        }
    }

    @ViewBuilder
    private var refillHistorySection: some View {
        let completedTasks = refillTasks.filter { !$0.isOpen }
        if !completedTasks.isEmpty {
            Section("Refill history") {
                ForEach(completedTasks) { task in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(
                                task.status.displayName,
                                systemImage: task.status == .pickedUp
                                    ? "checkmark.circle.fill"
                                    : "xmark.circle"
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let quantity = task.fillQuantity {
                            Text("Fill quantity: \(quantity.formatted(.number.precision(.fractionLength(0...2))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let completedBy = task.completedByCaregiverName {
                            Text("Completed by \(completedBy)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func supplyLogRow(_ log: MedicationSupplyHistoryRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.reason?.displayName ?? "Supply update")
                    .font(.subheadline.weight(.semibold))
                Text(log.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !log.notes.isEmpty {
                    Text(log.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(signedSupplyAdjustment(log.adjustment))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(log.adjustment < 0 ? .secondary : .primary)
                if let resultingSupply = log.resultingSupply {
                    Text("\(resultingSupply.formatted(.number.precision(.fractionLength(0...2)))) left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var supplyEditor: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Quantity on hand") {
                        TextField("Required", value: $supply, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Reason", selection: $supplyReason) {
                        ForEach(supplyUpdateReasons) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    PersistentMultilineFormField(
                        title: "Notes",
                        prompt: "Optional",
                        text: $supplyNotes,
                        lineLimit: 2...4,
                        accessibilityIdentifier: "medication.supply.notes"
                    )
                } header: {
                    Text("Supply on hand")
                } footer: {
                    Text("Enter the total quantity on hand after this change.")
                }
            }
            .navigationTitle("Update Supply")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSupplyEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveSupplyUpdate)
                        .disabled(supply < 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var supplyUpdateReasons: [MedicationSupplyReason] {
        [.correction, .discarded]
    }

    private func saveSupplyUpdate() {
        MedicationService.updateSupply(
            medication: medication,
            newSupply: supply,
            reason: supplyReason,
            notes: supplyNotes,
            context: modelContext
        )
        showingSupplyEditor = false
        historyRevision += 1
    }

    private func loadHistory() async {
        isLoadingHistory = true
        let requestedMedicationID = medication.id
        let worker = MedicationHistoryWorker(modelContainer: modelContext.container)
        let snapshot = await worker.snapshot(medicationID: requestedMedicationID)
        guard !Task.isCancelled, medication.id == requestedMedicationID else { return }
        records = snapshot.doseRecords
        supplyLogs = snapshot.supplyLogs
        planRevisions = snapshot.planRevisions
        isLoadingHistory = false
    }

    private var planReviewSection: some View {
        Section("Plan review") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Status")
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(
                        systemName: medication.isConfirmedCurrent
                            ? "checkmark.seal.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .accessibilityHidden(true)
                    Text(medication.isConfirmedCurrent ? "Confirmed current" : "Needs review")
                }
                .foregroundStyle(medication.isConfirmedCurrent ? .green : .orange)
                .multilineTextAlignment(.trailing)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Status, \(medication.isConfirmedCurrent ? "Confirmed current" : "Needs review")"
            )
            if let lastReviewedAt = medication.lastReviewedAt {
                LabeledContent(
                    "Last reviewed",
                    value: lastReviewedAt.formatted(date: .abbreviated, time: .shortened)
                )
            } else {
                LabeledContent("Last reviewed", value: "Not recorded")
            }
            Button("Reconcile Medications", systemImage: "checkmark.seal") {
                showingReconciliation = true
            }
        }
    }

    @ViewBuilder
    private var planHistorySection: some View {
        if !planRevisions.isEmpty {
            Section("Plan history") {
                ForEach(planRevisions) { revision in
                    NavigationLink {
                        MedicationPlanRevisionDetailView(revision: revision)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(revision.changeKind.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(
                                "Effective \(revision.effectiveFrom.formatted(date: .abbreviated, time: .omitted)) · \(revision.source.displayName)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text("Changed by \(revision.changedByName.nilIfBlank ?? "Caregiver")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func doseHistoryDetail(_ row: MedicationDoseHistoryRow) -> String? {
        var parts = [String]()
        if let actualDoseAmount = row.effectiveActualDoseAmount {
            parts.append(
                "\(actualDoseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(row.doseUnit)"
            )
        }
        if let reason = row.reason {
            parts.append(reason.displayName)
        }
        if !row.notes.isEmpty {
            parts.append(row.notes)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func presentDoseEditor(for row: MedicationDoseHistoryRow) {
        doseEditorConfiguration = MedicationDoseEditorConfiguration(
            medicationID: medication.id,
            regimenID: row.regimenID,
            phaseID: nil,
            occurrenceKey: row.occurrenceKey,
            scheduledAt: row.scheduledAt,
            scheduledDoseAmount: row.doseAmount,
            doseUnit: row.doseUnit,
            medicationName: medication.name,
            recordID: row.id,
            initialEntry: MedicationDoseEntry(
                status: row.status,
                takenAt: row.status == .taken ? (row.takenAt ?? row.loggedAt) : nil,
                actualDoseAmount: row.effectiveActualDoseAmount,
                timing: row.timing,
                reason: row.reason,
                notes: row.notes
            )
        )
    }

    private func saveDoseEdit(
        configuration: MedicationDoseEditorConfiguration,
        entry: MedicationDoseEntry
    ) -> String? {
        guard let recordID = configuration.recordID,
              let record = doseRecord(id: recordID) else {
            return "This dose record changed. Close this form and try again."
        }
        guard MedicationService.updateDoseRecord(
            record,
            medication: medication,
            entry: entry,
            context: modelContext
        ) else {
            return "This dose could not be updated. Please try again."
        }
        historyRevision += 1
        return nil
    }

    private func deleteDoseRecord(_ row: MedicationDoseHistoryRow) {
        guard let record = doseRecord(id: row.id) else {
            historyRevision += 1
            return
        }
        MedicationService.deleteDoseRecord(
            record,
            medication: medication,
            context: modelContext
        )
        historyRevision += 1
    }

    private func doseRecord(id: UUID) -> MedicationDoseRecord? {
        var descriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func signedSupplyAdjustment(_ value: Double) -> String {
        let formatted = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "−\(formatted)" }
        return formatted
    }
}

private struct MedicationPlanRevisionDetailView: View {
    let revision: MedicationPlanRevisionHistoryRow

    var body: some View {
        List {
            Section("Change record") {
                LabeledContent("Action", value: revision.changeKind.displayName)
                LabeledContent(
                    "Effective from",
                    value: revision.effectiveFrom.formatted(date: .abbreviated, time: .omitted)
                )
                LabeledContent("Source", value: revision.source.displayName)
                LabeledContent(
                    "Changed by",
                    value: revision.changedByName.nilIfBlank ?? "Caregiver"
                )
                LabeledContent(
                    "Recorded",
                    value: revision.changedAt.formatted(date: .abbreviated, time: .shortened)
                )
                if revision.appointmentID != nil {
                    Label("Linked to an appointment", systemImage: "calendar.badge.checkmark")
                        .foregroundStyle(.secondary)
                }
                if !revision.notes.isEmpty {
                    Text(revision.notes)
                }
            }

            Section("Before and after") {
                if revision.changes.isEmpty {
                    Text("No plan fields changed. The existing plan was confirmed current.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(revision.changes) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(change.label)
                                .font(.subheadline.weight(.semibold))
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Before")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(change.before)
                                        .font(.caption)
                                }
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 17)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("After")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(change.after)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Plan Change")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MedicationInstructionsFormField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instructions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("medication.instructions.label")

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Optional")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 88)
                    .accessibilityIdentifier("medication.instructions")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MedicationReconciliationEditorRoute: Identifiable {
    let id = UUID()
    let medicationID: UUID?
}

struct MedicationReconciliationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var medications: [Medication]
    @Query private var regimens: [MedicationRegimen]
    @Query private var phases: [MedicationSchedulePhase]
    @Query private var reconciliations: [MedicationReconciliation]

    let profile: CareProfile
    let appointmentID: UUID?

    @State private var source: MedicationPlanChangeSource
    @State private var effectiveFrom: Date
    @State private var notes = ""
    @State private var reviewedMedicationIDs = Set<UUID>()
    @State private var reconciliationID = UUID()
    @State private var editorRoute: MedicationReconciliationEditorRoute?
    @State private var medicationPendingStop: Medication?
    @State private var validationMessage: String?

    init(
        profile: CareProfile,
        appointmentID: UUID? = nil,
        defaultSource: MedicationPlanChangeSource = .caregiver,
        defaultEffectiveFrom: Date = Date()
    ) {
        self.profile = profile
        self.appointmentID = appointmentID
        _source = State(initialValue: defaultSource)
        _effectiveFrom = State(initialValue: min(defaultEffectiveFrom, Date()))
        let profileID = profile.id
        _medications = Query(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\Medication.name)]
        ))
        _regimens = Query(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationRegimen.createdAt)]
        ))
        _phases = Query(FetchDescriptor<MedicationSchedulePhase>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationSchedulePhase.sequence)]
        ))
        _reconciliations = Query(FetchDescriptor<MedicationReconciliation>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationReconciliation.completedAt, order: .reverse)]
        ))
    }

    private var activeMedications: [Medication] {
        medications.filter { !$0.isArchived }
    }

    private var unreviewedMedicationIDs: Set<UUID> {
        Set(activeMedications.map(\.id)).subtracting(reviewedMedicationIDs)
    }

    private var reviewedActiveMedicationCount: Int {
        reviewedMedicationIDs.intersection(Set(activeMedications.map(\.id))).count
    }

    var body: some View {
        List {
            Section {
                DatePicker(
                    "Effective from",
                    selection: $effectiveFrom,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .disabled(!reviewedMedicationIDs.isEmpty)
                Picker("Primary source", selection: $source) {
                    ForEach(MedicationPlanChangeSource.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .disabled(!reviewedMedicationIDs.isEmpty)
                LabeledContent(
                    "Reviewed by",
                    value: CaregiverIdentityService.currentCaregiverName()
                )
                PersistentMultilineFormField(
                    title: "Review notes",
                    prompt: "Optional",
                    text: $notes,
                    lineLimit: 2...5,
                    accessibilityIdentifier: "medication-reconciliation.notes"
                )
                .disabled(!reviewedMedicationIDs.isEmpty)
            } header: {
                Text("Review context")
            } footer: {
                Text(reviewedMedicationIDs.isEmpty
                    ? "Compare every medication with the selected source. Confirm it, update its plan, or mark it stopped."
                    : "Review context is locked after the first medication so every audit entry uses the same source and effective date.")
            }

            Section {
                if activeMedications.isEmpty {
                    ContentUnavailableView(
                        "No current medications",
                        systemImage: "pills",
                        description: Text("Add any medications listed in the source you are reviewing.")
                    )
                } else {
                    ForEach(activeMedications) { medication in
                        reconciliationRow(medication)
                    }
                }
                Button("Add medication from this review", systemImage: "plus.circle.fill") {
                    editorRoute = MedicationReconciliationEditorRoute(medicationID: nil)
                }
            } header: {
                AppSectionHeader(
                    title: "Medication list",
                    subtitle: "\(reviewedActiveMedicationCount) of \(activeMedications.count) reviewed"
                )
            } footer: {
                if !unreviewedMedicationIDs.isEmpty {
                    Text("Review every current medication before finishing.")
                }
            }

            if !reconciliations.isEmpty {
                Section("Reconciliation history") {
                    ForEach(reconciliations) { reconciliation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reconciliation.completedAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(
                                "\(reconciliation.source.displayName) · \(reconciliation.reviewedMedicationIDs.count) medications"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text("Reviewed by \(reconciliation.reviewerName.nilIfBlank ?? "Caregiver")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let notes = reconciliation.notes.nilIfBlank {
                                Text(notes)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button {
                    finishReconciliation()
                } label: {
                    Label("Finish Reconciliation", systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!unreviewedMedicationIDs.isEmpty)
            } footer: {
                Text("Finishing records this review without replacing clinical records or instructions.")
            }
        }
        .navigationTitle("Reconcile Medications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                medicationEditor(for: route)
            }
        }
        .confirmationDialog(
            "Mark this medication stopped?",
            isPresented: Binding(
                get: { medicationPendingStop != nil },
                set: { if !$0 { medicationPendingStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mark Stopped", role: .destructive) {
                guard let medication = medicationPendingStop else { return }
                medicationPendingStop = nil
                stopMedication(medication)
            }
            Button("Cancel", role: .cancel) { medicationPendingStop = nil }
        } message: {
            Text("The current plan will be retired on the effective date and preserved in plan history.")
        }
        .alert("Medication review", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .onDisappear {
            _ = MedicationService.abandonReconciliation(
                id: reconciliationID,
                context: modelContext
            )
        }
    }

    private func reconciliationRow(_ medication: Medication) -> some View {
        let regimen = activeRegimen(for: medication)
        let reviewed = reviewedMedicationIDs.contains(medication.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(medication.name)
                        .font(.subheadline.weight(.semibold))
                    Text([
                        medication.strengthDescription,
                        regimen.map {
                            "\($0.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \($0.doseUnit) · \($0.scheduleSummary)"
                        }
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    reviewed ? "Reviewed" : "Needs review",
                    systemImage: reviewed ? "checkmark.seal.fill" : "exclamationmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(reviewed ? .green : .orange)
            }
            HStack {
                Button(reviewed ? "Confirmed" : "Confirm Current") {
                    confirmMedication(medication)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewed)
                Menu("More") {
                    Button("Update Plan", systemImage: "square.and.pencil") {
                        editorRoute = MedicationReconciliationEditorRoute(
                            medicationID: medication.id
                        )
                    }
                    Button("Mark Stopped", systemImage: "archivebox", role: .destructive) {
                        medicationPendingStop = medication
                    }
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func medicationEditor(for route: MedicationReconciliationEditorRoute) -> some View {
        if let medicationID = route.medicationID,
           let medication = medications.first(where: { $0.id == medicationID }),
           let regimen = activeRegimen(for: medication) {
            MedicationEditorView(
                profile: profile,
                medication: medication,
                regimen: regimen,
                phases: phases.filter { $0.regimenID == regimen.id },
                defaultEffectiveFrom: effectiveFrom,
                defaultChangeSource: source,
                appointmentID: appointmentID,
                reconciliationID: reconciliationID,
                defaultConfirmsCurrent: true,
                onSaved: { reviewedMedicationIDs.insert($0) }
            )
        } else if route.medicationID == nil {
            MedicationEditorView(
                profile: profile,
                defaultEffectiveFrom: effectiveFrom,
                defaultChangeSource: source,
                appointmentID: appointmentID,
                reconciliationID: reconciliationID,
                defaultConfirmsCurrent: true,
                onSaved: { reviewedMedicationIDs.insert($0) }
            )
        } else {
            ContentUnavailableView(
                "Medication changed",
                systemImage: "exclamationmark.triangle",
                description: Text("Close this form and review the refreshed list.")
            )
        }
    }

    private func activeRegimen(for medication: Medication) -> MedicationRegimen? {
        regimens.first { $0.medicationID == medication.id && $0.isActive }
    }

    private func changeContext(confirmsCurrent: Bool) -> MedicationPlanChangeContext {
        MedicationPlanChangeContext(
            effectiveFrom: effectiveFrom,
            source: source,
            appointmentID: appointmentID,
            reconciliationID: reconciliationID,
            notes: notes,
            confirmsCurrent: confirmsCurrent
        )
    }

    private func confirmMedication(_ medication: Medication) {
        guard MedicationService.confirmCurrent(
            medication: medication,
            regimens: regimens,
            changeContext: changeContext(confirmsCurrent: true),
            context: modelContext
        ) else {
            validationMessage = "This medication could not be confirmed. Please try again."
            return
        }
        reviewedMedicationIDs.insert(medication.id)
    }

    private func stopMedication(_ medication: Medication) {
        guard MedicationService.archive(
            medication: medication,
            regimens: regimens,
            changeContext: changeContext(confirmsCurrent: false),
            context: modelContext
        ) else {
            validationMessage = "This medication could not be marked stopped. Please try again."
            return
        }
        reviewedMedicationIDs.insert(medication.id)
    }

    private func finishReconciliation() {
        guard unreviewedMedicationIDs.isEmpty else {
            validationMessage = "Review every current medication before finishing."
            return
        }
        guard MedicationService.completeReconciliation(
            id: reconciliationID,
            profileID: profile.id,
            source: source,
            effectiveFrom: effectiveFrom,
            appointmentID: appointmentID,
            notes: notes,
            reviewedMedicationIDs: Array(reviewedMedicationIDs),
            context: modelContext
        ) != nil else {
            validationMessage = "The reconciliation could not be saved. Please try again."
            return
        }
        dismiss()
    }
}

private struct MedicationRefillAssigneeOption: Identifiable {
    let id: String
    let name: String
}

private struct MedicationRefillEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FamilyCaregiverIdentity.displayName) private var familyCaregivers: [FamilyCaregiverIdentity]

    let profile: CareProfile
    let medication: Medication
    let task: MedicationRefillTask?
    let projection: MedicationSupplyProjection?

    @State private var dueDate: Date
    @State private var fillQuantity: Double?
    @State private var notes: String
    @State private var selectedAssigneeIdentifier: String
    @State private var validationMessage: String?

    init(
        profile: CareProfile,
        medication: Medication,
        task: MedicationRefillTask?,
        projection: MedicationSupplyProjection?
    ) {
        self.profile = profile
        self.medication = medication
        self.task = task
        self.projection = projection
        let suggestedDate = projection.map {
            Calendar.current.date(
                byAdding: .day,
                value: -medication.refillLeadDays,
                to: $0.estimatedRunOutDate
            ) ?? $0.estimatedRunOutDate
        } ?? Date()
        _dueDate = State(initialValue: task?.dueDate ?? max(suggestedDate, Date()))
        _fillQuantity = State(initialValue: task?.fillQuantity ?? medication.fillQuantity)
        _notes = State(initialValue: task?.notes ?? "")
        _selectedAssigneeIdentifier = State(initialValue:
            task?.assignedCaregiverIdentifier
                ?? CaregiverIdentityService.stableCaregiverIdentifier()
        )
    }

    private var assigneeOptions: [MedicationRefillAssigneeOption] {
        let current = MedicationRefillAssigneeOption(
            id: CaregiverIdentityService.stableCaregiverIdentifier(),
            name: CaregiverIdentityService.currentCaregiverName()
        )
        let options = [current] + familyCaregivers.map {
            MedicationRefillAssigneeOption(id: $0.caregiverIdentifier, name: $0.displayName)
        }
        return Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedAssignee: MedicationRefillAssigneeOption? {
        assigneeOptions.first { $0.id == selectedAssigneeIdentifier }
    }

    var body: some View {
        Form {
            Section {
                if let task {
                    LabeledContent("Status", value: task.status.displayName)
                }
                DatePicker("Task due", selection: $dueDate, displayedComponents: .date)
                Picker("Assigned to", selection: $selectedAssigneeIdentifier) {
                    Text("Unassigned").tag("")
                    ForEach(assigneeOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                LabeledContent("Fill quantity") {
                    TextField("Required for pickup", value: $fillQuantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                PersistentMultilineFormField(
                    title: "Notes",
                    prompt: "Optional pharmacy or pickup details",
                    text: $notes,
                    lineLimit: 2...5,
                    accessibilityIdentifier: "medication.refill.notes"
                )
            } header: {
                Text("Refill task")
            } footer: {
                Text("This task appears in Home → Needs attention and can be reassigned as it moves from request to pickup.")
            }

            Section("Prescription") {
                LabeledContent(
                    "Prescription number",
                    value: medication.prescriptionNumber.nilIfBlank ?? "Not entered"
                )
                LabeledContent(
                    "Pharmacy",
                    value: medication.pharmacy.nilIfBlank ?? "Not entered"
                )
                if let refillsRemaining = medication.refillsRemaining {
                    LabeledContent("Refills remaining", value: refillsRemaining.description)
                }
                if let expirationDate = medication.prescriptionExpirationDate {
                    LabeledContent(
                        "Expires",
                        value: expirationDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let projection {
                    LabeledContent(
                        "Estimated run-out",
                        value: projection.estimatedRunOutDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    LabeledContent(
                        "Lead time",
                        value: "\(medication.refillLeadDays) days"
                    )
                }
            }

            if let task {
                Section {
                    Button("Cancel Refill Task", role: .destructive) {
                        cancel(task)
                    }
                }
            }
        }
        .navigationTitle(task == nil ? "Start Refill" : "Edit Refill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
            }
        }
        .alert("Check refill", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private func save() {
        if fillQuantity.map({ !$0.isFinite || $0 <= 0 }) == true {
            validationMessage = "Fill quantity must be greater than zero."
            return
        }
        let assignee = selectedAssigneeIdentifier.isEmpty ? nil : selectedAssignee
        let saved: Bool
        if let task {
            saved = MedicationService.updateRefillTask(
                task,
                medication: medication,
                dueDate: dueDate,
                fillQuantity: fillQuantity,
                assignedCaregiverIdentifier: assignee?.id,
                assignedCaregiverName: assignee?.name,
                notes: notes,
                context: modelContext
            )
        } else {
            let household = HouseholdService.ensureDefaultHousehold(context: modelContext)
            saved = MedicationService.createRefillTask(
                medication: medication,
                householdID: household.id,
                dueDate: dueDate,
                fillQuantity: fillQuantity,
                assignedCaregiverIdentifier: assignee?.id,
                assignedCaregiverName: assignee?.name,
                notes: notes,
                context: modelContext
            ) != nil
        }
        guard saved else {
            validationMessage = task == nil
                ? "A refill task could not be created. Check for another open refill."
                : "The refill task could not be updated."
            return
        }
        if profile.sharingScope == .family,
           PersistenceService.familySyncMode() == .sharedFamilySync {
            let medicationID = medication.id
            let savedTask = task ?? ((try? modelContext.fetch(FetchDescriptor<MedicationRefillTask>(
                predicate: #Predicate { $0.medicationID == medicationID }
            ))) ?? []).first(where: \.isOpen)
            if let savedTask {
                if let assignee {
                    _ = HouseholdAttentionService.claim(
                        sourceKey: savedTask.attentionSourceKey,
                        householdID: savedTask.householdID,
                        profileID: savedTask.profileID,
                        caregiverIdentifier: assignee.id,
                        caregiverName: assignee.name,
                        context: modelContext
                    )
                } else {
                    _ = HouseholdAttentionService.clearClaim(
                        sourceKey: savedTask.attentionSourceKey,
                        householdID: savedTask.householdID,
                        profileID: savedTask.profileID,
                        context: modelContext
                    )
                }
            }
        }
        dismiss()
    }

    private func cancel(_ task: MedicationRefillTask) {
        guard MedicationService.setRefillStatus(
            task,
            medication: medication,
            status: .cancelled,
            context: modelContext
        ) else {
            validationMessage = "The refill task could not be cancelled."
            return
        }
        dismiss()
    }
}

private struct MedicationEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let profile: CareProfile
    let medication: Medication?
    let regimen: MedicationRegimen?
    let appointmentID: UUID?
    let reconciliationID: UUID?
    let onSaved: ((UUID) -> Void)?

    @State private var name = ""
    @State private var form: MedicationForm = .tablet
    @State private var strength: Double?
    @State private var strengthUnit = "mg"
    @State private var route: MedicationRoute = .oral
    @State private var instructions = ""
    @State private var reasonForTaking = ""
    @State private var prescriber = ""
    @State private var pharmacy = ""
    @State private var tracksSupply = false
    @State private var currentSupply = 0.0
    @State private var refillThreshold = 5.0
    @State private var refillLeadDays = 7
    @State private var prescriptionNumber = ""
    @State private var fillQuantity: Double?
    @State private var refillsRemaining: Int?
    @State private var tracksPrescriptionExpiration = false
    @State private var prescriptionExpirationDate = Calendar.current.date(
        byAdding: .year,
        value: 1,
        to: Date()
    ) ?? Date()

    @State private var scheduleKind: MedicationScheduleKind = .daily
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var doseAmount = 1.0
    @State private var doseUnit: MedicationDoseUnit = .tablet
    @State private var doseTimes = [Calendar.current.date(from: DateComponents(hour: 8)) ?? Date()]
    @State private var weekdayMask = 127
    @State private var intervalDays = 2
    @State private var cycleOnDays = 21
    @State private var cycleOffDays = 7
    @State private var alternateDose = 2.0
    @State private var alternateEveryDays = 1
    @State private var taperStepDays = 3
    @State private var taperPhaseCount = 3
    @State private var taperReduction = 0.5
    @State private var minimumHoursBetweenDoses = 6.0
    @State private var maximumDosesPerDay = 4
    @State private var remindersEnabled = false
    @State private var followUpRemindersEnabled = false
    @State private var timeZoneBehavior: MedicationTimeZoneBehavior = .localTime
    @State private var changeSource: MedicationPlanChangeSource = .caregiver
    @State private var changeNotes = ""
    @State private var confirmsCurrent = false
    @State private var validationMessage: String?

    init(
        profile: CareProfile,
        medication: Medication? = nil,
        regimen: MedicationRegimen? = nil,
        phases: [MedicationSchedulePhase] = [],
        defaultEffectiveFrom: Date? = nil,
        defaultChangeSource: MedicationPlanChangeSource = .caregiver,
        appointmentID: UUID? = nil,
        reconciliationID: UUID? = nil,
        defaultConfirmsCurrent: Bool = false,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.profile = profile
        self.medication = medication
        self.regimen = regimen
        self.appointmentID = appointmentID
        self.reconciliationID = reconciliationID
        self.onSaved = onSaved
        _name = State(initialValue: medication?.name ?? "")
        _form = State(initialValue: medication?.form ?? .tablet)
        _strength = State(initialValue: medication?.strength)
        _strengthUnit = State(initialValue: medication?.strengthUnit ?? "mg")
        _route = State(initialValue: medication?.route ?? .oral)
        _instructions = State(initialValue: medication?.instructions ?? "")
        _reasonForTaking = State(initialValue: medication?.reasonForTaking ?? "")
        _prescriber = State(initialValue: medication?.prescriber ?? "")
        _pharmacy = State(initialValue: medication?.pharmacy ?? "")
        _tracksSupply = State(initialValue: medication?.currentSupply != nil)
        _currentSupply = State(initialValue: medication?.currentSupply ?? 0)
        _refillThreshold = State(initialValue: medication?.refillThreshold ?? 5)
        _refillLeadDays = State(initialValue: medication?.refillLeadDays ?? 7)
        _prescriptionNumber = State(initialValue: medication?.prescriptionNumber ?? "")
        _fillQuantity = State(initialValue: medication?.fillQuantity)
        _refillsRemaining = State(initialValue: medication?.refillsRemaining)
        _tracksPrescriptionExpiration = State(
            initialValue: medication?.prescriptionExpirationDate != nil
        )
        _prescriptionExpirationDate = State(initialValue:
            medication?.prescriptionExpirationDate
                ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())
                ?? Date()
        )

        let displayCalendar = MedicationScheduleDate.currentCalendar()
        _scheduleKind = State(initialValue: regimen?.scheduleKind ?? .daily)
        let effectiveFrom = min(defaultEffectiveFrom ?? Date(), Date())
        _startDate = State(initialValue: effectiveFrom)
        let existingEndDate = regimen?.endDate.map {
            MedicationScheduleDate.displayDate(
                for: $0,
                anchorTimeZoneIdentifier: regimen?.timeZoneIdentifier,
                calendar: displayCalendar
            )
        }
        _endDate = State(initialValue: max(
            existingEndDate ?? displayCalendar.date(byAdding: .day, value: 7, to: effectiveFrom) ?? effectiveFrom,
            effectiveFrom
        ))
        _doseAmount = State(initialValue: regimen?.doseAmount ?? 1)
        _doseUnit = State(
            initialValue: regimen
                .flatMap { MedicationDoseUnit(rawValue: $0.doseUnit) }
                ?? MedicationDoseUnit.defaultUnit(for: medication?.form ?? .tablet)
        )
        let existingTimes = regimen?.doseTimes.compactMap { value in
            displayCalendar.date(from: DateComponents(hour: value.hour, minute: value.minute))
        } ?? []
        _doseTimes = State(initialValue: existingTimes.isEmpty
            ? [displayCalendar.date(from: DateComponents(hour: 8)) ?? Date()]
            : existingTimes)
        _weekdayMask = State(initialValue: regimen?.weekdayMask ?? 127)
        _intervalDays = State(initialValue: regimen?.intervalDays ?? 2)
        _cycleOnDays = State(initialValue: regimen?.cycleOnDays ?? 21)
        _cycleOffDays = State(initialValue: regimen?.cycleOffDays ?? 7)
        _minimumHoursBetweenDoses = State(initialValue: regimen?.minimumHoursBetweenDoses ?? 6)
        _maximumDosesPerDay = State(initialValue: regimen?.maximumDosesPerDay ?? 4)
        _remindersEnabled = State(initialValue: regimen?.remindersEnabled ?? false)
        _followUpRemindersEnabled = State(initialValue: regimen?.followUpRemindersEnabled ?? false)
        _timeZoneBehavior = State(initialValue: regimen?.timeZoneBehavior ?? .localTime)
        _changeSource = State(initialValue: defaultChangeSource)
        _confirmsCurrent = State(initialValue: defaultConfirmsCurrent)

        let sortedPhases = phases.sorted { $0.sequence < $1.sequence }
        _alternateDose = State(initialValue: sortedPhases.dropFirst().first?.doseAmount ?? 2)
        _alternateEveryDays = State(initialValue: sortedPhases.first?.durationDays ?? 1)
        _taperStepDays = State(initialValue: sortedPhases.first?.durationDays ?? 3)
        _taperPhaseCount = State(initialValue: max(sortedPhases.count, 3))
        let taperReduction = if sortedPhases.count >= 2 {
            max(sortedPhases[0].doseAmount - sortedPhases[1].doseAmount, 0.1)
        } else {
            0.5
        }
        _taperReduction = State(initialValue: taperReduction)
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Effective from",
                    selection: $startDate,
                    in: earliestEffectiveDate...Date(),
                    displayedComponents: .date
                )
                .environment(\.timeZone, scheduleTimeZone)
                Picker("Source", selection: $changeSource) {
                    ForEach(MedicationPlanChangeSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                LabeledContent(
                    "Changed by",
                    value: CaregiverIdentityService.currentCaregiverName()
                )
                Toggle("Confirmed current", isOn: $confirmsCurrent)
                PersistentMultilineFormField(
                    title: "Change notes",
                    prompt: "Optional context",
                    text: $changeNotes,
                    lineLimit: 2...5,
                    accessibilityIdentifier: "medication.change.notes"
                )
            } header: {
                Text("Change record")
            } footer: {
                Text("The prior plan stays in medication history. Confirm current only after checking this source.")
            }

            Section("Medication") {
                LabeledContent("Name") {
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Form", selection: $form) {
                    ForEach(MedicationForm.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("medication.form")
                LabeledContent("Strength") {
                    TextField("Optional", value: $strength, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Strength unit") {
                    TextField("Optional", text: $strengthUnit)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Route", selection: $route) {
                    ForEach(MedicationRoute.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Purpose") {
                    TextField("Optional", text: $reasonForTaking)
                        .multilineTextAlignment(.trailing)
                }
                MedicationInstructionsFormField(text: $instructions)
            }

            Section("Schedule") {
                Picker("Pattern", selection: $scheduleKind) {
                    ForEach(MedicationScheduleKind.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Dose") {
                    TextField("Required", value: $doseAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Dose unit", selection: $doseUnit) {
                    ForEach(MedicationDoseUnit.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .accessibilityIdentifier("medication.dose-unit")
                scheduleFields
            }

            if scheduleKind.isScheduled {
                Section("Dose times") {
                    ForEach(doseTimes.indices, id: \.self) { index in
                        DatePicker(
                            "Dose \(index + 1)",
                            selection: $doseTimes[index],
                            displayedComponents: .hourAndMinute
                        )
                        .environment(\.timeZone, scheduleTimeZone)
                    }
                    .onDelete { doseTimes.remove(atOffsets: $0) }
                    if doseTimes.count < 6 {
                        Button("Add another time", systemImage: "plus.circle") {
                            doseTimes.append(scheduleCalendar.date(from: DateComponents(hour: 20)) ?? Date())
                        }
                    }
                }

                Section {
                    Toggle("Dose reminders", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Toggle("Follow up if not logged", isOn: $followUpRemindersEnabled)
                        Picker("When traveling", selection: $timeZoneBehavior) {
                            ForEach(MedicationTimeZoneBehavior.allCases) { Text($0.displayName).tag($0) }
                        }
                        if timeZoneBehavior == .fixedTimeZone {
                            LabeledContent(
                                "Home time zone",
                                value: CareTimeZoneSettings.displayName(
                                    for: regimen?.timeZoneIdentifier
                                        .flatMap(TimeZone.init(identifier:))
                                        ?? scheduleTimeZone
                                )
                            )
                        }
                    }
                } footer: {
                    Text("Reminders are a convenience. Always follow the medication label or care team instructions.")
                }
            }

            Section("Supply and refill") {
                Toggle("Track quantity on hand", isOn: $tracksSupply)
                if tracksSupply {
                    LabeledContent("Quantity on hand") {
                        TextField("Required", value: $currentSupply, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Refill alert at") {
                        TextField("Required", value: $refillThreshold, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Stepper(
                    "Start refill \(refillLeadDays) day\(refillLeadDays == 1 ? "" : "s") early",
                    value: $refillLeadDays,
                    in: 0...60
                )
            }

            Section {
                LabeledContent("Prescription number") {
                    TextField("Optional", text: $prescriptionNumber)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                }
                LabeledContent("Fill quantity") {
                    TextField("Optional", value: $fillQuantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Refills remaining") {
                    TextField("Optional", value: $refillsRemaining, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Track prescription expiration", isOn: $tracksPrescriptionExpiration)
                if tracksPrescriptionExpiration {
                    DatePicker(
                        "Prescription expires",
                        selection: $prescriptionExpirationDate,
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Prescription and fills")
            } footer: {
                Text("These details support refill planning; verify them against the prescription label or pharmacy.")
            }

            Section("Care team (optional)") {
                LabeledContent("Prescriber") {
                    TextField("Optional", text: $prescriber)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Pharmacy") {
                    TextField("Optional", text: $pharmacy)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .navigationTitle(medication == nil ? "Add Medication" : "Edit Medication")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .alert("Check medication", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .onChange(of: form) { oldForm, newForm in
            guard doseUnit == MedicationDoseUnit.defaultUnit(for: oldForm) else { return }
            doseUnit = MedicationDoseUnit.defaultUnit(for: newForm)
        }
    }

    private var scheduleCalendar: Calendar {
        MedicationScheduleDate.currentCalendar()
    }

    private var scheduleTimeZone: TimeZone {
        scheduleCalendar.timeZone
    }

    private var earliestEffectiveDate: Date {
        guard let regimen else { return Date.distantPast }
        return MedicationScheduleDate.displayDate(
            for: regimen.startDate,
            anchorTimeZoneIdentifier: regimen.timeZoneIdentifier,
            calendar: scheduleCalendar
        )
    }

    @ViewBuilder
    private var scheduleFields: some View {
        switch scheduleKind {
        case .daily:
            EmptyView()
        case .specificWeekdays:
            weekdayPicker
        case .everyNDays:
            Stepper("Every \(intervalDays) days", value: $intervalDays, in: 2...30)
        case .fixedCourse:
            DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                .environment(\.timeZone, scheduleTimeZone)
        case .cycle:
            Stepper("\(cycleOnDays) days on", value: $cycleOnDays, in: 1...90)
            Stepper("\(cycleOffDays) days off", value: $cycleOffDays, in: 1...90)
        case .alternating:
            Stepper("Switch every \(alternateEveryDays) day(s)", value: $alternateEveryDays, in: 1...14)
            LabeledContent("Alternate dose") {
                TextField("Required", value: $alternateDose, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        case .taper:
            Stepper("\(taperPhaseCount) phases", value: $taperPhaseCount, in: 2...12)
            Stepper("Change every \(taperStepDays) days", value: $taperStepDays, in: 1...30)
            LabeledContent("Reduction per phase") {
                TextField("Required", value: $taperReduction, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        case .asNeeded:
            Stepper("At least \(minimumHoursBetweenDoses.formatted(.number.precision(.fractionLength(0...1)))) hours apart", value: $minimumHoursBetweenDoses, in: 0.5...48, step: 0.5)
            Stepper("Up to \(maximumDosesPerDay) doses per day", value: $maximumDosesPerDay, in: 1...24)
        }
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                let bit = 1 << index
                Button {
                    weekdayMask ^= bit
                } label: {
                    Text(symbol)
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(weekdayMask & bit != 0 ? AppTheme.accent : Color.secondary.opacity(0.12), in: Circle())
                        .foregroundStyle(weekdayMask & bit != 0 ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[index])
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter the medication name."
            return
        }
        guard doseAmount > 0 else {
            validationMessage = "Enter a dose greater than zero."
            return
        }
        if let strength, strength <= 0 {
            validationMessage = "Medication strength must be greater than zero."
            return
        }
        if strength != nil,
           strengthUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "Enter the medication strength unit."
            return
        }
        if tracksSupply && (currentSupply < 0 || refillThreshold < 0) {
            validationMessage = "Supply and refill values cannot be negative."
            return
        }
        if fillQuantity.map({ !$0.isFinite || $0 <= 0 }) == true {
            validationMessage = "Fill quantity must be greater than zero."
            return
        }
        if refillsRemaining.map({ $0 < 0 }) == true {
            validationMessage = "Refills remaining cannot be negative."
            return
        }
        if scheduleKind.isScheduled && doseTimes.isEmpty {
            validationMessage = "Add at least one dose time."
            return
        }
        let times = doseTimes.map { MedicationDoseTime(date: $0, calendar: scheduleCalendar) }
        if scheduleKind.isScheduled && Set(times).count != times.count {
            validationMessage = "Each dose time must be unique."
            return
        }
        if scheduleKind == .specificWeekdays && weekdayMask == 0 {
            validationMessage = "Choose at least one weekday."
            return
        }
        if scheduleKind == .taper && taperReduction <= 0 {
            validationMessage = "Enter a taper reduction greater than zero."
            return
        }
        if scheduleKind == .taper,
           doseAmount - Double(taperPhaseCount - 1) * taperReduction <= 0 {
            validationMessage = "Adjust the taper so every phase has a dose greater than zero."
            return
        }
        if scheduleKind == .alternating && alternateDose <= 0 {
            validationMessage = "Enter an alternate dose greater than zero."
            return
        }

        let normalizedDoseUnit = doseUnit.rawValue
        let changeContext = MedicationPlanChangeContext(
            effectiveFrom: startDate,
            source: changeSource,
            appointmentID: appointmentID,
            reconciliationID: reconciliationID,
            notes: changeNotes,
            confirmsCurrent: confirmsCurrent
        )
        let savedMedicationID: UUID
        if let medication, let regimen {
            guard MedicationService.updateMedication(
                medication: medication,
                regimen: regimen,
                name: trimmedName,
                form: form,
                strength: strength,
                strengthUnit: strengthUnit,
                route: route,
                instructions: instructions,
                reasonForTaking: reasonForTaking,
                prescriber: prescriber,
                pharmacy: pharmacy,
                currentSupply: tracksSupply ? currentSupply : nil,
                refillThreshold: tracksSupply ? refillThreshold : nil,
                refillLeadDays: refillLeadDays,
                prescriptionNumber: prescriptionNumber,
                fillQuantity: fillQuantity,
                refillsRemaining: refillsRemaining,
                prescriptionExpirationDate: tracksPrescriptionExpiration
                    ? prescriptionExpirationDate
                    : nil,
                scheduleKind: scheduleKind,
                startDate: startDate,
                endDate: scheduleKind == .fixedCourse ? endDate : nil,
                doseAmount: doseAmount,
                doseUnit: normalizedDoseUnit,
                doseTimes: times,
                weekdayMask: weekdayMask,
                intervalDays: intervalDays,
                cycleOnDays: cycleOnDays,
                cycleOffDays: cycleOffDays,
                minimumHoursBetweenDoses: scheduleKind == .asNeeded ? minimumHoursBetweenDoses : nil,
                maximumDosesPerDay: scheduleKind == .asNeeded ? maximumDosesPerDay : nil,
                remindersEnabled: scheduleKind.isScheduled && remindersEnabled,
                followUpRemindersEnabled: scheduleKind.isScheduled && remindersEnabled && followUpRemindersEnabled,
                timeZoneBehavior: timeZoneBehavior,
                phases: schedulePhases,
                changeContext: changeContext,
                context: modelContext
            ) != nil else {
                validationMessage = "The medication plan could not be saved. Please try again."
                return
            }
            savedMedicationID = medication.id
        } else {
            let medication = MedicationService.createMedication(
                profileID: profile.id,
                name: trimmedName,
                form: form,
                strength: strength,
                strengthUnit: strengthUnit,
                route: route,
                instructions: instructions,
                reasonForTaking: reasonForTaking,
                prescriber: prescriber,
                pharmacy: pharmacy,
                currentSupply: tracksSupply ? currentSupply : nil,
                refillThreshold: tracksSupply ? refillThreshold : nil,
                refillLeadDays: refillLeadDays,
                prescriptionNumber: prescriptionNumber,
                fillQuantity: fillQuantity,
                refillsRemaining: refillsRemaining,
                prescriptionExpirationDate: tracksPrescriptionExpiration
                    ? prescriptionExpirationDate
                    : nil,
                context: modelContext
            )
            guard MedicationService.createRegimen(
                for: medication,
                scheduleKind: scheduleKind,
                startDate: startDate,
                endDate: scheduleKind == .fixedCourse ? endDate : nil,
                doseAmount: doseAmount,
                doseUnit: normalizedDoseUnit,
                doseTimes: times,
                weekdayMask: weekdayMask,
                intervalDays: intervalDays,
                cycleOnDays: cycleOnDays,
                cycleOffDays: cycleOffDays,
                minimumHoursBetweenDoses: scheduleKind == .asNeeded ? minimumHoursBetweenDoses : nil,
                maximumDosesPerDay: scheduleKind == .asNeeded ? maximumDosesPerDay : nil,
                remindersEnabled: scheduleKind.isScheduled && remindersEnabled,
                followUpRemindersEnabled: scheduleKind.isScheduled && remindersEnabled && followUpRemindersEnabled,
                timeZoneBehavior: timeZoneBehavior,
                phases: schedulePhases,
                changeContext: changeContext,
                context: modelContext
            ) != nil else {
                validationMessage = "The medication plan could not be saved. Please try again."
                return
            }
            savedMedicationID = medication.id
        }
        onSaved?(savedMedicationID)
        dismiss()
    }

    private var schedulePhases: [(durationDays: Int?, doseAmount: Double)] {
        switch scheduleKind {
        case .alternating:
            return [
                (alternateEveryDays, doseAmount),
                (alternateEveryDays, alternateDose)
            ]
        case .taper:
            return (0..<taperPhaseCount).compactMap { index in
                let phaseDose = doseAmount - Double(index) * taperReduction
                guard phaseDose > 0 else { return nil }
                return (taperStepDays, phaseDose)
            }
        default:
            return []
        }
    }
}
