import SwiftData
import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color.indigo
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.08)
}

extension EventType {
    var tint: Color {
        switch self {
        case .sleep: .indigo
        case .feed: .orange
        case .nursing: .pink
        case .pumping: .cyan
        case .diaper: .teal
        case .medicine: .red
        case .growth: .mint
        case .temperature: .red
        case .activity: .green
        case .food: .orange
        case .water: .cyan
        case .treat: .brown
        case .potty: .teal
        case .walk: .green
        case .rest: .indigo
        case .training: .purple
        case .grooming: .pink
        case .symptom: .red
        case .bloodPressure: .red
        case .heartRate: .pink
        case .oxygenSaturation: .cyan
        case .respiratoryRate: .blue
        case .vaccine: .mint
        case .glucose: .red
        case .pain: .orange
        case .custom: .purple
        }
    }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        content
            .textCase(nil)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if let subtitle {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    headerTitle
                    Spacer(minLength: 12)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 3) {
                    headerTitle
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            headerTitle
        }
    }

    private var headerTitle: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct AdaptiveLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                configuration.label
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                configuration.content
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                configuration.label
                configuration.content
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct SurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.line, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}

extension View {
    func appSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(SurfaceModifier(cornerRadius: cornerRadius))
    }

    func appActionSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        systemImage: String? = nil,
        tint: Color = AppTheme.accent,
        options: [AppActionSheetOption],
        cancelTitle: String = "Cancel",
        cancelAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        let estimatedHeight = max(320, min(700, 220 + CGFloat(options.count) * 78))
        return sheet(isPresented: isPresented, onDismiss: onDismiss) {
            AppActionSheetView(
                title: title,
                message: message,
                systemImage: systemImage,
                tint: tint,
                options: options,
                cancelTitle: cancelTitle,
                cancelAction: cancelAction
            )
            .presentationDetents([
                .height(estimatedHeight),
                .large
            ])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
        }
    }
}

struct AppActionSheetOption: Identifiable {
    let id: String
    var title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color
    var role: ButtonRole?
    var isEnabled: Bool
    var isSelected: Bool
    var action: () -> Void

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accent,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.role = role
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
    }
}

