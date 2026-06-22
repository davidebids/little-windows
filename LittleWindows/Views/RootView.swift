import SwiftData
import SwiftUI

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
        case .vaccine: .mint
        case .glucose: .red
        case .custom: .purple
        }
    }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.horizontal, 4)
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
        cancelAction: (() -> Void)? = nil
    ) -> some View {
        let estimatedHeight = max(320, min(700, 220 + CGFloat(options.count) * 78))
        return sheet(isPresented: isPresented) {
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
    let id = UUID()
    var title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color
    var role: ButtonRole?
    var isSelected: Bool
    var action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accent,
        role: ButtonRole? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.role = role
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
    @AppStorage(FirstRunOnboarding.completedKey) private var hasCompletedInitialOnboarding = false
    @AppStorage(CaregiverIdentityService.currentCaregiverNameKey) private var currentCaregiverName = ""
    @AppStorage(CaregiverIdentityService.needsLogNamePromptKey) private var needsLogNamePrompt = false
    @StateObject private var router = DeepLinkRouter.shared
    @State private var shouldOpenSettingsAfterOnboarding = false
    @State private var hasCheckedInitialOnboardingState = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Group {
                if router.selectedTab == .today {
                    NavigationStack { TodayView() }
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
                .tabItem { Label("Food", systemImage: "cart.fill") }
                .tag(LittleWindowsTab.food)

            Group {
                if router.selectedTab == .reports {
                    NavigationStack { ReportsView() }
                } else {
                    Color.clear
                }
            }
                .tabItem { Label("Reports", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(LittleWindowsTab.reports)

            Group {
                if router.selectedTab == .milestones {
                    NavigationStack { MilestonesView() }
                } else {
                    Color.clear
                }
            }
                .tabItem { Label("Milestones", systemImage: "heart.text.clipboard.fill") }
                .tag(LittleWindowsTab.milestones)

            Group {
                if router.selectedTab == .nightLight {
                    NavigationStack { NightLightView() }
                } else {
                    Color.clear
                }
            }
                .tabItem { Label("Night Light", systemImage: "lightbulb.fill") }
                .tag(LittleWindowsTab.nightLight)
        }
        .tint(AppTheme.accent)
        .environmentObject(router)
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    guard hasCheckedInitialOnboardingState else { return false }
                    return FirstRunOnboarding.shouldPresent(
                        hasCompleted: hasCompletedInitialOnboarding,
                        profiles: profiles
                    )
                },
                set: { _ in }
            )
        ) {
            FirstRunOnboardingView(
                completeOnboarding: {
                    hasCompletedInitialOnboarding = true
                    router.selectedTab = .today
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
            Text("Enter the caregiver name this device should use for new care entries.")
        }
        .onOpenURL { url in
            route(url)
        }
        .task {
            markOnboardingCompleteForExistingData()
            hasCheckedInitialOnboardingState = true
            if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_TAB"] == "insights" {
                router.selectedReportsMode = .summary
                router.selectedTab = .reports
            }
            if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_TAB"] == "history" {
                router.selectedReportsMode = .day
                router.selectedTab = .reports
            }
            if let value = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_URL"],
               let url = URL(string: value) {
                route(url)
            }
            consumePendingSystemAction()
        }
        .onChange(of: profiles.count) { _, _ in
            markOnboardingCompleteForExistingData()
            hasCheckedInitialOnboardingState = true
        }
        .onChange(of: hasCompletedInitialOnboarding) { _, completed in
            guard completed, shouldOpenSettingsAfterOnboarding else { return }
            shouldOpenSettingsAfterOnboarding = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                router.showingSettings = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumePendingSystemAction() }
        }
    }

    private func markOnboardingCompleteForExistingData() {
        guard !hasCompletedInitialOnboarding, !profiles.isEmpty else { return }
        hasCompletedInitialOnboarding = true
    }

    private func route(_ url: URL) {
        #if DEBUG
        if DebugSimulatorSmokeSeedService.isResetEmpty(url), DebugSimulatorSmokeSeedService.isEnabled {
            DebugSimulatorSmokeSeedService.resetEmpty(context: modelContext)
            hasCompletedInitialOnboarding = false
            hasCheckedInitialOnboardingState = true
            router.selectedTab = .today
            return
        }
        if DebugSimulatorSmokeSeedService.canHandle(url), DebugSimulatorSmokeSeedService.isEnabled {
            DebugSimulatorSmokeSeedService.seedIfNeeded(context: modelContext)
            hasCompletedInitialOnboarding = true
            router.selectedTab = .today
            return
        }
        #endif
        router.route(url)
    }

    private func consumePendingSystemAction() {
        if let url = IntegrationCommandStore.consumePendingURL() {
            route(url)
        }
    }
}

