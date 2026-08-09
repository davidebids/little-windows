import SwiftData
import SwiftUI

struct AppointmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var appointment: DoctorAppointment
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @Query(sort: \Medication.name) private var allMedications: [Medication]
    @Query(sort: \MedicationRegimen.createdAt) private var allMedicationRegimens: [MedicationRegimen]
    @StateObject private var profileService = ProfileService.shared

    @State private var showingEditor = false
    @State private var eventRoute: EventEditorRoute?
    @State private var milestoneTemplate: MilestoneTemplate?
    @State private var showingDeleteConfirmation = false
    @State private var events: [CareEvent] = []
    @State private var visitSummaryDraft = ""
    @State private var followUpInstructionsDraft = ""
    @State private var vaccinesGivenDraft = ""
    @State private var medicationsDiscussedDraft = ""
    @State private var hasLoadedVisitJournalDrafts = false
    @State private var pendingVisitJournalSave: Task<Void, Never>?

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
                    title: "Follow-up",
                    prompt: "Optional",
                    text: $followUpInstructionsDraft,
                    lineLimit: 3...8,
                    accessibilityIdentifier: "appointment.result.follow-up"
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
        }
        .onAppear(perform: loadVisitJournalDraftsIfNeeded)
        .onChange(of: visitSummaryDraft) { _, _ in scheduleVisitJournalSave() }
        .onChange(of: followUpInstructionsDraft) { _, _ in scheduleVisitJournalSave() }
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
                    if event.type == .growth {
                        event.startDate = appointment.startDate
                        switch profile?.profileType {
                        case .child: event.growthSource = .pediatrician
                        case .adult: event.growthSource = .medicalVisit
                        default: event.growthSource = .other
                        }
                        appointment.growthEntryID = event.id
                    } else if event.type == .temperature {
                        event.startDate = appointment.startDate
                        appointment.temperatureEntryID = event.id
                    }
                    appointment.updatedAt = Date()
                    _ = PersistenceService.save(context: modelContext)
                }
            }
        }
        .sheet(item: $milestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(
                    template: template,
                    profileID: appointment.profileID ?? profile?.id
                )
            }
        }
        .confirmationDialog(
            "Delete \(appointment.displayTitle)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Appointment", role: .destructive) {
                Task { await deleteAppointment() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the appointment and cancels its reminders.")
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
            }
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
        followUpInstructionsDraft = appointment.followUpInstructions ?? ""
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
        let followUpInstructions = cleanedOptional(followUpInstructionsDraft)
        let vaccinesGiven = cleanedOptional(vaccinesGivenDraft)
        let medicationsDiscussed = cleanedOptional(medicationsDiscussedDraft)

        guard appointment.visitSummary != visitSummary ||
              appointment.followUpInstructions != followUpInstructions ||
              appointment.vaccinesGiven != vaccinesGiven ||
              appointment.medicationsDiscussed != medicationsDiscussed else {
            return
        }

        appointment.visitSummary = visitSummary
        appointment.followUpInstructions = followUpInstructions
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
        await NotificationManager.shared.cancelAppointmentReminders(
            appointmentID: appointment.id
        )
        modelContext.delete(appointment)
        guard PersistenceService.save(context: modelContext) else { return }
        dismiss()
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