private struct AppActionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var message: String?
    var systemImage: String?
    var tint: Color
    var options: [AppActionSheetOption]
    var cancelTitle = "Cancel"
    var cancelAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Button {
                    cancelAction?()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        Button(role: option.role) {
                            dismiss()
                            option.action()
                        } label: {
                            AppActionSheetRow(option: option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityHint(option.subtitle ?? "")
                        .disabled(!option.isEnabled)
                        .opacity(option.isEnabled ? 1 : 0.48)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)
            .layoutPriority(1)

            Button(cancelTitle, role: .cancel) {
                cancelAction?()
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(AppTheme.background)
    }
}

private struct AppActionSheetRow: View {
    let option: AppActionSheetOption

    private var effectiveTint: Color {
        option.role == .destructive ? .red : option.tint
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: option.systemImage)
                .font(.headline)
                .foregroundStyle(effectiveTint)
                .frame(width: 38, height: 38)
                .background(effectiveTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(option.role == .destructive ? .red : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if option.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(effectiveTint)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.line, lineWidth: 0.5)
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @Query(sort: \Household.createdAt) private var households: [Household]
    @AppStorage(FirstRunOnboarding.completedKey) private var hasCompletedInitialOnboarding = false
    @AppStorage(CaregiverIdentityService.currentCaregiverNameKey) private var currentCaregiverName = ""
    @AppStorage(CaregiverIdentityService.needsLogNamePromptKey) private var needsLogNamePrompt = false
    @StateObject private var router = DeepLinkRouter.shared
    @StateObject private var profileService = ProfileService.shared
    @State private var shouldOpenSettingsAfterOnboarding = false
    @State private var hasCheckedInitialOnboardingState = false
    @State private var showingFamilySyncAcceptanceStatus = false
    @State private var showingFamilySyncAccessEndedStatus = false
    @State private var localSaveErrorMessage: String?
    @State private var reconciliationRequestTask: Task<Void, Never>?
    @State private var careProfilePresentationTask: Task<Void, Never>?
    @AppStorage(CloudKitSharingService.acceptanceStatusMessageKey)
    private var familySyncAcceptanceMessage = ""
    @AppStorage(PersistenceService.familySyncModeKey)
    private var familySyncModeRawValue = FamilySyncMode.privateICloudSync.rawValue
    @AppStorage("familySync.lastPresentedAcceptanceStatusMessage")
    private var lastPresentedFamilySyncAcceptanceMessage = ""
    @AppStorage(CloudKitSharingService.inactiveReasonKey)
    private var familySyncInactiveReasonRawValue = ""
    @AppStorage(CloudKitSharingService.inactiveEventIDKey)
    private var familySyncInactiveEventID = ""
    @AppStorage("familySync.lastPresentedInactiveEventID")
    private var lastPresentedFamilySyncInactiveEventID = ""

    private var selectedProfile: CareProfile? {
        profileService.selectedProfile(in: profiles)
    }

    private var activeProfileIDs: [UUID] {
        profileService.allActiveProfiles(in: profiles).map(\.id)
    }

    private var experienceMode: AppExperienceMode {
        AppExperienceMode(hasActiveCareProfile: !activeProfileIDs.isEmpty)
    }

    private var primaryTabs: some View {
        TabView(selection: $router.selectedTab) {
            Group {
                if router.selectedTab == .today {
                    NavigationStack { TodayView(profileID: selectedProfile?.id) }
                } else {
                    Color.clear
                }
            }
                .tabItem { Label("Today", systemImage: "sparkles") }
                .tag(LittleWindowsTab.today)

            Group {
                if router.selectedTab == .food {
                    FoodHomeView()
                } else {
                    Color.clear
                }
            }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(LittleWindowsTab.food)

            if experienceMode == .care {
                Group {
                    if router.selectedTab == .reports {
                        NavigationStack { ReportsView(profileID: selectedProfile?.id) }
                    } else {
                        Color.clear
                    }
                }
                    .tabItem { Label("Reports", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(LittleWindowsTab.reports)

                Group {
                    if router.selectedTab == .milestones {
                        CareView(profileID: selectedProfile?.id)
                    } else {
                        Color.clear
                    }
                }
                    .tabItem { Label("Care", systemImage: "heart.text.clipboard.fill") }
                    .tag(LittleWindowsTab.milestones)
            }

            Group {
                if router.selectedTab == .nightLight {
                    NavigationStack { NightLightView(profile: selectedProfile) }
                } else {
                    Color.clear
                }
            }
                .tabItem { Label("Night Light", systemImage: "lightbulb.fill") }
                .tag(LittleWindowsTab.nightLight)
        }
        .onChange(of: router.selectedTab) { _, _ in
            handleNavigationRequestForCurrentExperience()
        }
    }

    private var presentedTabs: some View {
        primaryTabs
        .tint(AppTheme.accent)
        .environmentObject(router)
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    guard hasCheckedInitialOnboardingState else { return false }
                    return FirstRunOnboarding.shouldPresent(
                        hasCompleted: hasCompletedInitialOnboarding,
                        profiles: profiles,
                        households: households
                    )
                },
                set: { _ in }
            )
        ) {
            FirstRunOnboardingView(
                completeOnboarding: {
                    hasCompletedInitialOnboarding = true
                    if selectedProfile == nil {
                        router.todayDisplayMode = .home
                        router.selectedTab = .today
                    } else {
                        router.selectTodayCare()
                    }
                },
                importBackupInstead: {
                    shouldOpenSettingsAfterOnboarding = true
                    hasCompletedInitialOnboarding = true
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $router.showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                router.showingSettings = false
                            }
                        }
                }
            }
        }
        .sheet(item: $router.careProfileRequirement) { requirement in
            NavigationStack {
                CareProfileRequiredView(requirement: requirement)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var alertedTabs: some View {
        presentedTabs
        .alert("Set your caregiver name", isPresented: Binding(
            get: {
                needsLogNamePrompt &&
                    currentCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            set: { if !$0 { needsLogNamePrompt = false } }
        )) {
            Button("Open Settings") {
                needsLogNamePrompt = false
                router.showingSettings = true
            }
            Button("Later", role: .cancel) {
                needsLogNamePrompt = false
            }
        } message: {
            Text("Enter the name this device should use for household activity and any future care entries.")
        }
        .alert("Family Sync", isPresented: $showingFamilySyncAcceptanceStatus) {
            Button("Open Settings") {
                lastPresentedFamilySyncAcceptanceMessage = familySyncAcceptanceMessage
                router.showingSettings = true
            }
            Button("OK", role: .cancel) {
                lastPresentedFamilySyncAcceptanceMessage = familySyncAcceptanceMessage
            }
        } message: {
            Text(familySyncAcceptanceMessage)
        }
        .alert(
            familySyncInactiveReason?.title ?? "Family Sync access ended",
            isPresented: $showingFamilySyncAccessEndedStatus
        ) {
            Button("Review Family Sync") {
                lastPresentedFamilySyncInactiveEventID = familySyncInactiveEventID
                router.route(URL(string: "littlewindows://settings/family-sync")!)
            }
            Button("Later", role: .cancel) {
                lastPresentedFamilySyncInactiveEventID = familySyncInactiveEventID
            }
        } message: {
            Text(familySyncInactiveReason?.detail ?? "Family Sync is no longer active. Your downloaded data remains on this device.")
        }
        .alert("Changes weren’t saved", isPresented: Binding(
            get: { localSaveErrorMessage != nil },
            set: { if !$0 { localSaveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Little Windows kept the previous saved version. \(localSaveErrorMessage ?? "Please try again.")")
        }
    }

    private var tabsWithApplicationEvents: some View {
        alertedTabs
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: CloudKitSharingService.acceptanceStatusDidChangeNotification
            )
        ) { _ in
            presentFamilySyncAcceptanceStatusIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: CloudKitSharingService.shareStateDidChangeNotification
            )
        ) { _ in
            presentFamilySyncAccessEndedStatusIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: PersistenceService.localSaveDidFailNotification
            )
        ) { notification in
            localSaveErrorMessage = notification.userInfo?["message"] as? String
                ?? "Please try again."
        }
    }

    private var tabsWithStateObservers: some View {
        tabsWithApplicationEvents
        .onChange(of: familySyncInactiveEventID) { _, _ in
            presentFamilySyncAccessEndedStatusIfNeeded()
        }
        .onChange(of: router.showingFamilySyncSettings) { _, isShowing in
            guard isShowing, !familySyncInactiveEventID.isEmpty else { return }
            lastPresentedFamilySyncInactiveEventID = familySyncInactiveEventID
        }
        .onChange(of: profiles.count) { _, _ in
            recoverCaregiverIdentityIfNeeded()
            markOnboardingCompleteForExistingData()
            hasCheckedInitialOnboardingState = true
        }
        .onChange(of: households.count) { _, _ in
            markOnboardingCompleteForExistingData()
            hasCheckedInitialOnboardingState = true
        }
        .onChange(of: activeProfileIDs) { previousIDs, currentIDs in
            handleActiveProfileTransition(from: previousIDs, to: currentIDs)
        }
        .onChange(of: router.navigationRequestRevision) { _, _ in
            handleNavigationRequestForCurrentExperience()
        }
    }

    private var tabsWithLifecycleWork: some View {
        tabsWithStateObservers
        .task(id: "profile-duplicate-repair-\(profiles.count)") {
            guard profiles.count > 1 else { return }
            let worker = ProfileDuplicateRepairWorker(
                modelContainer: modelContext.container
            )
            let removedCount = await worker.repair()
            guard !Task.isCancelled, removedCount > 0 else { return }
            let currentProfiles = (try? modelContext.fetch(
                FetchDescriptor<CareProfile>()
            )) ?? []
            _ = profileService.ensureSelection(in: currentProfiles)
            }
        .onChange(of: hasCompletedInitialOnboarding) { _, completed in
            guard completed else { return }
            ensureHouseholdWorkspaceIfNeeded()
            guard shouldOpenSettingsAfterOnboarding else { return }
            shouldOpenSettingsAfterOnboarding = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                router.showingSettings = true
            }
        }
        .onChange(of: scenePhase) {
            let phase = scenePhase
            if phase == .active {
                consumePendingSystemAction()
            } else {
                // Flush any main-context timer field changes before iOS
                // suspends the process.
                _ = EventMutationService.persistTimerMutations(
                    context: modelContext
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: SystemIntegrationReconciler.reconciliationRequestedNotification
        )) { _ in
            reconciliationRequestTask?.cancel()
            reconciliationRequestTask = Task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                await SystemIntegrationReconciler.reconcile(context: modelContext)
            }
        }
        .task(id: "\(scenePhase)-\(familySyncModeRawValue)") {
            guard scenePhase == .active else { return }
            await pollFamilyTimerChangesWhileActive()
        }
        .task(id: "system-integrations-\(scenePhase)") {
            guard scenePhase == .active else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            await SystemIntegrationReconciler.reconcileIfNeeded(context: modelContext)
        }
    }

    var body: some View {
        tabsWithLifecycleWork
            .task {
                performInitialSetup()
            }
    }

    private func performInitialSetup() {
        let launchURL = uiTestingLaunchURL
        if let launchURL {
            route(launchURL)
            #if DEBUG
            if DebugSimulatorSmokeSeedService.isResetEmpty(launchURL),
               DebugSimulatorSmokeSeedService.isEnabled {
                // The query arrays still describe the pre-reset store in this
                // render pass. Let their updates drive onboarding instead of
                // marking that stale data as an existing setup.
                hasCheckedInitialOnboardingState = true
                return
            }
            #endif
        }
        recoverCaregiverIdentityIfNeeded()
        markOnboardingCompleteForExistingData()
        hasCheckedInitialOnboardingState = true
        ensureHouseholdWorkspaceIfNeeded()
        handleNavigationRequestForCurrentExperience()
        if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_TAB"] == "insights" {
            router.selectedReportsMode = .summary
            router.selectedTab = .reports
        }
        if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_TAB"] == "history" {
            router.selectedReportsMode = .day
            router.selectedTab = .reports
        }
        consumePendingSystemAction()
        presentFamilySyncAcceptanceStatusIfNeeded()
        presentFamilySyncAccessEndedStatusIfNeeded()
    }

    private func markOnboardingCompleteForExistingData() {
        guard !hasCompletedInitialOnboarding,
              !profiles.isEmpty || !households.isEmpty else { return }
        if !CaregiverIdentityService.hasExplicitCurrentCaregiverName() {
            needsLogNamePrompt = true
        }
        hasCompletedInitialOnboarding = true
    }

    private var uiTestingLaunchURL: URL? {
        if let value = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_URL"],
           let url = URL(string: value) {
            return url
        }
        let arguments = CommandLine.arguments
        guard let markerIndex = arguments.firstIndex(of: "--little-windows-start-url"),
              arguments.indices.contains(markerIndex + 1) else {
            return nil
        }
        return URL(string: arguments[markerIndex + 1])
    }

    private func ensureHouseholdWorkspaceIfNeeded() {
        guard hasCompletedInitialOnboarding, households.isEmpty else { return }
        FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
    }

    private func handleActiveProfileTransition(
        from previousIDs: [UUID],
        to currentIDs: [UUID]
    ) {
        if previousIDs.isEmpty, !currentIDs.isEmpty {
            router.careProfileRequirement = nil
            router.todayDisplayMode = .care
            router.selectedTab = .today
        } else if !previousIDs.isEmpty, currentIDs.isEmpty {
            router.todayDisplayMode = .home
            router.selectedTab = .today
        } else {
            normalizeNavigationForCurrentExperience()
        }
    }

    private func normalizeNavigationForCurrentExperience() {
        let normalizedTab = experienceMode.normalizedTab(router.selectedTab)
        if router.selectedTab != normalizedTab {
            router.selectedTab = normalizedTab
        }
        let normalizedTodayMode = experienceMode.normalizedTodayMode(router.todayDisplayMode)
        if router.todayDisplayMode != normalizedTodayMode {
            router.todayDisplayMode = normalizedTodayMode
        }
    }

    private func handleNavigationRequestForCurrentExperience() {
        guard hasCompletedInitialOnboarding, experienceMode == .householdOnly else {
            normalizeNavigationForCurrentExperience()
            return
        }

        if let url = router.lastRequestedURL,
           let requirement = AppNavigationPolicy.careProfileRequirement(for: url) {
            prepareForCareProfileRequirement(requirement)
            return
        }
        if let requirement = pendingCareProfileRequirement {
            prepareForCareProfileRequirement(requirement)
            return
        }
        if let url = router.lastRequestedURL,
           AppNavigationPolicy.isHouseholdRoute(url) {
            prepareForHouseholdNavigation(to: url)
            normalizeNavigationForCurrentExperience()
            return
        }
        normalizeNavigationForCurrentExperience()
    }

    private var pendingCareProfileRequirement: CareProfileRequirement? {
        switch router.selectedTab {
        case .reports, .medical:
            return .reports
        case .milestones:
            return .care
        case .today where router.todayDisplayMode == .care:
            if router.pendingAppointmentCommand != nil { return .appointments }
            if router.pendingRoutineCommand != nil { return .routines }
            if router.pendingAgeGuideCommand != nil
                || router.pendingPuppyGuideCommand != nil
                || router.pendingSolidsCommand != nil {
                return .care
            }
            if router.pendingAction != nil { return .logging }
            return nil
        default:
            return nil
        }
    }

    private func recoverCaregiverIdentityIfNeeded() {
        guard !profiles.isEmpty,
              !CaregiverIdentityService.hasExplicitCurrentCaregiverName() else {
            return
        }
        if CaregiverIdentityService.restoreFromHistoryIfUnambiguous(context: modelContext) != nil {
            needsLogNamePrompt = false
        }
    }

    private func pollFamilyTimerChangesWhileActive() async {
        do {
            try await Task.sleep(
                for: .seconds(
                    CloudKitSharingService.foregroundTimerInitialDelaySeconds
                )
            )
        } catch {
            return
        }

        while !Task.isCancelled,
              PersistenceService.familySyncMode() == .sharedFamilySync {
            let retryDelay: TimeInterval
            do {
                _ = try await CloudKitSharingService.shared.pollForForegroundTimerChanges(
                    context: modelContext
                )
                retryDelay = CloudKitSharingService.foregroundTimerPollIntervalSeconds
            } catch {
                retryDelay = CloudKitSharingService.foregroundTimerFailureRetrySeconds
            }
            do {
                try await Task.sleep(for: .seconds(retryDelay))
            } catch {
                return
            }
        }
    }

    private func route(_ url: URL) {
        #if DEBUG
        if DebugSimulatorSmokeSeedService.isResetEmpty(url), DebugSimulatorSmokeSeedService.isEnabled {
            DebugSimulatorSmokeSeedService.resetEmpty(context: modelContext)
            hasCompletedInitialOnboarding = false
            hasCheckedInitialOnboardingState = true
            router.selectTodayCare()
            return
        }
        if DebugSimulatorSmokeSeedService.isPerformanceSeed(url),
           DebugSimulatorSmokeSeedService.isEnabled {
            DebugSimulatorSmokeSeedService.seedPerformanceDataIfNeeded(context: modelContext)
            hasCompletedInitialOnboarding = true
            router.selectTodayCare()
            return
        }
        if DebugSimulatorSmokeSeedService.canHandle(url), DebugSimulatorSmokeSeedService.isEnabled {
            DebugSimulatorSmokeSeedService.seedIfNeeded(context: modelContext)
            hasCompletedInitialOnboarding = true
            router.selectTodayCare()
            return
        }
        #endif
        guard !presentCareProfileRequirementIfNeeded(for: url) else { return }
        prepareForHouseholdNavigation(to: url)
        router.route(url)
        if experienceMode == .householdOnly {
            // Profile-prefixed Home or Night Light links can outlive an archived
            // profile. Neither destination is profile-scoped, so do not let that
            // stale identifier affect a later care navigation request.
            router.pendingProfileID = nil
        }
    }

    private func consumePendingSystemAction() {
        Task { @MainActor in
            while let url = IntegrationCommandStore.consumePendingURL() {
                if presentCareProfileRequirementIfNeeded(for: url) {
                    continue
                }
                prepareForHouseholdNavigation(to: url)
                if await IntegrationCommandStore.deliverToRunningApp(url) {
                    presentProcessedSystemAction(url)
                    continue
                }
                route(url)
                break
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        Task { @MainActor in
            if presentCareProfileRequirementIfNeeded(for: url) {
                IntegrationCommandStore.clearPendingURL(matching: url)
                return
            }
            prepareForHouseholdNavigation(to: url)
            if await IntegrationCommandStore.deliverToRunningApp(url) {
                IntegrationCommandStore.clearPendingURL(matching: url)
                presentProcessedSystemAction(url)
            } else {
                route(url)
            }
        }
    }

    private func presentCareProfileRequirementIfNeeded(for url: URL) -> Bool {
        guard hasCompletedInitialOnboarding,
              experienceMode == .householdOnly,
              let requirement = AppNavigationPolicy.careProfileRequirement(for: url) else {
            return false
        }
        // The URL is intentionally not routed while no profile exists. Clear any
        // older request so its destination cannot cancel this delayed prompt.
        router.clearLastRequestedURL()
        prepareForCareProfileRequirement(requirement)
        return true
    }

    private func prepareForCareProfileRequirement(_ requirement: CareProfileRequirement) {
        // A system link can arrive while Settings is already presented. Dismiss
        // it first so the contextual profile prompt has one unambiguous presenter.
        router.showingSettings = false
        router.showingFamilySyncSettings = false
        normalizeNavigationForCurrentExperience()
        scheduleCareProfileRequirement(requirement)
    }

    private func scheduleCareProfileRequirement(_ requirement: CareProfileRequirement) {
        careProfilePresentationTask?.cancel()
        careProfilePresentationTask = Task { @MainActor in
            // Let the system finish handing off the URL before asking SwiftUI
            // to present over the current navigation stack.
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, experienceMode == .householdOnly else { return }
            router.presentCareProfileRequirement(requirement)
            careProfilePresentationTask = nil
        }
    }

    private func prepareForHouseholdNavigation(to url: URL) {
        careProfilePresentationTask?.cancel()
        careProfilePresentationTask = nil
        router.careProfileRequirement = nil
        router.discardCareNavigationRequest()
        guard !AppNavigationPolicy.isSettingsRoute(url) else { return }
        router.showingSettings = false
        router.showingFamilySyncSettings = false
    }

    private func presentProcessedSystemAction(_ url: URL) {
        var path = [url.host].compactMap { $0 }
            + url.pathComponents.filter { $0 != "/" }
        if path.count >= 2,
           path[0] == "profile",
           let profileID = UUID(uuidString: path[1]) {
            router.pendingProfileID = profileID
            path.removeFirst(2)
        }
        guard path.first == "action" else { return }
        if path.count == 3, let eventID = UUID(uuidString: path[2]) {
            router.openToday(action: .showEvent(eventID))
        } else {
            router.selectTodayCare()
        }
    }

    private func presentFamilySyncAcceptanceStatusIfNeeded() {
        guard !familySyncAcceptanceMessage.isEmpty,
              familySyncAcceptanceMessage != lastPresentedFamilySyncAcceptanceMessage else {
            return
        }
        showingFamilySyncAcceptanceStatus = true
    }

    private var familySyncInactiveReason: FamilyShareInactiveReason? {
        FamilyShareInactiveReason(rawValue: familySyncInactiveReasonRawValue)
    }

    private func presentFamilySyncAccessEndedStatusIfNeeded() {
        guard familySyncInactiveReason != nil,
              !familySyncInactiveEventID.isEmpty,
              familySyncInactiveEventID != lastPresentedFamilySyncInactiveEventID else {
            return
        }
        showingFamilySyncAccessEndedStatus = true
    }
}

private struct CareProfileRequiredView: View {
    @Environment(\.dismiss) private var dismiss
    let requirement: CareProfileRequirement

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.10))
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: requirement.systemImage)
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Add a care profile")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(requirement.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label(requirement.contextTitle, systemImage: requirement.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(AppTheme.accent.opacity(0.09), in: Capsule())

                VStack(spacing: 9) {
                    NavigationLink {
                        ProfileEditorView()
                    } label: {
                        Label("Add Care Profile", systemImage: "person.crop.circle.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("profile-required.add-profile")

                    Button("Not Now") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("Care Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
}

enum FirstRunOnboarding {
    static let completedKey = "hasCompletedInitialOnboarding"

    static func shouldPresent(
        hasCompleted: Bool,
        profiles: [CareProfile],
        households: [Household]
    ) -> Bool {
        !hasCompleted && profiles.isEmpty && households.isEmpty
    }
}

private enum FirstRunOnboardingStep: Int {
    case caregiver
    case profile
}

private enum FirstRunICloudRestoreState: Equatable {
    case idle
    case restoring
    case noDataArrived
    case unavailable(String)
    case failed(String)

    var isWorking: Bool {
        self == .restoring
    }
}

private struct FirstRunOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("caregiverOne") private var caregiverOne = "Caregiver 1"
    @StateObject private var profileService = ProfileService.shared

    var completeOnboarding: () -> Void
    var importBackupInstead: () -> Void

    @State private var step = FirstRunOnboardingStep.caregiver
    @State private var primaryCaregiverName = ""
    @State private var profileType = CareProfileType.child
    @State private var profileName = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var sex = ProfileSex.unknown
    @State private var adultRelationship = AdultCareRelationship.myself
    @State private var sharesWithFamily = false
    @State private var hasAdoptionDate = false
    @State private var adoptionDate = Date()
    @State private var breed = ""
    @State private var validationMessage: String?
    @State private var iCloudRestoreState = FirstRunICloudRestoreState.idle
    @State private var iCloudRestoreTask: Task<Void, Never>?

    private var trimmedPrimaryCaregiverName: String {
        primaryCaregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedProfileName: String {
        profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCaregiverStepValid: Bool {
        !trimmedPrimaryCaregiverName.isEmpty
    }

    private var isProfileStepValid: Bool {
        !trimmedProfileName.isEmpty
    }

    private var profileNamePrompt: String {
        switch profileType {
        case .child: "Child name"
        case .adult: adultRelationship == .myself ? "Your name" : "Adult name"
        case .dog: "Dog name"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if step == .caregiver {
                        caregiverStep
                    } else {
                        profileStep
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(step == .caregiver ? "Welcome" : "First Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step == .profile {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { step = .caregiver }
                    }
                }
            }
            .alert("Check setup", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "")
            }
        }
        .onDisappear {
            iCloudRestoreTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: step == .caregiver ? "sparkles" : profileType.systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            Text(step == .caregiver ? "Set up your home" : "Add the first profile")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(step == .caregiver
                ? "Use Little Windows for household planning, care tracking, or both. You can always add more later."
                : "Choose whether you are tracking a child, adult, or dog, then add the details needed for daily care.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caregiverStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            iCloudRestoreSection

            VStack(alignment: .leading, spacing: 12) {
                Text("Your name")
                    .font(.headline)

                TextField(
                    "Your name",
                    text: $primaryCaregiverName,
                    prompt: Text("Enter name here")
                )
                    .textContentType(.name)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("firstRun.caregiverName")

                Text("This name appears on household assignments and activity. If you add a care profile, it also appears on new care entries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .appSurface()

            VStack(alignment: .leading, spacing: 12) {
                Text("How would you like to start?")
                    .font(.headline)

                setupChoice(
                    title: "Home, Food & Night Light",
                    detail: "Plan tasks, shopping, meals, trips, returns, and use the night light—no care profile needed.",
                    systemImage: "house.fill",
                    tint: .indigo,
                    accessibilityIdentifier: "firstRun.householdOnly",
                    action: startHouseholdOnly
                )

                setupChoice(
                    title: "Add a Care Profile",
                    detail: "Add a care profile now for daily tracking and a personalized Care workspace.",
                    systemImage: "person.crop.circle.badge.plus",
                    tint: .teal,
                    accessibilityIdentifier: "firstRun.addCareProfile",
                    action: startProfileSetup
                )
            }

            Button {
                iCloudRestoreTask?.cancel()
                importBackupInstead()
            } label: {
                Label("Import JSON backup instead", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(iCloudRestoreState.isWorking)
        }
    }

    private func setupChoice(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isCaregiverStepValid || iCloudRestoreState.isWorking)
        .opacity(isCaregiverStepValid && !iCloudRestoreState.isWorking ? 1 : 0.55)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func startHouseholdOnly() {
        guard persistCaregiverIdentity() else { return }
        iCloudRestoreTask?.cancel()
        FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
        completeOnboarding()
    }

    private func startProfileSetup() {
        guard persistCaregiverIdentity() else { return }
        iCloudRestoreTask?.cancel()
        step = .profile
    }

    private func persistCaregiverIdentity() -> Bool {
        guard isCaregiverStepValid else {
            validationMessage = "Enter your name to continue."
            return false
        }
        caregiverOne = trimmedPrimaryCaregiverName
        CaregiverIdentityService.storeIdentity(
            currentName: trimmedPrimaryCaregiverName,
            primaryName: trimmedPrimaryCaregiverName
        )
        return true
    }

    private var iCloudRestoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Already use Little Windows?", systemImage: "icloud.and.arrow.down")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)

            Text("Look for Little Windows data previously synced with Private iCloud Sync on this Apple Account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if iCloudRestoreState.isWorking {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Restoring from iCloud…")
                            .font(.subheadline.weight(.semibold))
                        Text("Keep Little Windows open while synced data arrives.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("firstRun.iCloudRestoreProgress")

                Button("Cancel") {
                    iCloudRestoreTask?.cancel()
                    iCloudRestoreState = .idle
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    beginICloudRestore()
                } label: {
                    Label("Restore from iCloud", systemImage: "arrow.clockwise.icloud.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("firstRun.restoreFromICloud")
            }

            iCloudRestoreResult

            Text("Only data that finished syncing to iCloud can return this way. JSON backups remain the most complete manual recovery option.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .appSurface()
    }

    @ViewBuilder
    private var iCloudRestoreResult: some View {
        switch iCloudRestoreState {
        case .idle, .restoring:
            EmptyView()
        case .noDataArrived:
            restoreMessage(
                title: "No synced data arrived yet",
                detail: "Confirm this device uses the same Apple Account, check the connection, and try again. Little Windows did not create or overwrite any data.",
                systemImage: "icloud.slash",
                color: .orange
            )
        case .unavailable(let message):
            restoreMessage(
                title: "iCloud restore is unavailable",
                detail: message,
                systemImage: "exclamationmark.icloud",
                color: .orange
            )
        case .failed(let message):
            restoreMessage(
                title: "Restore could not finish",
                detail: message,
                systemImage: "exclamationmark.triangle",
                color: .red
            )
        }
    }

    private func restoreMessage(
        title: String,
        detail: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func beginICloudRestore() {
        iCloudRestoreTask?.cancel()
        iCloudRestoreState = .restoring
        iCloudRestoreTask = Task { @MainActor in
            let outcome = await ICloudRestoreService.restore(context: modelContext)
            guard !Task.isCancelled else { return }

            switch outcome {
            case .restored:
                completeOnboarding()
            case .noDataArrived:
                iCloudRestoreState = .noDataArrived
            case .unavailable(let message):
                iCloudRestoreState = .unavailable(message)
            case .failed(let message):
                iCloudRestoreState = .failed(message)
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Care profile")
                    .font(.headline)

                Picker("Profile type", selection: $profileType) {
                    ForEach(CareProfileType.allCases) { value in
                        Label(value.displayName, systemImage: value.systemImage).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline)

                    TextField(profileNamePrompt, text: $profileName)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                }

                if profileType == .adult {
                    Picker("Relationship", selection: $adultRelationship) {
                        ForEach(AdultCareRelationship.allCases) { relationship in
                            Text(relationship.displayName).tag(relationship)
                        }
                    }
                    Toggle("Add date of birth", isOn: $hasBirthDate)
                }

                if profileType != .adult || hasBirthDate {
                    DatePicker(
                        profileType == .dog ? "Birthday or best estimate" : "Date of birth",
                        selection: $birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                HStack {
                    Text("Sex")
                    Spacer()
                    Picker("Sex", selection: $sex) {
                        ForEach(ProfileSex.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if profileType == .dog {
                    TextField("Breed, optional", text: $breed)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Add adoption date", isOn: $hasAdoptionDate)

                    if hasAdoptionDate {
                        DatePicker(
                            "Adoption date",
                            selection: $adoptionDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }
                }

                Toggle("Share this profile with Family Sync", isOn: $sharesWithFamily)

                Text(sharesWithFamily
                    ? "This profile and its care records can be included if you connect Family Sync."
                    : "This profile stays private. You can opt in to Family Sync later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .appSurface()

            Button {
                save()
            } label: {
                Label("Start Tracking", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isProfileStepValid)
        }
    }

    private func save() {
        guard isCaregiverStepValid else {
            validationMessage = "Enter your name to continue."
            step = .caregiver
            return
        }
        guard isProfileStepValid else {
            validationMessage = "Enter a name for this care profile."
            return
        }

        guard persistCaregiverIdentity() else { return }

        if profileType == .dog {
            profileService.createDogProfile(
                name: trimmedProfileName,
                birthDate: birthDate,
                sex: sex,
                sharingScope: sharesWithFamily ? .family : .privateOnly,
                adoptionDate: hasAdoptionDate ? adoptionDate : nil,
                breed: breed.nilIfBlank,
                displayColor: "teal",
                context: modelContext
            )
        } else if profileType == .adult {
            profileService.createAdultProfile(
                name: trimmedProfileName,
                birthDate: hasBirthDate ? birthDate : nil,
                sex: sex,
                relationship: adultRelationship,
                sharingScope: sharesWithFamily ? .family : .privateOnly,
                displayColor: "purple",
                context: modelContext
            )
        } else {
            profileService.createChildProfile(
                name: trimmedProfileName,
                birthDate: birthDate,
                sex: sex,
                sharingScope: sharesWithFamily ? .family : .privateOnly,
                displayColor: "indigo",
                context: modelContext
            )
        }

        completeOnboarding()
    }
}

#if DEBUG
enum DebugSimulatorSmokeSeedService {
    private static let performanceSeededKey = "debug.performanceSeeded.v5"
    static var isEnabled: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["LITTLE_WINDOWS_UI_TESTING"] == "1"
            || CommandLine.arguments.contains("--little-windows-ui-testing")
        #else
        false
        #endif
    }

    static let childProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let dogProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let adultProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static let sleepEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let activeNursingEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    static let appointmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    static let todoListID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    static let shoppingListID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    static let inventoryItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    static let mealPrepItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    static let storeID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
    private static let profilePhotoID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!

    private static let produceSectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000802")!
    private static let coldSectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000803")!
    private static let pantryLocationID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
    private static let freezerLocationID = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!

    static func canHandle(_ url: URL) -> Bool {
        guard url.scheme == "littlewindows" else { return false }
        let components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        return components == ["debug", "seed-smoke"]
    }

    static func isResetEmpty(_ url: URL) -> Bool {
        guard url.scheme == "littlewindows" else { return false }
        let components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        return components == ["debug", "reset-empty"]
    }

    static func isPerformanceSeed(_ url: URL) -> Bool {
        guard url.scheme == "littlewindows" else { return false }
        let components = [url.host].compactMap { $0 }
            + url.pathComponents.filter { $0 != "/" }
        return components == ["debug", "seed-performance"]
    }

    @MainActor
    static func resetEmpty(context: ModelContext) {
        try? DataExportImportService.deleteAll(context: context)
        UserDefaults.standard.removeObject(forKey: FirstRunOnboarding.completedKey)
        UserDefaults.standard.removeObject(forKey: "caregiverOne")
        UserDefaults.standard.removeObject(forKey: CaregiverIdentityService.currentCaregiverNameKey)
        UserDefaults.standard.removeObject(forKey: CaregiverIdentityService.needsLogNamePromptKey)
        UserDefaults.standard.removeObject(forKey: "selectedCareProfileID")
        UserDefaults.standard.removeObject(forKey: FoodNavigationRestorationState.defaultsKey)
        UserDefaults.standard.removeObject(forKey: "debug.performanceSeeded.v1")
        UserDefaults.standard.removeObject(forKey: "debug.performanceSeeded.v2")
        UserDefaults.standard.removeObject(forKey: "debug.performanceSeeded.v3")
        UserDefaults.standard.removeObject(forKey: "debug.performanceSeeded.v4")
        UserDefaults.standard.removeObject(forKey: performanceSeededKey)
        PersistenceService.setICloudSyncEnabled(false)
    }

    @MainActor
    static func seedPerformanceDataIfNeeded(
        context: ModelContext,
        now: Date = Date()
    ) {
        seedIfNeeded(context: context, now: now)
        guard !UserDefaults.standard.bool(forKey: performanceSeededKey) else { return }
        guard let profile = fetch(CareProfile.self, id: childProfileID, context: context) else {
            return
        }
        let adult = fetchOrCreateProfile(
            id: adultProfileID,
            profileType: .adult,
            name: "Sample Adult",
            birthDate: calendarDate(year: 1990, month: 1, day: 1),
            sex: .unknown,
            displayColor: "purple",
            context: context
        )
        let household = HouseholdService.ensureDefaultHousehold(context: context)
        let calendar = Calendar.current
        let solidsState = SolidsTrackingService.activate(
            profileID: profile.id,
            existingState: nil,
            context: context,
            now: now,
            persist: false
        )
        solidsState.guidedStartDate = calendar.startOfDay(for: now)

        // Match the largest reported child profile so timer, Today, and solids
        // performance tests exercise production-scale history rather than a
        // smaller synthetic workload that can conceal main-actor scans.
        for index in 0..<6_000 {
            let date = calendar.date(byAdding: .hour, value: -index * 5, to: now) ?? now
            let type: EventType = switch index % 4 {
            case 0: .sleep
            case 1: .feed
            case 2: .diaper
            default: .activity
            }
            let endDate: Date? = switch type {
            case .sleep:
                date.addingTimeInterval(45 * 60)
            case .feed:
                date.addingTimeInterval(15 * 60)
            case .activity:
                date.addingTimeInterval(20 * 60)
            default:
                nil
            }
            let event = CareEvent(
                profileID: profile.id,
                type: type,
                startDate: date,
                endDate: endDate,
                caregiverName: "Sample Caregiver"
            )
            event.profileTypeSnapshot = .child
            if type == .feed {
                event.feedKind = index % 20 == 1 ? .solid : .bottle
                event.amountOz = event.feedKind == .bottle ? 4 : nil
            } else if type == .diaper {
                event.diaperKind = .wet
            } else if type == .activity {
                event.activityType = .tummyTime
            }
            context.insert(event)

            if type == .feed, event.feedKind == .solid {
                let foodIndex = index % 400
                let foodID = "performance-food-\(foodIndex)"
                let foodName = "Performance Food \(foodIndex + 1)"
                event.foodDescription = foodName
                event.solidFoodDetails = [
                    SolidFoodLogDetail(foodID: foodID, foodName: foodName)
                ]
                context.insert(SolidFoodEventItem(
                    eventID: event.id,
                    profileID: profile.id,
                    foodID: foodID,
                    foodNameSnapshot: foodName,
                    createdAt: date,
                    updatedAt: date
                ))
            }
        }

        seedAdultHealthPerformanceEvents(
            profile: adult,
            now: now,
            calendar: calendar,
            context: context
        )

        for index in 0..<400 {
            context.insert(SolidFoodProgress(
                profileID: profile.id,
                foodID: "performance-food-\(index)",
                foodNameSnapshot: "Performance Food \(index + 1)",
                status: .tried,
                lastTriedAt: now.addingTimeInterval(Double(-index) * 86_400),
                exposureCount: 1
            ))
        }

        // Exercise the user-created side of the nutrition catalog as well as
        // the bundled references. These rows catch screens that accidentally
        // observe or decode every manual label and recipe during unrelated
        // timer, Today, and primary-navigation interactions.
        var performanceCustomFoods: [SolidFoodCatalogItem] = []
        performanceCustomFoods.reserveCapacity(400)
        for index in 0..<400 {
            let food = SolidFoodCatalogItem(
                name: "Custom Performance Food \(index + 1)",
                allergenIDs: index.isMultiple(of: 20) ? [SolidsAllergen.milk.rawValue] : [],
                preparationNotes: "Prepare in an age-appropriate texture.",
                nutritionLabel: SolidManualNutritionLabel(
                    servingQuantity: 30,
                    servingUnit: .gram,
                    servingGrams: 30,
                    sourceDescription: "Sample nutrition label",
                    nutrients: SolidNutritionValues(
                        energyKilocalories: Double(20 + index % 80),
                        proteinGrams: Double(index % 8) + 0.5,
                        fatGrams: Double(index % 6) + 0.25,
                        fiberGrams: Double(index % 5) + 0.2,
                        ironMilligrams: Double(index % 4) + 0.1,
                        zincMilligrams: Double(index % 3) + 0.1,
                        calciumMilligrams: Double(10 + index % 90),
                        vitaminCMilligrams: Double(index % 25) + 0.5
                    )
                ),
                createdAt: now.addingTimeInterval(Double(-index)),
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            performanceCustomFoods.append(food)
            context.insert(food)
        }
        for index in 0..<160 {
            let food = performanceCustomFoods[index % performanceCustomFoods.count]
            context.insert(CustomSolidRecipe(
                name: "Custom Performance Recipe \(index + 1)",
                ingredients: [CustomSolidRecipeIngredient(
                    foodID: food.trackingID,
                    foodName: food.name,
                    amount: Double(15 + index % 30),
                    unit: .gram
                )],
                servings: Double(1 + index % 4),
                instructions: "Combine and serve safely.",
                createdAt: now.addingTimeInterval(Double(-index)),
                updatedAt: now.addingTimeInterval(Double(-index))
            ))
        }

        for index in 0..<120 {
            context.insert(PlannedSolidMeal(
                profileID: profile.id,
                scheduledAt: now.addingTimeInterval(Double(index - 30) * 86_400),
                title: "Performance Meal \(index + 1)",
                foodIDs: ["performance-food-\(index % 400)"],
                foodNames: ["Performance Food \((index % 400) + 1)"],
                completedEventID: index < 60 ? UUID() : nil
            ))
        }

        let todoList = HomeTodoList(
            id: todoListID,
            householdID: household.id,
            name: "Performance To-Do",
            createdAt: now,
            updatedAt: now,
            sortOrder: 0
        )
        context.insert(todoList)
        for index in 0..<600 {
            context.insert(HomeTodoItem(
                householdID: household.id,
                todoListID: todoList.id,
                title: "Performance Task \(index + 1)",
                isCompleted: index.isMultiple(of: 4),
                addedBy: "Sample Caregiver",
                completedBy: index.isMultiple(of: 4) ? "Sample Caregiver" : nil,
                completedAt: index.isMultiple(of: 4)
                    ? now.addingTimeInterval(Double(-index) * 300)
                    : nil,
                createdAt: now.addingTimeInterval(Double(-index) * 300),
                updatedAt: now.addingTimeInterval(Double(-index) * 300),
                sortOrder: index
            ))
        }

        for tripIndex in 0..<30 {
            let trip = PackingTrip(
                householdID: household.id,
                title: "Performance Trip \(tripIndex + 1)",
                startDate: now.addingTimeInterval(Double(tripIndex + 1) * 86_400),
                endDate: now.addingTimeInterval(Double(tripIndex + 3) * 86_400),
                status: tripIndex < 20 ? .upcoming : .completed
            )
            context.insert(trip)
            let traveler = TripTraveler(
                householdID: household.id,
                tripID: trip.id,
                kind: .child,
                profileID: profile.id,
                displayName: "Sample Child"
            )
            context.insert(traveler)
            for itemIndex in 0..<60 {
                context.insert(PackingItem(
                    householdID: household.id,
                    tripID: trip.id,
                    travelerID: traveler.id,
                    title: "Packing Item \(itemIndex + 1)",
                    category: PackingItemCategory.allCases[itemIndex % PackingItemCategory.allCases.count],
                    state: itemIndex.isMultiple(of: 3) ? .packed : .needed,
                    sortOrder: itemIndex
                ))
            }
        }

        if PersistenceService.save(context: context) {
            UserDefaults.standard.set(true, forKey: performanceSeededKey)
        }
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext, now: Date = Date()) {
        UserDefaults.standard.set(true, forKey: FirstRunOnboarding.completedKey)
        UserDefaults.standard.set("Sample Caregiver", forKey: "caregiverOne")
        UserDefaults.standard.set("Sample Caregiver", forKey: CaregiverIdentityService.currentCaregiverNameKey)
        PersistenceService.setICloudSyncEnabled(false)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let childBirthDate = calendar.date(byAdding: .month, value: -5, to: today) ?? today
        let dogBirthDate = calendar.date(byAdding: .month, value: -10, to: today) ?? today

        let child = fetchOrCreateProfile(
            id: childProfileID,
            profileType: .child,
            name: "Sample Child",
            birthDate: childBirthDate,
            sex: .unknown,
            displayColor: "indigo",
            context: context
        )
        if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_UI_TEST_UNOWNED_PROFILE"] == "1" {
            child.ownerIdentifier = ""
        }
        if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_UI_TEST_PROFILE_PHOTO"] == "1" {
            seedProfilePhoto(for: child, context: context)
        }
        _ = fetchOrCreateProfile(
            id: dogProfileID,
            profileType: .dog,
            name: "Sample Dog",
            birthDate: dogBirthDate,
            sex: .female,
            displayColor: "teal",
            adoptionDate: calendar.date(byAdding: .month, value: -3, to: today),
            breed: "Mixed breed",
            context: context
        )
        ProfileService.shared.switchProfile(child)

        seedCareEvents(profile: child, today: today, context: context)
        seedAppointments(profile: child, today: today, context: context)
        seedMilestones(profile: child, today: today, context: context)
        seedFoodHome(today: today, context: context)

        _ = PersistenceService.save(context: context)
    }

    @MainActor
    private static func seedProfilePhoto(for profile: CareProfile, context: ModelContext) {
        let size = CGSize(width: 240, height: 100)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: size.height))
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 80, y: 0, width: 80, height: size.height))
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 160, y: 0, width: 80, height: size.height))
        }
        guard let data = image.pngData() else { return }

        if let attachment = fetch(PhotoAttachment.self, id: profilePhotoID, context: context) {
            attachment.imageData = data
            attachment.thumbnailData = data
            attachment.updatedAt = Date()
        } else {
            context.insert(PhotoAttachment(
                id: profilePhotoID,
                profileID: profile.id,
                ownerKind: .profilePhoto,
                contentType: "image/png",
                filename: "simulator-profile-photo.png",
                imageData: data,
                thumbnailData: data
            ))
        }
        profile.profilePhotoAttachmentID = profilePhotoID
        profile.updatedAt = Date()
    }

    @MainActor
    private static func fetchOrCreateProfile(
        id: UUID,
        profileType: CareProfileType,
        name: String,
        birthDate: Date,
        sex: ProfileSex,
        displayColor: String,
        adoptionDate: Date? = nil,
        breed: String? = nil,
        context: ModelContext
    ) -> CareProfile {
        if let existing = fetch(CareProfile.self, id: id, context: context) {
            existing.name = name
            existing.profileType = profileType
            existing.birthDate = birthDate
            existing.sex = sex
            existing.displayColor = displayColor
            existing.adoptionDate = adoptionDate
            existing.breed = breed
            existing.species = profileType == .dog ? "dog" : nil
            existing.isArchived = false
            existing.updatedAt = Date()
            return existing
        }
        let profile = CareProfile(
            id: id,
            profileType: profileType,
            name: name,
            birthDate: birthDate,
            sex: sex,
            displayColor: displayColor,
            adoptionDate: adoptionDate,
            species: profileType == .dog ? "dog" : nil,
            breed: breed
        )
        context.insert(profile)
        return profile
    }

    private static func calendarDate(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @MainActor
    private static func seedAdultHealthPerformanceEvents(
        profile: CareProfile,
        now: Date,
        calendar: Calendar,
        context: ModelContext
    ) {
        let eventTypes: [EventType] = [
            .bloodPressure,
            .heartRate,
            .oxygenSaturation,
            .respiratoryRate,
            .glucose,
            .temperature,
            .growth,
            .pain,
            .symptom
        ]

        // Match a long-lived real profile closely enough to expose accidental
        // full-history work in Adult Care while keeping this simulator-only.
        for index in 0..<6_000 {
            let type = eventTypes[index % eventTypes.count]
            let date = calendar.date(byAdding: .hour, value: -index * 6, to: now) ?? now
            let event = CareEvent(
                profileID: profile.id,
                type: type,
                startDate: date,
                caregiverName: "Sample Caregiver"
            )
            event.profileTypeSnapshot = .adult

            switch type {
            case .bloodPressure:
                event.healthObservationDetails = HealthObservationDetails(
                    systolicBloodPressure: 112 + index % 18,
                    diastolicBloodPressure: 70 + index % 12
                )
            case .heartRate:
                event.healthObservationDetails = HealthObservationDetails(
                    heartRateBPM: 62 + index % 30
                )
            case .oxygenSaturation:
                event.healthObservationDetails = HealthObservationDetails(
                    oxygenSaturationPercent: Double(96 + index % 4)
                )
            case .respiratoryRate:
                event.healthObservationDetails = HealthObservationDetails(
                    respiratoryRatePerMinute: 12 + index % 7
                )
            case .glucose:
                event.healthObservationDetails = HealthObservationDetails(
                    bloodGlucoseValue: Double(82 + index % 35),
                    bloodGlucoseUnitRawValue: BloodGlucoseUnit.milligramsPerDeciliter.rawValue
                )
            case .temperature:
                event.temperatureCelsius = 36.4 + Double(index % 9) / 10
            case .growth:
                event.weightKilograms = 68 + Double(index % 30) / 10
            case .pain:
                event.healthObservationDetails = HealthObservationDetails(
                    painScore: index % 6,
                    painLocation: "General"
                )
            case .symptom:
                event.healthObservationDetails = HealthObservationDetails(
                    symptomName: "Sample symptom",
                    symptomSeverity: index % 6,
                    symptomResolved: index.isMultiple(of: 3)
                )
            default:
                break
            }
            context.insert(event)
        }
    }

    @MainActor
    private static func seedCareEvents(profile: CareProfile, today: Date, context: ModelContext) {
        let nightStart = today.addingTimeInterval(-9.5 * 3_600)
        upsertEvent(
            id: sleepEventID,
            profile: profile,
            type: .sleep,
            startDate: nightStart,
            endDate: today.addingTimeInterval(6.75 * 3_600),
            title: nil,
            notes: "Slept through one short wake-up.",
            context: context
        ) { event in
            event.sleepKind = .nightSleep
        }
        upsertEvent(
            id: activeNursingEventID,
            profile: profile,
            type: .nursing,
            startDate: Date().addingTimeInterval(-11 * 60),
            endDate: nil,
            title: nil,
            notes: "Active simulator smoke timer.",
            context: context
        ) { event in
            event.nursingSide = .left
            event.activeNursingSide = .left
            event.timerState = .running
            event.activeTimerSegmentStartDate = Date().addingTimeInterval(-11 * 60)
        }
        upsertEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            profile: profile,
            type: .feed,
            startDate: today.addingTimeInterval(8.5 * 3_600),
            endDate: today.addingTimeInterval(8.55 * 3_600),
            title: nil,
            notes: "Finished most of the bottle.",
            context: context
        ) { event in
            event.feedKind = .bottle
            event.amountOz = 5
        }
        upsertEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
            profile: profile,
            type: .diaper,
            startDate: today.addingTimeInterval(9.2 * 3_600),
            endDate: nil,
            title: nil,
            notes: "Normal change.",
            context: context
        ) { event in
            event.diaperKind = .both
            event.peeAmount = .medium
            event.pooAmount = .little
        }
        upsertEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
            profile: profile,
            type: .medicine,
            startDate: today.addingTimeInterval(10.25 * 3_600),
            endDate: nil,
            title: nil,
            notes: "Given with snack.",
            context: context
        ) { event in
            event.medicineName = "Vitamin D"
            event.dose = 1
            event.doseUnit = "drop"
        }
    }

    @MainActor
    private static func upsertEvent(
        id: UUID,
        profile: CareProfile,
        type: EventType,
        startDate: Date,
        endDate: Date?,
        title: String?,
        notes: String?,
        context: ModelContext,
        configure: (CareEvent) -> Void
    ) {
        let resolvedEndDate = type.supportsTimer ? endDate : nil
        let timeZoneIdentifier = CareTimeZoneSettings.effectiveIdentifier()
        let event = fetch(CareEvent.self, id: id, context: context) ?? CareEvent(
            id: id,
            profileID: profile.id,
            type: type,
            title: title,
            startDate: startDate,
            endDate: resolvedEndDate,
            startTimeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: resolvedEndDate == nil ? nil : timeZoneIdentifier,
            caregiverName: "Sample Caregiver",
            notes: notes
        )
        if event.modelContext == nil {
            context.insert(event)
        }
        event.profileID = profile.id
        event.profileTypeSnapshot = profile.profileType
        event.type = type
        event.title = title
        event.startDate = startDate
        event.endDate = resolvedEndDate
        event.startTimeZoneIdentifier = event.startTimeZoneIdentifier ?? timeZoneIdentifier
        event.endTimeZoneIdentifier = resolvedEndDate == nil
            ? nil
            : (event.endTimeZoneIdentifier ?? timeZoneIdentifier)
        event.caregiverName = "Sample Caregiver"
        event.notes = notes
        event.updatedAt = Date()
        configure(event)
    }

    @MainActor
    private static func seedAppointments(profile: CareProfile, today: Date, context: ModelContext) {
        let appointment = fetch(DoctorAppointment.self, id: appointmentID, context: context) ?? DoctorAppointment(
            id: appointmentID,
            profileID: profile.id,
            title: "Six month checkup",
            appointmentType: .wellnessCheck,
            startDate: today.addingTimeInterval(2 * 24 * 3_600 + 10 * 3_600),
            caregiverName: "Sample Caregiver"
        )
        if appointment.modelContext == nil {
            context.insert(appointment)
        }
        appointment.profileID = profile.id
        appointment.title = "Six month checkup"
        appointment.appointmentType = .wellnessCheck
        appointment.startDate = today.addingTimeInterval(2 * 24 * 3_600 + 10 * 3_600)
        appointment.endDate = nil
        appointment.clinicName = "Neighborhood Clinic"
        appointment.doctorName = "Care Team"
        appointment.questionsToAsk = "Ask about sleep schedule and introducing new foods."
        appointment.notes = "Bring backup bottle and growth notes."
        appointment.caregiverName = "Sample Caregiver"
        appointment.isCompleted = false
    }

    @MainActor
    private static func seedMilestones(profile: CareProfile, today: Date, context: ModelContext) {
        let milestones = [
            ("Rolled from tummy to back", MilestoneCategory.motor, -24, true),
            ("First big laugh", MilestoneCategory.social, -12, false),
            ("Tried oatmeal", MilestoneCategory.feeding, -4, false)
        ]
        for (index, milestone) in milestones.enumerated() {
            let id = UUID(uuidString: "00000000-0000-0000-0000-00000000030\(index + 2)")!
            let entry = fetch(MilestoneEntry.self, id: id, context: context) ?? MilestoneEntry(
                id: id,
                profileID: profile.id,
                title: milestone.0,
                date: today.addingTimeInterval(Double(milestone.2) * 24 * 3_600),
                category: milestone.1,
                caregiverName: "Sample Caregiver",
                isFavorite: milestone.3
            )
            if entry.modelContext == nil {
                context.insert(entry)
            }
            entry.profileID = profile.id
            entry.title = milestone.0
            entry.date = today.addingTimeInterval(Double(milestone.2) * 24 * 3_600)
            entry.category = milestone.1
            entry.notes = "Simulator smoke milestone."
            entry.caregiverName = "Sample Caregiver"
            entry.isFavorite = milestone.3
        }
    }

    @MainActor
    private static func seedFoodHome(today: Date, context: ModelContext) {
        let household = HouseholdService.ensureDefaultHousehold(context: context)
        household.name = "Sample Home"
        household.updatedAt = Date()
        let householdID = household.id

        let store = fetch(FoodStore.self, id: storeID, context: context) ?? FoodStore(
            id: storeID,
            householdID: householdID,
            name: "Neighborhood Market",
            notes: "Main weekly grocery route.",
            sortOrder: 0
        )
        if store.modelContext == nil { context.insert(store) }
        store.householdID = householdID
        store.name = "Neighborhood Market"
        store.notes = "Main weekly grocery route."
        store.isArchived = false

        seedStoreSection(
            id: produceSectionID,
            householdID: householdID,
            storeID: storeID,
            name: "Produce",
            sortOrder: 0,
            context: context
        )
        seedStoreSection(
            id: coldSectionID,
            householdID: householdID,
            storeID: storeID,
            name: "Cold Case",
            sortOrder: 1,
            context: context
        )

        seedLocation(
            id: pantryLocationID,
            householdID: householdID,
            name: "Pantry",
            type: .pantry,
            sortOrder: 0,
            context: context
        )
        seedLocation(
            id: freezerLocationID,
            householdID: householdID,
            name: "Freezer",
            type: .freezer,
            sortOrder: 1,
            context: context
        )

        let list = fetch(ShoppingList.self, id: shoppingListID, context: context) ?? ShoppingList(
            id: shoppingListID,
            householdID: householdID,
            name: "Weekly groceries",
            storeID: storeID,
            listType: .store,
            sortOrder: 0,
            notes: "Used for simulator smoke QA."
        )
        if list.modelContext == nil { context.insert(list) }
        list.householdID = householdID
        list.name = "Weekly groceries"
        list.storeID = storeID
        list.isArchived = false

        seedShoppingItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
            householdID: householdID,
            listID: shoppingListID,
            name: "Bananas",
            quantity: 6,
            unit: nil,
            sectionID: produceSectionID,
            isChecked: false,
            priority: .high,
            context: context
        )
        seedShoppingItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
            householdID: householdID,
            listID: shoppingListID,
            name: "Yogurt cups",
            quantity: 4,
            unit: "pack",
            sectionID: coldSectionID,
            isChecked: true,
            priority: .normal,
            context: context
        )

        let inventory = fetch(InventoryItem.self, id: inventoryItemID, context: context) ?? InventoryItem(
            id: inventoryItemID,
            householdID: householdID,
            name: "Applesauce pouches",
            quantity: 8,
            unit: "pouches",
            locationID: pantryLocationID
        )
        if inventory.modelContext == nil { context.insert(inventory) }
        inventory.householdID = householdID
        inventory.name = "Applesauce pouches"
        inventory.quantity = 8
        inventory.unit = "pouches"
        inventory.locationID = pantryLocationID
        inventory.notes = "Restock at 3 pouches."
        inventory.status = .available

        let mealPrep = fetch(MealPrepItem.self, id: mealPrepItemID, context: context) ?? MealPrepItem(
            id: mealPrepItemID,
            householdID: householdID,
            name: "Veggie puree cubes",
            locationID: freezerLocationID,
            servingsTotal: 12,
            servingsRemaining: 9,
            servingUnit: .portion,
            preparedDate: today.addingTimeInterval(-2 * 24 * 3_600),
            notes: "Carrot and sweet potato."
        )
        if mealPrep.modelContext == nil { context.insert(mealPrep) }
        mealPrep.householdID = householdID
        mealPrep.name = "Veggie puree cubes"
        mealPrep.locationID = freezerLocationID
        mealPrep.servingsTotal = 12
        mealPrep.servingsRemaining = 9
        mealPrep.servingUnit = .portion
        mealPrep.isArchived = false

        let usageID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let usage = fetch(MealPrepUsage.self, id: usageID, context: context) ?? MealPrepUsage(
            id: usageID,
            householdID: householdID,
            mealPrepItemID: mealPrepItemID,
            dateTime: today.addingTimeInterval(8 * 3_600),
            servingsUsed: 1,
            notes: "Served with breakfast."
        )
        if usage.modelContext == nil { context.insert(usage) }
        usage.householdID = householdID
        usage.mealPrepItemID = mealPrepItemID
    }

    @MainActor
    private static func seedStoreSection(
        id: UUID,
        householdID: UUID,
        storeID: UUID,
        name: String,
        sortOrder: Int,
        context: ModelContext
    ) {
        let section = fetch(FoodStoreSection.self, id: id, context: context) ?? FoodStoreSection(
            id: id,
            householdID: householdID,
            storeID: storeID,
            name: name,
            sortOrder: sortOrder
        )
        if section.modelContext == nil { context.insert(section) }
        section.householdID = householdID
        section.storeID = storeID
        section.name = name
        section.sortOrder = sortOrder
    }

    @MainActor
    private static func seedLocation(
        id: UUID,
        householdID: UUID,
        name: String,
        type: InventoryLocationType,
        sortOrder: Int,
        context: ModelContext
    ) {
        let location = fetch(InventoryLocation.self, id: id, context: context) ?? InventoryLocation(
            id: id,
            householdID: householdID,
            name: name,
            locationType: type,
            sortOrder: sortOrder
        )
        if location.modelContext == nil { context.insert(location) }
        location.householdID = householdID
        location.name = name
        location.locationType = type
        location.sortOrder = sortOrder
        location.isArchived = false
    }

    @MainActor
    private static func seedShoppingItem(
        id: UUID,
        householdID: UUID,
        listID: UUID,
        name: String,
        quantity: Double,
        unit: String?,
        sectionID: UUID,
        isChecked: Bool,
        priority: ShoppingItemPriority,
        context: ModelContext
    ) {
        let item = fetch(ShoppingListItem.self, id: id, context: context) ?? ShoppingListItem(
            id: id,
            householdID: householdID,
            shoppingListID: listID,
            name: name,
            quantity: quantity,
            unit: unit,
            storeSectionID: sectionID,
            isChecked: isChecked,
            checkedAt: isChecked ? Date() : nil,
            priority: priority,
            addedBy: "Sample Caregiver"
        )
        if item.modelContext == nil { context.insert(item) }
        item.householdID = householdID
        item.shoppingListID = listID
        item.name = name
        item.quantity = quantity
        item.unit = unit
        item.storeSectionID = sectionID
        item.isChecked = isChecked
        item.checkedAt = isChecked ? Date() : nil
        item.priority = priority
        item.addedBy = "Sample Caregiver"
    }

    @MainActor
    private static func fetch<Model: PersistentModel & Identifiable>(
        _ type: Model.Type,
        id: UUID,
        context: ModelContext
    ) -> Model? where Model.ID == UUID {
        var descriptor = FetchDescriptor<Model>(
            predicate: #Predicate<Model> { model in
                model.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
#endif

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
}
