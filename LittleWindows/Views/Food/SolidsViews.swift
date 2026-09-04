import SwiftData
import SwiftUI
import UIKit
import Combine

private struct SolidsDrawerSelectionButton: View {
    let title: String
    let value: String
    var systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(value)
    }
}

struct SolidsHomeView: View {
    @Environment(\.modelContext) private var modelContext

    let profile: CareProfile
    let accessLevel: SolidsAccessLevel
    let progress: [SolidFoodProgress]
    let plans: [PlannedSolidMeal]
    let eventItems: [SolidFoodEventItem]
    let profileState: SolidsProfileState?
    let open: (FoodRoute) -> Void

    @State private var isActivating = false
    @State private var activationError: String?
    @State private var stateWriter: SolidsProfileStateWriter?
    @State private var backfillWriter: SolidsBackfillWriter?

    private var ageMonths: Int {
        SolidsTrackingService.ageMonths(for: profile)
    }

    private var scopedProgress: [SolidFoodProgress] {
        progress.filter { $0.profileID == profile.id }
    }

    private var upcomingPlans: [PlannedSolidMeal] {
        plans.filter { $0.profileID == profile.id && !$0.isCompleted }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if accessLevel == .readinessPreview {
                    readinessPreview
                } else {
                    dashboard
                }
                safetyFooter
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .task {
            if stateWriter == nil {
                stateWriter = await SolidsWriterPool.shared.profileStateWriter(
                    for: modelContext.container
                )
            }
            guard accessLevel == .full else { return }
            if let error = await resolvedBackfillWriter().backfill(profileID: profile.id).error {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
        .alert("Couldn’t start solids", isPresented: Binding(
            get: { activationError != nil },
            set: { if !$0 { activationError = nil } }
        )) {
            Button("OK") { activationError = nil }
        } message: {
            Text(activationError ?? "")
        }
    }

    @MainActor
    private func resolvedBackfillWriter() async -> SolidsBackfillWriter {
        if let backfillWriter { return backfillWriter }
        let writer = await SolidsWriterPool.shared.backfillWriter(for: modelContext.container)
        backfillWriter = writer
        return writer
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "carrot.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text("Solids for \(profile.name)")
                    .font(.title2.bold())
                Text(accessLevel == .readinessPreview
                    ? "A readiness preview for the months ahead"
                    : "Prepare, plan, and track foods in one place")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .appSurface()
    }

    private var readinessPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Think readiness, not a birthday", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Many children begin complementary foods around 6 months. Before starting, look for coordinated head and neck control, supported upright sitting, bringing objects to the mouth, and swallowing food rather than pushing it back out.")
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 10) {
                readinessRow("Sits upright with support and controls head and neck")
                readinessRow("Opens their mouth or reaches when food is offered")
                readinessRow("Moves food from the front of the tongue to swallow")
                readinessRow("Caregiver feels ready to supervise every meal")
            }
            Text("Readiness varies. A pediatric clinician can help if you are unsure, especially for a child born early or with feeding or developmental concerns.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await activateWorkspace() }
            } label: {
                Label(
                    isActivating ? "Starting workspace…" : "Start solids workspace",
                    systemImage: "arrow.right.circle.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isActivating)
        }
        .padding(16)
        .appSurface()
    }

    private func readinessRow(_ text: String) -> some View {
        Label(text, systemImage: "circle")
            .font(.subheadline)
            .foregroundStyle(.primary)
    }

