import SwiftData
import SwiftUI

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var allMedications: [Medication]
    @Query(sort: \MedicationRegimen.createdAt) private var allRegimens: [MedicationRegimen]
    @Query(sort: \MedicationSchedulePhase.sequence) private var allPhases: [MedicationSchedulePhase]
    @Query(sort: \MedicationDoseRecord.loggedAt, order: .reverse) private var allDoseRecords: [MedicationDoseRecord]
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared

    let profile: CareProfile
    @State private var showingEditor = false
    @State private var actionMessage: String?

    private var medications: [Medication] {
        allMedications.filter { $0.profileID == profile.id && !$0.isArchived }
    }

    private var archivedMedications: [Medication] {
        allMedications.filter { $0.profileID == profile.id && $0.isArchived }
    }

    private var regimens: [MedicationRegimen] {
        allRegimens.filter { $0.profileID == profile.id && $0.isActive }
    }

    private var records: [MedicationDoseRecord] {
        allDoseRecords.filter { $0.profileID == profile.id }
    }

    private var scheduleCalendar: Calendar {
        MedicationScheduleDate.currentCalendar()
    }

    private var upcomingOccurrences: [MedicationOccurrence] {
        let now = Date()
        let start = scheduleCalendar.startOfDay(for: now)
        let end = scheduleCalendar.date(byAdding: .day, value: 7, to: now) ?? now
        return regimens.flatMap { regimen in
            MedicationScheduleEngine.occurrences(
                regimen: regimen,
                phases: allPhases.filter { $0.regimenID == regimen.id },
                from: start,
                through: end
            )
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var todayOccurrences: [MedicationOccurrence] {
        upcomingOccurrences.filter { scheduleCalendar.isDate($0.scheduledAt, inSameDayAs: Date()) }
    }

    private var asNeededRegimens: [MedicationRegimen] {
        regimens.filter { $0.scheduleKind == .asNeeded }
    }

    var body: some View {
        List {
            todaySection
            asNeededSection
            medicationSection
            upcomingSection
            archivedSection
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
    private var todaySection: some View {
        Section {
            if todayOccurrences.isEmpty {
                ContentUnavailableView(
                    "No scheduled doses today",
                    systemImage: "checkmark.circle",
                    description: Text("Scheduled doses will appear here.")
                )
            } else {
                ForEach(todayOccurrences) { occurrence in
                    occurrenceRow(occurrence)
                }
            }
        } header: {
            AppSectionHeader(title: "Today", subtitle: profile.name)
        }
    }

    @ViewBuilder
    private var asNeededSection: some View {
        if !asNeededRegimens.isEmpty {
            Section("As needed") {
                ForEach(asNeededRegimens) { regimen in
                    if let medication = medication(for: regimen) {
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
                                logAsNeeded(medication: medication, regimen: regimen)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var medicationSection: some View {
        Section {
            if medications.isEmpty {
                ContentUnavailableView {
                    Label("No medications", systemImage: "pills")
                } description: {
                    Text("Add a medication, its dose, and the schedule you want to follow.")
                } actions: {
                    Button("Add Medication") { showingEditor = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(medications) { medication in
                    NavigationLink {
                        MedicationDetailView(
                            profile: profile,
                            medication: medication,
                            regimens: regimens.filter { $0.medicationID == medication.id },
                            phases: allPhases
                        )
                    } label: {
                        medicationRow(medication)
                    }
                }
            }
        } header: {
            AppSectionHeader(title: "Medication list", subtitle: medications.count.description)
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let future = upcomingOccurrences.filter {
            $0.scheduledAt > Date() && !scheduleCalendar.isDate($0.scheduledAt, inSameDayAs: Date())
        }
        if !future.isEmpty {
            Section("Next 7 days") {
                ForEach(future.prefix(12)) { occurrence in
                    occurrenceRow(occurrence)
                }
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if !archivedMedications.isEmpty {
            Section("Archived") {
                ForEach(archivedMedications) { medication in
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
    private func occurrenceRow(_ occurrence: MedicationOccurrence) -> some View {
        if let regimen = regimens.first(where: { $0.id == occurrence.regimenID }),
           let medication = medication(for: regimen) {
            let record = records.first { $0.occurrenceKey == occurrence.occurrenceKey }
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

    private func medicationRow(_ medication: Medication) -> some View {
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
                    regimens.first(where: { $0.medicationID == medication.id })?.scheduleSummary
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

    private func medication(for regimen: MedicationRegimen) -> Medication? {
        medications.first { $0.id == regimen.medicationID }
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

    private func logAsNeeded(medication: Medication, regimen: MedicationRegimen) {
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

private struct MedicationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MedicationDoseRecord.loggedAt, order: .reverse) private var allDoseRecords: [MedicationDoseRecord]
    @Query(sort: \MedicationSupplyLog.loggedAt, order: .reverse) private var allSupplyLogs: [MedicationSupplyLog]
    let profile: CareProfile
    let medication: Medication
    let regimens: [MedicationRegimen]
    let phases: [MedicationSchedulePhase]
    @State private var showingSupplyEditor = false
    @State private var showingEditor = false
    @State private var supply = 0.0
    @State private var supplyReason: MedicationSupplyReason = .correction
    @State private var supplyNotes = ""
    @State private var doseRecordToDelete: MedicationDoseRecord?
    @State private var showingArchiveConfirmation = false

    private var activeRegimen: MedicationRegimen? { regimens.first { $0.isActive } }

    private var records: [MedicationDoseRecord] {
        allDoseRecords.filter { $0.medicationID == medication.id }
    }

    private var supplyLogs: [MedicationSupplyLog] {
        allSupplyLogs.filter { $0.medicationID == medication.id }
    }

    private var scheduleCalendar: Calendar {
        MedicationScheduleDate.currentCalendar()
    }

    private var adherence: MedicationAdherenceSummary? {
        guard let regimen = activeRegimen,
              regimen.scheduleKind.isScheduled else { return nil }
        let start = scheduleCalendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let occurrences = MedicationScheduleEngine.occurrences(
            regimen: regimen,
            phases: phases,
            from: start,
            through: Date(),
            calendar: scheduleCalendar
        )
        return MedicationScheduleEngine.adherence(occurrences: occurrences, records: records)
    }

    var body: some View {
        List {
            Section("Medication") {
                LabeledContent("Name", value: medication.name)
                if let strength = medication.strengthDescription {
                    LabeledContent("Strength", value: strength)
                }
                LabeledContent("Form", value: medication.form.displayName)
                LabeledContent("Route", value: medication.route.displayName)
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
                        LabeledContent("When traveling", value: regimen.timeZoneBehavior.displayName)
                        if regimen.timeZoneBehavior == .fixedTimeZone,
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
            if !records.isEmpty {
                Section("Dose history") {
                    ForEach(records.prefix(30)) { record in
                        HStack {
                            Label(record.status.displayName, systemImage: record.status == .taken ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(record.status == .taken ? .green : .secondary)
                            Spacer()
                            Text((record.takenAt ?? record.scheduledAt ?? record.loggedAt).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Menu("Dose actions", systemImage: "ellipsis.circle") {
                                Button(record.status == .taken ? "Change to Skipped" : "Change to Taken") {
                                    MedicationService.updateDoseRecordStatus(
                                        record,
                                        medication: medication,
                                        status: record.status == .taken ? .skipped : .taken,
                                        context: modelContext
                                    )
                                }
                                Button("Delete Dose", role: .destructive) {
                                    doseRecordToDelete = record
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
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
        .confirmationDialog(
            "Delete this dose record?",
            isPresented: Binding(
                get: { doseRecordToDelete != nil },
                set: { if !$0 { doseRecordToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Dose", role: .destructive) {
                if let record = doseRecordToDelete {
                    MedicationService.deleteDoseRecord(
                        record,
                        medication: medication,
                        context: modelContext
                    )
                }
                doseRecordToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                doseRecordToDelete = nil
            }
        } message: {
            Text("This removes the dose from medication history and the care timeline, and restores any supply that was deducted.")
        }
        .confirmationDialog(
            "Archive \(medication.name)?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Medication", role: .destructive) {
                MedicationService.archive(
                    medication: medication,
                    regimens: regimens,
                    context: modelContext
                )
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scheduled reminders will stop. You can restore this medication from the archived list.")
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

    private func supplyLogRow(_ log: MedicationSupplyLog) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.reason.displayName)
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
                    LabeledContent("Notes") {
                        TextField("Optional", text: $supplyNotes, axis: .vertical)
                            .lineLimit(2...4)
                            .multilineTextAlignment(.trailing)
                    }
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
    }

    private func signedSupplyAdjustment(_ value: Double) -> String {
        let formatted = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "−\(formatted)" }
        return formatted
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
    @State private var doseUnit = "tablet"
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
        _doseUnit = State(initialValue: regimen?.doseUnit ?? "tablet")
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
                LabeledContent("Instructions") {
                    TextField("Optional", text: $instructions, axis: .vertical)
                        .lineLimit(2...4)
                        .multilineTextAlignment(.trailing)
                }
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
                LabeledContent("Dose unit") {
                    TextField("Required", text: $doseUnit)
                        .multilineTextAlignment(.trailing)
                }
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
        guard doseAmount > 0,
              !doseUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Enter a dose greater than zero and its unit."
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

        let normalizedDoseUnit = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
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
