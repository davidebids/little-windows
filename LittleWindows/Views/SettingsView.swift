import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum DataMutationScope: Equatable {
    case localDevice
    case privateICloud
    case sharedFamilyOwner
    case sharedFamilyParticipant
    case sharedFamilyUnknownRole

    static func resolve(
        isUsingCloudKitStore: Bool,
        startupMode: FamilySyncMode,
        currentMode: FamilySyncMode,
        familyRole: FamilyShareRole
    ) -> DataMutationScope {
        if isUsingCloudKitStore {
            return .privateICloud
        }
        guard startupMode == .sharedFamilySync,
              currentMode == .sharedFamilySync else {
            return .localDevice
        }
        switch familyRole {
        case .owner:
            return .sharedFamilyOwner
        case .participant:
            return .sharedFamilyParticipant
        case .none:
            return .sharedFamilyUnknownRole
        }
    }

    var allowsBulkMutation: Bool {
        self != .sharedFamilyParticipant && self != .sharedFamilyUnknownRole
    }

    var deleteButtonTitle: String {
        switch self {
        case .localDevice:
            return "Delete Data on This Device"
        case .privateICloud:
            return "Delete Synced Data Everywhere"
        case .sharedFamilyOwner:
            return "Delete Shared Family Data"
        case .sharedFamilyParticipant, .sharedFamilyUnknownRole:
            return "Delete All Data"
        }
    }

    var scopeTitle: String {
        switch self {
        case .localDevice:
            return "This device only"
        case .privateICloud:
            return "Every device on this Apple Account"
        case .sharedFamilyOwner:
            return "Every Family Sync caregiver"
        case .sharedFamilyParticipant:
            return "Family Sync participant"
        case .sharedFamilyUnknownRole:
            return "Family Sync role unavailable"
        }
    }

    var dataSectionExplanation: String {
        switch self {
        case .localDevice:
            return "Imports and deletions affect only the local store currently open on this device."
        case .privateICloud:
            return "This store uses private iCloud Sync. Imports and deletions will propagate to other devices signed into this Apple Account."
        case .sharedFamilyOwner:
            return "You own this Family Sync space. Imports and deletions will propagate to every accepted caregiver."
        case .sharedFamilyParticipant:
            return "Only the Family Sync owner can replace or erase the entire shared dataset. Open Family Sync to leave and optionally delete this device's downloaded copy."
        case .sharedFamilyUnknownRole:
            return "Little Windows could not confirm who owns this Family Sync space. Bulk import and deletion are disabled until the role is available."
        }
    }

    var destructiveDetail: String {
        switch self {
        case .localDevice:
            return "Only the data in the store currently open on this device will change."
        case .privateICloud:
            return "The change will sync to every device signed into this Apple Account."
        case .sharedFamilyOwner:
            return "The change will be published to every accepted Family Sync caregiver."
        case .sharedFamilyParticipant:
            return "Participants cannot replace or erase the complete shared family dataset."
        case .sharedFamilyUnknownRole:
            return "Little Windows must confirm the Family Sync owner before changing the complete dataset."
        }
    }

    var successSuffix: String {
        switch self {
        case .localDevice:
            return "on this device."
        case .privateICloud:
            return "and the change will sync to your other devices."
        case .sharedFamilyOwner:
            return "and the change will sync to family caregivers."
        case .sharedFamilyParticipant, .sharedFamilyUnknownRole:
            return "."
        }
    }
}

private enum DestructiveDataAction {
    case importBackup
    case deleteAll
}

private struct PendingDestructiveDataOperation: Identifiable {
    let id = UUID()
    var action: DestructiveDataAction
    var scope: DataMutationScope

    var title: String {
        switch action {
        case .importBackup:
            return "Replace Current Data?"
        case .deleteAll:
            return scope.deleteButtonTitle + "?"
        }
    }

    var buttonTitle: String {
        switch action {
        case .importBackup:
            return "Replace Data"
        case .deleteAll:
            return scope.deleteButtonTitle
        }
    }

    var message: String {
        let actionDescription: String
        switch action {
        case .importBackup:
            actionDescription = "This backup will replace all current Little Windows data."
        case .deleteAll:
            actionDescription = "This will delete all Little Windows data."
        }
        return "\(actionDescription)\n\n\(scope.scopeTitle): \(scope.destructiveDetail)\n\nA local automatic recovery backup will be created first."
    }
}