enum FirstRunOnboarding {
    static let completedKey = "hasCompletedInitialOnboarding"

    static func shouldPresent(hasCompleted: Bool, profiles: [CareProfile]) -> Bool {
        !hasCompleted && profiles.isEmpty
    }
}

private enum FirstRunOnboardingStep: Int {
    case caregiver
    case profile
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
    @State private var sex = BabySex.unknown
    @State private var hasAdoptionDate = false
    @State private var adoptionDate = Date()
    @State private var breed = ""
    @State private var validationMessage: String?

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
        profileType == .dog ? "Dog name" : "Child name"
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: step == .caregiver ? "sparkles" : profileType.systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            Text(step == .caregiver ? "Set up your care home" : "Add the first profile")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(step == .caregiver
                ? "Little Windows uses your name on logs so the history makes sense later."
                : "Choose whether you are tracking a child or dog, then add the details needed for daily care.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caregiverStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Caregiver")
                    .font(.headline)

                TextField("Your name", text: $primaryCaregiverName)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)

                Text("This name is attached to care entries created on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .appSurface()

            Button {
                guard isCaregiverStepValid else {
                    validationMessage = "Enter your name to continue."
                    return
                }
                step = .profile
            } label: {
                Label("Continue", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isCaregiverStepValid)

            Button {
                importBackupInstead()
            } label: {
                Label("Import JSON backup instead", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .onAppear {
            if primaryCaregiverName.isEmpty, caregiverOne != "Caregiver 1" {
                primaryCaregiverName = caregiverOne
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

                TextField(profileNamePrompt, text: $profileName)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)

                DatePicker(
                    profileType == .dog ? "Birthday or best estimate" : "Birthdate",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )

                HStack {
                    Text("Sex")
                    Spacer()
                    Picker("Sex", selection: $sex) {
                        ForEach(BabySex.allCases) { value in
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
            validationMessage = "Enter a \(profileType == .dog ? "dog" : "child") name."
            return
        }

        caregiverOne = trimmedPrimaryCaregiverName
        CaregiverIdentityService.seedCurrentCaregiverNameIfNeeded(from: trimmedPrimaryCaregiverName)

        if profileType == .dog {
            profileService.createDogProfile(
                name: trimmedProfileName,
                birthDate: birthDate,
                sex: sex,
                adoptionDate: hasAdoptionDate ? adoptionDate : nil,
                breed: breed.nilIfBlank,
                displayColor: "teal",
                context: modelContext
            )
        } else {
            profileService.createChildProfile(
                name: trimmedProfileName,
                birthDate: birthDate,
                sex: sex,
                displayColor: "indigo",
                context: modelContext
            )
        }

        completeOnboarding()
    }
}

#if DEBUG
enum DebugSimulatorSmokeSeedService {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LITTLE_WINDOWS_UI_TESTING"] == "1"
    }

    static let childProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let dogProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let sleepEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let activeNursingEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    static let appointmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    static let shoppingListID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    static let inventoryItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    static let mealPrepItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    static let storeID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!

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

    @MainActor
    static func resetEmpty(context: ModelContext) {
        try? DataExportImportService.deleteAll(context: context)
        UserDefaults.standard.removeObject(forKey: FirstRunOnboarding.completedKey)
        UserDefaults.standard.removeObject(forKey: "caregiverOne")
        UserDefaults.standard.removeObject(forKey: CaregiverIdentityService.currentCaregiverNameKey)
        UserDefaults.standard.removeObject(forKey: CaregiverIdentityService.needsLogNamePromptKey)
        UserDefaults.standard.removeObject(forKey: "selectedCareProfileID")
        PersistenceService.setICloudSyncEnabled(false)
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

        try? context.save()
        PersistenceService.recordLocalSave()
    }

    @MainActor
    private static func fetchOrCreateProfile(
        id: UUID,
        profileType: CareProfileType,
        name: String,
        birthDate: Date,
        sex: BabySex,
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
        configure: (BabyEvent) -> Void
    ) {
        let resolvedEndDate = type.supportsTimer ? endDate : nil
        let event = fetch(BabyEvent.self, id: id, context: context) ?? BabyEvent(
            id: id,
            profileID: profile.id,
            type: type,
            title: title,
            startDate: startDate,
            endDate: resolvedEndDate,
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
