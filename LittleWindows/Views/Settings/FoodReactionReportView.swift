import CoreTransferable
import PDFKit
import SwiftData
import SwiftUI

struct FoodReactionReportView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: CareProfile

    @AppStorage("foodReactionReportIncludeNotes") private var includeNotes = true
    @AppStorage("foodReactionReportIncludeCaregiverNames") private var includeCaregiverNames = true
    @State private var includeMealsWithoutReactions = false
    @State private var rangePreset: CareReportDateRangePreset = .last30Days
    @State private var startDate = CareReportExportService.defaultRange(for: .last30Days).0
    @State private var endDate = CareReportExportService.defaultRange(for: .last30Days).1
    @State private var previewReport: FoodReactionReport?
    @State private var previewData = Data()
    @State private var showingPreview = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Child", value: profile.name)
                    .accessibilityIdentifier("food-reaction-report.profile")
                Text("Review recorded food reactions and share the report at a visit or care handoff.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Dates") {
                Picker("Date range", selection: $rangePreset) {
                    ForEach(CareReportDateRangePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                if rangePreset == .custom {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                } else {
                    LabeledContent("Start", value: startDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("End", value: endDate.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                Toggle("Include meals without reaction details", isOn: $includeMealsWithoutReactions)
                    .accessibilityIdentifier("food-reaction-report.include-other-meals")
                Toggle("Include notes and response descriptions", isOn: $includeNotes)
                    .accessibilityIdentifier("food-reaction-report.include-notes")
                Toggle("Include caregiver names", isOn: $includeCaregiverNames)
                    .accessibilityIdentifier("food-reaction-report.include-caregivers")
            } header: {
                Text("Included details")
            } footer: {
                Text("Symptoms, recorded severity, timing, and follow-up stay in the report. Turning off notes removes free-text food notes, meal notes, and response descriptions. Review the preview before sharing; free text can contain names or other personal details.")
            }

            Section {
                Button(action: preview) {
                    Label("Preview Report", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(profile.profileType != .child)
                .accessibilityIdentifier("food-reaction-report.preview")
            } footer: {
                Text(FoodReactionReport.notice)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Food Reaction Report")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: rangePreset) { _, preset in
            guard preset != .custom else { return }
            let range = CareReportExportService.defaultRange(for: preset)
            startDate = range.0
            endDate = range.1
        }
        .navigationDestination(isPresented: $showingPreview) {
            if let previewReport {
                FoodReactionReportPreview(report: previewReport, pdfData: previewData)
            }
        }
        .alert("Report unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func preview() {
        do {
            let report = try FoodReactionReportService.makeReport(
                profile: profile,
                options: FoodReactionReportOptions(
                    startDate: startDate, endDate: endDate,
                    includeNotes: includeNotes, includeCaregiverNames: includeCaregiverNames,
                    includeMealsWithoutReactions: includeMealsWithoutReactions
                ),
                context: modelContext
            )
            previewData = FoodReactionReportService.pdfData(for: report)
            previewReport = report
            showingPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FoodReactionReportPreview: View {
    let report: FoodReactionReport
    let pdfData: Data

    @State private var showingExporter = false
    @State private var exportDocument = CareReportDocument()
    @State private var exportFormat: CareReportFormat = .pdf
    @State private var errorMessage: String?

    var body: some View {
        FoodReactionPDFPreview(data: pdfData)
            .accessibilityIdentifier("food-reaction-report.pdf-preview")
            .navigationTitle("Report Preview")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    ShareLink(
                        item: FoodReactionPDFFile(
                            data: pdfData,
                            filename: FoodReactionReportService.defaultFilename(for: report, format: .pdf)
                        ),
                        preview: SharePreview("Food Reaction Report for \(report.profileName)")
                    ) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("food-reaction-report.share-pdf")
                    Menu {
                        Button("Save PDF") { save(.pdf) }
                        Button("Save CSV") { save(.csv) }
                    } label: {
                        Label("Save", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("food-reaction-report.save")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: exportFormat.contentType,
                defaultFilename: FoodReactionReportService.defaultFilename(for: report, format: exportFormat)
            ) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("Couldn’t save report", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func save(_ format: CareReportFormat) {
        exportFormat = format
        exportDocument = CareReportDocument(data: format == .pdf
            ? pdfData : FoodReactionReportService.csvData(for: report))
        showingExporter = true
    }
}

private struct FoodReactionPDFFile: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in file.data }
            .suggestedFileName { $0.filename }
    }
}

private struct FoodReactionPDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