private enum SettingsRoute: Hashable {
    case monthlyAgeGuides
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]

    @StateObject private var profileService = ProfileService.shared
    @StateObject private var router = DeepLinkRouter.shared
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument = BackupDocument()
    @State private var pendingImportData: Data?
    @State private var pendingDestructiveOperation: PendingDestructiveDataOperation?
    @State private var statusMessage: String?
    @AppStorage(PersistenceService.familySyncModeKey)
    private var currentSyncModeRawValue = FamilySyncMode.privateICloudSync.rawValue

    private var selectedProfile: CareProfile? {
        profileService.selectedProfile(in: profiles)
    }

    private var dataMutationScope: DataMutationScope {
        let familyRole = CloudKitSharingService.shared
            .currentFamilySyncStatus()
            .role
        return DataMutationScope.resolve(
            isUsingCloudKitStore: PersistenceService.isUsingCloudKitStore,
            startupMode: PersistenceService.syncModeAtStartup,
            currentMode: FamilySyncMode(rawValue: currentSyncModeRawValue)
                ?? PersistenceService.familySyncMode(),
            familyRole: familyRole
        )
    }

    var body: some View {
        Form {
            if let profile = selectedProfile {
                ProfileSettingsSection(profile: profile)
            }

            Section {
                NavigationLink {
                    LazySettingsDestination {
                        ManageProfilesView()
                    }
                } label: {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selectedProfile?.name ?? "Not tracking care")
                            Text(selectedProfile == nil ? "Add a care profile" : "Switch or edit")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } label: {
                        Label("Care Profiles", systemImage: "person.2.fill")
                    }
                }
            } header: {
                Label("Care Profiles", systemImage: "person.crop.circle")
            } footer: {
                if selectedProfile == nil {
                    Text("Home, Food, and Night Light work without a care profile. Add one whenever you want to track care for a child, adult, or dog.")
                }
            }

            Section("Your name") {
                CaregiverNameFields(
                    detail: "Your name appears on household assignments and activity, and on new care entries when a profile is active. It follows this Apple Account when iCloud Sync is on."
                )
            }

            if let selectedProfile {
                CareTimeZoneSettingsNavigationSection()

                if selectedProfile.profileType == .child {
                    ChildSleepSettingsNavigationSection(profile: selectedProfile)
                }
            }

            SyncSettingsSection(hasActiveCareProfile: selectedProfile != nil)

            if selectedProfile != nil {
                WatchSettingsSection(profile: selectedProfile)
            }

            Section {
                NavigationLink {
                    LazySettingsDestination {
                        FoodReminderSettingsLauncher()
                    }
                } label: {
                    Label("Food & Home reminders", systemImage: "bell.badge.fill")
                }
            } header: {
                Label("Food & Home", systemImage: "fork.knife")
            } footer: {
                Text("Food & Home records are household-level and sync through the same private iCloud store when iCloud Sync is available.")
            }

            if selectedProfile != nil {
                AppointmentSettingsNavigationSection(profile: selectedProfile)
            }

            if let selectedProfile, selectedProfile.profileType == .child {
                MonthlyAgeGuideSettingsNavigationSection()
            }

            Section {
                if selectedProfile != nil {
                    NavigationLink {
                        LazySettingsDestination {
                            CareReportExportView()
                        }
                    } label: {
                        Label("Export care report", systemImage: "doc.text.magnifyingglass")
                    }
                }
                Button("Export JSON backup", systemImage: "square.and.arrow.up") {
                    export()
                }
                Button("Import JSON backup", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
                .disabled(!dataMutationScope.allowsBulkMutation)
                Button(dataMutationScope.deleteButtonTitle, systemImage: "trash", role: .destructive) {
                    pendingDestructiveOperation = PendingDestructiveDataOperation(
                        action: .deleteAll,
                        scope: dataMutationScope
                    )
                }
                .disabled(!dataMutationScope.allowsBulkMutation)

                if dataMutationScope == .sharedFamilyParticipant
                    || dataMutationScope == .sharedFamilyUnknownRole {
                    Button("Review Family Sync", systemImage: "person.2.badge.gearshape.fill") {
                        router.showingFamilySyncSettings = true
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text(dataMutationScope.dataSectionExplanation)
            }

            SettingsSupportAndPrivacySection()
            SettingsBuildInfoFooter()
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .navigationDestination(isPresented: $router.showingFamilySyncSettings) {
            FamilySyncSettingsView()
        }
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .monthlyAgeGuides:
                MonthlyAgeGuideSettingsView(profile: selectedProfile)
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Little-Windows-Backup"
        ) { result in
            if case .failure(let error) = result {
                statusMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .appActionSheet(
            isPresented: Binding(
                get: { pendingDestructiveOperation != nil },
                set: { if !$0 { pendingDestructiveOperation = nil } }
            ),
            title: pendingDestructiveOperation?.title ?? "Confirm Data Change",
            message: pendingDestructiveOperation?.message,
            systemImage: "exclamationmark.triangle.fill",
            tint: .red,
            options: pendingDestructiveOperation.map { operation in
                let subtitle: String
                let systemImage: String
                switch operation.action {
                case .importBackup:
                    subtitle = "Replace the current local data with the selected backup."
                    systemImage = "square.and.arrow.down.fill"
                case .deleteAll:
                    subtitle = "Permanently remove the data covered by this action."
                    systemImage = "trash.fill"
                }
                return [AppActionSheetOption(
                    title: operation.buttonTitle,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    tint: .red,
                    role: .destructive
                ) {
                    pendingDestructiveOperation = nil
                    switch operation.action {
                    case .importBackup:
                        performPendingImport(scope: operation.scope)
                    case .deleteAll:
                        deleteAll(scope: operation.scope)
                    }
                }]
            } ?? [],
            cancelAction: {
                if let operation = pendingDestructiveOperation,
                   case .importBackup = operation.action {
                    pendingImportData = nil
                }
                pendingDestructiveOperation = nil
            }
        )
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
        do {
            exportDocument = BackupDocument(data: try DataExportImportService.exportData(context: modelContext))
            showingExporter = true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try DataExportImportService.validateBackupData(data)
            pendingImportData = data
            pendingDestructiveOperation = PendingDestructiveDataOperation(
                action: .importBackup,
                scope: dataMutationScope
            )
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func performPendingImport(scope: DataMutationScope) {
        guard scope.allowsBulkMutation,
              dataMutationScope == scope,
              let data = pendingImportData else {
            pendingImportData = nil
            statusMessage = "Import was stopped because the active sync scope changed. Review Data settings and try again."
            return
        }
        do {
            try DataExportImportService.importData(data, context: modelContext)
            pendingImportData = nil
            statusMessage = "Backup imported \(scope.successSuffix)"
            SystemIntegrationReconciler.requestReconciliation()
        } catch {
            pendingImportData = nil
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteAll(scope: DataMutationScope) {
        guard scope.allowsBulkMutation,
              dataMutationScope == scope else {
            statusMessage = "Deletion was stopped because the active sync scope changed. Review Data settings and try again."
            return
        }
        do {
            _ = try DataExportImportService.createAutomaticRecoveryBackup(
                context: modelContext,
                reason: "before-delete-all"
            )
            try DataExportImportService.deleteAll(context: modelContext)
            UserDefaults.standard.removeObject(forKey: FirstRunOnboarding.completedKey)
            statusMessage = "All Little Windows data was deleted \(scope.successSuffix)"
            SystemIntegrationReconciler.requestReconciliation()
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

struct LazySettingsDestination<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

private struct CareTimeZoneSettingsNavigationSection: View {
    @AppStorage(CareTimeZoneSettings.modeKey)
    private var modeRawValue = CareTimeZoneMode.automatic.rawValue
    @AppStorage(CareTimeZoneSettings.manualIdentifierKey)
    private var manualIdentifier = TimeZone.autoupdatingCurrent.identifier

    private var mode: CareTimeZoneMode {
        CareTimeZoneMode(rawValue: modeRawValue) ?? .automatic
    }

    private var selectedTimeZone: TimeZone {
        if mode == .manual, let value = TimeZone(identifier: manualIdentifier) {
            return value
        }
        return .autoupdatingCurrent
    }

    var body: some View {
        Section {
            NavigationLink {
                CareTimeZoneSettingsView()
            } label: {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(mode.displayName)
                        Text(CareTimeZoneSettings.displayName(for: selectedTimeZone))
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                } label: {
                    Label("Time zone", systemImage: "globe.americas.fill")
                }
            }
        } header: {
            Text("Dates & times")
        } footer: {
            Text("New care entries remember the time zone where each timestamp was recorded, so travel does not change historical clock times or daily totals.")
        }
    }
}

private struct CareTimeZoneSettingsView: View {
    @AppStorage(CareTimeZoneSettings.modeKey)
    private var modeRawValue = CareTimeZoneMode.automatic.rawValue
    @AppStorage(CareTimeZoneSettings.manualIdentifierKey)
    private var manualIdentifier = TimeZone.autoupdatingCurrent.identifier

    private var mode: Binding<CareTimeZoneMode> {
        Binding(
            get: { CareTimeZoneMode(rawValue: modeRawValue) ?? .automatic },
            set: { modeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Time zone", selection: mode) {
                    ForEach(CareTimeZoneMode.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(
                    "Device detected",
                    value: CareTimeZoneSettings.displayName(for: .autoupdatingCurrent)
                )

                if mode.wrappedValue == .manual {
                    NavigationLink {
                        TimeZonePickerView(selection: $manualIdentifier)
                    } label: {
                        LabeledContent(
                            "Override",
                            value: TimeZone(identifier: manualIdentifier)
                                .map { CareTimeZoneSettings.displayName(for: $0) }
                                ?? manualIdentifier
                        )
                    }
                }
            } footer: {
                Text("Automatic follows the device and captures a concrete zone on every new start and end time. Use an override if the device has not switched zones yet or you want to log in another location's time.")
            }

            Section("Existing entries") {
                Text("Open any care entry to review or change its start and end time zones. Changing this setting does not rewrite history.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Time Zone")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode.wrappedValue) { _, newValue in
            if newValue == .manual, TimeZone(identifier: manualIdentifier) == nil {
                manualIdentifier = TimeZone.autoupdatingCurrent.identifier
            }
        }
    }
}

struct TimeZonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var searchText = ""

    private static let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted { first, second in
        let firstZone = TimeZone(identifier: first) ?? .gmt
        let secondZone = TimeZone(identifier: second) ?? .gmt
        let firstOffset = firstZone.secondsFromGMT()
        let secondOffset = secondZone.secondsFromGMT()
        if firstOffset != secondOffset { return firstOffset < secondOffset }
        return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
    }

    private var filteredIdentifiers: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.identifiers }
        return Self.identifiers.filter { identifier in
            guard let timeZone = TimeZone(identifier: identifier) else { return false }
            return identifier.localizedCaseInsensitiveContains(query)
                || CareTimeZoneSettings.displayName(for: timeZone)
                    .localizedCaseInsensitiveContains(query)
                || (timeZone.abbreviation()?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            Section("Suggested") {
                timeZoneButton(TimeZone.autoupdatingCurrent.identifier)
                if selection != TimeZone.autoupdatingCurrent.identifier {
                    timeZoneButton(selection)
                }
            }

            Section("All time zones") {
                ForEach(filteredIdentifiers, id: \.self) { identifier in
                    timeZoneButton(identifier)
                }
            }
        }
        .navigationTitle("Choose Time Zone")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "City, region, or abbreviation")
    }

    @ViewBuilder
    private func timeZoneButton(_ identifier: String) -> some View {
        if let timeZone = TimeZone(identifier: identifier) {
            Button {
                selection = identifier
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CareTimeZoneSettings.displayName(for: timeZone))
                            .foregroundStyle(.primary)
                        Text("\(identifier) · \(CareTimeZoneSettings.gmtOffsetText(for: timeZone))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selection == identifier {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
    }
}

private struct ChildSleepSettingsRenderState {
    var currentPrediction: SleepPrediction?
    var currentPressure: SleepPressure?
    var selectedProfileIsSleeping: Bool
    var notificationStatus: String
    var sleepPressureStatus: String
    var sleepPressurePreviewText: String
    var notificationPreview: LittleWindowNotificationCopy

    static let placeholder = ChildSleepSettingsRenderState(
        currentPrediction: nil,
        currentPressure: nil,
        selectedProfileIsSleeping: false,
        notificationStatus: "Checking next alert",
        sleepPressureStatus: "Checking pressure",
        sleepPressurePreviewText: "Checking recent sleep rhythm.",
        notificationPreview: LittleWindowNotificationCopy(
            title: "Nap window soon",
            body: "Little Windows will show the next alert preview after it checks recent sleep."
        )
    )
}

private struct ChildSleepSettingsNavigationSection: View {
    let profile: CareProfile?

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    ChildSleepSettingsView(profile: profile)
                }
            } label: {
                Label("Sleep predictions and alerts", systemImage: "moon.stars.fill")
            }
        } header: {
            Label("Prediction", systemImage: "moon.stars.fill")
        } footer: {
            Text("Sleep predictions are planning aids based on local logs, not medical advice.")
        }
    }
}

private struct ChildSleepSettingsView: View {
    let profile: CareProfile?

    var body: some View {
        Form {
            ChildSleepSettingsSections(profile: profile)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChildSleepSettingsSections: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var events: [CareEvent]
    @Query private var records: [SleepPredictionRecord]

    let profile: CareProfile?

    @AppStorage("feedAdjustmentEnabled") private var feedAdjustmentEnabled = true
    @AppStorage("nursingAdjustmentEnabled") private var nursingAdjustmentEnabled = true
    @AppStorage("bedtimePredictionEnabled") private var bedtimePredictionEnabled = true
    @AppStorage("predictionNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("sleepPressureAlertsEnabled") private var sleepPressureAlertsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 10
    @AppStorage("littleWindowNapAlertsEnabled") private var napAlertsEnabled = true
    @AppStorage("littleWindowBedtimeAlertsEnabled") private var bedtimeAlertsEnabled = true
    @AppStorage("littleWindowConfidenceThreshold") private var confidenceThresholdRawValue =
        LittleWindowConfidenceThreshold.medium.rawValue
    @AppStorage("customWakeMinimum") private var customWakeMinimum = 0.0
    @AppStorage("customWakeMaximum") private var customWakeMaximum = 0.0

    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingAlertPermissionPrompt = false
    @State private var showingPermissionDenied = false
    @State private var pendingNotificationRefresh: Task<Void, Never>?
    @State private var cachedRenderState = ChildSleepSettingsRenderState.placeholder
    @State private var renderRefreshTask: Task<Void, Never>?

    init(profile: CareProfile?) {
        self.profile = profile
        let selectedProfileID = profile?.id
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        let recentCutoff = Calendar.current.date(
            byAdding: .day,
            value: -45,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        var eventDescriptor = FetchDescriptor<CareEvent>(
            predicate: #Predicate<CareEvent> { event in
                event.profileID == selectedProfileID && event.startDate >= recentCutoff
            },
            sortBy: [SortDescriptor(\CareEvent.startDate, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 900
        _events = Query(eventDescriptor)

        var recordDescriptor = FetchDescriptor<SleepPredictionRecord>(
            predicate: #Predicate<SleepPredictionRecord> { record in
                record.profileID == selectedProfileID
                    && (record.actualSleepEventID == nil || record.generatedAt >= recentCutoff)
            },
            sortBy: [SortDescriptor(\SleepPredictionRecord.generatedAt, order: .reverse)]
        )
        recordDescriptor.fetchLimit = 120
        _records = Query(recordDescriptor)
    }

    var body: some View {
        let state = cachedRenderState

        Group {
            Section("Prediction") {
                Toggle("Use feed timing", isOn: $feedAdjustmentEnabled)
                    .onChange(of: feedAdjustmentEnabled) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }
                Toggle("Use nursing timing", isOn: $nursingAdjustmentEnabled)
                    .onChange(of: nursingAdjustmentEnabled) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }
                Toggle("Predict bedtime", isOn: $bedtimePredictionEnabled)
                    .onChange(of: bedtimePredictionEnabled) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }
                NavigationLink("Wake-window tuning") {
                    LazySettingsDestination {
                        WakeWindowTuningView(
                            minimum: $customWakeMinimum,
                            maximum: $customWakeMaximum
                        )
                    }
                }
            }

            Section {
                Toggle(
                    "Enable Little Window Alerts",
                    isOn: Binding(
                        get: { notificationsEnabled },
                        set: { enabled in
                            if enabled {
                                showingAlertPermissionPrompt = true
                            } else {
                                notificationsEnabled = false
                                Task {
                                    await notificationManager.cancelAllPendingLittleWindowAlerts()
                                }
                            }
                        }
                    )
                )

                if notificationsEnabled {
                    Picker("Alert timing", selection: $notificationLeadMinutes) {
                        Text("At window start").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                        Text("20 minutes before").tag(20)
                        Text("30 minutes before").tag(30)
                    }
                    .onChange(of: notificationLeadMinutes) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }

                    Toggle("Nap alerts", isOn: $napAlertsEnabled)
                        .onChange(of: napAlertsEnabled) { _, _ in
                            scheduleRenderStateRefresh()
                            scheduleNotificationRefresh()
                        }
                    Toggle("Bedtime alerts", isOn: $bedtimeAlertsEnabled)
                        .onChange(of: bedtimeAlertsEnabled) { _, _ in
                            scheduleRenderStateRefresh()
                            scheduleNotificationRefresh()
                        }

                    Picker("Minimum confidence", selection: $confidenceThresholdRawValue) {
                        ForEach(LittleWindowConfidenceThreshold.allCases) { threshold in
                            Text(threshold.displayName).tag(threshold.rawValue)
                        }
                    }
                    .onChange(of: confidenceThresholdRawValue) { _, _ in
                        scheduleRenderStateRefresh()
                        scheduleNotificationRefresh()
                    }

                    LabeledContent("Next alert") {
                        Text(state.notificationStatus)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if notificationManager.authorizationStatus == .denied {
                    Button("Open iOS Notification Settings", systemImage: "gear") {
                        openNotificationSettings()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notification preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(state.notificationPreview.title)
                        .font(.subheadline.weight(.semibold))
                    Text(state.notificationPreview.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } header: {
                Label("Little Window Alerts", systemImage: "bell.badge.fill")
            } footer: {
                Text("Little Windows can remind you before the next likely nap or bedtime window. Alerts are based on logged patterns and are not medical advice.")
            }

            Section {
                Toggle(
                    "Enable Sleep Pressure Alerts",
                    isOn: Binding(
                        get: { sleepPressureAlertsEnabled },
                        set: { enabled in
                            if enabled {
                                Task { await enableSleepPressureAlerts() }
                            } else {
                                sleepPressureAlertsEnabled = false
                                Task {
                                    await notificationManager.cancelAllPendingSleepPressureAlerts()
                                }
                            }
                        }
                    )
                )

                if sleepPressureAlertsEnabled {
                    LabeledContent("Next pressure alert") {
                        Text(state.sleepPressureStatus)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pressure preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label(
                        state.currentPressure?.band.statusText ?? "Learning rhythm",
                        systemImage: state.currentPressure?.band.systemImage ?? "sparkle.magnifyingglass"
                    )
                    .font(.subheadline.weight(.semibold))
                    Text(state.sleepPressurePreviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } header: {
                Label("Sleep Pressure Alerts", systemImage: "gauge.with.dots.needle.50percent")
            } footer: {
                Text("These are separate from Little Window Alerts. They use the current pressure band and are hidden for babies under 4 months while Little Windows is learning rhythm.")
            }
        }
        .appActionSheet(
            isPresented: $showingAlertPermissionPrompt,
            title: "Turn on Little Window Alerts?",
            message: "Little Windows can remind you before the next likely nap or bedtime window.",
            systemImage: "bell.badge.fill",
            tint: .purple,
            options: [
                AppActionSheetOption(
                    title: "Allow Notifications",
                    subtitle: "Continue to the iOS notification permission prompt.",
                    systemImage: "bell.badge.fill",
                    tint: .purple
                ) {
                    Task { await enableLittleWindowAlerts() }
                }
            ],
            cancelTitle: "Not Now"
        )
        .alert("Notifications are turned off", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                openNotificationSettings()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can allow Little Window Alerts in iOS Settings whenever you're ready.")
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
            await notificationManager.configure()
            await refreshRenderState()
        }
        .onChange(of: profileID) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: events.count) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: records.count) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: sleepPressureAlertsEnabled) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: notificationsEnabled) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: customWakeMinimum) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onChange(of: customWakeMaximum) { _, _ in
            scheduleRenderStateRefresh()
        }
        .onDisappear {
            pendingNotificationRefresh?.cancel()
            renderRefreshTask?.cancel()
        }
    }

    private var profileID: UUID? {
        profile?.id
    }

    private var scopedEventsForProfile: [CareEvent] {
        events.filter { $0.matchesProfile(profileID) }
    }

    private var scopedRecordsForProfile: [SleepPredictionRecord] {
        records.filter { $0.matchesProfile(profileID) }
    }

    private func makeRenderState() -> ChildSleepSettingsRenderState {
        let scopedEvents = scopedEventsForProfile
        let scopedRecords = scopedRecordsForProfile
        let currentPrediction = scopedRecords.first(where: {
            $0.actualSleepEventID == nil
        })?.prediction
        let selectedProfileIsSleeping = scopedEvents.contains {
            $0.isSleepBlock && $0.isTimerRunning
        }
        let currentPressure = SleepPredictionEngine.sleepPressure(
            profile: profile,
            events: scopedEvents,
            records: scopedRecords,
            settings: settings
        )
        let notificationStatus = notificationManager.statusText(
            prediction: currentPrediction,
            profileID: profileID,
            settings: .current,
            isSleeping: selectedProfileIsSleeping
        )
        let sleepPressureStatus = NotificationManager.sleepPressureStatusText(
            pressure: currentPressure,
            enabled: sleepPressureAlertsEnabled,
            isSleeping: selectedProfileIsSleeping,
            authorizationStatus: notificationManager.authorizationStatus
        )
        let sleepPressurePreviewText: String
        if let pressure = currentPressure {
            if let score = pressure.score {
                sleepPressurePreviewText = "\(Int(score.rounded())) / 100 · \(pressure.confidenceLabel.displayName.lowercased()) confidence"
            } else {
                sleepPressurePreviewText = "No pressure score yet; Little Windows is learning rhythm."
            }
        } else {
            sleepPressurePreviewText = "Complete a sleep log to start learning pressure."
        }
        let notificationPreview: LittleWindowNotificationCopy
        if let currentPrediction {
            notificationPreview = NotificationManager.notificationCopy(
                for: currentPrediction,
                babyName: profile?.name ?? "Baby",
                leadMinutes: notificationLeadMinutes
            )
        } else {
            notificationPreview = LittleWindowNotificationCopy(
                title: "Nap window soon",
                body: "Baby's Little Window is estimated for 1:55-2:35 PM."
            )
        }
        return ChildSleepSettingsRenderState(
            currentPrediction: currentPrediction,
            currentPressure: currentPressure,
            selectedProfileIsSleeping: selectedProfileIsSleeping,
            notificationStatus: notificationStatus,
            sleepPressureStatus: sleepPressureStatus,
            sleepPressurePreviewText: sleepPressurePreviewText,
            notificationPreview: notificationPreview
        )
    }

    @MainActor
    private func refreshRenderState() async {
        await Task.yield()
        guard !Task.isCancelled else { return }
        cachedRenderState = makeRenderState()
    }

    private func scheduleRenderStateRefresh() {
        renderRefreshTask?.cancel()
        renderRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            cachedRenderState = makeRenderState()
        }
    }

    private var settings: PredictionSettings {
        PredictionSettings(
            feedAdjustmentEnabled: feedAdjustmentEnabled,
            nursingAdjustmentEnabled: nursingAdjustmentEnabled,
            bedtimePredictionEnabled: bedtimePredictionEnabled,
            customBaselineMinimum: customWakeMinimum > 0 ? customWakeMinimum : nil,
            customBaselineMaximum: customWakeMaximum > 0 ? customWakeMaximum : nil
        )
    }

    private func rescheduleNotification() async {
        await EventMutationService.refreshPrediction(
            profile: profile,
            events: scopedEventsForProfile,
            records: scopedRecordsForProfile,
            context: modelContext,
            settings: settings,
            notificationsEnabled: notificationsEnabled,
            notificationLeadMinutes: notificationLeadMinutes
        )
    }

    private func scheduleNotificationRefresh() {
        pendingNotificationRefresh?.cancel()
        pendingNotificationRefresh = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await rescheduleNotification()
        }
    }

    private var currentPrediction: SleepPrediction? {
        cachedRenderState.currentPrediction
    }

    private var notificationStatus: String {
        cachedRenderState.notificationStatus
    }

    private var currentPressure: SleepPressure? {
        cachedRenderState.currentPressure
    }

    private var selectedProfileIsSleeping: Bool {
        cachedRenderState.selectedProfileIsSleeping
    }

    private var sleepPressureStatus: String {
        cachedRenderState.sleepPressureStatus
    }

    private var sleepPressurePreviewText: String {
        cachedRenderState.sleepPressurePreviewText
    }

    private var notificationPreview: LittleWindowNotificationCopy {
        cachedRenderState.notificationPreview
    }

    private func enableLittleWindowAlerts() async {
        let status = await notificationManager.getAuthorizationStatus()
        let granted: Bool
        if status == .notDetermined {
            granted = await notificationManager.requestAuthorization()
        } else {
            granted = status == .authorized || status == .provisional || status == .ephemeral
        }
        guard granted else {
            notificationsEnabled = false
            showingPermissionDenied = true
            return
        }
        notificationsEnabled = true
        await rescheduleNotification()
        await refreshRenderState()
    }

    private func enableSleepPressureAlerts() async {
        let status = await notificationManager.getAuthorizationStatus()
        let granted: Bool
        if status == .notDetermined {
            granted = await notificationManager.requestAuthorization()
        } else {
            granted = status == .authorized || status == .provisional || status == .ephemeral
        }
        guard granted else {
            sleepPressureAlertsEnabled = false
            showingPermissionDenied = true
            return
        }
        sleepPressureAlertsEnabled = true
        scheduleNotificationRefresh()
        scheduleRenderStateRefresh()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }
}

private struct AppointmentSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appointments: [DoctorAppointment]
    @AppStorage("appointmentRemindersEnabled") private var appointmentRemindersEnabled = true
    @StateObject private var notificationManager = NotificationManager.shared

    let profile: CareProfile?

    init(profile: CareProfile?) {
        self.profile = profile

        if let profileID = profile?.id {
            _appointments = Query(
                FetchDescriptor<DoctorAppointment>(
                    predicate: #Predicate<DoctorAppointment> { appointment in
                        appointment.profileID == profileID
                    },
                    sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
                )
            )
        } else {
            _appointments = Query(
                FetchDescriptor<DoctorAppointment>(
                    sortBy: [SortDescriptor(\DoctorAppointment.startDate)]
                )
            )
        }
    }

    private var profileID: UUID? {
        profile?.id
    }

    private var selectedProfileAppointments: [DoctorAppointment] {
        appointments.filter { $0.matchesProfile(profileID) }
    }

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    AppointmentsListView()
                }
            } label: {
                LabeledContent {
                    Text("\(selectedProfileAppointments.count)")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Appointments and visits", systemImage: "stethoscope")
                }
            }
            Toggle("Appointment reminders", isOn: $appointmentRemindersEnabled)
                .onChange(of: appointmentRemindersEnabled) { _, enabled in
                    Task {
                        await SystemIntegrationReconciler.reconcile(context: modelContext)
                    }
                }
        } header: {
            Label("Appointments", systemImage: "calendar.badge.clock")
        } footer: {
            Text("Appointment reminders are separate from Little Window sleep alerts.")
        }
    }
}

private struct AppointmentSettingsNavigationSection: View {
    let profile: CareProfile?

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    AppointmentSettingsView(profile: profile)
                }
            } label: {
                Label("Appointments and reminders", systemImage: "stethoscope")
            }
        } header: {
            Label("Appointments", systemImage: "calendar.badge.clock")
        } footer: {
            Text("Appointment reminders are separate from Little Window sleep alerts.")
        }
    }
}

