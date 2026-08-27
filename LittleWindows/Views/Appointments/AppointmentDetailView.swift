import SwiftData
import SwiftUI

struct AppointmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var appointment: DoctorAppointment
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @Query private var allMedications: [Medication]
    @Query private var allMedicationRegimens: [MedicationRegimen]
    @Query private var followUps: [AppointmentFollowUp]
    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \FamilyCaregiverIdentity.displayName) private var familyCaregivers: [FamilyCaregiverIdentity]
    @Query(sort: \HouseholdAttentionClaim.updatedAt, order: .reverse) private var attentionClaims: [HouseholdAttentionClaim]
    @StateObject private var profileService = ProfileService.shared

    @AppStorage(PersistenceService.familySyncModeKey)
    private var syncModeRawValue = FamilySyncMode.privateICloudSync.rawValue

    @State private var showingEditor = false
    @State private var eventRoute: EventEditorRoute?
    @State private var milestoneTemplate: MilestoneTemplate?
    @State private var showingDeleteConfirmation = false
    @State private var events: [CareEvent] = []
    @State private var visitSummaryDraft = ""
    @State private var vaccinesGivenDraft = ""
    @State private var medicationsDiscussedDraft = ""
    @State private var followUpToEdit: AppointmentFollowUp?
    @State private var followUpPendingDeletion: AppointmentFollowUp?
    @State private var showingNewFollowUp = false
    @State private var showingMedicationReconciliation = false
    @State private var hasLoadedVisitJournalDrafts = false
    @State private var pendingVisitJournalSave: Task<Void, Never>?
    @State private var actionErrorMessage: String?

    init(appointment: DoctorAppointment) {
        self.appointment = appointment
        let profileID = appointment.profileID
        _allMedications = Query(FetchDescriptor<Medication>(
            predicate: #Predicate { profileID == nil || $0.profileID == profileID },
            sortBy: [SortDescriptor(\Medication.name)]
        ))
        _allMedicationRegimens = Query(FetchDescriptor<MedicationRegimen>(
            predicate: #Predicate { profileID == nil || $0.profileID == profileID },
            sortBy: [SortDescriptor(\MedicationRegimen.createdAt)]
        ))
        let appointmentID = appointment.id
        _followUps = Query(FetchDescriptor<AppointmentFollowUp>(
            predicate: #Predicate { $0.appointmentID == appointmentID },
            sortBy: [
                SortDescriptor(\AppointmentFollowUp.completedAt),
                SortDescriptor(\AppointmentFollowUp.dueDate),
                SortDescriptor(\AppointmentFollowUp.createdAt)
            ]
        ))
    }

    private var profile: CareProfile? {
        if let profileID = appointment.profileID,
           let appointmentProfile = profiles.first(where: { $0.id == profileID }) {
            return appointmentProfile
        }
        return profileService.selectedProfile(in: profiles)
    }
    private var growthEntryTitle: String {
        switch profile?.profileType {
        case .adult: "Add weight or height entry"
        case .dog: "Add vet growth entry"
        default: "Add pediatrician growth entry"
        }
    }
    private var scopedEvents: [CareEvent] {
        events.filter { $0.matchesProfile(appointment.profileID ?? profile?.id) }
    }
    private var appointmentTimeSummary: String {
        guard let endDate = appointment.endDate,
              endDate > appointment.startDate else {
            return DateFormatting.timeString(
                from: appointment.startDate,
                timeZone: appointment.timeZone,
                includesTimeZone: true
            )
        }
        return DateFormatting.window(
            start: appointment.startDate,
            end: endDate,
            startTimeZone: appointment.timeZone,
            endTimeZone: appointment.timeZone,
            includesTimeZones: true
        )
    }

    private var familySyncEnabled: Bool {
        FamilySyncMode(rawValue: syncModeRawValue) == .sharedFamilySync
    }

    private var appointmentFamilyCollaborationEnabled: Bool {
        guard familySyncEnabled, let profileID = appointment.profileID else { return false }
        return profiles.first(where: { $0.id == profileID })?.sharingScope == .family
    }

    private var currentHouseholdID: UUID? { households.first?.id }

    private var claimsBySourceKey: [String: HouseholdAttentionClaim] {
        Dictionary(
            attentionClaims.map { ($0.sourceKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        List {
            Section {
                AppointmentCard(appointment: appointment)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Details") {
                DetailRow("Type", appointment.appointmentType.displayName, icon: appointment.appointmentType.systemImage)
                DetailRow("Time", appointmentTimeSummary, icon: "clock.fill")
                if let doctor = appointment.doctorName {
                    DetailRow("Doctor", doctor, icon: "person.crop.circle.fill")
                }
                if let clinic = appointment.clinicName {
                    DetailRow("Clinic", clinic, icon: "building.2.fill")
                }
                if let location = appointment.locationName {
                    DetailRow("Location", location, icon: "mappin.circle.fill")
                }
                if let address = appointment.address {
                    DetailRow("Address", address, icon: "map.fill")
                }
                if let phone = appointment.phoneNumber {
                    DetailRow("Phone", phone, icon: "phone.fill")
                }
                DetailRow("Reminders", appointment.reminderSummary, icon: "bell.fill")
            }

            if let notes = appointment.notes {
                notesSection("Notes", notes, icon: "note.text")
            }
            let questions = AppointmentQuestionList.parse(appointment.questionsToAsk)
            if !questions.isEmpty {
                questionsSection(questions)
            }

            Section("Visit journal") {
                Toggle("Visit completed", isOn: $appointment.isCompleted)
                    .onChange(of: appointment.isCompleted) { _, completed in
                        appointment.updatedAt = Date()
                        if completed {
                            Task {
                                await NotificationManager.shared.cancelAppointmentReminders(
                                    appointmentID: appointment.id
                                )
                            }
                        }
                    }
                PersistentMultilineFormField(
                    title: "Summary",
                    prompt: "Optional",
                    text: $visitSummaryDraft,
                    lineLimit: 3...8,
                    accessibilityIdentifier: "appointment.result.summary"
                )
                PersistentMultilineFormField(
                    title: "Vaccines given",
                    prompt: "Optional",
                    text: $vaccinesGivenDraft,
                    lineLimit: 2...5,
                    accessibilityIdentifier: "appointment.result.vaccines"
                )
                PersistentMultilineFormField(
                    title: "Medications discussed",
                    prompt: "Optional",
                    text: $medicationsDiscussedDraft,
                    lineLimit: 2...5,
                    accessibilityIdentifier: "appointment.result.medications"
                )
            }

            Section {
                if followUps.isEmpty {
                    ContentUnavailableView(
                        "No follow-ups",
                        systemImage: "checklist",
                        description: Text("Add each next step separately so it can be due, assigned, and completed.")
                    )
                } else {
                    ForEach(followUps) { followUp in
                        AppointmentFollowUpRow(
                            followUp: followUp,
                            assignedCaregiverName: assignedCaregiverName(for: followUp),
                            toggleCompleted: {
                                guard HouseholdAttentionService.setFollowUpCompleted(
                                    followUp,
                                    completed: !followUp.isCompleted,
                                    context: modelContext
                                ) else {
                                    actionErrorMessage = "The follow-up couldn't be updated. Please try again."
                                    return
                                }
                            },
                            edit: { followUpToEdit = followUp }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                followUpPendingDeletion = followUp
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button("Add follow-up", systemImage: "plus.circle.fill") {
                    showingNewFollowUp = true
                }
                .accessibilityIdentifier("appointment.follow-up.add")
            } header: {
                Text("Follow-ups")
            } footer: {
                Text("Follow-ups are actionable items. Use the visit summary or notes for narrative instructions and context.")
            }

            currentMedicationsSection

            Section("Related health info") {
                if let growth = latestGrowth {
                    HealthContextRow(
                        title: "Latest growth",
                        value: growthSummary(growth),
                        icon: "ruler.fill",
                        tint: .mint
                    )
                }
                if let temperature = latestTemperature {
                    HealthContextRow(
                        title: "Recent temperature",
                        value: temperatureSummary(temperature),
                        icon: "thermometer.medium",
                        tint: .red
                    )
                }
                if recentMedicines.isEmpty {
                    Text("No recent medicine entries.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentMedicines.prefix(3)) { medicine in
                        HealthContextRow(
                            title: medicine.medicineName ?? "Medicine",
                            value: medicine.startDate.formatted(date: .abbreviated, time: .shortened),
                            icon: "cross.case.fill",
                            tint: .red
                        )
                    }
                }
            }

            Section("Add from this visit") {
                Button(growthEntryTitle, systemImage: "ruler.fill") {
                    eventRoute = EventEditorRoute(type: .growth)
                }
                Button("Add temperature entry", systemImage: "thermometer.medium") {
                    eventRoute = EventEditorRoute(type: .temperature)
                }
                Button("Add milestone", systemImage: "heart.text.clipboard.fill") {
                    milestoneTemplate = MilestoneTemplate(
                        title: "\(appointment.appointmentType.displayName) visit",
                        category: .health
                    )
                }
            }

            Section {
                Button("Delete Appointment", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }

            Section {
                Text("Appointments and visit notes are for personal organization and are not a substitute for medical records or medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(appointment.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .task(id: healthContextRefreshToken) {
            refreshHealthContext()
            if familySyncEnabled, let householdID = currentHouseholdID {
                _ = HouseholdAttentionService.registerCurrentFamilyCaregiver(
                    householdID: householdID,
                    context: modelContext
                )
            }
        }
        .onAppear(perform: loadVisitJournalDraftsIfNeeded)
        .onChange(of: visitSummaryDraft) { _, _ in scheduleVisitJournalSave() }
        .onChange(of: vaccinesGivenDraft) { _, _ in scheduleVisitJournalSave() }
        .onChange(of: medicationsDiscussedDraft) { _, _ in scheduleVisitJournalSave() }
        .onDisappear(perform: saveVisitJournalNow)
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                AppointmentEditorView(
                    appointment: appointment,
                    babyName: profile?.name ?? "Profile",
                    profileID: appointment.profileID ?? profile?.id,
                    profileType: profile?.profileType ?? .child
                )
            }
        }
        .sheet(item: $eventRoute) { route in
            NavigationStack {
                EventEditorView(type: route.type, event: route.event) { event in
                    if let appointmentProfileID = appointment.profileID ?? profile?.id {
                        event.profileID = appointmentProfileID
                    }
                    let appointmentLinkKind: AppointmentEventLinkKind?
                    if event.type == .growth {
                        event.startDate = appointment.startDate
                        switch profile?.profileType {
                        case .child: event.growthSource = .pediatrician
                        case .adult: event.growthSource = .medicalVisit
                        default: event.growthSource = .other
                        }
                        appointmentLinkKind = .growth
                    } else if event.type == .temperature {
                        event.startDate = appointment.startDate
                        appointmentLinkKind = .temperature
                    } else {
                        appointmentLinkKind = nil
                    }
                    let container = modelContext.container
                    let appointmentID = appointment.id
                    Task {
                        if let appointmentLinkKind {
                            _ = await EventMutationService.persistStandaloneEvent(
                                event,
                                appointmentID: appointmentID,
                                appointmentLinkKind: appointmentLinkKind,
                                container: container
                            )
                        } else {
                            _ = await EventMutationService.persistStandaloneEvent(
                                event,
                                container: container
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewFollowUp) {
            followUpEditor(followUp: nil)
        }
        .sheet(isPresented: $showingMedicationReconciliation) {
            if let profile {
                NavigationStack {
                    MedicationReconciliationView(
                        profile: profile,
                        appointmentID: appointment.id,
                        defaultSource: appointmentReconciliationSource,
                        defaultEffectiveFrom: appointment.startDate
                    )
                }
            }
        }
        .sheet(item: $followUpToEdit) { followUp in
            followUpEditor(followUp: followUp)
        }
        .confirmationDialog(
            "Delete follow-up?",
            isPresented: Binding(
                get: { followUpPendingDeletion != nil },
                set: { if !$0 { followUpPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Follow-up", role: .destructive) {
                guard let followUp = followUpPendingDeletion else { return }
                followUpPendingDeletion = nil
                guard HouseholdAttentionService.deleteFollowUp(
                    followUp,
                    context: modelContext
                ) else {
                    actionErrorMessage = "The follow-up couldn't be deleted. Please try again."
                    return
                }
            }
            Button("Cancel", role: .cancel) { followUpPendingDeletion = nil }
        } message: {
            Text("This also removes its seen status, assignment, and linked handoff notes.")
        }
        .sheet(item: $milestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(
                    template: template,
                    profileID: appointment.profileID ?? profile?.id
                )
            }
        }
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete \(appointment.displayTitle)?",
            message: "This permanently removes the appointment, its follow-ups and handoff activity, and cancels its reminders.",
            systemImage: "calendar.badge.minus",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Delete Appointment",
                    subtitle: "Also remove its follow-ups and handoff activity.",
                    systemImage: "calendar.badge.minus",
                    tint: .red,
                    role: .destructive
                ) {
                    Task { await deleteAppointment() }
                }
            ]
        )
        .alert("Couldn't Complete Action", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "Please try again.")
        }
    }

    private var latestGrowth: CareEvent? {
        scopedEvents.first { $0.type == .growth }
    }

    private var latestTemperature: CareEvent? {
        scopedEvents.first {
            $0.type == .temperature &&
            Date().timeIntervalSince($0.startDate) <= 14 * 24 * 60 * 60
        }
    }

    private var recentMedicines: [CareEvent] {
        scopedEvents.filter {
            $0.type == .medicine &&
            Date().timeIntervalSince($0.startDate) <= 30 * 24 * 60 * 60
        }
    }

    private var currentMedications: [Medication] {
        let profileID = appointment.profileID ?? profile?.id
        return allMedications.filter { $0.profileID == profileID && !$0.isArchived }
    }

    @ViewBuilder
    private var currentMedicationsSection: some View {
        if let profile, profile.profileType.capabilities.supportsMedications {
            Section("Current medications") {
                if currentMedications.isEmpty {
                    Text("No current medications added.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentMedications.prefix(8)) { medication in
                        HealthContextRow(
                            title: medication.name,
                            value: currentMedicationSummary(medication),
                            icon: "pills.fill",
                            tint: .red
                        )
                    }
                }
                NavigationLink {
                    MedicationsView(profile: profile)
                } label: {
                    Label("Review or add medications", systemImage: "pills.fill")
                }
                Button("Reconcile after this visit", systemImage: "checkmark.seal.fill") {
                    showingMedicationReconciliation = true
                }
            }
        }
    }

    private var appointmentReconciliationSource: MedicationPlanChangeSource {
        switch appointment.appointmentType {
        case .urgentCare, .procedure:
            .dischargePaperwork
        default:
            .clinician
        }
    }

    private func currentMedicationSummary(_ medication: Medication) -> String {
        let regimen = allMedicationRegimens.first {
            $0.medicationID == medication.id && $0.isActive
        }
        return [medication.strengthDescription, regimen?.scheduleSummary]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfBlank ?? medication.form.displayName
    }

    private var healthContextRefreshToken: String {
        [
            appointment.id.uuidString,
            (appointment.profileID ?? profile?.id)?.uuidString ?? "all"
        ].joined(separator: "-")
    }

    private func refreshHealthContext() {
        let selectedProfileID = appointment.profileID ?? profile?.id
        let now = Date()
        let temperatureCutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        let medicineCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)

        do {
            let growthEvents: [CareEvent]
            let temperatureEvents: [CareEvent]
            let medicineEvents: [CareEvent]
            if let selectedProfileID {
                var growthDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.profileID == selectedProfileID && event.typeRawValue == "growth"
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                growthDescriptor.fetchLimit = 1
                growthEvents = try modelContext.fetch(growthDescriptor)

                var temperatureDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.profileID == selectedProfileID &&
                            event.typeRawValue == "temperature" &&
                            event.startDate >= temperatureCutoff
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                temperatureDescriptor.fetchLimit = 1
                temperatureEvents = try modelContext.fetch(temperatureDescriptor)

                var medicineDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.profileID == selectedProfileID &&
                            event.typeRawValue == "medicine" &&
                            event.startDate >= medicineCutoff
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                medicineDescriptor.fetchLimit = 3
                medicineEvents = try modelContext.fetch(medicineDescriptor)
            } else {
                var growthDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.typeRawValue == "growth"
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                growthDescriptor.fetchLimit = 1
                growthEvents = try modelContext.fetch(growthDescriptor)

                var temperatureDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.typeRawValue == "temperature" && event.startDate >= temperatureCutoff
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                temperatureDescriptor.fetchLimit = 1
                temperatureEvents = try modelContext.fetch(temperatureDescriptor)

                var medicineDescriptor = FetchDescriptor<CareEvent>(
                    predicate: #Predicate<CareEvent> { event in
                        event.typeRawValue == "medicine" && event.startDate >= medicineCutoff
                    },
                    sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
                )
                medicineDescriptor.fetchLimit = 3
                medicineEvents = try modelContext.fetch(medicineDescriptor)
            }
            events = growthEvents + temperatureEvents + medicineEvents
        } catch {
            events = []
        }
    }

    @ViewBuilder
    private func notesSection(_ title: String, _ text: String, icon: String) -> some View {
        Section {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(text)
                .font(.body)
        }
    }

    @ViewBuilder
    private func questionsSection(_ questions: [String]) -> some View {
        Section {
            Label("Questions to ask", systemImage: "questionmark.bubble.fill")
                .font(.headline)
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                LabeledContent("Question \(index + 1)") {
                    Text(question)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func growthSummary(_ event: CareEvent) -> String {
        var pieces = [String]()
        if let weight = event.canonicalWeightKilograms {
            let pounds = GrowthUnitConversion.kilogramsToPoundsAndOunces(weight)
            pieces.append("\(pounds.pounds) lb \(pounds.ounces.formatted(.number.precision(.fractionLength(1)))) oz")
        }
        if let length = event.canonicalLengthCentimeters {
            pieces.append("\((length / GrowthUnitConversion.centimetersPerInch).formatted(.number.precision(.fractionLength(1)))) in")
        }
        return pieces.isEmpty ? "Measurement logged" : pieces.joined(separator: " / ")
    }

    private func temperatureSummary(_ event: CareEvent) -> String {
        guard let value = event.temperatureValue(in: .fahrenheit) else {
            return "Temperature logged"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1))))°F"
    }

    private func loadVisitJournalDraftsIfNeeded() {
        guard !hasLoadedVisitJournalDrafts else { return }
        hasLoadedVisitJournalDrafts = true
        visitSummaryDraft = appointment.visitSummary ?? ""
        vaccinesGivenDraft = appointment.vaccinesGiven ?? ""
        medicationsDiscussedDraft = appointment.medicationsDiscussed ?? ""
    }

    private func scheduleVisitJournalSave() {
        guard hasLoadedVisitJournalDrafts else { return }
        pendingVisitJournalSave?.cancel()
        pendingVisitJournalSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            persistVisitJournalDrafts()
        }
    }

    private func saveVisitJournalNow() {
        pendingVisitJournalSave?.cancel()
        persistVisitJournalDrafts()
    }

    private func persistVisitJournalDrafts() {
        let visitSummary = cleanedOptional(visitSummaryDraft)
        let vaccinesGiven = cleanedOptional(vaccinesGivenDraft)
        let medicationsDiscussed = cleanedOptional(medicationsDiscussedDraft)

        guard appointment.visitSummary != visitSummary ||
              appointment.vaccinesGiven != vaccinesGiven ||
              appointment.medicationsDiscussed != medicationsDiscussed else {
            return
        }

        appointment.visitSummary = visitSummary
        appointment.vaccinesGiven = vaccinesGiven
        appointment.medicationsDiscussed = medicationsDiscussed
        appointment.updatedAt = Date()
        _ = PersistenceService.save(context: modelContext)
    }

    private func cleanedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func deleteAppointment() async {
        guard await HouseholdAttentionService.deleteAppointment(
            appointment,
            context: modelContext
        ) else {
            actionErrorMessage = "The appointment couldn't be deleted. Please try again."
            return
        }
        dismiss()
    }

    private func assignedCaregiverName(for followUp: AppointmentFollowUp) -> String? {
        guard appointmentFamilyCollaborationEnabled,
              let claim = claimsBySourceKey[followUp.attentionSourceKey],
              let identifier = claim.caregiverIdentifier,
              !identifier.isEmpty else { return nil }
        return familyCaregivers.first {
            $0.householdID == currentHouseholdID && $0.caregiverIdentifier == identifier
        }?.displayName ?? claim.caregiverName
    }

    private func followUpEditor(followUp: AppointmentFollowUp?) -> some View {
        let collaborationEnabled = appointmentFamilyCollaborationEnabled
            && followUp?.isCompleted != true
        let currentClaim = collaborationEnabled
            ? followUp.flatMap { claimsBySourceKey[$0.attentionSourceKey] }
            : nil
        return NavigationStack {
            AppointmentFollowUpEditorView(
                followUp: followUp,
                familySyncEnabled: collaborationEnabled,
                caregivers: familyCaregivers.filter { $0.householdID == currentHouseholdID },
                currentClaim: currentClaim
            ) { title, details, dueDate, assignee in
                guard let householdID = currentHouseholdID else { return false }
                let savedFollowUp: AppointmentFollowUp?
                if let followUp {
                    guard HouseholdAttentionService.updateFollowUp(
                        followUp,
                        title: title,
                        details: details,
                        dueDate: dueDate,
                        context: modelContext
                    ) else { return false }
                    savedFollowUp = followUp
                } else {
                    savedFollowUp = HouseholdAttentionService.createFollowUp(
                        appointment: appointment,
                        householdID: householdID,
                        title: title,
                        details: details,
                        dueDate: dueDate,
                        assignedCaregiverIdentifier: collaborationEnabled
                            ? assignee?.identifier
                            : nil,
                        assignedCaregiverName: collaborationEnabled
                            ? assignee?.name
                            : nil,
                        context: modelContext
                    )
                }
                guard let savedFollowUp else { return false }
                if collaborationEnabled, followUp != nil {
                    guard HouseholdAttentionService.setClaimIfNeeded(
                        sourceKey: savedFollowUp.attentionSourceKey,
                        householdID: householdID,
                        profileID: savedFollowUp.profileID,
                        currentClaim: currentClaim,
                        caregiverIdentifier: assignee?.identifier,
                        caregiverName: assignee?.name,
                        context: modelContext
                    ) else { return false }
                }
                return true
            }
        }
    }
}

private struct AppointmentFollowUpAssignee {
    var identifier: String
    var name: String
}

private struct AppointmentFollowUpRow: View {
    let followUp: AppointmentFollowUp
    let assignedCaregiverName: String?
    let toggleCompleted: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggleCompleted) {
                Image(systemName: followUp.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(followUp.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(followUp.isCompleted ? "Reopen follow-up" : "Complete follow-up")

            Button(action: edit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(followUp.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(followUp.isCompleted)
                        .foregroundStyle(.primary)
                    if let details = followUp.details {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if let dueDate = followUp.dueDate {
                            Label(
                                dueDate.formatted(date: .abbreviated, time: .omitted),
                                systemImage: "calendar"
                            )
                        }
                        if let name = assignedCaregiverName, !name.isEmpty {
                            Label(name, systemImage: "person.fill")
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}

private struct AppointmentFollowUpEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let followUp: AppointmentFollowUp?
    let familySyncEnabled: Bool
    let caregivers: [FamilyCaregiverIdentity]
    let currentClaim: HouseholdAttentionClaim?
    let save: (String, String?, Date?, AppointmentFollowUpAssignee?) -> Bool

    @State private var title: String
    @State private var details: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var assigneeIdentifier: String
    @State private var showingSaveError = false

    init(
        followUp: AppointmentFollowUp?,
        familySyncEnabled: Bool,
        caregivers: [FamilyCaregiverIdentity],
        currentClaim: HouseholdAttentionClaim?,
        save: @escaping (String, String?, Date?, AppointmentFollowUpAssignee?) -> Bool
    ) {
        self.followUp = followUp
        self.familySyncEnabled = familySyncEnabled
        self.caregivers = caregivers
        self.currentClaim = currentClaim
        self.save = save
        _title = State(initialValue: followUp?.title ?? "")
        _details = State(initialValue: followUp?.details ?? "")
        _hasDueDate = State(initialValue: followUp?.dueDate != nil)
        _dueDate = State(initialValue: followUp?.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        _assigneeIdentifier = State(initialValue: currentClaim?.caregiverIdentifier ?? "")
    }

    var body: some View {
        Form {
            Section("Follow-up") {
                TextField("What needs to happen?", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Details (optional)", text: $details, axis: .vertical)
                    .lineLimit(2...6)
            }
            Section("Timing") {
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            if familySyncEnabled {
                Section("Responsibility") {
                    Picker("Caregiver", selection: $assigneeIdentifier) {
                        Text("Unassigned").tag("")
                        ForEach(caregivers) { caregiver in
                            Text(caregiver.displayName).tag(caregiver.caregiverIdentifier)
                        }
                        if let currentClaim,
                           let identifier = currentClaim.caregiverIdentifier,
                           let name = currentClaim.caregiverName,
                           !identifier.isEmpty,
                           !caregivers.contains(where: { $0.caregiverIdentifier == identifier }) {
                            Text(name).tag(identifier)
                        }
                    }
                    if caregivers.isEmpty {
                        Text("Caregivers appear here after their device has joined and synced this family space.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(followUp == nil ? "New Follow-up" : "Edit Follow-up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let assignee = selectedAssignee
                    if save(
                        title,
                        details.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                        hasDueDate ? dueDate : nil,
                        assignee
                    ) {
                        dismiss()
                    } else {
                        showingSaveError = true
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Couldn't Save Follow-up", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your changes weren't saved. Please try again.")
        }
    }

    private var selectedAssignee: AppointmentFollowUpAssignee? {
        guard !assigneeIdentifier.isEmpty else { return nil }
        if let caregiver = caregivers.first(where: {
            $0.caregiverIdentifier == assigneeIdentifier
        }) {
            return AppointmentFollowUpAssignee(
                identifier: caregiver.caregiverIdentifier,
                name: caregiver.displayName
            )
        }
        guard currentClaim?.caregiverIdentifier == assigneeIdentifier,
              let name = currentClaim?.caregiverName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return AppointmentFollowUpAssignee(identifier: assigneeIdentifier, name: name)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let icon: String

    init(_ title: String, _ value: String, icon: String) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        Label {
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

private struct HealthContextRow: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
