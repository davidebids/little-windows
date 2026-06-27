import SwiftData
import SwiftUI

struct AppointmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var appointment: DoctorAppointment
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @StateObject private var profileService = ProfileService.shared

    @State private var showingEditor = false
    @State private var eventRoute: EventEditorRoute?
    @State private var milestoneTemplate: MilestoneTemplate?
    @State private var showingDeleteConfirmation = false
    @State private var events: [BabyEvent] = []

    private var profile: BabyProfile? { profileService.selectedProfile(in: profiles) }
    private var growthEntryTitle: String {
        profile?.profileType == .dog ? "Add vet growth entry" : "Add pediatrician growth entry"
    }
    private var scopedEvents: [BabyEvent] {
        events.filter { $0.matchesProfile(appointment.profileID ?? profile?.id) }
    }
    private var appointmentTimeSummary: String {
        guard let endDate = appointment.endDate,
              endDate > appointment.startDate else {
            return DateFormatting.time.string(from: appointment.startDate)
        }
        return DateFormatting.window(start: appointment.startDate, end: endDate)
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
            if let questions = appointment.questionsToAsk {
                notesSection("Questions to ask", questions, icon: "questionmark.bubble.fill")
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
                TextField("Visit summary", text: optional($appointment.visitSummary), axis: .vertical)
                    .lineLimit(3...8)
                TextField("Follow-up instructions", text: optional($appointment.followUpInstructions), axis: .vertical)
                    .lineLimit(3...8)
                TextField("Vaccines given", text: optional($appointment.vaccinesGiven), axis: .vertical)
                    .lineLimit(2...5)
                TextField("Medications discussed", text: optional($appointment.medicationsDiscussed), axis: .vertical)
                    .lineLimit(2...5)
            }

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
                Button("Add medicine entry", systemImage: "cross.case.fill") {
                    eventRoute = EventEditorRoute(type: .medicine)
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
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                AppointmentEditorView(
                    appointment: appointment,
                    babyName: profile?.name ?? "Baby",
                    profileID: appointment.profileID ?? profile?.id,
                    profileType: profile?.profileType ?? .child
                )
            }
        }
        .sheet(item: $eventRoute) { route in
            NavigationStack {
                EventEditorView(type: route.type, event: route.event) { event in
                    event.profileID = event.profileID ?? appointment.profileID ?? profile?.id
                    if event.type == .growth {
                        event.startDate = appointment.startDate
                        event.growthSource = .pediatrician
                        appointment.growthEntryID = event.id
                    } else if event.type == .temperature {
                        event.startDate = appointment.startDate
                        appointment.temperatureEntryID = event.id
                    }
                    appointment.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
        .sheet(item: $milestoneTemplate) { template in
            NavigationStack {
                MilestoneEditorView(template: template)
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

    private var latestGrowth: BabyEvent? {
        scopedEvents.first { $0.type == .growth }
    }

    private var latestTemperature: BabyEvent? {
        scopedEvents.first {
            $0.type == .temperature &&
            Date().timeIntervalSince($0.startDate) <= 14 * 24 * 60 * 60
        }
    }

    private var recentMedicines: [BabyEvent] {
        scopedEvents.filter {
            $0.type == .medicine &&
            Date().timeIntervalSince($0.startDate) <= 30 * 24 * 60 * 60
        }
    }

    private var healthContextRefreshToken: String {
        [
            appointment.id.uuidString,
            (appointment.profileID ?? profile?.id)?.uuidString ?? "all",
            appointment.updatedAt.timeIntervalSinceReferenceDate.description
        ].joined(separator: "-")
    }

    private func refreshHealthContext() {
        let selectedProfileID = appointment.profileID ?? profile?.id
        let now = Date()
        let temperatureCutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        let medicineCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)

        do {
            let growthEvents: [BabyEvent]
            let temperatureEvents: [BabyEvent]
            let medicineEvents: [BabyEvent]
            if let selectedProfileID {
                var growthDescriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.profileID == selectedProfileID && event.typeRawValue == "growth"
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
                )
                growthDescriptor.fetchLimit = 1
                growthEvents = try modelContext.fetch(growthDescriptor)

                var temperatureDescriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.profileID == selectedProfileID &&
                            event.typeRawValue == "temperature" &&
                            event.startDate >= temperatureCutoff
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
                )
                temperatureDescriptor.fetchLimit = 1
                temperatureEvents = try modelContext.fetch(temperatureDescriptor)

                var medicineDescriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.profileID == selectedProfileID &&
                            event.typeRawValue == "medicine" &&
                            event.startDate >= medicineCutoff
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
                )
                medicineDescriptor.fetchLimit = 3
                medicineEvents = try modelContext.fetch(medicineDescriptor)
            } else {
                var growthDescriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.typeRawValue == "growth"
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
                )
                growthDescriptor.fetchLimit = 1
                growthEvents = try modelContext.fetch(growthDescriptor)

                var temperatureDescriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.typeRawValue == "temperature" && event.startDate >= temperatureCutoff
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
                )
                temperatureDescriptor.fetchLimit = 1
                temperatureEvents = try modelContext.fetch(temperatureDescriptor)

                var medicineDescriptor = FetchDescriptor<BabyEvent>(
                    predicate: #Predicate<BabyEvent> { event in
                        event.typeRawValue == "medicine" && event.startDate >= medicineCutoff
                    },
                    sortBy: [SortDescriptor(\BabyEvent.startDate, order: .reverse)]
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

    private func growthSummary(_ event: BabyEvent) -> String {
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

    private func temperatureSummary(_ event: BabyEvent) -> String {
        guard let value = event.temperatureValue(in: .fahrenheit) else {
            return "Temperature logged"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1))))°F"
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                binding.wrappedValue = trimmed.isEmpty ? nil : trimmed
                appointment.updatedAt = Date()
            }
        )
    }

    private func deleteAppointment() async {
        await NotificationManager.shared.cancelAppointmentReminders(
            appointmentID: appointment.id
        )
        modelContext.delete(appointment)
        try? modelContext.save()
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