private struct AppointmentSettingsView: View {
    let profile: CareProfile?

    var body: some View {
        Form {
            AppointmentSettingsSection(profile: profile)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Appointments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MonthlyAgeGuideSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var ageGuideReadStates: [AgeGuideReadState]

    let profile: CareProfile?

    @AppStorage("monthlyAgeGuideNotificationsEnabled") private var monthlyAgeGuideNotificationsEnabled = false
    @AppStorage("monthlyAgeGuideNotificationTiming") private var monthlyAgeGuideNotificationTimingRawValue =
        MonthlyAgeGuideNotificationTiming.monthlyBirthday.rawValue
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingPermissionDenied = false

    init(profile: CareProfile?) {
        self.profile = profile

        if let profileID = profile?.id {
            _ageGuideReadStates = Query(
                FetchDescriptor<AgeGuideReadState>(
                    predicate: #Predicate<AgeGuideReadState> { state in
                        state.profileID == profileID
                    },
                    sortBy: [SortDescriptor(\AgeGuideReadState.updatedAt)]
                )
            )
        } else {
            _ageGuideReadStates = Query(
                FetchDescriptor<AgeGuideReadState>(
                    sortBy: [SortDescriptor(\AgeGuideReadState.updatedAt)]
                )
            )
        }
    }

    private var selectedProfileAgeGuideReadStates: [AgeGuideReadState] {
        ageGuideReadStates.filter { $0.matchesProfile(profile?.id) }
    }

    var body: some View {
        Section {
            Toggle(
                "Monthly guide notifications",
                isOn: Binding(
                    get: { monthlyAgeGuideNotificationsEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                let granted = await notificationManager.requestAuthorization()
                                if granted {
                                    monthlyAgeGuideNotificationsEnabled = true
                                    await rescheduleMonthlyAgeGuideNotification()
                                } else {
                                    monthlyAgeGuideNotificationsEnabled = false
                                    showingPermissionDenied = true
                                }
                            }
                        } else {
                            monthlyAgeGuideNotificationsEnabled = false
                            Task {
                                await notificationManager.cancelMonthlyAgeGuideNotifications()
                            }
                        }
                    }
                )
            )
            if monthlyAgeGuideNotificationsEnabled {
                Picker("Timing", selection: $monthlyAgeGuideNotificationTimingRawValue) {
                    ForEach(MonthlyAgeGuideNotificationTiming.allCases) { timing in
                        Text(timing.displayName).tag(timing.rawValue)
                    }
                }
                .onChange(of: monthlyAgeGuideNotificationTimingRawValue) { _, _ in
                    Task { await rescheduleMonthlyAgeGuideNotification() }
                }
            }
            NavigationLink {
                LazySettingsDestination {
                    AgeGuidesListView(
                        guides: AgeGuideService.shared.allAgeGuides(),
                        currentMonth: profile.map {
                            AgeGuideService.shared.ageMonth(for: $0)
                        },
                        readStates: selectedProfileAgeGuideReadStates
                    )
                }
            } label: {
                Label("Browse age guides", systemImage: "book.pages.fill")
            }
        } header: {
            Label("Monthly Age Guides", systemImage: "calendar.badge.clock")
        } footer: {
            Text("One gentle reminder per monthly age at most. Guides are parent education and memory prompts, not medical advice.")
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
            if UserDefaults.standard.object(forKey: "monthlyAgeGuideNotificationsEnabled") == nil,
               notificationManager.authorizationStatus == .authorized {
                monthlyAgeGuideNotificationsEnabled = true
                await rescheduleMonthlyAgeGuideNotification()
            }
        }
        .alert("Notifications are turned off", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                openNotificationSettings()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can allow Little Window Alerts in iOS Settings whenever you're ready.")
        }
    }

    private func rescheduleMonthlyAgeGuideNotification() async {
        guard let profile else { return }
        let timing = MonthlyAgeGuideNotificationTiming(
            rawValue: monthlyAgeGuideNotificationTimingRawValue
        ) ?? .monthlyBirthday
        await notificationManager.scheduleMonthlyAgeGuideNotification(
            profile: profile,
            readStates: selectedProfileAgeGuideReadStates,
            context: modelContext,
            timing: timing
        )
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }
}

