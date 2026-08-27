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
    var futureOccurrences: [MedicationOccurrence]
    var asNeededRegimens: [MedicationRegimen]
}

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allMedications: [Medication]
    @Query private var allRegimens: [MedicationRegimen]
    @Query private var allPhases: [MedicationSchedulePhase]
    @Query private var allDoseRecords: [MedicationDoseRecord]
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared

    let profile: CareProfile
    @State private var showingEditor = false
    @State private var actionMessage: String?

    init(profile: CareProfile) {
        self.profile = profile
        let profileID = profile.id
        let calendar = MedicationScheduleDate.currentCalendar()
        let currentDay = calendar.startOfDay(for: Date())
        let relevantRecordStart = calendar.date(byAdding: .day, value: -2, to: currentDay) ?? currentDay
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
        let regimenByID = Dictionary(uniqueKeysWithValues: activeRegimens.map { ($0.id, $0) })
        let regimensByMedicationID = Dictionary(grouping: activeRegimens, by: \.medicationID)
        let phasesByRegimenID = Dictionary(grouping: allPhases, by: \.regimenID)
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
            upcomingSection(dashboard)
            archivedSection(dashboard)
            safetySection
        }
        .navigationTitle("Medications")
        .toolbar {
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
                                logAsNeeded(
                                    medication: medication,
                                    regimen: regimen,
                                    records: dashboard.records
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
                            MedicationService.restore(
                                medication: medication,
                                regimens: allRegimens,
                                context: modelContext
                            )
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
                        Label(record.status.displayName, systemImage: record.status == .taken ? "checkmark.circle.fill" : "minus.circle.fill")
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
                        Button("Skip") {
                            recordScheduledDose(
                                occurrence,
                                medication: medication,
                                regimen: regimen,
                                status: .skipped
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

    private func logAsNeeded(
        medication: Medication,
        regimen: MedicationRegimen,
        records: [MedicationDoseRecord]
    ) {
        switch MedicationScheduleEngine.asNeededDecision(
            regimen: regimen,
            records: records
        ) {
        case .allowed:
            MedicationService.recordDose(
                medication: medication,
                regimen: regimen,
                status: .taken,
                context: modelContext
            )
        case .waitUntil(let date):
            actionMessage = "Based on the interval you entered, the next dose is due after \(date.formatted(date: .omitted, time: .shortened)). Check the medication instructions if plans changed."
        case .dailyLimitReached(let maximum):
            actionMessage = "The daily limit you entered is \(maximum) doses. Check the medication instructions before logging another dose."
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
        switch MedicationService.recordScheduledDose(
            reference,
            status: command.status,
            context: modelContext
        ) {
        case .applied(let medicationName):
            actionMessage = "Recorded \(medicationName) as \(command.status.displayName.lowercased())."
        case .duplicate(let medicationName):
            actionMessage = "\(medicationName) was already recorded as \(command.status.displayName.lowercased())."
        case .rejected(let message):
            actionMessage = message
        }
    }
}

private struct MedicationDoseHistoryRow: Identifiable, Sendable {
    let id: UUID
    let occurrenceKey: String?
    let statusRawValue: String
    let loggedAt: Date
    let takenAt: Date?
    let scheduledAt: Date?

    var status: MedicationDoseStatus? {
        MedicationDoseStatus(rawValue: statusRawValue)
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

private struct MedicationHistorySnapshot: Sendable {
    let doseRecords: [MedicationDoseHistoryRow]
    let supplyLogs: [MedicationSupplyHistoryRow]
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
                occurrenceKey: $0.occurrenceKey,
                statusRawValue: $0.statusRawValue,
                loggedAt: $0.loggedAt,
                takenAt: $0.takenAt,
                scheduledAt: $0.scheduledAt
            )
        }

        var supplyDescriptor = FetchDescriptor<MedicationSupplyLog>(
            predicate: #Predicate { $0.medicationID == medicationID },
            sortBy: [SortDescriptor(\MedicationSupplyLog.loggedAt, order: .reverse)]
        )
        supplyDescriptor.fetchLimit = 30
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

        return MedicationHistorySnapshot(
            doseRecords: doseRecords,
            supplyLogs: supplyLogs
        )
    }
}

private struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
    @State private var isLoadingHistory = true
    @State private var historyRevision = 0
    @State private var doseRecordToDelete: MedicationDoseHistoryRow?
    @State private var showingArchiveConfirmation = false

    private var activeRegimen: MedicationRegimen? { regimens.first { $0.isActive } }

    private var scheduleCalendar: Calendar {
        MedicationScheduleDate.currentCalendar()
    }

    private var adherence: MedicationAdherenceSummary? {
        guard !isLoadingHistory,
              let regimen = activeRegimen,
              regimen.scheduleKind.isScheduled else { return nil }
        let start = scheduleCalendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: phases,
            from: start,
            through: Date(),
            calendar: scheduleCalendar
        )
        let recordsByKey = Dictionary(
            records.compactMap { record -> (String, MedicationDoseStatus)? in
                guard let occurrenceKey = record.occurrenceKey,
                      let status = record.status else { return nil }
                return (occurrenceKey, status)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let expected = occurrences.filter { $0.scheduledAt <= Date() }
        let taken = expected.filter { recordsByKey[$0.occurrenceKey] == .taken }.count
        let skipped = expected.filter { recordsByKey[$0.occurrenceKey] == .skipped }.count
        return MedicationAdherenceSummary(
            scheduledCount: expected.count,
            takenCount: taken,
            skippedCount: skipped,
            missedCount: max(expected.count - taken - skipped, 0)
        )
    }

    var body: some View {
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
            if let adherence, let rate = adherence.completionRate {
                Section("Last 30 days") {
                    LabeledContent("Taken", value: "\(adherence.takenCount) of \(adherence.scheduledCount)")
                    LabeledContent("Completion", value: rate.formatted(.percent.precision(.fractionLength(0))))
                    LabeledContent("Skipped", value: adherence.skippedCount.description)
                    LabeledContent("Not logged", value: adherence.missedCount.description)
                }
            }
            Section("Supply") {
                if let current = medication.currentSupply {
                    LabeledContent("Remaining", value: current.formatted(.number.precision(.fractionLength(0...2))))
                } else {
                    Text("Supply tracking is off")
                        .foregroundStyle(.secondary)
                }
                Button("Update supply") {
                    supply = medication.currentSupply ?? 0
                    supplyReason = .correction
                    supplyNotes = ""
                    showingSupplyEditor = true
                }
            }
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
                            Label(
                                record.status?.displayName ?? "Unknown status",
                                systemImage: record.status == .taken
                                    ? "checkmark.circle.fill"
                                    : "minus.circle"
                            )
                                .foregroundStyle(record.status == .taken ? .green : .secondary)
                            Spacer()
                            Text(record.displayDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Menu("Dose actions", systemImage: "ellipsis.circle") {
                                Button(record.status == .taken ? "Change to Skipped" : "Change to Taken") {
                                    updateDoseRecord(
                                        record,
                                        status: record.status == .taken ? .skipped : .taken
                                    )
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
                        phases: phases.filter { $0.regimenID == activeRegimen.id }
                    )
                }
            }
        }
        .sheet(isPresented: $showingSupplyEditor) {
            supplyEditor
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
                    MedicationService.archive(
                        medication: medication,
                        regimens: regimens,
                        context: modelContext
                    )
                    dismiss()
                }
            ]
        )
        .task(id: historyRevision) {
            await loadHistory()
        }
    }

    @ViewBuilder
    private var supplyHistorySection: some View {
        if !supplyLogs.isEmpty {
            Section("Supply history") {
                ForEach(supplyLogs.prefix(30)) { log in
                    supplyLogRow(log)
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
        [.refill, .correction, .discarded]
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
        isLoadingHistory = false
    }

    private func updateDoseRecord(
        _ row: MedicationDoseHistoryRow,
        status: MedicationDoseStatus
    ) {
        guard let record = doseRecord(id: row.id) else {
            historyRevision += 1
            return
        }
        MedicationService.updateDoseRecordStatus(
            record,
            medication: medication,
            status: status,
            context: modelContext
        )
        historyRevision += 1
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

private struct MedicationEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let profile: CareProfile
    let medication: Medication?
    let regimen: MedicationRegimen?

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
    @State private var validationMessage: String?

    init(
        profile: CareProfile,
        medication: Medication? = nil,
        regimen: MedicationRegimen? = nil,
        phases: [MedicationSchedulePhase] = []
    ) {
        self.profile = profile
        self.medication = medication
        self.regimen = regimen
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

        let displayCalendar = MedicationScheduleDate.currentCalendar()
        _scheduleKind = State(initialValue: regimen?.scheduleKind ?? .daily)
        _startDate = State(initialValue: regimen.map {
            MedicationScheduleDate.displayDate(
                for: $0.startDate,
                anchorTimeZoneIdentifier: $0.timeZoneIdentifier,
                calendar: displayCalendar
            )
        } ?? Date())
        _endDate = State(initialValue: regimen?.endDate.map {
            MedicationScheduleDate.displayDate(
                for: $0,
                anchorTimeZoneIdentifier: regimen?.timeZoneIdentifier,
                calendar: displayCalendar
            )
        } ?? displayCalendar.date(byAdding: .day, value: 7, to: Date()) ?? Date())
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
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    .environment(\.timeZone, scheduleTimeZone)
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
        if let medication, let regimen {
            MedicationService.updateMedication(
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
                context: modelContext
            )
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
                context: modelContext
            )
            MedicationService.createRegimen(
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
                context: modelContext
            )
        }
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