    private var dashboard: some View {
        let visibleProgress = scopedProgress
        let visiblePlans = upcomingPlans
        let digestiveAssessment = SolidsDigestiveSupportService.assessment(
            profileID: profile.id,
            ageMonths: ageMonths,
            eventItems: eventItems,
            state: profileState
        )
        let showsDigestiveSupport = SolidsDigestiveSupportService.isSupportAvailable(
            ageMonths: ageMonths,
            state: profileState,
            assessment: digestiveAssessment
        )
        return VStack(alignment: .leading, spacing: 16) {
            if digestiveAssessment.activeConcern != nil
                    || digestiveAssessment.shouldSurfaceProactively {
                Button { open(.solidsDigestive) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: digestiveAssessment.activeConcern == nil
                            ? "leaf.circle.fill"
                            : "cross.case.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(digestiveAssessment.activeConcern == nil
                                ? "A feeding pattern to review"
                                : "Digestive concern is active")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(digestiveAssessment.activeConcern == nil
                                ? "See gentle ideas for broadening the foods logged this week."
                                : "Review comfort, safety signs, and follow-up suggestions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .appSurface(cornerRadius: 17)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("solids.digestive.proactive")
            }

            HStack(spacing: 10) {
                metric(
                    value: "\(visibleProgress.lazy.filter { $0.status == .tried }.count)",
                    label: "Foods tried",
                    route: .solidsTracker(.tried),
                    accessibilityIdentifier: "solids.metric.tried"
                )
                metric(
                    value: "\(visibleProgress.lazy.filter { $0.status == .wantToTry }.count)",
                    label: "Want to try",
                    route: .solidsTracker(.wantToTry),
                    accessibilityIdentifier: "solids.metric.want-to-try"
                )
                metric(
                    value: "\(visiblePlans.count)",
                    label: "Planned",
                    route: .solidsPlan,
                    accessibilityIdentifier: "solids.metric.planned"
                )
            }

            Button {
                startSolidLog(.empty)
            } label: {
                Label("Log solids", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Text("Explore")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                destinationCard("Guided solids", "A practical next step", "point.forward.to.point.capsulepath", .solidsGuided)
                destinationCard("Food database", "400+ foods", "books.vertical.fill", .solidsDatabase)
                destinationCard("Plan meals", visiblePlans.isEmpty ? "Build the next plate" : "\(visiblePlans.count) upcoming", "calendar.badge.plus", .solidsPlan)
                destinationCard("Food tracker", "Foods and meal history", "checklist", .solidsTracker(.all))
                destinationCard("Allergens", "9 major allergens", "allergens", .solidsAllergens)
                destinationCard("Recipes", "400+ simple ideas", "fork.knife", .solidsRecipes)
                if showsDigestiveSupport {
                    destinationCard("Feeding balance", "Comfort & variety", "leaf.circle.fill", .solidsDigestive)
                }
            }

            if showsDigestiveSupport {
                Button { open(.solidsDigestive) } label: {
                    Label("Constipation concern today", systemImage: "cross.case.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("solids.digestive.check-in")
            }

            Button {
                openFeedingReport()
            } label: {
                Label("View feeding report", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityIdentifier("solids.view-feeding-report")

            if let next = visiblePlans.first {
                Button {
                    open(.plannedSolidMeal(next.id))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next planned meal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(next.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .appSurface(cornerRadius: 17)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metric(
        value: String,
        label: String,
        route: FoodRoute,
        accessibilityIdentifier: String
    ) -> some View {
        Button {
            open(route)
        } label: {
            VStack(spacing: 3) {
                Text(value).font(.title3.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .appSurface(cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityHint("Opens the corresponding list")
    }

    private func destinationCard(
        _ title: String,
        _ subtitle: String,
        _ image: String,
        _ route: FoodRoute
    ) -> some View {
        Button { open(route) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: image)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(14)
            .appSurface(cornerRadius: 17)
        }
        .buttonStyle(.plain)
    }

    private var safetyFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Safety basics", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
            Text("Seat \(profile.name) upright and supervise every bite. Preparation guidance is educational and should be adapted to individual development and medical advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
    }

    private func startSolidLog(_ preset: SolidFeedEditorPreset) {
        let router = DeepLinkRouter.shared
        router.openToday(action: .logSolidFeed(preset), profileID: profile.id)
    }

    private func openFeedingReport() {
        let router = DeepLinkRouter.shared
        router.pendingProfileID = profile.id
        router.pendingInsightsSection = .feeding
        router.pendingFeedingInsightsMode = .solids
        router.selectedReportsMode = .summary
        router.selectedTab = .reports
    }

    private func activateWorkspace() async {
        isActivating = true
        defer { isActivating = false }
        let writer: SolidsProfileStateWriter
        if let stateWriter {
            writer = stateWriter
        } else {
            writer = await SolidsWriterPool.shared.profileStateWriter(for: modelContext.container)
        }
        stateWriter = writer
        if let error = await writer.activate(profileID: profile.id) {
            PersistenceService.recordLocalSaveFailure(error)
            activationError = "The solids workspace could not be started. Please try again."
        } else {
            SystemIntegrationReconciler.requestReconciliation()
        }
    }
}

struct SolidsGuidedPathView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: CareProfile
    let progress: [SolidFoodProgress]
    let allergenProgress: [SolidAllergenProgress]
    let plans: [PlannedSolidMeal]
    let profileState: SolidsProfileState?
    let openFood: (String) -> Void
    let openRecipe: (String) -> Void
    let openPlan: (UUID) -> Void

    @State private var selectedStartDate = Date()
    @State private var cachedSuggestions: [SolidsGuidedMealSuggestion] = []
    @State private var showingBuildConfirmation = false
    @State private var buildResultMessage: String?
    @State private var isBuildingJourney = false
    @State private var isUpdatingJourney = false
    @State private var planWriter: SolidsGuidedPlanWriter?

    private var scopedProgress: [SolidFoodProgress] {
        progress.filter { $0.profileID == profile.id }
    }

    private var triedIDs: Set<String> {
        Set(scopedProgress.filter { $0.status == .tried }.map(\.foodID))
    }

    private var completedSkillIDs: Set<String> {
        Set(profileState?.completedFeedingSkillIDs ?? [])
    }

    private var toleratedAllergenIDs: Set<String> {
        Set(allergenProgress.filter {
            $0.profileID == profile.id && $0.status == .tolerated
        }.map(\.allergenID))
    }

    private var blockedAllergenNames: [String] {
        allergenProgress.filter {
            $0.profileID == profile.id
                && ($0.status == .suspectedReaction || $0.status == .avoidPendingAdvice)
        }.compactMap { SolidsAllergen(rawValue: $0.allergenID)?.displayName }.sorted()
    }

    private var earliestGuidedStartDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let birthDate = profile.birthDate else { return today }
        let sixMonthDate = calendar.date(byAdding: .month, value: 6, to: birthDate) ?? today
        return max(today, calendar.startOfDay(for: sixMonthDate))
    }

    private var suggestionStartDate: Date {
        guard let last = upcomingPlans.last?.scheduledAt else {
            return max(earliestGuidedStartDate, profileState?.guidedStartDate ?? selectedStartDate)
        }
        let dayAfterLast = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        return max(earliestGuidedStartDate, dayAfterLast)
    }

    private var remainingFoodCount: Int {
        let plannedIDs = Set(plans.filter {
            $0.profileID == profile.id && !$0.isCompleted
        }.flatMap(\.foodIDs))
        return max(0, 100 - triedIDs.union(plannedIDs).count)
    }

    private var allSuggestions: [SolidsGuidedMealSuggestion] {
        cachedSuggestions
    }

    private var suggestions: [SolidsGuidedMealSuggestion] {
        Array(allSuggestions.prefix(7))
    }

    private var upcomingPlans: [PlannedSolidMeal] {
        plans.filter {
            $0.profileID == profile.id && $0.isGuided && !$0.isCompleted
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var nextUpcomingPlans: [PlannedSolidMeal] {
        Array(upcomingPlans.prefix(7))
    }

    private var laterUpcomingPlanCount: Int {
        max(0, upcomingPlans.count - nextUpcomingPlans.count)
    }

    private var suggestionRefreshKey: Int {
        var refreshHash = selectedStartDate.hashValue
        for item in progress where item.profileID == profile.id {
            var hasher = Hasher()
            hasher.combine(item.id)
            hasher.combine(item.statusRawValue)
            hasher.combine(item.updatedAt)
            refreshHash ^= hasher.finalize()
        }
        for plan in plans where plan.profileID == profile.id {
            var hasher = Hasher()
            hasher.combine(plan.id)
            hasher.combine(plan.completedEventID)
            hasher.combine(plan.updatedAt)
            refreshHash ^= hasher.finalize()
        }
        for item in allergenProgress where item.profileID == profile.id {
            var hasher = Hasher()
            hasher.combine(item.allergenID)
            hasher.combine(item.statusRawValue)
            hasher.combine(item.introductionStep)
            hasher.combine(item.updatedAt)
            refreshHash ^= hasher.finalize()
        }
        // Skills affect only preparation wording. Keeping them out of this key
        // avoids rebuilding the entire remaining journey on every checkmark.
        return refreshHash
    }

    var body: some View {
        let visibleTriedIDs = triedIDs
        let visibleToleratedAllergenIDs = toleratedAllergenIDs
        let visibleBlockedAllergenNames = blockedAllergenNames
        let visibleUpcomingPlans = nextUpcomingPlans
        let visibleLaterUpcomingPlanCount = laterUpcomingPlanCount
        let visibleSuggestions = suggestions
        let visibleRemainingFoodCount = remainingFoodCount
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(min(100, visibleTriedIDs.count)) of 100 foods")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    ProgressView(value: Double(min(100, visibleTriedIDs.count)), total: 100)
                        .tint(.orange)
                    Text(visibleTriedIDs.count >= 100 ? "First 100 complete" : "Build variety at a comfortable pace")
                        .font(.title3.bold())
                    Text(developmentDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

            }

            if !visibleBlockedAllergenNames.isEmpty {
                Section("Safety pauses") {
                    Label(visibleBlockedAllergenNames.joined(separator: ", "), systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.red)
                    Text("These allergens are excluded from new suggestions until their status changes. Other foods continue to count toward the First 100.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if profileState?.guidedStartDate == nil {
                Section("Create your guided plan") {
                    Label("1. Choose the first meal date", systemImage: "calendar")
                        .font(.headline)
                    Text("This date sets the calendar for the recommendations below. Changing it does not save or schedule anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "First meal",
                        selection: $selectedStartDate,
                        in: earliestGuidedStartDate...,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("solids.guided.start-date")

                    Label("2. Review the first week", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Text("The opening meals use one simple food at a time, including an iron-rich choice and familiar repeats. Allergen introductions stay separate, and recipes appear only after their other ingredients are familiar. Tap any meal for its preparation guidance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if visibleSuggestions.isEmpty {
                        Label("No new guided meals are available right now.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleSuggestions) { suggestion in
                            suggestionRow(suggestion)
                        }

                        Text("Previewing \(visibleSuggestions.count) of \(allSuggestions.count) suggested meals.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        buildJourneyButton(title: "Add full journey to Planner")

                        Text("Nothing is added until you confirm. All \(allSuggestions.count) meals remain editable, so you can swap meals or shift dates later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let startDate = profileState?.guidedStartDate {
                Section("Journey") {
                    LabeledContent("Started", value: startDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Foods still to plan", value: "\(visibleRemainingFoodCount)")
                }

                if !visibleUpcomingPlans.isEmpty {
                    Section("Next planned meals") {
                        Text("Your next seven guided meals are shown here. Open any meal to edit it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(visibleUpcomingPlans) { plan in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { openPlan(plan.id) } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(plan.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                            Text(plan.title).font(.subheadline.weight(.semibold))
                                            if !plan.notes.isEmpty {
                                                Text(plan.notes).font(.caption).foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Button(isUpdatingJourney ? "Updating meal…" : "Swap this meal") {
                                    Task { await swap(plan) }
                                }
                                    .font(.caption.weight(.semibold))
                                    .disabled(isUpdatingJourney)
                            }
                        }

                        if visibleLaterUpcomingPlanCount > 0 {
                            Label(
                                "\(visibleLaterUpcomingPlanCount) later meals remain in Planner",
                                systemImage: "ellipsis.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await shiftUpcomingPlans() }
                        } label: {
                            Label(
                                isUpdatingJourney ? "Updating plan…" : "Shift remaining plan by one day",
                                systemImage: "calendar.badge.clock"
                            )
                        }
                        .disabled(isUpdatingJourney)
                    }
                }

                if !visibleSuggestions.isEmpty {
                    Section("Continue your guided plan") {
                        Text("These meals would follow your current plan. Review the next week before adding the remaining journey to Planner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(visibleSuggestions) { suggestion in
                            suggestionRow(suggestion)
                        }
                        Text("Previewing \(visibleSuggestions.count) of \(allSuggestions.count) remaining suggestions.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        buildJourneyButton(title: "Add remaining journey to Planner")
                    }
                }
            }

            SolidsCurrentStageSection(
                triedCount: visibleTriedIDs.count,
                profileState: profileState
            )

            SolidsFeedingSkillsSection(
                profileID: profile.id,
                profileState: profileState
            )

            Section("Milestones") {
                guidedRow(1, "First tastes", "Five foods, including an iron-rich choice.", complete: visibleTriedIDs.count >= 5)
                guidedRow(2, "Growing rotation", "Twenty-five different foods and familiar repeats.", complete: visibleTriedIDs.count >= 25)
                guidedRow(3, "Halfway", "Fifty foods across categories and textures.", complete: visibleTriedIDs.count >= 50)
                guidedRow(4, "Allergen set", "All nine major allergen groups tolerated.", complete: visibleToleratedAllergenIDs.count == SolidsAllergen.allCases.count)
                guidedRow(5, "First 100", "A broad foundation for adaptable family meals.", complete: visibleTriedIDs.count >= 100)
            }

            Section {
                Text("This path organizes the food database and tracker; it is not a medical or developmental assessment. Go at \(profile.name)'s pace and use individualized guidance when needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Guided Solids")
        .appActionSheet(
            isPresented: $showingBuildConfirmation,
            title: profileState?.guidedStartDate == nil
                ? "Add \(allSuggestions.count) meals to Planner?"
                : "Add \(allSuggestions.count) more meals to Planner?",
            message: "The first week is previewed on this screen. Every meal remains editable, and existing plans are preserved.",
            systemImage: "calendar.badge.plus",
            tint: .orange,
            options: [
                AppActionSheetOption(
                    title: profileState?.guidedStartDate == nil ? "Add guided journey" : "Add remaining journey",
                    subtitle: "Add the suggested meals to the editable Planner.",
                    systemImage: "calendar.badge.checkmark",
                    tint: .orange
                ) {
                    Task { await planRemainingJourney() }
                }
            ]
        )
        .alert("Guided plan", isPresented: Binding(
            get: { buildResultMessage != nil },
            set: { if !$0 { buildResultMessage = nil } }
        )) {
            Button("OK") { buildResultMessage = nil }
        } message: {
            Text(buildResultMessage ?? "")
        }
        .task(id: suggestionRefreshKey) {
            if planWriter == nil {
                planWriter = await SolidsWriterPool.shared.guidedPlanWriter(
                    for: modelContext.container
                )
            }
            let snapshot = SolidsTrackingService.guidedSuggestionSnapshot(
                for: profile,
                progress: progress,
                eventItems: [],
                allergenProgress: allergenProgress,
                plans: plans,
                completedSkillIDs: completedSkillIDs,
                startingAt: suggestionStartDate,
                count: remainingFoodCount
            )
            let generated = await Task.detached(priority: .userInitiated) {
                SolidsTrackingService.guidedSuggestions(from: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            cachedSuggestions = generated
        }
        .onAppear {
            if let startDate = profileState?.guidedStartDate {
                selectedStartDate = startDate
            } else if selectedStartDate < earliestGuidedStartDate {
                selectedStartDate = earliestGuidedStartDate
            }
        }
    }

    private func suggestionRow(_ suggestion: SolidsGuidedMealSuggestion) -> some View {
        Group {
            if let destination = suggestion.primaryDestination {
                Button {
                    open(destination)
                } label: {
                    suggestionRowContent(suggestion, showsDisclosureIndicator: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(suggestion.recipe.map {
                    "solids.guided.recipe.\($0.id)"
                } ?? "solids.guided.food.\(suggestion.foods.first?.id ?? "unknown")")
                .accessibilityHint("Opens preparation guidance for this meal.")
            } else {
                suggestionRowContent(suggestion, showsDisclosureIndicator: false)
            }
        }
    }

    private func suggestionRowContent(
        _ suggestion: SolidsGuidedMealSuggestion,
        showsDisclosureIndicator: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(suggestion.scheduledAt.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Label(suggestion.kind.displayName, systemImage: suggestion.kind.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if showsDisclosureIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            if suggestion.primaryDestination != nil {
                Group {
                    Text(suggestion.primaryDestinationTitle ?? "Meal guidance")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text(suggestion.foods.map(\.name).joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let allergenID = suggestion.allergenID,
               let allergen = SolidsAllergen(rawValue: allergenID) {
                Label(
                    suggestion.allergenIntroductionStep.map {
                        "\(allergen.displayName) introduction portion \($0) of 3"
                    } ?? "\(allergen.displayName) rotation",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            SolidsSuggestionPreparationText(
                suggestion: suggestion,
                profile: profile,
                profileState: profileState
            )
            .lineLimit(2)
        }
    }

    private func open(_ destination: SolidsGuidedMealDestination) {
        switch destination {
        case .recipe(let id):
            openRecipe(id)
        case .food(let id):
            openFood(id)
        }
    }

    private func buildJourneyButton(title: String) -> some View {
        Button {
            showingBuildConfirmation = true
        } label: {
            Label(
                isBuildingJourney ? "Adding journey…" : title,
                systemImage: isBuildingJourney ? "hourglass" : "calendar.badge.plus"
            )
        }
        .disabled(isBuildingJourney)
        .accessibilityIdentifier("solids.guided.build-journey")
    }

    private var developmentDetail: String {
        switch SolidsTrackingService.ageMonths(for: profile) {
        case ..<9: "Start with soft mashes, preloaded spoons, and large graspable pieces. Pair new foods with familiar foods and repeat without pressure."
        case 9..<12: "Practice soft bite-size pieces, pincer grasp, and varied textures while repeating familiar foods."
        default: "Adapt family meals into soft manageable pieces and encourage utensil practice while continuing variety."
        }
    }

    private func guidedRow(
        _ number: Int,
        _ title: String,
        _ detail: String,
        complete: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(complete ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func planRemainingJourney() async {
        let nextPosition = max(
            triedIDs.count,
            plans.filter { $0.profileID == profile.id && $0.isGuided }
                .compactMap(\.guidedPosition)
                .max() ?? 0
        ) + 1
        let personalizedSuggestions = SolidsTrackingService.applyingFeedingSkills(
            to: allSuggestions,
            for: profile,
            completedSkillIDs: completedSkillIDs
        )
        let writes = personalizedSuggestions.map { suggestion in
            SolidsGuidedPlanWrite(
                suggestion: suggestion,
                guidedPosition: nextPosition + suggestion.dayOffset
            )
        }
        guard !writes.isEmpty else { return }
        isBuildingJourney = true
        defer { isBuildingJourney = false }
        let writer: SolidsGuidedPlanWriter
        if let planWriter {
            writer = planWriter
        } else {
            writer = await SolidsWriterPool.shared.guidedPlanWriter(for: modelContext.container)
        }
        planWriter = writer
        let result = await writer.buildJourney(
            profileID: profile.id,
            startDate: selectedStartDate,
            writes: writes
        )
        guard result.error == nil, result.count == writes.count else {
            if let error = result.error {
                PersistenceService.recordLocalSaveFailure(error)
            }
            buildResultMessage = "The journey could not be saved. No partial plan was kept."
            return
        }
        SystemIntegrationReconciler.requestReconciliation()
        buildResultMessage = "Added \(result.count) editable meals to the planner."
    }

    private func swap(_ plan: PlannedSolidMeal) async {
        guard !isUpdatingJourney else { return }
        isUpdatingJourney = true
        defer { isUpdatingJourney = false }
        let snapshot = SolidsTrackingService.guidedSuggestionSnapshot(
            for: profile,
            progress: progress,
            eventItems: [],
            allergenProgress: allergenProgress,
            plans: plans,
            completedSkillIDs: completedSkillIDs,
            startingAt: plan.scheduledAt,
            count: 1
        )
        let replacements = await Task.detached(priority: .userInitiated) {
            SolidsTrackingService.guidedSuggestions(from: snapshot)
        }.value
        guard !Task.isCancelled else { return }
        if let replacement = replacements.first {
            let originalTitle = plan.title
            let writer: SolidsGuidedPlanWriter
            if let planWriter {
                writer = planWriter
            } else {
                writer = await SolidsWriterPool.shared.guidedPlanWriter(for: modelContext.container)
            }
            planWriter = writer
            let error = await writer.replacePlan(
                planID: plan.id,
                profileID: profile.id,
                write: SolidsGuidedPlanWrite(
                    suggestion: replacement,
                    guidedPosition: plan.guidedPosition ?? 1
                )
            )
            if let error {
                PersistenceService.recordLocalSaveFailure(error)
                buildResultMessage = "The meal could not be swapped. Please try again."
            } else {
                let replacementTitle = replacement.primaryDestinationTitle
                    ?? replacement.foods.map(\.name).joined(separator: " + ")
                buildResultMessage = "Replaced \(originalTitle) with \(replacementTitle)."
            }
        } else {
            buildResultMessage = "No suitable replacement is available right now."
        }
    }

    private func shiftUpcomingPlans() async {
        guard !isUpdatingJourney else { return }
        isUpdatingJourney = true
        defer { isUpdatingJourney = false }
        let writer: SolidsGuidedPlanWriter
        if let planWriter {
            writer = planWriter
        } else {
            writer = await SolidsWriterPool.shared.guidedPlanWriter(for: modelContext.container)
        }
        planWriter = writer
        let result = await writer.shiftUpcomingPlans(
            profileID: profile.id,
            onOrAfter: Date(),
            byDays: 1
        )
        if let error = result.error {
            PersistenceService.recordLocalSaveFailure(error)
            buildResultMessage = "The remaining plan could not be shifted. Please try again."
        } else if result.count == 0 {
            buildResultMessage = "There are no upcoming guided meals to shift."
        } else {
            buildResultMessage = "Shifted \(result.count) upcoming meal\(result.count == 1 ? "" : "s") by one day."
        }
    }
}

private struct SolidsCurrentStageSection: View {
    let triedCount: Int
    let profileState: SolidsProfileState?

    var body: some View {
        let foodStage = SolidsGuidedStage.stage(forTriedCount: triedCount)
        let completedSkillCount = Set(profileState?.completedFeedingSkillIDs ?? []).count
        let skillStage = SolidsGuidedStage.allCases[
            min(completedSkillCount / 2, SolidsGuidedStage.allCases.count - 1)
        ]
        let stage = foodStage.rawValue >= skillStage.rawValue ? foodStage : skillStage
        Section("Current stage") {
            Label(stage.title, systemImage: "figure.child.circle")
                .font(.headline)
            Text(stage.skill)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SolidsFeedingSkillsSection: View {
    @Environment(\.modelContext) private var modelContext

    let profileID: UUID
    let profileState: SolidsProfileState?

    @State private var draft = SolidsFeedingSkillsDraft()
    @State private var writer: SolidsFeedingSkillWriter?

    private var persistedCompletedSkillIDs: Set<String> {
        Set(profileState?.completedFeedingSkillIDs ?? [])
    }

    var body: some View {
        let completedSkillIDs = persistedCompletedSkillIDs
        Section("Feeding skills") {
            Text("Track what you have actually observed. These check-ins personalize the current stage without treating development as a test.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SolidsFeedingSkill.allCases) { skill in
                SolidsFeedingSkillRow(
                    skill: skill,
                    persistedIsComplete: completedSkillIDs.contains(skill.rawValue)
                ) { isComplete in
                    let update = draft.update(
                        skillID: skill.rawValue,
                        isComplete: isComplete,
                        persistedSkillIDs: completedSkillIDs
                    )
                    Task {
                        let skillWriter = await resolvedWriter()
                        await skillWriter.schedulePersistence(
                            profileID: profileID,
                            completedSkillIDs: update.skillIDs,
                            revision: update.revision
                        )
                    }
                }
            }
        }
        .task {
            _ = await resolvedWriter()
        }
        .onChange(of: profileState?.completedFeedingSkillIDsJSON ?? "[]") { _, _ in
            draft.replace(with: persistedCompletedSkillIDs)
        }
    }

    @MainActor
    private func resolvedWriter() async -> SolidsFeedingSkillWriter {
        if let writer { return writer }
        let value = await SolidsWriterPool.shared.feedingSkillWriter(for: modelContext.container)
        writer = value
        return value
    }
}

private final class SolidsFeedingSkillsDraft {
    private var skillIDs: Set<String>?
    private var revision = 0

    func update(
        skillID: String,
        isComplete: Bool,
        persistedSkillIDs: Set<String>
    ) -> (skillIDs: Set<String>, revision: Int) {
        var updatedSkillIDs = skillIDs ?? persistedSkillIDs
        if isComplete {
            updatedSkillIDs.insert(skillID)
        } else {
            updatedSkillIDs.remove(skillID)
        }
        skillIDs = updatedSkillIDs
        revision += 1
        return (updatedSkillIDs, revision)
    }

    func replace(with persistedSkillIDs: Set<String>) {
        skillIDs = persistedSkillIDs
    }
}

private struct SolidsFeedingSkillRow: View {
    let skill: SolidsFeedingSkill
    let persistedIsComplete: Bool
    let onChange: (Bool) -> Void

    @State private var displayedIsComplete: Bool

    init(
        skill: SolidsFeedingSkill,
        persistedIsComplete: Bool,
        onChange: @escaping (Bool) -> Void
    ) {
        self.skill = skill
        self.persistedIsComplete = persistedIsComplete
        self.onChange = onChange
        _displayedIsComplete = State(initialValue: persistedIsComplete)
    }

    var body: some View {
        Button {
            let updatedValue = !displayedIsComplete
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedIsComplete = updatedValue
            }
            onChange(updatedValue)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: displayedIsComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(displayedIsComplete ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.title).foregroundStyle(.primary)
                    Text(skill.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("solids.feeding-skill.\(skill.rawValue)")
        .accessibilityValue(displayedIsComplete ? "Completed" : "Not completed")
        .onChange(of: persistedIsComplete) { _, newValue in
            guard displayedIsComplete != newValue else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedIsComplete = newValue
            }
        }
    }
}

private struct SolidsSuggestionPreparationText: View {
    let suggestion: SolidsGuidedMealSuggestion
    let profile: CareProfile
    let profileState: SolidsProfileState?

    var body: some View {
        Text(SolidsTrackingService.preparationNotes(
            for: suggestion,
            profile: profile,
            completedSkillIDs: Set(profileState?.completedFeedingSkillIDs ?? [])
        ))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct SolidsFoodDatabaseView: View {
    let profile: CareProfile
    let progress: [SolidFoodProgress]
    let customFoods: [SolidFoodCatalogItem]
    let openFood: (String) -> Void
    let openCustomFood: (UUID) -> Void

    @State private var effectiveSearchText = ""
    @State private var selectedCategory: SolidsFoodCategory?
    @State private var filters = SolidsFoodDatabaseFilters.empty
    @State private var showingFilters = false
    @State private var showingNewCustomFood = false
    @State private var bundledFoods: [SolidsReferenceFoodSummary]?

    private var searchAndCategoryFoods: [SolidsReferenceFoodSummary] {
        SolidsReferenceCatalog.searchSummaries(
            effectiveSearchText,
            category: selectedCategory,
            in: bundledFoods ?? []
        )
    }

    private var filteredCustomFoods: [SolidFoodCatalogItem] {
        guard selectedCategory == nil, filters.isEmpty else { return [] }
        let query = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return customFoods }
        return customFoods.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.preparationNotes.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let progressByFoodID = progress.reduce(into: [String: SolidFoodProgress]()) { result, item in
            guard item.profileID == profile.id else { return }
            result[item.foodID] = item
        }
        let progressFilterByFoodID = progressByFoodID.mapValues {
            SolidsFoodProgressFilterValue(status: $0.status, isFavorite: $0.isFavorite)
        }
        let candidateFoods = searchAndCategoryFoods
        let visibleFoods = candidateFoods.filter {
            filters.matches($0, progress: progressFilterByFoodID[$0.id])
        }
        let visibleCustomFoods = filteredCustomFoods
        List {
            if !visibleCustomFoods.isEmpty {
                Section("Your foods") {
                    ForEach(visibleCustomFoods) { food in
                        Button { openCustomFood(food.id) } label: {
                            HStack(spacing: 12) {
                                SolidFoodPhotoDataLoader(attachmentID: food.photoAttachmentID) { photo in
                                    SolidFoodDatabaseThumbnail(food: food, photo: photo)
                                }
                                VStack(alignment: .leading) {
                                    Text(food.name).foregroundStyle(.primary)
                                    Text("Custom food").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        categoryButton(nil, title: "All")
                        ForEach(SolidsFoodCategory.allCases) { category in
                            categoryButton(category, title: category.displayName)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            if !filters.isEmpty {
                Section {
                    HStack {
                        Label(
                            "\(filters.activeCount) active filter\(filters.activeCount == 1 ? "" : "s")",
                            systemImage: "line.3.horizontal.decrease.circle.fill"
                        )
                        .foregroundStyle(.orange)
                        Spacer()
                        Button("Clear") { filters = .empty }
                    }
                }
            }
            Section("\(visibleFoods.count) foods") {
                ForEach(visibleFoods) { food in
                    Button { openFood(food.id) } label: {
                        SolidsFoodRow(
                            id: food.id,
                            name: food.name,
                            visualEmoji: food.visualEmoji,
                            category: food.category,
                            isIronRich: food.isIronRich,
                            containsAllergen: !food.allergenIDs.isEmpty,
                            status: progressByFoodID[food.id]?.status
                        )
                        .equatable()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Food Database")
        .debouncedSearch(
            text: $effectiveSearchText,
            prompt: "Search foods",
            delay: .milliseconds(250)
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingFilters = true } label: {
                    Label(
                        filters.isEmpty ? "Filters" : "\(filters.activeCount) filters",
                        systemImage: filters.isEmpty
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                    )
                }
                .accessibilityIdentifier("solids.foods.filters")
                .disabled(bundledFoods == nil)
                Button { showingNewCustomFood = true } label: {
                    Label("New custom food", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                SolidsFoodDatabaseFilterView(
                    filters: filters,
                    foods: candidateFoods,
                    progressByFoodID: progressFilterByFoodID
                ) { updatedFilters in
                    filters = updatedFilters
                }
            }
        }
        .sheet(isPresented: $showingNewCustomFood) {
            NavigationStack {
                CustomSolidFoodEditorView(
                    item: nil,
                    existingItems: customFoods,
                    existingPhoto: nil,
                    onSave: { _, _ in }
                )
            }
        }
        .task {
            guard bundledFoods == nil else { return }
            bundledFoods = await SolidsReferenceCatalog.loadFoodSummaries()
        }
        .overlay {
            if bundledFoods == nil {
                ProgressView("Loading food database")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
            } else if visibleFoods.isEmpty && visibleCustomFoods.isEmpty {
                if filters.isEmpty {
                    ContentUnavailableView.search(text: effectiveSearchText)
                } else {
                    ContentUnavailableView {
                        Label("No matching foods", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Try clearing one or more filters.")
                    } actions: {
                        Button("Clear filters") {
                            filters = .empty
                            selectedCategory = nil
                        }
                    }
                }
            }
        }
    }

    private func categoryButton(_ category: SolidsFoodCategory?, title: String) -> some View {
        Button(title) { selectedCategory = category }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(selectedCategory == category ? .orange : .secondary)
    }
}

struct SolidFoodPhotoDataLoader<Content: View>: View {
    @Query private var attachments: [PhotoAttachment]
    private let content: (PhotoAttachment?) -> Content

    init(
        attachmentID: UUID?,
        @ViewBuilder content: @escaping (PhotoAttachment?) -> Content
    ) {
        self.content = content
        let resolvedID = attachmentID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var descriptor = FetchDescriptor<PhotoAttachment>(
            predicate: #Predicate { $0.id == resolvedID }
        )
        descriptor.fetchLimit = 1
        _attachments = Query(descriptor)
    }

    var body: some View {
        content(attachments.first)
    }
}

private struct SolidFoodDatabaseThumbnail: View {
    let food: SolidFoodCatalogItem
    let photo: PhotoAttachment?

    @ViewBuilder
    var body: some View {
        if let photo,
           let data = photo.previewData,
           let image = ThumbnailImageCache.image(
               attachmentID: photo.id,
               data: data
           ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Text(SolidsFoodVisual.emoji(for: food.name))
                .font(.system(size: 27))
                .frame(width: 42, height: 42)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct SolidsFoodDatabaseFilterView: View {
    @Environment(\.dismiss) private var dismiss

    let foods: [SolidsReferenceFoodSummary]
    let progressByFoodID: [String: SolidsFoodProgressFilterValue]
    let onApply: (SolidsFoodDatabaseFilters) -> Void

    @State private var draft: SolidsFoodDatabaseFilters
    @State private var showingIronOptions = false
    @State private var showingTrackingOptions = false

    private let ageOptions = [6, 9, 12, 18, 24, 36, 48]
    private let availableTypes: [(type: SolidsFoodTypeFilter, count: Int)]
    private let allergenCounts: [String: Int]

    init(
        filters: SolidsFoodDatabaseFilters,
        foods: [SolidsReferenceFoodSummary],
        progressByFoodID: [String: SolidsFoodProgressFilterValue],
        onApply: @escaping (SolidsFoodDatabaseFilters) -> Void
    ) {
        self.foods = foods
        self.progressByFoodID = progressByFoodID
        self.onApply = onApply
        availableTypes = SolidsFoodTypeFilter.allCases.compactMap { type in
            let count = foods.lazy.filter(type.matches).count
            return count == 0 ? nil : (type, count)
        }
        allergenCounts = Dictionary(uniqueKeysWithValues: SolidsAllergen.allCases.map { allergen in
            let count = foods.lazy.filter {
                $0.allergenIDs.contains(allergen.rawValue)
                    || $0.possibleAllergenIDs.contains(allergen.rawValue)
            }.count
            return (allergen.rawValue, count)
        })
        _draft = State(initialValue: filters)
    }

    private var resultCount: Int {
        foods.lazy.filter { draft.matches($0, progress: progressByFoodID[$0.id]) }.count
    }

    var body: some View {
        Form {
            Section("Age of child") {
                selectionRow(
                    title: "Any age",
                    subtitle: nil,
                    isSelected: draft.ageMonths == nil,
                    style: .radio
                ) { draft.ageMonths = nil }
                ForEach(ageOptions, id: \.self) { months in
                    selectionRow(
                        title: ageTitle(months),
                        subtitle: nil,
                        isSelected: draft.ageMonths == months,
                        style: .radio
                    ) { draft.ageMonths = months }
                }
                Text("Shows foods whose suggested introduction age is at or before the selected age. Readiness and the food's preparation guidance still apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Food types") {
                ForEach(availableTypes, id: \.type.id) { item in
                    selectionRow(
                        title: item.type.displayName,
                        subtitle: "\(item.count)",
                        isSelected: draft.selectedTypes.contains(item.type),
                        style: .checkbox
                    ) {
                        if !draft.selectedTypes.insert(item.type).inserted {
                            draft.selectedTypes.remove(item.type)
                        }
                    }
                    .accessibilityIdentifier("solids.foods.filter.type.\(item.type.rawValue)")
                }
                Text("Selecting multiple food types shows foods matching any selected type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Food allergies") {
                Text("Select allergens to exclude. Foods that contain or may contain any selected allergen will be hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SolidsAllergen.allCases) { allergen in
                    selectionRow(
                        title: allergen.displayName,
                        subtitle: "\(allergenCounts[allergen.rawValue, default: 0])",
                        isSelected: draft.excludedAllergenIDs.contains(allergen.rawValue),
                        style: .checkbox
                    ) {
                        if !draft.excludedAllergenIDs.insert(allergen.rawValue).inserted {
                            draft.excludedAllergenIDs.remove(allergen.rawValue)
                        }
                    }
                    .accessibilityIdentifier("solids.foods.filter.allergen.\(allergen.rawValue)")
                }
            }

            Section("Nutrition") {
                SolidsDrawerSelectionButton(
                    title: "Iron",
                    value: draft.ironFilter.displayName,
                    systemImage: "leaf.fill"
                ) {
                    showingIronOptions = true
                }
            }

            Section("Tracking") {
                SolidsDrawerSelectionButton(
                    title: "Status",
                    value: draft.trackingFilter.displayName,
                    systemImage: "checkmark.circle"
                ) {
                    showingTrackingOptions = true
                }
            }
        }
        .navigationTitle("Food Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { draft = .empty }
                    .disabled(draft.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onApply(draft)
                dismiss()
            } label: {
                Text("Show \(resultCount) food\(resultCount == 1 ? "" : "s")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
            .accessibilityIdentifier("solids.foods.filter.apply")
        }
        .appActionSheet(
            isPresented: $showingIronOptions,
            title: "Iron",
            message: "Choose which foods to include based on their iron-rich classification.",
            systemImage: "leaf.fill",
            tint: .orange,
            options: SolidsIronFilter.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: value == .ironRich ? "leaf.fill" : "circle.grid.2x2",
                    tint: .orange,
                    isSelected: draft.ironFilter == value
                ) {
                    draft.ironFilter = value
                }
            }
        )
        .appActionSheet(
            isPresented: $showingTrackingOptions,
            title: "Tracking status",
            message: "Show foods with the selected tracking status.",
            systemImage: "checkmark.circle",
            tint: .orange,
            options: SolidsDatabaseTrackingFilter.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: trackingSystemImage(value),
                    tint: .orange,
                    isSelected: draft.trackingFilter == value
                ) {
                    draft.trackingFilter = value
                }
            }
        )
    }

    private enum SelectionStyle {
        case radio
        case checkbox
    }

    private func selectionRow(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        style: SelectionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selectionImage(style: style, isSelected: isSelected))
                    .foregroundStyle(isSelected ? .orange : .secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectionImage(style: SelectionStyle, isSelected: Bool) -> String {
        switch (style, isSelected) {
        case (.radio, true): "largecircle.fill.circle"
        case (.radio, false): "circle"
        case (.checkbox, true): "checkmark.square.fill"
        case (.checkbox, false): "square"
        }
    }

    private func ageTitle(_ months: Int) -> String {
        if months < 36 { return "\(months) months +" }
        return "\(months / 12) years +"
    }

    private func trackingSystemImage(_ value: SolidsDatabaseTrackingFilter) -> String {
        switch value {
        case .all: "circle.grid.2x2"
        case .notTried: "circle"
        case .wantToTry: "bookmark.fill"
        case .tried: "checkmark.circle.fill"
        case .favorites: "heart.fill"
        }
    }
}

private struct SolidsFoodRow: View, Equatable {
    let id: String
    let name: String
    let visualEmoji: String
    let category: SolidsFoodCategory
    let isIronRich: Bool
    let containsAllergen: Bool
    let status: SolidsFoodStatus?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.visualEmoji == rhs.visualEmoji
            && lhs.category == rhs.category
            && lhs.isIronRich == rhs.isIronRich
            && lhs.containsAllergen == rhs.containsAllergen
            && lhs.status == rhs.status
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(visualEmoji)
                .font(.system(size: 22))
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(category.displayName)
                    if isIronRich { Text("• Iron-rich") }
                    if containsAllergen { Text("• Allergen") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let status, status != .notTried {
                Image(systemName: status == .tried ? "checkmark.circle.fill" : "bookmark.fill")
                    .foregroundStyle(status == .tried ? .green : .orange)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct SolidFoodNutritionFactsView: View {
    let reference: SolidNutritionReference
    var showsCommonPortions = false

    private var isRepresentativeEstimate: Bool {
        reference.sourceDescription.hasPrefix("Representative USDA estimate")
    }

    private var providedNutrientCount: Int {
        [
            reference.nutrients.energyKilocalories,
            reference.nutrients.proteinGrams,
            reference.nutrients.fatGrams,
            reference.nutrients.fiberGrams,
            reference.nutrients.ironMilligrams,
            reference.nutrients.zincMilligrams,
            reference.nutrients.calciumMilligrams,
            reference.nutrients.vitaminCMilligrams
        ].compactMap { $0 }.count
    }

    private var basisDescription: String {
        "\(formatted(reference.basisQuantity)) \(reference.basisUnit.abbreviatedName)"
    }

    private var showsSeparateBasisWeight: Bool {
        guard let basisGrams = reference.basisGrams else { return false }
        return reference.basisUnit != .gram || abs(basisGrams - reference.basisQuantity) > 0.000_1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            factRow("Values shown for", value: basisDescription)
                .accessibilityIdentifier("solids.food.nutrition.basis")
            if showsSeparateBasisWeight, let basisGrams = reference.basisGrams {
                factRow("Serving weight", value: "\(formatted(basisGrams)) g")
            }

            Divider()

            nutrientRow(
                "Calories",
                value: reference.nutrients.energyKilocalories,
                unit: "kcal",
                identifier: "calories"
            )
            nutrientRow(
                "Protein",
                value: reference.nutrients.proteinGrams,
                unit: "g",
                identifier: "protein"
            )
            nutrientRow(
                "Fat",
                value: reference.nutrients.fatGrams,
                unit: "g",
                identifier: "fat"
            )
            nutrientRow(
                "Fiber",
                value: reference.nutrients.fiberGrams,
                unit: "g",
                identifier: "fiber"
            )
            nutrientRow(
                "Iron",
                value: reference.nutrients.ironMilligrams,
                unit: "mg",
                identifier: "iron"
            )
            nutrientRow(
                "Zinc",
                value: reference.nutrients.zincMilligrams,
                unit: "mg",
                identifier: "zinc"
            )
            nutrientRow(
                "Calcium",
                value: reference.nutrients.calciumMilligrams,
                unit: "mg",
                identifier: "calcium"
            )
            nutrientRow(
                "Vitamin C",
                value: reference.nutrients.vitaminCMilligrams,
                unit: "mg",
                identifier: "vitamin-c"
            )

            Divider()

            Label(
                isRepresentativeEstimate
                    ? "Complete for the named USDA proxy—not exact for this food."
                    : reference.nutrients.isComplete
                    ? "All eight tracked nutrients are included."
                    : "\(providedNutrientCount) of 8 tracked nutrients are included.",
                systemImage: isRepresentativeEstimate
                    ? "exclamationmark.triangle.fill"
                    : reference.nutrients.isComplete
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isRepresentativeEstimate ? .orange : (reference.nutrients.isComplete ? .green : .orange))

            factRow("Source", value: reference.sourceKind.displayName)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Source, \(reference.sourceKind.displayName)")
                .accessibilityIdentifier("solids.food.nutrition.source")
            Text(reference.sourceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsCommonPortions, !reference.portions.isEmpty {
                Divider()
                Text("Common portion weights")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(reference.portions) { portion in
                    factRow(
                        "1 \(portion.unit.abbreviatedName)",
                        value: "\(formatted(portion.gramsPerUnit)) g · \(portion.description)"
                    )
                }
            }
        }
    }

    private func factRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func nutrientRow(
        _ title: String,
        value: Double?,
        unit: String,
        identifier: String
    ) -> some View {
        let displayValue = value.map { "\(formatted($0)) \(unit)" } ?? "Not provided"
        return LabeledContent(title, value: displayValue)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(displayValue)")
            .accessibilityIdentifier("solids.food.nutrition.\(identifier)")
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct SolidsDigestiveSupportView: View {
    @Environment(\.modelContext) private var modelContext

    let profile: CareProfile
    let careEvents: [CareEvent]
    let eventItems: [SolidFoodEventItem]
    let profileState: SolidsProfileState?
    let assessment: SolidsBalanceAssessment
    let openFood: (String) -> Void
    let openRecipe: (String) -> Void

    @State private var showingCheckIn = false
    @State private var loggingCoverage: SolidsLoggingCoverage = .unknown
    @State private var persistedLoggingCoverage: SolidsLoggingCoverage = .unknown
    @State private var stateWriter: SolidsProfileStateWriter?
    @State private var errorMessage: String?
    @State private var showingCheckInHistory = false
    @State private var showingAllTimelineEntries = false
    @State private var updatingReminder = false

    private let timelinePreviewLimit = 6
    private var ageMonths: Int { SolidsTrackingService.ageMonths(for: profile) }

    private var recentResolvedCheckIns: [SolidsDigestiveCheckIn] {
        Array((profileState?.digestiveCheckIns ?? []).lazy.filter { !$0.isActive }.prefix(5))
    }

    private var timelineEntries: [SolidsDigestiveTimelineEntry] {
        SolidsDigestiveSupportService.timeline(
            profileID: profile.id,
            events: careEvents,
            eventItems: eventItems,
            checkIns: profileState?.digestiveCheckIns ?? []
        )
    }

    var body: some View {
        let currentResolvedCheckIns = recentResolvedCheckIns
        let currentTimelineEntries = timelineEntries
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if let concern = assessment.activeConcern {
                    activeConcernCard(concern)
                }
                if !currentResolvedCheckIns.isEmpty {
                    checkInHistoryCard(currentResolvedCheckIns)
                }
                timelineCard(currentTimelineEntries)
                balanceCard(assessment)
                insightsSection(assessment)
                suggestionsSection(assessment)
                practicalGuidance
                safetyCard
                sources
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .navigationTitle("Feeding balance")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if stateWriter == nil {
                stateWriter = await SolidsWriterPool.shared.profileStateWriter(
                    for: modelContext.container
                )
            }
            let storedCoverage = profileState?.digestiveLoggingCoverage ?? .unknown
            persistedLoggingCoverage = storedCoverage
            loggingCoverage = storedCoverage
        }
        .sheet(isPresented: $showingCheckIn) {
            SolidsDigestiveCheckInSheet(
                profile: profile,
                initialCoverage: loggingCoverage,
                writer: stateWriter,
                onSaved: { coverage in
                    persistedLoggingCoverage = coverage
                    loggingCoverage = coverage
                    showingCheckIn = false
                }
            )
        }
        .alert("Couldn’t save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func timelineCard(_ entries: [SolidsDigestiveTimelineEntry]) -> some View {
        let visibleEntries = showingAllTimelineEntries
            ? entries
            : Array(entries.prefix(timelinePreviewLimit))
        return VStack(alignment: .leading, spacing: 12) {
            Label("What changed?", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Text("Stool observations appear beside recent solids, health, medicine, and caregiver context logs. Being close in time does not mean one caused another.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if visibleEntries.isEmpty {
                Text("Log a poo diaper, solids meal, or relevant care note to build this 7-day view.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in
                    timelineRow(entry)
                }
                if entries.count > timelinePreviewLimit {
                    Button(showingAllTimelineEntries ? "Show less" : "Show all \(entries.count)") {
                        withAnimation(.snappy) {
                            showingAllTimelineEntries.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .appSurface()
        .accessibilityIdentifier("solids.digestive.timeline")
    }

    private func timelineRow(_ entry: SolidsDigestiveTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: entry.kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(timelineColor(entry.kind))
                .frame(width: 28, height: 28)
                .background(timelineColor(entry.kind).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func timelineColor(_ kind: SolidsDigestiveTimelineKind) -> Color {
        switch kind {
        case .stool: .brown
        case .solids: .orange
        case .health: .red
        case .medicine: .purple
        case .context: .blue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "leaf.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Comfort and balance")
                        .font(.title2.bold())
                    Text("A gentle review of \(profile.name)’s recent solids log")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Hard, dry, or painful stools are more useful signs of constipation than the number of bowel movements alone. This tool records a caregiver concern; it does not diagnose constipation.")
                .font(.subheadline)
            Button {
                showingCheckIn = true
            } label: {
                Label("Constipation concern today", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityIdentifier("solids.digestive.add-check-in")
        }
        .padding(16)
        .appSurface()
    }

    private func activeConcernCard(_ concern: SolidsDigestiveCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Concern recorded", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(concern.needsPromptMedicalAdvice ? .red : .orange)
            Text("Recorded \(concern.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(concern.observationLabels.joined(separator: " • "))
                .font(.subheadline)
            if concern.needsPromptMedicalAdvice {
                Text("One or more symptoms selected here warrant prompt medical advice. Use urgent care for severe or rapidly worsening symptoms.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
            if !concern.notes.isEmpty {
                Text(concern.notes)
                    .font(.subheadline)
            }
            if profileState?.digestiveReminderEnabled == true,
               let reminderAt = profileState?.digestiveReminderAt,
               reminderAt > Date() {
                Label(
                    "Follow-up reminder: \(reminderAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "bell.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Cancel follow-up reminder") {
                    Task { await updateReminder(for: concern, reminderAt: nil) }
                }
                .disabled(updatingReminder)
            } else {
                Button("Remind me tomorrow") {
                    Task { await addTomorrowReminder(for: concern) }
                }
                .disabled(updatingReminder)
            }
            Button("Mark concern resolved") {
                Task { await resolve(concern) }
            }
            .buttonStyle(.bordered)
            .disabled(updatingReminder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appSurface()
    }

    private func checkInHistoryCard(_ checkIns: [SolidsDigestiveCheckIn]) -> some View {
        DisclosureGroup(
            "Recent check-ins (\(checkIns.count))",
            isExpanded: $showingCheckInHistory
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(checkIns) { concern in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(concern.recordedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Text(concern.observationLabels.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let resolvedAt = concern.resolvedAt {
                            Text("Resolved \(resolvedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
        .font(.headline)
        .padding(16)
        .appSurface()
    }

    private func balanceCard(_ assessment: SolidsBalanceAssessment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-day solids review")
                    .font(.headline)
                Spacer()
                Text("\(assessment.mealCount) meals")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(assessment.summary)
                .font(.subheadline)
            HStack {
                Text("Logging coverage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Logging coverage", selection: $loggingCoverage) {
                    ForEach(SolidsLoggingCoverage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .onChange(of: loggingCoverage) { _, coverage in
                guard coverage != persistedLoggingCoverage else { return }
                Task { await saveCoverage(coverage) }
            }
            Text(loggingCoverage.assessmentNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .appSurface()
    }

    @ViewBuilder
    private func insightsSection(_ assessment: SolidsBalanceAssessment) -> some View {
        if !assessment.strengths.isEmpty || !assessment.opportunities.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What the log shows")
                    .font(.headline)
                ForEach(assessment.strengths) { insight in
                    insightRow(insight, color: .green)
                }
                ForEach(assessment.opportunities) { insight in
                    insightRow(insight, color: .orange)
                }
            }
        }
    }

    private func insightRow(_ insight: SolidsBalanceInsight, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .appSurface(cornerRadius: 17)
    }

    @ViewBuilder
    private func suggestionsSection(_ assessment: SolidsBalanceAssessment) -> some View {
        if !assessment.suggestedFoodIDs.isEmpty || !assessment.suggestedRecipeIDs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ideas for the next meals")
                    .font(.headline)
                Text("Open a food to see age-safe preparation, recipes, and the existing shopping-list actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(assessment.suggestedFoodIDs, id: \.self) { foodID in
                    if let food = SolidsReferenceCatalog.food(id: foodID) {
                        Button { openFood(food.id) } label: {
                            HStack {
                                Text(food.visualEmoji)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).foregroundStyle(.primary)
                                    Text(food.category.displayName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .appSurface(cornerRadius: 15)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(assessment.suggestedRecipeIDs, id: \.self) { recipeID in
                    if let recipe = SolidsReferenceCatalog.recipe(id: recipeID) {
                        Button { openRecipe(recipe.id) } label: {
                            Label(recipe.title, systemImage: "fork.knife")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }
        }
    }

    private var practicalGuidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Age-aware balance", systemImage: "scalemass.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(ageBalanceGuidance)
                .font(.subheadline)
            Text(hydrationGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .appSurface()
    }

    private var ageBalanceGuidance: String {
        switch ageMonths {
        case ..<6:
            "Before about 6 months, use this review only if solids have already started based on readiness and clinician guidance. Breast milk or formula remains central; do not increase solid meals because of this screen."
        case 6..<9:
            "For 6–8 months, WHO guidance commonly describes 2–3 complementary-food meals a day, while breast milk or formula remains central. Build variety gradually and follow hunger and fullness cues."
        case 9...11:
            "For 9–11 months, WHO guidance commonly describes 3–4 complementary-food meals a day, while breast milk or formula remains important. Keep broadening textures and food groups at the child’s pace."
        case 12:
            "At 12 months, keep offering varied family foods in age-safe textures and follow hunger and fullness cues. Ask the child’s clinician about the family’s transition from infant feeding guidance."
        default:
            "After 12 months, keep offering varied family foods in age-safe textures and follow hunger and fullness cues. Ask the child’s clinician for age-specific feeding guidance."
        }
    }

    private var hydrationGuidance: String {
        if (6...12).contains(ageMonths) {
            return "From about 6 months, small amounts of plain water can be offered with meals; the AAP describes about 4–8 oz total per day for 6–12 months. Do not use this screen to restrict breast milk or formula."
        }
        return "Offer drinks according to the child’s current age and their clinician’s guidance. Do not use this screen to restrict milk feeds or fluids."
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("When to get medical help", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("Contact the child’s clinician promptly for blood in the stool or rectal bleeding, a swollen belly, constant abdominal pain, vomiting, poor feeding, weight loss, or symptoms that are severe, worsening, or not improving.")
                .font(.subheadline)
            Text("Do not give laxatives, mineral oil, enemas, or suppositories to a baby unless their clinician recommends it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .appSurface()
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clinical and feeding sources")
                .font(.headline)
            ForEach(SolidsDigestiveSupportService.sourceURLs, id: \.absoluteString) { url in
                Link(destination: url) {
                    Label(SolidsSourceLibrary.displayName(for: url), systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .appSurface()
    }

    @MainActor
    private func saveCoverage(_ coverage: SolidsLoggingCoverage) async {
        guard let stateWriter else { return }
        if let error = await stateWriter.setDigestiveLoggingCoverage(
            profileID: profile.id,
            coverage: coverage
        ) {
            errorMessage = error
            loggingCoverage = persistedLoggingCoverage
        } else {
            persistedLoggingCoverage = coverage
        }
    }

    @MainActor
    private func resolve(_ concern: SolidsDigestiveCheckIn) async {
        guard let stateWriter else { return }
        if let error = await stateWriter.resolveDigestiveCheckIn(
            profileID: profile.id,
            checkInID: concern.id
        ) {
            errorMessage = error
        }
    }

    @MainActor
    private func addTomorrowReminder(for concern: SolidsDigestiveCheckIn) async {
        updatingReminder = true
        let authorized = await NotificationManager.shared.ensureAuthorization()
        guard authorized else {
            updatingReminder = false
            errorMessage = "Notifications are off. Enable them in Settings to add a follow-up reminder."
            return
        }
        let reminderAt = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ?? Date().addingTimeInterval(86_400)
        await updateReminder(for: concern, reminderAt: reminderAt)
    }

    @MainActor
    private func updateReminder(
        for concern: SolidsDigestiveCheckIn,
        reminderAt: Date?
    ) async {
        updatingReminder = true
        guard let stateWriter else {
            updatingReminder = false
            errorMessage = "The solids store is still loading. Try again."
            return
        }
        if let error = await stateWriter.setDigestiveReminder(
            profileID: profile.id,
            checkInID: concern.id,
            reminderAt: reminderAt
        ) {
            errorMessage = error
        }
        updatingReminder = false
    }
}

private struct SolidsDigestiveCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profile: CareProfile
    let initialCoverage: SolidsLoggingCoverage
    let writer: SolidsProfileStateWriter?
    let onSaved: (SolidsLoggingCoverage) -> Void

    @State private var hardStool = true
    @State private var difficultOrPainful = false
    @State private var prolongedStraining = false
    @State private var visibleBlood = false
    @State private var vomiting = false
    @State private var swollenBelly = false
    @State private var poorFeeding = false
    @State private var notes = ""
    @State private var loggingCoverage: SolidsLoggingCoverage
    @State private var reminderEnabled = false
    @State private var reminderAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var checkingReminderPermission = false
    @State private var saving = false
    @State private var errorMessage: String?

    init(
        profile: CareProfile,
        initialCoverage: SolidsLoggingCoverage,
        writer: SolidsProfileStateWriter?,
        onSaved: @escaping (SolidsLoggingCoverage) -> Void
    ) {
        self.profile = profile
        self.initialCoverage = initialCoverage
        self.writer = writer
        self.onSaved = onSaved
        _loggingCoverage = State(initialValue: initialCoverage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you noticing?") {
                    Toggle("Hard or dry stool", isOn: $hardStool)
                    Toggle("Difficult or painful to pass", isOn: $difficultOrPainful)
                    Toggle("Prolonged straining", isOn: $prolongedStraining)
                }
                Section {
                    Toggle("Visible blood", isOn: $visibleBlood)
                    Toggle("Vomiting", isOn: $vomiting)
                    Toggle("Swollen belly", isOn: $swollenBelly)
                    Toggle("Poor feeding", isOn: $poorFeeding)
                } header: {
                    Text("Contact a clinician promptly if present")
                } footer: {
                    Text("Use urgent care for severe or rapidly worsening symptoms. This check-in does not replace medical care.")
                }
                Section("Context") {
                    Picker("Solids logging", selection: $loggingCoverage) {
                        ForEach(SolidsLoggingCoverage.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Remind me to check again", isOn: $reminderEnabled)
                        .disabled(checkingReminderPermission)
                    if reminderEnabled {
                        DatePicker("Reminder", selection: $reminderAt, in: Date()...)
                            .disabled(checkingReminderPermission)
                    }
                } header: {
                    Text("Follow up")
                } footer: {
                    Text("The concern stays active until you mark it resolved.")
                }
            }
            .navigationTitle("Digestive check-in")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: reminderEnabled) { _, isEnabled in
                guard isEnabled else { return }
                Task { await authorizeReminder() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(saving || checkingReminderPermission
                        || !(hardStool || difficultOrPainful || prolongedStraining
                        || visibleBlood || vomiting || swollenBelly || poorFeeding))
                }
            }
            .alert("Needs attention", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func authorizeReminder() async {
        checkingReminderPermission = true
        let authorized = await NotificationManager.shared.ensureAuthorization()
        checkingReminderPermission = false
        guard !authorized else { return }
        reminderEnabled = false
        errorMessage = "Notifications are off. You can save the concern without a reminder or enable notifications in Settings."
    }

    @MainActor
    private func save() async {
        guard let writer else {
            errorMessage = "The solids store is still loading. Try again."
            return
        }
        saving = true
        if reminderEnabled {
            let authorized = await NotificationManager.shared.ensureAuthorization()
            guard authorized else {
                reminderEnabled = false
                saving = false
                errorMessage = "Notifications are off. The concern has not been saved yet. Save again without a reminder or enable notifications in Settings."
                return
            }
        }
        let checkIn = SolidsDigestiveCheckIn(
            hardStool: hardStool,
            difficultOrPainful: difficultOrPainful,
            prolongedStraining: prolongedStraining,
            visibleBlood: visibleBlood,
            vomiting: vomiting,
            swollenBelly: swollenBelly,
            poorFeeding: poorFeeding,
            notes: notes
        )
        if let error = await writer.saveDigestiveCheckIn(
            profileID: profile.id,
            checkIn: checkIn,
            loggingCoverage: loggingCoverage,
            reminderAt: reminderEnabled ? reminderAt : nil
        ) {
            errorMessage = error
            saving = false
        } else {
            onSaved(loggingCoverage)
        }
    }
}

struct SolidsFoodDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let food: SolidsReferenceFood
    let profile: CareProfile
    let progress: [SolidFoodProgress]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let inventoryItems: [InventoryItem]
    let foodItems: [FoodItem]
    let openHistory: (String, String) -> Void
    let openRecipe: (String) -> Void

    @State private var showingPreparationWalkthrough = false
    @State private var showingShoppingLists = false
    @State private var shoppingWriter: SolidsShoppingListWriter?
    @State private var shoppingMessage: String?

    private var record: SolidFoodProgress? {
        progress.first { $0.profileID == profile.id && $0.foodID == food.id }
    }

    private var ageMonths: Int { SolidsTrackingService.ageMonths(for: profile) }

    var body: some View {
        let visibleRecord = record
        let visibleAgeMonths = ageMonths
        let digestiveGuidance = SolidsDigestiveSupportService.foodGuidance(
            for: food,
            ageMonths: visibleAgeMonths
        )
        let matchingRecipes = SolidsReferenceCatalog.recipes(containingFoodID: food.id)
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Text(food.visualEmoji)
                        .font(.system(size: 32))
                        .frame(width: 58, height: 58)
                        .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name).font(.title2.bold())
                        Text(food.category.displayName).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                HStack(alignment: .top, spacing: 0) {
                    foodFact(title: "Age suggestion", value: "\(food.minimumAgeMonths)+ months")
                    Divider().padding(.horizontal, 8)
                    foodFact(title: "Iron-rich", value: food.isIronRich ? "Yes" : "No")
                    Divider().padding(.horizontal, 8)
                    foodFact(
                        title: "Major allergen",
                        value: food.allergenIDs.isEmpty
                            ? (food.possibleAllergenIDs.isEmpty ? "No" : "Check label")
                            : "Yes"
                    )
                }
                .padding(.vertical, 6)
            }

            Section("When can babies have \(food.name.lowercased())?") {
                Text(food.details.introductionSummary)
            }

            if let backgroundSummary = food.details.backgroundSummary {
                Section("About \(food.name)") {
                    Text(backgroundSummary)
                }
            }

            nutritionSections

            Section("Digestive notes") {
                Text(digestiveGuidance.note)
                if let caution = digestiveGuidance.caution {
                    Label {
                        Text(caution)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Text("Stool response varies. Consider the whole feeding pattern and contact the child’s clinician for persistent or concerning symptoms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(digestiveGuidance.sourceURLs, id: \.absoluteString) { url in
                    Link(destination: url) {
                        Label(SolidsSourceLibrary.displayName(for: url), systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }

            Section("Preparation by age") {
                ForEach(Array(food.preparations.enumerated()), id: \.element.id) { index, stage in
                    HStack(alignment: .top, spacing: 12) {
                        let visual = food.servingVisuals[min(index, food.servingVisuals.count - 1)]
                        SolidsServingPhoto(visual: visual, foodName: food.name, compact: true)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(stage.title).font(.subheadline.weight(.semibold))
                                if visibleAgeMonths >= food.minimumAgeMonths,
                                   stage.id == food.preparation(forAgeMonths: visibleAgeMonths).id {
                                    Text("For \(profile.name) now")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(visual.displayName).font(.caption).foregroundStyle(.orange)
                            Text(stage.instructions)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("First serving")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(stage.servingAmount.firstServing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("After tolerated")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(stage.servingAmount.routineServing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                Button {
                    showingPreparationWalkthrough = true
                } label: {
                    Label("Start guided prep checklist", systemImage: "checklist")
                }
                .accessibilityIdentifier("solids.preparation.open")
                Text("Technique photos are illustrative. Use the food-specific written instructions for shape, texture, and safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Amounts are starting suggestions, not requirements. Follow hunger and fullness cues and offer more when the child shows interest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety and choking") {
                Text(food.chokingGuidance)
            }

            Section("Allergens") {
                Text(food.details.allergenSummary)
            }

            Section("Choosing and storage") {
                VStack(alignment: .leading, spacing: 5) {
                    Label("What to look for", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(food.details.choosingGuidance)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Label("How to store it", systemImage: "refrigerator.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(food.details.storageGuidance)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if !food.details.questions.isEmpty {
                Section("Common questions") {
                    ForEach(food.details.questions) { item in
                        DisclosureGroup(item.question) {
                            Text(item.answer)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            Section("Track") {
                if let visibleRecord, visibleRecord.exposureCount > 0 {
                    LabeledContent("Meals recorded", value: "\(visibleRecord.exposureCount)")
                    if let last = visibleRecord.lastTriedAt {
                        LabeledContent("Last tried", value: last.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button {
                        openHistory(food.id, food.name)
                    } label: {
                        Label("View exposure timeline", systemImage: "clock.arrow.circlepath")
                    }
                }
                Button {
                    startSolidLog()
                } label: {
                    Label("Log \(food.name)", systemImage: "plus.circle.fill")
                }
                SolidsFoodTrackingButtons(
                    profileID: profile.id,
                    foodID: food.id,
                    foodName: food.name,
                    initialStatus: visibleRecord?.status ?? .notTried,
                    initiallyFavorite: visibleRecord?.isFavorite == true
                )
                if SolidsTrackingService.isAvailableInInventory(
                    food: food,
                    inventoryItems: inventoryItems,
                    foodItems: foodItems
                ) {
                    Label("Available in kitchen inventory", systemImage: "cabinet.fill")
                        .foregroundStyle(.green)
                }
                if !shoppingLists.isEmpty {
                    Button {
                        showingShoppingLists = true
                    } label: {
                        Label("Add to shopping list", systemImage: "cart.badge.plus")
                    }
                }
            }

            Section("Your notes") {
                SolidsFoodNotesEditor(
                    profileID: profile.id,
                    foodID: food.id,
                    foodName: food.name,
                    initialNotes: visibleRecord?.notes ?? ""
                )
                .id("\(profile.id.uuidString)-\(food.id)")
            }

            if !matchingRecipes.isEmpty {
                Section("Meals with \(food.name)") {
                    ForEach(matchingRecipes.prefix(5)) { recipe in
                        Button { openRecipe(recipe.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title).foregroundStyle(.primary)
                                    Text("\(recipe.minimumAgeMonths)+ months • \(recipe.mealType.displayName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("solids.food.recipe.\(recipe.id)")
                    }
                }
            }

            Section("Sources") {
                ForEach(food.sourceURLs, id: \.absoluteString) { url in
                    Link(destination: url) {
                        Label(SolidsSourceLibrary.displayName(for: url), systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPreparationWalkthrough) {
            SolidsPreparationWalkthroughView(food: food, ageMonths: visibleAgeMonths)
        }
        .appActionSheet(
            isPresented: $showingShoppingLists,
            title: "Add \(food.name) to a list",
            message: "Choose the shopping list that should receive this food.",
            systemImage: "cart.badge.plus",
            tint: .orange,
            options: shoppingLists.map { shoppingList in
                let activeCount = shoppingItems.lazy.filter {
                    $0.shoppingListID == shoppingList.id && !$0.isChecked
                }.count
                return AppActionSheetOption(
                    title: shoppingList.name,
                    subtitle: "\(activeCount) active item\(activeCount == 1 ? "" : "s")",
                    systemImage: "list.bullet.rectangle",
                    tint: .orange
                ) {
                    addToShoppingList(shoppingList)
                }
            }
        )
        .alert("Shopping list", isPresented: Binding(
            get: { shoppingMessage != nil },
            set: { if !$0 { shoppingMessage = nil } }
        )) {
            Button("OK") { shoppingMessage = nil }
        } message: {
            Text(shoppingMessage ?? "")
        }
        .task {
            _ = await resolvedShoppingWriter()
        }
    }

    @ViewBuilder
    private var nutritionSections: some View {
        Section {
            if let nutritionContext = food.details.nutritionContext {
                Text(nutritionContext)
            }
            if let nutritionReference = SolidsNutritionCatalog.reference(foodID: food.id) {
                SolidFoodNutritionFactsView(
                    reference: nutritionReference,
                    showsCommonPortions: true
                )
            } else {
                Label("Nutrition estimate unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This bundled food is missing its required nutrition reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text("Reference values describe the named USDA food form, not how much a child must eat.")
        }
    }

    private func startSolidLog() {
        let router = DeepLinkRouter.shared
        router.openToday(
            action: .logSolidFeed(
                SolidFeedEditorPreset(foodIDs: [food.id], foodNames: [food.name])
            ),
            profileID: profile.id
        )
    }

    private func foodFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func servingAmountRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func addToShoppingList(_ list: ShoppingList) {
        let write = SolidsShoppingFoodWrite(
            foodID: food.id,
            foodName: food.name,
            aliases: food.aliases
        )
        Task {
            let writer = await resolvedShoppingWriter()
            let result = await writer.addFoods(
                [write],
                listID: list.id,
                householdID: list.householdID
            )
            if let error = result.error {
                shoppingMessage = "\(food.name) could not be added. Please try again."
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                shoppingMessage = result.count == 0
                    ? "\(food.name) is already on \(list.name)."
                    : "Added \(food.name) to \(list.name)."
            }
        }
    }

    @MainActor
    private func resolvedShoppingWriter() async -> SolidsShoppingListWriter {
        if let shoppingWriter { return shoppingWriter }
        let writer = await SolidsWriterPool.shared.shoppingListWriter(for: modelContext.container)
        shoppingWriter = writer
        return writer
    }
}

private struct SolidsServingPhoto: View {
    let visual: SolidsServingVisual
    let foodName: String
    var compact = false

    var body: some View {
        Image(visual.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: compact ? 72 : nil, height: compact ? 72 : 260)
            .frame(maxWidth: compact ? nil : .infinity)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 22))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 16 : 22)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel("Illustrative \(visual.displayName.lowercased()) technique for \(foodName)")
            .accessibilityIdentifier("solids.serving-photo.\(visual.rawValue)")
    }
}

private func solidsTomorrowInterval(
    now: Date = Date(),
    calendar: Calendar = .current
) -> DateInterval? {
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
    return calendar.dateInterval(of: .day, for: tomorrow)
}

struct CustomSolidFoodDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let food: SolidFoodCatalogItem
    let profile: CareProfile
    let photo: PhotoAttachment?
    let allFoods: [SolidFoodCatalogItem]
    let progress: [SolidFoodProgress]
    let plannedMeals: [PlannedSolidMeal]
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let inventoryItems: [InventoryItem]
    let foodItems: [FoodItem]
    let openPlan: (UUID) -> Void
    let openHistory: (String, String) -> Void

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShoppingLists = false
    @State private var actionMessage: String?
    @State private var isPlanningForTomorrow = false
    @State private var locallyPlannedTomorrowID: UUID?
    @State private var planWriter: SolidsPlanWriter?
    @State private var shoppingWriter: SolidsShoppingListWriter?
    @State private var catalogWriter: SolidsCustomFoodWriter?

    private var trackingID: String { "custom-\(food.id.uuidString.lowercased())" }
    private var record: SolidFoodProgress? {
        progress.first { $0.profileID == profile.id && $0.foodID == trackingID }
    }
    private var plannedTomorrowMeal: PlannedSolidMeal? {
        guard let interval = solidsTomorrowInterval() else { return nil }
        return plannedMeals.first {
            interval.contains($0.scheduledAt) && $0.foodIDs.contains(trackingID)
        }
    }
    private var isPlannedForTomorrow: Bool {
        locallyPlannedTomorrowID != nil || plannedTomorrowMeal != nil
    }
    private var ageMonths: Int { SolidsTrackingService.ageMonths(for: profile) }

    var body: some View {
        let visibleTrackingID = trackingID
        let visibleRecord = record
        List {
            Section {
                if let photo,
                   let data = photo.previewData,
                   let image = ThumbnailImageCache.image(attachmentID: photo.id, data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                LabeledContent("Earliest stage", value: "\(food.minimumAgeMonths)+ months")
            }
            if !food.preparationNotes.isEmpty {
                Section("Prepare") { Text(food.preparationNotes) }
            }
            if !food.safetyNotes.isEmpty {
                Section("Safety") { Text(food.safetyNotes).foregroundStyle(.orange) }
            }
            if !food.allergenIDs.isEmpty {
                Section("Major allergens") {
                    ForEach(food.allergenIDs, id: \.self) { id in
                        Label(SolidsAllergen(rawValue: id)?.displayName ?? id, systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            Section("Nutrition information") {
                if let nutritionReference = food.nutritionLabel?.nutritionReference {
                    SolidFoodNutritionFactsView(reference: nutritionReference)
                    Text("These values are shown for the label serving and are also used when a numeric eaten amount is logged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("No nutrition label added", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Add the package or recipe label to see nutrition here and calculate nutrient totals when this food is logged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add nutrition label", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("solids.custom-food.add-nutrition")
                }
            }
            Section("Digestive notes") {
                Text(SolidsDigestiveSupportService.generalFoodWarning(ageMonths: ageMonths))
                Text("Consider the whole feeding pattern and contact the child’s clinician for persistent or concerning symptoms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(destination: SolidsSourceLibrary.niddkChildConstipationEating) {
                    Label(
                        SolidsSourceLibrary.displayName(for: SolidsSourceLibrary.niddkChildConstipationEating),
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.caption)
                }
            }
            Section {
                Button {
                    let router = DeepLinkRouter.shared
                    router.openToday(
                        action: .logSolidFeed(SolidFeedEditorPreset(
                            foodIDs: [visibleTrackingID],
                            foodNames: [food.name],
                            allergenIDsByFoodID: [visibleTrackingID: food.allergenIDs]
                        )),
                        profileID: profile.id
                    )
                } label: {
                    Label("Log \(food.name)", systemImage: "plus.circle.fill")
                }
                Button {
                    openHistory(visibleTrackingID, food.name)
                } label: {
                    Label("View exposure timeline", systemImage: "clock.arrow.circlepath")
                }
                SolidsFoodTrackingButtons(
                    profileID: profile.id,
                    foodID: visibleTrackingID,
                    foodName: food.name,
                    initialStatus: visibleRecord?.status ?? .notTried,
                    initiallyFavorite: visibleRecord?.isFavorite == true
                )
                if let plannedTomorrowMeal {
                    Button {
                        locallyPlannedTomorrowID = nil
                        openPlan(plannedTomorrowMeal.id)
                    } label: {
                        HStack {
                            Label("Planned for tomorrow", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.green)
                    .accessibilityHint("Opens the planned meal.")
                    .accessibilityIdentifier("solids.custom-food.planned-tomorrow")
                } else if isPlannedForTomorrow {
                    Label("Planned for tomorrow", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("solids.custom-food.planned-tomorrow")
                } else {
                    Button {
                        planCustomFoodForTomorrow()
                    } label: {
                        Label(
                            isPlanningForTomorrow ? "Adding to tomorrow…" : "Plan for tomorrow",
                            systemImage: isPlanningForTomorrow ? "hourglass" : "calendar.badge.plus"
                        )
                    }
                    .disabled(isPlanningForTomorrow)
                    .accessibilityIdentifier("solids.custom-food.plan-tomorrow")
                }
                if SolidsTrackingService.isAvailableInInventory(
                    foodID: visibleTrackingID,
                    foodName: food.name,
                    inventoryItems: inventoryItems,
                    foodItems: foodItems
                ) {
                    Label("Available in kitchen inventory", systemImage: "cabinet.fill")
                        .foregroundStyle(.green)
                }
                if !shoppingLists.isEmpty {
                    Button {
                        showingShoppingLists = true
                    } label: {
                        Label("Add to shopping list", systemImage: "cart.badge.plus")
                    }
                }
            }
            Section("Your notes") {
                SolidsFoodNotesEditor(
                    profileID: profile.id,
                    foodID: visibleTrackingID,
                    foodName: food.name,
                    initialNotes: visibleRecord?.notes ?? ""
                )
                .id("\(profile.id.uuidString)-\(visibleTrackingID)")
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingEditor = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete custom food", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                CustomSolidFoodEditorView(
                    item: food,
                    existingItems: allFoods,
                    existingPhoto: photo,
                    onSave: { _, _ in }
                )
            }
        }
        .appActionSheet(
            isPresented: $showingShoppingLists,
            title: "Add \(food.name) to a list",
            message: "Choose the shopping list that should receive this food.",
            systemImage: "cart.badge.plus",
            tint: .orange,
            options: shoppingLists.map { list in
                let activeCount = shoppingItems.lazy.filter {
                    $0.shoppingListID == list.id && !$0.isChecked
                }.count
                return AppActionSheetOption(
                    title: list.name,
                    subtitle: "\(activeCount) active item\(activeCount == 1 ? "" : "s")",
                    systemImage: "list.bullet.rectangle",
                    tint: .orange
                ) {
                    addToShoppingList(list)
                }
            }
        )
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete custom food?",
            message: "Past meal history keeps the recorded food name. Foods used by a recipe or unlogged meal plan must be removed there first. Its custom photo will also be removed.",
            systemImage: "trash",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Delete \(food.name)",
                    subtitle: "Remove this food and its custom photo.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    let itemID = food.id
                    Task {
                        if let error = await resolvedCatalogWriter().delete(itemID: itemID) {
                            actionMessage = error
                            PersistenceService.recordLocalSaveFailure(error)
                        } else {
                            dismiss()
                        }
                    }
                }
            ]
        )
        .alert("Custom food", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
        .onChange(of: plannedTomorrowMeal?.id) { _, planID in
            if planID != nil {
                locallyPlannedTomorrowID = nil
            }
        }
        .onAppear {
            if locallyPlannedTomorrowID != nil, plannedTomorrowMeal == nil {
                locallyPlannedTomorrowID = nil
            }
        }
        .task {
            _ = await resolvedPlanWriter()
            _ = await resolvedShoppingWriter()
            _ = await resolvedCatalogWriter()
        }
    }

    private func planCustomFoodForTomorrow() {
        guard !isPlanningForTomorrow, !isPlannedForTomorrow else { return }
        isPlanningForTomorrow = true
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        Task {
            let writer = await resolvedPlanWriter()
            let result = await writer.saveEditorPlan(SolidsPlanEditorWrite(
                planID: nil,
                profileID: profile.id,
                scheduledAt: tomorrow,
                foodIDs: [trackingID],
                foodNames: [food.name],
                notes: food.preparationNotes,
                reminderEnabled: false,
                reminderOffsetMinutes: 30,
                duplicatePolicy: .containingSelectedFoodOnDay
            ))
            isPlanningForTomorrow = false
            if let error = result.error {
                actionMessage = "The meal plan could not be saved."
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                locallyPlannedTomorrowID = result.planID.flatMap { planID in
                    plannedMeals.contains { $0.id == planID } ? nil : planID
                }
                actionMessage = result.wasAlreadyPresent
                    ? "This food was already on tomorrow's meal plan."
                    : "Added to tomorrow's meal plan."
            }
        }
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let writer = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = writer
        return writer
    }

    @MainActor
    private func resolvedCatalogWriter() async -> SolidsCustomFoodWriter {
        if let catalogWriter { return catalogWriter }
        let writer = await SolidsWriterPool.shared.customFoodWriter(for: modelContext.container)
        catalogWriter = writer
        return writer
    }

    private func addToShoppingList(_ list: ShoppingList) {
        Task {
            let writer = await resolvedShoppingWriter()
            let result = await writer.addFoods(
                [SolidsShoppingFoodWrite(foodID: trackingID, foodName: food.name)],
                listID: list.id,
                householdID: list.householdID
            )
            if let error = result.error {
                actionMessage = "\(food.name) could not be added. Please try again."
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                actionMessage = result.count == 0
                    ? "\(food.name) is already on \(list.name)."
                    : "Added to \(list.name)."
            }
        }
    }

    @MainActor
    private func resolvedShoppingWriter() async -> SolidsShoppingListWriter {
        if let shoppingWriter { return shoppingWriter }
        let writer = await SolidsWriterPool.shared.shoppingListWriter(for: modelContext.container)
        shoppingWriter = writer
        return writer
    }
}

private struct SolidsFoodNotesEditor: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    let profileID: UUID
    let foodID: String
    let foodName: String
    let initialNotes: String

    @State private var draft: String
    @State private var lastSavedDraft: String
    @State private var writer: SolidsFoodProgressWriter?
    @State private var writeRevision = 0
    @FocusState private var isFocused: Bool

    init(profileID: UUID, foodID: String, foodName: String, initialNotes: String) {
        self.profileID = profileID
        self.foodID = foodID
        self.foodName = foodName
        self.initialNotes = initialNotes
        _draft = State(initialValue: initialNotes)
        _lastSavedDraft = State(initialValue: initialNotes)
    }

    var body: some View {
        TextField(
            "Preparation ideas or observations",
            text: $draft,
            axis: .vertical
        )
        .lineLimit(2...6)
        .focused($isFocused)
        .accessibilityIdentifier("solids.food.notes")
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused && !focused {
                saveIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                saveIfNeeded()
            }
        }
        .onChange(of: initialNotes) { oldValue, newValue in
            guard !isFocused, draft == lastSavedDraft, oldValue != newValue else { return }
            draft = newValue
            lastSavedDraft = newValue
        }
        .onDisappear {
            saveIfNeeded()
        }
    }

    private func saveIfNeeded() {
        guard draft != lastSavedDraft else { return }
        let notes = draft
        writeRevision += 1
        let revision = writeRevision
        Task {
            let progressWriter = await resolvedWriter()
            await progressWriter.scheduleNotes(
                notes,
                profileID: profileID,
                foodID: foodID,
                foodName: foodName,
                revision: revision
            )
        }
        lastSavedDraft = draft
    }

    @MainActor
    private func resolvedWriter() async -> SolidsFoodProgressWriter {
        if let writer { return writer }
        let value = await SolidsWriterPool.shared.foodProgressWriter(for: modelContext.container)
        writer = value
        return value
    }
}

private struct SolidsFoodTrackingButtons: View {
    @Environment(\.modelContext) private var modelContext

    let profileID: UUID
    let foodID: String
    let foodName: String
    let initialStatus: SolidsFoodStatus
    let initiallyFavorite: Bool

    @State private var displayedStatus: SolidsFoodStatus
    @State private var isFavorite: Bool
    @State private var writer: SolidsFoodProgressWriter?
    @State private var statusRevision = 0
    @State private var favoriteRevision = 0

    init(
        profileID: UUID,
        foodID: String,
        foodName: String,
        initialStatus: SolidsFoodStatus,
        initiallyFavorite: Bool
    ) {
        self.profileID = profileID
        self.foodID = foodID
        self.foodName = foodName
        self.initialStatus = initialStatus
        self.initiallyFavorite = initiallyFavorite
        _displayedStatus = State(initialValue: initialStatus)
        _isFavorite = State(initialValue: initiallyFavorite)
    }

    var body: some View {
        Button {
            let newStatus: SolidsFoodStatus = displayedStatus == .wantToTry ? .notTried : .wantToTry
            displayedStatus = newStatus
            statusRevision += 1
            let revision = statusRevision
            Task {
                let progressWriter = await resolvedWriter()
                await progressWriter.scheduleStatus(
                    newStatus,
                    profileID: profileID,
                    foodID: foodID,
                    foodName: foodName,
                    revision: revision
                )
            }
        } label: {
            Label(
                displayedStatus == .wantToTry ? "Remove from want to try" : "Want to try",
                systemImage: displayedStatus == .wantToTry ? "bookmark.slash" : "bookmark"
            )
        }
        .accessibilityIdentifier("solids.food.want-to-try")

        Button {
            isFavorite.toggle()
            let favorite = isFavorite
            favoriteRevision += 1
            let revision = favoriteRevision
            Task {
                let progressWriter = await resolvedWriter()
                await progressWriter.scheduleFavorite(
                    favorite,
                    profileID: profileID,
                    foodID: foodID,
                    foodName: foodName,
                    revision: revision
                )
            }
        } label: {
            Label(
                isFavorite ? "Remove favorite" : "Favorite",
                systemImage: isFavorite ? "heart.slash" : "heart"
            )
        }
        .accessibilityIdentifier("solids.food.favorite")
        .onChange(of: initialStatus) { _, value in
            displayedStatus = value
        }
        .onChange(of: initiallyFavorite) { _, value in
            isFavorite = value
        }
    }

    @MainActor
    private func resolvedWriter() async -> SolidsFoodProgressWriter {
        if let writer { return writer }
        let value = await SolidsWriterPool.shared.foodProgressWriter(for: modelContext.container)
        writer = value
        return value
    }
}

private struct SolidsPreparationWalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    let food: SolidsReferenceFood

    @State private var selectedStageIndex: Int
    @State private var selectedActionIndex = 0
    @State private var completedActionIDs = Set<String>()
    @State private var showingStageOptions = false

    init(food: SolidsReferenceFood, ageMonths: Int) {
        self.food = food
        let current = food.preparations.lastIndex { $0.minimumAgeMonths <= ageMonths } ?? 0
        _selectedStageIndex = State(initialValue: current)
    }

    private var walkthrough: SolidsPreparationWalkthrough {
        food.preparationWalkthrough(stageIndex: selectedStageIndex)
    }

    private var currentAction: SolidsPreparationAction {
        walkthrough.actions[selectedActionIndex]
    }

    private var allActionsComplete: Bool {
        completedActionIDs.count == walkthrough.actions.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stageHeader
                    progressHeader
                    actionPicker

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: currentAction.kind.systemImage)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 48, height: 48)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Step \(selectedActionIndex + 1) of \(walkthrough.actions.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(currentAction.title)
                                    .font(.title2.bold())
                            }
                        }

                        if currentAction.kind == .shape || currentAction.kind == .verify {
                            SolidsServingPhoto(
                                visual: walkthrough.visual,
                                foodName: food.name
                            )
                            Text("Target: \(walkthrough.visual.displayName)")
                                .font(.headline)
                                .foregroundStyle(.orange)
                        }

                        Text(currentAction.detail)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        if currentAction.kind == .verify {
                            Label {
                                Text(food.safetyNote)
                                    .font(.subheadline)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.orange)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        }

                        if completedActionIDs.contains(currentAction.id) {
                            Button {
                                completedActionIDs.remove(currentAction.id)
                            } label: {
                                Label(currentAction.completionLabel, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Double tap to mark this step incomplete")
                        }
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))

                    if allActionsComplete {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ready to serve")
                                    .font(.headline)
                                Text("All six checks are complete for \(walkthrough.stage.title.lowercased()). Stay within arm's reach while the child eats.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityIdentifier("solids.preparation.ready")
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("solids.preparation.walkthrough")
            .navigationTitle("Prepare \(food.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .onChange(of: selectedStageIndex) { _, _ in
                selectedActionIndex = 0
                completedActionIDs.removeAll()
            }
        }
        .appActionSheet(
            isPresented: $showingStageOptions,
            title: "Preparation stage",
            message: "Choose the age and skill stage you are preparing for.",
            systemImage: "figure.child",
            tint: .orange,
            options: Array(food.preparations.enumerated()).map { index, stage in
                AppActionSheetOption(
                    title: stage.title,
                    subtitle: stage.instructions,
                    systemImage: "figure.child",
                    tint: .orange,
                    isSelected: selectedStageIndex == index
                ) {
                    selectedStageIndex = index
                }
            }
        )
    }

    private var stageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prepare for this stage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                showingStageOptions = true
            } label: {
                HStack {
                    Label(walkthrough.stage.title, systemImage: "figure.child")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("solids.preparation.stage")
            VStack(alignment: .leading, spacing: 4) {
                Text("First serving")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(walkthrough.stage.servingAmount.firstServing)
                    .font(.subheadline)
                Text("After tolerated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(walkthrough.stage.servingAmount.routineServing)
                    .font(.subheadline)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Text("The overview explains what to serve. This checklist walks through choosing, cleaning, cooking, shaping, testing, and serving it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Preparation checklist")
                    .font(.headline)
                Spacer()
                Text("\(completedActionIDs.count) of \(walkthrough.actions.count) done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(completedActionIDs.count),
                total: Double(walkthrough.actions.count)
            )
            .tint(.orange)
        }
    }

    private var actionPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(walkthrough.actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    withAnimation(.snappy) { selectedActionIndex = index }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: completedActionIDs.contains(action.id)
                            ? "checkmark.circle.fill"
                            : action.kind.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(
                                completedActionIDs.contains(action.id)
                                    ? Color.green
                                    : (selectedActionIndex == index ? Color.orange : Color.secondary)
                            )
                            .frame(width: 34, height: 34)
                            .background(
                                selectedActionIndex == index ? Color.orange.opacity(0.12) : Color.clear,
                                in: Circle()
                            )
                        Text("\(index + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selectedActionIndex == index ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(index + 1), \(action.title)")
                .accessibilityValue(completedActionIDs.contains(action.id) ? "Completed" : "Not completed")
                .accessibilityIdentifier("solids.preparation.step.\(index)")
            }
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    selectedActionIndex = max(0, selectedActionIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(selectedActionIndex == 0)
            .accessibilityLabel("Previous preparation step")

            Button {
                completeAndContinue()
            } label: {
                Label(primaryButtonTitle, systemImage: primaryButtonImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(allActionsComplete ? .green : .orange)
            .accessibilityIdentifier("solids.preparation.complete")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var primaryButtonTitle: String {
        if allActionsComplete { return "Close walkthrough" }
        if completedActionIDs.contains(currentAction.id) { return "Continue" }
        if selectedActionIndex == walkthrough.actions.count - 1 { return "Mark ready to serve" }
        return "Complete and continue"
    }

    private var primaryButtonImage: String {
        if allActionsComplete { return "checkmark" }
        if completedActionIDs.contains(currentAction.id) { return "arrow.right" }
        return "checkmark.circle.fill"
    }

    private func completeAndContinue() {
        if allActionsComplete {
            dismiss()
            return
        }

        completedActionIDs.insert(currentAction.id)
        if selectedActionIndex < walkthrough.actions.count - 1 {
            withAnimation(.snappy) { selectedActionIndex += 1 }
        }
    }
}

struct SolidsPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: CareProfile
    let plans: [PlannedSolidMeal]
    let openPlan: (UUID) -> Void

    @State private var showingNewPlan = false
    @State private var editingPlan: PlannedSolidMeal?
    @State private var pendingDeletedPlanIDs: Set<UUID> = []
    @State private var planWriter: SolidsPlanWriter?
    @State private var deleteError: String?

    private var scopedPlans: [PlannedSolidMeal] {
        plans.filter { $0.profileID == profile.id && !pendingDeletedPlanIDs.contains($0.id) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        let visiblePlans = scopedPlans
        List {
            if visiblePlans.isEmpty {
                ContentUnavailableView(
                    "No meals planned",
                    systemImage: "calendar.badge.plus",
                    description: Text("Choose foods now, then log the plan as a solid feed event at mealtime.")
                )
            } else {
                ForEach(visiblePlans) { plan in
                    Button { openPlan(plan.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.title).font(.body.weight(.medium))
                                Text(plan.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if plan.isCompleted {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("solids.plan.row")
                    .swipeActions(edge: .leading) {
                        Button { editingPlan = plan } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    let planIDs = offsets.map { visiblePlans[$0].id }
                    pendingDeletedPlanIDs.formUnion(planIDs)
                    Task {
                        let writer = await resolvedPlanWriter()
                        if let error = await writer.deletePlans(planIDs) {
                            pendingDeletedPlanIDs.subtract(planIDs)
                            deleteError = error
                            PersistenceService.recordLocalSaveFailure(error)
                        }
                    }
                }
            }
        }
        .navigationTitle("Plan Meals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewPlan = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("solids.plan.add")
            }
        }
        .sheet(isPresented: $showingNewPlan) {
            NavigationStack {
                NewSolidMealPlanView(profile: profile, plan: nil)
            }
        }
        .sheet(item: $editingPlan) { plan in
            NavigationStack { NewSolidMealPlanView(profile: profile, plan: plan) }
        }
        .alert("Couldn’t delete meal", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text("The planned meal is still available. Please try again.")
        }
        .task {
            _ = await resolvedPlanWriter()
        }
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let writer = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = writer
        return writer
    }
}

private struct SolidPlanFoodChoice: Identifiable {
    var id: String
    var name: String
    var minimumAgeMonths: Int
    var isCustom: Bool

    var hasHardMinimumAge: Bool {
        let words = name.lowercased().split { !$0.isLetter }
        return id == "honey" || words.contains("honey")
    }
}

private final class SolidPlanNotesDraft {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}

private struct SolidPlanFoodRow: View, Equatable {
    let food: SolidPlanFoodChoice
    let ageAtMeal: Int
    let isSelected: Bool
    let action: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.food.id == rhs.food.id
            && lhs.food.name == rhs.food.name
            && lhs.food.minimumAgeMonths == rhs.food.minimumAgeMonths
            && lhs.food.isCustom == rhs.food.isCustom
            && lhs.food.hasHardMinimumAge == rhs.food.hasHardMinimumAge
            && lhs.ageAtMeal == rhs.ageAtMeal
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(food.name).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if food.isCustom {
                            Text("Custom food")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if food.minimumAgeMonths > ageAtMeal {
                            Label(
                                food.hasHardMinimumAge
                                    ? "Available at \(food.minimumAgeMonths) months"
                                    : "\(food.minimumAgeMonths)+ months",
                                systemImage: food.hasHardMinimumAge ? "lock.fill" : "calendar"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                } else if food.minimumAgeMonths > ageAtMeal {
                    Image(systemName: food.hasHardMinimumAge ? "lock.circle.fill" : "info.circle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityHint(
            food.minimumAgeMonths > ageAtMeal && !isSelected
                ? "Opens age guidance and available actions."
                : "Toggles this food in the planned meal."
        )
        .accessibilityIdentifier("solids.plan.food.\(food.id)")
    }
}

private struct SolidPlanFoodGuidanceView: View {
    @Environment(\.dismiss) private var dismiss

    let choice: SolidPlanFoodChoice
    let referenceFood: SolidsReferenceFood?
    let customFood: SolidFoodCatalogItem?
    let ageAtMeal: Int

    var body: some View {
        List {
            Section {
                Label(
                    choice.hasHardMinimumAge
                        ? "Available from \(choice.minimumAgeMonths) months"
                        : "Designed for \(choice.minimumAgeMonths)+ months",
                    systemImage: choice.hasHardMinimumAge ? "lock.fill" : "calendar"
                )
                .font(.headline)
                .foregroundStyle(.orange)
                LabeledContent("Age on planned date", value: "\(ageAtMeal) months")
                Text(choice.hasHardMinimumAge
                    ? "This is a firm minimum age, so the food cannot be added to an earlier meal."
                    : "This is a developmental recommendation. Use the preparation guidance and the child's current skills to decide when it fits."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let referenceFood {
                let stage = referenceFood.preparation(
                    forAgeMonths: max(ageAtMeal, choice.minimumAgeMonths)
                )
                Section("Preparation at this stage") {
                    Text(stage.title).font(.subheadline.weight(.semibold))
                    Text(stage.instructions)
                }
                Section("Safety") {
                    Text(referenceFood.safetyNote)
                        .foregroundStyle(.orange)
                }
            } else if let customFood {
                if !customFood.preparationNotes.isEmpty {
                    Section("Preparation") { Text(customFood.preparationNotes) }
                }
                if !customFood.safetyNotes.isEmpty {
                    Section("Safety") {
                        Text(customFood.safetyNotes).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("\(choice.name) guidance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct NewSolidMealPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SolidFoodCatalogItem.name) private var customFoods: [SolidFoodCatalogItem]
    let profile: CareProfile
    let plan: PlannedSolidMeal?

    @State private var scheduledAt: Date
    @State private var selectedFoodIDs: Set<String>
    @State private var notesDraft: SolidPlanNotesDraft
    @State private var effectiveSearchText = ""
    @State private var reminderEnabled: Bool
    @State private var reminderOffsetMinutes: Int
    @State private var showingReminderOptions = false
    @State private var reminderAuthorizationConfirmed = false
    @State private var reminderPermissionMessage: String?
    @State private var ageGuidanceFood: SolidPlanFoodChoice?
    @State private var showingAgeGuidance = false
    @State private var guidanceFood: SolidPlanFoodChoice?
    @State private var pendingGuidanceFood: SolidPlanFoodChoice?
    @State private var ageAdjustmentMessage: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var planWriter: SolidsPlanWriter?
    @State private var foodChoices: [SolidPlanFoodChoice]

    private static let bundledFoodChoices = SolidsReferenceCatalog.foodSummaries.map {
        SolidPlanFoodChoice(
            id: $0.id,
            name: $0.name,
            minimumAgeMonths: $0.minimumAgeMonths,
            isCustom: false
        )
    }

    init(profile: CareProfile, plan: PlannedSolidMeal? = nil) {
        self.profile = profile
        self.plan = plan
        let now = Date()
        let sixMonthDate = profile.birthDate.flatMap {
            Calendar.current.date(byAdding: .month, value: 6, to: $0)
        } ?? now
        _scheduledAt = State(initialValue: plan?.scheduledAt ?? max(now, sixMonthDate))
        _selectedFoodIDs = State(initialValue: Set(plan?.foodIDs ?? []))
        _notesDraft = State(initialValue: SolidPlanNotesDraft(plan?.notes ?? ""))
        _reminderEnabled = State(initialValue: plan?.reminderEnabled ?? false)
        _reminderOffsetMinutes = State(initialValue: plan?.reminderOffsetMinutes ?? 30)
        _foodChoices = State(initialValue: Self.mergedFoodChoices(customFoods: [], plan: plan))
    }

    private var ageAtMeal: Int {
        SolidsTrackingService.ageMonths(for: profile, now: scheduledAt)
    }

    private static func mergedFoodChoices(
        customFoods: [SolidFoodCatalogItem],
        plan: PlannedSolidMeal?
    ) -> [SolidPlanFoodChoice] {
        var seenIDs = Set(Self.bundledFoodChoices.map(\.id))
        var additionalChoices = customFoods.map {
            SolidPlanFoodChoice(
                id: "custom-\($0.id.uuidString.lowercased())",
                name: $0.name,
                minimumAgeMonths: $0.minimumAgeMonths,
                isCustom: true
            )
        }
        seenIDs.formUnion(additionalChoices.map(\.id))
        if let plan {
            for (id, name) in zip(plan.foodIDs, plan.foodNames)
            where seenIDs.insert(id).inserted {
                additionalChoices.append(SolidPlanFoodChoice(
                    id: id,
                    name: name,
                    minimumAgeMonths: 6,
                    isCustom: id.hasPrefix("custom-")
                ))
            }
        }
        additionalChoices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var merged: [SolidPlanFoodChoice] = []
        merged.reserveCapacity(Self.bundledFoodChoices.count + additionalChoices.count)
        var bundledIndex = 0
        var additionalIndex = 0
        while bundledIndex < Self.bundledFoodChoices.count && additionalIndex < additionalChoices.count {
            let bundled = Self.bundledFoodChoices[bundledIndex]
            let additional = additionalChoices[additionalIndex]
            if bundled.name.localizedStandardCompare(additional.name) != .orderedDescending {
                merged.append(bundled)
                bundledIndex += 1
            } else {
                merged.append(additional)
                additionalIndex += 1
            }
        }
        merged.append(contentsOf: Self.bundledFoodChoices[bundledIndex...])
        merged.append(contentsOf: additionalChoices[additionalIndex...])
        return merged
    }

    private var customFoodChoiceRevision: String {
        customFoods.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate)" }
            .joined(separator: "|")
    }

    private func refreshFoodChoices() {
        foodChoices = Self.mergedFoodChoices(customFoods: customFoods, plan: plan)
    }

    private func foods(in choices: [SolidPlanFoodChoice]) -> [SolidPlanFoodChoice] {
        let query = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return choices.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }.prefix(100).map { $0 }
    }

    private func ineligibleSelectedFoods(
        in choices: [SolidPlanFoodChoice],
        ageAtMeal: Int
    ) -> [SolidPlanFoodChoice] {
        choices.filter {
            selectedFoodIDs.contains($0.id) && $0.minimumAgeMonths > ageAtMeal
        }
    }

    private func hardRestrictedSelectedFoods(
        in choices: [SolidPlanFoodChoice],
        ageAtMeal: Int
    ) -> [SolidPlanFoodChoice] {
        choices.filter {
            selectedFoodIDs.contains($0.id)
                && $0.hasHardMinimumAge
                && $0.minimumAgeMonths > ageAtMeal
        }
    }

    private var missingPlannedAllergen: SolidsAllergen? {
        guard let allergenID = plan?.allergenID,
              let allergen = SolidsAllergen(rawValue: allergenID) else { return nil }
        let selectedContainsAllergen = selectedFoodIDs.contains { foodID in
            if let reference = SolidsReferenceCatalog.foodSummary(id: foodID) {
                return reference.allergenIDs.contains(allergenID)
            }
            return customFoods.first {
                "custom-\($0.id.uuidString.lowercased())" == foodID
            }?.allergenIDs.contains(allergenID) == true
        }
        return selectedContainsAllergen ? nil : allergen
    }

    var body: some View {
        let allChoices = foodChoices
        let visibleAgeAtMeal = ageAtMeal
        let visibleFoods = foods(in: allChoices)
        let ineligibleFoods = ineligibleSelectedFoods(in: allChoices, ageAtMeal: visibleAgeAtMeal)
        let hardRestrictedFoods = hardRestrictedSelectedFoods(
            in: allChoices,
            ageAtMeal: visibleAgeAtMeal
        )
        let plannedAllergenGap = missingPlannedAllergen
        List {
            Section("When") {
                DatePicker("Meal", selection: Binding(
                    get: { scheduledAt },
                    set: { newValue in
                        scheduledAt = newValue
                        ageAdjustmentMessage = nil
                    }
                ))
                LabeledContent("Age at meal", value: "\(visibleAgeAtMeal) months")
                if let ageAdjustmentMessage {
                    Label(ageAdjustmentMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Section("Foods") {
                ForEach(visibleFoods) { food in
                    SolidPlanFoodRow(
                        food: food,
                        ageAtMeal: visibleAgeAtMeal,
                        isSelected: selectedFoodIDs.contains(food.id)
                    ) {
                        handleFoodTap(food)
                    }
                    .equatable()
                }
                if !ineligibleFoods.isEmpty {
                    Text(hardRestrictedFoods.isEmpty
                        ? "Designed for a later stage: \(ineligibleFoods.map(\.name).joined(separator: ", ")). Keep these selected only if the child is ready and the preparation guidance fits their current skills."
                        : "Remove \(hardRestrictedFoods.map(\.name).joined(separator: ", ")) or move the meal to the listed minimum age before saving."
                    )
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let plannedAllergenGap {
                    Text("Keep at least one food containing \(plannedAllergenGap.displayName) so this planned exposure remains accurate.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("Notes") {
                SolidPlanNotesField(draft: notesDraft)
            }
            Section("Reminder") {
                Toggle("Remind me", isOn: Binding(
                    get: { reminderEnabled },
                    set: { requested in setReminderEnabled(requested) }
                ))
                if reminderEnabled {
                    SolidsDrawerSelectionButton(
                        title: "Before meal",
                        value: reminderOffsetTitle(reminderOffsetMinutes),
                        systemImage: "bell.badge"
                    ) {
                        showingReminderOptions = true
                    }
                }
            }
        }
        .navigationTitle(plan == nil ? "New Solids Plan" : "Edit Solids Plan")
        .navigationBarTitleDisplayMode(.inline)
        .debouncedSearch(text: $effectiveSearchText, prompt: "Find foods")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await savePlan() }
                }
                .accessibilityIdentifier("solids.plan.save")
                .disabled(
                    selectedFoodIDs.isEmpty
                        || !hardRestrictedFoods.isEmpty
                        || plannedAllergenGap != nil
                        || isSaving
                )
            }
        }
        .alert("Notifications unavailable", isPresented: Binding(
            get: { reminderPermissionMessage != nil },
            set: { if !$0 { reminderPermissionMessage = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                reminderPermissionMessage = nil
            }
            Button("Not now", role: .cancel) { reminderPermissionMessage = nil }
        } message: {
            Text(reminderPermissionMessage ?? "")
        }
        .alert("Couldn’t save meal", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text("Your changes are still on this screen. Please try again.")
        }
        .appActionSheet(
            isPresented: $showingReminderOptions,
            title: "Meal reminder",
            message: "Choose when the reminder should arrive.",
            systemImage: "bell.badge",
            tint: .orange,
            options: [0, 15, 30, 60].map { minutes in
                AppActionSheetOption(
                    title: reminderOffsetTitle(minutes),
                    systemImage: minutes == 0 ? "bell.fill" : "clock.badge",
                    tint: .orange,
                    isSelected: reminderOffsetMinutes == minutes
                ) {
                    reminderOffsetMinutes = minutes
                }
            }
        )
        .appActionSheet(
            isPresented: $showingAgeGuidance,
            title: ageGuidanceTitle,
            message: ageGuidanceMessage,
            systemImage: ageGuidanceFood?.hasHardMinimumAge == true ? "lock.fill" : "calendar",
            tint: .orange,
            options: ageGuidanceOptions,
            onDismiss: presentPendingGuidance
        )
        .sheet(item: $guidanceFood) { food in
            NavigationStack {
                SolidPlanFoodGuidanceView(
                    choice: food,
                    referenceFood: SolidsReferenceCatalog.food(id: food.id),
                    customFood: customFood(for: food),
                    ageAtMeal: ageAtMeal
                )
            }
        }
        .task {
            _ = await resolvedPlanWriter()
            refreshFoodChoices()
        }
        .onChange(of: customFoodChoiceRevision) { _, _ in refreshFoodChoices() }
    }

    private func setReminderEnabled(_ requested: Bool) {
        guard requested else {
            reminderEnabled = false
            return
        }
        Task {
            let allowed = await NotificationManager.shared.ensureAuthorization()
            if allowed {
                reminderAuthorizationConfirmed = true
                reminderEnabled = true
            } else {
                reminderAuthorizationConfirmed = false
                reminderEnabled = false
                reminderPermissionMessage = "Allow notifications in Settings to turn on meal reminders."
            }
        }
    }

    private func reminderOffsetTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: "At meal time"
        case 15: "15 minutes before"
        case 30: "30 minutes before"
        case 60: "1 hour before"
        default: "\(minutes) minutes before"
        }
    }

    private func toggleFood(_ food: SolidPlanFoodChoice) {
        if selectedFoodIDs.contains(food.id) {
            selectedFoodIDs.remove(food.id)
        } else {
            guard !food.hasHardMinimumAge || food.minimumAgeMonths <= ageAtMeal else { return }
            selectedFoodIDs.insert(food.id)
        }
    }

    private func handleFoodTap(_ food: SolidPlanFoodChoice) {
        if selectedFoodIDs.contains(food.id) {
            toggleFood(food)
        } else if food.minimumAgeMonths > ageAtMeal {
            ageGuidanceFood = food
            showingAgeGuidance = true
        } else {
            toggleFood(food)
        }
    }

    private var ageGuidanceTitle: String {
        guard let food = ageGuidanceFood else { return "Age guidance" }
        return food.hasHardMinimumAge
            ? "\(food.name) is available at \(food.minimumAgeMonths) months"
            : "\(food.name) is designed for \(food.minimumAgeMonths)+ months"
    }

    private var ageGuidanceMessage: String? {
        guard let food = ageGuidanceFood else { return nil }
        if food.hasHardMinimumAge {
            return "This food cannot be added to a meal before the listed minimum age. Move the meal date or review its guidance."
        }
        return "\(profile.name) will be \(ageAtMeal) months on this date. Review readiness and preparation before adding this later-stage food."
    }

    private var ageGuidanceOptions: [AppActionSheetOption] {
        guard let food = ageGuidanceFood else { return [] }
        var options: [AppActionSheetOption] = []
        if !food.hasHardMinimumAge {
            options.append(AppActionSheetOption(
                title: "Add to this meal",
                subtitle: "Keep the current date and use the age-specific preparation guidance.",
                systemImage: "plus.circle.fill",
                tint: .orange
            ) {
                selectedFoodIDs.insert(food.id)
                ageGuidanceFood = nil
            })
        }
        options.append(AppActionSheetOption(
            title: "Move meal to \(food.minimumAgeMonths) months",
            subtitle: eligibilityDate(for: food).formatted(date: .abbreviated, time: .omitted),
            systemImage: "calendar.badge.clock",
            tint: .orange
        ) {
            moveMealToEligibilityDate(for: food)
            ageGuidanceFood = nil
        })
        options.append(AppActionSheetOption(
            title: "View food guidance",
            subtitle: "Review preparation and safety without losing this meal draft.",
            systemImage: "book.pages",
            tint: .orange
        ) {
            pendingGuidanceFood = food
            ageGuidanceFood = nil
        })
        return options
    }

    private func presentPendingGuidance() {
        guard let pendingGuidanceFood else { return }
        self.pendingGuidanceFood = nil
        guidanceFood = pendingGuidanceFood
    }

    private func eligibilityDate(for food: SolidPlanFoodChoice) -> Date {
        guard let birthDate = profile.birthDate else { return scheduledAt }
        return Calendar.current.date(
            byAdding: .month,
            value: food.minimumAgeMonths,
            to: birthDate
        ) ?? scheduledAt
    }

    private func moveMealToEligibilityDate(for food: SolidPlanFoodChoice) {
        let calendar = Calendar.current
        let eligibleDay = eligibilityDate(for: food)
        let time = calendar.dateComponents([.hour, .minute, .second], from: scheduledAt)
        scheduledAt = calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: eligibleDay
        ) ?? eligibleDay
        selectedFoodIDs.insert(food.id)
        ageAdjustmentMessage = "Moved the meal to \(food.minimumAgeMonths) months and added \(food.name)."
    }

    private func customFood(for food: SolidPlanFoodChoice) -> SolidFoodCatalogItem? {
        guard food.isCustom else { return nil }
        return customFoods.first {
            "custom-\($0.id.uuidString.lowercased())" == food.id
        }
    }

    private func savePlan() async {
        guard !selectedFoodIDs.isEmpty, missingPlannedAllergen == nil else { return }
        isSaving = true
        defer { isSaving = false }
        if reminderEnabled, !reminderAuthorizationConfirmed {
            guard await NotificationManager.shared.ensureAuthorization() else {
                reminderPermissionMessage = "Allow notifications in Settings before saving this reminder."
                return
            }
            reminderAuthorizationConfirmed = true
        }
        let selected = foodChoices.filter { selectedFoodIDs.contains($0.id) }
        let foodIDs = selected.map(\.id)
        let foodNames = selected.map(\.name)
        let writer = await resolvedPlanWriter()
        let result = await writer.saveEditorPlan(SolidsPlanEditorWrite(
            planID: plan?.id,
            profileID: profile.id,
            scheduledAt: scheduledAt,
            foodIDs: foodIDs,
            foodNames: foodNames,
            notes: notesDraft.text,
            reminderEnabled: reminderEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes
        ))
        if let error = result.error {
            saveError = error
            PersistenceService.recordLocalSaveFailure(error)
        } else {
            dismiss()
        }
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let writer = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = writer
        return writer
    }
}

private struct SolidPlanNotesField: View {
    let draft: SolidPlanNotesDraft
    @State private var text: String

    init(draft: SolidPlanNotesDraft) {
        self.draft = draft
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        TextField("Optional", text: $text, axis: .vertical)
            .onChange(of: text) { _, value in
                draft.text = value
            }
    }
}

private enum PlannedSolidMealAlert: Identifiable {
    case shoppingMessage(String)
    case deleteFailure

    var id: String {
        switch self {
        case .shoppingMessage: "shopping-message"
        case .deleteFailure: "delete-failure"
        }
    }
}

struct PlannedSolidMealDetailView: View {
    let plan: PlannedSolidMeal
    let profile: CareProfile
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let inventoryItems: [InventoryItem]
    let foodItems: [FoodItem]
    let openFood: (String, String) -> Void
    let openRecipe: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SolidFoodCatalogItem.name) private var customSolidFoods: [SolidFoodCatalogItem]
    @Query(sort: \CustomSolidRecipe.updatedAt, order: .reverse) private var customSolidRecipes: [CustomSolidRecipe]
    @State private var showingEdit = false
    @State private var showingShoppingLists = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var activeAlert: PlannedSolidMealAlert?
    @State private var planWriter: SolidsPlanWriter?
    @State private var shoppingWriter: SolidsShoppingListWriter?

    var body: some View {
        List {
            Section("Meal") {
                LabeledContent("For", value: profile.name)
                LabeledContent("When", value: plan.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                ForEach(Array(zip(plan.foodIDs, plan.foodNames).enumerated()), id: \.offset) { _, food in
                    Button { openFood(food.0, food.1) } label: {
                        HStack {
                            Label(food.1, systemImage: "circle.fill")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let recipeID = plan.recipeID,
                   let recipe = SolidsReferenceCatalog.recipe(id: recipeID) {
                    Button { openRecipe(recipeID) } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recipe")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(recipe.title)
                                        .foregroundStyle(.primary)
                                }
                            } icon: {
                                Image(systemName: "fork.knife")
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("solids.plan.recipe.\(recipeID)")
                } else if let recipeID = plan.recipeID,
                          let recipe = customSolidRecipes.first(where: { $0.trackingID == recipeID }) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recipe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(recipe.name)
                        }
                    } icon: {
                        Image(systemName: "fork.knife")
                    }
                }
                if let allergenID = plan.allergenID,
                   let allergen = SolidsAllergen(rawValue: allergenID) {
                    if let step = plan.allergenIntroductionStep {
                        Label("\(allergen.displayName) introduction portion \(step) of 3", systemImage: "allergens")
                            .foregroundStyle(.orange)
                    } else {
                        Label("\(allergen.displayName) rotation meal", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                    }
                }
                if let guidance = plan.allergenServingGuidance, !guidance.isEmpty {
                    Text(guidance).font(.subheadline)
                }
                if let minutes = plan.allergenObservationMinutes {
                    Label("Pause and observe for about \(minutes) minutes after the first taste.", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !plan.notes.isEmpty { Text(plan.notes) }
                if plan.reminderEnabled {
                    Label("Reminder \(plan.reminderOffsetMinutes) minutes before", systemImage: "bell.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                if plan.isCompleted {
                    Label("Logged", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        let router = DeepLinkRouter.shared
                        router.openToday(
                            action: .logSolidFeed(SolidsTrackingService.preset(
                                for: plan,
                                customRecipes: customSolidRecipes,
                                customFoods: customSolidFoods
                            )),
                            profileID: profile.id
                        )
                    } label: {
                        Label("Log this meal", systemImage: "plus.circle.fill")
                    }
                }
            }
            if !shoppingLists.isEmpty {
                Section("Household") {
                    let availableCount = zip(plan.foodIDs, plan.foodNames).filter {
                        SolidsTrackingService.isAvailableInInventory(
                            foodID: $0.0,
                            foodName: $0.1,
                            inventoryItems: inventoryItems,
                            foodItems: foodItems
                        )
                    }.count
                    if availableCount > 0 {
                        Label("\(availableCount) ingredient\(availableCount == 1 ? "" : "s") already in inventory", systemImage: "cabinet.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        showingShoppingLists = true
                    } label: {
                        Label("Add missing ingredients", systemImage: "cart.badge.plus")
                    }
                    .accessibilityIdentifier("solids.plan.add-missing-ingredients")
                }
            }
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(
                        isDeleting ? "Deleting planned meal…" : "Delete planned meal",
                        systemImage: "trash"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityIdentifier("solids.plan.delete")
            }
        }
        .navigationTitle("Planned Meal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { NewSolidMealPlanView(profile: profile, plan: plan) }
        }
        .appActionSheet(
            isPresented: $showingShoppingLists,
            title: "Add missing ingredients",
            message: "Choose a shopping list. Ingredients already in inventory or on that list will be skipped.",
            systemImage: "cart.badge.plus",
            tint: .orange,
            options: shoppingLists.map { list in
                let activeCount = shoppingItems.lazy.filter {
                    $0.shoppingListID == list.id && !$0.isChecked
                }.count
                return AppActionSheetOption(
                    title: list.name,
                    subtitle: "\(activeCount) active item\(activeCount == 1 ? "" : "s")",
                    systemImage: "list.bullet.rectangle",
                    tint: .orange
                ) {
                    addMissingIngredients(to: list)
                }
            }
        )
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete planned meal?",
            message: plan.isCompleted
                ? "This removes the plan and cancels its reminder. The logged solids meal stays in feeding history."
                : "This removes the plan and cancels its reminder. This can't be undone.",
            systemImage: "trash.fill",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Delete Planned Meal",
                    subtitle: "Remove the plan and cancel its reminder.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive,
                    isEnabled: !isDeleting
                ) {
                    deletePlan()
                }
            ]
        )
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .shoppingMessage(let message):
                Alert(
                    title: Text("Shopping list"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .deleteFailure:
                Alert(
                    title: Text("Couldn’t delete meal"),
                    message: Text("The planned meal is still available. Please try again."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .task {
            _ = await resolvedShoppingWriter()
            _ = await resolvedPlanWriter()
        }
    }

    private func deletePlan() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            let writer = await resolvedPlanWriter()
            if let error = await writer.deletePlans([plan.id]) {
                isDeleting = false
                activeAlert = .deleteFailure
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                dismiss()
            }
        }
    }

    private func addMissingIngredients(to list: ShoppingList) {
        let writes = SolidsTrackingService.shoppingWrites(
            foodIDs: plan.foodIDs,
            foodNames: plan.foodNames,
            inventoryItems: inventoryItems,
            foodItems: foodItems,
            skipAvailableInventory: true
        )
        guard !writes.isEmpty else {
            activeAlert = .shoppingMessage("All ingredients are already available in inventory.")
            return
        }
        Task {
            let writer = await resolvedShoppingWriter()
            let result = await writer.addFoods(
                writes,
                listID: list.id,
                householdID: list.householdID
            )
            if let error = result.error {
                activeAlert = .shoppingMessage("The ingredients could not be added. Please try again.")
                PersistenceService.recordLocalSaveFailure(error)
            } else if result.count == 0 {
                activeAlert = .shoppingMessage("The missing ingredients are already on \(list.name).")
            } else {
                activeAlert = .shoppingMessage("Added \(result.count) ingredient\(result.count == 1 ? "" : "s") to \(list.name).")
            }
        }
    }

    @MainActor
    private func resolvedShoppingWriter() async -> SolidsShoppingListWriter {
        if let shoppingWriter { return shoppingWriter }
        let writer = await SolidsWriterPool.shared.shoppingListWriter(for: modelContext.container)
        shoppingWriter = writer
        return writer
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let writer = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = writer
        return writer
    }
}

private enum SolidsTrackerSort: String, CaseIterable, Identifiable {
    case recentlyTried
    case firstTried
    case mostExposures
    case name

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recentlyTried: "Recently tried"
        case .firstTried: "First tried"
        case .mostExposures: "Most exposures"
        case .name: "Food name"
        }
    }
}

private func solidTrackedAmountDescription(_ item: SolidFoodEventItem) -> String? {
    guard let unit = item.portionUnit else { return nil }
    let formatted: (Double) -> String = {
        $0.formatted(.number.precision(.fractionLength(0...2)))
    }
    if let eaten = item.amountEaten, let offered = item.amountOffered {
        return "\(formatted(eaten)) of \(formatted(offered)) \(unit.abbreviatedName) eaten"
    }
    if let eaten = item.amountEaten {
        return "\(formatted(eaten)) \(unit.abbreviatedName) eaten"
    }
    if let offered = item.amountOffered,
       let estimate = item.consumptionEstimate,
       let fraction = estimate.offeredFraction {
        return "About \(formatted(offered * fraction)) of \(formatted(offered)) \(unit.abbreviatedName) eaten (\(estimate.displayName.lowercased()) estimate)"
    }
    if let offered = item.amountOffered {
        return "\(formatted(offered)) \(unit.abbreviatedName) offered"
    }
    return nil
}

private func solidMealRecipeName(
    eventID: UUID,
    items: [SolidFoodEventItem]
) -> String? {
    items.lazy
        .filter { $0.eventID == eventID }
        .compactMap(\.recipeNameSnapshot)
        .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct SolidsTrackerView: View {
    let profile: CareProfile
    let events: [CareEvent]
    let progress: [SolidFoodProgress]
    let eventItems: [SolidFoodEventItem]
    let openFoodHistory: (String, String) -> Void
    let openMeal: (UUID) -> Void

    @State private var filter: SolidsTrackerFilter
    @State private var sort: SolidsTrackerSort = .recentlyTried
    @State private var effectiveSearchText = ""
    @State private var showingSortOptions = false

    init(
        profile: CareProfile,
        initialFilter: SolidsTrackerFilter = .all,
        events: [CareEvent],
        progress: [SolidFoodProgress],
        eventItems: [SolidFoodEventItem],
        openFoodHistory: @escaping (String, String) -> Void,
        openMeal: @escaping (UUID) -> Void
    ) {
        self.profile = profile
        self.events = events
        self.progress = progress
        self.eventItems = eventItems
        self.openFoodHistory = openFoodHistory
        self.openMeal = openMeal
        _filter = State(initialValue: initialFilter)
    }

    private var scopedProgress: [SolidFoodProgress] {
        let query = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Build this once for the filter pass. Referencing a computed property
        // from the closure rebuilt the full set for every progress row.
        let reactionFoodIDs = filter == .reactions
            ? Set(eventItems.lazy.filter {
                $0.profileID == profile.id && $0.suspectedReaction
            }.map(\.foodID))
            : []
        let filtered = progress.filter { item in
            guard item.profileID == profile.id,
                  item.status != .notTried || item.isFavorite,
                  query.isEmpty || item.foodNameSnapshot.localizedCaseInsensitiveContains(query) else {
                return false
            }
            switch filter {
            case .all: return true
            case .tried: return item.status == .tried
            case .favorites: return item.isFavorite
            case .wantToTry: return item.status == .wantToTry
            case .reactions: return reactionFoodIDs.contains(item.foodID)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch sort {
            case .recentlyTried:
                return (lhs.lastTriedAt ?? .distantPast) > (rhs.lastTriedAt ?? .distantPast)
            case .firstTried:
                return (lhs.firstTriedAt ?? .distantFuture) < (rhs.firstTriedAt ?? .distantFuture)
            case .mostExposures:
                if lhs.exposureCount != rhs.exposureCount { return lhs.exposureCount > rhs.exposureCount }
                return lhs.foodNameSnapshot.localizedStandardCompare(rhs.foodNameSnapshot) == .orderedAscending
            case .name:
                return lhs.foodNameSnapshot.localizedStandardCompare(rhs.foodNameSnapshot) == .orderedAscending
            }
        }
    }

    private var scopedMeals: [CareEvent] {
        events.filter { $0.profileID == profile.id && $0.type == .feed && $0.feedKind == .solid }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        let visibleProgress = scopedProgress
        let visibleMeals = scopedMeals
        // Progress is reconciled from the complete history, so this total
        // remains exact without counting every event item on each render.
        let totalExposureCount = progress.lazy
            .filter { $0.profileID == profile.id }
            .reduce(0) { $0 + $1.exposureCount }
        let recipeNamesByEventID = eventItems.reduce(into: [UUID: String]()) { names, item in
            guard item.profileID == profile.id,
                  names[item.eventID] == nil,
                  let name = item.recipeNameSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            names[item.eventID] = name
        }
        List {
            Section("Summary") {
                LabeledContent("Foods tried", value: "\(visibleProgress.lazy.filter { $0.status == .tried }.count)")
                LabeledContent("Total exposures", value: "\(totalExposureCount)")
                LabeledContent("Favorites", value: "\(visibleProgress.lazy.filter(\.isFavorite).count)")
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(SolidsTrackerFilter.allCases) { value in
                            Button(value.title) { filter = value }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(filter == value ? .orange : .secondary)
                                .accessibilityIdentifier("solids.tracker.filter.\(value.rawValue)")
                                .accessibilityValue(filter == value ? "Selected" : "Not selected")
                        }
                    }
                }
                SolidsDrawerSelectionButton(
                    title: "Sort foods",
                    value: sort.title,
                    systemImage: "arrow.up.arrow.down"
                ) {
                    showingSortOptions = true
                }
            }
            Section("Foods") {
                if visibleProgress.isEmpty {
                    Text(emptyFoodsMessage)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleProgress) { item in
                    Button { openFoodHistory(item.foodID, item.foodNameSnapshot) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.foodNameSnapshot).foregroundStyle(.primary)
                                Text("\(item.exposureCount) exposure\(item.exposureCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                            Image(systemName: item.status == .tried ? "checkmark.circle.fill" : "bookmark.fill")
                                .foregroundStyle(item.status == .tried ? .green : .orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Meal history") {
                if visibleMeals.isEmpty {
                    Text("Logged solid feed events will appear here.").foregroundStyle(.secondary)
                }
                ForEach(visibleMeals) { event in
                    Button { openMeal(event.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recipeNamesByEventID[event.id]
                                    ?? event.foodDescription
                                    ?? "Solids meal")
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if event.solidSensitivityObserved == true {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Food Tracker")
        .debouncedSearch(text: $effectiveSearchText, prompt: "Search tracked foods")
        .appActionSheet(
            isPresented: $showingSortOptions,
            title: "Sort foods",
            message: "Choose how tracked foods are ordered.",
            systemImage: "arrow.up.arrow.down",
            tint: .orange,
            options: SolidsTrackerSort.allCases.map { value in
                AppActionSheetOption(
                    title: value.title,
                    systemImage: sortSystemImage(value),
                    tint: .orange,
                    isSelected: sort == value
                ) {
                    sort = value
                }
            }
        )
    }

    private var emptyFoodsMessage: String {
        switch filter {
        case .all:
            "Foods logged from a solid feed event or saved for later will appear here."
        case .tried:
            "No foods have been marked tried yet."
        case .favorites:
            "No foods have been marked as favorites yet."
        case .wantToTry:
            "No foods are saved to Want to try yet."
        case .reactions:
            "No foods with suspected reactions have been logged."
        }
    }

    private func sortSystemImage(_ value: SolidsTrackerSort) -> String {
        switch value {
        case .recentlyTried: "clock.arrow.circlepath"
        case .firstTried: "calendar"
        case .mostExposures: "number.circle"
        case .name: "textformat.abc"
        }
    }
}

struct SolidFoodHistoryView: View {
    let profile: CareProfile
    let foodID: String
    let foodName: String
    let eventItems: [SolidFoodEventItem]
    let openMeal: (UUID) -> Void

    private var exposures: [SolidFoodEventItem] {
        eventItems.filter { $0.profileID == profile.id && $0.foodID == foodID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        let visibleExposures = exposures
        List {
            Section("Summary") {
                LabeledContent("Meals recorded", value: "\(Set(visibleExposures.map(\.eventID)).count)")
                if let first = visibleExposures.last?.createdAt {
                    LabeledContent("First tried", value: first.formatted(date: .abbreviated, time: .omitted))
                }
                if let latest = visibleExposures.first?.createdAt {
                    LabeledContent("Most recent", value: latest.formatted(date: .abbreviated, time: .omitted))
                }
                if visibleExposures.contains(where: \.suspectedReaction) {
                    Label("A possible reaction is recorded", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section("Exposure timeline") {
                if visibleExposures.isEmpty {
                    Text("No logged meals for this food.").foregroundStyle(.secondary)
                }
                ForEach(visibleExposures) { item in
                    Button { openMeal(item.eventID) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.createdAt
                                    .formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 8) {
                                if let amount = solidTrackedAmountDescription(item) {
                                    Text(amount)
                                } else if !item.servingAmount.isEmpty {
                                    Text(item.servingAmount)
                                }
                                if item.reaction != .unknown { Text(item.reaction.displayName) }
                                if item.suspectedReaction { Text("Reaction noted").foregroundStyle(.red) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !item.notes.isEmpty {
                                Text(item.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(foodName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SolidMealDetailView: View {
    let event: CareEvent
    let items: [SolidFoodEventItem]
    let editEvent: () -> Void

    private var scopedItems: [SolidFoodEventItem] {
        items.filter { $0.eventID == event.id }.sorted { $0.foodNameSnapshot < $1.foodNameSnapshot }
    }

    var body: some View {
        let visibleItems = scopedItems
        List {
            Section("Meal") {
                LabeledContent("When", value: event.startDate.formatted(date: .abbreviated, time: .shortened))
                if let recipeName = solidMealRecipeName(eventID: event.id, items: visibleItems) {
                    LabeledContent("Recipe", value: recipeName)
                }
                if let style = event.solidFeedingStyle { LabeledContent("Style", value: style.displayName) }
                if let texture = event.solidTexture { LabeledContent("Texture", value: texture.displayName) }
                if let notes = event.notes, !notes.isEmpty { Text(notes) }
            }
            ForEach(visibleItems) { item in
                Section(item.foodNameSnapshot) {
                    if let amount = solidTrackedAmountDescription(item) {
                        LabeledContent("Amount", value: amount)
                    } else if !item.servingAmount.isEmpty {
                        LabeledContent("Amount", value: item.servingAmount)
                    }
                    if item.reaction != .unknown { LabeledContent("Preference", value: item.reaction.displayName) }
                    if !item.notes.isEmpty { Text(item.notes) }
                    if !item.allergenIDs.isEmpty {
                        LabeledContent("Allergens", value: item.allergenIDs.compactMap {
                            SolidsAllergen(rawValue: $0)?.displayName
                        }.joined(separator: ", "))
                    }
                    if item.suspectedReaction {
                        Label("Possible reaction", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        if !item.symptoms.isEmpty {
                            LabeledContent("Symptoms", value: item.symptoms.map(\.displayName).joined(separator: ", "))
                        }
                        if item.severity != .unknown { LabeledContent("Severity", value: item.severity.displayName) }
                        if let minutes = item.onsetMinutes { LabeledContent("Onset", value: "\(minutes) minutes") }
                        if let duration = item.durationMinutes { LabeledContent("Duration", value: "\(duration) minutes") }
                        if !item.responseNotes.isEmpty { Text(item.responseNotes) }
                        if item.followUp != .none { LabeledContent("Follow-up", value: item.followUp.displayName) }
                    }
                    nutritionRows(for: item)
                }
            }
        }
        .navigationTitle("Solids Meal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit", action: editEvent) }
        }
    }

    @ViewBuilder
    private func nutritionRows(for item: SolidFoodEventItem) -> some View {
        if let snapshot = item.nutritionSnapshot {
            solidNutrientRow("Calories", value: snapshot.nutrients.energyKilocalories, unit: "kcal")
            solidNutrientRow("Protein", value: snapshot.nutrients.proteinGrams, unit: "g")
            solidNutrientRow("Fat", value: snapshot.nutrients.fatGrams, unit: "g")
            solidNutrientRow("Fiber", value: snapshot.nutrients.fiberGrams, unit: "g")
            solidNutrientRow("Iron", value: snapshot.nutrients.ironMilligrams, unit: "mg")
            solidNutrientRow("Zinc", value: snapshot.nutrients.zincMilligrams, unit: "mg")
            solidNutrientRow("Calcium", value: snapshot.nutrients.calciumMilligrams, unit: "mg")
            solidNutrientRow("Vitamin C", value: snapshot.nutrients.vitaminCMilligrams, unit: "mg")
            LabeledContent(
                "Nutrition source",
                value: "\(snapshot.sourceKind.displayName): \(snapshot.sourceDescription)"
            )
            .font(.caption)
            if snapshot.isComplete {
                Label("All eight tracked nutrients are included.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Only values present on the saved manual label are included.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            Label(nutritionUnavailableText(for: item), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func nutritionUnavailableText(for item: SolidFoodEventItem) -> String {
        let hasEatenAmount = item.amountEaten != nil
            || (item.amountOffered != nil && item.consumptionEstimate?.offeredFraction != nil)
        guard hasEatenAmount else {
            return "Nutrition was not calculated because no eaten amount was recorded."
        }
        if item.foodID.hasPrefix("custom-") {
            return "Nutrition was not calculated because this custom food had no usable manual label when logged."
        }
        return "Nutrition was not available for this saved amount."
    }

    @ViewBuilder
    private func solidNutrientRow(_ title: String, value: Double?, unit: String) -> some View {
        if let value {
            LabeledContent(
                "Estimated \(title.lowercased())",
                value: "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
            )
        }
    }
}

struct SolidsAllergensView: View {
    let profile: CareProfile
    let progress: [SolidAllergenProgress]
    let openAllergen: (String) -> Void

    var body: some View {
        let progressByAllergenID = progress.reduce(into: [String: SolidAllergenProgress]()) {
            result, item in
            guard item.profileID == profile.id else { return }
            result[item.allergenID] = item
        }
        List {
            Section {
                Text("The nine major U.S. food allergens are tracked from foods saved in solid feed events. Introduce foods in a form appropriate for current skills and follow individualized medical advice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Introduction history") {
                ForEach(SolidsAllergen.allCases.map(\.rawValue), id: \.self) { allergenID in
                    Button { openAllergen(allergenID) } label: {
                        allergenRow(
                            allergenID,
                            exposureCount: progressByAllergenID[allergenID]?.exposureMealCount ?? 0,
                            record: progressByAllergenID[allergenID]
                        )
                    }
                        .buttonStyle(.plain)
                }
            }
            Section("Important") {
                Text("A tracker cannot determine whether a symptom is an allergy. Seek urgent medical help for trouble breathing, swelling, collapse, or other severe symptoms.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Link("FDA major food allergen information", destination: SolidsSourceLibrary.fdaAllergens)
            }
        }
        .navigationTitle("Allergens")
    }

    private func allergenRow(
        _ allergenID: String,
        exposureCount count: Int,
        record: SolidAllergenProgress?
    ) -> some View {
        let allergen = SolidsAllergen(rawValue: allergenID)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(allergen?.displayName ?? allergenID).font(.body.weight(.medium))
                Text(record?.status.displayName ?? (count == 0 ? "No recorded introduction" : "Introducing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Image(systemName: record?.status == .tolerated ? "checkmark.circle.fill" : count == 0 ? "circle" : "clock.badge.checkmark")
                .foregroundStyle(record?.status == .suspectedReaction || record?.status == .avoidPendingAdvice
                    ? Color.red : record?.status == .tolerated ? Color.green : Color.orange)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct SolidsAllergenDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let allergen: SolidsAllergen
    let profile: CareProfile
    let eventItems: [SolidFoodEventItem]
    let progress: SolidAllergenProgress?
    let allProgress: [SolidAllergenProgress]
    let plans: [PlannedSolidMeal]
    let openRecipe: (String) -> Void

    @State private var status: SolidAllergenStatus
    @State private var hasManualStatusOverride: Bool
    @State private var reminderEnabled: Bool
    @State private var showingStatusOptions = false
    @State private var plannedConfirmation: String?
    @State private var reminderPermissionMessage: String?
    @State private var writer: SolidsAllergenProgressWriter?
    @State private var planWriter: SolidsPlanWriter?
    @State private var isBuildingPlan = false
    @State private var statusRevision = 0
    @State private var reminderRevision = 0

    init(
        allergen: SolidsAllergen,
        profile: CareProfile,
        eventItems: [SolidFoodEventItem],
        progress: SolidAllergenProgress?,
        allProgress: [SolidAllergenProgress],
        plans: [PlannedSolidMeal],
        openRecipe: @escaping (String) -> Void
    ) {
        self.allergen = allergen
        self.profile = profile
        self.eventItems = eventItems
        self.progress = progress
        self.allProgress = allProgress
        self.plans = plans
        self.openRecipe = openRecipe
        _status = State(initialValue: progress?.status ?? .notStarted)
        _hasManualStatusOverride = State(initialValue: progress?.statusOverride != nil)
        _reminderEnabled = State(initialValue: progress?.reminderEnabled == true)
    }

    private var guidance: SolidsAllergenGuidance {
        SolidsReferenceCatalog.allergenGuidance(allergen)
    }

    private var exposures: [SolidFoodEventItem] {
        eventItems.filter { $0.profileID == profile.id && $0.allergenIDs.contains(allergen.rawValue) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var recommendedRecipes: [SolidsReferenceRecipe] {
        SolidsTrackingService.recommendedRecipes(
            for: allergen,
            ageMonths: SolidsTrackingService.ageMonths(for: profile),
            introducedAllergenIDs: Set(allProgress.filter {
                $0.profileID == profile.id && $0.status == .tolerated
            }.map(\.allergenID))
        )
    }

    private var canPlanExposure: Bool {
        status != .suspectedReaction && status != .avoidPendingAdvice && !recommendedRecipes.isEmpty
    }

    var body: some View {
        let visibleGuidance = guidance
        let visibleExposures = exposures
        let visibleRecipes = recommendedRecipes
        let canPlanVisibleExposure = status != .suspectedReaction
            && status != .avoidPendingAdvice
            && !visibleRecipes.isEmpty
        List {
            Section("Safe form") {
                Text(visibleGuidance.safeForm)
                Text(visibleGuidance.exampleServing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("This is an example portion, not a required dose. Follow individualized advice for children with eczema, an existing allergy, or a prior reaction.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Introduction steps") {
                ForEach(visibleGuidance.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "\(step.number).circle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(step.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Progress") {
                SolidsDrawerSelectionButton(
                    title: "Manual status",
                    value: status.displayName,
                    systemImage: "allergens"
                ) {
                    showingStatusOptions = true
                }
                if hasManualStatusOverride {
                    Button("Use automatic progress") {
                        clearStatusOverride(using: visibleExposures)
                    }
                }
                LabeledContent("Meals recorded", value: "\(Set(visibleExposures.map(\.eventID)).count)")
                LabeledContent("Confirmed introduction portions", value: "\(progress?.introductionStep ?? 0) of 3")
                if let next = progress?.nextExposureDueAt,
                   status != .suspectedReaction, status != .avoidPendingAdvice {
                    LabeledContent("Next rotation", value: next.formatted(date: .abbreviated, time: .omitted))
                }
                Toggle("Weekly rotation reminder", isOn: Binding(
                    get: { reminderEnabled },
                    set: { enabled in
                        setReminderEnabled(enabled)
                    }
                ))
                .disabled(visibleExposures.isEmpty || status == .suspectedReaction || status == .avoidPendingAdvice)
                if visibleExposures.isEmpty {
                    Text("Log at least one exposure before turning on a weekly rotation reminder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if status == .suspectedReaction || status == .avoidPendingAdvice {
                    Text("Rotation reminders are paused while this allergen is marked for follow-up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SolidsAllergenNotesEditor(
                    profileID: profile.id,
                    allergenID: allergen.rawValue,
                    initialNotes: progress?.notes ?? ""
                )
                .id("\(profile.id.uuidString)-\(allergen.rawValue)")
            }
            if !visibleRecipes.isEmpty {
                Section("Meal ideas") {
                    ForEach(visibleRecipes.prefix(5)) { recipe in
                        Button { openRecipe(recipe.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title).font(.subheadline.weight(.semibold))
                                    Text(recipe.foodNames.joined(separator: " • "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("solids.allergen.recipe.\(recipe.id)")
                    }
                    Button { Task { await buildAllergenPlan() } } label: {
                        Label(
                            isBuildingPlan
                                ? "Building plan…"
                                : (progress?.introductionStep ?? 0) < 3
                                ? "Plan remaining introduction steps"
                                : "Plan the next rotation meal",
                            systemImage: "calendar.badge.plus"
                        )
                    }
                    .disabled(!canPlanVisibleExposure || isBuildingPlan)
                    if let plannedConfirmation {
                        Text(plannedConfirmation).font(.caption).foregroundStyle(.green)
                    }
                    if !canPlanVisibleExposure {
                        Text("Planning is paused while this allergen is marked as a possible reaction or avoid pending advice.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !visibleExposures.isEmpty {
                Section("Exposure history") {
                    ForEach(visibleExposures) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.foodNameSnapshot).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if item.suspectedReaction {
                                Label(
                                    item.symptoms.isEmpty
                                        ? "Possible reaction"
                                        : item.symptoms.map(\.displayName).joined(separator: ", "),
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                    .font(.caption).foregroundStyle(.red)
                            }
                            if let amount = solidTrackedAmountDescription(item) {
                                Text("Amount: \(amount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if !item.servingAmount.isEmpty {
                                Text("Amount: \(item.servingAmount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if !item.notes.isEmpty {
                                Text(item.notes).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Sources") {
                ForEach(visibleGuidance.sourceURLs, id: \.absoluteString) { url in
                    Link(destination: url) {
                        Label(
                            SolidsSourceLibrary.displayName(for: url),
                            systemImage: "arrow.up.right.square"
                        )
                    }
                }
            }
        }
        .navigationTitle(allergen.displayName)
        .alert("Notifications unavailable", isPresented: Binding(
            get: { reminderPermissionMessage != nil },
            set: { if !$0 { reminderPermissionMessage = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                reminderPermissionMessage = nil
            }
            Button("Not now", role: .cancel) { reminderPermissionMessage = nil }
        } message: {
            Text(reminderPermissionMessage ?? "")
        }
        .appActionSheet(
            isPresented: $showingStatusOptions,
            title: "\(allergen.displayName) status",
            message: "Choosing a status overrides automatic progress until you select Use automatic progress.",
            systemImage: "allergens",
            tint: .orange,
            options: SolidAllergenStatus.allCases.map { value in
                AppActionSheetOption(
                    title: value.displayName,
                    systemImage: allergenStatusSystemImage(value),
                    tint: allergenStatusTint(value),
                    isSelected: status == value
                ) {
                    status = value
                    hasManualStatusOverride = true
                    saveStatus(value)
                }
            }
        )
        .task {
            _ = await resolvedWriter()
            _ = await resolvedPlanWriter()
        }
        .onChange(of: progress?.reminderEnabled == true) { _, value in
            reminderEnabled = value
        }
    }

    private func saveStatus(_ value: SolidAllergenStatus) {
        statusRevision += 1
        let revision = statusRevision
        Task {
            let progressWriter = await resolvedWriter()
            if let error = await progressWriter.setStatus(
                value,
                allergenID: allergen.rawValue,
                profileID: profile.id,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func allergenStatusSystemImage(_ value: SolidAllergenStatus) -> String {
        switch value {
        case .notStarted: "circle"
        case .introducing: "clock.badge.checkmark"
        case .tolerated: "checkmark.circle.fill"
        case .suspectedReaction: "exclamationmark.triangle.fill"
        case .avoidPendingAdvice: "hand.raised.fill"
        }
    }

    private func allergenStatusTint(_ value: SolidAllergenStatus) -> Color {
        switch value {
        case .notStarted: .secondary
        case .introducing: .orange
        case .tolerated: .green
        case .suspectedReaction, .avoidPendingAdvice: .red
        }
    }

    private func clearStatusOverride(using exposures: [SolidFoodEventItem]) {
        hasManualStatusOverride = false
        status = automaticStatus(using: exposures)
        statusRevision += 1
        let revision = statusRevision
        Task {
            let progressWriter = await resolvedWriter()
            if let error = await progressWriter.clearStatusOverride(
                allergenID: allergen.rawValue,
                profileID: profile.id,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func automaticStatus(using exposures: [SolidFoodEventItem]) -> SolidAllergenStatus {
        if exposures.contains(where: { $0.followUp == .avoidPendingAdvice }) {
            return .avoidPendingAdvice
        }
        if exposures.contains(where: \.suspectedReaction) {
            return .suspectedReaction
        }
        let confirmedEventIDs = Set(exposures.filter {
            $0.confirmsIntroductionPortion(for: allergen.rawValue)
        }.map(\.eventID))
        if confirmedEventIDs.count >= 3 { return .tolerated }
        return exposures.isEmpty ? .notStarted : .introducing
    }

    private func setReminderEnabled(_ enabled: Bool) {
        guard enabled else {
            reminderEnabled = false
            persistReminder(false)
            return
        }
        reminderEnabled = true
        Task {
            guard await NotificationManager.shared.ensureAuthorization() else {
                reminderEnabled = false
                reminderPermissionMessage = "Allow notifications in Settings to turn on allergen rotation reminders."
                return
            }
            persistReminder(true)
        }
    }

    private func persistReminder(_ enabled: Bool) {
        reminderRevision += 1
        let revision = reminderRevision
        Task {
            let progressWriter = await resolvedWriter()
            if let error = await progressWriter.setReminder(
                enabled,
                allergenID: allergen.rawValue,
                profileID: profile.id,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    @MainActor
    private func resolvedWriter() async -> SolidsAllergenProgressWriter {
        if let writer { return writer }
        let value = await SolidsWriterPool.shared.allergenProgressWriter(for: modelContext.container)
        writer = value
        return value
    }

    private func buildAllergenPlan() async {
        guard canPlanExposure else { return }
        let currentStep = min(3, max(0, progress?.introductionStep ?? 0))
        let existing = plans.filter {
            $0.profileID == profile.id
                && !$0.isCompleted
                && $0.allergenID == allergen.rawValue
        }
        let alreadyPlanned: Bool
        if currentStep < 3 {
            let plannedSteps = Set(existing.compactMap(\.allergenIntroductionStep))
            alreadyPlanned = ((currentStep + 1)...3).allSatisfy(plannedSteps.contains)
        } else {
            alreadyPlanned = existing.contains { $0.allergenIntroductionStep == nil }
        }
        let writes = SolidsTrackingService.allergenPlanWrites(
            for: allergen,
            profile: profile,
            progress: progress,
            allProgress: allProgress,
            existingPlans: plans
        )
        guard !writes.isEmpty else {
            plannedConfirmation = alreadyPlanned
                ? "The next exposure is already planned."
                : "The exposure plan could not be saved. Please try again."
            return
        }
        isBuildingPlan = true
        defer { isBuildingPlan = false }
        let writer = await resolvedPlanWriter()
        let result = await writer.createPlans(writes)
        if let error = result.error {
            plannedConfirmation = "The exposure plan could not be saved. Please try again."
            PersistenceService.recordLocalSaveFailure(error)
        } else {
            plannedConfirmation = "Added \(result.count) editable meal\(result.count == 1 ? "" : "s") to the planner."
        }
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let value = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = value
        return value
    }
}

private struct SolidsAllergenNotesEditor: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    let profileID: UUID
    let allergenID: String
    let initialNotes: String

    @State private var draft: String
    @State private var lastSavedDraft: String
    @State private var writer: SolidsAllergenProgressWriter?
    @State private var writeRevision = 0
    @FocusState private var isFocused: Bool

    init(profileID: UUID, allergenID: String, initialNotes: String) {
        self.profileID = profileID
        self.allergenID = allergenID
        self.initialNotes = initialNotes
        _draft = State(initialValue: initialNotes)
        _lastSavedDraft = State(initialValue: initialNotes)
    }

    var body: some View {
        TextField("Notes", text: $draft, axis: .vertical)
            .focused($isFocused)
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused && !focused { saveIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { saveIfNeeded() }
            }
            .onChange(of: initialNotes) { oldValue, newValue in
                guard !isFocused, draft == lastSavedDraft, oldValue != newValue else { return }
                draft = newValue
                lastSavedDraft = newValue
            }
            .onDisappear { saveIfNeeded() }
            .task {
                _ = await resolvedWriter()
            }
    }

    private func saveIfNeeded() {
        guard draft != lastSavedDraft else { return }
        writeRevision += 1
        let revision = writeRevision
        let currentNotes = draft
        Task {
            let progressWriter = await resolvedWriter()
            if let error = await progressWriter.setNotes(
                currentNotes,
                allergenID: allergenID,
                profileID: profileID,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
        lastSavedDraft = draft
    }

    @MainActor
    private func resolvedWriter() async -> SolidsAllergenProgressWriter {
        if let writer { return writer }
        let value = await SolidsWriterPool.shared.allergenProgressWriter(for: modelContext.container)
        writer = value
        return value
    }
}

struct SolidsRecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomSolidRecipe.updatedAt, order: .reverse) private var customRecipes: [CustomSolidRecipe]
    let profile: CareProfile
    let profileState: SolidsProfileState?
    let openRecipe: (String) -> Void

    @State private var effectiveSearchText = ""
    @State private var mealType: SolidsMealType?
    @State private var dietaryTag: SolidsDietaryTag?
    @State private var savedOnly = false
    @State private var selectedCollectionID: UUID?
    @State private var showLaterStages = false
    @State private var showingCollectionActions = false
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var collectionToRename: SolidRecipeCollection?
    @State private var pendingNewCollectionPresentation = false
    @State private var pendingCollectionToRename: SolidRecipeCollection?
    @State private var renamedCollectionName = ""
    @State private var displayedCollections: [SolidRecipeCollection]?
    @State private var recipeWriter: SolidsRecipePreferenceWriter?
    @State private var pendingCollectionMutations = 0
    @State private var collectionMutationError: String?
    @State private var showingCustomRecipeEditor = false

    private var ageMonths: Int {
        SolidsTrackingService.ageMonths(for: profile)
    }

    private var visibleStageAgeMonths: Int {
        max(ageMonths, 6)
    }

    private var isPlanningAhead: Bool {
        ageMonths < 6
    }

    private var visibleCustomRecipes: [CustomSolidRecipeViewSnapshot] {
        // Keep rows and navigation destinations independent from live SwiftData
        // objects while a background writer inserts, updates, or deletes one.
        let snapshots = customRecipes.map(CustomSolidRecipeViewSnapshot.init)
        let query = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snapshots }
        return snapshots.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(query)
                || recipe.instructions.localizedCaseInsensitiveContains(query)
                || recipe.notes.localizedCaseInsensitiveContains(query)
                || recipe.ingredients.contains { $0.foodName.localizedCaseInsensitiveContains(query) }
        }
    }

    private func recipes(
        favoriteRecipeIDs: Set<String>,
        wantToTryRecipeIDs: Set<String>,
        collections: [SolidRecipeCollection]
    ) -> [SolidsReferenceRecipe] {
        let query = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedRecipeIDs = favoriteRecipeIDs.union(wantToTryRecipeIDs)
        let selectedCollectionRecipeIDs = collections
            .first(where: { $0.id == selectedCollectionID })
            .map { Set($0.recipeIDs) }
        return SolidsReferenceCatalog.searchRecipes(query).filter { recipe in
            (mealType == nil || recipe.mealType == mealType)
                && (dietaryTag.map { recipe.dietaryTags.contains($0) } ?? true)
                && (!savedOnly || savedRecipeIDs.contains(recipe.id))
                && (selectedCollectionID == nil || selectedCollectionRecipeIDs?.contains(recipe.id) == true)
                && (showLaterStages || recipe.minimumAgeMonths <= visibleStageAgeMonths)
        }
    }

    var body: some View {
        // Decode the profile's JSON-backed recipe state once per render. Doing
        // this from every visible row made scrolling and search cost grow with
        // the number of recipes on screen.
        let favoriteRecipeIDs = Set(profileState?.favoriteRecipeIDs ?? [])
        let wantToTryRecipeIDs = Set(profileState?.wantToTryRecipeIDs ?? [])
        let collections = displayedCollections ?? profileState?.recipeCollections ?? []
        let selectedCollection = collections.first { $0.id == selectedCollectionID }
        let visibleRecipes = recipes(
            favoriteRecipeIDs: favoriteRecipeIDs,
            wantToTryRecipeIDs: wantToTryRecipeIDs,
            collections: collections
        )
        List {
            Section("Your recipes") {
                Button {
                    showingCustomRecipeEditor = true
                } label: {
                    Label("Build a recipe", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("solids.recipes.create-custom")

                ForEach(visibleCustomRecipes) { recipe in
                    NavigationLink {
                        CustomSolidRecipeDetailView(recipe: recipe, profile: profile)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name).font(.body.weight(.medium))
                            Text("\(recipe.ingredients.count) ingredient\(recipe.ingredients.count == 1 ? "" : "s") • \(recipe.servings.formatted(.number.precision(.fractionLength(0...1)))) serving\(recipe.servings == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("solids.custom-recipe.row.\(recipe.trackingID)")
                }
                if !effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   visibleCustomRecipes.isEmpty {
                    Text("No custom recipes match this search.")
                        .foregroundStyle(.secondary)
                }
            }
            if !collections.isEmpty {
                Section("Your recipe lists") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(collections) { collection in
                                collectionFilterButton(
                                    collection,
                                    selected: selectedCollectionID == collection.id
                                ) {
                                    selectedCollectionID = selectedCollectionID == collection.id
                                        ? nil
                                        : collection.id
                                }
                            }
                        }
                    }
                }
            }
            Section("Browse recipes") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        filterButton(
                            "All meals",
                            selected: mealType == nil && dietaryTag == nil && !savedOnly
                                && selectedCollectionID == nil && !showLaterStages
                        ) {
                            mealType = nil; dietaryTag = nil; savedOnly = false
                            selectedCollectionID = nil; showLaterStages = false
                        }
                        ForEach(SolidsMealType.allCases) { value in
                            filterButton(value.displayName, selected: mealType == value) { mealType = value }
                        }
                        ForEach(SolidsDietaryTag.allCases) { value in
                            filterButton(value.displayName, selected: dietaryTag == value) { dietaryTag = value }
                        }
                        filterButton("Saved", selected: savedOnly) { savedOnly.toggle() }
                        filterButton("Later stages", selected: showLaterStages) { showLaterStages.toggle() }
                    }
                }
            }
            if let selectedCollection {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedCollection.name)
                                .font(.headline)
                            Text("Showing \(visibleRecipes.count) \(visibleRecipes.count == 1 ? "meal" : "meals") in this recipe list")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("solids.recipes.active-list")
                }
            }
            if isPlanningAhead && !showLaterStages {
                Section {
                    Label {
                        Text("Planning ahead: showing recipes for around 6 months. Use them when \(profile.name) is ready to start solids.")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("solids.recipes.planning-ahead")
                }
            }
            if visibleRecipes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Matching Recipes",
                        systemImage: "fork.knife.circle",
                        description: Text(selectedCollection.map {
                            "No meals in \($0.name) match the other active filters."
                        } ?? "Try clearing the search or recipe filters.")
                    )
                    Button("Clear recipe filters", systemImage: "line.3.horizontal.decrease.circle") {
                        clearFilters()
                    }
                }
            } else {
                Section("\(visibleRecipes.count) meal ideas") {
                    ForEach(visibleRecipes) { recipe in
                        Button { openRecipe(recipe.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text("\(recipe.minimumAgeMonths)+ months • \(recipe.mealType.displayName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if favoriteRecipeIDs.contains(recipe.id) {
                                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                                } else if wantToTryRecipeIDs.contains(recipe.id) {
                                    Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                                }
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("solids.recipes.recipe.\(recipe.id)")
                    }
                }
            }
        }
        .navigationTitle("Solids Recipes")
        .debouncedSearch(text: $effectiveSearchText, prompt: "Search meals or ingredients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCollectionActions = true
                } label: {
                    Label("Manage recipe lists", systemImage: "folder.badge.plus")
                }
            }
        }
        .appActionSheet(
            isPresented: $showingCollectionActions,
            title: "Recipe lists",
            message: collections.isEmpty
                ? "Create a list to group meals you want to make together."
                : "Choose one of your named recipe lists to rename or delete, or create a new one.",
            systemImage: "folder.fill",
            tint: .orange,
            options: collectionActionOptions(collections),
            onDismiss: presentPendingCollectionAction
        )
        .alert("New recipe list", isPresented: $showingNewCollection) {
            TextField("List name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                createCollection()
            }
        } message: {
            Text("Create a named list for meals you want to group together.")
        }
        .alert(
            collectionToRename.map { "Rename “\($0.name)”" } ?? "Rename recipe list",
            isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            )
        ) {
            TextField("List name", text: $renamedCollectionName)
            Button("Cancel", role: .cancel) { collectionToRename = nil }
            Button("Save") {
                if let collectionToRename {
                    renameCollection(collectionToRename)
                }
                collectionToRename = nil
            }
        }
        .alert("Couldn’t update recipe list", isPresented: Binding(
            get: { collectionMutationError != nil },
            set: { if !$0 { collectionMutationError = nil } }
        )) {
            Button("OK") { collectionMutationError = nil }
        } message: {
            Text(collectionMutationError ?? "")
        }
        .sheet(isPresented: $showingCustomRecipeEditor) {
            NavigationStack {
                CustomSolidRecipeEditorView(recipe: nil)
            }
        }
        .task {
            if displayedCollections == nil {
                displayedCollections = profileState?.recipeCollections ?? []
            }
            _ = await resolvedRecipeWriter()
        }
        .onChange(of: profileState?.recipeCollectionsJSON ?? "[]") { _, _ in
            guard pendingCollectionMutations == 0 else { return }
            displayedCollections = profileState?.recipeCollections ?? []
        }
    }

    private func filterButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(selected ? .orange : .secondary)
    }

    private func collectionFilterButton(
        _ collection: SolidRecipeCollection,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(
                collection.name,
                systemImage: selected ? "folder.fill" : "folder"
            )
        }
        .font(.callout.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(selected ? .orange : .secondary)
        .accessibilityLabel("Recipe list: \(collection.name)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("solids.recipes.collection.\(collection.id.uuidString)")
    }

    private func clearFilters() {
        effectiveSearchText = ""
        mealType = nil
        dietaryTag = nil
        savedOnly = false
        selectedCollectionID = nil
        showLaterStages = false
    }

    private func collectionActionOptions(
        _ collections: [SolidRecipeCollection]
    ) -> [AppActionSheetOption] {
        var options = [
            AppActionSheetOption(
                title: "New recipe list",
                subtitle: "Create a named collection for saved meals.",
                systemImage: "folder.badge.plus",
                tint: .orange
            ) {
                pendingNewCollectionPresentation = true
            }
        ]
        for collection in collections {
            options.append(AppActionSheetOption(
                title: "Rename \(collection.name)",
                subtitle: "Recipe list • \(collection.recipeIDs.count) \(collection.recipeIDs.count == 1 ? "meal" : "meals")",
                systemImage: "pencil",
                tint: .orange
            ) {
                pendingCollectionToRename = collection
            })
            options.append(AppActionSheetOption(
                title: "Delete \(collection.name)",
                subtitle: "The recipes remain available outside this list.",
                systemImage: "trash",
                tint: .red,
                role: .destructive
            ) {
                if selectedCollectionID == collection.id { selectedCollectionID = nil }
                deleteCollection(collection)
            })
        }
        return options
    }

    private func presentPendingCollectionAction() {
        if pendingNewCollectionPresentation {
            pendingNewCollectionPresentation = false
            newCollectionName = ""
            showingNewCollection = true
        } else if let pendingCollectionToRename {
            self.pendingCollectionToRename = nil
            renamedCollectionName = pendingCollectionToRename.name
            collectionToRename = pendingCollectionToRename
        }
    }

    private func createCollection() {
        let cleanedName = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            collectionMutationError = "Enter a list name."
            return
        }
        var collections = displayedCollections ?? profileState?.recipeCollections ?? []
        guard !collections.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame
        }) else {
            collectionMutationError = "A recipe list with that name already exists."
            return
        }
        let collection = SolidRecipeCollection(name: cleanedName)
        collections.append(collection)
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        displayedCollections = collections
        pendingCollectionMutations += 1
        Task {
            let writer = await resolvedRecipeWriter()
            let error = await writer.createCollection(
                id: collection.id,
                name: collection.name,
                profileID: profile.id,
                now: collection.createdAt
            )
            pendingCollectionMutations -= 1
            if let error {
                displayedCollections?.removeAll { $0.id == collection.id }
                collectionMutationError = error
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func renameCollection(_ collection: SolidRecipeCollection) {
        let cleanedName = renamedCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            collectionMutationError = "Enter a list name."
            return
        }
        var collections = displayedCollections ?? profileState?.recipeCollections ?? []
        guard !collections.contains(where: {
            $0.id != collection.id
                && $0.name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame
        }), let index = collections.firstIndex(where: { $0.id == collection.id }) else {
            collectionMutationError = "That recipe list name is already in use."
            return
        }
        let original = collections[index]
        collections[index].name = cleanedName
        collections[index].updatedAt = Date()
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        displayedCollections = collections
        pendingCollectionMutations += 1
        Task {
            let writer = await resolvedRecipeWriter()
            let error = await writer.renameCollection(
                id: collection.id,
                name: cleanedName,
                profileID: profile.id
            )
            pendingCollectionMutations -= 1
            if let error {
                displayedCollections?.removeAll { $0.id == original.id }
                displayedCollections?.append(original)
                displayedCollections?.sort {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                collectionMutationError = error
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func deleteCollection(_ collection: SolidRecipeCollection) {
        var collections = displayedCollections ?? profileState?.recipeCollections ?? []
        collections.removeAll { $0.id == collection.id }
        displayedCollections = collections
        pendingCollectionMutations += 1
        Task {
            let writer = await resolvedRecipeWriter()
            let error = await writer.deleteCollection(id: collection.id, profileID: profile.id)
            pendingCollectionMutations -= 1
            if let error {
                displayedCollections?.append(collection)
                displayedCollections?.sort {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                collectionMutationError = error
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    @MainActor
    private func resolvedRecipeWriter() async -> SolidsRecipePreferenceWriter {
        if let recipeWriter { return recipeWriter }
        let writer = await SolidsWriterPool.shared.recipePreferenceWriter(for: modelContext.container)
        recipeWriter = writer
        return writer
    }
}

struct SolidsRecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let recipe: SolidsReferenceRecipe
    let profile: CareProfile
    let profileState: SolidsProfileState?
    let plannedMeals: [PlannedSolidMeal]
    let household: Household?
    let shoppingLists: [ShoppingList]
    let shoppingItems: [ShoppingListItem]
    let inventoryItems: [InventoryItem]
    let foodItems: [FoodItem]
    let locations: [InventoryLocation]
    let openPlan: (UUID) -> Void
    let openFood: (String) -> Void

    @State private var selectedFoodNames: [String]
    @State private var selectedIngredientIndex: Int?
    @State private var showingShoppingLists = false
    @State private var showingMealPrepLocations = false
    @State private var planResultMessage: String?
    @State private var isPlanningForTomorrow = false
    @State private var locallyPlannedTomorrowID: UUID?
    @State private var planWriter: SolidsPlanWriter?
    @State private var shoppingResultMessage: String?
    @State private var shoppingWriter: SolidsShoppingListWriter?
    @State private var mealPrepResultMessage: String?
    @State private var mealPrepWriter: SolidsMealPrepWriter?
    init(
        recipe: SolidsReferenceRecipe,
        profile: CareProfile,
        profileState: SolidsProfileState?,
        plannedMeals: [PlannedSolidMeal],
        household: Household?,
        shoppingLists: [ShoppingList],
        shoppingItems: [ShoppingListItem],
        inventoryItems: [InventoryItem],
        foodItems: [FoodItem],
        locations: [InventoryLocation],
        openPlan: @escaping (UUID) -> Void,
        openFood: @escaping (String) -> Void
    ) {
        self.recipe = recipe
        self.profile = profile
        self.profileState = profileState
        self.plannedMeals = plannedMeals
        self.household = household
        self.shoppingLists = shoppingLists
        self.shoppingItems = shoppingItems
        self.inventoryItems = inventoryItems
        self.foodItems = foodItems
        self.locations = locations
        self.openPlan = openPlan
        self.openFood = openFood
        _selectedFoodNames = State(initialValue: recipe.foodNames)
    }

    private var selectedFoods: [SolidsReferenceFood] {
        selectedFoodNames.compactMap(SolidsReferenceCatalog.food(named:))
    }
    private var plannedTomorrowMeal: PlannedSolidMeal? {
        guard let interval = solidsTomorrowInterval() else { return nil }
        return plannedMeals.first {
            interval.contains($0.scheduledAt) && $0.recipeID == recipe.id
        }
    }
    private var isPlannedForTomorrow: Bool {
        locallyPlannedTomorrowID != nil || plannedTomorrowMeal != nil
    }

    var body: some View {
        let visibleSelectedFoods = selectedFoods
        let visibleMinimumRequiredAge = max(
            recipe.minimumAgeMonths,
            visibleSelectedFoods.map(\.minimumAgeMonths).max() ?? 6
        )
        let ageEligible = SolidsTrackingService.ageMonths(for: profile) >= visibleMinimumRequiredAge
        let visibleSelectedAllergenIDs = Array(
            Set(visibleSelectedFoods.flatMap(\.allergenIDs))
        ).sorted()
        List {
            if !ageEligible {
                Section {
                    Label(
                        "This meal is designed for \(visibleMinimumRequiredAge)+ months. Review the preparation guidance and use it when the child is ready.",
                        systemImage: "calendar.badge.clock"
                    )
                    .foregroundStyle(.orange)
                }
            }
            Section("Ingredients") {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                    VStack(alignment: .leading, spacing: 5) {
                        if let food = SolidsReferenceCatalog.food(named: selectedFoodNames[index]) {
                            Button {
                                openFood(food.id)
                            } label: {
                                HStack {
                                    Label(selectedFoodNames[index], systemImage: "circle.fill")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(ingredient.quantity).font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("solids.recipe.ingredient.\(food.id)")
                        }
                        if !ingredient.substitutionNames.isEmpty {
                            Button {
                                selectedIngredientIndex = index
                            } label: {
                                Label("Swap ingredient", systemImage: "arrow.triangle.swap")
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("solids.recipe.swap.\(index)")
                        }
                    }
                }
            }
            Section("Prepare") {
                Text(recipe.instructions)
                Text("Review each ingredient's food page for age-specific shape, texture, allergen, and safety guidance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !visibleSelectedAllergenIDs.isEmpty {
                Section("Contains major allergens") {
                    ForEach(visibleSelectedAllergenIDs, id: \.self) { id in
                        Text(SolidsAllergen(rawValue: id)?.displayName ?? id)
                    }
                }
            }
            SolidsRecipePreferenceSections(
                recipeID: recipe.id,
                profileID: profile.id,
                profileState: profileState
            )
            Section {
                Button {
                    let router = DeepLinkRouter.shared
                    router.openToday(
                        action: .logSolidFeed(
                            SolidFeedEditorPreset(
                                foodIDs: visibleSelectedFoods.map(\.id),
                                foodNames: visibleSelectedFoods.map(\.name),
                                allergenIDsByFoodID: Dictionary(
                                    uniqueKeysWithValues: visibleSelectedFoods.map {
                                        ($0.id, $0.allergenIDs)
                                    }
                                ),
                                recipeID: recipe.id
                            )
                        ),
                        profileID: profile.id
                    )
                } label: {
                    Label("Adjust and log this meal", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("solids.recipe.log")
                if let plannedTomorrowMeal {
                    Button {
                        locallyPlannedTomorrowID = nil
                        openPlan(plannedTomorrowMeal.id)
                    } label: {
                        HStack {
                            Label("Planned for tomorrow", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.green)
                    .accessibilityHint("Opens the planned meal.")
                    .accessibilityIdentifier("solids.recipe.planned-tomorrow")
                } else if isPlannedForTomorrow {
                    Label("Planned for tomorrow", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("solids.recipe.planned-tomorrow")
                } else {
                    Button {
                        planRecipeForTomorrow(foods: visibleSelectedFoods)
                    } label: {
                        Label(
                            isPlanningForTomorrow ? "Adding to tomorrow…" : "Plan for tomorrow",
                            systemImage: isPlanningForTomorrow ? "hourglass" : "calendar.badge.plus"
                        )
                    }
                    .disabled(isPlanningForTomorrow)
                    .accessibilityIdentifier("solids.recipe.plan-tomorrow")
                }
            }
            if !shoppingLists.isEmpty || (household != nil && !locations.isEmpty) {
                Section("Food & Home") {
                    if !shoppingLists.isEmpty {
                        Button {
                            showingShoppingLists = true
                        } label: {
                            Label("Add missing ingredients", systemImage: "cart.badge.plus")
                        }
                        .accessibilityIdentifier("solids.recipe.add-missing-ingredients")
                    }
                    if household != nil, !locations.isEmpty {
                        Button {
                            showingMealPrepLocations = true
                        } label: {
                            Label("Save as meal prep", systemImage: "takeoutbag.and.cup.and.straw")
                        }
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .appActionSheet(
            isPresented: Binding(
                get: { selectedIngredientIndex != nil },
                set: { if !$0 { selectedIngredientIndex = nil } }
            ),
            title: swapDrawerTitle,
            message: "Choose the ingredient to use in this meal. The plan, log, and shopping actions below will use your selection.",
            systemImage: "arrow.triangle.swap",
            tint: .orange,
            options: swapIngredientOptions
        )
        .appActionSheet(
            isPresented: $showingShoppingLists,
            title: "Add missing ingredients",
            message: "Choose a shopping list. Ingredients already in inventory or on that list will be skipped.",
            systemImage: "cart.badge.plus",
            tint: .orange,
            options: shoppingLists.map { list in
                let activeCount = shoppingItems.lazy.filter {
                    $0.shoppingListID == list.id && !$0.isChecked
                }.count
                return AppActionSheetOption(
                    title: list.name,
                    subtitle: "\(activeCount) active item\(activeCount == 1 ? "" : "s")",
                    systemImage: "list.bullet.rectangle",
                    tint: .orange
                ) {
                    addMissingIngredients(to: list)
                }
            }
        )
        .appActionSheet(
            isPresented: $showingMealPrepLocations,
            title: "Save as meal prep",
            message: "Choose where this prepared meal will be stored.",
            systemImage: "takeoutbag.and.cup.and.straw",
            tint: .orange,
            options: locations.map { location in
                AppActionSheetOption(
                    title: location.name,
                    subtitle: location.locationType.displayName,
                    systemImage: location.locationType.systemImage,
                    tint: .orange
                ) {
                    saveAsMealPrep(to: location)
                }
            }
        )
        .alert("Meal plan", isPresented: Binding(
            get: { planResultMessage != nil },
            set: { if !$0 { planResultMessage = nil } }
        )) {
            Button("OK") { planResultMessage = nil }
        } message: {
            Text(planResultMessage ?? "")
        }
        .alert("Shopping list", isPresented: Binding(
            get: { shoppingResultMessage != nil },
            set: { if !$0 { shoppingResultMessage = nil } }
        )) {
            Button("OK") { shoppingResultMessage = nil }
        } message: {
            Text(shoppingResultMessage ?? "")
        }
        .alert("Meal prep", isPresented: Binding(
            get: { mealPrepResultMessage != nil },
            set: { if !$0 { mealPrepResultMessage = nil } }
        )) {
            Button("OK") { mealPrepResultMessage = nil }
        } message: {
            Text(mealPrepResultMessage ?? "")
        }
        .onChange(of: plannedTomorrowMeal?.id) { _, planID in
            if planID != nil {
                locallyPlannedTomorrowID = nil
            }
        }
        .onAppear {
            if locallyPlannedTomorrowID != nil, plannedTomorrowMeal == nil {
                locallyPlannedTomorrowID = nil
            }
        }
        .task {
            _ = await resolvedPlanWriter()
            _ = await resolvedShoppingWriter()
            _ = await resolvedMealPrepWriter()
        }
    }

    private func planRecipeForTomorrow(foods: [SolidsReferenceFood]) {
        guard !isPlanningForTomorrow, !isPlannedForTomorrow else { return }
        isPlanningForTomorrow = true
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        Task {
            let writer = await resolvedPlanWriter()
            let result = await writer.saveEditorPlan(SolidsPlanEditorWrite(
                planID: nil,
                profileID: profile.id,
                scheduledAt: Calendar.current.date(
                    bySettingHour: 12,
                    minute: 0,
                    second: 0,
                    of: tomorrow
                ) ?? tomorrow,
                foodIDs: foods.map(\.id),
                foodNames: foods.map(\.name),
                notes: recipe.title,
                reminderEnabled: false,
                reminderOffsetMinutes: 30,
                title: recipe.title,
                recipeID: recipe.id,
                duplicatePolicy: .matchingRecipeOnDay
            ))
            isPlanningForTomorrow = false
            if let error = result.error {
                planResultMessage = "The meal plan could not be saved."
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                locallyPlannedTomorrowID = result.planID.flatMap { planID in
                    plannedMeals.contains { $0.id == planID } ? nil : planID
                }
                planResultMessage = result.wasAlreadyPresent
                    ? "This meal was already on tomorrow's plan."
                    : "Added to tomorrow's meal plan."
            }
        }
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let writer = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = writer
        return writer
    }

    private func addMissingIngredients(to list: ShoppingList) {
        let writes = SolidsTrackingService.shoppingWrites(
            foods: selectedFoods,
            inventoryItems: inventoryItems,
            foodItems: foodItems,
            skipAvailableInventory: true
        )
        guard !writes.isEmpty else {
            shoppingResultMessage = "All ingredients are already available in inventory."
            return
        }
        Task {
            let writer = await resolvedShoppingWriter()
            let result = await writer.addFoods(
                writes,
                listID: list.id,
                householdID: list.householdID
            )
            if let error = result.error {
                shoppingResultMessage = "The ingredients could not be added. Please try again."
                PersistenceService.recordLocalSaveFailure(error)
            } else if result.count == 0 {
                shoppingResultMessage = "The missing ingredients are already on \(list.name)."
            } else {
                shoppingResultMessage = "Added \(result.count) ingredient\(result.count == 1 ? "" : "s") to \(list.name)."
            }
        }
    }

    @MainActor
    private func resolvedShoppingWriter() async -> SolidsShoppingListWriter {
        if let shoppingWriter { return shoppingWriter }
        let writer = await SolidsWriterPool.shared.shoppingListWriter(for: modelContext.container)
        shoppingWriter = writer
        return writer
    }

    @MainActor
    private func resolvedMealPrepWriter() async -> SolidsMealPrepWriter {
        if let mealPrepWriter { return mealPrepWriter }
        let writer = await SolidsWriterPool.shared.mealPrepWriter(for: modelContext.container)
        mealPrepWriter = writer
        return writer
    }

    private var swapDrawerTitle: String {
        guard let index = selectedIngredientIndex,
              recipe.ingredients.indices.contains(index) else {
            return "Swap ingredient"
        }
        return "Swap \(recipe.ingredients[index].foodName)"
    }

    private var swapIngredientOptions: [AppActionSheetOption] {
        guard let index = selectedIngredientIndex,
              recipe.ingredients.indices.contains(index),
              selectedFoodNames.indices.contains(index) else { return [] }
        let ingredient = recipe.ingredients[index]
        return ([ingredient.foodName] + ingredient.substitutionNames).map { name in
            AppActionSheetOption(
                title: name,
                subtitle: name == ingredient.foodName ? "Original ingredient" : "Suggested substitute",
                systemImage: name == ingredient.foodName ? "fork.knife" : "arrow.triangle.swap",
                tint: .orange,
                isSelected: selectedFoodNames[index] == name
            ) {
                selectedFoodNames[index] = name
            }
        }
    }

    private func saveAsMealPrep(to location: InventoryLocation) {
        guard let household else { return }
        let write = SolidsMealPrepWrite(
            name: recipe.title,
            servings: Double(recipe.servings),
            locationID: location.id,
            householdID: household.id,
            preparedDate: Date(),
            notes: selectedFoodNames.joined(separator: ", "),
            tags: "solids,\(recipe.mealType.rawValue)"
        )
        Task {
            let writer = await resolvedMealPrepWriter()
            if let error = await writer.create(write) {
                mealPrepResultMessage = "The meal prep item could not be saved."
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                mealPrepResultMessage = "Saved \(recipe.title) to meal prep."
            }
        }
    }
}

private struct SolidsRecipePreferenceSections: View {
    @Environment(\.modelContext) private var modelContext

    let recipeID: String
    let profileID: UUID
    let profileState: SolidsProfileState?

    @State private var isFavorite: Bool
    @State private var wantsToTry: Bool
    @State private var collections: [SolidRecipeCollection]
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var writer: SolidsRecipePreferenceWriter?
    @State private var favoriteRevision = 0
    @State private var wantRevision = 0
    @State private var collectionRevisions: [UUID: Int] = [:]
    @State private var collectionMutationError: String?

    init(recipeID: String, profileID: UUID, profileState: SolidsProfileState?) {
        self.recipeID = recipeID
        self.profileID = profileID
        self.profileState = profileState
        _isFavorite = State(initialValue: profileState?.favoriteRecipeIDs.contains(recipeID) == true)
        _wantsToTry = State(initialValue: profileState?.wantToTryRecipeIDs.contains(recipeID) == true)
        _collections = State(initialValue: profileState?.recipeCollections ?? [])
    }

    var body: some View {
        Group {
            saveSection
            recipeListsSection
        }
        .task {
            _ = await resolvedWriter()
        }
        .alert("New recipe list", isPresented: $showingNewCollection) {
            TextField("List name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create and add", action: createCollection)
        }
        .alert("Couldn’t create recipe list", isPresented: Binding(
            get: { collectionMutationError != nil },
            set: { if !$0 { collectionMutationError = nil } }
        )) {
            Button("OK") { collectionMutationError = nil }
        } message: {
            Text(collectionMutationError ?? "")
        }
    }

    private var saveSection: some View {
        Section("Save") {
            Button(action: toggleFavorite) {
                Label(isFavorite ? "Remove favorite" : "Favorite", systemImage: "heart")
            }
            .accessibilityIdentifier("solids.recipe.favorite")

            Button(action: toggleWantToTry) {
                Label(wantsToTry ? "Remove from want to try" : "Want to try", systemImage: "bookmark")
            }
            .accessibilityIdentifier("solids.recipe.want-to-try")
        }
    }

    private var recipeListsSection: some View {
        Section("Recipe lists") {
            if collections.isEmpty {
                Text("Create named lists for breakfasts, daycare meals, family favorites, or anything else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(collections) { collection in
                let isIncluded = collection.recipeIDs.contains(recipeID)
                Button {
                    toggleMembership(collection)
                } label: {
                    HStack {
                        Text(collection.name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isIncluded ? .orange : .secondary)
                    }
                }
                .accessibilityIdentifier("solids.recipe.collection.\(collection.id.uuidString)")
            }
            Button("New recipe list", systemImage: "folder.badge.plus") {
                newCollectionName = ""
                showingNewCollection = true
            }
        }
    }

    private func toggleFavorite() {
        isFavorite.toggle()
        favoriteRevision += 1
        let value = isFavorite
        let revision = favoriteRevision
        Task {
            let preferenceWriter = await resolvedWriter()
            if let error = await preferenceWriter.setFavorite(
                value,
                recipeID: recipeID,
                profileID: profileID,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func toggleWantToTry() {
        wantsToTry.toggle()
        wantRevision += 1
        let value = wantsToTry
        let revision = wantRevision
        Task {
            let preferenceWriter = await resolvedWriter()
            if let error = await preferenceWriter.setWantToTry(
                value,
                recipeID: recipeID,
                profileID: profileID,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func toggleMembership(_ collection: SolidRecipeCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        var recipeIDs = Set(collections[index].recipeIDs)
        if !recipeIDs.insert(recipeID).inserted { recipeIDs.remove(recipeID) }
        collections[index].recipeIDs = recipeIDs.sorted()
        let included = recipeIDs.contains(recipeID)
        let revision = (collectionRevisions[collection.id] ?? 0) + 1
        collectionRevisions[collection.id] = revision
        Task {
            let preferenceWriter = await resolvedWriter()
            if let error = await preferenceWriter.setMembership(
                included,
                recipeID: recipeID,
                collectionID: collection.id,
                profileID: profileID,
                revision: revision
            ) {
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    private func createCollection() {
        let cleanedName = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            collectionMutationError = "Enter a list name."
            return
        }
        guard !collections.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame
        }) else {
            collectionMutationError = "A recipe list with that name already exists."
            return
        }
        let collection = SolidRecipeCollection(name: cleanedName, recipeIDs: [recipeID])
        collections.append(collection)
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        Task {
            let preferenceWriter = await resolvedWriter()
            if let error = await preferenceWriter.createCollection(
                id: collection.id,
                name: collection.name,
                initialRecipeIDs: [recipeID],
                profileID: profileID,
                now: collection.createdAt
            ) {
                collections.removeAll { $0.id == collection.id }
                collectionMutationError = error
                PersistenceService.recordLocalSaveFailure(error)
            }
        }
    }

    @MainActor
    private func resolvedWriter() async -> SolidsRecipePreferenceWriter {
        if let writer { return writer }
        let value = await SolidsWriterPool.shared.recipePreferenceWriter(for: modelContext.container)
        writer = value
        return value
    }
}

/// Keeps recipe navigation and editing independent from a live SwiftData model.
/// A background save or delete can then merge into the recipes query without
/// invalidating the detail/editor view during its dismissal transition.
struct CustomSolidRecipeViewSnapshot: Identifiable, Hashable {
    var id: UUID
    var name: String
    var ingredients: [CustomSolidRecipeIngredient]
    var servings: Double
    var minimumAgeMonths: Int
    var instructions: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(_ recipe: CustomSolidRecipe) {
        id = recipe.id
        name = recipe.name
        ingredients = recipe.ingredients
        servings = recipe.servings
        minimumAgeMonths = recipe.minimumAgeMonths
        instructions = recipe.instructions
        notes = recipe.notes
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }

    var trackingID: String { "custom-recipe-\(id.uuidString.lowercased())" }
}

private struct CustomRecipeFoodChoice: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var hasNutrition: Bool
}

struct CustomSolidRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SolidFoodCatalogItem.name) private var customFoods: [SolidFoodCatalogItem]

    let recipe: CustomSolidRecipeViewSnapshot
    let profile: CareProfile

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var recipeWriter: SolidsCustomRecipeWriter?
    @State private var planWriter: SolidsPlanWriter?
    @State private var isPlanning = false
    @State private var planMessage: String?

    init(recipe: CustomSolidRecipe, profile: CareProfile) {
        self.recipe = CustomSolidRecipeViewSnapshot(recipe)
        self.profile = profile
    }

    init(recipe: CustomSolidRecipeViewSnapshot, profile: CareProfile) {
        self.recipe = recipe
        self.profile = profile
    }

    private var nutrition: SolidRecipeNutritionSummary {
        SolidsNutritionService.recipeSummary(
            ingredients: recipe.ingredients,
            servings: recipe.servings,
            capturedAt: recipe.updatedAt,
            customFoods: customFoods
        )
    }

    var body: some View {
        let summary = nutrition
        List {
            Section {
                LabeledContent("Yield") {
                    Text("\(recipe.servings.formatted(.number.precision(.fractionLength(0...1)))) serving\(recipe.servings == 1 ? "" : "s")")
                }
                LabeledContent("Suggested stage", value: "\(recipe.minimumAgeMonths)+ months")
            }

            Section("Ingredients") {
                ForEach(recipe.ingredients) { ingredient in
                    HStack {
                        Text(ingredient.foodName)
                        Spacer()
                        Text("\(ingredient.amount.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit.abbreviatedName)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if summary.quantifiedIngredientCount > 0 {
                Section {
                    nutrientRow("Calories", value: summary.nutrients.energyKilocalories, unit: "kcal")
                    nutrientRow("Protein", value: summary.nutrients.proteinGrams, unit: "g")
                    nutrientRow("Fat", value: summary.nutrients.fatGrams, unit: "g")
                    nutrientRow("Fiber", value: summary.nutrients.fiberGrams, unit: "g")
                    nutrientRow("Iron", value: summary.nutrients.ironMilligrams, unit: "mg")
                    nutrientRow("Zinc", value: summary.nutrients.zincMilligrams, unit: "mg")
                    nutrientRow("Calcium", value: summary.nutrients.calciumMilligrams, unit: "mg")
                    nutrientRow("Vitamin C", value: summary.nutrients.vitaminCMilligrams, unit: "mg")
                } header: {
                    Text("Estimated per serving")
                } footer: {
                    if summary.isComplete {
                        Text("All ingredients have values for all eight tracked nutrients. Estimates use the saved ingredient amounts.")
                    } else if summary.quantifiedIngredientCount == summary.ingredientCount {
                        Text("Built-in foods are fully covered. One or more custom labels omit values, so those specific nutrient totals only include entered label values.")
                    } else {
                        Text("Built-in foods are fully covered. Some custom ingredients could not be calculated from their saved unit and manual-label serving information. Add or update the label’s serving weight, or change the recipe unit; blank label values are not inferred.")
                    }
                }
            } else {
                Section("Estimated nutrition") {
                    Text("Every built-in food includes all eight tracked nutrients. Custom ingredients need a manual nutrition label whose serving unit or serving weight can convert the saved recipe amount.")
                        .foregroundStyle(.secondary)
                }
            }

            if !recipe.instructions.isEmpty {
                Section("Prepare") { Text(recipe.instructions) }
            }
            if !recipe.notes.isEmpty {
                Section("Notes") { Text(recipe.notes) }
            }

            Section {
                Button {
                    let preset = SolidsNutritionService.preset(
                        recipeID: recipe.trackingID,
                        recipeName: recipe.name,
                        ingredients: recipe.ingredients,
                        servings: recipe.servings,
                        customFoods: customFoods
                    )
                    DeepLinkRouter.shared.openToday(action: .logSolidFeed(preset), profileID: profile.id)
                } label: {
                    Label("Adjust and log this recipe", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("solids.custom-recipe.log")

                Button {
                    planForTomorrow()
                } label: {
                    Label(isPlanning ? "Adding to tomorrow…" : "Plan for tomorrow", systemImage: "calendar.badge.plus")
                }
                .disabled(isPlanning)

                Button {
                    showingEditor = true
                } label: {
                    Label("Edit recipe", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete recipe", systemImage: "trash")
                }
                .accessibilityIdentifier("solids.custom-recipe.delete")
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            NavigationStack { CustomSolidRecipeEditorView(recipe: recipe) }
        }
        .appActionSheet(
            isPresented: $showingDeleteConfirmation,
            title: "Delete \(recipe.name)?",
            message: "Existing food logs keep their saved amounts and nutrition snapshots. Remove this recipe from meal plans that have not been logged before deleting it.",
            systemImage: "trash.fill",
            tint: .red,
            options: [
                AppActionSheetOption(
                    title: "Delete Recipe",
                    subtitle: "Permanently remove this recipe from your saved recipes.",
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive
                ) {
                    Task { await deleteRecipe() }
                }
            ]
        )
        .alert("Couldn’t delete recipe", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Meal plan", isPresented: Binding(
            get: { planMessage != nil },
            set: { if !$0 { planMessage = nil } }
        )) {
            Button("OK") { planMessage = nil }
        } message: {
            Text(planMessage ?? "")
        }
        .task {
            _ = await resolvedRecipeWriter()
            _ = await resolvedPlanWriter()
        }
    }

    @ViewBuilder
    private func nutrientRow(_ title: String, value: Double?, unit: String) -> some View {
        if let value {
            LabeledContent(title, value: "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
        }
    }

    private func deleteRecipe() async {
        let writer = await resolvedRecipeWriter()
        if let error = await writer.delete(recipeID: recipe.id) {
            deleteError = error
            PersistenceService.recordLocalSaveFailure(error)
        } else {
            dismiss()
        }
    }

    private func planForTomorrow() {
        guard !isPlanning else { return }
        isPlanning = true
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        Task {
            let writer = await resolvedPlanWriter()
            let result = await writer.saveEditorPlan(SolidsPlanEditorWrite(
                planID: nil,
                profileID: profile.id,
                scheduledAt: tomorrow,
                foodIDs: recipe.ingredients.map(\.foodID),
                foodNames: recipe.ingredients.map(\.foodName),
                notes: recipe.instructions,
                reminderEnabled: false,
                reminderOffsetMinutes: 30,
                title: recipe.name,
                recipeID: recipe.trackingID,
                duplicatePolicy: .matchingRecipeOnDay
            ))
            isPlanning = false
            if let error = result.error {
                planMessage = "The meal plan could not be saved."
                PersistenceService.recordLocalSaveFailure(error)
            } else {
                planMessage = result.wasAlreadyPresent
                    ? "This recipe is already on tomorrow’s meal plan."
                    : "Added this recipe to tomorrow’s meal plan."
            }
        }
    }

    @MainActor
    private func resolvedRecipeWriter() async -> SolidsCustomRecipeWriter {
        if let recipeWriter { return recipeWriter }
        let value = await SolidsWriterPool.shared.customRecipeWriter(for: modelContext.container)
        recipeWriter = value
        return value
    }

    @MainActor
    private func resolvedPlanWriter() async -> SolidsPlanWriter {
        if let planWriter { return planWriter }
        let value = await SolidsWriterPool.shared.planWriter(for: modelContext.container)
        planWriter = value
        return value
    }
}

struct CustomSolidRecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SolidFoodCatalogItem.name) private var customFoods: [SolidFoodCatalogItem]

    let recipe: CustomSolidRecipeViewSnapshot?

    @State private var name: String
    @State private var ingredients: [CustomSolidRecipeIngredient]
    @State private var servings: Double
    @State private var minimumAgeMonths: Int
    @State private var instructions: String
    @State private var notes: String
    @State private var selectedFoodID: String?
    @State private var ingredientAmount: Double?
    @State private var ingredientUnit: SolidPortionUnit = .gram
    @State private var showingFoodPicker = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var recipeWriter: SolidsCustomRecipeWriter?

    init(recipe: CustomSolidRecipeViewSnapshot?) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _ingredients = State(initialValue: recipe?.ingredients ?? [])
        _servings = State(initialValue: recipe?.servings ?? 1)
        _minimumAgeMonths = State(initialValue: recipe?.minimumAgeMonths ?? 6)
        _instructions = State(initialValue: recipe?.instructions ?? "")
        _notes = State(initialValue: recipe?.notes ?? "")
    }

    private var foodChoices: [CustomRecipeFoodChoice] {
        let referenceChoices = SolidsReferenceCatalog.foodSummaries.map { food in
            CustomRecipeFoodChoice(
                id: food.id,
                name: food.name,
                subtitle: food.category.displayName,
                // Catalog coverage is generated and enforced by tests. Avoid
                // constructing 535 full nutrition references every time this
                // editor recomputes its food choices.
                hasNutrition: true
            )
        }
        let customChoices = customFoods.map { food in
            CustomRecipeFoodChoice(
                id: food.trackingID,
                name: food.name,
                subtitle: "Custom food",
                hasNutrition: food.nutritionLabel != nil
            )
        }
        return (referenceChoices + customChoices).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var selectedFood: CustomRecipeFoodChoice? {
        guard let selectedFoodID else { return nil }
        if selectedFoodID.hasPrefix("custom-"),
           let food = customFoods.first(where: { $0.trackingID == selectedFoodID }) {
            return CustomRecipeFoodChoice(
                id: food.trackingID,
                name: food.name,
                subtitle: "Custom food",
                hasNutrition: food.nutritionLabel != nil
            )
        }
        guard let food = SolidsReferenceCatalog.foodSummary(id: selectedFoodID) else { return nil }
        return CustomRecipeFoodChoice(
            id: food.id,
            name: food.name,
            subtitle: food.category.displayName,
            hasNutrition: SolidsNutritionCatalog.reference(foodID: food.id) != nil
        )
    }

    private var supportedIngredientUnits: [SolidPortionUnit] {
        guard let selectedFoodID else { return SolidPortionUnit.allCases }
        return SolidsNutritionService.supportedUnits(foodID: selectedFoodID, customFoods: customFoods)
    }

    private var canAddIngredient: Bool {
        selectedFood != nil
            && (ingredientAmount.map { $0.isFinite && $0 > 0 } ?? false)
            && !ingredients.contains(where: { $0.foodID == selectedFoodID })
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ingredients.isEmpty
            && ingredients.allSatisfy { $0.amount.isFinite && $0.amount > 0 }
            && servings.isFinite
            && servings > 0
            && !isSaving
    }

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Recipe name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("solids.custom-recipe.name")
                Stepper(value: $servings, in: 0.5...50, step: 0.5) {
                    LabeledContent("Yield", value: "\(servings.formatted(.number.precision(.fractionLength(0...1)))) servings")
                }
                Stepper(value: $minimumAgeMonths, in: 6...36, step: 1) {
                    LabeledContent("Suggested stage", value: "\(minimumAgeMonths)+ months")
                }
            }

            Section("Ingredients") {
                if ingredients.isEmpty {
                    Text("Add each ingredient with the amount used for the full recipe.")
                        .foregroundStyle(.secondary)
                }
                ForEach($ingredients) { $ingredient in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(ingredient.foodName)
                                .font(.body.weight(.medium))
                            Spacer()
                            Button(role: .destructive) {
                                let ingredientID = ingredient.id
                                ingredients.removeAll { $0.id == ingredientID }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(ingredient.foodName)")
                        }
                        HStack {
                            TextField("Amount", value: $ingredient.amount, format: .number)
                                .keyboardType(.decimalPad)
                            Picker("Unit", selection: $ingredient.unit) {
                                ForEach(supportedUnits(for: ingredient.foodID, including: ingredient.unit)) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .labelsHidden()
                        }
                        if ingredientNutritionIsUnavailable(ingredient) {
                            Text("Nutrition cannot be calculated for this saved unit. Update the custom food’s label serving weight or choose a compatible unit.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("Amount used for the full recipe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    showingFoodPicker = true
                } label: {
                    HStack {
                        Label("Food", systemImage: "fork.knife")
                        Spacer()
                        Text(selectedFood?.name ?? "Choose")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("solids.custom-recipe.choose-food")
                LabeledContent("Amount") {
                    TextField("Required", value: $ingredientAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("solids.custom-recipe.ingredient-amount")
                }
                Picker("Unit", selection: $ingredientUnit) {
                    ForEach(supportedIngredientUnits) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                if let selectedFood, !selectedFood.hasNutrition {
                    Text("This ingredient can still be used, but its nutrients will be omitted until nutrition data is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Add ingredient", systemImage: "plus.circle.fill") {
                    addIngredient()
                }
                .disabled(!canAddIngredient)
                .accessibilityIdentifier("solids.custom-recipe.add-ingredient")
            } header: {
                Text("Add ingredient")
            } footer: {
                Text("Enter full-recipe amounts. Little Windows divides the estimate by the recipe yield when logging one serving.")
            }

            Section("Prepare") {
                TextField("Instructions", text: $instructions, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle(recipe == nil ? "Build Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityIdentifier("solids.custom-recipe.save")
            }
        }
        .sheet(isPresented: $showingFoodPicker) {
            NavigationStack {
                CustomRecipeFoodPickerView(
                    choices: foodChoices.filter { choice in
                        choice.id == selectedFoodID || !ingredients.contains(where: { $0.foodID == choice.id })
                    },
                    selectedID: selectedFoodID
                ) { choice in
                    selectedFoodID = choice.id
                    let units = SolidsNutritionService.supportedUnits(foodID: choice.id, customFoods: customFoods)
                    ingredientUnit = units.contains(.gram) ? .gram : units.first ?? .serving
                    showingFoodPicker = false
                }
            }
        }
        .alert("Couldn’t save recipe", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task { _ = await resolvedRecipeWriter() }
    }

    private func addIngredient() {
        guard let food = selectedFood, let amount = ingredientAmount, canAddIngredient else { return }
        ingredients.append(CustomSolidRecipeIngredient(
            foodID: food.id,
            foodName: food.name,
            amount: amount,
            unit: ingredientUnit
        ))
        selectedFoodID = nil
        ingredientAmount = nil
        ingredientUnit = .gram
    }

    private func supportedUnits(
        for foodID: String,
        including currentUnit: SolidPortionUnit
    ) -> [SolidPortionUnit] {
        var units = SolidsNutritionService.supportedUnits(foodID: foodID, customFoods: customFoods)
        if !units.contains(currentUnit) { units.append(currentUnit) }
        return SolidPortionUnit.allCases.filter(units.contains)
    }

    private func ingredientNutritionIsUnavailable(_ ingredient: CustomSolidRecipeIngredient) -> Bool {
        guard ingredient.foodID.hasPrefix("custom-") else { return false }
        guard let reference = SolidsNutritionService.reference(
            foodID: ingredient.foodID,
            customFoods: customFoods
        ) else { return true }
        return SolidsNutritionService.snapshot(
            amount: ingredient.amount,
            unit: ingredient.unit,
            reference: reference
        ) == nil
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let writer = await resolvedRecipeWriter()
        let result = await writer.save(SolidsCustomRecipeWrite(
            recipeID: recipe?.id,
            name: name,
            ingredients: ingredients,
            servings: servings,
            minimumAgeMonths: minimumAgeMonths,
            instructions: instructions,
            notes: notes
        ))
        if let error = result.error {
            saveError = error
            PersistenceService.recordLocalSaveFailure(error)
        } else {
            dismiss()
        }
    }

    @MainActor
    private func resolvedRecipeWriter() async -> SolidsCustomRecipeWriter {
        if let recipeWriter { return recipeWriter }
        let value = await SolidsWriterPool.shared.customRecipeWriter(for: modelContext.container)
        recipeWriter = value
        return value
    }
}

private struct CustomRecipeFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let choices: [CustomRecipeFoodChoice]
    let selectedID: String?
    let select: (CustomRecipeFoodChoice) -> Void

    @State private var searchText = ""

    private var visibleChoices: [CustomRecipeFoodChoice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return choices }
        return choices.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(visibleChoices) { choice in
            Button {
                select(choice)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(choice.name).foregroundStyle(.primary)
                        Text(choice.hasNutrition ? "\(choice.subtitle) • nutrition available" : choice.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedID == choice.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                    }
                }
            }
            .accessibilityIdentifier("solids.custom-recipe.food.\(choice.id)")
        }
        .navigationTitle("Choose Food")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search foods")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