private struct MonthlyAgeGuideSettingsNavigationSection: View {
    var body: some View {
        Section {
            NavigationLink(value: SettingsRoute.monthlyAgeGuides) {
                Label("Monthly guide notifications", systemImage: "book.pages.fill")
            }
        } header: {
            Label("Monthly Age Guides", systemImage: "calendar.badge.clock")
        } footer: {
            Text("One gentle reminder per monthly age at most. Guides are parent education and memory prompts, not medical advice.")
        }
    }
}

private struct MonthlyAgeGuideSettingsView: View {
    let profile: CareProfile?

    var body: some View {
        Form {
            MonthlyAgeGuideSettingsSection(profile: profile)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Monthly Guides")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsSupportAndPrivacySection: View {
    var body: some View {
        Section("Help & Legal") {
            NavigationLink {
                BundledLegalDocumentView(document: .support)
            } label: {
                Label("Support", systemImage: "questionmark.circle.fill")
            }
            NavigationLink {
                BundledLegalDocumentView(document: .privacyPolicy)
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }
        }
    }
}

private enum BundledLegalDocument {
    case support
    case privacyPolicy

    var resourceName: String {
        switch self {
        case .support: "SUPPORT"
        case .privacyPolicy: "PRIVACY"
        }
    }

    var navigationTitle: String {
        switch self {
        case .support: "Support"
        case .privacyPolicy: "Privacy Policy"
        }
    }
}

private struct BundledLegalDocumentView: View {
    let document: BundledLegalDocument
    private let blocks: [LegalMarkdownBlock]?

    init(document: BundledLegalDocument) {
        self.document = document
        blocks = LegalMarkdownParser.load(resourceName: document.resourceName)
    }

    var body: some View {
        Group {
            if let blocks {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(blocks) { block in
                            LegalMarkdownBlockView(block: block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Document Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This document could not be loaded from the app.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(document.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
    }
}

private struct LegalMarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int)
        case paragraph
        case bullet
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

private enum LegalMarkdownParser {
    static func load(resourceName: String, bundle: Bundle = .main) -> [LegalMarkdownBlock]? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parse(markdown)
    }

    static func parse(_ markdown: String) -> [LegalMarkdownBlock] {
        var blocks = [LegalMarkdownBlock]()
        var paragraphLines = [String]()

        func appendParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(LegalMarkdownBlock(
                kind: .paragraph,
                text: paragraphLines.joined(separator: " ")
            ))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                appendParagraph()
            } else if trimmed.hasPrefix("### ") {
                appendParagraph()
                blocks.append(LegalMarkdownBlock(
                    kind: .heading(level: 3),
                    text: String(trimmed.dropFirst(4))
                ))
            } else if trimmed.hasPrefix("## ") {
                appendParagraph()
                blocks.append(LegalMarkdownBlock(
                    kind: .heading(level: 2),
                    text: String(trimmed.dropFirst(3))
                ))
            } else if trimmed.hasPrefix("# ") {
                appendParagraph()
                blocks.append(LegalMarkdownBlock(
                    kind: .heading(level: 1),
                    text: String(trimmed.dropFirst(2))
                ))
            } else if trimmed.hasPrefix("- ") {
                appendParagraph()
                blocks.append(LegalMarkdownBlock(
                    kind: .bullet,
                    text: String(trimmed.dropFirst(2))
                ))
            } else if trimmed != "---" {
                paragraphLines.append(trimmed)
            }
        }

        appendParagraph()
        return blocks
    }
}

private struct LegalMarkdownBlockView: View {
    let block: LegalMarkdownBlock

    var body: some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.text))
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 0 : 8)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(block.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        default: .headline
        }
    }

    private func inlineMarkdown(_ value: String) -> AttributedString {
        let localLinksRemoved = value
            .replacingOccurrences(
                of: "[Little Windows Privacy Policy](PRIVACY.md)",
                with: "Little Windows Privacy Policy"
            )
            .replacingOccurrences(
                of: "[Little Windows Support](SUPPORT.md)",
                with: "Little Windows Support"
            )
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: localLinksRemoved, options: options))
            ?? AttributedString(localLinksRemoved)
    }
}

