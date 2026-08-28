import SwiftData
import SwiftUI

private enum CareStoryPeriod: Int, CaseIterable, Identifiable, Sendable {
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90
    case sixMonths = 180

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .fourteenDays: "14d"
        case .thirtyDays: "30d"
        case .ninetyDays: "90d"
        case .sixMonths: "6m"
        }
    }

    var displayName: String {
        switch self {
        case .fourteenDays: "Last 14 days"
        case .thirtyDays: "Last 30 days"
        case .ninetyDays: "Last 90 days"
        case .sixMonths: "Last 6 months"
        }
    }
}

private struct CareStoryRequest: Hashable {
    let profileID: UUID
    let period: CareStoryPeriod
    let anchorDay: Date
}

private struct CareStoryPulseSelection: Identifiable {
    let category: CareStoryCategory
    let dayOffset: Int

    var id: String { "\(category.rawValue)-\(dayOffset)" }
}

@ModelActor
private actor CareStorySnapshotWorker {
    func snapshot(
        profileID: UUID,
        startDate: Date,
        endDate: Date
    ) throws -> CareStorySnapshot {
        try Task.checkCancellation()
        let maximumEventRecordCount = 5_000
        let maximumMedicationCount = 500
        // Care Story intentionally presents at most 12 chapters. Once 12
        // newer anchors exist, older revisions or visits cannot enter the
        // combined chapter list, so decoding hundreds of them is wasted work.
        let maximumRevisionCount = 12
        let maximumAppointmentCount = 12
        let maximumDoseRecordCount = 5_000
        let confirmedCurrentRawValue = MedicationPlanChangeKind.confirmedCurrent.rawValue
        let comparisonStartDate = Calendar.current.date(
            byAdding: .day,
            value: -7,
            to: startDate
        ) ?? startDate.addingTimeInterval(-7 * 86_400)
        var eventDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && $0.startDate >= comparisonStartDate
                    && $0.startDate < endDate
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        // The work remains isolated from the UI, and the limit prevents an
        // unusually dense imported history from producing an unbounded view.
        eventDescriptor.fetchLimit = maximumEventRecordCount + 1
        let fetchedEvents = try modelContext.fetch(eventDescriptor)
        try Task.checkCancellation()
        let eventsWereLimited = fetchedEvents.count > maximumEventRecordCount
        let events = fetchedEvents.prefix(maximumEventRecordCount)
            .filter(EventVisibilityStore.isVisible)
            .compactMap(makeEventRecord)

        var medicationDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        medicationDescriptor.fetchLimit = maximumMedicationCount + 1
        let fetchedMedications = try modelContext.fetch(medicationDescriptor)
        try Task.checkCancellation()
        let medicationsWereLimited = fetchedMedications.count > maximumMedicationCount
        let medications = fetchedMedications.prefix(maximumMedicationCount)
        let medicationNames = Dictionary(uniqueKeysWithValues: medications.map {
            ($0.id, cleanMedicationName($0.name))
        })

        var revisionDescriptor = FetchDescriptor<MedicationPlanRevision>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && $0.effectiveFrom >= startDate
                    && $0.effectiveFrom < endDate
                    && $0.changeKindRawValue != confirmedCurrentRawValue
            },
            sortBy: [SortDescriptor(\MedicationPlanRevision.effectiveFrom, order: .reverse)]
        )
        revisionDescriptor.fetchLimit = maximumRevisionCount + 1
        let fetchedRevisions = try modelContext.fetch(revisionDescriptor)
        try Task.checkCancellation()
        let revisionsWereLimited = fetchedRevisions.count > maximumRevisionCount
        let revisions = fetchedRevisions.prefix(maximumRevisionCount).map { revision in
            let before = revision.beforeSnapshot
            let after = revision.afterSnapshot
            return CareStoryMedicationChangeRecord(
                id: revision.id,
                date: revision.effectiveFrom,
                medicationName: after?.medicationName
                    ?? before?.medicationName
                    ?? medicationNames[revision.medicationID]
                    ?? "Medication",
                changeKind: revision.changeKind,
                source: revision.source,
                beforeDose: doseDescription(before),
                afterDose: doseDescription(after),
                beforeSchedule: scheduleDescription(before),
                afterSchedule: scheduleDescription(after)
            )
        }

        var appointmentDescriptor = FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && $0.startDate >= startDate
                    && $0.startDate < endDate
                    && $0.isCompleted
            },
            sortBy: [SortDescriptor(\DoctorAppointment.startDate, order: .reverse)]
        )
        appointmentDescriptor.fetchLimit = maximumAppointmentCount + 1
        let fetchedAppointments = try modelContext.fetch(appointmentDescriptor)
        try Task.checkCancellation()
        let appointmentsWereLimited = fetchedAppointments.count > maximumAppointmentCount
        let appointments = fetchedAppointments.prefix(maximumAppointmentCount).map {
            CareStoryAppointmentRecord(
                id: $0.id,
                date: $0.startDate,
                title: $0.displayTitle,
                typeName: $0.appointmentType.displayName,
                summary: $0.visitSummary?.nilIfBlank
            )
        }

        let fetchLowerBound = comparisonStartDate
        var doseDescriptor = FetchDescriptor<MedicationDoseRecord>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && $0.loggedAt >= fetchLowerBound
                    && $0.loggedAt < endDate
            },
            sortBy: [SortDescriptor(\MedicationDoseRecord.loggedAt, order: .reverse)]
        )
        doseDescriptor.fetchLimit = maximumDoseRecordCount + 1
        let fetchedDoses = try modelContext.fetch(doseDescriptor)
        try Task.checkCancellation()
        let dosesWereLimited = fetchedDoses.count > maximumDoseRecordCount
        let doses = fetchedDoses.prefix(maximumDoseRecordCount).compactMap { dose -> CareStoryDoseRecord? in
            let status = MedicationDoseStatus(rawValue: dose.statusRawValue) ?? .skipped
            let meaningfulDate = status == .taken
                ? (dose.takenAt ?? dose.scheduledAt ?? dose.loggedAt)
                : (dose.scheduledAt ?? dose.loggedAt)
            guard meaningfulDate >= comparisonStartDate, meaningfulDate < endDate else { return nil }
            return CareStoryDoseRecord(
                id: dose.id,
                date: meaningfulDate,
                medicationName: medicationNames[dose.medicationID] ?? "Medication",
                status: status,
                timing: dose.timingRawValue.flatMap(MedicationDoseTiming.init(rawValue:)),
                reason: dose.reasonRawValue.flatMap(MedicationDoseReason.init(rawValue:)),
                scheduledAmount: dose.doseAmount,
                actualAmount: dose.actualDoseAmount,
                doseUnit: dose.doseUnit
            )
        }

        return CareStoryService.makeSnapshot(
            events: events,
            medicationChanges: revisions,
            doseRecords: doses,
            appointments: appointments,
            dataWasLimited: eventsWereLimited
                || medicationsWereLimited
                || revisionsWereLimited
                || appointmentsWereLimited
                || dosesWereLimited,
            content: .chaptersOnly,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func makeEventRecord(_ event: CareEvent) -> CareStoryEventRecord? {
        let category: CareStoryCategory
        switch event.type {
        case .symptom: category = .symptom
        case .pain: category = .pain
        case .sleep: category = .sleep
        case .activity: category = .activity
        case .bloodPressure, .heartRate, .oxygenSaturation, .respiratoryRate,
             .glucose, .temperature, .growth:
            category = .vital
        default:
            return nil
        }

        let details = event.healthObservationDetails
        let title: String
        let detail: String?
        switch event.type {
        case .symptom:
            let symptom = details.symptomName?.nilIfBlank ?? "Symptom"
            title = symptom
            detail = [
                details.symptomSeverity.map { "Severity \($0) of 5" },
                details.symptomBodyLocation?.nilIfBlank,
                details.symptomResolved == true ? "Marked resolved" : nil
            ].compactMap { $0 }.joined(separator: " · ").nilIfBlank
        case .pain:
            title = details.painScore.map { "Pain \($0)/10" } ?? "Pain"
            detail = details.painLocation?.nilIfBlank
        case .sleep:
            title = event.displayTitle
            detail = event.timelineDurationDescription
        case .activity:
            title = event.displayTitle
            detail = event.timelineDurationDescription
        default:
            title = event.displayTitle
            detail = nil
        }

        return CareStoryEventRecord(
            id: event.id,
            date: event.startDate,
            category: category,
            title: title,
            detail: detail,
            symptomName: details.symptomName?.nilIfBlank,
            symptomSeverity: details.symptomSeverity,
            painScore: details.painScore,
            systolicBloodPressure: event.type == .bloodPressure ? details.systolicBloodPressure : nil,
            diastolicBloodPressure: event.type == .bloodPressure ? details.diastolicBloodPressure : nil,
            durationMinutes: event.endDate.map {
                max(0, $0.timeIntervalSince(event.startDate) / 60)
            }
        )
    }

    private func doseDescription(_ snapshot: MedicationPlanSnapshot?) -> String? {
        guard let amount = snapshot?.doseAmount,
              let unit = snapshot?.doseUnit?.nilIfBlank else { return nil }
        return "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    private func scheduleDescription(_ snapshot: MedicationPlanSnapshot?) -> String? {
        snapshot?.scheduleKind?.displayName
    }

    private func cleanMedicationName(_ value: String) -> String {
        value.nilIfBlank ?? "Medication"
    }
}

