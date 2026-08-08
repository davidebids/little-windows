import SwiftData
import SwiftUI

struct AppointmentsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoctorAppointment.startDate) private var appointments: [DoctorAppointment]
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @State private var showingEditor = false
    @State private var appointmentPendingDelete: DoctorAppointment?
    @State private var showingDeleteConfirmation = false
    @StateObject private var profileService = ProfileService.shared

    init(profileID: UUID? = nil) {
        let selectedProfileID = profileID ?? ProfileService.shared.selectedProfileID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        _appointments = Query(FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate { $0.profileID == selectedProfileID },
            sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
        ))
    }

    private var profile: CareProfile? { profileService.selectedProfile(in: profiles) }
    private var scopedAppointments: [DoctorAppointment] {
        appointments.filter { $0.matchesProfile(profile?.id) }
    }

    private var upcoming: [DoctorAppointment] {
        scopedAppointments
            .filter { !$0.isCompleted && $0.startDate >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.startDate < $1.startDate }
    }

    private var past: [DoctorAppointment] {
        scopedAppointments
            .filter { $0.isCompleted || $0.startDate < Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        List {
            if scopedAppointments.isEmpty {
                ContentUnavailableView(
                    "No appointments yet",
                    systemImage: "stethoscope",
                    description: Text(emptyDescription)
                )
                .listRowBackground(Color.clear)
            } else {
                appointmentSection("Upcoming", appointments: upcoming)
                appointmentSection("Past visits", appointments: past)
            }

            Section {
                Text("Appointments and visit notes are for personal organization and are not a substitute for medical records or medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Appointments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                AppointmentEditorView(
                    babyName: profile?.name ?? "Profile",
                    profileID: profile?.id,
                    profileType: profile?.profileType ?? .child
                )
            }
        }
        .confirmationDialog(
            "Delete appointment?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Appointment", role: .destructive) {
                if let appointmentPendingDelete {
                    Task { await delete(appointmentPendingDelete) }
                }
                appointmentPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                appointmentPendingDelete = nil
            }
        } message: {
            Text("This permanently removes the appointment and cancels its reminders.")
        }
    }

    private var emptyDescription: String {
        switch profile?.profileType {
        case .adult: "Add primary care, specialist, lab, therapy, dental, and follow-up visits here."
        case .dog: "Add vet wellness, vaccine, grooming, and follow-up visits here."
        default: "Add pediatrician visits, vaccines, checkups, and follow-ups here."
        }
    }

    @ViewBuilder
    private func appointmentSection(
        _ title: String,
        appointments: [DoctorAppointment]
    ) -> some View {
        if !appointments.isEmpty {
            Section(title) {
                ForEach(appointments) { appointment in
                    NavigationLink {
                        AppointmentDetailView(appointment: appointment)
                    } label: {
                        AppointmentCard(appointment: appointment, style: .row)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            appointmentPendingDelete = appointment
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func delete(_ appointment: DoctorAppointment) async {
        await NotificationManager.shared.cancelAppointmentReminders(
            appointmentID: appointment.id
        )
        modelContext.delete(appointment)
        _ = PersistenceService.save(context: modelContext)
    }
}

struct AppointmentCard: View {
    enum Style {
        case row
        case featured
    }

    let appointment: DoctorAppointment
    var style: Style = .featured

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: appointment.appointmentType.systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: style == .featured ? 44 : 38, height: style == .featured ? 44 : 38)
                .background(tint.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(appointment.displayTitle)
                        .font(style == .featured ? .headline : .subheadline.weight(.semibold))
                    if appointment.isCompleted {
                        Text("DONE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let location = appointment.locationSummary {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if style == .featured {
                    HStack(spacing: 8) {
                        Label(appointment.appointmentType.displayName, systemImage: "tag.fill")
                        Label(appointment.reminderSummary, systemImage: "bell.fill")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(style == .featured ? 14 : 4)
        .background {
            if style == .featured {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            if style == .featured {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            }
        }
    }

    private var tint: Color {
        appointment.appointmentType == .urgentCare ? .red : .indigo
    }

    private var dateText: String {
        let day = DateFormatting.dayString(
            from: appointment.startDate,
            timeZone: appointment.timeZone
        )
        let time = DateFormatting.timeString(
            from: appointment.startDate,
            timeZone: appointment.timeZone,
            includesTimeZone: true
        )
        return "\(day) at \(time)"
    }
}

struct AppointmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("caregiverOne") private var caregiverOne = "Caregiver 1"
    @AppStorage("currentCaregiverName") private var currentCaregiverName = ""

    let appointment: DoctorAppointment?
    let babyName: String
    let profileID: UUID?
    let profileType: CareProfileType

    @State private var title: String
    @State private var appointmentType: AppointmentType
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasEndDate: Bool
    @State private var timeZoneIdentifier: String
    @State private var doctorName: String
    @State private var clinicName: String
    @State private var locationName: String
    @State private var address: String
    @State private var phoneNumber: String
    @State private var notes: String
    @State private var questionDrafts: [AppointmentQuestionDraft]
    @State private var remindersEnabled: Bool
    @State private var selectedLeadTimes: Set<AppointmentReminderLeadTime>
    @State private var validationMessage: String?
    private var activeCaregiverName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: caregiverOne
        )
    }

    init(
        appointment: DoctorAppointment? = nil,
        babyName: String = "Baby",
        profileID: UUID? = nil,
        profileType: CareProfileType = .child
    ) {
        self.appointment = appointment
        self.babyName = babyName
        self.profileID = profileID
        self.profileType = profileType
        let defaultTitle: String
        let defaultType: AppointmentType
        switch profileType {
        case .child:
            defaultTitle = "Pediatrician visit"
            defaultType = .pediatrician
        case .adult:
            defaultTitle = "Primary care visit"
            defaultType = .primaryCare
        case .dog:
            defaultTitle = "Vet visit"
            defaultType = .vetWellness
        }
        _title = State(initialValue: appointment?.title ?? defaultTitle)
        _appointmentType = State(initialValue: appointment?.appointmentType ?? defaultType)
        _startDate = State(initialValue: appointment?.startDate ?? Date().addingTimeInterval(24 * 60 * 60))
        _endDate = State(initialValue: appointment?.endDate ?? Date().addingTimeInterval(25 * 60 * 60))
        _hasEndDate = State(initialValue: appointment?.endDate != nil)
        _timeZoneIdentifier = State(
            initialValue: appointment?.timeZoneIdentifier
                ?? CareTimeZoneSettings.effectiveIdentifier()
        )
        _doctorName = State(initialValue: appointment?.doctorName ?? "")
        _clinicName = State(initialValue: appointment?.clinicName ?? "")
        _locationName = State(initialValue: appointment?.locationName ?? "")
        _address = State(initialValue: appointment?.address ?? "")
        _phoneNumber = State(initialValue: appointment?.phoneNumber ?? "")
        _notes = State(initialValue: appointment?.notes ?? "")
        _questionDrafts = State(initialValue: AppointmentQuestionDraft.drafts(from: appointment?.questionsToAsk))
        _remindersEnabled = State(initialValue: appointment?.remindersEnabled ?? true)
        _selectedLeadTimes = State(
            initialValue: Set(
                appointment?.reminderLeadTimes ?? [.oneDay, .oneHour]
            )
        )
    }

    var body: some View {
        Form {
            Section("Appointment") {
                TextField("Title", text: $title)
                Picker("Type", selection: $appointmentType) {
                    ForEach(appointmentTypes) {
                        Label($0.displayName, systemImage: $0.systemImage).tag($0)
                    }
                }
                DatePicker("Starts", selection: $startDate)
                    .environment(\.timeZone, appointmentTimeZone)
                Toggle("Has end time", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("Ends", selection: $endDate, in: startDate...)
                        .environment(\.timeZone, appointmentTimeZone)
                }
                NavigationLink {
                    TimeZonePickerView(selection: $timeZoneIdentifier)
                } label: {
                    LabeledContent(
                        "Time zone",
                        value: CareTimeZoneSettings.displayName(
                            for: appointmentTimeZone,
                            on: startDate
                        )
                    )
                }
            }

            Section("Fast presets") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        if profileType == .dog {
                            presetButton("Vet wellness", .vetWellness)
                            presetButton("Vaccine visit", .vaccine)
                            presetButton("Sick visit", .sickVisit)
                            presetButton("Emergency vet", .emergencyVet)
                            presetButton("Grooming", .grooming)
                            presetButton("Training", .training)
                            presetButton("Boarding", .boarding)
                        } else if profileType == .adult {
                            presetButton("Primary care", .primaryCare)
                            presetButton("Specialist visit", .specialist)
                            presetButton("Lab work", .lab)
                            presetButton("Therapy", .therapy)
                            presetButton("Dental visit", .dental)
                            presetButton("Imaging", .imaging)
                        } else {
                            presetButton("Pediatrician visit", .pediatrician)
                            presetButton("Wellness check", .wellnessCheck)
                            presetButton("Vaccine appointment", .vaccine)
                            presetButton("Sick visit", .sickVisit)
                            presetButton("Specialist visit", .specialist)
                            presetButton("Dental visit", .dental)
                        }
                    }
                }
            }

            Section(profileType == .dog ? "Vet and place" : "People and place") {
                TextField(profileType == .dog ? "Veterinarian name" : "Doctor name", text: $doctorName)
                TextField("Clinic name", text: $clinicName)
                TextField("Location name", text: $locationName)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(2...3)
                TextField("Phone number", text: $phoneNumber)
                    .keyboardType(.phonePad)
            }

            Section("Visit prep") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            AppointmentQuestionsEditor(questionDrafts: $questionDrafts)

            Section("Reminders") {
                AppointmentReminderPicker(
                    remindersEnabled: $remindersEnabled,
                    selectedLeadTimes: $selectedLeadTimes
                )
            }
        }
        .navigationTitle(appointment == nil ? "Add Appointment" : "Edit Appointment")
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
        .alert("Check appointment", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue.addingTimeInterval(60 * 60)
            }
        }
    }

    private var appointmentTypes: [AppointmentType] {
        if profileType == .dog {
            return [.vetWellness, .vaccine, .sickVisit, .emergencyVet, .dental, .grooming, .training, .boarding, .daycare, .other]
        }
        if profileType == .adult {
            return [.primaryCare, .wellnessCheck, .sickVisit, .specialist, .lab,
                    .imaging, .procedure, .therapy, .dental, .optometry,
                    .vaccine, .urgentCare, .other]
        }
        return [.pediatrician, .wellnessCheck, .vaccine, .sickVisit, .specialist, .lab, .dental, .lactation, .urgentCare, .other]
    }

    private func presetButton(_ presetTitle: String, _ type: AppointmentType) -> some View {
        Button(presetTitle) {
            title = presetTitle
            appointmentType = type
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Enter an appointment title."
            return
        }
        if hasEndDate, endDate < startDate {
            validationMessage = "End time must be after the start time."
            return
        }
        let value = appointment ?? DoctorAppointment(title: trimmedTitle)
        if appointment == nil {
            modelContext.insert(value)
        }
        value.profileID = value.profileID ?? profileID
        value.title = trimmedTitle
        value.appointmentType = appointmentType
        value.startDate = startDate
        value.endDate = hasEndDate ? endDate : nil
        value.timeZoneIdentifier = appointmentTimeZone.identifier
        value.doctorName = clean(doctorName)
        value.clinicName = clean(clinicName)
        value.locationName = clean(locationName)
        value.address = clean(address)
        value.phoneNumber = clean(phoneNumber)
        value.notes = clean(notes)
        value.questionsToAsk = AppointmentQuestionList.storageString(from: questionDrafts.map(\.text))
        value.remindersEnabled = remindersEnabled
        value.reminderLeadTimes = Array(selectedLeadTimes)
        value.caregiverName = activeCaregiverName
        value.updatedAt = Date()
        guard PersistenceService.save(context: modelContext) else { return }
        Task {
            if remindersEnabled {
                _ = await NotificationManager.shared.requestAuthorization()
                await NotificationManager.shared.rescheduleAppointmentReminders(
                    appointment: value,
                    babyName: babyName
                )
            } else {
                await NotificationManager.shared.cancelAppointmentReminders(
                    appointmentID: value.id
                )
            }
        }
        dismiss()
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var appointmentTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier)
            ?? CareTimeZoneSettings.effectiveTimeZone()
    }
}