private struct SettingsBuildInfoFooter: View {
    private var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
    }

    private var buildChannel: String {
        #if DEBUG
        return "Debug"
        #elseif targetEnvironment(simulator)
        return "Simulator"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "TestFlight"
        }
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            return "Development"
        }
        return "App Store"
        #endif
    }

    var body: some View {
        Section {
            VStack(spacing: 4) {
                Text("Little Windows")
                    .font(.caption.weight(.semibold))
                Text("Version \(version) (\(build))")
                    .font(.caption2.monospacedDigit())
                Text("Build: \(buildChannel)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
}

private struct FoodReminderSettingsLauncher: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Household.createdAt) private var households: [Household]

    var body: some View {
        Group {
            if let household = households.first {
                FoodReminderSettingsDataView(household: household)
            } else {
                ProgressView("Preparing Food & Home")
                    .task {
                        FoodHomeBootstrapService.seedIfNeeded(context: modelContext)
                    }
            }
        }
    }
}

private struct FoodReminderSettingsDataView: View {
    let household: Household
    @Query private var reminders: [FoodReminder]
    @Query private var todoLists: [HomeTodoList]
    @Query private var shoppingLists: [ShoppingList]
    @Query private var mealPrepItems: [MealPrepItem]
    @Query private var returnRequests: [ReturnRequest]

    init(household: Household) {
        self.household = household
        let householdID = household.id
        _reminders = Query(FetchDescriptor<FoodReminder>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\FoodReminder.dateTime)]
        ))
        _todoLists = Query(FetchDescriptor<HomeTodoList>(
            predicate: #Predicate { $0.householdID == householdID && !$0.isArchived },
            sortBy: [SortDescriptor(\HomeTodoList.sortOrder)]
        ))
        _shoppingLists = Query(FetchDescriptor<ShoppingList>(
            predicate: #Predicate { $0.householdID == householdID && !$0.isArchived },
            sortBy: [SortDescriptor(\ShoppingList.sortOrder)]
        ))
        _mealPrepItems = Query(FetchDescriptor<MealPrepItem>(
            predicate: #Predicate { $0.householdID == householdID && !$0.isArchived },
            sortBy: [SortDescriptor(\MealPrepItem.updatedAt, order: .reverse)]
        ))
        _returnRequests = Query(FetchDescriptor<ReturnRequest>(
            predicate: #Predicate { $0.householdID == householdID && !$0.isArchived },
            sortBy: [SortDescriptor(\ReturnRequest.updatedAt, order: .reverse)]
        ))
    }

    var body: some View {
        FoodReminderSettingsView(
            household: household,
            reminders: reminders,
            todoLists: todoLists,
            shoppingLists: shoppingLists,
            mealPrepItems: mealPrepItems,
            returnRequests: returnRequests
        )
    }
}