struct CareStoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profileAppointments: [DoctorAppointment]
    let profile: CareProfile

    @State private var selectedPeriod: CareStoryPeriod = .ninetyDays
    @State private var selectedChapterID: String?
    @State private var snapshot: CareStorySnapshot?
    @State private var snapshotCache: [CareStoryRequest: CareStorySnapshot] = [:]
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var showingSourceRecords = false
    @State private var selectedPulseCell: CareStoryPulseSelection?
    @State private var showingNewAppointment = false
    @State private var actionNotice: String?

    init(profile: CareProfile) {
        self.profile = profile
        let profileID = profile.id
        let today = Calendar.current.startOfDay(for: Date())
        _profileAppointments = Query(FetchDescriptor<DoctorAppointment>(
            predicate: #Predicate {
                $0.profileID == profileID
                    && !$0.isCompleted
                    && $0.startDate >= today
            },
            sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
        ))
    }

    private var request: CareStoryRequest {
        CareStoryRequest(
            profileID: profile.id,
            period: selectedPeriod,
            anchorDay: Calendar.current.startOfDay(for: Date())
        )
    }

    var body: some View {
        List {
            storyIntroSection
            periodSection

            if let snapshot {
                if snapshot.dataWasLimited {
                    dataLimitSection
                }
                if snapshot.chapters.isEmpty {
                    storyEmptySection
                } else if let chapter = selectedChapter(in: snapshot) {
                    chapterCarouselSection(snapshot.chapters)
                    chapterHeroSection(chapter, snapshot: snapshot)
                    changePulseSection(chapter)
                    domainShiftSection(chapter)
                    discussionSection(chapter)
                }
            } else if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Building the care story…")
                            .foregroundStyle(.secondary)
                    }
                        .accessibilityIdentifier("care-story.loading")
                }
            } else if loadErrorMessage != nil {
                Section {
                    ContentUnavailableView {
                        Label("Care Story couldn’t load", systemImage: "arrow.clockwise.circle")
                    } description: {
                        Text("Your records are unchanged. Try building the story again.")
                    } actions: {
                        Button("Try Again") {
                            Task { await load(request) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .accessibilityIdentifier("care-story.load-error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Care Story")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            await load(request)
        }
        .sheet(isPresented: $showingSourceRecords) {
            if let snapshot,
               let chapter = selectedChapter(in: snapshot) {
                sourceRecordsSheet(chapter)
            }
        }
        .sheet(item: $selectedPulseCell) { selection in
            if let snapshot,
               let chapter = selectedChapter(in: snapshot) {
                pulseRecordsSheet(chapter, selection: selection)
            }
        }
        .sheet(isPresented: $showingNewAppointment) {
            NavigationStack {
                if let snapshot,
                   let chapter = selectedChapter(in: snapshot) {
                    AppointmentEditorView(
                        babyName: profile.name,
                        profileID: profile.id,
                        profileType: profile.profileType,
                        initialQuestions: appointmentQuestions(for: chapter)
                    )
                }
            }
        }
        .alert("Care Story", isPresented: Binding(
            get: { actionNotice != nil },
            set: { if !$0 { actionNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionNotice ?? "")
        }
        .accessibilityIdentifier("care-story.view")
    }

    private var storyIntroSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 5) {
                    Text("See the story around a change")
                        .font(.headline)
                    Text("Compare what was recorded before and after medications, symptoms, pain, or visits.")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("care-story.safety-note")
    }

    private var periodSection: some View {
        Section {
            Picker("Story window", selection: $selectedPeriod) {
                ForEach(CareStoryPeriod.allCases) { period in
                    Text(period.shortName).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("care-story.period-picker")
        } header: {
            AppSectionHeader(title: "Story window", subtitle: selectedPeriod.displayName)
        }
    }

    private var storyEmptySection: some View {
        Section {
            ContentUnavailableView {
                Label("No care episodes yet", systemImage: "sparkles.rectangle.stack")
            } description: {
                Text("Care Story will automatically create chapters from medication changes, repeated symptoms, elevated-pain periods, and completed appointments.")
            } actions: {
                NavigationLink {
                    AdultHealthOverviewView(profile: profile)
                } label: {
                    Text("Open Health Log")
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            AppSectionHeader(title: "Detected chapters", subtitle: selectedPeriod.displayName)
        }
    }

    private var dataLimitSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shorter story window recommended")
                        .font(.subheadline.weight(.semibold))
                    Text("This period contains more records than Care Story can compare responsively. A limited set is shown; try a shorter window for a complete comparison.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityIdentifier("care-story.data-limit")
    }

    private func selectedChapter(in snapshot: CareStorySnapshot) -> CareStoryChapter? {
        if let selectedChapterID,
           let selected = snapshot.chapters.first(where: { $0.id == selectedChapterID }) {
            return selected
        }
        return preferredChapter(in: snapshot.chapters)
    }

    private func preferredChapter(in chapters: [CareStoryChapter]) -> CareStoryChapter? {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -45, to: Date())
            ?? Date().addingTimeInterval(-45 * 86_400)
        let recent = chapters.filter { $0.date >= recentCutoff }
        return recent.first { $0.evidence.level == .strong }
            ?? recent.first { $0.evidence.level == .building }
            ?? chapters.first
    }

    private func chapterCarouselSection(_ chapters: [CareStoryChapter]) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(chapters) { chapter in
                        let isSelected = selectedChapterID == chapter.id
                            || (selectedChapterID == nil
                                && chapter.id == preferredChapter(in: chapters)?.id)
                        Button {
                            withAnimation(.snappy) {
                                selectedChapterID = chapter.id
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: chapterKindIcon(chapter.kind))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : chapterAccent(chapter.kind))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        isSelected ? Color.white.opacity(0.18) : chapterAccent(chapter.kind).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(chapter.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .opacity(0.8)
                                }
                            }
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .frame(width: 200, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        isSelected
                                            ? chapterAccent(chapter.kind)
                                            : chapterAccent(chapter.kind).opacity(0.07)
                                    )
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        isSelected
                                            ? chapterAccent(chapter.kind)
                                            : chapterAccent(chapter.kind).opacity(0.32),
                                        lineWidth: 1
                                    )
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("care-story.chapter-choice.\(chapter.id)")
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityHint("Swipe left or right to browse chapters")
        } header: {
            AppSectionHeader(
                title: "Detected chapters",
                subtitle: "\(chapters.count) · Swipe ↔"
            )
        }
    }

    private func chapterHeroSection(
        _ chapter: CareStoryChapter,
        snapshot: CareStorySnapshot
    ) -> some View {
        let storyDayCount = max(
            1,
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: snapshot.startDate),
                to: Calendar.current.startOfDay(for: snapshot.endDate)
            ).day ?? 1
        )
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(chapterKindName(chapter.kind), systemImage: chapterKindIcon(chapter.kind))
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                    Spacer()
                    Label(chapter.evidence.level.displayName, systemImage: evidenceIcon(chapter.evidence.level))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title)
                        .font(.title2.weight(.bold))
                    Text("\(chapter.date.formatted(date: .abbreviated, time: .omitted)) · \(chapter.sourceLabel)")
                        .font(.subheadline)
                        .opacity(0.86)
                    if let detail = chapter.changeDetail {
                        Text(detail)
                            .font(.caption.weight(.medium))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0.86)
                    }
                }

                Divider().overlay(Color.white.opacity(0.32))

                Text(chapter.pulseHeadline)
                    .font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "circle.grid.3x3.fill")
                    Text(chapter.evidence.coverageDescription)
                }
                .font(.caption)
                .opacity(0.84)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [chapterAccent(chapter.kind), Color.indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .shadow(color: chapterAccent(chapter.kind).opacity(0.22), radius: 16, y: 8)
            .accessibilityIdentifier("care-story.chapter-hero")
            .accessibilityValue("\(storyDayCount)-day story")
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private func changePulseSection(_ chapter: CareStoryChapter) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Grid(horizontalSpacing: 5, verticalSpacing: 10) {
                    GridRow {
                        Color.clear
                            .frame(width: 20, height: 1)
                        Text(chapter.beforeLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(7)
                        Color.clear
                            .frame(height: 15)
                            .overlay {
                                Text(chapterKindCenterLabel(chapter.kind))
                                    .fontWeight(.bold)
                                    .foregroundStyle(chapterAccent(chapter.kind))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        Text(chapter.afterLabel)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .gridCellColumns(6)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(pulseCategories, id: \.self) { category in
                        pulseRow(category, chapter: chapter)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(pulseCategories, id: \.self) { category in
                        Label(category.displayName, systemImage: categoryIcon(category))
                            .font(.caption2)
                            .foregroundStyle(color(for: category))
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(.indigo)
                    Text("Darker = more records · Tap a filled square · Outline = chapter date")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if chapter.sourceRecordCount > 0 {
                    Button {
                        showingSourceRecords = true
                    } label: {
                        Label(sourceRecordButtonTitle(chapter), systemImage: "list.bullet.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(chapterAccent(chapter.kind))
                    .accessibilityIdentifier("care-story.review-sources")
                }
            }
            .padding(.vertical, 4)
        } header: {
            AppSectionHeader(title: "Care pulse", subtitle: "A 14-day care constellation")
                .accessibilityIdentifier("care-story.change-pulse")
        }
    }

    private func pulseRow(
        _ category: CareStoryCategory,
        chapter: CareStoryChapter
    ) -> some View {
        GridRow {
            Image(systemName: categoryIcon(category))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color(for: category))
                .frame(width: 20)
                .accessibilityLabel(category.displayName)
            ForEach(Array(-7...6), id: \.self) { day in
                let count = chapter.signals.first {
                    $0.dayOffset == day && $0.category == category
                }?.count ?? 0
                if count > 0 {
                    Button {
                        selectedPulseCell = CareStoryPulseSelection(
                            category: category,
                            dayOffset: day
                        )
                    } label: {
                        pulseCell(
                            category: category,
                            count: count,
                            isChapterDay: day == 0,
                            chapter: chapter
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(category.displayName), day \(day), \(count) records")
                    .accessibilityHint("Shows the contributing records")
                    .accessibilityIdentifier("care-story.pulse-cell.\(category.rawValue).\(day)")
                } else {
                    pulseCell(
                        category: category,
                        count: count,
                        isChapterDay: day == 0,
                        chapter: chapter
                    )
                    .accessibilityLabel("\(category.displayName), day \(day), no records")
                }
            }
        }
    }

    private func pulseCell(
        category: CareStoryCategory,
        count: Int,
        isChapterDay: Bool,
        chapter: CareStoryChapter
    ) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color(for: category).opacity(pulseOpacity(count)))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        color(for: category).opacity(count == 0 ? 0.16 : 0.28),
                        lineWidth: 0.5
                    )
                if isChapterDay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(chapterAccent(chapter.kind), lineWidth: 1.5)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 4))
    }

    private func domainShiftSection(_ chapter: CareStoryChapter) -> some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(chapter.domainShifts) { shift in
                    domainShiftCard(shift, chapter: chapter)
                }
            }
            .padding(.vertical, 3)
            .accessibilityIdentifier("care-story.domain-shifts")
        } header: {
            AppSectionHeader(
                title: "What shifted",
                subtitle: "\(chapter.evidence.comparableDomainCount) areas comparable"
            )
        } footer: {
            Text("Shifts describe recorded values and frequency only. They do not indicate whether a change was beneficial, harmful, or caused by the chapter event.")
        }
    }

    private func domainShiftCard(
        _ shift: CareStoryDomainShift,
        chapter: CareStoryChapter
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: domainIcon(shift.domain))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(domainColor(shift.domain))
                    .frame(width: 28, height: 28)
                    .background(domainColor(shift.domain).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Image(systemName: shiftIcon(shift.direction))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(shiftColor(shift.direction))
            }
            Text(shift.domain.displayName)
                .font(.caption.weight(.semibold))
            Text(shift.changeLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(shiftColor(shift.direction))
            HStack(spacing: 4) {
                Text(shift.beforeValue)
                Image(systemName: "arrow.right")
                Text(shift.afterValue)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(shift.domain.displayName), \(shift.changeLabel), \(chapter.beforeLabel) \(shift.beforeValue), \(chapter.afterLabel) \(shift.afterValue)"
        )
    }

    private func discussionSection(_ chapter: CareStoryChapter) -> some View {
        Section {
            ForEach(Array(chapter.discussionPrompts.enumerated()), id: \.offset) { index, prompt in
                HStack(alignment: .top, spacing: 11) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(chapterAccent(chapter.kind), in: Circle())
                    Text(prompt)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, 3)
            }

            if upcomingAppointments.count == 1,
               let appointment = upcomingAppointments.first {
                Button {
                    addQuestions(appointmentQuestions(for: chapter), to: appointment)
                } label: {
                    Label(
                        "Add to \(appointment.displayTitle)",
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(chapterAccent(chapter.kind))
                .accessibilityIdentifier("care-story.add-to-appointment")
            } else if !upcomingAppointments.isEmpty {
                Menu {
                    ForEach(upcomingAppointments) { appointment in
                        Button {
                            addQuestions(appointmentQuestions(for: chapter), to: appointment)
                        } label: {
                            Label {
                                Text(
                                    "\(appointment.displayTitle) · \(appointment.startDate.formatted(date: .abbreviated, time: .omitted))"
                                )
                            } icon: {
                                Image(systemName: appointment.appointmentType.systemImage)
                            }
                        }
                    }
                } label: {
                    Label("Add to an upcoming appointment", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(chapterAccent(chapter.kind))
                .accessibilityIdentifier("care-story.choose-appointment")
            } else {
                Button {
                    showingNewAppointment = true
                } label: {
                    Label("Create a visit with these questions", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(chapterAccent(chapter.kind))
                .accessibilityIdentifier("care-story.plan-appointment")
            }

            ShareLink(item: episodeShareText(chapter)) {
                Label("Share this story", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(chapterAccent(chapter.kind))
            .accessibilityIdentifier("care-story.share-chapter")
        } header: {
            AppSectionHeader(title: "Questions worth asking", subtitle: "Turn patterns into a conversation")
        } footer: {
            Text("Sharing sends only this episode’s context. Use Care Report when a complete clinical or caregiver handoff is needed.")
        }
    }

    private var upcomingAppointments: [DoctorAppointment] {
        let today = Calendar.current.startOfDay(for: Date())
        return profileAppointments.filter { $0.startDate >= today }
    }

    private func appointmentQuestions(for chapter: CareStoryChapter) -> [String] {
        let context = "\(chapter.title) (\(chapter.date.formatted(date: .abbreviated, time: .omitted)))"
        return chapter.discussionPrompts.map { "\(context): \($0)" }
    }

    private func addQuestions(
        _ questions: [String],
        to appointment: DoctorAppointment
    ) {
        guard let addedCount = HouseholdAttentionService.addAppointmentQuestions(
            questions,
            to: appointment,
            context: modelContext
        ) else {
            actionNotice = "The questions couldn’t be saved. Please try again."
            return
        }
        if addedCount == 0 {
            actionNotice = "These questions are already in \(appointment.displayTitle)."
        } else {
            let word = addedCount == 1 ? "question" : "questions"
            actionNotice = "Added \(addedCount) \(word) to \(appointment.displayTitle)."
        }
    }

    private func sourceRecordButtonTitle(_ chapter: CareStoryChapter) -> String {
        if chapter.sourceRecords.count < chapter.sourceRecordCount {
            return "Review \(chapter.sourceRecords.count) of \(chapter.sourceRecordCount) records"
        }
        let word = chapter.sourceRecordCount == 1 ? "record" : "records"
        return "Review \(chapter.sourceRecordCount) contributing \(word)"
    }

    private func pulseRecordsSheet(
        _ chapter: CareStoryChapter,
        selection: CareStoryPulseSelection
    ) -> some View {
        let calendar = Calendar.current
        let chapterDay = calendar.startOfDay(for: chapter.date)
        let selectedDay = calendar.date(
            byAdding: .day,
            value: selection.dayOffset,
            to: chapterDay
        ) ?? chapterDay
        let expectedCount = chapter.signals.first {
            $0.dayOffset == selection.dayOffset
                && $0.category == selection.category
        }?.count ?? 0
        let records = chapter.sourceRecords
            .filter {
                $0.category == selection.category
                    && calendar.isDate($0.date, inSameDayAs: selectedDay)
            }
            .sorted { $0.date > $1.date }

        return NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: categoryIcon(selection.category))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(color(for: selection.category))
                            .frame(width: 38, height: 38)
                            .background(
                                color(for: selection.category).opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selection.category.displayName)
                                .font(.headline)
                            Text(selectedDay.formatted(date: .complete, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(expectedCount) contributing \(expectedCount == 1 ? "record" : "records")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 3)
                }

                Section("Recorded details") {
                    if records.isEmpty {
                        Text("This record is outside the story’s compact detail list. Open Health Log to see the complete day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(records) { record in
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: categoryIcon(record.category))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(color(for: record.category))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        color(for: record.category).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title)
                                        .font(.subheadline.weight(.semibold))
                                    if let detail = record.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(record.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if records.count < expectedCount && !records.isEmpty {
                    Section {
                        Text("Showing \(records.count) of \(expectedCount) records kept in this story. Health Log has the complete day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        AdultHealthOverviewView(profile: profile)
                    } label: {
                        Label("Open Health Log", systemImage: "waveform.path.ecg.rectangle")
                    }
                } footer: {
                    Text("Use Health Log to review related history or correct an entry.")
                }
            }
            .navigationTitle("Day Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selectedPulseCell = nil }
                }
            }
            .accessibilityIdentifier("care-story.pulse-records")
        }
    }

    private func sourceRecordsSheet(_ chapter: CareStoryChapter) -> some View {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: chapter.sourceRecords) {
            calendar.startOfDay(for: $0.date)
        }
        let days = grouped.keys.sorted(by: >)
        return NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(chapter.title)
                            .font(.headline)
                        Text("These are the exact records counted in this chapter’s 14-day pulse. Routine taken doses are summarized in Dose consistency; only dose exceptions appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(days, id: \.self) { day in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(grouped[day] ?? []) { record in
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: categoryIcon(record.category))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(color(for: record.category))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        color(for: record.category).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title)
                                        .font(.subheadline.weight(.semibold))
                                    if let detail = record.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(
                                        "\(record.date.formatted(date: .omitted, time: .shortened)) · \(record.date < chapter.date ? chapter.beforeLabel : chapter.afterLabel)"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if chapter.sourceRecords.count < chapter.sourceRecordCount {
                    Section {
                        Text("Showing the 80 most recent contributing records to keep this view responsive. The chapter totals still include every contributing record loaded for this story.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        AdultHealthOverviewView(profile: profile)
                    } label: {
                        Label("Open Health Log", systemImage: "waveform.path.ecg.rectangle")
                    }
                } footer: {
                    Text("Use Health Log to review the broader record history or correct an entry.")
                }
            }
            .navigationTitle("Story evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSourceRecords = false }
                }
            }
            .accessibilityIdentifier("care-story.source-records")
        }
    }

    @MainActor
    private func load(_ request: CareStoryRequest) async {
        isLoading = true
        loadErrorMessage = nil
        if let cached = snapshotCache[request] {
            snapshot = cached
            if !cached.chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = preferredChapter(in: cached.chapters)?.id
            }
            isLoading = false
            return
        }
        snapshot = nil
        let calendar = Calendar.current
        let endDate = calendar.startOfNextDay(for: request.anchorDay)
        let startDate = calendar.date(
            byAdding: .day,
            value: -request.period.rawValue,
            to: endDate
        ) ?? endDate.addingTimeInterval(Double(-request.period.rawValue) * 86_400)
        let worker = CareStorySnapshotWorker(modelContainer: modelContext.container)
        let result: CareStorySnapshot
        do {
            result = try await worker.snapshot(
                profileID: request.profileID,
                startDate: startDate,
                endDate: endDate
            )
        } catch {
            guard !Task.isCancelled, self.request == request else { return }
            loadErrorMessage = "The story couldn’t be built from the saved records."
            isLoading = false
            return
        }
        guard !Task.isCancelled, self.request == request else { return }
        if snapshotCache.count >= CareStoryPeriod.allCases.count {
            snapshotCache.removeAll(keepingCapacity: true)
        }
        snapshotCache[request] = result
        snapshot = result
        if !result.chapters.contains(where: { $0.id == selectedChapterID }) {
            selectedChapterID = preferredChapter(in: result.chapters)?.id
        }
        isLoading = false
    }

    private func episodeShareText(_ chapter: CareStoryChapter) -> String {
        let shifts = chapter.domainShifts
            .filter(\.isComparable)
            .map { "• \($0.domain.displayName): \($0.beforeValue) → \($0.afterValue) (\($0.changeLabel.lowercased()))" }
            .joined(separator: "\n")
        let shiftText = shifts.isEmpty ? "• No domains have enough data in both windows yet." : shifts
        let prompts = chapter.discussionPrompts.map { "• \($0)" }.joined(separator: "\n")
        let detail = chapter.changeDetail.map { "\n\($0)" } ?? ""
        return """
        Care Story for \(profile.name)
        \(chapter.title)
        \(chapter.date.formatted(date: .abbreviated, time: .omitted)) · \(chapter.sourceLabel)\(detail)

        Context strength: \(chapter.evidence.level.displayName)
        \(chapter.evidence.coverageDescription)

        \(chapter.pulseHeadline)

        Recorded shifts
        \(shiftText)

        Questions worth asking
        \(prompts)

        This story describes recorded timing and values only. It does not identify causes, diagnose conditions, or recommend treatment. Use Care Report for a complete record.
        """
    }

    private var pulseCategories: [CareStoryCategory] {
        [.medication, .symptom, .pain, .sleep, .activity, .vital]
    }

    private func pulseOpacity(_ count: Int) -> Double {
        switch count {
        case 0: 0.12
        case 1: 0.36
        case 2: 0.62
        default: 0.9
        }
    }

    private func chapterKindName(_ kind: CareStoryChapterKind) -> String {
        switch kind {
        case .medicationChange: "Medication change"
        case .symptomEpisode: "Symptom episode"
        case .painEpisode: "Pain episode"
        case .appointment: "Care visit"
        }
    }

    private func chapterKindCenterLabel(_ kind: CareStoryChapterKind) -> String {
        switch kind {
        case .medicationChange: "Change"
        case .symptomEpisode, .painEpisode: "Start"
        case .appointment: "Visit"
        }
    }

    private func chapterKindIcon(_ kind: CareStoryChapterKind) -> String {
        switch kind {
        case .medicationChange: "pills.fill"
        case .symptomEpisode: "waveform.path.ecg"
        case .painEpisode: "bandage.fill"
        case .appointment: "stethoscope"
        }
    }

    private func chapterAccent(_ kind: CareStoryChapterKind) -> Color {
        switch kind {
        case .medicationChange: .indigo
        case .symptomEpisode: .orange
        case .painEpisode: .pink
        case .appointment: .teal
        }
    }

    private func evidenceIcon(_ level: CareStoryEvidenceLevel) -> String {
        switch level {
        case .early: "sparkles"
        case .building: "circle.dotted"
        case .strong: "checkmark.seal.fill"
        }
    }

    private func categoryIcon(_ category: CareStoryCategory) -> String {
        switch category {
        case .medication: "pills.fill"
        case .symptom: "exclamationmark.triangle.fill"
        case .pain: "bandage.fill"
        case .vital: "waveform.path.ecg"
        case .sleep: "moon.stars.fill"
        case .activity: "figure.walk"
        }
    }

    private func domainIcon(_ domain: CareStoryDomain) -> String {
        switch domain {
        case .symptoms: "exclamationmark.triangle.fill"
        case .pain: "bandage.fill"
        case .sleep: "moon.stars.fill"
        case .activity: "figure.walk"
        case .bloodPressure: "heart.text.square.fill"
        case .doseConsistency: "pills.fill"
        }
    }

    private func domainColor(_ domain: CareStoryDomain) -> Color {
        switch domain {
        case .symptoms: .orange
        case .pain: .pink
        case .sleep: .indigo
        case .activity: .green
        case .bloodPressure: .blue
        case .doseConsistency: .purple
        }
    }

    private func shiftIcon(_ direction: CareStoryShiftDirection) -> String {
        switch direction {
        case .higher: "arrow.up.right"
        case .lower: "arrow.down.right"
        case .similar: "equal"
        case .insufficient: "ellipsis"
        }
    }

    private func shiftColor(_ direction: CareStoryShiftDirection) -> Color {
        switch direction {
        case .higher: .orange
        case .lower: .indigo
        case .similar: .secondary
        case .insufficient: .gray
        }
    }

    private func color(for category: CareStoryCategory) -> Color {
        switch category {
        case .medication: .red
        case .symptom: .orange
        case .pain: .pink
        case .vital: .blue
        case .sleep: .indigo
        case .activity: .green
        }
    }

}
