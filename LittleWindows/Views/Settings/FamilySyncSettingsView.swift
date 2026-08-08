import CloudKit
import SwiftData
import SwiftUI
import UIKit

struct FamilySyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CareProfile.createdAt) private var profiles: [CareProfile]
    @StateObject private var viewModel = FamilySyncViewModel()
    @AppStorage("familySyncActivityNotificationsEnabled")
    private var activityNotificationsEnabled = true
    @AppStorage("familySyncHomeTodoNotificationsEnabled")
    private var homeTodoNotificationsEnabled = true
    @AppStorage("familySyncTripNotificationsEnabled")
    private var tripNotificationsEnabled = true
    @State private var confirmLeave = false
    @State private var confirmStopSharing = false
    @State private var confirmDeleteInactiveData = false
    @State private var deleteLocalDataOnLeave = false
    @State private var isConfirmingLeave = false

    private var hasActiveCareProfile: Bool {
        profiles.contains { !$0.isArchived }
    }

    private var sharedProfileCount: Int {
        profiles.filter { !$0.isArchived && $0.sharingScope == .family }.count
    }

    private var privateProfileCount: Int {
        profiles.filter { !$0.isArchived && $0.sharingScope == .privateOnly }.count
    }

    var body: some View {
        List {
            Section("Current mode") {
                LabeledContent("Mode", value: viewModel.state.syncMode.displayName)
                LabeledContent("Status", value: viewModel.state.status.displayName)
                LabeledContent("iCloud Sync", value: viewModel.availability.title)
                LabeledContent("Role", value: viewModel.state.role.displayName)
                LabeledContent("Owner", value: viewModel.state.ownerDescription)
                if viewModel.state.role == .owner {
                    LabeledContent(
                        hasActiveCareProfile ? "Accepted caregivers" : "Accepted people",
                        value: "\(viewModel.state.participantCount)"
                    )
                } else {
                    LabeledContent("Participant", value: viewModel.state.participantDescription)
                }
                LabeledContent("Last sync", value: lastSyncText)
            }
            .labeledContentStyle(AdaptiveLabeledContentStyle())

            Section("How family sync works") {
                Text("Family Sync uses an iCloud shared record between Apple Accounts. It is separate from Apple Family Sharing membership.")
                    .foregroundStyle(.secondary)
                Text(hasActiveCareProfile
                    ? "Home and Food data are shared with accepted caregivers. Only care profiles you explicitly opt in—and their care records—are included."
                    : "Home, Food, trips, returns, reminders, and other household data are shared with accepted people. New care profiles stay private until you opt them in.")
                    .foregroundStyle(.secondary)
                if hasActiveCareProfile {
                    LabeledContent("Shared care profiles", value: "\(sharedProfileCount)")
                    LabeledContent("Private care profiles", value: "\(privateProfileCount)")
                    Text("Change a profile’s setting under Settings → Care Profiles. Private profile data stays out of the family share and remains in this device’s local app data and backups while Family Sync is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Private iCloud Sync remains available for devices signed into the same Apple Account.")
                    .foregroundStyle(.secondary)
            }

            if let inactiveReason = viewModel.state.inactiveReason {
                Section("Access ended") {
                    Label(inactiveReason.title, systemImage: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.orange)
                    Text(inactiveReason.detail)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await viewModel.resolveInactiveShare(
                                context: modelContext,
                                deleteLocalData: false
                            )
                        }
                    } label: {
                        Label("Keep Local Copy", systemImage: "internaldrive")
                    }
                    .disabled(familyActionIsRunning)

                    Button("Delete Shared Data from This Device", role: .destructive) {
                        confirmDeleteInactiveData = true
                    }
                    .disabled(familyActionIsRunning)
                }
            }

            Section("Family sharing") {
                if let operationStatusText {
                    Label(operationStatusText, systemImage: "hourglass")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if viewModel.state.canResumeShare {
                    Button {
                        Task { await viewModel.resumeSharing(context: modelContext) }
                    } label: {
                        Label(
                            viewModel.activeOperation == .resume
                                ? "Turning On Family Sync"
                                : "Turn On Family Sync",
                            systemImage: viewModel.activeOperation == .resume
                                ? "hourglass"
                                : "person.2.badge.gearshape.fill"
                        )
                    }
                    .disabled(familyActionIsRunning)
                }

                if viewModel.state.canCreateShare {
                    Button {
                        Task { await viewModel.startSharing(context: modelContext) }
                    } label: {
                        Label(
                            viewModel.activeOperation == .create
                                ? "Creating Family Share"
                                : "Create Family Share",
                            systemImage: viewModel.activeOperation == .create
                                ? "hourglass"
                                : "person.crop.circle.badge.plus"
                        )
                    }
                    .disabled(familyActionIsRunning)
                }

                if viewModel.state.canManageShare {
                    Button {
                        Task { await viewModel.manageSharing() }
                    } label: {
                        Label(
                            viewModel.activeOperation == .manage
                                ? (hasActiveCareProfile ? "Opening Caregivers" : "Opening People")
                                : (hasActiveCareProfile ? "Manage Caregivers" : "Manage People"),
                            systemImage: viewModel.activeOperation == .manage
                                ? "hourglass"
                                : "person.2"
                        )
                    }
                    .disabled(familyActionIsRunning)
                }

                if viewModel.state.canSyncNow {
                    Button {
                        Task { await viewModel.syncNow(context: modelContext) }
                    } label: {
                        if viewModel.isSyncing {
                            Label("Syncing Family Data", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Upload and Download Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(familyActionIsRunning)

                    if viewModel.isSyncing {
                        Label("Checking the shared iCloud record for newer changes and uploading local edits.", systemImage: "icloud")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let message = viewModel.syncStatusMessage {
                        Label(message, systemImage: "checkmark.icloud")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(hasActiveCareProfile
                            ? "Manually checks the shared iCloud family record, downloads newer caregiver changes, and uploads local edits from this device."
                            : "Manually checks the shared iCloud family record, downloads newer household changes, and uploads local edits from this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.state.pendingUploadCount > 0 {
                    Label("Local changes are waiting to upload.", systemImage: "icloud.and.arrow.up")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if viewModel.state.canLeaveShare {
                    Button(role: .destructive) {
                        confirmLeave = true
                    } label: {
                        Label(
                            leaveActionIsRunning
                                ? leaveProgressTitle
                                : leaveButtonTitle,
                            systemImage: leaveActionIsRunning
                                ? "hourglass"
                                : "person.crop.circle.badge.minus"
                        )
                    }
                    .disabled(familyActionIsRunning)

                    if viewModel.state.role == .owner {
                        Button("Stop Sharing for Everyone", role: .destructive) {
                            confirmStopSharing = true
                        }
                        .disabled(familyActionIsRunning)
                    }
                }

                if viewModel.state.status == .localOnly {
                    Text("Turn on iCloud Sync before creating or accepting a family share.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Your name") {
                CaregiverNameFields(
                    detail: hasActiveCareProfile
                        ? "Name on this device appears on new care entries you log here. Family Sync share name labels the shared family space; most people can keep both names the same."
                        : "Name on this device appears on household assignments and activity. Family Sync share name labels the shared household space; most people can keep both names the same.",
                    clearsFamilySyncPrompt: true
                )
            }

            if viewModel.state.syncMode == .sharedFamilySync {
                Section("Notifications") {
                    Toggle(
                        "Shared activity alerts",
                        isOn: $activityNotificationsEnabled
                    )
                    .onChange(of: activityNotificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = await NotificationManager.shared.requestAuthorization()
                        }
                    }
                    Text(hasActiveCareProfile
                        ? "Show alerts when another caregiver's synced changes arrive on this device."
                        : "Show alerts when another person's synced household changes arrive on this device.")
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Home to-do list updates",
                        isOn: $homeTodoNotificationsEnabled
                    )
                    .disabled(!activityNotificationsEnabled)
                    .onChange(of: homeTodoNotificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = await NotificationManager.shared.requestAuthorization()
                        }
                    }
                    Text(hasActiveCareProfile
                        ? "Alert when another caregiver adds, completes, reopens, or edits Home to-do items."
                        : "Alert when another person adds, completes, reopens, or edits Home to-do items.")
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Trip packing updates",
                        isOn: $tripNotificationsEnabled
                    )
                    .disabled(!activityNotificationsEnabled)
                    .onChange(of: tripNotificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = await NotificationManager.shared.requestAuthorization()
                        }
                    }
                    Text("Alert for meaningful shared trip changes without notifying for every packed item.")
                        .foregroundStyle(.secondary)
                }
            }

            if let message = viewModel.state.lastAcceptanceMessage {
                Section("Invite status") {
                    Label(message, systemImage: inviteStatusImage(for: message))
                        .foregroundStyle(inviteStatusColor(for: message))
                }
            }

            if viewModel.state.canLeaveShare {
                Section("Leaving") {
                    Toggle("Delete local shared data when disconnecting", isOn: $deleteLocalDataOnLeave)
                    Text(leavingDataExplanation)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = viewModel.state.lastErrorMessage {
                Section("Attention") {
                    Text(message)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Family Sync")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh(force: true)
        }
        .task {
            await viewModel.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: CloudKitSharingService.acceptanceStatusDidChangeNotification
            )
        ) { _ in
            Task { await viewModel.refresh(force: true) }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: CloudKitSharingService.shareStateDidChangeNotification
            )
        ) { _ in
            Task { await viewModel.refresh(force: true) }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.presentedShare != nil },
                set: { if !$0 { viewModel.presentedShare = nil } }
            )
        ) {
            if let share = viewModel.presentedShare {
                CloudSharingControllerView(share: share)
            }
        }
        .confirmationDialog(
            leaveConfirmationTitle,
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button(leaveButtonTitle, role: .destructive) {
                isConfirmingLeave = true
                confirmLeave = false
                Task {
                    await viewModel.leaveShare(
                        context: modelContext,
                        deleteLocalData: deleteLocalDataOnLeave
                    )
                    isConfirmingLeave = false
                }
            }
            Button("Cancel", role: .cancel) {
                isConfirmingLeave = false
            }
        } message: {
            Text(leaveConfirmationMessage)
        }
        .confirmationDialog(
            "Stop sharing for everyone?",
            isPresented: $confirmStopSharing,
            titleVisibility: .visible
        ) {
            Button("Stop Sharing for Everyone", role: .destructive) {
                Task { await viewModel.stopSharingForEveryone() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every caregiver will lose access to this family share. Their already-downloaded data will remain on their devices until they choose to delete it.")
        }
        .confirmationDialog(
            "Delete this device's shared data?",
            isPresented: $confirmDeleteInactiveData,
            titleVisibility: .visible
        ) {
            Button("Delete from This Device", role: .destructive) {
                Task {
                    await viewModel.resolveInactiveShare(
                        context: modelContext,
                        deleteLocalData: true
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the downloaded Little Windows data from this device. It does not affect the former owner's data or other caregivers' local copies.")
        }
    }

    private var lastSyncText: String {
        guard let lastSyncAt = viewModel.state.lastSyncAt else { return "Never" }
        return lastSyncAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var familyActionIsRunning: Bool {
        viewModel.activeOperation != nil || isConfirmingLeave
    }

    private var leaveActionIsRunning: Bool {
        viewModel.activeOperation == .leave || isConfirmingLeave
    }

    private var leaveButtonTitle: String {
        viewModel.state.role == .owner
            ? "Turn Off on This Device"
            : "Leave Family Sync"
    }

    private var leaveProgressTitle: String {
        viewModel.state.role == .owner
            ? "Turning Off on This Device"
            : "Leaving Family Sync"
    }

    private var leaveConfirmationTitle: String {
        viewModel.state.role == .owner
            ? "Turn off on this device?"
            : "Leave Family Sync?"
    }

    private var leaveConfirmationMessage: String {
        if viewModel.state.role == .owner {
            return "This device will stop syncing. The iCloud family share and every other caregiver's access will stay active."
        }
        return "This Apple Account will leave the share and this device will stop syncing. Other caregivers will keep access."
    }

    private var leavingDataExplanation: String {
        let effect = viewModel.state.role == .owner
            ? "Turning off Family Sync here does not stop the share for other caregivers."
            : "Leaving removes this Apple Account from the share but does not stop sharing for other caregivers."
        return "Keeping local data leaves this device with a private copy. Deleting local data removes the downloaded Little Windows data from this device only. \(effect)"
    }

    private var operationStatusText: String? {
        if isConfirmingLeave {
            return viewModel.state.role == .owner
                ? "Turning off Family Sync on this device..."
                : FamilySyncOperation.leave.statusText
        }
        if viewModel.activeOperation == .create,
           let shareCreationProgress = viewModel.shareCreationProgress {
            return shareCreationProgress.statusText
        }
        return viewModel.activeOperation?.statusText
    }

    private func inviteStatusImage(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("failed") {
            return "exclamationmark.triangle"
        }
        if message.localizedCaseInsensitiveContains("accepted") {
            return "checkmark.icloud"
        }
        return "icloud.and.arrow.down"
    }

    private func inviteStatusColor(for message: String) -> Color {
        if message.localizedCaseInsensitiveContains("failed") {
            return .orange
        }
        if message.localizedCaseInsensitiveContains("accepted") {
            return .secondary
        }
        return .secondary
    }
}

private struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: share,
            container: CKContainer(identifier: PersistenceService.iCloudContainerIdentifier)
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            Task { @MainActor in
                CloudKitSharingService.shared.handleShareSheetSaveFailed(error)
            }
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            CloudKitSharingService.shared.shareTitle
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            CloudKitSharingService.shareIconData
        }

        func itemType(for csc: UICloudSharingController) -> String? {
            "app.littlewindows.family-sync"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in
                CloudKitSharingService.shared.handleShareSheetDidSave()
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                await CloudKitSharingService.shared.handleOwnerStoppedSharing()
            }
        }
    }
}