private struct WatchSettingsSection: View {
    let profile: CareProfile?

    @State private var status = WatchConnectivityService.shared.statusSnapshot()

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    AppleWatchSettingsView()
                }
            } label: {
                LabeledContent {
                    Text(summary)
                        .foregroundStyle(summaryTint)
                } label: {
                    Label("Apple Watch", systemImage: "applewatch")
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            if let profile {
                Text("The Watch companion follows the selected profile, currently \(profile.name), and keeps working from its last received snapshot when the iPhone is not immediately reachable.")
            } else {
                Text("Add a profile before configuring Watch favorites.")
            }
        }
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(
            for: .watchConnectivityStatusDidChange
        )) { _ in
            refreshStatus()
        }
    }

    private var summary: String {
        guard status.isSupported else { return "Unavailable" }
        guard status.isPaired else { return "Not paired" }
        guard status.isWatchAppInstalled else { return "Not installed" }
        guard status.isActivated else { return "Connecting" }
        if status.isLatestStateConfirmed { return "Ready" }
        if status.lastStateQueuedAt != nil { return "Syncing" }
        return "Waiting for first sync"
    }

    private var summaryTint: Color {
        guard status.isSupported,
              status.isPaired,
              status.isWatchAppInstalled else {
            return .orange
        }
        return status.isLatestStateConfirmed ? .green : .secondary
    }

    private func refreshStatus() {
        status = WatchConnectivityService.shared.statusSnapshot()
    }
}

private struct AppleWatchSettingsView: View {
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @StateObject private var profileService = ProfileService.shared
    @State private var status = WatchConnectivityService.shared.statusSnapshot()
    @State private var refreshMessage: String?

