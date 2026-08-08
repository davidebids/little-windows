import SwiftData
import SwiftUI

struct CareReportExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]

    @AppStorage("careReportRangePreset") private var storedRangePreset = CareReportDateRangePreset.last30Days.rawValue
    @AppStorage("careReportFormat") private var storedFormat = CareReportFormat.pdf.rawValue
    @AppStorage("careReportCustomStart") private var storedCustomStart = CareReportExportService.defaultRange(for: .last30Days).0.timeIntervalSinceReferenceDate
    @AppStorage("careReportCustomEnd") private var storedCustomEnd = CareReportExportService.defaultRange(for: .last30Days).1.timeIntervalSinceReferenceDate
    @AppStorage("careReportIncludeNotes") private var includeNotes = true
    @AppStorage("careReportIncludeCaregiverNames") private var includeCaregiverNames = true
    @AppStorage("careReportIncludeAppointments") private var includeAppointments = true
    @AppStorage("careReportIncludeMilestones") private var includeMilestones = true
    @State private var selectedProfileID: UUID?
    @State private var format: CareReportFormat = .pdf
    @State private var rangePreset: CareReportDateRangePreset = .last30Days
    @State private var startDate: Date = CareReportExportService.defaultRange(for: .last30Days).0
    @State private var endDate: Date = CareReportExportService.defaultRange(for: .last30Days).1
    @State private var showingExporter = false
    @State private var exportDocument = CareReportDocument()
    @State private var exportContentType = CareReportFormat.pdf.contentType
    @State private var defaultFilename = "Little-Windows-Care-Report.pdf"
    @State private var statusMessage: String?

    private var uniqueProfiles: [CareProfile] {
        ProfileService.shared.allProfiles(in: profiles)
    }

    private var activeProfiles: [CareProfile] {
        ProfileService.shared.allActiveProfiles(in: profiles)
    }

    private var selectedProfile: CareProfile? {
        let candidates = activeProfiles.isEmpty ? uniqueProfiles : activeProfiles
        if let selectedProfileID,
           let profile = candidates.first(where: { $0.id == selectedProfileID }) {
            return profile
        }
        return candidates.first
    }

    var body: some View {
        Form {
            Section {
                if activeProfiles.isEmpty && uniqueProfiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Create a profile before exporting a visit report.")
                    )
                } else {
                    Picker("Profile", selection: Binding(
                        get: { selectedProfile?.id },
                        set: { selectedProfileID = $0 }
                    )) {
                        ForEach(activeProfiles.isEmpty ? uniqueProfiles : activeProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                }

                Picker("Format", selection: $format) {
                    ForEach(CareReportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Report", systemImage: "doc.text.magnifyingglass")
            } footer: {
                Text("CSV and PDF reports include logged facts and the current medication plan for sharing at visits. JSON backup remains the restore/import format.")
            }

            Section {
                Picker("Date Range", selection: $rangePreset) {
                    ForEach(CareReportDateRangePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                if rangePreset == .custom {
                    CareReportDatePickerRow(title: "Start", date: $startDate)
                    CareReportDatePickerRow(title: "End", date: $endDate)
                } else {
                    LabeledContent("Start", value: startDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("End", value: endDate.formatted(date: .abbreviated, time: .omitted))
                }
            } header: {
                Label("Dates", systemImage: "calendar")
            }
            .onChange(of: rangePreset) { _, newValue in
                storedRangePreset = newValue.rawValue
                if newValue == .custom {
                    startDate = Date(timeIntervalSinceReferenceDate: storedCustomStart)
                    endDate = Date(timeIntervalSinceReferenceDate: storedCustomEnd)
                    return
                }
                let range = CareReportExportService.defaultRange(for: newValue)
                startDate = range.0
                endDate = range.1
            }
            .onChange(of: startDate) { _, newValue in
                guard rangePreset == .custom else { return }
                storedCustomStart = newValue.timeIntervalSinceReferenceDate
            }
            .onChange(of: endDate) { _, newValue in
                guard rangePreset == .custom else { return }
                storedCustomEnd = newValue.timeIntervalSinceReferenceDate
            }

            Section {
                Toggle("Include notes", isOn: $includeNotes)
                Toggle("Include caregiver names", isOn: $includeCaregiverNames)
                Toggle("Include appointments", isOn: $includeAppointments)
                Toggle("Include milestones", isOn: $includeMilestones)
            } header: {
                Label("Included Details", systemImage: "checklist")
            } footer: {
                Text("Notes and caregiver names are included by default so doctor visit exports are complete. Turn them off for a smaller, more private report.")
            }

            Section {
                Button {
                    export()
                } label: {
                    Label("Export \(format.displayName) Report", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedProfile == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Care Report Export")
        .onChange(of: format) { _, newValue in
            storedFormat = newValue.rawValue
        }
        .onAppear {
            rangePreset = CareReportDateRangePreset(rawValue: storedRangePreset) ?? .last30Days
            format = CareReportFormat(rawValue: storedFormat) ?? .pdf
            if rangePreset == .custom {
                startDate = Date(timeIntervalSinceReferenceDate: storedCustomStart)
                endDate = Date(timeIntervalSinceReferenceDate: storedCustomEnd)
            } else {
                let range = CareReportExportService.defaultRange(for: rangePreset)
                startDate = range.0
                endDate = range.1
            }
            selectedProfileID = selectedProfile?.id
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: defaultFilename
        ) { result in
            if case .failure(let error) = result {
                statusMessage = error.localizedDescription
            }
        }
        .alert("Little Windows", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func export() {
        guard let selectedProfile else {
            statusMessage = "Choose a profile before exporting."
            return
        }
        let options = CareReportExportOptions(
            startDate: startDate,
            endDate: endDate,
            includeNotes: includeNotes,
            includeCaregiverNames: includeCaregiverNames,
            includeAppointments: includeAppointments,
            includeMilestones: includeMilestones
        )
        do {
            exportDocument = CareReportDocument(
                data: try CareReportExportService.export(
                    profile: selectedProfile,
                    format: format,
                    options: options,
                    context: modelContext
                )
            )
            exportContentType = format.contentType
            defaultFilename = CareReportExportService.defaultFilename(
                profile: selectedProfile,
                format: format,
                startDate: startDate,
                endDate: endDate
            )
            showingExporter = true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

private struct CareReportDatePickerRow: View {
    let title: String
    @Binding var date: Date

    private var displayDate: String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            ZStack(alignment: .trailing) {
                Text(displayDate)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsHitTesting(false)

                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .opacity(0.01)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text(displayDate))
                    .frame(width: 156, alignment: .trailing)
            }
            .frame(width: 156, alignment: .trailing)
        }
    }
}
