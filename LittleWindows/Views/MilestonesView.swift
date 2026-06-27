import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum MilestoneSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .category: "By category"
        }
    }
}

private enum MilestoneTimelineItem: Identifiable {
    case automatic(AutomaticMilestoneSummary)
    case memory(MilestoneEntry)

    var id: String {
        switch self {
        case .automatic(let summary): summary.id
        case .memory(let milestone): milestone.id.uuidString
        }
    }

    var date: Date {
        switch self {
        case .automatic(let summary): summary.date
        case .memory(let milestone): milestone.date
        }
    }

    var category: MilestoneCategory {
        switch self {
        case .automatic: .family
        case .memory(let milestone): milestone.category
        }
    }
}

struct MilestonesView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query(sort: \MilestoneEntry.date, order: .reverse) private var allMilestones: [MilestoneEntry]
    @Query(sort: \AgeGuideReadState.updatedAt) private var ageGuideReadStates: [AgeGuideReadState]
    @Query(sort: \PuppyStageGuideReadState.updatedAt) private var puppyStageGuideReadStates: [PuppyStageGuideReadState]
    @Query(sort: \PhotoAttachment.createdAt) private var photoAttachments: [PhotoAttachment]
    @State private var searchText = ""
    @State private var selectedCategory: MilestoneCategory?
    @State private var favoritesOnly = false
    @State private var sortOption = MilestoneSortOption.newest
    @State private var showingSortPicker = false
    @State private var showingEditor = false
    @State private var editingMilestone: MilestoneEntry?
    @State private var selectedTemplate: MilestoneTemplate?
    @State private var automaticSummaries: [AutomaticMilestoneSummary] = []
    @State private var selectedAutomaticSummary: AutomaticMilestoneSummary?
    @State private var selectedAgeGuide: AgeGuide?
    @State private var selectedPuppyStageGuideID: String?
    @State private var showingAgeGuides = false
    @State private var events: [BabyEvent] = []
    @State private var milestonePendingDelete: MilestoneEntry?
    @State private var showingDeleteConfirmation = false
    @StateObject private var profileService = ProfileService.shared

    private var profile: BabyProfile? { profileService.selectedProfile(in: profiles) }
    private var selectedProfileID: UUID? { profile?.id }
    private var isDogProfile: Bool { profile?.profileType == .dog }
    private var milestones: [MilestoneEntry] {
        allMilestones.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var readStates: [AgeGuideReadState] {
        ageGuideReadStates.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var puppyReadStates: [PuppyStageGuideReadState] {
        puppyStageGuideReadStates.filter { $0.matchesProfile(selectedProfileID) }
    }
    private var ageGuides: [AgeGuide] { AgeGuideService.shared.allAgeGuides() }
    private var availableCategories: [MilestoneCategory] {
        MilestoneCategory.categories(for: profile?.profileType ?? .child)
    }
    private var currentAgeGuide: AgeGuide? {
        guard !isDogProfile else { return nil }
        return profile.flatMap { AgeGuideService.shared.currentAgeGuide(for: $0) }
    }
    private var currentAgeMonth: Int? {
        guard !isDogProfile else { return nil }
        return profile.map { AgeGuideService.shared.ageMonth(for: $0) }
    }
    private var currentPuppyStageGuide: PuppyStageGuide? {
        guard isDogProfile, let profile else { return nil }
        return PuppyStageGuideService.shared.currentGuide(for: profile)
    }

    private var timelineItems: [MilestoneTimelineItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let manualItems = milestones.compactMap { milestone -> MilestoneTimelineItem? in
            let matchesCategory = selectedCategory == nil || milestone.category == selectedCategory
            let matchesFavorite = !favoritesOnly || milestone.isFavorite
            let matchesSearch = query.isEmpty
                || milestone.title.lowercased().contains(query)
                || (milestone.notes?.lowercased().contains(query) ?? false)
                || milestone.category.displayName.lowercased().contains(query)
            guard matchesCategory && matchesFavorite && matchesSearch else { return nil }
            return .memory(milestone)
        }
        let automaticItems = automaticSummaries.compactMap {
            summary -> MilestoneTimelineItem? in
            let matchesCategory = selectedCategory == nil || selectedCategory == .family
            let matchesFavorite = !favoritesOnly
            let searchable = [
                summary.title,
                "automatic recap",
                "sleep nursing pumping diapers weight",
                summary.topActivities.map(\.activityType.displayName).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            let matchesSearch = query.isEmpty || searchable.contains(query)
            guard matchesCategory && matchesFavorite && matchesSearch else { return nil }
            return .automatic(summary)
        }
        let filtered = manualItems + automaticItems

        switch sortOption {
        case .newest:
            return filtered.sorted { $0.date > $1.date }
        case .oldest:
            return filtered.sorted { $0.date < $1.date }
        case .category:
            return filtered.sorted {
                if $0.category.displayName != $1.category.displayName {
                    return $0.category.displayName < $1.category.displayName
                }
                return $0.date > $1.date
            }
        }
    }

    private var summaryRefreshToken: String {
        [
            profile?.id.uuidString ?? "no-profile",
            profile?.updatedAt.timeIntervalSinceReferenceDate.description ?? "0"
        ].joined(separator: "-")
    }

    var body: some View {
        List {
            Section {
                memoryHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            featuredGuideSection

            Section {
                controls
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ageGuidesLinkSection

            timelineSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MilestonePalette.background)
        .navigationTitle("Milestones")
        .searchable(text: $searchText, prompt: "Search memories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentEditor()
                } label: {
                    Label("Add milestone", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                MilestoneEditorView(
                    milestone: editingMilestone,
                    template: selectedTemplate
                )
            }
        }
        .task(id: summaryRefreshToken) {
            await refreshAutomaticSummaries()
            handlePendingAgeGuideDeepLink()
        }
        .navigationDestination(item: $selectedAutomaticSummary) { summary in
            AutomaticMilestoneSummaryDetailView(summary: summary)
        }
        .navigationDestination(item: $selectedAgeGuide) { guide in
            AgeGuideDetailView(guide: guide)
        }
        .navigationDestination(item: $selectedPuppyStageGuideID) { guideID in
            if let guide = PuppyStageGuideService.shared.guide(forStageKey: guideID) {
                PuppyStageGuideDetailView(guide: guide, profile: profile)
            }
        }
        .navigationDestination(isPresented: $showingAgeGuides) {
            AgeGuidesListView(
                guides: ageGuides,
                currentMonth: currentAgeMonth,
                readStates: readStates
            )
        }
        .onChange(of: deepLinkRouter.pendingAgeGuideCommand) { _, _ in
            handlePendingAgeGuideDeepLink()
        }
        .onChange(of: deepLinkRouter.isDataReady) { _, ready in
            if ready { handlePendingAgeGuideDeepLink() }
        }
        .confirmationDialog(
            "Delete memory?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Memory", role: .destructive) {
                if let milestonePendingDelete {
                    delete(milestonePendingDelete)
                }
                milestonePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                milestonePendingDelete = nil
            }
        } message: {
            Text("This permanently removes the memory from the timeline.")
        }
    }

    @ViewBuilder
    private var featuredGuideSection: some View {
        if let guide = currentPuppyStageGuide {
            Section {
                puppyStageGuideSection(guide)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "Current Stage", subtitle: guide.title)
            }
        } else if let guide = currentAgeGuide {
            Section {
                currentAgeGuideSection(guide)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                AppSectionHeader(title: "This Month", subtitle: guide.ageLabel)
            }
        }
    }

    @ViewBuilder
    private var ageGuidesLinkSection: some View {
        if !isDogProfile {
            Section {
                NavigationLink {
                    AgeGuidesListView(
                        guides: ageGuides,
                        currentMonth: currentAgeMonth,
                        readStates: readStates
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(MilestonePalette.accent)
                            .frame(width: 38, height: 38)
                            .background(Color.pink.opacity(0.09), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Monthly Age Guides")
                                .font(.subheadline.weight(.semibold))
                            Text("Development notes, play ideas, and milestone prompts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                AppSectionHeader(title: "Age Guides", subtitle: "\(ageGuides.count) guides")
            }
        }
    }

    private var timelineSection: some View {
        Section {
            if timelineItems.isEmpty {
                emptyTimelineView
            } else {
                ForEach(timelineItems) { item in
                    timelineRow(for: item)
                }
            }
        } header: {
            AppSectionHeader(title: "Memory timeline", subtitle: timelineSubtitle)
        }
    }

    private var timelineSubtitle: String? {
        guard !timelineItems.isEmpty else { return nil }
        return timelineItems.count == 1 ? "1 memory" : "\(timelineItems.count) memories"
    }

    private var emptyTimelineView: some View {
        ContentUnavailableView {
            Label(
                milestones.isEmpty && automaticSummaries.isEmpty
                    ? "A place for the little things"
                    : "No memories found",
                systemImage: "heart.text.clipboard"
            )
        } description: {
            Text(emptyTimelineDescription)
        } actions: {
            if milestones.isEmpty && automaticSummaries.isEmpty {
                Button("Capture a memory") {
                    presentEditor()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Clear filters") {
                    clearFilters()
                }
            }
        }
    }

    private var emptyTimelineDescription: String {
        if milestones.isEmpty && automaticSummaries.isEmpty {
            let fallback = isDogProfile ? "your dog" : "your baby"
            return "Capture \(profile?.name ?? fallback)'s firsts, funny moments, and little life changes here."
        }
        return "Try clearing a filter or searching for something else."
    }

    @ViewBuilder
    private func timelineRow(for item: MilestoneTimelineItem) -> some View {
        switch item {
        case .automatic(let summary):
            Button {
                selectedAutomaticSummary = summary
            } label: {
                AutomaticMilestoneSummaryCard(summary: summary)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

        case .memory(let milestone):
            NavigationLink {
                MilestoneDetailView(milestone: milestone)
            } label: {
                MilestoneTimelineRow(
                    milestone: milestone,
                    babyName: profile?.name ?? "Baby",
                    birthDate: profile?.birthDate
                )
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    milestone.isFavorite.toggle()
                    milestone.updatedAt = Date()
                    try? modelContext.save()
                } label: {
                    Label(
                        milestone.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: milestone.isFavorite ? "heart.slash" : "heart.fill"
                    )
                }
                .tint(.pink)
            }
            .swipeActions {
                Button(role: .destructive) {
                    milestonePendingDelete = milestone
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @MainActor
    private func refreshAutomaticSummaries() async {
        guard let profile else {
            events = []
            automaticSummaries = []
            return
        }
        guard !isDogProfile else {
            events = []
            automaticSummaries = []
            return
        }

        await Task.yield()
        do {
            let birthDate = Calendar.current.startOfDay(for: profile.birthDate)
            let profileID = profile.id
            let descriptor = FetchDescriptor<BabyEvent>(
                predicate: #Predicate<BabyEvent> { event in
                    event.profileID == profileID && event.startDate >= birthDate
                },
                sortBy: [SortDescriptor(\BabyEvent.startDate)]
            )
            let fetchedEvents = try modelContext.fetch(descriptor)
            events = fetchedEvents
            automaticSummaries = AutomaticMilestoneSummaryService.summaries(
                profile: profile,
                events: fetchedEvents
            )
        } catch {
            events = []
            automaticSummaries = []
        }
    }

    private var memoryHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(profile?.name ?? "Baby")'s little big moments")
                        .font(.title2.bold())
                    if let profile {
                        Text("\(profile.name) is \(DateFormatting.age(from: profile.birthDate))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.72), in: Circle())
            }

            Button {
                presentEditor()
            } label: {
                Label("Capture a memory", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(MilestonePalette.accent)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.19), Color.orange.opacity(0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.pink.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        "All",
                        systemImage: "square.grid.2x2.fill",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }
                    ForEach(availableCategories) { category in
                        filterChip(
                            category.displayName,
                            systemImage: category.systemImage,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }

            HStack {
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Label("Favorites", systemImage: favoritesOnly ? "heart.fill" : "heart")
                }
                .buttonStyle(.bordered)
                .tint(.pink)

                Spacer()

                Button {
                    showingSortPicker = true
                } label: {
                    Label(sortOption.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .appSurface()
        .appActionSheet(
            isPresented: $showingSortPicker,
            title: "Sort Milestones",
            message: "Choose how memories and milestones are ordered.",
            systemImage: "arrow.up.arrow.down",
            tint: MilestonePalette.accent,
            options: sortOptions
        )
    }

    private var sortOptions: [AppActionSheetOption] {
        MilestoneSortOption.allCases.map { option in
            AppActionSheetOption(
                title: option.title,
                subtitle: sortSubtitle(for: option),
                systemImage: sortSystemImage(for: option),
                tint: MilestonePalette.accent,
                isSelected: sortOption == option
            ) {
                sortOption = option
            }
        }
    }

    private func sortSubtitle(for option: MilestoneSortOption) -> String {
        switch option {
        case .newest: "Show recent memories first."
        case .oldest: "Read from earliest to latest."
        case .category: "Group related milestones together."
        }
    }

    private func sortSystemImage(for option: MilestoneSortOption) -> String {
        switch option {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .category: "square.grid.2x2.fill"
        }
    }

    @ViewBuilder
    private func currentAgeGuideSection(_ guide: AgeGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AgeGuideFeatureCard(
                guide: guide,
                babyName: profile?.name ?? "Baby",
                isCurrent: true,
                isUnread: !readStates.contains {
                    $0.guideID == guide.id && $0.firstOpenedAt != nil
                },
                reachedDate: profile.flatMap {
                    AgeGuideService.shared.monthlyBirthdayDate(
                        for: $0,
                        ageMonth: guide.ageMonth
                    )
                },
                onAddMilestone: {
                    editingMilestone = nil
                    selectedTemplate = guide.milestonePrompts.first?.milestoneTemplate
                    showingEditor = selectedTemplate != nil
                }
            )

            NavigationLink {
                AgeGuideDetailView(guide: guide)
            } label: {
                Label("Read this month's guide", systemImage: "book.pages.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(MilestonePalette.accent)
        }
    }

    @ViewBuilder
    private func puppyStageGuideSection(_ guide: PuppyStageGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(profile?.name ?? "Dog")'s Stage", systemImage: "pawprint.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                        Text(profile.map { "\($0.name) at \(guide.title)" } ?? guide.title)
                            .font(.title3.bold())
                        Text(guide.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: puppyReadStates.contains {
                        $0.guideID == guide.id && $0.firstOpenedAt != nil
                    } ? "checkmark.circle.fill" : "book.pages.fill")
                    .foregroundStyle(.teal)
                    .font(.title3)
                }

                Text(guide.overview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.teal.opacity(0.15), Color.orange.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )

            Button {
                selectedPuppyStageGuideID = guide.id
            } label: {
                Label("Read puppy stage guide", systemImage: "book.pages.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
        }
    }

    private func filterChip(
        _ title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isSelected ? MilestonePalette.accent : Color.primary.opacity(0.055),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func presentEditor(
        milestone: MilestoneEntry? = nil,
        template: MilestoneTemplate? = nil
    ) {
        editingMilestone = milestone
        selectedTemplate = template
        showingEditor = true
    }

    private func clearFilters() {
        searchText = ""
        selectedCategory = nil
        favoritesOnly = false
    }

    private func delete(_ milestone: MilestoneEntry) {
        PhotoAttachmentStore.deleteAttachments(
            with: milestone.photoAttachmentIDs,
            in: photoAttachments,
            context: modelContext
        )
        modelContext.delete(milestone)
        try? modelContext.save()
    }

    private func handlePendingAgeGuideDeepLink() {
        guard !isDogProfile else { return }
        guard deepLinkRouter.isDataReady else { return }
        guard let command = deepLinkRouter.consumeAgeGuideCommand() else { return }
        switch command {
        case .list:
            showingAgeGuides = true
        case .detail(let month):
            selectedAgeGuide = AgeGuideService.shared.ageGuide(for: month)
        }
    }
}

private struct AutomaticMilestoneSummaryCard: View {
    let summary: AutomaticMilestoneSummary

    private var previewMetrics: [AutomaticMilestoneMetric] {
        var values = [
            AutomaticMilestoneMetric(
                title: "Sleep",
                value: DurationFormatting.string(seconds: summary.totalSleepSeconds),
                detail: "\(summary.sleepSessions) times",
                systemImage: "moon.stars.fill",
                tint: .indigo
            ),
            AutomaticMilestoneMetric(
                title: "Nursing",
                value: DurationFormatting.string(seconds: summary.nursingSeconds),
                detail: "\(summary.nursingSessions) sessions",
                systemImage: "figure.and.child.holdinghands",
                tint: .pink
            ),
            AutomaticMilestoneMetric(
                title: "Diapers",
                value: "\(summary.diaperChanges)",
                detail: "changes",
                systemImage: "drop.fill",
                tint: .teal
            )
        ]
        if summary.pumpingSessions > 0 {
            values.append(AutomaticMilestoneMetric(
                title: "Pumping",
                value: "\(summary.pumpingSessions)",
                detail: DurationFormatting.string(seconds: summary.pumpingSeconds),
                systemImage: "waterbottle.fill",
                tint: .blue
            ))
        } else if let gain = summary.weightGainPounds {
            values.append(AutomaticMilestoneMetric(
                title: "Grown",
                value: gain.formattedPoundChange,
                detail: "since birth",
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .green
            ))
        }
        return Array(values.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                    Image(systemName: "party.popper.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 5) {
                    Text("AUTOMATIC RECAP")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.15)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(summary.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(summary.date.formatted(date: .long, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 7)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 9),
                    GridItem(.flexible(), spacing: 9)
                ],
                spacing: 9
            ) {
                ForEach(previewMetrics) { metric in
                    AutomaticMilestoneMetricTile(metric: metric, compact: true)
                }
            }

            if let activity = summary.topActivities.first {
                Label {
                    Text(
                        "Favorite activity: \(activity.activityType.displayName) "
                            + "× \(activity.count)"
                    )
                    .lineLimit(1)
                } icon: {
                    Image(systemName: activity.activityType.systemImage)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            }
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.65, green: 0.24, blue: 0.56),
                        Color(red: 0.91, green: 0.35, blue: 0.42),
                        Color(red: 0.98, green: 0.56, blue: 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                GeometryReader { proxy in
                    Circle()
                        .fill(.white.opacity(0.09))
                        .frame(width: 150, height: 150)
                        .offset(x: proxy.size.width - 88, y: -78)
                    Circle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 90, height: 90)
                        .offset(x: -34, y: proxy.size.height - 45)
                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.12))
                        .offset(x: proxy.size.width - 76, y: proxy.size.height - 60)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.pink.opacity(0.18), radius: 15, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct AutomaticMilestoneSummaryDetailView: View {
    let summary: AutomaticMilestoneSummary

    private var metrics: [AutomaticMilestoneMetric] {
        var values = [
            AutomaticMilestoneMetric(
                title: "Total sleep",
                value: DurationFormatting.string(seconds: summary.totalSleepSeconds),
                detail: "Went to sleep \(summary.sleepSessions) times",
                systemImage: "moon.stars.fill",
                tint: .indigo
            ),
            AutomaticMilestoneMetric(
                title: "Nursing",
                value: DurationFormatting.string(seconds: summary.nursingSeconds),
                detail: "\(summary.nursingSessions) sessions",
                systemImage: "figure.and.child.holdinghands",
                tint: .pink
            ),
            AutomaticMilestoneMetric(
                title: "Diaper changes",
                value: "\(summary.diaperChanges)",
                detail: "Fresh starts",
                systemImage: "drop.fill",
                tint: .teal
            )
        ]
        if summary.pumpingSessions > 0 {
            values.append(AutomaticMilestoneMetric(
                title: "Pumping",
                value: "\(summary.pumpingSessions) sessions",
                detail: DurationFormatting.string(seconds: summary.pumpingSeconds),
                systemImage: "waterbottle.fill",
                tint: .blue
            ))
        }
        if let gain = summary.weightGainPounds {
            values.append(AutomaticMilestoneMetric(
                title: "Weight gained",
                value: gain.formattedPoundChange,
                detail: "From the earliest known weight",
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .green
            ))
        }
        return values
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero

                VStack(alignment: .leading, spacing: 12) {
                    recapSectionTitle("The little things added up", icon: "sparkles")
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(metrics) { metric in
                            AutomaticMilestoneMetricTile(metric: metric)
                        }
                    }
                }
                .padding(.horizontal)

                if !summary.topActivities.isEmpty {
                    activitiesSection
                        .padding(.horizontal)
                }

                Label {
                    Text(
                        "This recap is generated from logged events through "
                            + summary.date.formatted(date: .long, time: .omitted)
                            + ". It updates automatically when history changes."
                    )
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
            .padding(.bottom, 28)
        }
        .background(MilestonePalette.background)
        .navigationTitle("Automatic Recap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 112, height: 112)
                VStack(spacing: -3) {
                    Text(heroNumber)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                    Text(heroUnit.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
            }

            Text(summary.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("A look at everything from birth to this day")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            Text(summary.date.formatted(date: .long, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.60, green: 0.22, blue: 0.56),
                    Color(red: 0.89, green: 0.31, blue: 0.45),
                    Color(red: 0.98, green: 0.56, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 54))
                    .foregroundStyle(.white.opacity(0.12))
                    .padding(22)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 30,
                bottomTrailingRadius: 30
            )
        )
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            recapSectionTitle("Favorite ways to play", icon: "figure.play")

            VStack(spacing: 0) {
                ForEach(Array(summary.topActivities.enumerated()), id: \.element.id) {
                    index,
                    activity in
                    HStack(spacing: 13) {
                        Image(systemName: activity.activityType.systemImage)
                            .font(.headline)
                            .foregroundStyle(activityTint(index))
                            .frame(width: 42, height: 42)
                            .background(
                                activityTint(index).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 13)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.activityType.displayName)
                                .font(.headline)
                            Text(activityDetail(activity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("× \(activity.count)")
                            .font(.title3.bold())
                            .foregroundStyle(activityTint(index))
                    }
                    .padding(14)

                    if index < summary.topActivities.count - 1 {
                        Divider()
                            .padding(.leading, 69)
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func recapSectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(MilestonePalette.accent)
    }

    private var heroNumber: String {
        switch summary.kind {
        case .days(let days): "\(days)"
        case .birthday(let years): "\(years)"
        }
    }

    private var heroUnit: String {
        switch summary.kind {
        case .days: "days"
        case .birthday(let years): years == 1 ? "year" : "years"
        }
    }

    private func activityDetail(_ activity: AutomaticMilestoneActivitySummary) -> String {
        guard activity.durationSeconds >= 60 else {
            return activity.count == 1 ? "1 time" : "\(activity.count) times"
        }
        return DurationFormatting.string(seconds: activity.durationSeconds) + " total"
    }

    private func activityTint(_ index: Int) -> Color {
        [.orange, .purple, .blue][index % 3]
    }
}

private struct AutomaticMilestoneMetric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}

private struct AutomaticMilestoneMetricTile: View {
    let metric: AutomaticMilestoneMetric
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack {
                Image(systemName: metric.systemImage)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(compact ? Color.white : metric.tint)
                Spacer()
            }

            Text(metric.value)
                .font(compact ? .headline : .title3.bold())
                .foregroundStyle(compact ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(compact ? "\(metric.title) · \(metric.detail)" : metric.detail)
                .font(.caption2)
                .foregroundStyle(compact ? .white.opacity(0.72) : .secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 66 : 92, alignment: .leading)
        .padding(compact ? 10 : 13)
        .background(
            compact ? Color.white.opacity(0.14) : metric.tint.opacity(0.09),
            in: RoundedRectangle(cornerRadius: compact ? 14 : 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 14 : 18)
                .stroke(
                    compact ? Color.white.opacity(0.12) : metric.tint.opacity(0.08),
                    lineWidth: 0.5
                )
        }
    }
}

struct MilestoneTimelineRow: View {
    let milestone: MilestoneEntry
    let babyName: String
    let birthDate: Date?
    @Query private var photoAttachments: [PhotoAttachment]

    init(milestone: MilestoneEntry, babyName: String, birthDate: Date?) {
        self.milestone = milestone
        self.babyName = babyName
        self.birthDate = birthDate

        if let attachmentID = milestone.photoAttachmentIDs.first {
            var descriptor = FetchDescriptor<PhotoAttachment>(
                predicate: #Predicate<PhotoAttachment> { attachment in
                    attachment.id == attachmentID
                }
            )
            descriptor.fetchLimit = 1
            _photoAttachments = Query(descriptor)
        } else {
            var descriptor = FetchDescriptor<PhotoAttachment>(
                predicate: #Predicate<PhotoAttachment> { attachment in
                    attachment.ownerKindRawValue == "__missing_milestone_photo__"
                }
            )
            descriptor.fetchLimit = 1
            _photoAttachments = Query(descriptor)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            if let previewData = firstPhoto?.previewData {
                PhotoThumbnailImage(data: previewData)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        if milestone.photoAttachmentIDs.count > 1 {
                            Text("\(milestone.photoAttachmentIDs.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(4)
                        }
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(milestone.category.tint.opacity(0.14))
                    Image(systemName: milestone.category.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(milestone.category.tint)
                }
                .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(milestone.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if milestone.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                }

                HStack(spacing: 5) {
                    Text(milestone.approximateDate ? "Around \(dateText)" : dateText)
                    if let birthDate {
                        Text("·")
                        Text(milestone.ageAtMilestoneDescription(birthDate: birthDate))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let notes = milestone.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(milestone.category.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(milestone.category.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(milestone.category.tint.opacity(0.1), in: Capsule())
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, milestone.isFavorite ? 8 : 0)
        .background(
            milestone.isFavorite ? Color.pink.opacity(0.055) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        milestone.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var firstPhoto: PhotoAttachment? {
        milestone.photoAttachmentIDs.lazy.compactMap { id in
            photoAttachments.first { $0.id == id }
        }.first
    }
}

private struct PhotoAttachmentDisplayItem: Identifiable {
    let id: UUID
    let data: Data
}

private struct PhotoAttachmentGrid: View {
    let items: [PhotoAttachmentDisplayItem]
    var allowsDeletion = false
    var onDelete: ((UUID) -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                PhotoThumbnailImage(data: item.data)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if allowsDeletion {
                            Button {
                                onDelete?(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo")
                        }
                    }
            }
        }
    }
}

private struct PhotoThumbnailImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MilestoneEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query(sort: \PhotoAttachment.createdAt) private var photoAttachments: [PhotoAttachment]
    @AppStorage("caregiverOne") private var caregiverOne = "Caregiver 1"
    @AppStorage("currentCaregiverName") private var currentCaregiverName = ""
    @StateObject private var profileService = ProfileService.shared

    let milestone: MilestoneEntry?
    @State private var title: String
    @State private var date: Date
    @State private var approximateDate: Bool
    @State private var category: MilestoneCategory
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var attachmentIDs: [UUID]
    @State private var photoDrafts: [PhotoAttachmentDraft] = []
    @State private var removedAttachmentIDs: Set<UUID> = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false
    private var activeCaregiverName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: currentCaregiverName,
            primaryName: caregiverOne
        )
    }

    init(milestone: MilestoneEntry? = nil, template: MilestoneTemplate? = nil) {
        self.milestone = milestone
        _title = State(initialValue: milestone?.title ?? template?.title ?? "")
        _date = State(initialValue: milestone?.date ?? Date())
        _approximateDate = State(initialValue: milestone?.approximateDate ?? false)
        _category = State(initialValue: milestone?.category ?? template?.category ?? .firsts)
        _notes = State(initialValue: milestone?.notes ?? "")
        _isFavorite = State(initialValue: milestone?.isFavorite ?? false)
        _attachmentIDs = State(initialValue: milestone?.photoAttachmentIDs ?? [])
    }

    private var profile: BabyProfile? { profileService.selectedProfile(in: profiles) }
    private var activeProfileType: CareProfileType { profile?.profileType ?? .child }
    private var availableCategories: [MilestoneCategory] {
        MilestoneCategory.categories(for: activeProfileType, preserving: category)
    }
    private var suggestedTemplates: [MilestoneTemplate] {
        activeProfileType == .dog ? MilestoneTemplate.dogSuggested : MilestoneTemplate.suggested
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            if milestone == nil {
                Section("Start with an idea") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedTemplates) { template in
                                Button(template.title) {
                                    title = template.title
                                    category = template.category
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Memory") {
                TextField("What happened?", text: $title)
                    .textInputAutocapitalization(.sentences)

                DatePicker(
                    "Date",
                    selection: $date,
                    in: dateRange,
                    displayedComponents: .date
                )

                Toggle("Date is approximate", isOn: $approximateDate)

                Picker("Category", selection: $category) {
                    ForEach(availableCategories) { value in
                        Label(value.displayName, systemImage: value.systemImage)
                            .tag(value)
                    }
                }
            }

            if let profile {
                Section {
                    Label(
                        agePreview(profile: profile),
                        systemImage: "birthday.cake.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MilestonePalette.accent)
                }
            }

            Section("The story") {
                TextField(
                    "Add a detail, quote, or anything you want to remember",
                    text: $notes,
                    axis: .vertical
                )
                .lineLimit(4...9)
            }

            Section {
                Toggle(isOn: $isFavorite) {
                    Label("Favorite memory", systemImage: "heart.fill")
                        .foregroundStyle(isFavorite ? .pink : .primary)
                }
            }

            Section("Photos") {
                if photoDisplayItems.isEmpty {
                    ContentUnavailableView(
                        "No Photos",
                        systemImage: "photo.on.rectangle",
                        description: Text("Add a photo from your library.")
                    )
                    .listRowInsets(EdgeInsets())
                } else {
                    PhotoAttachmentGrid(
                        items: photoDisplayItems,
                        allowsDeletion: true,
                        onDelete: removePhoto
                    )
                    .padding(.vertical, 4)
                }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(1, remainingPhotoSlots),
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        isImportingPhotos ? "Adding Photos" : "Add Photos",
                        systemImage: "photo.badge.plus"
                    )
                }
                .disabled(isImportingPhotos || remainingPhotoSlots == 0)
            }
        }
        .navigationTitle(milestone == nil ? "New Milestone" : "Edit Milestone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            importPhotoItems(items)
        }
    }

    private var dateRange: ClosedRange<Date> {
        let lowerBound = profile?.birthDate ?? Calendar.current.date(
            byAdding: .year,
            value: -5,
            to: Date()
        ) ?? Date()
        return min(lowerBound, Date())...Date()
    }

    private func agePreview(profile: BabyProfile) -> String {
        let preview = MilestoneEntry(
            title: title,
            date: date,
            approximateDate: approximateDate,
            category: category
        )
        return preview.ageSentence(babyName: profile.name, birthDate: profile.birthDate)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let profileID = milestone?.profileID ?? profile?.id

        PhotoAttachmentStore.deleteAttachments(
            with: Array(removedAttachmentIDs),
            in: photoAttachments,
            context: modelContext
        )
        photoDrafts
            .filter { attachmentIDs.contains($0.id) }
            .forEach { draft in
                modelContext.insert(PhotoAttachment(
                    id: draft.id,
                    profileID: profileID,
                    ownerKind: .milestone,
                    contentType: draft.contentType,
                    filename: draft.filename,
                    imageData: draft.imageData,
                    thumbnailData: draft.thumbnailData,
                    createdAt: draft.createdAt,
                    updatedAt: now
                ))
            }

        if let milestone {
            milestone.title = cleanTitle
            milestone.date = date
            milestone.approximateDate = approximateDate
            milestone.category = category
            milestone.notes = cleanNotes.isEmpty ? nil : cleanNotes
            milestone.isFavorite = isFavorite
            milestone.photoAttachmentIDs = attachmentIDs
            milestone.updatedAt = now
        } else {
            modelContext.insert(MilestoneEntry(
                profileID: profileID,
                title: cleanTitle,
                date: date,
                approximateDate: approximateDate,
                category: category,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                photoAttachmentIDs: attachmentIDs,
                createdAt: now,
                updatedAt: now,
                caregiverName: activeCaregiverName,
                isFavorite: isFavorite
            ))
        }
        try? modelContext.save()
        dismiss()
    }

    private var remainingPhotoSlots: Int {
        max(0, 12 - attachmentIDs.count)
    }

    private var photoDisplayItems: [PhotoAttachmentDisplayItem] {
        attachmentIDs.compactMap { id in
            if let draft = photoDrafts.first(where: { $0.id == id }) {
                return PhotoAttachmentDisplayItem(
                    id: draft.id,
                    data: draft.thumbnailData ?? draft.imageData
                )
            }
            guard let attachment = photoAttachments.first(where: { $0.id == id }),
                  let data = attachment.previewData else { return nil }
            return PhotoAttachmentDisplayItem(id: attachment.id, data: data)
        }
    }

    private func importPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            isImportingPhotos = true
            defer {
                isImportingPhotos = false
                selectedPhotoItems = []
            }

            for item in items where remainingPhotoSlots > 0 {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let draft = PhotoAttachmentImageProcessor.draft(from: data)
                else { continue }
                photoDrafts.append(draft)
                attachmentIDs.append(draft.id)
            }
        }
    }

    private func removePhoto(id: UUID) {
        attachmentIDs.removeAll { $0 == id }
        if photoDrafts.contains(where: { $0.id == id }) {
            photoDrafts.removeAll { $0.id == id }
        } else {
            removedAttachmentIDs.insert(id)
        }
    }
}

struct MilestoneDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BabyProfile.createdAt) private var profiles: [BabyProfile]
    @Query(sort: \PhotoAttachment.createdAt) private var photoAttachments: [PhotoAttachment]
    let milestone: MilestoneEntry
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @StateObject private var profileService = ProfileService.shared

    private var profile: BabyProfile? {
        if let profileID = milestone.profileID,
           let matching = profiles.first(where: { $0.id == profileID }) {
            return matching
        }
        return profileService.selectedProfile(in: profiles)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: milestone.category.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(milestone.category.tint)
                        .frame(width: 74, height: 74)
                        .background(milestone.category.tint.opacity(0.13), in: Circle())

                    VStack(spacing: 7) {
                        HStack(spacing: 7) {
                            Text(milestone.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            if milestone.isFavorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                        }
                        Text(milestone.approximateDate ? "Around \(dateText)" : dateText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let profile {
                            Text(milestone.ageSentence(
                                babyName: profile.name,
                                birthDate: profile.birthDate
                            ))
                            .font(.headline)
                            .foregroundStyle(MilestonePalette.accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .listRowBackground(
                    LinearGradient(
                        colors: [
                            milestone.category.tint.opacity(0.15),
                            Color.pink.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Section("Details") {
                LabeledContent("Category", value: milestone.category.displayName)
                if let caregiver = milestone.caregiverName, !caregiver.isEmpty {
                    LabeledContent("Captured by", value: caregiver)
                }
                Toggle("Favorite", isOn: favoriteBinding)
            }

            if let notes = milestone.notes, !notes.isEmpty {
                Section("The story") {
                    Text(notes)
                }
            }

            Section("Photos & videos") {
                if milestonePhotoItems.isEmpty {
                    ContentUnavailableView(
                        "No Photos",
                        systemImage: "photo.on.rectangle.angled"
                    )
                } else {
                    PhotoAttachmentGrid(items: milestonePhotoItems)
                        .padding(.vertical, 4)
                }
            }

            Section {
                Button("Delete Memory", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                MilestoneEditorView(milestone: milestone)
            }
        }
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete Memory?",
            message: "This permanently removes this memory from the timeline.",
            systemImage: "trash",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Delete Memory",
                    subtitle: "Remove this memory now.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    PhotoAttachmentStore.deleteAttachments(
                        with: milestone.photoAttachmentIDs,
                        in: photoAttachments,
                        context: modelContext
                    )
                    modelContext.delete(milestone)
                    try? modelContext.save()
                    dismiss()
                }
            ]
        )
    }

    private var dateText: String {
        milestone.date.formatted(date: .long, time: .omitted)
    }

    private var milestonePhotoItems: [PhotoAttachmentDisplayItem] {
        milestone.photoAttachmentIDs.compactMap { id in
            guard let attachment = photoAttachments.first(where: { $0.id == id }),
                  let data = attachment.previewData else { return nil }
            return PhotoAttachmentDisplayItem(id: attachment.id, data: data)
        }
    }

    private var favoriteBinding: Binding<Bool> {
        Binding(
            get: { milestone.isFavorite },
            set: {
                milestone.isFavorite = $0
                milestone.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }
}

enum MilestonePalette {
    static let accent = Color(red: 0.72, green: 0.28, blue: 0.42)
    static let background = Color(uiColor: .systemGroupedBackground)
}

extension MilestoneCategory {
    static func categories(
        for profileType: CareProfileType,
        preserving selectedCategory: MilestoneCategory? = nil
    ) -> [MilestoneCategory] {
        var categories: [MilestoneCategory]
        switch profileType {
        case .child:
            categories = [
                .firsts, .motor, .social, .communication, .feeding, .sleep,
                .growth, .health, .travel, .family, .funny, .diapering, .custom
            ]
        case .dog:
            categories = [
                .adoption, .training, .pottyTraining, .grooming, .health,
                .growth, .travel, .family, .funny, .favoriteThings, .custom
            ]
        }
        if let selectedCategory, !categories.contains(selectedCategory) {
            categories.append(selectedCategory)
        }
        return categories
    }

    var tint: Color {
        switch self {
        case .firsts: .pink
        case .motor: .indigo
        case .social: .orange
        case .communication: .blue
        case .feeding: .green
        case .sleep: .purple
        case .growth: .mint
        case .health: .red
        case .travel: .cyan
        case .family: .pink
        case .funny: .yellow
        case .diapering: .teal
        case .adoption: .teal
        case .training: .purple
        case .pottyTraining: .brown
        case .grooming: .pink
        case .favoriteThings: .orange
        case .custom: .gray
        }
    }
}