private struct AppointmentQuestionDraft: Identifiable, Equatable {
    var id = UUID()
    var text: String

    static func drafts(from value: String?) -> [AppointmentQuestionDraft] {
        AppointmentQuestionList.parse(value).map { AppointmentQuestionDraft(text: $0) }
    }
}

private struct AppointmentQuestionsEditor: View {
    @Binding var questionDrafts: [AppointmentQuestionDraft]
    @State private var newQuestionText = ""
    @State private var newQuestionInputID = UUID()
    @FocusState private var isAddingQuestionFocused: Bool

    private var hasQuestionText: Bool {
        !newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            if questionDrafts.isEmpty {
                Label("No questions yet", systemImage: "questionmark.bubble")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($questionDrafts) { draft in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        TextField("Question", text: draft.text, axis: .vertical)
                            .lineLimit(1...3)

                        Button(role: .destructive) {
                            removeQuestion(withID: draft.wrappedValue.id)
                        } label: {
                            Image(systemName: "trash")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete question")
                    }
                }
                .onDelete { offsets in
                    questionDrafts.remove(atOffsets: offsets)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Add a question", text: $newQuestionText, axis: .vertical)
                    .id(newQuestionInputID)
                    .lineLimit(1...3)
                    .focused($isAddingQuestionFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        addQuestion()
                    }

                Button {
                    addQuestion()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .disabled(!hasQuestionText)
                .foregroundStyle(hasQuestionText ? Color.accentColor : Color.secondary)
                .accessibilityLabel("Add question")
            }
        } header: {
            Text("Questions to ask")
        } footer: {
            Text("Pasted lists are split automatically.")
        }
    }

    private func addQuestion() {
        let additions = AppointmentQuestionList.parse(newQuestionText)
        guard !additions.isEmpty else { return }
        newQuestionText = ""
        newQuestionInputID = UUID()
        questionDrafts.append(contentsOf: additions.map { AppointmentQuestionDraft(text: $0) })
        Task { @MainActor in
            isAddingQuestionFocused = true
        }
    }

    private func removeQuestion(withID id: UUID) {
        questionDrafts.removeAll { $0.id == id }
    }
}

struct AppointmentReminderPicker: View {
    @Binding var remindersEnabled: Bool
    @Binding var selectedLeadTimes: Set<AppointmentReminderLeadTime>

    var body: some View {
        Toggle("Enable reminders", isOn: $remindersEnabled)
        if remindersEnabled {
            ForEach(AppointmentReminderLeadTime.allCases) { leadTime in
                Toggle(
                    leadTime.displayName,
                    isOn: Binding(
                        get: { selectedLeadTimes.contains(leadTime) },
                        set: { enabled in
                            if enabled {
                                selectedLeadTimes.insert(leadTime)
                            } else {
                                selectedLeadTimes.remove(leadTime)
                            }
                        }
                    )
                )
            }
        }
    }
}