    private var selectedProfile: CareProfile? {
        profileService.selectedProfile(in: profiles)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: statusSymbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(statusTint)
                        .frame(width: 44, height: 44)
                        .background(statusTint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent("Watch app", value: watchAppStatus)
                LabeledContent("State delivery", value: stateDeliveryStatus)
                LabeledContent("Last confirmed contact", value: lastContactText)
                LabeledContent("Connection", value: connectionText)

                Button {
                    sendLatestState()
                } label: {
                    Label("Send Latest State", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!canSendState)

                if let refreshMessage {
                    Text(refreshMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Background delivery is normal. A live connection usually appears only while Little Windows is open on the Watch.")
            }

            Section {
                LabeledContent("Current profile") {
                    Text(selectedProfile?.name ?? "None")
                        .foregroundStyle(.secondary)
                }

                if let selectedProfile {
                    NavigationLink {
                        WatchFavoritesSettingsView(profile: selectedProfile)
                    } label: {
                        LabeledContent {
                            Text(favoriteModeText(for: selectedProfile))
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Watch Favorites", systemImage: "star.square.on.square.fill")
                        }
                    }
                } else {
                    Label("Watch Favorites", systemImage: "star.square.on.square.fill")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("Choose up to six favorites for each profile, or let Smart Favorites adapt to recent care. Hidden care categories remain hidden on the Watch.")
            }

            Section("What syncs") {
                WatchSyncContentRow(
                    title: "Profiles and preferences",
                    detail: "Selected profile and hidden categories",
                    systemImage: "person.crop.circle"
                )
                WatchSyncContentRow(
                    title: "Actions and timers",
                    detail: "Favorites, all actions, and the active timer",
                    systemImage: "timer"
                )
                WatchSyncContentRow(
                    title: "Today at a glance",
                    detail: "Summary metrics and the next sleep window",
                    systemImage: "chart.bar.fill"
                )
            }

            Section {
                Label("Configured on Apple Watch", systemImage: "applewatch.watchface")
                Text("Add Little Windows complications while editing a Watch face, or add its widgets to the Smart Stack. The phone sends their data, but watchOS controls where they appear.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Complications and widgets")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(
            for: .watchConnectivityStatusDidChange
        )) { _ in
            refreshStatus()
        }
    }

    private var canSendState: Bool {
        status.isSupported
            && status.isActivated
            && status.isPaired
            && status.isWatchAppInstalled
            && selectedProfile != nil
    }

    private var statusTitle: String {
        guard status.isSupported else { return "Watch unavailable" }
        guard status.isPaired else { return "No paired Watch" }
        guard status.isWatchAppInstalled else { return "Install the Watch app" }
        guard status.isActivated else { return "Preparing Watch sync" }
        if status.isLatestStateConfirmed { return "Ready" }
        if status.lastConfirmedContactAt == nil { return "Open the Watch app once" }
        return "Update queued"
    }

    private var statusDetail: String {
        guard status.isSupported else {
            return "Watch connectivity is not available on this device."
        }
        guard status.isPaired else {
            return "Pair an Apple Watch with this iPhone to use the companion."
        }
        guard status.isWatchAppInstalled else {
            return "Install Little Windows from the Watch app on this iPhone."
        }
        guard status.isActivated else {
            return "The iPhone is preparing the background connection."
        }
        if status.isLatestStateConfirmed {
            return "The latest Little Windows state was received by your Watch."
        }
        if status.lastConfirmedContactAt == nil {
            return "Open Little Windows on the Watch to complete the first confirmed sync."
        }
        return "The latest state is queued for background delivery."
    }

    private var statusSymbol: String {
        guard status.isSupported,
              status.isPaired,
              status.isWatchAppInstalled else {
            return "applewatch.slash"
        }
        if status.isLatestStateConfirmed { return "checkmark.circle.fill" }
        return "arrow.triangle.2.circlepath"
    }

    private var statusTint: Color {
        guard status.isSupported,
              status.isPaired,
              status.isWatchAppInstalled else {
            return .orange
        }
        return status.isLatestStateConfirmed ? .green : AppTheme.accent
    }

    private var watchAppStatus: String {
        guard status.isSupported else { return "Unavailable" }
        guard status.isPaired else { return "No paired Watch" }
        return status.isWatchAppInstalled ? "Installed" : "Not installed"
    }

    private var stateDeliveryStatus: String {
        guard status.isWatchAppInstalled else { return "—" }
        if status.isLatestStateConfirmed { return "Up to date" }
        if status.lastStateQueuedAt != nil { return "Update queued" }
        return "Waiting"
    }

    private var lastContactText: String {
        guard let date = status.lastConfirmedContactAt else { return "Not yet" }
        return date.formatted(.relative(presentation: .numeric))
    }

    private var connectionText: String {
        guard status.isWatchAppInstalled else { return "—" }
        return status.isReachable ? "Connected now" : "Background delivery"
    }

    private func favoriteModeText(for profile: CareProfile) -> String {
        guard let ids = WatchFavoritePreferenceStore.customActionIDs(
            profileID: profile.id
        ) else {
            return "Smart"
        }
        return "\(ids.count) custom"
    }

    private func sendLatestState() {
        let queued = WatchConnectivityService.shared.publishCurrentState(force: true)
        refreshMessage = queued
            ? "Latest profile, favorites, timer, and summary queued for delivery."
            : "The Watch is not ready for delivery yet."
        refreshStatus()
    }

    private func refreshStatus() {
        status = WatchConnectivityService.shared.statusSnapshot()
    }
}

private struct WatchSyncContentRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

private struct WatchFavoritesSettingsView: View {
    let profile: CareProfile

    @State private var usesSmartFavorites: Bool
    @State private var selectedActionIDs: [String]
    @State private var smartQuickActions: [QuickLogActionSnapshot] = []

    init(profile: CareProfile) {
        self.profile = profile
        let customIDs = WatchFavoritePreferenceStore.customActionIDs(
            profileID: profile.id
        )
        _usesSmartFavorites = State(initialValue: customIDs == nil)
        _selectedActionIDs = State(initialValue: customIDs ?? [])
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Profile", value: profile.name)
                Picker("Favorite mode", selection: Binding(
                    get: { usesSmartFavorites },
                    set: setUsesSmartFavorites
                )) {
                    Text("Smart").tag(true)
                    Text("Custom").tag(false)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(usesSmartFavorites
                    ? "Smart Favorites use recent care activity and the iPhone's pinned quick actions to keep the most useful choices first."
                    : "Custom Favorites keep the order you choose for this profile until you switch back to Smart.")
            }

            if usesSmartFavorites {
                Section("Current smart order") {
                    ForEach(Array(smartActions.enumerated()), id: \.element.id) { index, action in
                        actionRow(action, position: index + 1)
                    }
                }
            } else {
                Section {
                    ForEach(Array(selectedActions.enumerated()), id: \.element.id) { index, action in
                        HStack(spacing: 10) {
                            actionRow(action, position: index + 1)
                            Spacer(minLength: 8)
                            favoriteOptionsMenu(for: action, at: index)
                        }
                    }
                } header: {
                    Text("Shown on Watch · \(selectedActions.count)/\(WatchFavoritePreferenceStore.maximumFavoriteCount)")
                        .accessibilityIdentifier("watch.favorites.custom-header")
                } footer: {
                    Text("Use each action's menu to reorder or remove it. At least one favorite is kept; every supported action remains available from All Actions on the Watch.")
                }

                if !unselectedActions.isEmpty {
                    Section("Add an action") {
                        ForEach(unselectedActions) { action in
                            Button {
                                addAction(action)
                            } label: {
                                HStack {
                                    actionLabel(action)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("watch.favorite.add.\(action.id)")
                            .disabled(
                                selectedActionIDs.count
                                    >= WatchFavoritePreferenceStore.maximumFavoriteCount
                            )
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Watch Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reconcileSelection)
        .task {
            smartQuickActions = await Task.detached(priority: .utility) {
                WidgetSnapshotService.read().resolvedQuickActions
            }.value
        }
    }

    private var availableActions: [WatchActionSnapshot] {
        let hiddenRawValues = Set(CareCategoryPreferenceStore.hiddenTypes(
            profileID: profile.id
        ).map(\.rawValue))
        return WatchActionCatalog.actions(
            profileTypeRawValue: profile.profileType.rawValue
        ).filter { !hiddenRawValues.contains($0.categoryRawValue) }
    }

    private var selectedActions: [WatchActionSnapshot] {
        let actionsByID = Dictionary(
            uniqueKeysWithValues: availableActions.map { ($0.id, $0) }
        )
        return selectedActionIDs.compactMap { actionsByID[$0] }
    }

    private var unselectedActions: [WatchActionSnapshot] {
        let selected = Set(selectedActionIDs)
        return availableActions.filter { !selected.contains($0.id) }
    }

    private var smartActions: [WatchActionSnapshot] {
        WatchStateFactory.smartFavorites(
            from: smartQuickActions,
            allActions: availableActions
        )
    }

    @ViewBuilder
    private func actionRow(_ action: WatchActionSnapshot, position: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            actionLabel(action)
        }
    }

    private func actionLabel(_ action: WatchActionSnapshot) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: action.systemImage)
                .foregroundStyle(watchActionTint(action.tintName))
        }
    }

    private func favoriteOptionsMenu(
        for action: WatchActionSnapshot,
        at index: Int
    ) -> some View {
        Menu {
            Button("Move Up", systemImage: "arrow.up") {
                moveAction(at: index, offset: -1)
            }
            .disabled(index == 0)

            Button("Move Down", systemImage: "arrow.down") {
                moveAction(at: index, offset: 1)
            }
            .disabled(index >= selectedActionIDs.count - 1)

            Divider()

            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                removeAction(at: index)
            }
            .disabled(selectedActionIDs.count <= 1)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Favorite options for \(action.title)")
        .accessibilityIdentifier("watch.favorite.options.\(action.id)")
    }

    private func setUsesSmartFavorites(_ usesSmart: Bool) {
        usesSmartFavorites = usesSmart
        if usesSmart {
            WatchFavoritePreferenceStore.useSmartFavorites(profileID: profile.id)
        } else {
            let seed = smartActions.isEmpty
                ? Array(availableActions.prefix(
                    WatchFavoritePreferenceStore.maximumFavoriteCount
                ))
                : smartActions
            selectedActionIDs = seed.map(\.id)
            saveCustomSelection()
            return
        }
        publishFavorites()
    }

    private func addAction(_ action: WatchActionSnapshot) {
        guard selectedActionIDs.count < WatchFavoritePreferenceStore.maximumFavoriteCount,
              !selectedActionIDs.contains(action.id) else {
            return
        }
        selectedActionIDs.append(action.id)
        saveCustomSelection()
    }

    private func moveAction(at index: Int, offset: Int) {
        let destination = index + offset
        guard selectedActionIDs.indices.contains(index),
              selectedActionIDs.indices.contains(destination) else {
            return
        }
        selectedActionIDs.swapAt(index, destination)
        saveCustomSelection()
    }

    private func removeAction(at index: Int) {
        guard selectedActionIDs.count > 1,
              selectedActionIDs.indices.contains(index) else {
            return
        }
        selectedActionIDs.remove(at: index)
        saveCustomSelection()
    }

    private func reconcileSelection() {
        guard !usesSmartFavorites else { return }
        let validIDs = Set(availableActions.map(\.id))
        selectedActionIDs = selectedActionIDs.filter { validIDs.contains($0) }
        if selectedActionIDs.isEmpty {
            selectedActionIDs = smartActions.map(\.id)
        }
        saveCustomSelection()
    }

    private func saveCustomSelection() {
        WatchFavoritePreferenceStore.setCustomActionIDs(
            selectedActionIDs,
            profileID: profile.id
        )
        publishFavorites()
    }

    private func publishFavorites() {
        WatchConnectivityService.shared.publishCurrentState(force: true)
    }

    private func watchActionTint(_ name: String) -> Color {
        switch name {
        case "cyan": .cyan
        case "green": .green
        case "indigo": .indigo
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        default: AppTheme.accent
        }
    }
}

private struct SyncSettingsSection: View {
    let hasActiveCareProfile: Bool

    @AppStorage(PersistenceService.iCloudSyncEnabledKey) private var isICloudSyncEnabled = true
    @AppStorage(PersistenceService.familySyncModeKey) private var syncModeRawValue = FamilySyncMode.privateICloudSync.rawValue
    @AppStorage(CloudKitSharingService.inactiveReasonKey) private var inactiveReasonRawValue = ""

    private var syncMode: FamilySyncMode {
        FamilySyncMode(rawValue: syncModeRawValue)
            ?? (isICloudSyncEnabled ? .privateICloudSync : .localOnly)
    }

    var body: some View {
        Section {
            NavigationLink {
                LazySettingsDestination {
                    ICloudSyncSettingsView()
                }
            } label: {
                LabeledContent {
                    Text(isICloudSyncEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("iCloud and sharing", systemImage: "icloud")
                }
            }
            NavigationLink {
                LazySettingsDestination {
                    FamilySyncSettingsView()
                }
            } label: {
                LabeledContent {
                    Text(inactiveReasonRawValue.isEmpty
                        ? (syncMode == .sharedFamilySync ? "On" : "Off")
                        : "Review")
                    .foregroundStyle(
                        inactiveReasonRawValue.isEmpty ? Color.secondary : Color.orange
                    )
                } label: {
                    Label("Family Sync", systemImage: "person.2.badge.gearshape.fill")
                }
            }
        } header: {
            Text("Sync")
        } footer: {
            if hasActiveCareProfile {
                Text("Private iCloud Sync covers the same Apple Account. Family Sync shares Little Windows data with accepted iCloud caregivers across Apple Accounts.")
            } else {
                Text("Private iCloud Sync keeps your household data available on devices using the same Apple Account. Family Sync shares it with accepted people across Apple Accounts.")
            }
        }
    }
}

private struct ProfileSettingsSection: View {
    @Bindable var profile: CareProfile
    @State private var draftName = ""
    @State private var draftNotes = ""
    @State private var pendingSave: Task<Void, Never>?

    init(profile: CareProfile) {
        self.profile = profile
        _draftName = State(initialValue: profile.name)
        _draftNotes = State(initialValue: profile.notes)
    }

    var body: some View {
        Section {
            HStack(spacing: 14) {
                ProfileAvatarView(profile: profile, size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(draftName.isEmpty ? profile.name : draftName)
                        .font(.headline)
                    Text(profile.ageDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            TextField("Name", text: $draftName)
                .onSubmit(saveNow)
                .onChange(of: draftName) { _, _ in scheduleSave() }
            if let birthDate = profile.birthDate {
                DatePicker(
                    profile.profileType == .adult ? "Birthdate" : "Birthday",
                    selection: Binding(
                        get: { birthDate },
                        set: {
                            profile.birthDate = $0
                            profile.updatedAt = Date()
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
            }
            if profile.profileType != .adult {
                Picker("Sex for growth charts", selection: Binding(
                    get: { profile.sex },
                    set: {
                        profile.sex = $0
                        profile.updatedAt = Date()
                    }
                )) {
                    ForEach(ProfileSex.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
            }
            TextField("Notes", text: $draftNotes, axis: .vertical)
                .onSubmit(saveNow)
                .onChange(of: draftNotes) { _, _ in scheduleSave() }
        } header: {
            Label("Care profile", systemImage: profile.profileType.systemImage)
        }
        .onAppear(perform: syncDraftsFromProfile)
        .onChange(of: profile.id) { _, _ in syncDraftsFromProfile() }
        .onDisappear(perform: saveNow)
    }

    private func syncDraftsFromProfile() {
        pendingSave?.cancel()
        draftName = profile.name
        draftNotes = profile.notes
    }

    private func scheduleSave() {
        let name = draftName
        let notes = draftNotes
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            save(name: name, notes: notes)
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        save(name: draftName, notes: draftNotes)
    }

    private func save(name: String, notes: String) {
        guard profile.name != name || profile.notes != notes else { return }
        profile.name = name
        profile.notes = notes
        profile.updatedAt = Date()
    }
}

struct CaregiverNameFields: View {
    let detail: String
    var clearsFamilySyncPrompt = false
    var showsFallback = true

    @State private var currentName: String
    @State private var primaryName: String
    @State private var pendingSave: Task<Void, Never>?

    init(
        detail: String,
        clearsFamilySyncPrompt: Bool = false,
        showsFallback: Bool = true
    ) {
        self.detail = detail
        self.clearsFamilySyncPrompt = clearsFamilySyncPrompt
        self.showsFallback = showsFallback
        _currentName = State(
            initialValue: UserDefaults.standard.string(
                forKey: CaregiverIdentityService.currentCaregiverNameKey
            ) ?? ""
        )
        _primaryName = State(
            initialValue: UserDefaults.standard.string(
                forKey: CaregiverIdentityService.primaryCaregiverNameKey
            ) ?? "Caregiver 1"
        )
    }

    var body: some View {
        Group {
            LabeledContent("Name for new entries") {
                TextField("Your name", text: $currentName)
                    .textContentType(.name)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(saveNow)
                    .onChange(of: currentName) { _, _ in scheduleSave() }
            }
            LabeledContent("Share name") {
                TextField("Optional", text: $primaryName)
                    .textContentType(.name)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(saveNow)
                    .onChange(of: primaryName) { _, _ in scheduleSave() }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if showsFallback && currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Using \(fallbackName) until you enter a name here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: saveNow)
    }

    private var fallbackName: String {
        CaregiverIdentityService.currentCaregiverName(
            currentName: "",
            primaryName: primaryName,
            fallback: "Caregiver"
        )
    }

    private func scheduleSave() {
        let currentName = currentName
        let primaryName = primaryName
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            save(currentName: currentName, primaryName: primaryName)
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        save(currentName: currentName, primaryName: primaryName)
    }

    private func save(currentName: String, primaryName: String) {
        let defaults = UserDefaults.standard
        let previousEffectiveName = CaregiverIdentityService.currentCaregiverName(defaults: defaults)
        CaregiverIdentityService.storeIdentity(
            currentName: currentName,
            primaryName: primaryName,
            defaults: defaults
        )
        let updatedEffectiveName = CaregiverIdentityService.currentCaregiverName(defaults: defaults)
        if !CaregiverIdentityService.namesMatch(previousEffectiveName, updatedEffectiveName) {
            SystemIntegrationReconciler.requestReconciliation()
        }
        if clearsFamilySyncPrompt,
           !currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(false, forKey: CaregiverIdentityService.needsLogNamePromptKey)
        }
    }
}

private struct WakeWindowTuningView: View {
    @Binding var minimum: Double
    @Binding var maximum: Double

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortest") {
                    TextField("Minutes", value: $minimum, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Longest") {
                    TextField("Minutes", value: $maximum, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Use age-based defaults") {
                    minimum = 0
                    maximum = 0
                }
            } header: {
                Text("Fallback wake-window range")
            } footer: {
                Text("Used when there is not enough personal sleep history yet. Set both fields to 0 to use the age-based default range.")
            }
        }
        .navigationTitle("Wake Windows")
        .navigationBarTitleDisplayMode(.inline)
    }
}
